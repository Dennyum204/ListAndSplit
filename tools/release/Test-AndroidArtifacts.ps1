[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Apk,
    [Parameter(Mandatory)][string]$Aab,
    [Parameter(Mandatory)][string]$Package,
    [Parameter(Mandatory)][string]$VersionName,
    [Parameter(Mandatory)][int]$VersionCode,
    [switch]$PrivateBeta
)
$ErrorActionPreference = 'Stop'
$expectedSigner = (Get-Content (Join-Path $PSScriptRoot 'release-signer.sha256') -Raw).Trim()
if ($PrivateBeta) {
    if ($Package -ne 'com.ferbatech.listandsplit.dev') { throw 'Private beta verification only permits the separate Dev package.' }
    # Preserve updates to the existing private Dev installation. Never use this
    # historical debug certificate to approve the protected Production package.
    $expectedSigner = (Get-Content (Join-Path $PSScriptRoot 'private-beta-signer.sha256') -Raw).Trim()
}
$buildTools = Join-Path $env:ANDROID_HOME 'build-tools/36.0.0'
$certificate = (& "$buildTools/apksigner.bat" verify --print-certs $Apk) -join "`n"
if ($LASTEXITCODE -ne 0 -or $certificate -notmatch 'Signer #1 certificate SHA-256 digest: ([a-f0-9]+)' -or $Matches[1] -ne $expectedSigner -or (!$PrivateBeta -and $certificate -match 'CN=Android Debug')) { throw 'APK signing identity verification failed.' }
$badging = (& "$buildTools/aapt.exe" dump badging $Apk) -join "`n"
if ($LASTEXITCODE -ne 0 -or $badging -notmatch "package: name='$([regex]::Escape($Package))' versionCode='$VersionCode' versionName='$([regex]::Escape($VersionName))'" -or $badging -match 'application-debuggable' -or $badging -notmatch "sdkVersion:'24'" -or $badging -notmatch "targetSdkVersion:'36'") { throw 'Package, version, SDK or release-mode verification failed.' }
$permissions = @([regex]::Matches($badging, "uses-permission: name='([^']+)'") | ForEach-Object { $_.Groups[1].Value })
$allowedPermissions = @('android.permission.INTERNET',"$Package.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION",
    'android.permission.POST_NOTIFICATIONS','android.permission.ACCESS_NETWORK_STATE',
    'android.permission.WAKE_LOCK','com.google.android.c2dm.permission.RECEIVE')
if (@($permissions | Where-Object { $_ -notin $allowedPermissions }).Count) { throw 'Unexpected permission: review the merged manifest.' }
$manifest = (& "$buildTools/aapt.exe" dump xmltree $Apk AndroidManifest.xml) -join "`n"
if ($LASTEXITCODE -ne 0 -or $manifest -notmatch 'android:allowBackup.*0x0' -or $manifest -notmatch 'android:usesCleartextTraffic.*0x0' -or $manifest -notmatch "android:scheme.*`"$([regex]::Escape($Package))`"") { throw 'Backup, TLS or authentication callback verification failed.' }
& "$buildTools/zipalign.exe" -c -P 16 4 $Apk | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'APK 16 KB ZIP alignment failed.' }
$jar = (& jarsigner -verify $Aab 2>&1) -join "`n"
if ($LASTEXITCODE -ne 0 -or $jar -notmatch 'jar verified') { throw 'AAB signature verification failed.' }
$bundleCertificate = (& keytool -printcert -jarfile $Aab) -join "`n"
if ($LASTEXITCODE -ne 0 -or $bundleCertificate -notmatch 'SHA256: ([A-Fa-f0-9:]+)' -or $Matches[1].Replace(':','').ToLowerInvariant() -ne $expectedSigner) { throw 'AAB certificate does not match the pinned release signer.' }

function Test-NativeAlignment([string]$Archive) {
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    $checked = 0
    try {
        foreach ($entry in $zip.Entries | Where-Object { $_.FullName -match '(^|/)lib/(arm64-v8a|x86_64)/[^/]+\.so$' }) {
            $source = $entry.Open()
            $memory = [IO.MemoryStream]::new()
            try { $source.CopyTo($memory) } finally { $source.Dispose() }
            $reader = [IO.BinaryReader]::new($memory)
            try {
                $memory.Position = 0
                if ($reader.ReadUInt32() -ne 0x464c457f -or $reader.ReadByte() -ne 2 -or $reader.ReadByte() -ne 1) { throw 'Unexpected native ELF format.' }
                $memory.Position = 32; $table = $reader.ReadUInt64()
                $memory.Position = 54; $size = $reader.ReadUInt16(); $count = $reader.ReadUInt16()
                if ($size -lt 56 -or $table + $size * $count -gt $memory.Length) { throw 'Invalid native program headers.' }
                for ($index = 0; $index -lt $count; $index++) {
                    $memory.Position = $table + $size * $index
                    if ($reader.ReadUInt32() -ne 1) { continue }
                    $memory.Position += 4
                    $offset = $reader.ReadUInt64(); $address = $reader.ReadUInt64()
                    $memory.Position = $table + $size * $index + 48
                    $alignment = $reader.ReadUInt64()
                    if ($alignment -lt 16384 -or ($address % 16384) -ne ($offset % 16384)) { throw "Native 16 KB alignment failed: $($entry.FullName)" }
                }
                $checked++
            } finally { $reader.Dispose(); $memory.Dispose() }
        }
    } finally { $zip.Dispose() }
    if ($checked -lt 4) { throw 'Expected arm64/x64 Flutter and app libraries are missing.' }
    return $checked
}
$apkLibraries = Test-NativeAlignment $Apk
$aabLibraries = Test-NativeAlignment $Aab
[pscustomobject]@{ Package=$Package; VersionName=$VersionName; VersionCode=$VersionCode; SignerSha256=$expectedSigner; Debuggable=$false; TargetSdk=36; MinSdk=24; Backup=$false; Cleartext=$false; CallbackScheme=$Package; Permissions=$permissions; ZipAlignmentKb=16; NativeLibrariesChecked=@{Apk=$apkLibraries;Aab=$aabLibraries} }

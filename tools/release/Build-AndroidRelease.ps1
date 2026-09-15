[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('dev','prod')][string]$Environment,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$ExpectedHead,
    [Parameter(Mandatory)][ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')][string]$VersionName,
    [Parameter(Mandatory)][ValidateRange(2,2100000000)][int]$VersionCode,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$ConfigurationFile,
    [switch]$PackagingOnly,
    [switch]$PrivateBeta
)
$ErrorActionPreference = 'Stop'
if ($PrivateBeta -and ($Environment -ne 'dev' -or $PackagingOnly)) { throw 'Private beta requires configured Dev; Production is not permitted.' }
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Set-Location -LiteralPath $root
if ((git rev-parse HEAD).Trim() -ne $ExpectedHead -or (git status --porcelain)) { throw 'Build requires the exact clean reviewed commit.' }
$out = [IO.Path]::GetFullPath($OutputDirectory)
if ($out.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $out -eq $root) { throw 'Keep release artifacts outside the repository.' }
if (Test-Path -LiteralPath $out) { throw 'Artifact directory exists; never overwrite release evidence.' }
$pin = Get-Content (Join-Path $PSScriptRoot 'toolchain.json') -Raw | ConvertFrom-Json
$sdk = flutter --version --machine | ConvertFrom-Json
if ($sdk.frameworkVersion -ne $pin.flutter -or $sdk.frameworkRevision -ne $pin.flutterRevision) { throw 'Use the pinned Flutter release and revision.' }
foreach ($name in 'STORE_FILE','STORE_PASSWORD','KEY_ALIAS','KEY_PASSWORD') {
    if (![Environment]::GetEnvironmentVariable("LIST_AND_SPLIT_RELEASE_$name")) { throw "Missing release signing configuration name: LIST_AND_SPLIT_RELEASE_$name" }
}
if ($PackagingOnly -and ($Environment -ne 'prod' -or $ConfigurationFile)) { throw 'Packaging-only permits only unconfigured Production, with no client configuration.' }
if (!$PackagingOnly) {
    if (!$ConfigurationFile) { throw 'Provide a local public-client JSON configuration file.' }
    $config = Get-Content -LiteralPath $ConfigurationFile -Raw | ConvertFrom-Json
    if ($config.APP_ENV -ne $Environment -or $config.SUPABASE_PUBLISHABLE_KEY -notmatch '^sb_publishable_[A-Za-z0-9_-]+$') { throw 'Invalid environment or public client key type; values withheld.' }
    $ref = if ($Environment -eq 'dev') { 'lzwsgxziqxpxwyalkfuy' } else {
        ((Get-Content android/production.properties | Where-Object { $_ -match '^projectRef=' }) -replace '^projectRef=','').Trim()
    }
    if ($ref -notmatch '^[a-z]{20}$' -or ($Environment -eq 'prod' -and $ref -eq 'lzwsgxziqxpxwyalkfuy') -or $config.SUPABASE_URL -ne "https://$ref.supabase.co") { throw 'Client target does not match the approved native environment pin.' }
    if (@($config.PSObject.Properties.Name | Where-Object { $_ -notin 'APP_ENV','SUPABASE_URL','SUPABASE_PUBLISHABLE_KEY' }).Count) { throw 'Unexpected configuration fields; only the three public client settings are allowed.' }
}
New-Item -ItemType Directory -Path $out | Out-Null
$temporaryConfig = Join-Path $out 'build-config.tmp.json'
if ($PackagingOnly) { @{APP_ENV='prod'} | ConvertTo-Json | Set-Content -LiteralPath $temporaryConfig }
else { Copy-Item -LiteralPath $ConfigurationFile -Destination $temporaryConfig }
$redactions = @($env:LIST_AND_SPLIT_RELEASE_STORE_PASSWORD,$env:LIST_AND_SPLIT_RELEASE_KEY_PASSWORD)
if (!$PackagingOnly) { $redactions += $config.SUPABASE_PUBLISHABLE_KEY }
try {
    flutter pub get --enforce-lockfile *> (Join-Path $out 'dependencies.log')
    if ($LASTEXITCODE -ne 0) { throw 'Locked dependency resolution failed.' }
    foreach ($kind in 'apk','appbundle') {
        & flutter build $kind --release --flavor $Environment --no-pub --build-name $VersionName --build-number $VersionCode `
            --obfuscate "--split-debug-info=$out/symbols" "--dart-define-from-file=$temporaryConfig" 2>&1 | ForEach-Object {
                $line = [string]$_
                foreach ($value in $redactions) { if ($value) { $line = $line.Replace($value,'[REDACTED]') } }
                $line
            } | Set-Content -LiteralPath (Join-Path $out "$kind-build.log")
        if ($LASTEXITCODE -ne 0) { throw "Release $kind build failed; inspect its redacted log." }
    }
    Copy-Item -LiteralPath "build/app/outputs/flutter-apk/app-$Environment-release.apk" -Destination "$out/list-and-split.apk"
    Copy-Item -LiteralPath "build/app/outputs/bundle/${Environment}Release/app-$Environment-release.aab" -Destination "$out/list-and-split.aab"
    if (Test-Path "build/app/outputs/mapping/${Environment}Release") { Copy-Item "build/app/outputs/mapping/${Environment}Release" "$out/android-symbols" -Recurse }
    $package = if ($Environment -eq 'dev') { 'com.ferbatech.listandsplit.dev' } else { 'com.ferbatech.listandsplit' }
    $verification = & (Join-Path $PSScriptRoot 'Test-AndroidArtifacts.ps1') -Apk "$out/list-and-split.apk" -Aab "$out/list-and-split.aab" -Package $package -VersionName $VersionName -VersionCode $VersionCode -PrivateBeta:$PrivateBeta
    $manifest = [ordered]@{Source=$ExpectedHead;Environment=$Environment;Configured=(!$PackagingOnly);Distributable=$false;DistributionGate='Backend smoke tests, signer continuity and owner authorization still required';VersionName=$VersionName;VersionCode=$VersionCode;Flutter=$pin.flutter;Verification=$verification;Artifacts=@()}
    foreach ($file in 'list-and-split.apk','list-and-split.aab') { $manifest.Artifacts += @{Name=$file;Sha256=(Get-FileHash "$out/$file").Hash.ToLowerInvariant()} }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content "$out/manifest.json"
    if (git status --porcelain) { throw 'Build modified tracked source or lockfiles; review before distribution.' }
    'Signed APK/AAB verified. Packaging checks do not authorize distribution or prove backend readiness.'
} finally {
    if (Test-Path -LiteralPath $temporaryConfig) { Remove-Item -LiteralPath $temporaryConfig }
    foreach ($name in 'STORE_FILE','STORE_PASSWORD','KEY_ALIAS','KEY_PASSWORD') { Remove-Item "Env:LIST_AND_SPLIT_RELEASE_$name" -ErrorAction SilentlyContinue }
    $config=$null; $redactions=$null
}

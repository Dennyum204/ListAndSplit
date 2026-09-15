# Run interactively. The destination should be owner-controlled offline storage.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Destination)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $Destination) { throw 'Backup destination exists; never overwrite signing material.' }
$first = Read-Host 'Choose an independent backup password (at least 16 characters)' -AsSecureString
$second = Read-Host 'Confirm backup password' -AsSecureString
$password = [Net.NetworkCredential]::new('', $first).Password
if ($password.Length -lt 16 -or $password -cne [Net.NetworkCredential]::new('', $second).Password) { throw 'Passwords must match and contain at least 16 characters.' }
. (Join-Path $PSScriptRoot 'Import-ReleaseSigning.ps1')
$originalHash = (Get-FileHash -LiteralPath $env:LIST_AND_SPLIT_RELEASE_STORE_FILE).Hash
try {
    $env:LIST_AND_SPLIT_BACKUP_PASSWORD = $password
    & keytool -importkeystore -srckeystore $env:LIST_AND_SPLIT_RELEASE_STORE_FILE -srcstoretype PKCS12 `
        -srcstorepass:env LIST_AND_SPLIT_RELEASE_STORE_PASSWORD -srcalias listandsplit `
        -destkeystore $Destination -deststoretype PKCS12 -destalias listandsplit `
        -deststorepass:env LIST_AND_SPLIT_BACKUP_PASSWORD -destkeypass:env LIST_AND_SPLIT_BACKUP_PASSWORD -noprompt
    if ($LASTEXITCODE -ne 0) { throw 'Backup failed; preserve any partial output for inspection.' }
    $certificate = (& keytool -list -v -keystore $Destination -storepass:env LIST_AND_SPLIT_BACKUP_PASSWORD) -join "`n"
    $expected = (Get-Content (Join-Path $PSScriptRoot 'release-signer.sha256') -Raw).Trim()
    if ($LASTEXITCODE -ne 0 -or $certificate -notmatch 'SHA256: ([A-Fa-f0-9:]+)' -or $Matches[1].Replace(':','').ToLowerInvariant() -ne $expected) { throw 'Backup certificate verification failed.' }
    if ((Get-FileHash -LiteralPath $env:LIST_AND_SPLIT_RELEASE_STORE_FILE).Hash -ne $originalHash) { throw 'Original signing material changed unexpectedly.' }
    'Portable encrypted signing backup verified. Store its password separately, outside this PC and chat.'
} finally {
    foreach ($name in 'STORE_FILE','STORE_PASSWORD','KEY_ALIAS','KEY_PASSWORD') { Remove-Item "Env:LIST_AND_SPLIT_RELEASE_$name" -ErrorAction SilentlyContinue }
    Remove-Item Env:LIST_AND_SPLIT_BACKUP_PASSWORD -ErrorAction SilentlyContinue
    $password=$null; $first.Dispose(); $second.Dispose()
}

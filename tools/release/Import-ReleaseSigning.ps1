[CmdletBinding()]
param([string]$Directory = "$env:USERPROFILE\.listandsplit\signing")
$ErrorActionPreference = 'Stop'
$key = Join-Path $Directory 'release.p12'
if (!(Test-Path -LiteralPath $key)) { throw 'Release key missing. Do not generate a replacement for an existing signing identity.' }
$secure = (Get-Content -LiteralPath (Join-Path $Directory 'password.dpapi') -Raw).Trim() | ConvertTo-SecureString
$env:LIST_AND_SPLIT_RELEASE_STORE_FILE = [IO.Path]::GetFullPath($key)
$env:LIST_AND_SPLIT_RELEASE_KEY_ALIAS = 'listandsplit'
$env:LIST_AND_SPLIT_RELEASE_STORE_PASSWORD = [Net.NetworkCredential]::new('', $secure).Password
$env:LIST_AND_SPLIT_RELEASE_KEY_PASSWORD = $env:LIST_AND_SPLIT_RELEASE_STORE_PASSWORD
'Release signing loaded into this process; values withheld.'

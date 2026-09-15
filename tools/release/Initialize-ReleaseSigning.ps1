# Windows-only, current-user DPAPI. Make an independently encrypted offline backup.
[CmdletBinding()]
param([string]$Directory = "$env:USERPROFILE\.listandsplit\signing")
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $Directory) { throw 'Signing directory already exists. Preserve it and import the existing key.' }
New-Item -ItemType Directory -Path $Directory | Out-Null
$acl = Get-Acl -LiteralPath $Directory
$acl.SetAccessRuleProtection($true, $false)
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new('SYSTEM','FullControl','ContainerInherit,ObjectInherit','None','Allow'))
Set-Acl -LiteralPath $Directory -AclObject $acl
$bytes = New-Object byte[] 48
[Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
$password = [Convert]::ToBase64String($bytes)
try {
    $password | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString |
        Set-Content -LiteralPath (Join-Path $Directory 'password.dpapi')
    $env:LIST_AND_SPLIT_KEYTOOL_PASSWORD = $password
    & keytool -genkeypair -keystore (Join-Path $Directory 'release.p12') -storetype PKCS12 `
        -storepass:env LIST_AND_SPLIT_KEYTOOL_PASSWORD -keypass:env LIST_AND_SPLIT_KEYTOOL_PASSWORD `
        -alias listandsplit -keyalg RSA -keysize 4096 -validity 10000 -dname 'CN=List and Split Android Release'
    if ($LASTEXITCODE -ne 0) { throw 'Key creation failed. Preserve the directory and inspect; never overwrite a key.' }
    'Release key created outside Git. Keep this directory and arrange an encrypted offline backup before distribution.'
} finally {
    Remove-Item Env:LIST_AND_SPLIT_KEYTOOL_PASSWORD -ErrorAction SilentlyContinue
    $password = $null
    [Array]::Clear($bytes,0,$bytes.Length)
}

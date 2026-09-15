# Offline regression checks: no Supabase command or hosted target is invoked.
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$head = (git -C $root rev-parse HEAD).Trim()
$manifest = & "$PSScriptRoot/Test-BackendSource.ps1" -ExpectedHead $head
if ($manifest.migrations.Count -ne 31 -or $manifest.functions.Count -ne 3) { throw 'Unexpected reviewed backend inventory.' }
'PASS exact clean source, 31 migration hashes and three function bundles'
function Assert-Rejected([scriptblock]$Action, [string]$Message) {
    try { & $Action | Out-Null }
    catch { if ($_.Exception.Message -like "*$Message*") { "PASS $Message"; return }; throw }
    throw "Guard did not reject: $Message"
}
Assert-Rejected { & "$PSScriptRoot/Test-BackendSource.ps1" -ExpectedHead ('0'*40) } 'exact clean reviewed source'
Assert-Rejected { & "$PSScriptRoot/Build-AndroidRelease.ps1" -Environment prod -PrivateBeta -ExpectedHead $head -VersionName 1.0.0 -VersionCode 2 -OutputDirectory 'unused' } 'Private beta requires configured Dev'
Assert-Rejected { & "$PSScriptRoot/Build-AndroidRelease.ps1" -Environment dev -PrivateBeta -PackagingOnly -ExpectedHead $head -VersionName 1.0.0 -VersionCode 2 -OutputDirectory 'unused' } 'Private beta requires configured Dev'
Assert-Rejected { & "$PSScriptRoot/Test-AndroidArtifacts.ps1" -PrivateBeta -Package 'com.ferbatech.listandsplit' -Apk 'unused' -Aab 'unused' -VersionName 1.0.0 -VersionCode 2 } 'Private beta verification only permits'
foreach ($ref in 'lzwsgxziqxpxwyalkfuy','kqwiejjzknxudiajdnso') {
    Assert-Rejected { & "$PSScriptRoot/Prepare-ProductionBackend.ps1" -ExpectedHead $head -ProjectRef $ref -EvidenceDirectory 'unused' } 'not an approved fresh'
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('listandsplit-approval-test-'+[guid]::NewGuid()+'.json')
try {
    '{}' | Set-Content -LiteralPath $temporary
    Assert-Rejected { & "$PSScriptRoot/Invoke-ApprovedProductionBackend.ps1" -ApprovalFile $temporary -EvidenceDirectory 'unused' } 'OwnerAuthorized'
} finally { Remove-Item -LiteralPath $temporary }
foreach ($script in Get-ChildItem "$PSScriptRoot/*.ps1") {
    $tokens=$null; $errors=$null
    [Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count) { throw "PowerShell syntax error: $($script.Name)" }
}
'PASS release scripts parse'

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ApprovalFile,
    [Parameter(Mandatory)][string]$EvidenceDirectory
)
$ErrorActionPreference = 'Stop'
# An approval record documents external owner authorization; the file itself
# does not grant authority. Never run this script before that authorization.
$approval = Get-Content -LiteralPath $ApprovalFile -Raw | ConvertFrom-Json
foreach ($gate in 'OwnerAuthorized','BackupReviewed','AuthSmtpReviewed','RetentionSchedulesApproved') {
    if ($approval.$gate -ne $true) { throw "Missing reviewed rollout gate: $gate" }
}
# Repeat all authoritative checks immediately before the single migration push.
& "$PSScriptRoot/Prepare-ProductionBackend.ps1" -ExpectedHead $approval.Source -ProjectRef $approval.ProjectRef -EvidenceDirectory $EvidenceDirectory
$out = [IO.Path]::GetFullPath($EvidenceDirectory)
supabase db push --linked --workdir $out --yes *> "$out/migration-apply.log"
if ($LASTEXITCODE -ne 0) { throw 'Migration result uncertain. Inspect authoritative history before any retry; do not distribute clients.' }
$history = supabase db query --linked --workdir $out -f "$out/history.sql" -o json | ConvertFrom-Json
$expected = (Get-Content "$out/preflight.json" -Raw | ConvertFrom-Json).Migrations | ForEach-Object { $_.Substring(0,14) }
if ($LASTEXITCODE -ne 0 -or (Compare-Object @($expected) @($history.rows | ForEach-Object { $_.version }))) { throw 'Applied migration history differs; stop distribution.' }
foreach ($name in 'delete-account','profile-avatar') {
    supabase functions deploy $name --project-ref $approval.ProjectRef --workdir $out --use-api --no-verify-jwt *> "$out/$name-deploy.log"
    if ($LASTEXITCODE -ne 0) { throw "Deployment of $name uncertain. Inspect authoritative version and bundle before retrying. Keep avatar-aware deletion service." }
    $versions = @(supabase functions list --project-ref $approval.ProjectRef -o json | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0) { throw 'Authoritative function state unavailable; stop.' }
    $function = @($versions | Where-Object { $_.slug -eq $name -and $_.status -eq 'ACTIVE' -and $_.verify_jwt -eq $false })
    if ($function.Count -ne 1) { throw 'Function state did not match reviewed authentication configuration.' }
    $function | Select-Object slug,version,status,verify_jwt,ezbr_sha256 | ConvertTo-Json | Set-Content "$out/$name-version.json"
}
'Deployment commands completed. Client distribution remains blocked until the runbook backend smoke and recovery checks pass.'

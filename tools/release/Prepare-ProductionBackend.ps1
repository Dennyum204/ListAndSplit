[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$ExpectedHead,
    [Parameter(Mandatory)][ValidatePattern('^[a-z]{20}$')][string]$ProjectRef,
    [Parameter(Mandatory)][string]$EvidenceDirectory
)
$ErrorActionPreference = 'Stop'
# Read-only remote preflight for a newly approved, empty Production project.
# It cannot prepare Dev, an unrelated existing project, or an incremental rollout.
if ($ProjectRef -in 'lzwsgxziqxpxwyalkfuy','kqwiejjzknxudiajdnso') { throw 'This is not an approved fresh List & Split Production target.' }
$manifest = & "$PSScriptRoot/Test-BackendSource.ps1" -ExpectedHead $ExpectedHead
if ((supabase --version).Trim() -ne '2.109.1') { throw 'Use reviewed Supabase CLI 2.109.1.' }
$projects = supabase projects list -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Project discovery failed.' }
$target = @($projects | Where-Object { $_.id -eq $ProjectRef -and $_.name -eq 'List & Split Production' })
if ($target.Count -ne 1) { throw 'Exact Production identity was not verified.' }
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$out = [IO.Path]::GetFullPath($EvidenceDirectory)
if ($out -eq $root -or $out.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $out)) { throw 'Use a new evidence directory outside the source checkout.' }
New-Item -ItemType Directory -Path "$out/supabase" | Out-Null
Copy-Item "$root/supabase/config.toml" "$out/supabase/config.toml"
foreach ($part in 'migrations','functions') { Copy-Item "$root/supabase/$part" "$out/supabase/$part" -Recurse }
supabase link --project-ref $ProjectRef --workdir $out
if ($LASTEXITCODE -ne 0) { throw 'Link failed; no deployment attempted.' }
$historySql = Join-Path $out 'history.sql'
'select version from supabase_migrations.schema_migrations order by version;' | Set-Content $historySql
$history = supabase db query --linked --workdir $out -f $historySql -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $null -eq $history.rows) { throw 'Cannot establish authoritative migration history.' }
if (@($history.rows).Count) { throw 'Target already has migrations; stop for a separately reviewed incremental plan.' }
$functions = @(supabase functions list --project-ref $ProjectRef -o json | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or @($functions | Where-Object { $_ }).Count) { throw 'Unexpected existing Edge deployment; stop.' }
$dryRun = (supabase db push --dry-run --linked --workdir $out 2>&1) -join "`n"
$exitCode = $LASTEXITCODE
$dryRun | Set-Content "$out/migration-dry-run.txt"
if ($exitCode -ne 0) { throw 'Supported migration dry run failed.' }
$proposed = @([regex]::Matches($dryRun,'(?m)^\s*[•*-]\s*(\d{14}_[a-z0-9_]+\.sql)\s*$') | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
$expected = @($manifest.migrations | ForEach-Object { Split-Path $_.path -Leaf } | Sort-Object)
if ($proposed.Count -ne 30 -or (Compare-Object $expected $proposed)) { throw 'Dry run did not propose exactly the 30 reviewed migrations.' }
supabase db advisors --linked --workdir $out -o json *> "$out/advisor-baseline.json"
if ($LASTEXITCODE -ne 0) { throw 'Advisor baseline unavailable.' }
@{ Source=$ExpectedHead; ProjectRef=$ProjectRef; ProjectName=$target[0].name; Migrations=$expected; Functions=@('delete-account','profile-avatar'); CreatedUtc=[DateTime]::UtcNow.ToString('o'); Applied=$false } | ConvertTo-Json -Depth 5 | Set-Content "$out/preflight.json"
'Read-only preflight complete. Owner authorization and backup/Auth/SMTP review are still required before deployment.'

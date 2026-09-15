param([Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$ExpectedHead)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if ((git -C $root rev-parse HEAD).Trim() -ne $ExpectedHead -or (git -C $root status --porcelain)) { throw 'Require the exact clean reviewed source.' }
$manifest = Get-Content "$PSScriptRoot/backend-manifest.json" -Raw | ConvertFrom-Json
$entries = @($manifest.migrations) + @($manifest.functions | ForEach-Object { $_.files })
foreach ($entry in $entries) {
    $file = [IO.Path]::GetFullPath((Join-Path $root $entry.path))
    if (!$file.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Manifest path escaped source.' }
    $bytes = [Text.Encoding]::UTF8.GetBytes([IO.File]::ReadAllText($file).Replace("`r`n","`n"))
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    if ($hash -ne $entry.sha256) { throw "Reviewed backend source changed: $($entry.path)" }
}
$actual = @(Get-ChildItem "$root/supabase/migrations/*.sql" | ForEach-Object { $_.Name } | Sort-Object)
$expected = @($manifest.migrations | ForEach-Object { Split-Path $_.path -Leaf } | Sort-Object)
if (Compare-Object $actual $expected) { throw 'Unexpected migration set.' }
foreach ($name in 'delete-account','profile-avatar') {
    $config = Get-Content "$root/supabase/config.toml" -Raw
    if ($config -notmatch "(?s)\[functions\.$name\][^\[]*?verify_jwt\s*=\s*false") { throw 'Reviewed function authentication configuration changed.' }
}
$manifest

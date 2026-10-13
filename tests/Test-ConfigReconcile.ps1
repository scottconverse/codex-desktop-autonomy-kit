<#
.SYNOPSIS
    Tests the v2.0.0 autonomy-key reconcile: Setup sets ONLY its own keys in an
    existing custom config, preserves everything else, is idempotent, honors
    -SkipReconcile, and never injects developer_instructions.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$kit = Split-Path $PSScriptRoot -Parent
$setup = Join-Path $kit "Setup-Autonomy.ps1"
$results = New-Object System.Collections.Generic.List[object]
function Add-Result {
    param([string]$Name, [ValidateSet("PASS", "FAIL", "INFO")][string]$Status, [string]$Detail)
    $results.Add([pscustomobject]@{ Check = $Name; Status = $Status; Detail = $Detail })
}

# A custom config missing approval_policy, with a wrong sandbox_mode, a [windows]
# table that lacks sandbox, and distinctive user keys that must survive untouched.
$customConfig = @"
model = "deepseek-v4.1-flash:cloud"
sandbox_mode = "read-only"
preserve_marker = "KEEP-ME-123"

[desktop]
appearanceTheme = "dark"

[windows]
other_win = "x"

[plugins."browser@openai-bundled"]
enabled = true
"@

function New-Root {
    $r = Join-Path $env:TEMP ("ckit-rec-" + [guid]::NewGuid().ToString("n"))
    New-Item -ItemType Directory -Force -Path $r | Out-Null
    return $r
}
function Invoke-Setup {
    param([string]$Root, [switch]$SkipReconcile)
    $a = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $setup, "-ConfigOnly", "-SkipCommandRules", "-CodexRoot", $Root)
    if ($SkipReconcile) { $a += "-SkipReconcile" }
    & powershell @a *> $null
}

# --- default reconcile sets the kit's keys, preserves the rest ---------------
try {
    $root = New-Root
    $cfg = Join-Path $root "config.toml"
    Set-Content -LiteralPath $cfg -Value $customConfig -Encoding utf8 -NoNewline
    Invoke-Setup -Root $root
    $after = Get-Content -LiteralPath $cfg -Raw
    $set = ($after -match '(?m)^approval_policy = "never"$') -and
           ($after -match '(?m)^sandbox_mode = "danger-full-access"$') -and
           ($after -match '(?ms)^\[windows\].*?^sandbox = "elevated"$')
    $preserved = ($after -match 'KEEP-ME-123') -and ($after -match 'deepseek-v4\.1-flash') -and
                 ($after -match 'browser@openai-bundled') -and ($after -match '(?m)^other_win = "x"$') -and
                 ($after -match 'appearanceTheme = "dark"')
    $noDevInstr = -not ($after -match 'developer_instructions')
    $backup = @(Get-ChildItem -LiteralPath $root -Filter 'config.toml.bak-*').Count -ge 1
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    $ok = $set -and $preserved -and $noDevInstr -and $backup
    Add-Result "reconcile_sets_and_preserves" $(if ($ok) { "PASS" } else { "FAIL" }) "keysSet=$set preserved=$preserved noDevInstr=$noDevInstr backup=$backup"
} catch {
    if ($root -and (Test-Path -LiteralPath $root)) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    Add-Result "reconcile_sets_and_preserves" "FAIL" $_.Exception.Message
}

# --- idempotent: a second run changes nothing and adds no backup -------------
try {
    $root = New-Root
    $cfg = Join-Path $root "config.toml"
    Set-Content -LiteralPath $cfg -Value $customConfig -Encoding utf8 -NoNewline
    Invoke-Setup -Root $root
    $hash1 = (Get-FileHash -Algorithm SHA256 -LiteralPath $cfg).Hash
    $bak1 = @(Get-ChildItem -LiteralPath $root -Filter 'config.toml.bak-*').Count
    Invoke-Setup -Root $root
    $hash2 = (Get-FileHash -Algorithm SHA256 -LiteralPath $cfg).Hash
    $bak2 = @(Get-ChildItem -LiteralPath $root -Filter 'config.toml.bak-*').Count
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    $ok = ($hash1 -eq $hash2) -and ($bak1 -eq $bak2)
    Add-Result "reconcile_idempotent" $(if ($ok) { "PASS" } else { "FAIL" }) "hashStable=$($hash1 -eq $hash2) backups $bak1->$bak2"
} catch {
    if ($root -and (Test-Path -LiteralPath $root)) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    Add-Result "reconcile_idempotent" "FAIL" $_.Exception.Message
}

# --- -SkipReconcile leaves a custom config byte-for-byte untouched -----------
try {
    $root = New-Root
    $cfg = Join-Path $root "config.toml"
    Set-Content -LiteralPath $cfg -Value $customConfig -Encoding utf8 -NoNewline
    $before = (Get-FileHash -Algorithm SHA256 -LiteralPath $cfg).Hash
    Invoke-Setup -Root $root -SkipReconcile
    $afterHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $cfg).Hash
    $bak = @(Get-ChildItem -LiteralPath $root -Filter 'config.toml.bak-*').Count
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    $ok = ($before -eq $afterHash) -and ($bak -eq 0)
    Add-Result "skipreconcile_byte_identical" $(if ($ok) { "PASS" } else { "FAIL" }) "unchanged=$($before -eq $afterHash) backups=$bak"
} catch {
    if ($root -and (Test-Path -LiteralPath $root)) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    Add-Result "skipreconcile_byte_identical" "FAIL" $_.Exception.Message
}

# --- direct-function cases: append [windows]; already-satisfied is a no-op ----
try {
    $env:CODEX_SETUP_SOURCE_ONLY = "1"
    . $setup
    $env:CODEX_SETUP_SOURCE_ONLY = $null

    # No [windows] table at all -> table appended with sandbox = elevated.
    $root = New-Root
    New-Item -ItemType Directory -Force -Path (Join-Path $root "autonomy-kit") | Out-Null
    $cfg = Join-Path $root "config.toml"
    Set-Content -LiteralPath $cfg -Value "approval_policy = `"never`"`nsandbox_mode = `"danger-full-access`"`nkeepme = `"yes`"" -Encoding utf8 -NoNewline
    $r = Reconcile-AutonomyConfig -Path $cfg -ManifestPath (Join-Path $root "autonomy-kit\config-backup-manifest.json")
    $txt = Get-Content -LiteralPath $cfg -Raw
    $appended = ($r.Changed) -and ($txt -match '(?ms)^\[windows\]\s*\r?\nsandbox = "elevated"') -and ($txt -match 'keepme = "yes"')

    # Already satisfied -> no change, no backup.
    $root2 = New-Root
    New-Item -ItemType Directory -Force -Path (Join-Path $root2 "autonomy-kit") | Out-Null
    $cfg2 = Join-Path $root2 "config.toml"
    Set-Content -LiteralPath $cfg2 -Value "approval_policy = `"never`"`nsandbox_mode = `"danger-full-access`"`n`n[windows]`nsandbox = `"elevated`"" -Encoding utf8 -NoNewline
    $r2 = Reconcile-AutonomyConfig -Path $cfg2 -ManifestPath (Join-Path $root2 "autonomy-kit\config-backup-manifest.json")
    $noop = (-not $r2.Changed) -and (@(Get-ChildItem -LiteralPath $root2 -Filter 'config.toml.bak-*').Count -eq 0)

    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $root2 -Recurse -Force -ErrorAction SilentlyContinue
    Add-Result "reconcile_windows_and_noop" $(if ($appended -and $noop) { "PASS" } else { "FAIL" }) "windowsAppended=$appended alreadySatisfiedNoop=$noop"
} catch {
    foreach ($r in @($root, $root2)) { if ($r -and (Test-Path -LiteralPath $r)) { Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction SilentlyContinue } }
    Add-Result "reconcile_windows_and_noop" "FAIL" $_.Exception.Message
}

""
$results | Format-Table -AutoSize | Out-String | Write-Host
$pass = @($results | Where-Object { $_.Status -eq "PASS" }).Count
$fail = @($results | Where-Object { $_.Status -eq "FAIL" }).Count
Write-Host ("SUMMARY: {0} PASS / {1} FAIL" -f $pass, $fail)
if ($fail -gt 0) { exit 1 } else { exit 0 }

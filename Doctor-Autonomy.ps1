<#
.SYNOPSIS
    Read-only status dashboard for the Codex Desktop Autonomy Kit installation.
#>
[CmdletBinding()]
param()

$cx = "$env:USERPROFILE\.codex"
function Section($title) { Write-Host "`n=== $title ===" -ForegroundColor Cyan }
function L($k,$v) { "{0,-32} {1}" -f $k, $v | Write-Host }

Section "Toolchain"
foreach ($t in 'python3','pip','uv','scoop','node','npm','npx','gh','rg','jq','sqlite3','playwright') {
    $src = (Get-Command $t -ErrorAction SilentlyContinue).Source
    L $t $(if ($src) { $src } else { '(missing)' })
}

Section "Config (~/.codex)"
$config = Join-Path $cx "config.toml"
$profileDir = Join-Path $cx "autonomy-kit"
$core = Join-Path $profileDir "CODEX-Desktop-Core.md"
$full = Join-Path $profileDir "GEN5-Codex-Desktop-Autonomous-Software-Development.md"
L "config.toml" $(if (Test-Path $config) { "present ($((Get-Item $config).Length) bytes)" } else { '(missing)' })
L "compact core" $(if (Test-Path $core) { 'present' } else { '(missing)' })
L "full profile" $(if (Test-Path $full) { 'present' } else { '(missing)' })
if (Test-Path $config) {
    $raw = Get-Content -LiteralPath $config -Raw
    L "  approval_policy=never" $(if ($raw -match 'approval_policy\s*=\s*"never"') { 'yes' } else { 'no/unknown' })
    L "  danger-full-access" $(if ($raw -match 'sandbox_mode\s*=\s*"danger-full-access"') { 'yes' } else { 'no/unknown' })
    L "  windows elevated" $(if ($raw -match 'sandbox\s*=\s*"elevated"') { 'yes' } else { 'no/unknown' })
    L "  developer_instructions" $(if ($raw -match 'developer_instructions') { 'present' } else { 'missing' })
    $bakCount = (Get-ChildItem -LiteralPath $cx -Filter "config.toml.bak-*" -ErrorAction SilentlyContinue).Count
    L "  backups present" $bakCount
}

Section "Elevated dev helper"
$h = Get-ScheduledTask -TaskName "CodexElevatedDevHelper" -ErrorAction SilentlyContinue
if ($h) {
    L "task" "CodexElevatedDevHelper"
    L "  state" $h.State
    $hinfo = Get-ScheduledTaskInfo -TaskName "CodexElevatedDevHelper"
    L "  last run" $hinfo.LastRunTime
    L "  last result code" $hinfo.LastTaskResult
    L "  install root" 'C:\dev\CodexElevatedHelper'
} else {
    L "task" '(not registered - run elevated-dev-helper\Install-ElevatedDevHelper-AsAdmin.cmd)'
}

Write-Host ""

<#
.SYNOPSIS
    Read-only status dashboard for the Codex Desktop Autonomy Kit installation.
#>
[CmdletBinding()]
param()

$kit = $PSScriptRoot
$cx = "$env:USERPROFILE\.codex"
$configMarker = "# Codex Desktop Autonomy Kit managed config"

function Section($title) { Write-Host "`n=== $title ===" -ForegroundColor Cyan }
function L($k,$v) { "{0,-34} {1}" -f $k, $v | Write-Host }
function Hash($path) {
    if (Test-Path -LiteralPath $path) { return (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash }
    return $null
}
function Is-WritableDir($path) {
    try {
        New-Item -ItemType Directory -Force -Path $path | Out-Null
        $probe = Join-Path $path (".write-test-" + [guid]::NewGuid().ToString("n"))
        "ok" | Set-Content -LiteralPath $probe -Encoding UTF8
        Remove-Item -LiteralPath $probe -Force
        return $true
    } catch {
        return $false
    }
}

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
$manifest = Join-Path $profileDir "manifest.json"
L "config.toml" $(if (Test-Path $config) { "present ($((Get-Item $config).Length) bytes)" } else { '(missing)' })
L "staged profile dir" $(if (Test-Path $profileDir) { $profileDir } else { '(missing)' })
L "compact core" $(if (Test-Path $core) { 'present' } else { '(missing)' })
L "full profile" $(if (Test-Path $full) { 'present' } else { '(missing)' })
L "manifest" $(if (Test-Path $manifest) { 'present' } else { '(missing)' })

if (Test-Path $config) {
    $raw = Get-Content -LiteralPath $config -Raw
    $approval = ([regex]::Matches($raw, '(?m)^\s*approval_policy\s*=')).Count
    $sandboxMode = ([regex]::Matches($raw, '(?m)^\s*sandbox_mode\s*=')).Count
    L "  kit-managed marker" $(if ($raw -like "$configMarker*") { 'yes' } else { 'no/custom or older kit' })
    L "  approval_policy=never" $(if ($raw -match 'approval_policy\s*=\s*"never"') { 'yes' } else { 'no/unknown' })
    L "  danger-full-access" $(if ($raw -match 'sandbox_mode\s*=\s*"danger-full-access"') { 'yes' } else { 'no/unknown' })
    L "  windows elevated" $(if ($raw -match '(?s)\[windows\].*?sandbox\s*=\s*"elevated"') { 'yes' } else { 'no/unknown' })
    L "  developer_instructions" $(if ($raw -match 'developer_instructions') { 'present' } else { 'missing' })
    L "  duplicate top keys" $(if ($approval -gt 1 -or $sandboxMode -gt 1) { "possible ($approval approval_policy, $sandboxMode sandbox_mode)" } else { 'none detected' })
    $bakCount = (Get-ChildItem -LiteralPath $cx -Filter "config.toml.bak-*" -ErrorAction SilentlyContinue).Count
    L "  backups present" $bakCount
}

if (Test-Path $profileDir) {
    foreach ($f in 'CODEX-Desktop-Core.md','GEN5-Codex-Desktop-Autonomous-Software-Development.md','config.autonomy.example.toml') {
        $repo = Join-Path $kit $f
        $staged = Join-Path $profileDir $f
        $repoHash = Hash $repo
        $stagedHash = Hash $staged
        L "  staged $f" $(if (-not $stagedHash) { 'missing' } elseif ($repoHash -eq $stagedHash) { 'current' } else { 'STALE/modified' })
    }
}

Section "Capability rule + skill"
$agents = Join-Path $cx "AGENTS.md"
$agentsMarker = "Codex Desktop Autonomy Kit: capability-section begin"
$skillFile = Join-Path $cx "skills\capability-check\SKILL.md"
if (Test-Path -LiteralPath $agents) {
    $agentsRaw = Get-Content -LiteralPath $agents -Raw
    $hasBlock = $agentsRaw -match [regex]::Escape($agentsMarker)
    L "AGENTS.md" "present ($((Get-Item $agents).Length) bytes)"
    L "  kit capability rule" $(if ($hasBlock) { 'yes' } else { 'no - run Setup-Autonomy.ps1 to add it' })
} else {
    L "AGENTS.md" '(missing - run Setup-Autonomy.ps1 to create it)'
}
L "capability-check skill" $(if (Test-Path -LiteralPath $skillFile) { $skillFile } else { '(missing)' })

Section "Elevated dev helper"
$h = Get-ScheduledTask -TaskName "CodexElevatedDevHelper" -ErrorAction SilentlyContinue
$helperRoot = 'C:\dev\CodexElevatedHelper'
$helperPointer = Join-Path $profileDir "helper-root.json"
if (Test-Path -LiteralPath $helperPointer) {
    try {
        $hp = Get-Content -LiteralPath $helperPointer -Raw | ConvertFrom-Json
        if ($hp.install_root) { $helperRoot = $hp.install_root }
    } catch { }
}
if ($h) {
    L "task" "CodexElevatedDevHelper"
    L "  state" $h.State
    $hinfo = Get-ScheduledTaskInfo -TaskName "CodexElevatedDevHelper"
    L "  last run" $hinfo.LastRunTime
    L "  last result code" $hinfo.LastTaskResult
    L "  install root" $helperRoot
} else {
    L "task" '(not registered - run elevated-dev-helper\Install-ElevatedDevHelper-AsAdmin.cmd)'
}
foreach ($d in 'queue','done','failed','logs') {
    $p = Join-Path $helperRoot $d
    L "  $d dir" $(if (Test-Path $p) { "present; writable=$(Is-WritableDir $p)" } else { '(missing)' })
}
$repoHelper = Join-Path $kit "elevated-dev-helper\ElevatedDevHelper.ps1"
$installedHelper = Join-Path $helperRoot "ElevatedDevHelper.ps1"
$repoHash = Hash $repoHelper
$installedHash = Hash $installedHelper
L "  helper script parity" $(if (-not $installedHash) { 'installed copy missing' } elseif ($repoHash -eq $installedHash) { 'current' } else { 'STALE/modified' })

Write-Host ""

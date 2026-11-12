<#
.SYNOPSIS
    Read-only status dashboard for the Codex Desktop Autonomy Kit installation.
#>
[CmdletBinding()]
param(
    [string]$CodexRoot = "$env:USERPROFILE\.codex"
)

$kit = $PSScriptRoot
$cx = $CodexRoot
$isDefaultRoot = ($cx -eq "$env:USERPROFILE\.codex")
$configMarker = "# Codex Desktop Autonomy Kit managed config"

function Section($title) { Write-Host "`n=== $title ===" -ForegroundColor Cyan }
function L($k,$v) { "{0,-34} {1}" -f $k, $v | Write-Host }
function Hash($path) {
    if (Test-Path -LiteralPath $path) { return (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash }
    return $null
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

Section "Codex command rules"
# Reuse the real generator/discovery from Setup (read-only load; the guard returns
# before any machine-changing work).
$rulesPath = Join-Path $cx "rules\autonomy-kit.rules"
$commandRulesMarker = "# Codex Desktop Autonomy Kit managed rules"
$setupScript = Join-Path $kit "Setup-Autonomy.ps1"
$genAvailable = $false
if (Test-Path -LiteralPath $setupScript) {
    try { $env:CODEX_SETUP_SOURCE_ONLY = "1"; . $setupScript; $genAvailable = $true } catch { }
    finally { $env:CODEX_SETUP_SOURCE_ONLY = $null }
}
if (Test-Path -LiteralPath $rulesPath) {
    $rulesRaw = Get-Content -LiteralPath $rulesPath -Raw
    $firstLine = ($rulesRaw -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1)
    $marked = ($null -ne $firstLine) -and ($firstLine.Trim() -eq $commandRulesMarker)
    L "rules file" "present ($((Get-Item $rulesPath).Length) bytes)"
    L "  kit-managed marker" $(if ($marked) { 'yes' } else { 'no/custom' })
    $bytes = [System.IO.File]::ReadAllBytes($rulesPath)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    L "  BOM-free (parser-safe)" $(if ($hasBom) { 'NO - has UTF-8 BOM, Codex will reject it' } else { 'yes' })
    if ($genAvailable) {
        $shellPaths = Get-CodexCommandRulesShellPaths -CodexRoot $cx
        $generated = Get-CommandRulesText -ShellPaths $shellPaths
        $norm = { param($t) (($t -replace "^﻿", "") -replace "`r`n", "`n").TrimEnd() }
        $stripVersion = { param($t) ($t -replace '(?m)^\s*#\s*version\s*=\s*"[^"]*"\s*$', '# version = "(current)"') }
        $current = ((& $stripVersion (& $norm $rulesRaw)) -eq (& $stripVersion (& $norm $generated)))
        L "  current with this kit" $(if ($current) { 'yes' } else { 'STALE - re-run Install-Autonomy.cmd' })
    } else {
        L "  current with this kit" "(cannot compare - Setup-Autonomy.ps1 not loadable)"
    }
} else {
    L "rules file" "(missing - run Install-Autonomy.cmd to switch off Codex's dangerous-command list)"
}

Section "Codex runtime compatibility"
# A rules file being present, and its listed executables existing, does not show that
# it covers the executable Codex launches now. This section answers four separate
# questions and never upgrades missing evidence to PASS. It is read-only: Doctor does
# not regenerate, widen, or otherwise change rules, whatever it finds.
if (-not $genAvailable) {
    L "overall" "UNKNOWN (Setup-Autonomy.ps1 not loadable; no runtime check was run)"
} else {
    $health = Get-CodexRuntimeHealth -CodexRoot $cx -RulesPath $rulesPath
    $active = $health.Active
    $fmt = { param($d) if ($d) { ([datetime]$d).ToString("yyyy-MM-dd HH:mm:ss") + "Z" } else { "(unknown)" } }

    # 1. Does each configured executable exist? (A missing file is not a mismatch.)
    if ($health.RulesPresent) {
        $missing = @($health.Configured | Where-Object { -not $_.Exists })
        L "configured executables" "$(@($health.Configured).Count) listed; $($missing.Count) missing on disk"
        foreach ($c in $health.Configured) { L $(if ($c.Exists) { "  exists" } else { "  MISSING" }) $c.Path }
    } else {
        L "configured executables" "(no rules file)"
    }

    # 2. Which executable does Codex actually launch?
    L "active runtime" $active.Status
    if ($active.Path) {
        L "  executable" $active.Path
        L "  source" $active.Source
        L "  exists on disk" $(if ($active.Exists) { "yes" } else { "NO" })
    }
    foreach ($e in $active.Evidence) { L "  evidence" $e }
    if ($active.SessionLog) {
        L "  session log" (Split-Path -Leaf $active.SessionLog)
        L "  session started" (& $fmt $active.SessionStartUtc)
    }

    # 3. Does the installed configuration list that executable?
    L "rules list active runtime" $health.Match

    # 4. Is a new chat needed for the session to hold the current rules?
    $reloadText = switch ($health.Reload) {
        "REQUIRED"     { "REQUIRED - rules written $(& $fmt $health.RulesWrittenUtc), after that session started; start a new Codex chat" }
        "NOT_REQUIRED" { "not required - that session started after the rules were written $(& $fmt $health.RulesWrittenUtc)" }
        default        { "UNKNOWN - no session start time to compare against" }
    }
    L "new Codex chat required" $reloadText

    foreach ($u in $health.UncoveredInstalled) { L "installed runtime NOT listed" $u }

    # Policy rejections are Codex's decision. They are counted separately from the
    # questions above and are not an ACL failure, a missing executable, or (by
    # themselves) a runtime mismatch.
    if ($active.SessionLog) {
        L "policy rejections (that session)" $(if ($active.RejectionCount) { "$($active.RejectionCount); most recent $(& $fmt $active.LastRejectionUtc)" } else { "none recorded" })
    }

    L "overall" $health.Overall
    foreach ($n in $health.Notes) { L "  note" $n }
    switch ($health.Overall) {
        "PASS" {
            L "  meaning" "the rules list the executable Codex launched and that session started after they were written"
            L "  not shown" "that Codex will accept any given command; only a command run in a Codex chat shows that"
        }
        "MISMATCH" {
            L "  to change" "Install-Autonomy.cmd regenerates the kit's rules when YOU run it; Doctor changes nothing"
            L "  not shown" "that the mismatch caused any rejection; it is one candidate cause, unproven"
        }
        "UNKNOWN" {
            L "  to resolve" "run a command in a new Codex chat, then run Doctor again"
        }
    }
    if ($active.RejectionCount) {
        L "  on rejections" "a rejection is Codex enforcing its command policy; do not respell or reroute the command to get past it"
    }
}

Section "Elevated dev helper"
# UX-1 / QA-3: the helper task is machine-global, but the config layer is per-root.
# Only report the helper when we are auditing the machine's real Codex root, so the
# report never mixes two different installations into one picture.
if (-not $isDefaultRoot) {
    L "helper state" "(not reported - auditing a non-default root)"
    Write-Host ""
    return
}

$helperRoot = 'C:\dev\CodexElevatedHelper'
$helperTaskName = 'CodexElevatedDevHelper'
$installedInvoker = $null
$helperPointer = Join-Path $profileDir "helper-root.json"
if (Test-Path -LiteralPath $helperPointer) {
    try {
        $hp = Get-Content -LiteralPath $helperPointer -Raw | ConvertFrom-Json
        if ($hp.install_root) { $helperRoot = $hp.install_root }
        if ($hp.task_name) { $helperTaskName = [string]$hp.task_name }
        if ($hp.invoker_script) { $installedInvoker = [string]$hp.invoker_script }
    } catch { }
}
$h = Get-ScheduledTask -TaskName $helperTaskName -ErrorAction SilentlyContinue
if (-not $installedInvoker) { $installedInvoker = Join-Path $helperRoot "Invoke-ElevatedDevHelper.ps1" }
if ($h) {
    L "task" $helperTaskName
    L "  state" $h.State
    $hinfo = Get-ScheduledTaskInfo -TaskName $helperTaskName
    L "  last run" $hinfo.LastRunTime
    L "  last result code" $hinfo.LastTaskResult
    L "  install root" $helperRoot
} else {
    L "task" '(not registered - run elevated-dev-helper\Install-ElevatedDevHelper-AsAdmin.cmd)'
}
foreach ($d in 'queue','done','failed','logs') {
    $p = Join-Path $helperRoot $d
    L "  $d dir" $(if (Test-Path $p) { 'present' } else { '(missing)' })
}
L "  write probes" "not run (read-only Doctor)"
$repoHelper = Join-Path $kit "elevated-dev-helper\ElevatedDevHelper.ps1"
$installedHelper = Join-Path $helperRoot "ElevatedDevHelper.ps1"
$repoHash = Hash $repoHelper
$installedHash = Hash $installedHelper
L "  helper script parity" $(if (-not $installedHash) { 'installed copy missing' } elseif ($repoHash -eq $installedHash) { 'current' } else { 'STALE/modified' })
$repoInvoker = Join-Path $kit "elevated-dev-helper\Invoke-ElevatedDevHelper.ps1"
$repoInvokerHash = Hash $repoInvoker
$installedInvokerHash = Hash $installedInvoker
L "  invoker script parity" $(if (-not $installedInvokerHash) { 'installed copy missing' } elseif ($repoInvokerHash -eq $installedInvokerHash) { 'current' } else { 'STALE/modified' })

Write-Host ""

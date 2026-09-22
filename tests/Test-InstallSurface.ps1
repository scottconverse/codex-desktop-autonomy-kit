<#
.SYNOPSIS
    Checks the install/update surface without changing real Codex config.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$kit = Split-Path $PSScriptRoot -Parent
$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [string]$Name,
        [ValidateSet("PASS","FAIL","INFO")][string]$Status,
        [string]$Detail
    )
    $results.Add([pscustomobject]@{ Check = $Name; Status = $Status; Detail = $Detail })
}
function Hash($path) {
    if (Test-Path -LiteralPath $path) { return (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash }
    return $null
}

try {
    $required = @(
        'Setup-Autonomy.ps1',
        'Doctor-Autonomy.ps1',
        'Uninstall-Autonomy.ps1',
        'CODEX-Desktop-Core.md',
        'GEN5-Codex-Desktop-Autonomous-Software-Development.md',
        'config.autonomy.example.toml',
        'Install-Autonomy.cmd',
        'Doctor-Autonomy.cmd',
        'Uninstall-Autonomy.cmd',
        'Refresh-ElevatedHelper.cmd',
        'Run-Tests.cmd',
        'docs\index.html',
        'docs\USER-MANUAL.md',
        'docs\assets\codex-autonomy-architecture.svg',
        'docs\discussions\01-welcome-and-installation.md',
        'docs\discussions\02-design-boundaries-and-roadmap.md'
    )
    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $kit $_)) })
    Add-Result "required_files" $(if ($missing.Count -eq 0) { "PASS" } else { "FAIL" }) $(if ($missing.Count) { "missing: $($missing -join ', ')" } else { "all present" })
} catch { Add-Result "required_files" "FAIL" $_.Exception.Message }

try {
    $launchers = @{
        'Install-Autonomy.cmd' = 'Setup-Autonomy.ps1'
        'Doctor-Autonomy.cmd' = 'Doctor-Autonomy.ps1'
        'Uninstall-Autonomy.cmd' = 'Uninstall-Autonomy.ps1'
        'Refresh-ElevatedHelper.cmd' = 'Install-ElevatedDevHelper-AsAdmin.cmd'
        'Run-Tests.cmd' = 'Test-AutonomyKit.ps1'
    }
    $missingLinks = @()
    foreach ($launcher in $launchers.Keys) {
        $raw = Get-Content -LiteralPath (Join-Path $kit $launcher) -Raw
        if ($raw -notmatch [regex]::Escape($launchers[$launcher]) -or $raw -notmatch 'pause') {
            $missingLinks += $launcher
        }
    }
    $installer = Get-Content -LiteralPath (Join-Path $kit 'Install-Autonomy.cmd') -Raw
    $oneStopInstaller = (
        $installer -match 'Doctor-Autonomy\.ps1' -and
        $installer -match 'Install-ElevatedDevHelper-AsAdmin\.cmd' -and
        $installer -match 'Refresh elevated helper now'
    )
    Add-Result "double_click_launchers" $(if ($missingLinks.Count -eq 0 -and $oneStopInstaller) { "PASS" } else { "FAIL" }) $(if ($missingLinks.Count) { "bad launchers: $($missingLinks -join ', ')" } elseif (-not $oneStopInstaller) { "installer is not one-stop" } else { "all launchers point at expected scripts; installer includes doctor + helper refresh flow" })
} catch { Add-Result "double_click_launchers" "FAIL" $_.Exception.Message }

try {
    $adminLauncher = Get-Content -LiteralPath (Join-Path $kit 'elevated-dev-helper\Install-ElevatedDevHelper-AsAdmin.cmd') -Raw
    $helperInstaller = Get-Content -LiteralPath (Join-Path $kit 'elevated-dev-helper\Install-ElevatedDevHelper.ps1') -Raw
    $ok = (
        $adminLauncher -notmatch '-NoExit' -and
        $adminLauncher -match '-Wait' -and
        $adminLauncher -match '-PassThru' -and
        $adminLauncher -match 'exit \$p\.ExitCode' -and
        $helperInstaller -match 'AddSeconds\(30\)' -and
        $helperInstaller -match 'self-test did not confirm administrator execution'
    )
    Add-Result "elevated_installer_closes" $(if ($ok) { "PASS" } else { "FAIL" }) "admin launcher waits, propagates exit code, and closes after installer exits"
} catch { Add-Result "elevated_installer_closes" "FAIL" $_.Exception.Message }

try {
    $configExample = Get-Content -LiteralPath (Join-Path $kit 'config.autonomy.example.toml') -Raw
    $ok = (
        $configExample -match 'approval_policy\s*=\s*"never"' -and
        $configExample -match 'sandbox_mode\s*=\s*"danger-full-access"' -and
        $configExample -match '(?s)\[windows\].*?sandbox\s*=\s*"elevated"' -and
        $configExample -match 'developer_instructions'
    )
    Add-Result "config_example_sanity" $(if ($ok) { "PASS" } else { "FAIL" }) "expected autonomy keys present"
} catch { Add-Result "config_example_sanity" "FAIL" $_.Exception.Message }

try {
    $setup = Get-Content -LiteralPath (Join-Path $kit 'Setup-Autonomy.ps1') -Raw
    $ok = (
        $setup -match 'Codex Desktop Autonomy Kit managed config' -and
        $setup -match 'custom config\.toml found; left unchanged' -and
        $setup -match 'manifest\.json' -and
        $setup -match 'helper script differs from repo copy' -and
        $setup -match '\[switch\]\$ConfigOnly' -and
        $setup -match '\[string\]\$CodexRoot' -and
        $setup -match '\[switch\]\$RefreshHelper'
    )
    Add-Result "setup_custom_config_guard" $(if ($ok) { "PASS" } else { "FAIL" }) "marker, staging manifest, custom guard, isolated root, helper refresh warning"
} catch { Add-Result "setup_custom_config_guard" "FAIL" $_.Exception.Message }

try {
    $version = '1.6.1'
    $surfaces = @(
        'README.md',
        'CHANGELOG.md',
        'Setup-Autonomy.ps1',
        'docs\index.html',
        'docs\USER-MANUAL.md'
    )
    $missingVersion = @()
    foreach ($surface in $surfaces) {
        $raw = Get-Content -LiteralPath (Join-Path $kit $surface) -Raw
        if ($raw -notmatch [regex]::Escape($version)) { $missingVersion += $surface }
    }
    $readme = Get-Content -LiteralPath (Join-Path $kit 'README.md') -Raw
    $manual = Get-Content -LiteralPath (Join-Path $kit 'docs\USER-MANUAL.md') -Raw
    $landing = Get-Content -LiteralPath (Join-Path $kit 'docs\index.html') -Raw
    $ok = (
        $missingVersion.Count -eq 0 -and
        $readme -notmatch 'Keep this repo private|private personal kit' -and
        $readme -match 'docs/assets/codex-autonomy-architecture\.svg' -and
        $manual -match 'assets/codex-autonomy-architecture\.svg' -and
        $landing -match 'assets/codex-autonomy-architecture\.svg'
    )
    Add-Result "public_docs_versioning" $(if ($ok) { "PASS" } else { "FAIL" }) $(if ($missingVersion.Count) { "missing version in: $($missingVersion -join ', ')" } else { "public docs include current version and architecture graphic" })
} catch { Add-Result "public_docs_versioning" "FAIL" $_.Exception.Message }

try {
    $tempRoot = Join-Path $env:TEMP ("codex-kit-configonly-" + [guid]::NewGuid().ToString("n"))
    $setupPath = Join-Path $kit 'Setup-Autonomy.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $setupPath -ConfigOnly -CodexRoot $tempRoot *> $null
    $config = Join-Path $tempRoot 'config.toml'
    $manifest = Join-Path $tempRoot 'autonomy-kit\manifest.json'
    $freshOk = (
        (Test-Path -LiteralPath $config) -and
        (Test-Path -LiteralPath $manifest) -and
        ((Get-Content -LiteralPath $config -Raw) -match 'Codex Desktop Autonomy Kit managed config')
    )
    & powershell -NoProfile -ExecutionPolicy Bypass -File $setupPath -ConfigOnly -CodexRoot $tempRoot *> $null
    $kitBackups = @(Get-ChildItem -LiteralPath $tempRoot -Filter 'config.toml.bak-*' -ErrorAction SilentlyContinue)
    $repeatKitOk = ($kitBackups.Count -eq 0)

    $customOk = $true
    $customDetail = @()
    $customShapes = [ordered]@{
        'trivial'                  = 'custom=true'
        'never-plus-core-heading'  = "approval_policy = `"never`"`ndeveloper_instructions = `"`"`"# Codex Desktop Autonomy Core (compact)`"`"`"`nuser_key = `"keep`""
        'never-plus-plugins'       = "approval_policy = `"never`"`n[plugins.`"x@openai-bundled`"]`nenabled = true"
        'marker-in-middle'         = "model = `"x`"`n# Codex Desktop Autonomy Kit managed config`napproval_policy = `"never`"`nuser_key = `"keep`""
        'kit-template-then-edited' = "# Codex Desktop Autonomy Kit managed config`napproval_policy = `"never`"`nsandbox_mode = `"danger-full-access`"`n[windows]`nsandbox = `"elevated`"`nuser_added = `"keep`""
        'full-customized'          = "model = `"deepseek-v4.1-flash:cloud`"`napproval_policy = `"never`"`n[desktop]`nappearanceTheme = `"dark`"`n[plugins.`"browser@openai-bundled`"]`nenabled = true"
    }
    foreach ($shapeName in $customShapes.Keys) {
        $marker = 'CONFIG-PRESERVE-MARKER'
        $body = $customShapes[$shapeName] + "`npreserve_marker = `"$marker`""
        Set-Content -LiteralPath $config -Value $body -Encoding UTF8 -NoNewline
        $hashBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $config).Hash
        $bakBefore = @(Get-ChildItem -LiteralPath $tempRoot -Filter 'config.toml.bak-*' -ErrorAction SilentlyContinue).Count
        & powershell -NoProfile -ExecutionPolicy Bypass -File $setupPath -ConfigOnly -CodexRoot $tempRoot *> $null
        $hashAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath $config).Hash
        $bakAfter = @(Get-ChildItem -LiteralPath $tempRoot -Filter 'config.toml.bak-*' -ErrorAction SilentlyContinue).Count
        $contentNow = Get-Content -LiteralPath $config -Raw
        # Must be byte-identical: not rewritten, not backed up-and-replaced.
        $preserved = ($hashBefore -eq $hashAfter) -and ($contentNow -match [regex]::Escape($marker)) -and ($bakAfter -eq $bakBefore)
        if (-not $preserved) { $customOk = $false; $customDetail += $shapeName }
    }

    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    Add-Result "setup_configonly_isolated" $(if ($freshOk -and $repeatKitOk -and $customOk) { "PASS" } else { "FAIL" }) "fresh isolated root writes kit config+manifest; repeat kit/custom configs avoid backup churn" $(if ($customOk) {} else { "  clobbered: $($customDetail -join ', ')" })
} catch {
    if ($tempRoot -and (Test-Path -LiteralPath $tempRoot)) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
    Add-Result "setup_configonly_isolated" "FAIL" $_.Exception.Message
}

try {
    $doctor = Get-Content -LiteralPath (Join-Path $kit 'Doctor-Autonomy.ps1') -Raw
    $ok = (
        $doctor -match 'duplicate top keys' -and
        $doctor -match 'helper script parity' -and
        $doctor -match 'STALE/modified' -and
        $doctor -match 'Is-WritableDir'
    )
    Add-Result "doctor_surface" $(if ($ok) { "PASS" } else { "FAIL" }) "config duplicate, staged freshness, helper parity, writable dirs"
} catch { Add-Result "doctor_surface" "FAIL" $_.Exception.Message }

try {
    $uninstall = Get-Content -LiteralPath (Join-Path $kit 'Uninstall-Autonomy.ps1') -Raw
    $ok = (
        $uninstall -match 'SupportsShouldProcess' -and
        $uninstall -match 'remove kit-managed config\.toml' -and
        $uninstall -match 'custom config\.toml found'
    )
    Add-Result "uninstall_safety" $(if ($ok) { "PASS" } else { "FAIL" }) "WhatIf support and kit-owned/custom distinction"
} catch { Add-Result "uninstall_safety" "FAIL" $_.Exception.Message }

try {
    $repoHelper = Join-Path $kit 'elevated-dev-helper\ElevatedDevHelper.ps1'
    $helper = Get-Content -LiteralPath $repoHelper -Raw
    $ok = (
        $helper -match 'Resolve-Winget' -and
        $helper -match 'ReadToEndAsync' -and
        $helper -match '\$env:USERPROFILE\\Documents\\Codex' -and
        $helper -match '--disable-interactivity'
    )
    Add-Result "helper_hardening" $(if ($ok) { "PASS" } else { "FAIL" }) "winget resolution, async pipe drain, portable roots, noninteractive flags"
} catch { Add-Result "helper_hardening" "FAIL" $_.Exception.Message }

try {
    # Helper root must be resolved via the install-time pointer, not a bare C:\dev literal.
    $setupRaw = Get-Content -LiteralPath (Join-Path $kit 'Setup-Autonomy.ps1') -Raw
    $doctorRaw = Get-Content -LiteralPath (Join-Path $kit 'Doctor-Autonomy.ps1') -Raw
    $instCmdRaw = Get-Content -LiteralPath (Join-Path $kit 'Install-Autonomy.cmd') -Raw
    $installerRaw = Get-Content -LiteralPath (Join-Path $kit 'elevated-dev-helper\Install-ElevatedDevHelper.ps1') -Raw
    $ok = (
        $installerRaw -match 'helper-root\.json' -and
        $setupRaw -match 'Resolve-HelperRoot' -and
        $setupRaw -match 'Resolve-HelperRoot' -and
        $doctorRaw -match 'helper-root\.json' -and
        $instCmdRaw -match 'helper-root\.json'
    )
    Add-Result "helper_root_coherence" $(if ($ok) { "PASS" } else { "FAIL" }) "installer writes a root pointer; Setup, Doctor, and the launcher all read it"
} catch { Add-Result "helper_root_coherence" "FAIL" $_.Exception.Message }

try {
    # Scheduled-task principal must come from the resolved identity, not bare $env:USERNAME.
    $helperRaw = Get-Content -LiteralPath (Join-Path $kit 'elevated-dev-helper\ElevatedDevHelper.ps1') -Raw
    $ok = (
        $helperRaw -match 'New-ScheduledTaskPrincipal -UserId \$taskUser' -and
        $helperRaw -match 'WindowsIdentity.*GetCurrent\(\)\.Name' -and
        $helperRaw -notmatch 'New-ScheduledTaskPrincipal -UserId \$env:USERNAME'
    )
    Add-Result "helper_task_principal" $(if ($ok) { "PASS" } else { "FAIL" }) "RegisterDevScheduledTask uses the resolved identity, not the bare account name"
} catch { Add-Result "helper_task_principal" "FAIL" $_.Exception.Message }

try {
    # Install steps must be individually guarded so one failure cannot abort config staging.
    $setupRaw = Get-Content -LiteralPath (Join-Path $kit 'Setup-Autonomy.ps1') -Raw
    # Each fragile install step must have its own named guard; a count threshold
    # would let one guard be removed without the check going red.
    $guards = @('Warn "Python install failed', 'Warn "uv install failed', 'Warn "scoop install failed', 'Warn "scoop install $pkg failed', 'Warn "Playwright install failed')
    $missingGuards = @($guards | Where-Object { $setupRaw -notmatch [regex]::Escape($_) })
    $ok = ($missingGuards.Count -eq 0)
    Add-Result "setup_step_isolation" $(if ($ok) { "PASS" } else { "FAIL" }) $(if ($ok) { "all $($guards.Count) install steps warn-and-continue" } else { "missing guard: $($missingGuards -join ', ')" })
} catch { Add-Result "setup_step_isolation" "FAIL" $_.Exception.Message }

try {
    $lic = Join-Path $kit 'LICENSE'
    Add-Result "license_present" $(if (Test-Path -LiteralPath $lic) { "PASS" } else { "FAIL" }) $(if (Test-Path -LiteralPath $lic) { "root LICENSE present" } else { "no root LICENSE" })
} catch { Add-Result "license_present" "FAIL" $_.Exception.Message }

try {
    $tmpA = Join-Path $env:TEMP ("codex-kit-agents-" + [guid]::NewGuid().ToString("n"))
    New-Item -ItemType Directory -Force -Path $tmpA | Out-Null
    $ownerText = "# OWNER-RULES-KEEP-ME`r`n`r`n- do not delete this`r`n"
    Set-Content -LiteralPath (Join-Path $tmpA "AGENTS.md") -Value $ownerText -Encoding UTF8 -NoNewline
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kit 'Setup-Autonomy.ps1') -ConfigOnly -CodexRoot $tmpA *> $null
    $agentsRaw = Get-Content -LiteralPath (Join-Path $tmpA "AGENTS.md") -Raw
    $ownerOk = ($agentsRaw -match 'OWNER-RULES-KEEP-ME') -and ($agentsRaw -match 'do not delete this')
    $ruleOk = ($agentsRaw -match 'Capability self-assessment')
    $skillOk = (Test-Path -LiteralPath (Join-Path $tmpA "skills\\capability-check\\SKILL.md"))
    $bakOk = (@(Get-ChildItem -LiteralPath $tmpA -Filter 'AGENTS.md.bak-*' -ErrorAction SilentlyContinue).Count -ge 1)
    $hashBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $tmpA "AGENTS.md")).Hash
    $bakBefore = @(Get-ChildItem -LiteralPath $tmpA -Filter 'AGENTS.md.bak-*' -ErrorAction SilentlyContinue).Count
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kit 'Setup-Autonomy.ps1') -ConfigOnly -CodexRoot $tmpA *> $null
    $hashAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $tmpA "AGENTS.md")).Hash
    $bakAfter = @(Get-ChildItem -LiteralPath $tmpA -Filter 'AGENTS.md.bak-*' -ErrorAction SilentlyContinue).Count
    $idem = ($hashBefore -eq $hashAfter) -and ($bakBefore -eq $bakAfter)
    Remove-Item -LiteralPath $tmpA -Recurse -ErrorAction SilentlyContinue
    $ok = $ownerOk -and $ruleOk -and $skillOk -and $bakOk -and $idem
    Add-Result "agents_rule_install" $(if ($ok) { "PASS" } else { "FAIL" }) "owner preserved=$ownerOk; rule=$ruleOk; skill=$skillOk; backup=$bakOk; idempotent=$idem"
} catch {
    if ($tmpA -and (Test-Path -LiteralPath $tmpA)) { Remove-Item -LiteralPath $tmpA -Recurse -ErrorAction SilentlyContinue }
    Add-Result "agents_rule_install" "FAIL" $_.Exception.Message
}

try {
    $tmpB = Join-Path $env:TEMP ("codex-kit-agents-fresh-" + [guid]::NewGuid().ToString("n"))
    New-Item -ItemType Directory -Force -Path $tmpB | Out-Null
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kit 'Setup-Autonomy.ps1') -ConfigOnly -CodexRoot $tmpB *> $null
    $freshRaw = Get-Content -LiteralPath (Join-Path $tmpB "AGENTS.md") -Raw -ErrorAction SilentlyContinue
    $ok = ($freshRaw -match 'Capability self-assessment') -and ($freshRaw -match 'capability-section begin')
    Remove-Item -LiteralPath $tmpB -Recurse -ErrorAction SilentlyContinue
    Add-Result "agents_rule_fresh" $(if ($ok) { "PASS" } else { "FAIL" }) "fresh root gains AGENTS.md with a marker-delimited capability rule"
} catch {
    if ($tmpB -and (Test-Path -LiteralPath $tmpB)) { Remove-Item -LiteralPath $tmpB -Recurse -ErrorAction SilentlyContinue }
    Add-Result "agents_rule_fresh" "FAIL" $_.Exception.Message
}

try {
    $skillInRepo = Join-Path $kit 'skills\\capability-check\\SKILL.md'
    $tmplInRepo = Join-Path $kit 'templates\\AGENTS-capability-section.md'
    $coreRaw = Get-Content -LiteralPath (Join-Path $kit 'CODEX-Desktop-Core.md') -Raw
    $ok = (Test-Path -LiteralPath $skillInRepo) -and (Test-Path -LiteralPath $tmplInRepo) -and ($coreRaw -match 'Capability self-assessment')
    Add-Result "capability_piece_shipped" $(if ($ok) { "PASS" } else { "FAIL" }) "skill, AGENTS template, and core-profile section present in repo"
} catch { Add-Result "capability_piece_shipped" "FAIL" $_.Exception.Message }

try {
    # Every public doc surface must actually describe the capability feature, not just
    # carry the version number. Guards against the feature drifting out of the docs.
    $readme  = Get-Content -LiteralPath (Join-Path $kit 'README.md') -Raw
    $manual  = Get-Content -LiteralPath (Join-Path $kit 'docs\USER-MANUAL.md') -Raw
    $landing = Get-Content -LiteralPath (Join-Path $kit 'docs\index.html') -Raw
    $surfaces = [ordered]@{ 'README.md' = $readme; 'USER-MANUAL.md' = $manual; 'index.html' = $landing }
    $missing = @()
    foreach ($name in $surfaces.Keys) {
        $raw = [string]$surfaces[$name]
        if ($raw -notmatch 'capability-check') { $missing += ("{0}:no-skill-name" -f $name) }
        if ($raw -notmatch 'capability self-assessment|Capability Self-Assessment|imagined') { $missing += ("{0}:no-feature-desc" -f $name) }
    }
    $ok = ($missing.Count -eq 0)
    Add-Result "docs_describe_capability_feature" $(if ($ok) { "PASS" } else { "FAIL" }) $(if ($ok) { "README, manual, and landing page all describe the capability feature" } else { "missing: $($missing -join ', ')" })
} catch { Add-Result "docs_describe_capability_feature" "FAIL" $_.Exception.Message }

try {
    # THE regression this project must never repeat. An earlier release classified a
    # config as kit-owned when it merely CONTAINED the Autonomy Core heading plus an
    # approval_policy="never" line, then replaced the whole file. That destroyed real
    # user configuration (model selection, appearance, plugins, hooks, project trust).
    # This test asserts the detection is anchored, not heuristic.
    $setupRaw = Get-Content -LiteralPath (Join-Path $kit 'Setup-Autonomy.ps1') -Raw
    $noHeuristic = -not ($setupRaw -match 'looksLikeOldKitConfig')
    $hasAnchor = ($setupRaw -match 'firstMeaningfulLine') -and ($setupRaw -match 'matchesGenerated')
    $ownerWarn = ($setupRaw -match 'has been modified since')
    $ok = $noHeuristic -and $hasAnchor -and $ownerWarn
    Add-Result "config_ownership_is_anchored" $(if ($ok) { "PASS" } else { "FAIL" }) "no unanchored ownership heuristic; requires exact template match or anchored marker; marked-but-edited configs are preserved"
} catch { Add-Result "config_ownership_is_anchored" "FAIL" $_.Exception.Message }

try {
    $repoFiles = @('CODEX-Desktop-Core.md','GEN5-Codex-Desktop-Autonomous-Software-Development.md','config.autonomy.example.toml')
    $hashes = @($repoFiles | ForEach-Object { "$_=$(Hash (Join-Path $kit $_))" })
    Add-Result "profile_hashes" "INFO" ($hashes -join '; ')
} catch { Add-Result "profile_hashes" "INFO" $_.Exception.Message }

""
$results | Format-Table -AutoSize | Out-String | Write-Host
$pass = @($results | Where-Object { $_.Status -eq "PASS" }).Count
$fail = @($results | Where-Object { $_.Status -eq "FAIL" }).Count
$infoCount = @($results | Where-Object { $_.Status -eq "INFO" }).Count
Write-Host ("SUMMARY: {0} PASS / {1} FAIL / {2} INFO" -f $pass, $fail, $infoCount)

if ($fail -gt 0) { exit 1 } else { exit 0 }

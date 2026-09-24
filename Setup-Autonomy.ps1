<#
.SYNOPSIS
    One-command toolchain + config bootstrap for the Codex Desktop Autonomy Kit on Windows.

.DESCRIPTION
    Installs common user-scope development tooling, stages the Codex autonomy profiles under
    ~/.codex/autonomy-kit, creates or refreshes kit-managed ~/.codex/config.toml, and offers
    the elevated helper installer if the helper task is missing.

    Existing customized config.toml is left unchanged. The kit files are staged for manual
    merge so setup is safe to re-run on machines with hand-edited Codex config.
#>
[CmdletBinding()]
param(
    [switch]$SkipConfig,
    [switch]$SkipBrowsers,
    [switch]$SkipHelper,
    [switch]$ForceConfig,
    [switch]$ConfigOnly,
    [string]$CodexRoot = "$env:USERPROFILE\.codex",
    [switch]$RefreshHelper
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$kit = $PSScriptRoot
$kitVersion = "1.8.0"
$configMarker = "# Codex Desktop Autonomy Kit managed config"
$agentsMarkerBegin = "<!-- Codex Desktop Autonomy Kit: capability-section begin -->"
$agentsMarkerEnd = "<!-- Codex Desktop Autonomy Kit: capability-section end -->"

# EN-2: pinned SHA-256 hashes for the two remote bootstrap scripts the kit executes.
# These are deliberate release pins. A missing or mismatched pin must refuse execution;
# never turn a network response into code merely because the installer was launched.
# Update deliberately when intentionally moving to a newer upstream installer, and
# record the new hash in the release notes.
$uvPinnedHash = "E08CFE98A992B95C04B5C8E8A3E61A5CF4565EF844C78770659A98BB8A4B1B31"
$scoopPinnedHash = "94F983B190438311E006B957DB7C8422709E0BA62A6C2AC04E278164108F2512"

function Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Note($m) { Write-Host "  $m" }
function Warn($m) { Write-Warning $m }
function Prepend-UserPath($dir) {
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return }
    $up = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($up -split ';') -notcontains $dir) {
        [Environment]::SetEnvironmentVariable('Path', "$dir;$up", 'User')
    }
    if (($env:Path -split ';') -notcontains $dir) { $env:Path = "$dir;$env:Path" }
}
function Backup-File {
    param(
        [string]$path,
        [string]$OwnershipManifestPath
    )
    if (Test-Path -LiteralPath $path) {
        $bak = "$path.bak-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
        Copy-Item -LiteralPath $path -Destination $bak -Force
        if ($OwnershipManifestPath) {
            $manifestDir = Split-Path -Parent $OwnershipManifestPath
            if ($manifestDir) { New-Item -ItemType Directory -Force -Path $manifestDir | Out-Null }
            $backupHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $bak).Hash
            [pscustomobject]@{
                schema_version = 1
                source_path = [System.IO.Path]::GetFullPath($path)
                backup_path = [System.IO.Path]::GetFullPath($bak)
                backup_sha256 = $backupHash
                created_utc = (Get-Date).ToUniversalTime().ToString("o")
            } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OwnershipManifestPath -Encoding UTF8
        }
        Note "backed up $(Split-Path -Leaf $path) -> $(Split-Path -Leaf $bak)"
        return $bak
    }
    return $null
}
function Get-FileHashText($path) {
    if (Test-Path -LiteralPath $path) { return (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash }
    return $null
}
function Install-AgentsCapabilityRule {
    # Append the capability self-assessment rule to the global AGENTS.md.
    # Discipline matches the config path: marker-delimited, append-if-absent,
    # back up before changing, and never rewrite content the kit did not author.
    param([string]$AgentsPath, [string]$TemplatePath)

    if (-not (Test-Path -LiteralPath $TemplatePath)) {
        Warn "capability rule template missing: $TemplatePath"
        return
    }
    $section = (Get-Content -LiteralPath $TemplatePath -Raw).TrimEnd()

    if (-not (Test-Path -LiteralPath $AgentsPath)) {
        $dir = Split-Path -Parent $AgentsPath
        if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        "$agentsMarkerBegin`r`n$section`r`n$agentsMarkerEnd" | Set-Content -LiteralPath $AgentsPath -Encoding UTF8
        Note "created AGENTS.md with the capability rule"
        return
    }

    $raw = Get-Content -LiteralPath $AgentsPath -Raw
    if ($raw -match [regex]::Escape($agentsMarkerBegin)) {
        $blockPattern = "(?s)" + [regex]::Escape($agentsMarkerBegin) + ".*?" + [regex]::Escape($agentsMarkerEnd)
        $existing = [regex]::Match($raw, $blockPattern).Value
        $desired = "$agentsMarkerBegin`r`n$section`r`n$agentsMarkerEnd"
        if ((Normalize-ConfigText $existing) -eq (Normalize-ConfigText $desired)) {
            Note "AGENTS.md capability rule already current"
        } else {
            Backup-File $AgentsPath
            $updated = [regex]::Replace($raw, $blockPattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $desired }, 1)
            Set-Content -LiteralPath $AgentsPath -Value $updated -Encoding UTF8 -NoNewline
            Note "refreshed AGENTS.md capability rule (kit-authored block only)"
        }
    } else {
        # EN-4: AGENTS.md is loaded into every session as high-priority instruction, so a
        # very large file risks crowding other content out of the instruction window.
        # Warn before growing it, and report the resulting size either way.
        $preBytes = (Get-Item -LiteralPath $AgentsPath).Length
        if ($preBytes -gt 20000) {
            Warn ("AGENTS.md is already {0} bytes; appending the capability rule will grow it further" -f $preBytes)
            Warn "consider whether every section is still earning its place in the instruction window"
        }
        Backup-File $AgentsPath
        $sep = if ($raw.EndsWith("`n")) { "" } else { "`r`n" }
        $updated = $raw + $sep + "`r`n" + "$agentsMarkerBegin`r`n$section`r`n$agentsMarkerEnd" + "`r`n"
        Set-Content -LiteralPath $AgentsPath -Value $updated -Encoding UTF8 -NoNewline
        $postBytes = (Get-Item -LiteralPath $AgentsPath).Length
        Note ("appended capability rule to existing AGENTS.md (your content preserved; {0} -> {1} bytes)" -f $preBytes, $postBytes)
    }
}
function Resolve-HelperInstall {
    # The install-time pointer is the source of truth for both a custom root and task.
    $pointer = Join-Path (Join-Path $CodexRoot "autonomy-kit") "helper-root.json"
    if (Test-Path -LiteralPath $pointer) {
        try {
            $p = Get-Content -LiteralPath $pointer -Raw | ConvertFrom-Json
            if ($p.install_root) {
                return [pscustomobject]@{
                    Root = [string]$p.install_root
                    TaskName = $(if ($p.task_name) { [string]$p.task_name } else { "CodexElevatedDevHelper" })
                    InvokerScript = $(if ($p.invoker_script) { [string]$p.invoker_script } else { Join-Path ([string]$p.install_root) "Invoke-ElevatedDevHelper.ps1" })
                }
            }
        } catch { }
    }
    return [pscustomobject]@{
        Root = "C:\dev\CodexElevatedHelper"
        TaskName = "CodexElevatedDevHelper"
        InvokerScript = "C:\dev\CodexElevatedHelper\Invoke-ElevatedDevHelper.ps1"
    }
}
function Invoke-HelperInstallerAndVerify {
    param(
        [Parameter(Mandatory=$true)][string]$InstallerPath,
        [Parameter(Mandatory=$true)][pscustomobject]$InstallInfo,
        [Parameter(Mandatory=$true)][string]$ExpectedHelperPath,
        [Parameter(Mandatory=$true)][string]$ExpectedInvokerPath,
        [switch]$NoElevation,
        [scriptblock]$TaskLookup = { param($name) Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue }
    )

    $start = @{ FilePath = $InstallerPath; Wait = $true; PassThru = $true }
    if (-not $NoElevation) { $start.Verb = "RunAs" }
    $process = Start-Process @start
    if ($process.ExitCode -ne 0) {
        throw "Elevated helper installer failed with exit code $($process.ExitCode): $InstallerPath"
    }

    $task = & $TaskLookup $InstallInfo.TaskName
    if (-not $task) {
        throw "Elevated helper installer exited successfully but task '$($InstallInfo.TaskName)' was not found."
    }

    $installedHelper = Join-Path $InstallInfo.Root "ElevatedDevHelper.ps1"
    $installedInvoker = $InstallInfo.InvokerScript
    $expectedHelperHash = Get-FileHashText $ExpectedHelperPath
    $expectedInvokerHash = Get-FileHashText $ExpectedInvokerPath
    $installedHelperHash = Get-FileHashText $installedHelper
    $installedInvokerHash = Get-FileHashText $installedInvoker
    if (-not $installedHelperHash -or $installedHelperHash -ne $expectedHelperHash) {
        throw "Elevated helper refresh did not install the expected helper at: $installedHelper"
    }
    if (-not $installedInvokerHash -or $installedInvokerHash -ne $expectedInvokerHash) {
        throw "Elevated helper refresh did not install the expected invoker at: $installedInvoker"
    }
    return $task
}
function Get-GeneratedConfig($coreText) {
    return @"
$configMarker
# version = "$kitVersion"

approval_policy = "never"
sandbox_mode = "danger-full-access"

[windows]
sandbox = "elevated"

developer_instructions = '''
$coreText
'''
"@
}
function Normalize-ConfigText($text) {
    if ($null -eq $text) { return "" }
    return (($text -replace "^\uFEFF", "") -replace "`r`n", "`n").TrimEnd()
}
function Write-GeneratedConfig($path, $coreText) {
    $toml = Get-GeneratedConfig -coreText $coreText
    $toml | Set-Content -LiteralPath $path -Encoding UTF8
}

# Tests can load the real resolver and installer-verification functions without
# executing setup's machine-changing body.
if ($env:CODEX_SETUP_SOURCE_ONLY -eq "1") { return }

if (-not $ConfigOnly) {
    Step "Python (user-scope) + python3 shim"
    $pyExe = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $pyExe) {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Warn "winget not found; install Python manually or install App Installer, then re-run."
        } else {
            try {
                winget install -e --id Python.Python.3.12 --scope user `
                    --accept-package-agreements --accept-source-agreements --disable-interactivity
            } catch {
                Warn "Python install failed: $($_.Exception.Message)"
            }
            $pyExe = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending | Select-Object -First 1
        }
    }
    if ($pyExe) {
        $pydir = $pyExe.Directory.FullName
        $py3 = Join-Path $pydir "python3.exe"
        if (-not (Test-Path -LiteralPath $py3)) { Copy-Item $pyExe.FullName $py3 -Force }
        Prepend-UserPath $pydir
        Prepend-UserPath (Join-Path $pydir "Scripts")
        Note "python: $(& $pyExe.FullName --version)"
    } else {
        Warn "Python unavailable; later Python-based setup steps may be skipped."
    }

    Step "uv"
    if (-not (Test-Path "$env:USERPROFILE\.local\bin\uv.exe")) {
        # EN-2: never pipe a remote script straight into the interpreter. Download to a
        # file, verify its SHA-256 against the release pin shipped in this repo, and only
        # then execute it. A missing or mismatched pin is a hard refusal.
        try {
            $uvUrl = "https://astral.sh/uv/install.ps1"
            $uvTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("uv-install-" + [guid]::NewGuid().ToString("n") + ".ps1")
            Invoke-WebRequest -UseBasicParsing -Uri $uvUrl -OutFile $uvTmp -ErrorAction Stop
            $uvHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $uvTmp).Hash
            if (-not $uvPinnedHash) {
                [System.IO.File]::Delete($uvTmp)
                Warn "uv installer has no SHA-256 pin - refused to run it"
            } elseif ($uvHash -ne $uvPinnedHash) {
                [System.IO.File]::Delete($uvTmp)
                Warn "uv installer hash mismatch - refused to run it. expected=$uvPinnedHash actual=$uvHash"
            } else {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $uvTmp
                [System.IO.File]::Delete($uvTmp)
            }
        } catch {
            Warn "uv install failed: $($_.Exception.Message)"
        }
    }
    Prepend-UserPath "$env:USERPROFILE\.local\bin"
    if (Test-Path "$env:USERPROFILE\.local\bin\uv.exe") {
        Note "uv: $(& "$env:USERPROFILE\.local\bin\uv.exe" --version 2>&1)"
    }

    Step "scoop"
    if (-not (Test-Path "$env:USERPROFILE\scoop\shims\scoop.ps1")) {
        # EN-2: download-then-verify rather than piping a live response into iex.
        # A missing or mismatched pin is a hard refusal.
        try {
            $scoopUrl = "https://get.scoop.sh"
            $scoopTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("scoop-install-" + [guid]::NewGuid().ToString("n") + ".ps1")
            Invoke-WebRequest -UseBasicParsing -Uri $scoopUrl -OutFile $scoopTmp -ErrorAction Stop
            $scoopHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $scoopTmp).Hash
            if (-not $scoopPinnedHash) {
                [System.IO.File]::Delete($scoopTmp)
                Warn "scoop installer has no SHA-256 pin - refused to run it"
            } elseif ($scoopHash -ne $scoopPinnedHash) {
                [System.IO.File]::Delete($scoopTmp)
                Warn "scoop installer hash mismatch - refused to run it. expected=$scoopPinnedHash actual=$scoopHash"
            } else {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $scoopTmp
                [System.IO.File]::Delete($scoopTmp)
            }
        } catch {
            Warn "scoop install failed: $($_.Exception.Message)"
        }
    }
    Prepend-UserPath "$env:USERPROFILE\scoop\shims"
    $scoop = "$env:USERPROFILE\scoop\shims\scoop.ps1"
    if (Test-Path -LiteralPath $scoop) {
        try { & $scoop bucket add main *> $null } catch { Warn "scoop bucket add failed: $($_.Exception.Message)" }
    } else {
        Warn "scoop unavailable; skipping tool installs that require it."
    }

    Step "core tools via scoop"
    $wanted = [ordered]@{ 'nodejs-lts' = 'node'; 'gh' = 'gh'; 'ripgrep' = 'rg'; 'jq' = 'jq'; 'sqlite' = 'sqlite3' }
    foreach ($pkg in $wanted.Keys) {
        $cmd = $wanted[$pkg]
        if (Get-Command $cmd -ErrorAction SilentlyContinue) {
            Note "$cmd already present - skip"
        } else {
            try {
                & $scoop install $pkg
            } catch {
                Warn "scoop install $pkg failed: $($_.Exception.Message)"
            }
        }
    }

    Step "Playwright"
    $py3cmd = (Get-Command python3 -ErrorAction SilentlyContinue).Source
    if (-not $py3cmd -and $pyExe) { $py3cmd = Join-Path $pyExe.Directory.FullName "python3.exe" }
    if ($py3cmd) {
        try {
            & $py3cmd -m pip install --quiet --upgrade playwright
            if (-not $SkipBrowsers) { & $py3cmd -m playwright install }
            Note "playwright: $(& $py3cmd -m playwright --version 2>&1)"
        } catch {
            Warn "Playwright install failed: $($_.Exception.Message)"
        }
    } else {
        Warn "python3 not found; skipped Playwright install."
    }
}

if (-not $SkipConfig) {
    Step "Codex config/profile staging"
    $cx = $CodexRoot
    $profileDir = Join-Path $cx "autonomy-kit"
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

    $stageFiles = @(
        "CODEX-Desktop-Core.md",
        "GEN5-Codex-Desktop-Autonomous-Software-Development.md",
        "config.autonomy.example.toml"
    )
    foreach ($f in $stageFiles) { Copy-Item -LiteralPath (Join-Path $kit $f) -Destination $profileDir -Force }
    @{
        kit_version = $kitVersion
        staged_at = (Get-Date).ToUniversalTime().ToString("o")
        files = @($stageFiles | ForEach-Object {
            [pscustomobject]@{
                name = $_
                sha256 = Get-FileHashText (Join-Path $kit $_)
            }
        })
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $profileDir "manifest.json") -Encoding UTF8
    Note "staged profiles under $profileDir"
    Install-AgentsCapabilityRule -AgentsPath (Join-Path $cx "AGENTS.md") -TemplatePath (Join-Path $kit "templates\AGENTS-capability-section.md")
    $skillSrc = Join-Path $kit "skills\capability-check"
    if (Test-Path -LiteralPath $skillSrc) {
        $skillDst = Join-Path $cx "skills\capability-check"
        New-Item -ItemType Directory -Force -Path $skillDst | Out-Null
        Copy-Item -LiteralPath (Join-Path $skillSrc "SKILL.md") -Destination $skillDst -Force
        Note "installed capability-check skill under $skillDst"
    } else {
        Warn "capability-check skill not found in kit: $skillSrc"
    }

    $config = Join-Path $cx "config.toml"
    $core = Get-Content -LiteralPath "$kit\CODEX-Desktop-Core.md" -Raw
    $generated = Get-GeneratedConfig -coreText $core
    if (-not (Test-Path -LiteralPath $config)) {
        Write-GeneratedConfig -path $config -coreText $core
        Note "created kit-managed config.toml"
    } else {
        $raw = Get-Content -LiteralPath $config -Raw

        # Ownership test. Only two things may be replaced:
        #   1. A file that matches the exact config this kit generates (byte-for-byte
        #      after normalization). This is the only positive proof of kit ownership.
        #   2. A file whose FIRST non-blank line is the kit marker. Anchored at the
        #      start, so a customized config that merely embeds the marker deeper in
        #      the file is not captured.
        #
        # History: an earlier version classified a config as kit-owned when it merely
        # CONTAINED the Autonomy Core heading and an approval_policy="never" line
        # anywhere in the file. That unanchored substring test matched ordinary
        # customized configs -- anyone using approval_policy="never" plus the core
        # profile as developer_instructions -- and the installer replaced the entire
        # file, destroying model selection, appearance, plugins, hooks, and project
        # trust. Never reintroduce a substring/heuristic ownership test here. The
        # consequence of a false positive is total config loss.
        $firstMeaningfulLine = ($raw -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1)
        $startsWithMarker = ($null -ne $firstMeaningfulLine) -and ($firstMeaningfulLine.Trim() -eq $configMarker)
        $matchesGenerated = ((Normalize-ConfigText $raw) -eq (Normalize-ConfigText $generated))

        # The marker proves the kit CREATED the file. It does not prove the user has
        # not edited it since. A marked file that the user extended must be preserved,
        # not silently replaced with the template -- that would discard their additions.
        #
        # So: replace only when the file is exactly the generated template, optionally
        # differing ONLY in the version comment line that setup itself maintains. A
        # marked-but-modified file is reported and left alone unless -ForceConfig.
        $markedButModified = $startsWithMarker -and (-not $matchesGenerated)
        $matchesPreviousKitRelease = $false
        if ($markedButModified) {
            # Tolerate only the kit's own "# version = "x.y.z"" line differing, which
            # is the one thing a version bump legitimately changes.
            $stripVersion = { param($t) (($t -replace '(?m)^\s*#\s*version\s*=\s*"[^"]*"\s*$', '# version = "(current)"')) }
            $a = & $stripVersion (Normalize-ConfigText $raw)
            $b = & $stripVersion (Normalize-ConfigText $generated)
            $matchesPreviousKitRelease = ($a -eq $b)
        }

        # $ForceConfig is an explicit, deliberate override and is the only way to
        # replace a config that the kit did not generate or that the user has edited.
        $isProvablyKitOwned = $matchesGenerated -or $matchesPreviousKitRelease

        # EN-3: -ForceConfig destroys whatever is in the file. Say so, and say what is
        # about to be lost, before doing it. This is the flag a user reaches for when
        # something looks stuck, so it must not be silent.
        if ($ForceConfig -and -not $isProvablyKitOwned) {
            $lostKeys = @()
            foreach ($mline in ($raw -split "`r?`n")) {
                $t = $mline.Trim()
                if ($t -and -not $t.StartsWith('#') -and $t -match '^([A-Za-z0-9_.-]+)\s*=') {
                    $lostKeys += $Matches[1]
                }
            }
            Warn "-ForceConfig will replace your existing config.toml"
            if ($lostKeys.Count) {
                Warn ("  top-level keys that will be LOST: " + (($lostKeys | Select-Object -Unique) -join ', '))
            } else {
                Warn "  the existing file will be replaced entirely"
            }
            Note ("  a timestamped backup is written first: " + (Join-Path (Split-Path -Parent $config) (Split-Path -Leaf $config)) + ".bak-<timestamp>")
        }

        if ($ForceConfig -or $isProvablyKitOwned) {
            if ((Normalize-ConfigText $raw) -eq (Normalize-ConfigText $generated)) {
                Note "kit-managed config.toml already current"
            } else {
                Backup-File $config (Join-Path $profileDir "config-backup-manifest.json")
                Write-GeneratedConfig -path $config -coreText $core
                Note "refreshed kit-managed config.toml"
            }
        } elseif ($markedButModified) {
            Warn "config.toml carries the kit marker but has been modified since (your edits detected)"
            Note "left unchanged to protect your additions"
            Note "to replace it with the kit template anyway, re-run with -ForceConfig"
            Note "merge staged files from $profileDir when ready"
        } else {
            Note "custom config.toml found; left unchanged (not kit-owned, so never replaced)"
            Note "merge staged files from $profileDir when ready"
        }
    }
}

if (-not $SkipHelper -and -not $ConfigOnly) {
    Step "elevated dev helper"
    $helperInstallInfo = Resolve-HelperInstall
    $helperTask = Get-ScheduledTask -TaskName $helperInstallInfo.TaskName -ErrorAction SilentlyContinue
    $helperInstall = Join-Path $kit "elevated-dev-helper\Install-ElevatedDevHelper-AsAdmin.cmd"
    $helperRoot = $helperInstallInfo.Root
    $installedHelper = Join-Path $helperRoot "ElevatedDevHelper.ps1"
    $installedInvoker = $helperInstallInfo.InvokerScript
    if ($helperTask) {
        Note "$($helperInstallInfo.TaskName) already installed ($($helperTask.State))"
        $repoHelperHash = Get-FileHashText (Join-Path $kit "elevated-dev-helper\ElevatedDevHelper.ps1")
        $repoInvokerHash = Get-FileHashText (Join-Path $kit "elevated-dev-helper\Invoke-ElevatedDevHelper.ps1")
        $installedHelperHash = Get-FileHashText $installedHelper
        $installedInvokerHash = Get-FileHashText $installedInvoker
        $helperStale = (-not $installedHelperHash) -or ($repoHelperHash -ne $installedHelperHash)
        $invokerStale = (-not $installedInvokerHash) -or ($repoInvokerHash -ne $installedInvokerHash)
        if ($helperStale -or $invokerStale) {
            if ($RefreshHelper) {
                Note "installed helper is stale or missing its invoker; launching refresh installer (Windows UAC prompt expected)..."
                $helperTask = Invoke-HelperInstallerAndVerify `
                    -InstallerPath $helperInstall `
                    -InstallInfo $helperInstallInfo `
                    -ExpectedHelperPath (Join-Path $kit "elevated-dev-helper\ElevatedDevHelper.ps1") `
                    -ExpectedInvokerPath (Join-Path $kit "elevated-dev-helper\Invoke-ElevatedDevHelper.ps1")
                Note "helper refresh verified: task and installed file hashes are current"
            } else {
                Warn "installed helper is stale or missing its invoker; run setup with -RefreshHelper or run elevated-dev-helper\Install-ElevatedDevHelper-AsAdmin.cmd"
            }
        }
    } elseif (Test-Path -LiteralPath $helperInstall) {
        Note "launching helper installer (Windows UAC prompt expected)..."
        $helperTask = Invoke-HelperInstallerAndVerify `
            -InstallerPath $helperInstall `
            -InstallInfo $helperInstallInfo `
            -ExpectedHelperPath (Join-Path $kit "elevated-dev-helper\ElevatedDevHelper.ps1") `
            -ExpectedInvokerPath (Join-Path $kit "elevated-dev-helper\Invoke-ElevatedDevHelper.ps1")
        Note "helper: installed and verified"
    } else {
        Warn "helper installer not found: $helperInstall"
    }
}

if (-not $ConfigOnly) {
    Step "Summary"
    foreach ($t in 'python3','pip','uv','scoop','node','npm','npx','gh','rg','jq','sqlite3') {
        $src = (Get-Command $t -ErrorAction SilentlyContinue).Source
        "{0,-10} {1}" -f $t, $(if ($src) { 'OK' } else { 'missing (open a new shell)' }) | Write-Host
    }
}

Write-Host "`nNEXT:" -ForegroundColor Green
Write-Host "  1. Restart Codex Desktop so PATH and config changes load."
Write-Host "  2. Inventory check anytime: powershell -File .\Doctor-Autonomy.ps1"
Write-Host "  3. If config.toml was custom, merge staged files from ~/.codex/autonomy-kit manually."

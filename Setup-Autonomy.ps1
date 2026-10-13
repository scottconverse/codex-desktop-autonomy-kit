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
    [switch]$RefreshHelper,
    [switch]$SkipCommandRules,
    [switch]$ForceCommandRules,
    [switch]$SkipReconcile
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$kit = $PSScriptRoot
$kitVersion = "2.0.0"
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

# --- Codex command rules -----------------------------------------------------
# Codex ships a built-in "dangerous command" classifier (force deletes and
# web-link openers). Under approval_policy="never" a match is refused outright
# with "rejected: blocked by policy"; the agent cannot ask, so it simply stops.
# An explicit execpolicy allow-rule overrides the classifier. This kit writes a
# dedicated, kit-owned rules file that allows every pattern the classifier would
# otherwise block, built from paths discovered on THIS machine (no hardcoded
# paths). Delete the file to restore Codex's built-in behavior.
$commandRulesMarker = "# Codex Desktop Autonomy Kit managed rules"
$commandRulesFileName = "autonomy-kit.rules"

function Get-CodexCommandRulesShellPaths {
    # Discover every PowerShell/cmd executable Codex might launch on this machine.
    # Returns absolute paths that exist, de-duplicated case-insensitively.
    param([string]$CodexRoot)
    $found = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    $add = {
        param([string]$p)
        if (-not $p) { return }
        try { $full = [System.IO.Path]::GetFullPath($p) } catch { return }
        if ((Test-Path -LiteralPath $full -PathType Leaf) -and $seen.Add($full)) { $found.Add($full) }
    }
    # 1. Shells Codex actually launched, from recent session logs (most reliable).
    $sessions = Join-Path $CodexRoot "sessions"
    if (Test-Path -LiteralPath $sessions) {
        $re = [regex]'(?i)"([A-Za-z]:(?:\\\\[^"\\]+)+\\\\(?:pwsh|powershell|cmd)\.exe)"'
        # Long-running sessions can leave very large logs; reading those whole would
        # stall setup. Skip any log over 20 MB -- the same shell paths appear in every
        # logged command, and sources 2-4 below cover shells independently.
        $logs = Get-ChildItem -LiteralPath $sessions -Recurse -Filter "*.jsonl" -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -le 20MB } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 25
        foreach ($log in $logs) {
            try { $raw = Get-Content -LiteralPath $log.FullName -Raw -ErrorAction Stop } catch { continue }
            foreach ($m in $re.Matches($raw)) { & $add ($m.Groups[1].Value -replace '\\\\', '\') }
        }
    }
    # 2. Codex bundled runtime pwsh; the wildcard tolerates a renamed runtime folder.
    foreach ($p in (Get-ChildItem -Path (Join-Path $env:USERPROFILE ".cache\codex-runtimes\*\dependencies\native\powershell\pwsh.exe") -ErrorAction SilentlyContinue)) { & $add $p.FullName }
    # 3. Shells on PATH.
    foreach ($name in @("pwsh", "powershell", "cmd")) {
        foreach ($c in (Get-Command $name -All -ErrorAction SilentlyContinue)) { if ($c.Source) { & $add $c.Source } }
    }
    # 4. Standard Windows locations, built from environment variables only.
    & $add (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\pwsh.exe")
    foreach ($p in (Get-ChildItem -Path (Join-Path $env:ProgramFiles "PowerShell\*\pwsh.exe") -ErrorAction SilentlyContinue)) { & $add $p.FullName }
    & $add (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe")
    & $add (Join-Path $env:SystemRoot "System32\cmd.exe")
    return , $found.ToArray()
}

function Get-CommandRulesText {
    # Build the full rules file text from discovered shell paths plus the fixed
    # command-name lists. A path-only prefix rule allows every script that shell
    # runs (covers the wrapper call the classifier checks when it cannot split a
    # script); the name rules match the decomposed simple commands.
    param([string[]]$ShellPaths, [string]$Version = $kitVersion)
    $esc = { param([string]$t) $t.Replace('\', '\\').Replace('"', '\"') }
    $deleteCommands = @('Remove-Item', 'ri', 'rm', 'del', 'erase', 'rd', 'rmdir')
    $linkOpeners = @('Start-Process', 'start', 'saps', 'Invoke-Item', 'ii',
        'explorer', 'explorer.exe', 'mshta', 'mshta.exe', 'rundll32', 'rundll32.exe',
        'chrome', 'chrome.exe', 'msedge', 'msedge.exe', 'firefox', 'firefox.exe',
        'iexplore', 'iexplore.exe')
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add($commandRulesMarker)
    $lines.Add("# version = ""$Version""")
    $lines.Add("#")
    $lines.Add("# These allow-rules switch OFF Codex's built-in dangerous-command list on this")
    $lines.Add("# machine (force deletes and web-link openers). Delete this file to restore the")
    $lines.Add("# built-in behavior. Generated by the Codex Desktop Autonomy Kit; do not hand-edit.")
    $lines.Add("")
    $lines.Add("# Shells Codex launches (absolute paths discovered on this machine). A path-only")
    $lines.Add("# prefix rule allows every script that shell runs, so new flags are covered too.")
    foreach ($p in $ShellPaths) { $lines.Add("prefix_rule(pattern=[""$(& $esc $p)""], decision=""allow"")") }
    $lines.Add("")
    $lines.Add("# Delete cmdlets/commands (match the decomposed simple command).")
    foreach ($c in $deleteCommands) { $lines.Add("prefix_rule(pattern=[""$(& $esc $c)""], decision=""allow"")") }
    $lines.Add("")
    $lines.Add("# Web-link openers (match the decomposed simple command).")
    foreach ($c in $linkOpeners) { $lines.Add("prefix_rule(pattern=[""$(& $esc $c)""], decision=""allow"")") }
    $lines.Add("")
    return ($lines -join "`r`n")
}

function Find-CodexCli {
    # Newest codex.exe across the two known install locations and PATH, or $null.
    $cands = New-Object System.Collections.Generic.List[object]
    foreach ($base in @((Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin"), (Join-Path $env:LOCALAPPDATA "Programs\CodexCLI"))) {
        if (Test-Path -LiteralPath $base) {
            foreach ($f in (Get-ChildItem -LiteralPath $base -Recurse -Filter "codex.exe" -ErrorAction SilentlyContinue)) { $cands.Add($f) }
        }
    }
    $onPath = Get-Command codex -ErrorAction SilentlyContinue
    if ($onPath -and $onPath.Source -and (Test-Path -LiteralPath $onPath.Source)) { $cands.Add((Get-Item -LiteralPath $onPath.Source)) }
    $cands | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}

function Test-CommandRulesAllow {
    # Return $true if Codex's own execpolicy checker says the command is allowed.
    param([string]$CodexExe, [string]$RulesPath, [string[]]$Argv)
    try {
        $out = & $CodexExe execpolicy check --rules $RulesPath @Argv 2>$null | Out-String
        return ($out -match '"decision"\s*:\s*"allow"')
    } catch { return $false }
}

function Write-NoBomUtf8 {
    # Codex's Starlark rules parser rejects a UTF-8 BOM (Windows PowerShell's
    # Set-Content -Encoding UTF8 writes one), so the rules file must be BOM-free.
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

function Write-CodexCommandRules {
    # Create or refresh the kit-owned command-rules file, with the same ownership
    # discipline as config.toml: create when absent; refresh only a file this kit
    # generated; never overwrite a file edited since (unless -Force); back up first;
    # validate with Codex's own checker and roll back on failure. Throws on a
    # validation failure so the caller can report it; the file is left safe either way.
    param([string]$CodexRoot, [switch]$Force)
    $rulesDir = Join-Path $CodexRoot "rules"
    New-Item -ItemType Directory -Force -Path $rulesDir | Out-Null
    $rulesPath = Join-Path $rulesDir $commandRulesFileName

    $shellPaths = Get-CodexCommandRulesShellPaths -CodexRoot $CodexRoot
    if (-not $shellPaths -or $shellPaths.Count -eq 0) {
        Warn "no PowerShell/cmd shells discovered; command-rules file not written"
        return
    }
    $generated = Get-CommandRulesText -ShellPaths $shellPaths

    if (-not (Test-Path -LiteralPath $rulesPath)) {
        Write-NoBomUtf8 -Path $rulesPath -Text $generated
        Note "wrote Codex command-rules: $rulesPath ($($shellPaths.Count) shells)"
    } else {
        $raw = Get-Content -LiteralPath $rulesPath -Raw
        $firstLine = ($raw -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1)
        $startsWithMarker = ($null -ne $firstLine) -and ($firstLine.Trim() -eq $commandRulesMarker)
        $matchesGenerated = ((Normalize-ConfigText $raw) -eq (Normalize-ConfigText $generated))
        $stripVersion = { param($t) ($t -replace '(?m)^\s*#\s*version\s*=\s*"[^"]*"\s*$', '# version = "(current)"') }
        $matchesPrevKit = $startsWithMarker -and ((& $stripVersion (Normalize-ConfigText $raw)) -eq (& $stripVersion (Normalize-ConfigText $generated)))

        if ($matchesGenerated) {
            Note "Codex command-rules already current"
            return
        }
        if ($startsWithMarker -or $Force) {
            if ($Force -and -not $startsWithMarker) {
                Warn "-ForceCommandRules will replace a non-kit $commandRulesFileName (backed up first)"
            } elseif (-not $matchesPrevKit) {
                Note "command-rules file was modified since the kit wrote it; refreshing (backup first)"
            }
            Backup-File $rulesPath | Out-Null
            Write-NoBomUtf8 -Path $rulesPath -Text $generated
            Note "refreshed Codex command-rules: $rulesPath ($($shellPaths.Count) shells)"
        } else {
            Warn "a non-kit $commandRulesFileName exists; left unchanged (use -ForceCommandRules to replace)"
            return
        }
    }

    # Validate with Codex's own checker. A broken rules file would stop every command
    # loading the rules, so a failed validation rolls back and reports rather than
    # leaving the file in place.
    $codex = Find-CodexCli
    if (-not $codex) {
        Warn "Codex CLI not found; command-rules written but NOT validated"
        return
    }
    $sampleShell = $shellPaths[0]
    $checks = @(
        @{ name = "script force-delete"; argv = @($sampleShell, "-Command", 'Get-ChildItem x | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }') }
        @{ name = "single force-delete"; argv = @("Remove-Item", "x", "-Recurse", "-Force") }
        @{ name = "link opener"; argv = @("Start-Process", "https://example.com") }
    )
    $bad = @($checks | Where-Object { -not (Test-CommandRulesAllow -CodexExe $codex -RulesPath $rulesPath -Argv $_.argv) } | ForEach-Object { $_.name })
    if ($bad.Count) {
        $bak = Get-ChildItem -LiteralPath $rulesDir -Filter "$commandRulesFileName.bak-*" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($bak) {
            Copy-Item -LiteralPath $bak.FullName -Destination $rulesPath -Force
            Warn "restored previous command-rules from $($bak.Name)"
        } else {
            Remove-Item -LiteralPath $rulesPath -Force
            Warn "removed the invalid command-rules file"
        }
        throw "Codex command-rules validation failed for: $($bad -join ', ')"
    }
    Note "command-rules validated (force-delete script + single, and link opener all allow)"
}

# --- Autonomy-key reconcile (v2.0.0) -----------------------------------------
# For an existing config the kit does not own, set ONLY the kit's autonomy keys
# in place and leave everything else -- every other key, table, comment, blank
# line, and the file's newline style -- byte-for-byte untouched. This is a
# surgical key-setter, never a whole-file rewrite; the v1.6.1 clobber bug was
# exactly a whole-file rewrite of a custom config, and this must never become one.
# developer_instructions is deliberately NOT managed here: the kit never injects
# or rewrites it on an existing config.
function Reconcile-AutonomyConfig {
    param([string]$Path, [string]$ManifestPath)

    $raw = Get-Content -LiteralPath $Path -Raw
    if ($null -eq $raw) { $raw = "" }
    $nl = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
    $endsWithNewline = $raw.EndsWith("`n")
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($l in ($raw -split "`r?`n")) { $lines.Add($l) }
    # A trailing newline makes the split yield one empty tail element; drop it so
    # inserts land correctly, then restore the trailing newline when writing.
    if ($endsWithNewline -and $lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq "") {
        $lines.RemoveAt($lines.Count - 1)
    }

    function Find-FirstTable([System.Collections.Generic.List[string]]$L) {
        for ($i = 0; $i -lt $L.Count; $i++) { if ($L[$i] -match '^\s*\[') { return $i } }
        return -1
    }

    $changes = New-Object System.Collections.Generic.List[string]

    # Top-level scalar keys must sit above the first table header in TOML, so only
    # that region is searched and inserts go just before the first table.
    foreach ($kv in @(
            @{ k = 'approval_policy'; v = 'never' },
            @{ k = 'sandbox_mode'; v = 'danger-full-access' })) {
        $k = $kv.k; $desired = "$($kv.k) = ""$($kv.v)"""
        $firstTable = Find-FirstTable $lines
        $limit = if ($firstTable -ge 0) { $firstTable } else { $lines.Count }
        $idx = -1
        for ($i = 0; $i -lt $limit; $i++) { if ($lines[$i] -match "^\s*$([regex]::Escape($k))\s*=") { $idx = $i; break } }
        if ($idx -ge 0) {
            if ($lines[$idx].Trim() -ne $desired) {
                $changes.Add("${k}: '$($lines[$idx].Trim())' -> '$desired'")
                $lines[$idx] = $desired
            }
        } else {
            $insertAt = if ($firstTable -ge 0) { $firstTable } else { $lines.Count }
            $lines.Insert($insertAt, $desired)
            $changes.Add("${k}: (absent) -> '$desired'")
        }
    }

    # [windows] sandbox = "elevated"
    $winIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\[windows\]\s*$') { $winIdx = $i; break } }
    if ($winIdx -ge 0) {
        $end = $lines.Count
        for ($i = $winIdx + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\[') { $end = $i; break } }
        $sIdx = -1
        for ($i = $winIdx + 1; $i -lt $end; $i++) { if ($lines[$i] -match '^\s*sandbox\s*=') { $sIdx = $i; break } }
        if ($sIdx -ge 0) {
            if ($lines[$sIdx].Trim() -ne 'sandbox = "elevated"') {
                $changes.Add("[windows] sandbox: '$($lines[$sIdx].Trim())' -> 'sandbox = ""elevated""'")
                $lines[$sIdx] = 'sandbox = "elevated"'
            }
        } else {
            $lines.Insert($winIdx + 1, 'sandbox = "elevated"')
            $changes.Add("[windows] sandbox: (absent) -> 'sandbox = ""elevated""'")
        }
    } else {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -ne '') { $lines.Add('') }
        $lines.Add('[windows]')
        $lines.Add('sandbox = "elevated"')
        $changes.Add("[windows] table added with sandbox = ""elevated""")
    }

    if ($changes.Count -eq 0) {
        return [pscustomobject]@{ Changed = $false; Changes = @() }
    }

    $out = ($lines -join $nl)
    if ($endsWithNewline) { $out += $nl }
    Backup-File $Path $ManifestPath | Out-Null
    Write-NoBomUtf8 -Path $Path -Text $out
    return [pscustomobject]@{ Changed = $true; Changes = @($changes) }
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
        } else {
            # Not doing a full-file write. The file is never wholesale-replaced here; at
            # most the kit reconciles its own autonomy keys in place (v2.0.0), leaving
            # every other key, table, comment, and formatting byte untouched.
            if ($markedButModified) {
                Warn "config.toml carries the kit marker but has been modified since (your edits detected)"
                Note "not replacing it; to overwrite with the kit template, re-run with -ForceConfig"
            } else {
                Note "custom config.toml found; not replacing it (your settings are preserved)"
            }
            if ($SkipReconcile) {
                Note "autonomy-key reconcile skipped (-SkipReconcile); merge staged files from $profileDir when ready"
            } else {
                $rc = Reconcile-AutonomyConfig -Path $config -ManifestPath (Join-Path $profileDir "config-backup-manifest.json")
                if ($rc.Changed) {
                    Note "reconciled autonomy keys in your existing config (backup written first):"
                    foreach ($c in $rc.Changes) { Note "    $c" }
                } else {
                    Note "autonomy keys already satisfied; config left unchanged"
                }
            }
        }
    }
}

if (-not $SkipConfig -and -not $SkipCommandRules) {
    Step "Codex command rules (switch off the built-in dangerous-command list)"
    # Isolated like the other install steps: if this one fails, the file has already
    # been rolled back inside the function, so warn and continue rather than abort.
    try {
        Write-CodexCommandRules -CodexRoot $CodexRoot -Force:$ForceCommandRules
    } catch {
        Warn "command rules step failed: $($_.Exception.Message)"
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
Write-Host "  1. Restart Codex Desktop, and start a NEW chat, so PATH, config, and command"
Write-Host "     rules all load (Codex reads its rules when a chat starts)."
Write-Host "  2. Inventory check anytime: powershell -File .\Doctor-Autonomy.ps1"
Write-Host "  3. The kit sets its own autonomy keys in a custom config.toml and leaves the rest"
Write-Host "     alone; pass -SkipReconcile to turn that off. developer_instructions is never"
Write-Host "     touched -- merge the staged profile from ~/.codex/autonomy-kit if you want it."

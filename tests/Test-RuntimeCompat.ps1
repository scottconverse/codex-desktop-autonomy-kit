<#
.SYNOPSIS
    Regression tests for runtime compatibility detection: the rules file existing (and
    its listed executables existing) must never be reported as covering the executable
    Codex actually launches.

.DESCRIPTION
    Every case runs against fixtures in a temp directory: a fake Codex root with fake
    session logs, a fake per-user cached runtime, and a fake versioned packaged runtime
    under a path containing spaces. No case reads or writes the real ~/.codex, and the
    package lookup and process table are injected, so results do not depend on what is
    installed on the host or on whether the suite itself is run from inside Codex.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$kit = Split-Path $PSScriptRoot -Parent
$results = New-Object System.Collections.Generic.List[object]
function Add-Result {
    param([string]$Name, [ValidateSet("PASS", "FAIL", "INFO")][string]$Status, [string]$Detail)
    $results.Add([pscustomobject]@{ Check = $Name; Status = $Status; Detail = $Detail })
}

$env:CODEX_SETUP_SOURCE_ONLY = "1"
try { . (Join-Path $kit "Setup-Autonomy.ps1") } finally { $env:CODEX_SETUP_SOURCE_ONLY = $null }

# --- Fixture helpers ---------------------------------------------------------
$fx = Join-Path $env:TEMP ("ckit-runtime-" + [guid]::NewGuid().ToString("n"))
# TEMP can be an 8.3 short path (C:\Users\RUNNER~1\...) and .NET expands short names
# once the directory exists. Create it and take the expanded form up front, so fixture
# paths compare equal to the full paths the code under test returns.
[System.IO.Directory]::CreateDirectory($fx) | Out-Null
$fx = [System.IO.Path]::GetFullPath($fx)
$rel = "dependencies\native\powershell\pwsh.exe"
function New-FakeExe([string]$Path) {
    [System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [System.IO.File]::WriteAllText($Path, "")
    return $Path
}
function New-Machine([string]$Name) {
    # One isolated fake machine: Codex root, cached runtime, two packaged runtimes.
    $m = Join-Path $fx $Name
    $pkgBase = Join-Path $m "Program Files\WindowsApps"
    [pscustomobject]@{
        Root      = (Join-Path $m "codex home")
        CacheRoot = (Join-Path $m "cache\codex-runtimes")
        OldExe    = (Join-Path $m "cache\codex-runtimes\codex-primary-runtime\$rel")
        PkgDir1   = (Join-Path $pkgBase "OpenAI.CodexPrimaryRuntime.v26-1110-778-0_26.1110.778.0_x64__fixture")
        PkgDir2   = (Join-Path $pkgBase "OpenAI.CodexPrimaryRuntime.v26-1111-574-0_26.1111.574.0_x64__fixture")
        NewExe1   = (Join-Path $pkgBase "OpenAI.CodexPrimaryRuntime.v26-1110-778-0_26.1110.778.0_x64__fixture\$rel")
        NewExe2   = (Join-Path $pkgBase "OpenAI.CodexPrimaryRuntime.v26-1111-574-0_26.1111.574.0_x64__fixture\$rel")
    }
}
function Write-Rules([object]$M, [string[]]$Shells, [datetime]$WrittenUtc) {
    $dir = Join-Path $M.Root "rules"
    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    $path = Join-Path $dir "autonomy-kit.rules"
    Write-NoBomUtf8 -Path $path -Text (Get-CommandRulesText -ShellPaths $Shells)
    [System.IO.File]::SetLastWriteTimeUtc($path, $WrittenUtc)
    return $path
}
function Write-Session {
    # A session log in the shape Codex writes: one JSON object per line, launches as
    # item_completed/CommandExecution records whose command[0] is the executable.
    param([object]$M, [string]$Name, [datetime]$StartUtc, [string[]]$Launches = @(), [string[]]$ExtraLines = @())
    $dir = Join-Path $M.Root "sessions\2026\11"
    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
    $path = Join-Path $dir "$Name.jsonl"
    $ts = { param([datetime]$d) $d.ToString("yyyy-MM-ddTHH:mm:ss.fffZ") }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('{"timestamp":"' + (& $ts $StartUtc) + '","type":"session_meta","payload":{"originator":"Codex Desktop"}}')
    $i = 0
    foreach ($exe in $Launches) {
        $i++
        $q = ConvertTo-Json -InputObject ([string]$exe) -Compress   # JSON string, escaped as logs store it
        $lines.Add('{"timestamp":"' + (& $ts $StartUtc.AddSeconds(10 * $i)) + '","type":"event_msg","payload":{"type":"item_completed","item":{"type":"CommandExecution","id":"exec-' + $i + '","process_id":"' + $i + '","command":[' + $q + ',"-Command","Get-Date"],"status":"completed","exit_code":0}}}')
    }
    foreach ($x in $ExtraLines) { $lines.Add($x) }
    [System.IO.File]::WriteAllLines($path, $lines.ToArray(), (New-Object System.Text.UTF8Encoding $false))
    [System.IO.File]::SetLastWriteTimeUtc($path, $StartUtc.AddMinutes(5))
    return $path
}
function Get-Health([object]$M, [object[]]$Installed = @()) {
    # ProcessTable is pinned empty so a suite run from inside Codex cannot leak the
    # host's real process ancestry into a fixture result.
    $active = Get-CodexActiveRuntime -CodexRoot $M.Root -ProcessTable @()
    Get-CodexRuntimeHealth -CodexRoot $M.Root -ActiveRuntime $active -InstalledRuntimes $Installed
}
function Invoke-Case([string]$Name, [scriptblock]$Body) {
    try { & $Body } catch { Add-Result $Name "FAIL" ("threw: " + $_.Exception.Message) }
}
$t0 = [datetime]::SpecifyKind([datetime]"2026-11-11T10:00:00", [DateTimeKind]::Utc)

# --- 1. Both old and new executable paths exist ------------------------------
# The reported defect: rules list the cached runtime, Codex launches the packaged one,
# both files exist. "Everything listed exists" must not be read as coverage.
Invoke-Case "both_paths_exist_is_mismatch" {
    $m = New-Machine "both"
    New-FakeExe $m.OldExe | Out-Null; New-FakeExe $m.NewExe1 | Out-Null
    Write-Rules $m @($m.OldExe) $t0 | Out-Null
    Write-Session $m "s1" $t0.AddHours(20) @($m.NewExe1, $m.NewExe1) | Out-Null
    $h = Get-Health $m
    $allListedExist = (@($h.Configured | Where-Object { -not $_.Exists }).Count -eq 0)
    $ok = $allListedExist -and $h.Active.Status -eq "KNOWN" -and $h.Active.Path -eq $m.NewExe1 -and
        $h.Active.Exists -and $h.Match -eq "MISMATCH" -and $h.Overall -eq "MISMATCH"
    Add-Result "both_paths_exist_is_mismatch" $(if ($ok) { "PASS" } else { "FAIL" }) "listedExist=$allListedExist active=$($h.Active.Status) match=$($h.Match) overall=$($h.Overall)"
}

# --- 2. A versioned packaged runtime replaces the cached runtime -------------
# The cached runtime is gone. That is a MISSING configured executable, reported as
# its own fact, in addition to (not instead of) the mismatch.
Invoke-Case "packaged_runtime_replaces_cache" {
    $m = New-Machine "replace"
    New-FakeExe $m.NewExe1 | Out-Null
    Write-Rules $m @($m.OldExe) $t0 | Out-Null
    Write-Session $m "s1" $t0.AddHours(20) @($m.NewExe1) | Out-Null
    $h = Get-Health $m
    $missing = @($h.Configured | Where-Object { -not $_.Exists })
    $ok = $missing.Count -eq 1 -and $missing[0].Path -eq $m.OldExe -and $h.Match -eq "MISMATCH" -and $h.Overall -eq "MISMATCH"
    Add-Result "packaged_runtime_replaces_cache" $(if ($ok) { "PASS" } else { "FAIL" }) "missingConfigured=$($missing.Count) match=$($h.Match) overall=$($h.Overall)"
}

# --- 3. Discovery finds an installed packaged runtime no session has used ----
# Before this fix a packaged runtime entered discovery only after a session logged
# it, so regenerated rules were always one runtime update behind.
Invoke-Case "discovery_includes_unused_packaged_runtime" {
    $m = New-Machine "discover"
    New-FakeExe $m.OldExe | Out-Null; New-FakeExe $m.NewExe1 | Out-Null; New-FakeExe $m.NewExe2 | Out-Null
    [System.IO.Directory]::CreateDirectory($m.Root) | Out-Null
    $pkgs = @(
        [pscustomobject]@{ InstallLocation = $m.PkgDir1; Version = "26.1110.778.0" },
        [pscustomobject]@{ InstallLocation = $m.PkgDir2; Version = "26.1111.574.0" },
        [pscustomobject]@{ InstallLocation = (Join-Path $fx "no-such-package"); Version = "0" }
    )
    $lookup = { $pkgs }.GetNewClosure()
    $found = Get-CodexCommandRulesShellPaths -CodexRoot $m.Root -CacheRoot $m.CacheRoot -PackageLookup $lookup
    $installed = Get-CodexInstalledRuntimeShells -CacheRoot $m.CacheRoot -PackageLookup $lookup
    # A lookup that throws (no Appx support) must degrade to cache-only, not fail.
    $degraded = Get-CodexInstalledRuntimeShells -CacheRoot $m.CacheRoot -PackageLookup { throw "no appx here" }
    $ok = (@($found) -contains $m.OldExe) -and (@($found) -contains $m.NewExe1) -and (@($found) -contains $m.NewExe2) -and
        (@($installed).Count -eq 3) -and (@($degraded).Count -eq 1) -and ($degraded[0].Kind -eq "cache")
    Add-Result "discovery_includes_unused_packaged_runtime" $(if ($ok) { "PASS" } else { "FAIL" }) "old=$(@($found) -contains $m.OldExe) v1110=$(@($found) -contains $m.NewExe1) v1111=$(@($found) -contains $m.NewExe2) installed=$(@($installed).Count) degraded=$(@($degraded).Count)"
}

# --- 4. Paths containing spaces round-trip through rules and logs ------------
Invoke-Case "paths_with_spaces" {
    $m = New-Machine "spaces dir with  two spaces"
    New-FakeExe $m.NewExe1 | Out-Null
    $rules = Write-Rules $m @($m.NewExe1) $t0
    Write-Session $m "s1" $t0.AddHours(1) @($m.NewExe1) | Out-Null
    $parsed = Get-CommandRulesConfiguredShells -RulesText (Get-Content -LiteralPath $rules -Raw)
    $h = Get-Health $m
    $ok = ($m.NewExe1 -match ' ') -and (@($parsed).Count -eq 1) -and ($parsed[0] -eq $m.NewExe1) -and
        $h.Active.Path -eq $m.NewExe1 -and $h.Match -eq "MATCH" -and $h.Overall -eq "PASS"
    Add-Result "paths_with_spaces" $(if ($ok) { "PASS" } else { "FAIL" }) "parsedRoundTrip=$($parsed[0] -eq $m.NewExe1) active=$($h.Active.Path -eq $m.NewExe1) match=$($h.Match) overall=$($h.Overall)"
}

# --- 5. Custom installation roots --------------------------------------------
# A non-default Codex root: evidence and rules are read from THAT root only, and
# Doctor run against it reports that root's verdict.
Invoke-Case "custom_install_root" {
    $m = New-Machine "custom"
    New-FakeExe $m.OldExe | Out-Null; New-FakeExe $m.NewExe1 | Out-Null
    Write-Rules $m @($m.OldExe) $t0 | Out-Null
    Write-Session $m "s1" $t0.AddHours(2) @($m.NewExe1) | Out-Null
    $h = Get-Health $m
    $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kit "Doctor-Autonomy.ps1") -CodexRoot $m.Root 2>&1 | Out-String -Width 500)
    $doctorMismatch = ($out -match '(?m)^overall\s+MISMATCH\s*$') -and ($out -match '(?m)^active runtime\s+KNOWN\s*$') -and ($out -match [regex]::Escape($m.NewExe1))
    $ok = $h.Overall -eq "MISMATCH" -and $h.RulesPath.StartsWith($m.Root) -and $doctorMismatch
    Add-Result "custom_install_root" $(if ($ok) { "PASS" } else { "FAIL" }) "health=$($h.Overall) doctorReportsRootVerdict=$doctorMismatch"
}

# --- 6. Unknown active runtime is UNKNOWN, never PASS ------------------------
Invoke-Case "unknown_active_runtime" {
    # (a) no session logs at all, rules present and every listed executable exists
    $a = New-Machine "unk-a"
    New-FakeExe $a.OldExe | Out-Null
    Write-Rules $a @($a.OldExe) $t0 | Out-Null
    $ha = Get-Health $a
    # (b) newest session ran no commands; an older session did. Old evidence is shown
    #     but must not be promoted to a known current runtime.
    $b = New-Machine "unk-b"
    New-FakeExe $b.OldExe | Out-Null
    Write-Rules $b @($b.OldExe) $t0 | Out-Null
    Write-Session $b "older" $t0.AddHours(1) @($b.OldExe) | Out-Null
    Write-Session $b "newest" $t0.AddHours(30) @() | Out-Null
    $hb = Get-Health $b
    $olderShown = [bool](@($hb.Active.Evidence) -match 'OLDER session')
    # (c) newest log too large to read
    $c = New-Machine "unk-c"
    New-FakeExe $c.OldExe | Out-Null
    Write-Rules $c @($c.OldExe) $t0 | Out-Null
    Write-Session $c "s1" $t0.AddHours(1) @($c.OldExe) | Out-Null
    $ac = Get-CodexActiveRuntime -CodexRoot $c.Root -ProcessTable @() -MaxBytes 10
    $hc = Get-CodexRuntimeHealth -CodexRoot $c.Root -ActiveRuntime $ac -InstalledRuntimes @()
    # (d) the last-launched executable has since been removed
    $d = New-Machine "unk-d"
    Write-Rules $d @($d.OldExe) $t0 | Out-Null
    Write-Session $d "s1" $t0.AddHours(1) @($d.OldExe) | Out-Null
    $hd = Get-Health $d
    # (e) Doctor prints UNKNOWN, not PASS, for case (a)
    $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kit "Doctor-Autonomy.ps1") -CodexRoot $a.Root 2>&1 | Out-String -Width 500)
    $doctorUnknown = ($out -match '(?m)^overall\s+UNKNOWN\s*$') -and ($out -notmatch '(?m)^overall\s+PASS')
    $ok = $ha.Overall -eq "UNKNOWN" -and $ha.Match -eq "UNKNOWN" -and $ha.Reload -eq "UNKNOWN" -and
        $hb.Overall -eq "UNKNOWN" -and $hb.Active.Status -eq "UNKNOWN" -and $olderShown -and
        $hc.Overall -eq "UNKNOWN" -and $hd.Overall -eq "UNKNOWN" -and ($hd.Active.Exists -eq $false) -and $doctorUnknown
    Add-Result "unknown_active_runtime" $(if ($ok) { "PASS" } else { "FAIL" }) "noLogs=$($ha.Overall) newestHasNoLaunch=$($hb.Overall) olderEvidenceShown=$olderShown oversize=$($hc.Overall) removedExe=$($hd.Overall) doctor=$doctorUnknown"
}

# --- 7. Stale configuration vs configuration loaded by a new session ---------
Invoke-Case "stale_vs_loaded_session" {
    # Stale: the rules were (re)written AFTER the evidenced session started. They list
    # the right executable, but that session started with the older rules.
    $s = New-Machine "stale"
    New-FakeExe $s.NewExe1 | Out-Null
    Write-Session $s "s1" $t0.AddHours(1) @($s.NewExe1) | Out-Null
    Write-Rules $s @($s.NewExe1) $t0.AddHours(2) | Out-Null
    $hs = Get-Health $s
    # Loaded: a newer session started after the rules were written.
    Write-Session $s "s2" $t0.AddHours(3) @($s.NewExe1) | Out-Null
    $hl = Get-Health $s
    $ok = $hs.Match -eq "MATCH" -and $hs.Reload -eq "REQUIRED" -and $hs.Overall -eq "RELOAD_REQUIRED" -and
        $hl.Match -eq "MATCH" -and $hl.Reload -eq "NOT_REQUIRED" -and $hl.Overall -eq "PASS"
    Add-Result "stale_vs_loaded_session" $(if ($ok) { "PASS" } else { "FAIL" }) "stale: reload=$($hs.Reload) overall=$($hs.Overall); new session: reload=$($hl.Reload) overall=$($hl.Overall)"
}

# --- 8. Repeated setup and diagnostic runs -----------------------------------
Invoke-Case "repeated_runs_are_stable" {
    $m = New-Machine "repeat"
    New-FakeExe $m.OldExe | Out-Null; New-FakeExe $m.NewExe1 | Out-Null
    Write-Session $m "s1" $t0.AddHours(1) @($m.NewExe1) | Out-Null
    # Setup's rules writer, twice: second run must be a no-op (no rewrite, no backup),
    # so re-running setup cannot by itself flip the reload verdict.
    Write-CodexCommandRules -CodexRoot $m.Root *> $null
    $rules = Join-Path $m.Root "rules\autonomy-kit.rules"
    [System.IO.File]::SetLastWriteTimeUtc($rules, $t0)
    $hash1 = (Get-FileHash -Algorithm SHA256 -LiteralPath $rules).Hash
    Write-CodexCommandRules -CodexRoot $m.Root *> $null
    $rewritten = ((Get-Item -LiteralPath $rules).LastWriteTimeUtc -ne $t0) -or ((Get-FileHash -Algorithm SHA256 -LiteralPath $rules).Hash -ne $hash1)
    $backups = @(Get-ChildItem -LiteralPath (Join-Path $m.Root "rules") -Filter "*.bak-*" -ErrorAction SilentlyContinue).Count
    # Diagnostics, twice: identical verdicts, and Doctor leaves every file untouched.
    $snap = { (Get-ChildItem -LiteralPath $m.Root -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)" }) -join "`n" }
    $before = & $snap
    $h1 = Get-Health $m; $h2 = Get-Health $m
    $d1 = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kit "Doctor-Autonomy.ps1") -CodexRoot $m.Root 2>&1 | Out-String -Width 500)
    $d2 = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kit "Doctor-Autonomy.ps1") -CodexRoot $m.Root 2>&1 | Out-String -Width 500)
    $after = & $snap
    $pick = { param($t) ([regex]::Match($t, '(?m)^overall\s+(\S+)')).Groups[1].Value }
    $sameVerdict = ($h1.Overall -eq $h2.Overall) -and ($h1.Match -eq $h2.Match) -and ((& $pick $d1) -eq (& $pick $d2)) -and ((& $pick $d1) -ne "")
    $ok = (-not $rewritten) -and ($backups -eq 0) -and $sameVerdict -and ($before -eq $after)
    Add-Result "repeated_runs_are_stable" $(if ($ok) { "PASS" } else { "FAIL" }) "setupRewrote=$rewritten backups=$backups sameVerdict=$sameVerdict doctorLeftFilesUntouched=$($before -eq $after)"
}

# --- 9. A policy rejection is its own fact ------------------------------------
# A rejection in the log must be counted, must not change the coverage verdict, and
# must not be confused with prose that merely quotes the phrase. Nothing regenerates
# or widens the rules in response.
Invoke-Case "policy_rejection_reported_separately" {
    $m = New-Machine "reject"
    New-FakeExe $m.NewExe1 | Out-Null
    $rules = Write-Rules $m @($m.NewExe1) $t0
    $rulesHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $rules).Hash
    $ts = $t0.AddHours(1).AddMinutes(1).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $real = '{"timestamp":"' + $ts + '","type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"c1","output":[{"type":"input_text","text":"Script failed\nexec_command failed: CreateProcess { message: \"Rejected(\\\"`pwsh.exe -Command x` rejected: blocked by policy\\\")\" }"}]}}'
    $prose = '{"timestamp":"' + $ts + '","type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"c2","output":[{"type":"input_text","text":"docs say: a policy veto (`rejected: blocked by policy`) ... message: \"Rejected(... rejected: blocked by policy)\""}]}}'
    Write-Session $m "s1" $t0.AddHours(1) @($m.NewExe1) @($real, $prose) | Out-Null
    $h = Get-Health $m
    $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kit "Doctor-Autonomy.ps1") -CodexRoot $m.Root 2>&1 | Out-String -Width 500)
    $doctorSeparate = ($out -match '(?m)^policy rejections \(that session\)\s+1;') -and ($out -match '(?m)^overall\s+PASS\s*$')
    $unchanged = ((Get-FileHash -Algorithm SHA256 -LiteralPath $rules).Hash -eq $rulesHash)
    $ok = $h.Active.RejectionCount -eq 1 -and $h.Match -eq "MATCH" -and $h.Overall -eq "PASS" -and $doctorSeparate -and $unchanged
    Add-Result "policy_rejection_reported_separately" $(if ($ok) { "PASS" } else { "FAIL" }) "rejections=$($h.Active.RejectionCount) (want 1; quoted prose excluded) coverage=$($h.Overall) doctorSeparate=$doctorSeparate rulesUnchanged=$unchanged"
}

# --- 10. Process ancestry identifies the live session's executable -----------
Invoke-Case "process_tree_active_runtime" {
    $m = New-Machine "ptree"
    New-FakeExe $m.OldExe | Out-Null; New-FakeExe $m.NewExe2 | Out-Null
    # Logs still show the old executable; the live process tree shows the new one.
    Write-Session $m "s1" $t0.AddHours(1) @($m.OldExe) | Out-Null
    $table = @(
        [pscustomobject]@{ ProcessId = 10; ParentProcessId = 1;  Name = "Codex.exe";      ExecutablePath = "C:\x\Codex.exe" },
        [pscustomobject]@{ ProcessId = 20; ParentProcessId = 10; Name = "codex.exe";      ExecutablePath = "C:\x\resources\codex.exe" },
        [pscustomobject]@{ ProcessId = 30; ParentProcessId = 20; Name = "pwsh.exe";       ExecutablePath = $m.NewExe2 },
        [pscustomobject]@{ ProcessId = 40; ParentProcessId = 30; Name = "powershell.exe"; ExecutablePath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" }
    )
    $live = Get-CodexActiveRuntime -CodexRoot $m.Root -ProcessTable $table -StartPid 40
    # Not under Codex at all: falls back to the session log.
    $plain = Get-CodexActiveRuntime -CodexRoot $m.Root -ProcessTable @($table[3]) -StartPid 40
    $ok = $live.Status -eq "KNOWN" -and $live.Source -eq "process-tree" -and $live.Path -eq $m.NewExe2 -and
        $plain.Source -eq "session-log" -and $plain.Path -eq $m.OldExe
    Add-Result "process_tree_active_runtime" $(if ($ok) { "PASS" } else { "FAIL" }) "live=$($live.Source):$($live.Path -eq $m.NewExe2) fallback=$($plain.Source):$($plain.Path -eq $m.OldExe)"
}

# --- 11. Only structured launches count as evidence --------------------------
Invoke-Case "prose_path_is_not_a_launch" {
    $m = New-Machine "prose"
    New-FakeExe $m.OldExe | Out-Null; New-FakeExe $m.NewExe1 | Out-Null
    $q = ConvertTo-Json -InputObject ([string]$m.NewExe1) -Compress
    $mention = '{"timestamp":"2026-11-11T12:00:00.000Z","type":"response_item","payload":{"type":"message","content":[{"type":"output_text","text":' + $q + '}]}}'
    Write-Session $m "s1" $t0.AddHours(1) @() @($mention) | Out-Null
    $a = Get-CodexActiveRuntime -CodexRoot $m.Root -ProcessTable @()
    Add-Result "prose_path_is_not_a_launch" $(if ($a.Status -eq "UNKNOWN" -and -not $a.Path) { "PASS" } else { "FAIL" }) "status=$($a.Status) path=$($a.Path)"
}

# --- 12. No rules file --------------------------------------------------------
Invoke-Case "no_rules_file" {
    $m = New-Machine "norules"
    New-FakeExe $m.NewExe1 | Out-Null
    Write-Session $m "s1" $t0.AddHours(1) @($m.NewExe1) | Out-Null
    $h = Get-Health $m
    Add-Result "no_rules_file" $(if ($h.Overall -eq "NOT_INSTALLED" -and -not $h.RulesPresent) { "PASS" } else { "FAIL" }) "overall=$($h.Overall)"
}

# --- 13. Shipped guidance does not coach around a rejection ------------------
# The kit's instruction surfaces are loaded into an agent's context. They must not
# tell it to respell or reroute a command that Codex's policy rejected.
Invoke-Case "guidance_does_not_coach_evasion" {
    $surfaces = @('README.md', 'CODEX-Desktop-Core.md', 'docs\BLOCKED-BY-POLICY.md', 'docs\USER-MANUAL.md',
        'docs\index.html', 'skills\capability-check\SKILL.md', 'templates\AGENTS-capability-section.md', 'Doctor-Autonomy.ps1')
    $banned = @('spelling problem', 'reformat and retry', 'keep moving', 'without `-Force`',
        'non-force delete', 'permitted command form', 'is not blocked')
    $hits = @()
    foreach ($s in $surfaces) {
        $raw = Get-Content -LiteralPath (Join-Path $kit $s) -Raw
        foreach ($b in $banned) { if ($raw -match [regex]::Escape($b)) { $hits += "${s}: '$b'" } }
    }
    Add-Result "guidance_does_not_coach_evasion" $(if ($hits.Count -eq 0) { "PASS" } else { "FAIL" }) $(if ($hits.Count) { $hits -join "; " } else { "no respell/reroute advice in $($surfaces.Count) shipped surfaces" })
}

if (Test-Path -LiteralPath $fx) { [System.IO.Directory]::Delete($fx, $true) }

""
$results | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host
$pass = @($results | Where-Object { $_.Status -eq "PASS" }).Count
$fail = @($results | Where-Object { $_.Status -eq "FAIL" }).Count
$info = @($results | Where-Object { $_.Status -eq "INFO" }).Count
Write-Host ("SUMMARY: {0} PASS / {1} FAIL / {2} INFO" -f $pass, $fail, $info)
if ($fail -gt 0) { exit 1 } else { exit 0 }

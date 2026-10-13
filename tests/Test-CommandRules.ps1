<#
.SYNOPSIS
    Behavioral tests for the Codex command-rules feature: machine-independent shell
    discovery, BOM-free generation, ownership, validation, and uninstall.

.DESCRIPTION
    Discovery runs against a FAKE machine layout (temp USERPROFILE/LOCALAPPDATA and fake
    session logs), so it is proven on a layout that is not the author's. The execpolicy
    allow checks and the sensitivity check run only when a Codex CLI is present; otherwise
    they report INFO so CI (which has no Codex) still passes.
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

# Load the real functions without running setup's machine-changing body.
$env:CODEX_SETUP_SOURCE_ONLY = "1"
try { . (Join-Path $kit "Setup-Autonomy.ps1") } finally { $env:CODEX_SETUP_SOURCE_ONLY = $null }

$codex = Find-CodexCli

# --- Discovery on a fake machine layout --------------------------------------
try {
    $fake = Join-Path $env:TEMP ("ckit-fake-" + [guid]::NewGuid().ToString("n"))
    $fakeHome = Join-Path $fake "home"
    # A real file on disk that the fake session log will reference; discovery keeps
    # only paths that exist, so this proves the log-parsing branch end to end.
    $fakeShellDir = Join-Path $fake "FakeShellDir"
    New-Item -ItemType Directory -Force -Path $fakeShellDir | Out-Null
    $fakeShell = Join-Path $fakeShellDir "pwsh.exe"
    Set-Content -LiteralPath $fakeShell -Value "" -Encoding ascii
    $sessDir = Join-Path $fakeHome "sessions\2026\10"
    New-Item -ItemType Directory -Force -Path $sessDir | Out-Null
    $jsonPath = ($fakeShell -replace '\\', '\\')   # JSON-escaped backslashes, as logs store them
    $logLine = '{"payload":{"item":{"type":"CommandExecution","command":["' + $jsonPath + '","-Command","x"]}}}'
    Set-Content -LiteralPath (Join-Path $sessDir "s.jsonl") -Value $logLine -Encoding utf8

    $discovered = Get-CodexCommandRulesShellPaths -CodexRoot $fakeHome
    $foundFake = @($discovered) -contains ([System.IO.Path]::GetFullPath($fakeShell))
    # Standard Windows shells should also be discovered (sources 3-4) on any real runner.
    $foundStd = @($discovered | Where-Object { $_ -match '(?i)\\(pwsh|powershell|cmd)\.exe$' }).Count -ge 1
    Add-Result "discovery_fake_layout" $(if ($foundFake -and $foundStd) { "PASS" } else { "FAIL" }) "fake-log shell found=$foundFake; standard shell found=$foundStd; total=$($discovered.Count)"
    Remove-Item -LiteralPath $fake -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    if ($fake -and (Test-Path -LiteralPath $fake)) { Remove-Item -LiteralPath $fake -Recurse -Force -ErrorAction SilentlyContinue }
    Add-Result "discovery_fake_layout" "FAIL" $_.Exception.Message
}

# --- Generated file is marked and BOM-free -----------------------------------
try {
    $sample = @("C:\Fake\pwsh.exe", "C:\Windows\System32\cmd.exe")
    $text = Get-CommandRulesText -ShellPaths $sample -Version "9.9.9"
    $tmpFile = Join-Path $env:TEMP ("ckit-rules-shape-" + [guid]::NewGuid().ToString("n") + ".rules")
    Write-NoBomUtf8 -Path $tmpFile -Text $text
    $bytes = [System.IO.File]::ReadAllBytes($tmpFile)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $marked = ($text -split "`r?`n")[0].Trim() -eq "# Codex Desktop Autonomy Kit managed rules"
    # Escaped backslashes: a Windows path must appear with doubled separators.
    $escaped = $text -match 'C:\\\\Windows\\\\System32\\\\cmd\.exe'
    $hasDelete = ($text -match '(?m)^prefix_rule\(pattern=\["Remove-Item"\]') -and ($text -match '(?m)^prefix_rule\(pattern=\["rm"\]')
    $hasLink = ($text -match '(?m)^prefix_rule\(pattern=\["Start-Process"\]') -and ($text -match '(?m)^prefix_rule\(pattern=\["mshta"\]') -and ($text -match '(?m)^prefix_rule\(pattern=\["rundll32"\]')
    Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
    $ok = (-not $hasBom) -and $marked -and $escaped -and $hasDelete -and $hasLink
    Add-Result "rules_text_shape" $(if ($ok) { "PASS" } else { "FAIL" }) "bom=$hasBom marker=$marked escaped=$escaped delete=$hasDelete link=$hasLink"
} catch { Add-Result "rules_text_shape" "FAIL" $_.Exception.Message }

# --- Write / ownership / uninstall against an isolated root ------------------
try {
    $root = Join-Path $env:TEMP ("ckit-own-" + [guid]::NewGuid().ToString("n"))
    $rulesPath = Join-Path $root "rules\autonomy-kit.rules"
    Write-CodexCommandRules -CodexRoot $root *> $null
    $created = Test-Path -LiteralPath $rulesPath
    # Re-run: identical environment -> "already current", no backup churn.
    Write-CodexCommandRules -CodexRoot $root *> $null
    $bakAfterRerun = @(Get-ChildItem -LiteralPath (Join-Path $root "rules") -Filter "autonomy-kit.rules.bak-*" -ErrorAction SilentlyContinue).Count
    # A non-kit file at the path is left untouched without -Force.
    $customRoot = Join-Path $env:TEMP ("ckit-own2-" + [guid]::NewGuid().ToString("n"))
    $customRules = Join-Path $customRoot "rules\autonomy-kit.rules"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $customRules) | Out-Null
    Set-Content -LiteralPath $customRules -Value "prefix_rule(pattern=[`"my-own`"], decision=`"allow`")" -Encoding ascii
    $customHashBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $customRules).Hash
    Write-CodexCommandRules -CodexRoot $customRoot *> $null
    $customHashAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath $customRules).Hash
    $customPreserved = ($customHashBefore -eq $customHashAfter)
    # Uninstall removes the kit-owned file but not the custom one.
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kit "Uninstall-Autonomy.ps1") -CodexRoot $root *> $null
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $kit "Uninstall-Autonomy.ps1") -CodexRoot $customRoot *> $null
    $kitRemoved = -not (Test-Path -LiteralPath $rulesPath)
    $customKept = Test-Path -LiteralPath $customRules
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $customRoot -Recurse -Force -ErrorAction SilentlyContinue
    $ok = $created -and ($bakAfterRerun -eq 0) -and $customPreserved -and $kitRemoved -and $customKept
    Add-Result "write_ownership_uninstall" $(if ($ok) { "PASS" } else { "FAIL" }) "created=$created rerunBackups=$bakAfterRerun customPreserved=$customPreserved kitRemoved=$kitRemoved customKept=$customKept"
} catch {
    foreach ($r in @($root, $customRoot)) { if ($r -and (Test-Path -LiteralPath $r)) { Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction SilentlyContinue } }
    Add-Result "write_ownership_uninstall" "FAIL" $_.Exception.Message
}

# --- execpolicy allow + sensitivity (needs a Codex CLI) ----------------------
if ($codex) {
    try {
        $shell = "C:\Windows\System32\cmd.exe"
        if ($PSHOME) {
            $cand = Join-Path $PSHOME ((Get-Process -Id $PID).ProcessName + ".exe")
            if (Test-Path -LiteralPath $cand) { $shell = $cand }
        }
        $text = Get-CommandRulesText -ShellPaths @($shell)
        $rulesFile = Join-Path $env:TEMP ("ckit-allow-" + [guid]::NewGuid().ToString("n") + ".rules")
        Write-NoBomUtf8 -Path $rulesFile -Text $text
        $allowSingle = Test-CommandRulesAllow -CodexExe $codex -RulesPath $rulesFile -Argv @("Remove-Item", "x", "-Recurse", "-Force")
        $allowLink = Test-CommandRulesAllow -CodexExe $codex -RulesPath $rulesFile -Argv @("Start-Process", "https://example.com")
        $allowScript = Test-CommandRulesAllow -CodexExe $codex -RulesPath $rulesFile -Argv @($shell, "-Command", 'Remove-Item x -Recurse -Force')
        $negControl = Test-CommandRulesAllow -CodexExe $codex -RulesPath $rulesFile -Argv @("some-unlisted-binary", "--flag")
        Add-Result "execpolicy_allows_list" $(if ($allowSingle -and $allowLink -and $allowScript -and -not $negControl) { "PASS" } else { "FAIL" }) "single=$allowSingle link=$allowLink script=$allowScript negcontrol=$negControl(want False)"

        # Sensitivity: remove the Remove-Item allow line; the single force-delete must now
        # be refused. Proves the check can fail and is not a rubber stamp.
        $weakened = ($text -split "`r?`n" | Where-Object { $_ -notmatch '^prefix_rule\(pattern=\["Remove-Item"\]' }) -join "`r`n"
        $weakFile = Join-Path $env:TEMP ("ckit-weak-" + [guid]::NewGuid().ToString("n") + ".rules")
        Write-NoBomUtf8 -Path $weakFile -Text $weakened
        $stillAllowed = Test-CommandRulesAllow -CodexExe $codex -RulesPath $weakFile -Argv @("Remove-Item", "x", "-Recurse", "-Force")
        Add-Result "sensitivity_goes_red" $(if (-not $stillAllowed) { "PASS" } else { "FAIL" }) "after removing the Remove-Item rule, single force-delete allowed=$stillAllowed (want False)"
        Remove-Item -LiteralPath $rulesFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $weakFile -Force -ErrorAction SilentlyContinue
    } catch { Add-Result "execpolicy_allows_list" "FAIL" $_.Exception.Message }
} else {
    Add-Result "execpolicy_allows_list" "INFO" "no Codex CLI on this host; allow/sensitivity checks skipped (expected on CI)"
}

""
$results | Format-Table -AutoSize | Out-String | Write-Host
$pass = @($results | Where-Object { $_.Status -eq "PASS" }).Count
$fail = @($results | Where-Object { $_.Status -eq "FAIL" }).Count
$info = @($results | Where-Object { $_.Status -eq "INFO" }).Count
Write-Host ("SUMMARY: {0} PASS / {1} FAIL / {2} INFO" -f $pass, $fail, $info)
if ($fail -gt 0) { exit 1 } else { exit 0 }

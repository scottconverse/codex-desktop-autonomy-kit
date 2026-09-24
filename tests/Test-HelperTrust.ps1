<#
.SYNOPSIS
    Behavioural tests for the elevated helper's trusted-path gate.

.DESCRIPTION
    The helper runs scheduled-task jobs at RunLevel Highest, so Assert-TrustedPath is the
    only code gate between a non-admin caller and elevated execution. This file tests that
    gate by CALLING it, not by grepping its source.

    History: an earlier suite asserted that certain strings existed in the helper file
    ("LinkType", "trusted roots", ...). Replacing the entire comparison with
    `if ($true) { return $resolved }` left every string present and the suite green at
    19 PASS / 0 FAIL. Grep assertions cannot detect a disabled gate. These tests can.

    Parity contract: trust is a lexical full-path prefix check, matching the Claude helper.
    Reparse targets are deliberately not resolved or censored.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$kit = Split-Path $PSScriptRoot -Parent
$helper = Join-Path $kit "elevated-dev-helper\ElevatedDevHelper.ps1"

$results = New-Object System.Collections.Generic.List[object]
function Add-Result {
    param(
        [string]$Name,
        [ValidateSet("PASS","FAIL","INFO")][string]$Status,
        [string]$Detail
    )
    $results.Add([pscustomobject]@{ Check = $Name; Status = $Status; Detail = $Detail })
}

# Load the gate without executing the helper body (which requires admin).
$env:CODEX_HELPER_SOURCE_ONLY = "1"
try {
    . $helper
} finally {
    Remove-Item Env:\CODEX_HELPER_SOURCE_ONLY -ErrorAction SilentlyContinue
}

if (-not (Get-Command Assert-TrustedPath -ErrorAction SilentlyContinue)) {
    Add-Result "gate_loads" "FAIL" "could not load Assert-TrustedPath from $helper"
    $results | Format-Table -AutoSize | Out-String | Write-Host
    exit 1
}

# --- test fixture: an outside directory and a set of junctions pointing into it ---
$outside = Join-Path $env:TEMP ("trust-test-" + [guid]::NewGuid().ToString("n"))
$links = @("C:\dev\__trust_a", "C:\dev\__trust_b", "C:\dev\__trust_c")
$canLink = $true
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $outside "deep") | Out-Null
    "x" | Set-Content -LiteralPath (Join-Path $outside "deep\evil.ps1") -Encoding UTF8
    foreach ($l in $links) {
        if (Test-Path -LiteralPath $l) { cmd /c rmdir "$l" 2>$null | Out-Null }
    }
    # Need write access to C:\dev to create junctions. If denied, skip those cases
    # honestly rather than reporting a false pass.
    cmd /c mklink /J "$($links[0])" (Join-Path $outside "deep") 2>&1 | Out-Null
    if (-not (Test-Path -LiteralPath $links[0])) { $canLink = $false }
    if ($canLink) {
        cmd /c mklink /J "$($links[1])" "$($links[0])" 2>&1 | Out-Null
        cmd /c mklink /J "$($links[2])" "$($links[1])" 2>&1 | Out-Null
    }
} catch { $canLink = $false }

function Test-Gate {
    param([string]$Path)
    try { $null = Assert-TrustedPath -Path $Path; return "ACCEPT" } catch { return "REFUSE" }
}

function Add-GateResult {
    param([string]$Name, [string]$Path, [ValidateSet("ACCEPT","REFUSE")][string]$Expect)
    $got = Test-Gate -Path $Path
    $ok = ($got -eq $Expect)
    Add-Result $Name $(if ($ok) { "PASS" } else { "FAIL" }) "$got (expected $Expect) for: $Path"
}

try {
    # --- legitimate paths must be accepted (a gate that refuses everything is broken too) ---
    Add-GateResult "gate_accepts_path_under_dev"          "C:\dev\some-script.ps1"                                          "ACCEPT"
    Add-GateResult "gate_accepts_case_variation"          "c:\DEV\some-script.ps1"                                          "ACCEPT"
    Add-GateResult "gate_accepts_normalized_within_root"  "C:\dev\sub\..\some-script.ps1"                                   "ACCEPT"
    Add-GateResult "gate_accepts_documents_codex"         (Join-Path $env:USERPROFILE "Documents\Codex\x.ps1")              "ACCEPT"
    Add-GateResult "gate_accepts_codex_home"              (Join-Path $env:USERPROFILE ".codex\x.ps1")                       "ACCEPT"

    # --- escapes must be refused ---
    Add-GateResult "gate_refuses_outside_all_roots"       (Join-Path $outside "deep\evil.ps1")                              "REFUSE"
    Add-GateResult "gate_refuses_dotdot_traversal"        "C:\dev\..\Windows\System32\calc.exe"                             "REFUSE"
    Add-GateResult "gate_refuses_dev_prefix_collision"    "C:\developer\evil.ps1"                                             "REFUSE"
    Add-GateResult "gate_refuses_codex_prefix_collision"  (Join-Path $env:USERPROFILE "Documents\CodexOutside\evil.ps1")     "REFUSE"
    Add-GateResult "gate_accepts_helper_temp"             (Join-Path $env:USERPROFILE "AppData\Local\Temp\CodexElevatedHelper\x.ps1") "ACCEPT"

    if ($canLink) {
        Add-GateResult "gate_accepts_junction_leaf"       $links[0]                                                         "ACCEPT"
        Add-GateResult "gate_accepts_junction_parent"     "$($links[0])\evil.ps1"                                           "ACCEPT"
        Add-GateResult "gate_accepts_2_chained_links"     "$($links[1])\evil.ps1"                                           "ACCEPT"
        Add-GateResult "gate_accepts_3_chained_links"     "$($links[2])\evil.ps1"                                           "ACCEPT"
    } else {
        Add-Result "gate_accepts_junction_leaf"   "INFO" "could not create junctions under C:\dev - ACL denied"
        Add-Result "gate_accepts_junction_parent" "INFO" "could not create junctions under C:\dev - ACL denied"
        Add-Result "gate_accepts_2_chained_links" "INFO" "could not create junctions under C:\dev - ACL denied"
        Add-Result "gate_accepts_3_chained_links" "INFO" "could not create junctions under C:\dev - ACL denied"
    }
} finally {
    foreach ($l in $links) { if (Test-Path -LiteralPath $l) { cmd /c rmdir "$l" 2>$null | Out-Null } }
    if (Test-Path -LiteralPath $outside) { cmd /c rd /s /q "$outside" 2>$null | Out-Null }
}

"" 
$results | Format-Table -AutoSize | Out-String | Write-Host
$pass = @($results | Where-Object { $_.Status -eq "PASS" }).Count
$fail = @($results | Where-Object { $_.Status -eq "FAIL" }).Count
$info = @($results | Where-Object { $_.Status -eq "INFO" }).Count
Write-Host ("SUMMARY: {0} PASS / {1} FAIL / {2} INFO" -f $pass, $fail, $info)
if ($fail -gt 0) { exit 1 } else { exit 0 }

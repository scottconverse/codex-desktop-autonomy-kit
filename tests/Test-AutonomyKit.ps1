<#
.SYNOPSIS
    Capability harness for the Codex Desktop Autonomy Kit.
#>
param(
    [string]$Sandbox = (Join-Path $env:TEMP ("codex-autonomy-kit-test-" + [guid]::NewGuid().ToString("n"))),
    [switch]$KeepSandbox
)

$ErrorActionPreference = "Stop"
$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [string]$Name,
        [ValidateSet("PASS","FAIL","INFO")][string]$Status,
        [string]$Detail
    )
    $results.Add([pscustomobject]@{ Check = $Name; Status = $Status; Detail = $Detail })
}

Write-Host "Sandbox: $Sandbox`n"
New-Item -ItemType Directory -Force -Path $Sandbox | Out-Null

try {
    $f = Join-Path $Sandbox "create.txt"
    "hello" | Set-Content -LiteralPath $f -Encoding UTF8
    Add-Result "file_create" $(if (Test-Path $f) { "PASS" } else { "FAIL" }) $f
} catch { Add-Result "file_create" "FAIL" $_.Exception.Message }

try {
    $f = Join-Path $Sandbox "create.txt"
    "world" | Add-Content -LiteralPath $f -Encoding UTF8
    $lines = (Get-Content -LiteralPath $f).Count
    Add-Result "file_edit" $(if ($lines -eq 2) { "PASS" } else { "FAIL" }) "$lines lines"
} catch { Add-Result "file_edit" "FAIL" $_.Exception.Message }

try {
    $f = Join-Path $Sandbox "create.txt"
    $c = Get-Content -LiteralPath $f -Raw
    Add-Result "file_read" $(if ($c -match "hello") { "PASS" } else { "FAIL" }) "read $((Get-Item $f).Length) bytes"
} catch { Add-Result "file_read" "FAIL" $_.Exception.Message }

try {
    $nuke = Join-Path $Sandbox "nuke"
    New-Item -ItemType Directory -Force -Path (Join-Path $nuke "a\b\c") | Out-Null
    1..5 | ForEach-Object { "x" | Set-Content -LiteralPath (Join-Path $nuke "a\b\c\file$_.txt") }
    Remove-Item -LiteralPath $nuke -Recurse -Force
    Add-Result "destructive_delete" $(if (-not (Test-Path $nuke)) { "PASS" } else { "FAIL" }) "Remove-Item -Recurse -Force on populated tree"
} catch { Add-Result "destructive_delete" "FAIL" $_.Exception.Message }

try {
    $canary = Join-Path $env:USERPROFILE ".codex-autonomy-kit-canary.txt"
    (Get-Date).ToString("o") | Set-Content -LiteralPath $canary -Encoding UTF8
    $ok = Test-Path $canary
    Remove-Item -LiteralPath $canary -Force -ErrorAction SilentlyContinue
    Add-Result "cross_dir_write" $(if ($ok) { "PASS" } else { "FAIL" }) "wrote+removed $canary"
} catch { Add-Result "cross_dir_write" "FAIL" $_.Exception.Message }

try {
    $out = & cmd /c "echo codex-autonomy-ok"
    Add-Result "process_launch" $(if ($out -match "codex-autonomy-ok") { "PASS" } else { "FAIL" }) "child process stdout captured"
} catch { Add-Result "process_launch" "FAIL" $_.Exception.Message }

try {
    $r = Invoke-WebRequest -UseBasicParsing -Uri "https://api.github.com/zen" -TimeoutSec 20
    Add-Result "network_egress" $(if ($r.StatusCode -eq 200) { "PASS" } else { "FAIL" }) "HTTP $($r.StatusCode)"
} catch { Add-Result "network_egress" "FAIL" $_.Exception.Message }

try {
    $null = Get-ItemProperty -Path "HKCU:\Environment" -ErrorAction Stop
    Add-Result "registry_read" "PASS" "read HKCU:\Environment"
} catch { Add-Result "registry_read" "FAIL" $_.Exception.Message }

try {
    $n = (Get-ScheduledTask -ErrorAction Stop | Measure-Object).Count
    Add-Result "scheduled_task_read" "PASS" "$n tasks enumerated"
} catch { Add-Result "scheduled_task_read" "FAIL" $_.Exception.Message }

try {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Add-Result "process_elevated" "INFO" "Elevated=$isAdmin"
} catch { Add-Result "process_elevated" "INFO" $_.Exception.Message }

try {
    $helper = Get-ScheduledTask -TaskName "CodexElevatedDevHelper" -ErrorAction SilentlyContinue
    Add-Result "elevated_helper_installed" "INFO" $(if ($helper) { "installed" } else { "not installed (optional)" })
} catch { Add-Result "elevated_helper_installed" "INFO" $_.Exception.Message }

if (-not $KeepSandbox) {
    Remove-Item -LiteralPath $Sandbox -Recurse -Force -ErrorAction SilentlyContinue
    Add-Result "sandbox_cleanup" "PASS" "removed $Sandbox"
} else {
    Add-Result "sandbox_cleanup" "INFO" "kept $Sandbox"
}

""
$results | Format-Table -AutoSize | Out-String | Write-Host
$pass = ($results | Where-Object { $_.Status -eq "PASS" }).Count
$fail = ($results | Where-Object { $_.Status -eq "FAIL" }).Count
$info = ($results | Where-Object { $_.Status -eq "INFO" }).Count
Write-Host ("SUMMARY: {0} PASS / {1} FAIL / {2} INFO" -f $pass, $fail, $info)

$report = Join-Path $env:TEMP ("codex-autonomy-kit-test-report-" + (Get-Date).ToString("yyyyMMdd-HHmmss") + ".json")
$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $report -Encoding UTF8
Write-Host "Report: $report"

if ($fail -gt 0) { exit 1 } else { exit 0 }

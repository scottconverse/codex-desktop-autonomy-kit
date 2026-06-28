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
        'config.autonomy.example.toml'
    )
    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $kit $_)) })
    Add-Result "required_files" $(if ($missing.Count -eq 0) { "PASS" } else { "FAIL" }) $(if ($missing.Count) { "missing: $($missing -join ', ')" } else { "all present" })
} catch { Add-Result "required_files" "FAIL" $_.Exception.Message }

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
        $setup -match 'helper script differs from repo copy'
    )
    Add-Result "setup_custom_config_guard" $(if ($ok) { "PASS" } else { "FAIL" }) "marker, staging manifest, custom guard, helper parity warning"
} catch { Add-Result "setup_custom_config_guard" "FAIL" $_.Exception.Message }

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

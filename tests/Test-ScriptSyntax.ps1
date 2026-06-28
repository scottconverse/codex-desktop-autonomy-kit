<#
.SYNOPSIS
    Parses shipped PowerShell scripts and fails on syntax errors.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$kit = Split-Path $PSScriptRoot -Parent
$scripts = Get-ChildItem -LiteralPath $kit -Recurse -File |
    Where-Object { $_.Extension -eq '.ps1' -and $_.FullName -notlike '*\.git\*' }

$failures = foreach ($script in $scripts) {
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
    foreach ($err in @($errors)) {
        [pscustomobject]@{
            File = $script.FullName.Substring($kit.Length + 1)
            Message = $err.Message
            Line = $err.Extent.StartLineNumber
        }
    }
}

if ($failures) {
    Write-Host "FAIL: PowerShell syntax errors found:" -ForegroundColor Red
    $failures | Format-Table -AutoSize | Out-String | Write-Host
    exit 1
}

Write-Host "PASS: PowerShell parser found no syntax errors." -ForegroundColor Green
exit 0

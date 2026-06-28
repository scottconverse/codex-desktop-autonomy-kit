<#
.SYNOPSIS
    Portability guard: fail if shipped files contain hardcoded per-user paths.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$kit = Split-Path $PSScriptRoot -Parent

$files = Get-ChildItem $kit -Recurse -File -Include *.ps1, *.psm1, *.json, *.cmd, *.md, *.toml |
    Where-Object { $_.FullName -notlike '*\.git\*' }

$placeholders = @('YOUR_USERNAME', 'YOUR-HOME', '<YOUR', '<PASTE')

$hits = foreach ($f in $files) {
    foreach ($ms in (Select-String -LiteralPath $f.FullName -Pattern 'C:\\+Users\\+[A-Za-z0-9._-]+' -AllMatches)) {
        foreach ($m in $ms.Matches) {
            $val = $m.Value
            $isPlaceholder = $false
            foreach ($p in $placeholders) { if ($val -like "*$p*") { $isPlaceholder = $true } }
            $isExempt = ($f.Name -eq 'CHANGELOG.md' -or $f.Name -eq 'Test-NoHardcodedPaths.ps1')
            if (-not $isPlaceholder -and -not $isExempt) {
                [pscustomobject]@{
                    File = $f.FullName.Substring($kit.Length + 1)
                    Line = $ms.LineNumber
                    Match = $val
                }
            }
        }
    }
}

if ($hits) {
    Write-Host "FAIL: hardcoded user/machine path(s) found:" -ForegroundColor Red
    $hits | ForEach-Object { Write-Host ("  {0}:{1} -> {2}" -f $_.File, $_.Line, $_.Match) -ForegroundColor Red }
    Write-Host 'Use $env:USERPROFILE in scripts or placeholders in examples.' -ForegroundColor Yellow
    exit 1
}

Write-Host "PASS: no hardcoded user/machine paths in shipped files." -ForegroundColor Green
exit 0

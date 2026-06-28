<#
.SYNOPSIS
    Reverses the config layer installed by Setup-Autonomy.ps1.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$RemoveHelper
)

$ErrorActionPreference = "Stop"
$cx = "$env:USERPROFILE\.codex"

function Restore-LatestBak($path) {
    $dir = Split-Path -Parent $path
    $name = Split-Path -Leaf $path
    $bak = Get-ChildItem -LiteralPath $dir -Filter "$name.bak-*" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($bak) {
        if ($PSCmdlet.ShouldProcess($path, "restore from $($bak.Name)")) {
            Copy-Item -LiteralPath $bak.FullName -Destination $path -Force
            Write-Host "restored $path <- $($bak.Name)"
        }
        return $true
    }
    return $false
}

if ($RemoveHelper) {
    $h = Get-ScheduledTask -TaskName "CodexElevatedDevHelper" -ErrorAction SilentlyContinue
    if ($h -and $PSCmdlet.ShouldProcess("CodexElevatedDevHelper", "Unregister-ScheduledTask")) {
        Unregister-ScheduledTask -TaskName "CodexElevatedDevHelper" -Confirm:$false
        Write-Host "removed scheduled task: CodexElevatedDevHelper"
    }
}

$config = Join-Path $cx "config.toml"
if (Test-Path -LiteralPath $config) {
    if (-not (Restore-LatestBak $config)) {
        Write-Host "no config.toml backup found; left current config in place"
    }
}

$profileDir = Join-Path $cx "autonomy-kit"
if (Test-Path -LiteralPath $profileDir) {
    if ($PSCmdlet.ShouldProcess($profileDir, "remove staged autonomy profiles")) {
        Remove-Item -LiteralPath $profileDir -Recurse -Force
        Write-Host "removed $profileDir"
    }
}

Write-Host "`nDONE. Toolchain left alone. Restart Codex Desktop for config changes to take effect."

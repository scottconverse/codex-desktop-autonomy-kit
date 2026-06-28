<#
.SYNOPSIS
    Reverses the config layer installed by Setup-Autonomy.ps1.

.DESCRIPTION
    Restores the newest config.toml backup when available. If no backup exists, removes only
    a config.toml that is clearly kit-managed. Removes staged autonomy profiles. Optionally
    unregisters the elevated helper task. Leaves the general-purpose toolchain alone.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$RemoveHelper
)

$ErrorActionPreference = "Stop"
$cx = "$env:USERPROFILE\.codex"
$configMarker = "# Codex Desktop Autonomy Kit managed config"

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
    if ($h) {
        if ($PSCmdlet.ShouldProcess("CodexElevatedDevHelper", "Unregister-ScheduledTask")) {
            Stop-ScheduledTask -TaskName "CodexElevatedDevHelper" -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName "CodexElevatedDevHelper" -Confirm:$false
            Write-Host "removed scheduled task: CodexElevatedDevHelper"
        }
    } else {
        Write-Host "CodexElevatedDevHelper not present - skip"
    }
}

$config = Join-Path $cx "config.toml"
if (Test-Path -LiteralPath $config) {
    if (-not (Restore-LatestBak $config)) {
        $raw = Get-Content -LiteralPath $config -Raw
        if ($raw -like "$configMarker*") {
            if ($PSCmdlet.ShouldProcess($config, "remove kit-managed config.toml")) {
                Remove-Item -LiteralPath $config -Force
                Write-Host "removed kit-managed config.toml (no backup found)"
            }
        } else {
            Write-Host "custom config.toml found and no backup exists; left it in place"
        }
    }
}

$profileDir = Join-Path $cx "autonomy-kit"
if (Test-Path -LiteralPath $profileDir) {
    if ($PSCmdlet.ShouldProcess($profileDir, "remove staged autonomy profiles")) {
        Remove-Item -LiteralPath $profileDir -Recurse -Force
        Write-Host "removed $profileDir"
    }
}

Write-Host "`nDONE. Toolchain and helper files under C:\dev left alone. Restart Codex Desktop for config changes to take effect."

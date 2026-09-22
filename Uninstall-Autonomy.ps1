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
    [switch]$RemoveHelper,
    [string]$CodexRoot = "$env:USERPROFILE\.codex"
)

$ErrorActionPreference = "Stop"
$cx = $CodexRoot
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

# Remove only the kit-authored capability block from AGENTS.md; keep owner content.
$agents = Join-Path $cx "AGENTS.md"
$agentsMarkerBegin = "<!-- Codex Desktop Autonomy Kit: capability-section begin -->"
$agentsMarkerEnd = "<!-- Codex Desktop Autonomy Kit: capability-section end -->"
if (Test-Path -LiteralPath $agents) {
    $raw = Get-Content -LiteralPath $agents -Raw
    # Require BOTH markers. Excising a begin without a matching end would corrupt the
    # file, so a half-matched block is left alone and reported rather than half-removed.
    $hasBegin = $raw -match [regex]::Escape($agentsMarkerBegin)
    $hasEnd = $raw -match [regex]::Escape($agentsMarkerEnd)
    if ($hasBegin -and -not $hasEnd) {
        Write-Host "AGENTS.md has a capability begin marker with no end marker - left unchanged (manual review needed)"
    }
    if ($hasBegin -and $hasEnd) {
        if ($PSCmdlet.ShouldProcess($agents, "remove kit capability block")) {
            $pattern = "(?s)\r?\n?" + [regex]::Escape($agentsMarkerBegin) + ".*?" + [regex]::Escape($agentsMarkerEnd) + "\r?\n?"
            $cleaned = [regex]::Replace($raw, $pattern, "", 1)
            if ([string]::IsNullOrWhiteSpace($cleaned)) {
                [System.IO.File]::Delete($agents)
                Write-Host "removed AGENTS.md (contained only the kit block)"
            } else {
                Set-Content -LiteralPath $agents -Value $cleaned -Encoding UTF8 -NoNewline
                Write-Host "removed kit capability block from AGENTS.md (your content kept)"
            }
        }
    } elseif (-not $hasBegin) {
        Write-Host "AGENTS.md has no kit capability block - left unchanged"
    }
}

$skillDir = Join-Path $cx "skills\capability-check"
if (Test-Path -LiteralPath $skillDir) {
    if ($PSCmdlet.ShouldProcess($skillDir, "remove capability-check skill")) {
        [System.IO.Directory]::Delete($skillDir, $true)
        Write-Host "removed $skillDir"
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

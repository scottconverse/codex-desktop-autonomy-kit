<#
.SYNOPSIS
    Reverses the config layer installed by Setup-Autonomy.ps1.

.DESCRIPTION
    Restores only the config.toml backup recorded by the kit's ownership manifest. If no
    valid kit-owned backup exists, removes only a config.toml that is clearly kit-managed.
    Removes staged autonomy profiles. Optionally unregisters the elevated helper task.
    Leaves the general-purpose toolchain alone.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$RemoveHelper,
    [string]$CodexRoot = "$env:USERPROFILE\.codex"
)

$ErrorActionPreference = "Stop"
$cx = $CodexRoot
$configMarker = "# Codex Desktop Autonomy Kit managed config"

function Get-KitBackupRecord($path) {
    $manifestPath = Join-Path (Join-Path $cx "autonomy-kit") "config-backup-manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $null }

    try {
        $record = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ($record.schema_version -ne 1) { throw "unsupported backup manifest schema" }
        if ([string]::IsNullOrWhiteSpace([string]$record.source_path)) { throw "source_path missing" }
        if ([string]::IsNullOrWhiteSpace([string]$record.backup_path)) { throw "backup_path missing" }
        if ([string]::IsNullOrWhiteSpace([string]$record.backup_sha256)) { throw "backup_sha256 missing" }

        $sourceFull = [System.IO.Path]::GetFullPath($path)
        $recordSource = [System.IO.Path]::GetFullPath([string]$record.source_path)
        if (-not [StringComparer]::OrdinalIgnoreCase.Equals($sourceFull, $recordSource)) {
            throw "source_path does not match the active config"
        }

        $backupFull = [System.IO.Path]::GetFullPath([string]$record.backup_path)
        $configDir = [System.IO.Path]::GetFullPath((Split-Path -Parent $path))
        $backupDir = [System.IO.Path]::GetDirectoryName($backupFull)
        $backupName = [System.IO.Path]::GetFileName($backupFull)
        $configName = [System.IO.Path]::GetFileName($path)
        if (-not [StringComparer]::OrdinalIgnoreCase.Equals($configDir, $backupDir)) {
            throw "backup is outside the config directory"
        }
        if ($backupName -notlike "$configName.bak-*") {
            throw "backup filename is not a config.toml backup"
        }
        if (-not (Test-Path -LiteralPath $backupFull -PathType Leaf)) {
            throw "recorded backup is missing"
        }

        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $backupFull).Hash
        if (-not [StringComparer]::OrdinalIgnoreCase.Equals($actualHash, [string]$record.backup_sha256)) {
            throw "recorded backup hash does not match"
        }

        return [pscustomobject]@{
            Status = 'valid'
            BackupPath = $backupFull
            ManifestPath = $manifestPath
        }
    } catch {
        return [pscustomobject]@{
            Status = 'invalid'
            ManifestPath = $manifestPath
            Reason = $_.Exception.Message
        }
    }
}

function Restore-KitBackup($path) {
    $record = Get-KitBackupRecord $path
    if (-not $record) { return 'missing' }
    if ($record.Status -ne 'valid') {
        Write-Host "kit backup manifest invalid; active config left unchanged: $($record.Reason)"
        return 'invalid'
    }
    if ($PSCmdlet.ShouldProcess($path, "restore from $([System.IO.Path]::GetFileName($record.BackupPath))")) {
        Copy-Item -LiteralPath $record.BackupPath -Destination $path -Force
        Write-Host "restored $path <- $([System.IO.Path]::GetFileName($record.BackupPath))"
    }
    return 'restored'
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
    $restoreStatus = Restore-KitBackup $config
    if ($restoreStatus -ne 'restored') {
        $raw = Get-Content -LiteralPath $config -Raw
        if ($restoreStatus -eq 'invalid') {
            Write-Host "config.toml has a backup manifest requiring manual review; left it in place"
        } elseif ($raw -like "$configMarker*") {
            if ($PSCmdlet.ShouldProcess($config, "remove kit-managed config.toml")) {
                Remove-Item -LiteralPath $config -Force
                Write-Host "removed kit-managed config.toml (no backup found)"
            }
        } else {
            Write-Host "custom config.toml found and no valid kit-owned backup exists; left it in place"
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

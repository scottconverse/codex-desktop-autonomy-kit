<#
.SYNOPSIS
    One-command toolchain + config bootstrap for the Codex Desktop Autonomy Kit on Windows.

.DESCRIPTION
    Installs common user-scope development tooling, stages the Codex autonomy profiles under
    ~/.codex/autonomy-kit, creates or refreshes kit-managed ~/.codex/config.toml, and offers
    the elevated helper installer if the helper task is missing.

    Existing customized config.toml is left unchanged. The kit files are staged for manual
    merge so setup is safe to re-run on machines with hand-edited Codex config.
#>
[CmdletBinding()]
param(
    [switch]$SkipConfig,
    [switch]$SkipBrowsers,
    [switch]$SkipHelper,
    [switch]$ForceConfig,
    [switch]$ConfigOnly,
    [string]$CodexRoot = "$env:USERPROFILE\.codex",
    [switch]$RefreshHelper
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$kit = $PSScriptRoot
$kitVersion = "1.5.0"
$configMarker = "# Codex Desktop Autonomy Kit managed config"

function Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Note($m) { Write-Host "  $m" }
function Warn($m) { Write-Warning $m }
function Prepend-UserPath($dir) {
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return }
    $up = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($up -split ';') -notcontains $dir) {
        [Environment]::SetEnvironmentVariable('Path', "$dir;$up", 'User')
    }
    if (($env:Path -split ';') -notcontains $dir) { $env:Path = "$dir;$env:Path" }
}
function Backup-File($path) {
    if (Test-Path -LiteralPath $path) {
        $bak = "$path.bak-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
        Copy-Item -LiteralPath $path -Destination $bak -Force
        Note "backed up $(Split-Path -Leaf $path) -> $(Split-Path -Leaf $bak)"
    }
}
function Get-FileHashText($path) {
    if (Test-Path -LiteralPath $path) { return (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash }
    return $null
}
function Resolve-HelperRoot {
    # Explicit pointer written by the elevated installer wins; else the documented default.
    # Without this, a custom -InstallRoot produced a permanent false STALE/modified result.
    $pointer = Join-Path (Join-Path $CodexRoot "autonomy-kit") "helper-root.json"
    if (Test-Path -LiteralPath $pointer) {
        try {
            $p = Get-Content -LiteralPath $pointer -Raw | ConvertFrom-Json
            if ($p.install_root) { return $p.install_root }
        } catch { }
    }
    return "C:\dev\CodexElevatedHelper"
}
function Get-GeneratedConfig($coreText) {
    return @"
$configMarker
# version = "$kitVersion"

approval_policy = "never"
sandbox_mode = "danger-full-access"

[windows]
sandbox = "elevated"

developer_instructions = '''
$coreText
'''
"@
}
function Normalize-ConfigText($text) {
    if ($null -eq $text) { return "" }
    return (($text -replace "^\uFEFF", "") -replace "`r`n", "`n").TrimEnd()
}
function Write-GeneratedConfig($path, $coreText) {
    $toml = Get-GeneratedConfig -coreText $coreText
    $toml | Set-Content -LiteralPath $path -Encoding UTF8
}

if (-not $ConfigOnly) {
    Step "Python (user-scope) + python3 shim"
    $pyExe = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $pyExe) {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Warn "winget not found; install Python manually or install App Installer, then re-run."
        } else {
            try {
                winget install -e --id Python.Python.3.12 --scope user `
                    --accept-package-agreements --accept-source-agreements --disable-interactivity
            } catch {
                Warn "Python install failed: $($_.Exception.Message)"
            }
            $pyExe = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending | Select-Object -First 1
        }
    }
    if ($pyExe) {
        $pydir = $pyExe.Directory.FullName
        $py3 = Join-Path $pydir "python3.exe"
        if (-not (Test-Path -LiteralPath $py3)) { Copy-Item $pyExe.FullName $py3 -Force }
        Prepend-UserPath $pydir
        Prepend-UserPath (Join-Path $pydir "Scripts")
        Note "python: $(& $pyExe.FullName --version)"
    } else {
        Warn "Python unavailable; later Python-based setup steps may be skipped."
    }

    Step "uv"
    if (-not (Test-Path "$env:USERPROFILE\.local\bin\uv.exe")) {
        try {
            powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex"
        } catch {
            Warn "uv install failed: $($_.Exception.Message)"
        }
    }
    Prepend-UserPath "$env:USERPROFILE\.local\bin"
    if (Test-Path "$env:USERPROFILE\.local\bin\uv.exe") {
        Note "uv: $(& "$env:USERPROFILE\.local\bin\uv.exe" --version 2>&1)"
    }

    Step "scoop"
    if (-not (Test-Path "$env:USERPROFILE\scoop\shims\scoop.ps1")) {
        try {
            Invoke-Expression (Invoke-RestMethod -Uri "https://get.scoop.sh")
        } catch {
            Warn "scoop install failed: $($_.Exception.Message)"
        }
    }
    Prepend-UserPath "$env:USERPROFILE\scoop\shims"
    $scoop = "$env:USERPROFILE\scoop\shims\scoop.ps1"
    if (Test-Path -LiteralPath $scoop) {
        try { & $scoop bucket add main *> $null } catch { Warn "scoop bucket add failed: $($_.Exception.Message)" }
    } else {
        Warn "scoop unavailable; skipping tool installs that require it."
    }

    Step "core tools via scoop"
    $wanted = [ordered]@{ 'nodejs-lts' = 'node'; 'gh' = 'gh'; 'ripgrep' = 'rg'; 'jq' = 'jq'; 'sqlite' = 'sqlite3' }
    foreach ($pkg in $wanted.Keys) {
        $cmd = $wanted[$pkg]
        if (Get-Command $cmd -ErrorAction SilentlyContinue) {
            Note "$cmd already present - skip"
        } else {
            try {
                & $scoop install $pkg
            } catch {
                Warn "scoop install $pkg failed: $($_.Exception.Message)"
            }
        }
    }

    Step "Playwright"
    $py3cmd = (Get-Command python3 -ErrorAction SilentlyContinue).Source
    if (-not $py3cmd -and $pyExe) { $py3cmd = Join-Path $pyExe.Directory.FullName "python3.exe" }
    if ($py3cmd) {
        try {
            & $py3cmd -m pip install --quiet --upgrade playwright
            if (-not $SkipBrowsers) { & $py3cmd -m playwright install }
            Note "playwright: $(& $py3cmd -m playwright --version 2>&1)"
        } catch {
            Warn "Playwright install failed: $($_.Exception.Message)"
        }
    } else {
        Warn "python3 not found; skipped Playwright install."
    }
}

if (-not $SkipConfig) {
    Step "Codex config/profile staging"
    $cx = $CodexRoot
    $profileDir = Join-Path $cx "autonomy-kit"
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

    $stageFiles = @(
        "CODEX-Desktop-Core.md",
        "GEN5-Codex-Desktop-Autonomous-Software-Development.md",
        "config.autonomy.example.toml"
    )
    foreach ($f in $stageFiles) { Copy-Item -LiteralPath (Join-Path $kit $f) -Destination $profileDir -Force }
    @{
        kit_version = $kitVersion
        staged_at = (Get-Date).ToUniversalTime().ToString("o")
        files = @($stageFiles | ForEach-Object {
            [pscustomobject]@{
                name = $_
                sha256 = Get-FileHashText (Join-Path $kit $_)
            }
        })
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $profileDir "manifest.json") -Encoding UTF8
    Note "staged profiles under $profileDir"

    $config = Join-Path $cx "config.toml"
    $core = Get-Content -LiteralPath "$kit\CODEX-Desktop-Core.md" -Raw
    $generated = Get-GeneratedConfig -coreText $core
    if (-not (Test-Path -LiteralPath $config)) {
        Write-GeneratedConfig -path $config -coreText $core
        Note "created kit-managed config.toml"
    } else {
        $raw = Get-Content -LiteralPath $config -Raw
        $isKitManaged = ($raw -like "$configMarker*") -or ($raw -match 'Codex Desktop Autonomy Kit managed config')
        $looksLikeOldKitConfig = ($raw -match 'Codex Desktop Autonomy Core \(compact\)' -and $raw -match 'approval_policy\s*=\s*"never"')
        if ($ForceConfig -or $isKitManaged -or $looksLikeOldKitConfig) {
            if ((Normalize-ConfigText $raw) -eq (Normalize-ConfigText $generated)) {
                Note "kit-managed config.toml already current"
            } else {
                Backup-File $config
                Write-GeneratedConfig -path $config -coreText $core
                Note "refreshed kit-managed config.toml"
            }
        } else {
            Note "custom config.toml found; left unchanged"
            Note "merge staged files from $profileDir when ready"
        }
    }
}

if (-not $SkipHelper -and -not $ConfigOnly) {
    Step "elevated dev helper"
    $helperTask = Get-ScheduledTask -TaskName "CodexElevatedDevHelper" -ErrorAction SilentlyContinue
    $helperInstall = Join-Path $kit "elevated-dev-helper\Install-ElevatedDevHelper-AsAdmin.cmd"
    $helperRoot = Resolve-HelperRoot
    $installedHelper = Join-Path $helperRoot "ElevatedDevHelper.ps1"
    if ($helperTask) {
        Note "CodexElevatedDevHelper already installed ($($helperTask.State))"
        $repoHash = Get-FileHashText (Join-Path $kit "elevated-dev-helper\ElevatedDevHelper.ps1")
        $installedHash = Get-FileHashText $installedHelper
        if ($repoHash -and $installedHash -and $repoHash -ne $installedHash) {
            if ($RefreshHelper) {
                Note "installed helper differs; launching refresh installer (Windows UAC prompt expected)..."
                Start-Process -FilePath $helperInstall -Verb RunAs -Wait
            } else {
                Warn "installed helper script differs from repo copy; run setup with -RefreshHelper or run elevated-dev-helper\Install-ElevatedDevHelper-AsAdmin.cmd"
            }
        }
    } elseif (Test-Path -LiteralPath $helperInstall) {
        Note "launching helper installer (Windows UAC prompt expected)..."
        Start-Process -FilePath $helperInstall -Verb RunAs -Wait
        $helperTask = Get-ScheduledTask -TaskName "CodexElevatedDevHelper" -ErrorAction SilentlyContinue
        Note ("helper: {0}" -f $(if ($helperTask) { 'installed' } else { 'NOT installed (UAC declined or installer error)' }))
    } else {
        Warn "helper installer not found: $helperInstall"
    }
}

if (-not $ConfigOnly) {
    Step "Summary"
    foreach ($t in 'python3','pip','uv','scoop','node','npm','npx','gh','rg','jq','sqlite3') {
        $src = (Get-Command $t -ErrorAction SilentlyContinue).Source
        "{0,-10} {1}" -f $t, $(if ($src) { 'OK' } else { 'missing (open a new shell)' }) | Write-Host
    }
}

Write-Host "`nNEXT:" -ForegroundColor Green
Write-Host "  1. Restart Codex Desktop so PATH and config changes load."
Write-Host "  2. Inventory check anytime: powershell -File .\Doctor-Autonomy.ps1"
Write-Host "  3. If config.toml was custom, merge staged files from ~/.codex/autonomy-kit manually."

<#
.SYNOPSIS
    One-command toolchain + config bootstrap for the Codex Desktop Autonomy Kit on Windows.

.DESCRIPTION
    Installs common user-scope development tooling, stages the Codex autonomy profiles under
    ~/.codex/autonomy-kit, creates ~/.codex/config.toml only if it does not already exist,
    and offers the elevated helper installer if the helper task is missing.

    Existing config.toml is backed up and left unchanged by default to avoid producing
    duplicate TOML keys. Use the staged files and config.autonomy.example.toml for manual
    merge when you already have a custom Codex config.
#>
[CmdletBinding()]
param(
    [switch]$SkipConfig,
    [switch]$SkipBrowsers,
    [switch]$SkipHelper
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$kit = $PSScriptRoot

function Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Prepend-UserPath($dir) {
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return }
    $up = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($up -split ';') -notcontains $dir) {
        [Environment]::SetEnvironmentVariable('Path', "$dir;$up", 'User')
    }
    if (($env:Path -split ';') -notcontains $dir) { $env:Path = "$dir;$env:Path" }
}

Step "Python (user-scope) + python3 shim"
$pyExe = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $pyExe) {
    winget install -e --id Python.Python.3.12 --scope user `
        --accept-package-agreements --accept-source-agreements --disable-interactivity
    $pyExe = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
}
if ($pyExe) {
    $pydir = $pyExe.Directory.FullName
    $py3 = Join-Path $pydir "python3.exe"
    if (-not (Test-Path -LiteralPath $py3)) { Copy-Item $pyExe.FullName $py3 -Force }
    Prepend-UserPath $pydir
    Prepend-UserPath (Join-Path $pydir "Scripts")
    Write-Host "python: $(& $pyExe.FullName --version)"
} else {
    Write-Warning "Python not installed automatically; install it and re-run."
}

Step "uv"
if (-not (Test-Path "$env:USERPROFILE\.local\bin\uv.exe")) {
    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex"
}
Prepend-UserPath "$env:USERPROFILE\.local\bin"
if (Test-Path "$env:USERPROFILE\.local\bin\uv.exe") {
    Write-Host "uv: $(& "$env:USERPROFILE\.local\bin\uv.exe" --version 2>&1)"
}

Step "scoop"
if (-not (Test-Path "$env:USERPROFILE\scoop\shims\scoop.ps1")) {
    Invoke-Expression (Invoke-RestMethod -Uri "https://get.scoop.sh")
}
Prepend-UserPath "$env:USERPROFILE\scoop\shims"
$scoop = "$env:USERPROFILE\scoop\shims\scoop.ps1"
& $scoop bucket add main *> $null

Step "core tools via scoop"
$wanted = [ordered]@{ 'nodejs-lts' = 'node'; 'gh' = 'gh'; 'ripgrep' = 'rg'; 'jq' = 'jq'; 'sqlite' = 'sqlite3' }
foreach ($pkg in $wanted.Keys) {
    $cmd = $wanted[$pkg]
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        Write-Host "$cmd already present - skip"
    } else {
        & $scoop install $pkg
    }
}

Step "Playwright"
$py3cmd = (Get-Command python3 -ErrorAction SilentlyContinue).Source
if (-not $py3cmd -and $pyExe) { $py3cmd = Join-Path $pyExe.Directory.FullName "python3.exe" }
if ($py3cmd) {
    & $py3cmd -m pip install --quiet --upgrade playwright
    if (-not $SkipBrowsers) { & $py3cmd -m playwright install }
    Write-Host "playwright: $(& $py3cmd -m playwright --version 2>&1)"
}

if (-not $SkipConfig) {
    Step "Codex config/profile staging"
    $cx = "$env:USERPROFILE\.codex"
    $profileDir = Join-Path $cx "autonomy-kit"
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    Copy-Item "$kit\CODEX-Desktop-Core.md" $profileDir -Force
    Copy-Item "$kit\GEN5-Codex-Desktop-Autonomous-Software-Development.md" $profileDir -Force
    Copy-Item "$kit\config.autonomy.example.toml" $profileDir -Force

    $config = Join-Path $cx "config.toml"
    if (Test-Path -LiteralPath $config) {
        Copy-Item $config "$config.bak-$((Get-Date).ToString('yyyyMMdd-HHmmss'))" -Force
        Write-Host "backed up existing config.toml; left it unchanged"
    } else {
        $core = Get-Content -LiteralPath "$kit\CODEX-Desktop-Core.md" -Raw
        $toml = @"
approval_policy = "never"
sandbox_mode = "danger-full-access"

[windows]
sandbox = "elevated"

developer_instructions = '''
$core
'''
"@
        $toml | Set-Content -LiteralPath $config -Encoding UTF8
        Write-Host "created $config with compact core instructions"
    }
}

if (-not $SkipHelper) {
    Step "elevated dev helper"
    $helperTask = Get-ScheduledTask -TaskName "CodexElevatedDevHelper" -ErrorAction SilentlyContinue
    $helperInstall = Join-Path $kit "elevated-dev-helper\Install-ElevatedDevHelper-AsAdmin.cmd"
    if ($helperTask) {
        Write-Host "CodexElevatedDevHelper already installed - skip"
    } elseif (Test-Path -LiteralPath $helperInstall) {
        Write-Host "launching helper installer (Windows UAC prompt expected)..."
        Start-Process -FilePath $helperInstall -Verb RunAs -Wait
        $helperTask = Get-ScheduledTask -TaskName "CodexElevatedDevHelper" -ErrorAction SilentlyContinue
        Write-Host ("helper: {0}" -f $(if ($helperTask) { 'installed' } else { 'NOT installed (UAC declined or installer error)' }))
    }
}

Step "Summary"
foreach ($t in 'python3','pip','uv','scoop','node','npm','npx','gh','rg','jq','sqlite3') {
    $src = (Get-Command $t -ErrorAction SilentlyContinue).Source
    "{0,-10} {1}" -f $t, $(if ($src) { 'OK' } else { 'missing (open a new shell)' }) | Write-Host
}

Write-Host "`nNEXT:" -ForegroundColor Green
Write-Host "  1. Restart Codex Desktop so PATH and config changes load."
Write-Host "  2. Inventory check anytime: powershell -File .\Doctor-Autonomy.ps1"
Write-Host "  3. If config.toml already existed, merge ~/.codex/autonomy-kit/config.autonomy.example.toml manually."

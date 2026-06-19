param(
    [string]$InstallRoot = "C:\dev\CodexElevatedHelper",
    [string]$TaskName = "CodexElevatedDevHelper"
)

$ErrorActionPreference = "Stop"

function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "This installer must be run from an elevated PowerShell session."
    }
}

Assert-Admin

$source = Join-Path $PSScriptRoot "ElevatedDevHelper.ps1"
if (-not (Test-Path -LiteralPath $source)) {
    throw "Missing helper script: $source"
}

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot "queue") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot "done") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot "failed") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot "logs") | Out-Null

$target = Join-Path $InstallRoot "ElevatedDevHelper.ps1"
Copy-Item -LiteralPath $source -Destination $target -Force

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$target`" -Root `"$InstallRoot`""
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)

Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null

@{
    installed = $true
    task_name = $TaskName
    install_root = $InstallRoot
    helper_script = $target
    installed_at = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $InstallRoot "install-state.json") -Encoding UTF8

Write-Host "Installed $TaskName at $InstallRoot"

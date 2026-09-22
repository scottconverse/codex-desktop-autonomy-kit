param(
    [string]$InstallRoot = "C:\dev\CodexElevatedHelper",
    [string]$TaskName = "CodexElevatedDevHelper"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "This installer must be run from an elevated PowerShell session."
    }
}

Assert-Admin

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$userId = $identity.Name

$source = Join-Path $PSScriptRoot "ElevatedDevHelper.ps1"
if (-not (Test-Path -LiteralPath $source)) {
    throw "Missing helper script: $source"
}
$invokerSource = Join-Path $PSScriptRoot "Invoke-ElevatedDevHelper.ps1"
if (-not (Test-Path -LiteralPath $invokerSource)) {
    throw "Missing helper invoker: $invokerSource"
}

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot "queue") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot "done") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot "failed") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot "logs") | Out-Null
$installLog = Join-Path $InstallRoot "install-log.txt"
"[$((Get-Date).ToUniversalTime().ToString("o"))] Installer running as $userId; elevated=True" | Add-Content -LiteralPath $installLog -Encoding UTF8

$target = Join-Path $InstallRoot "ElevatedDevHelper.ps1"
$invokerTarget = Join-Path $InstallRoot "Invoke-ElevatedDevHelper.ps1"
Copy-Item -LiteralPath $source -Destination $target -Force
Copy-Item -LiteralPath $invokerSource -Destination $invokerTarget -Force

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$target`" -Root `"$InstallRoot`""
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)

Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null

@{
    installed = $true
    task_name = $TaskName
    install_root = $InstallRoot
    helper_script = $target
    invoker_script = $invokerTarget
    user_id = $userId
    installed_at = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $InstallRoot "install-state.json") -Encoding UTF8

$jobId = "install-self-test-" + [guid]::NewGuid().ToString("n")
$jobPath = Join-Path (Join-Path $InstallRoot "queue") ($jobId + ".json")
@{
    action = "CheckAdmin"
    created_at = (Get-Date).ToUniversalTime().ToString("o")
    created_by = $userId
    purpose = "install self-test"
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jobPath -Encoding UTF8

Start-ScheduledTask -TaskName $TaskName

$resultPath = Join-Path (Join-Path $InstallRoot "done") ($jobId + ".result.json")
$errorPath = Join-Path (Join-Path $InstallRoot "failed") ($jobId + ".error.json")
$deadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $deadline) {
    if ((Test-Path -LiteralPath $resultPath) -or (Test-Path -LiteralPath $errorPath)) { break }
    Start-Sleep -Milliseconds 500
}

if (Test-Path -LiteralPath $errorPath) {
    "[$((Get-Date).ToUniversalTime().ToString("o"))] Self-test failed: $errorPath" | Add-Content -LiteralPath $installLog -Encoding UTF8
    throw "Elevated helper self-test failed: $errorPath"
}

if (-not (Test-Path -LiteralPath $resultPath)) {
    "[$((Get-Date).ToUniversalTime().ToString("o"))] Self-test did not complete within 30 seconds. Check Task Scheduler and helper logs." | Add-Content -LiteralPath $installLog -Encoding UTF8
    throw "Elevated helper self-test did not complete within 30 seconds."
}

$selfTest = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
if ($selfTest.status -ne "ok" -or -not $selfTest.result.ok -or -not $selfTest.result.is_admin) {
    "[$((Get-Date).ToUniversalTime().ToString("o"))] Self-test returned an unexpected result: $resultPath" | Add-Content -LiteralPath $installLog -Encoding UTF8
    throw "Elevated helper self-test did not confirm administrator execution: $resultPath"
}

"[$((Get-Date).ToUniversalTime().ToString("o"))] Self-test succeeded: $resultPath" | Add-Content -LiteralPath $installLog -Encoding UTF8

# Record the install root so the rest of the kit can discover it. Consumers
# (Setup, Doctor, Install-Autonomy.cmd) must not assume C:\dev.
$pointerDir = Join-Path $env:USERPROFILE ".codex\autonomy-kit"
New-Item -ItemType Directory -Force -Path $pointerDir | Out-Null
@{
    install_root = $InstallRoot
    task_name = $TaskName
    helper_script = $target
    invoker_script = $invokerTarget
    user_id = $userId
    updated_at = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $pointerDir "helper-root.json") -Encoding UTF8

Write-Host "Installed $TaskName at $InstallRoot for $userId"
Write-Host "Install log: $installLog"
if (Test-Path -LiteralPath $resultPath) {
    Write-Host "Self-test result: $resultPath"
    Get-Content -LiteralPath $resultPath
}

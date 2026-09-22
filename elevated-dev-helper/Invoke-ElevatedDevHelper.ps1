param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("CheckAdmin","WingetInstall","WingetUpgrade","RunTrustedPowerShellScript","StartService","StopService","RestartService","OpenDevFirewallPort","RegisterDevScheduledTask")]
    [string]$Action,

    [string]$Root,
    [string]$TaskName,
    [string]$PackageId,
    [string]$Scope,
    [string]$ScriptPath,
    [string[]]$Arguments,
    [string]$ServiceName,
    [int]$Port,
    [string]$Protocol,
    [string]$DevTaskName
)

$ErrorActionPreference = "Stop"

$pointerPath = Join-Path $env:USERPROFILE ".codex\autonomy-kit\helper-root.json"
if ((-not $Root -or -not $TaskName) -and (Test-Path -LiteralPath $pointerPath)) {
    $pointer = Get-Content -LiteralPath $pointerPath -Raw | ConvertFrom-Json
    if (-not $Root -and $pointer.install_root) { $Root = [string]$pointer.install_root }
    if (-not $TaskName -and $pointer.task_name) { $TaskName = [string]$pointer.task_name }
}
if (-not $Root) { $Root = "C:\dev\CodexElevatedHelper" }
if (-not $TaskName) { $TaskName = "CodexElevatedDevHelper" }

if (-not (Test-Path -LiteralPath $Root)) {
    throw "Helper root not found: $Root"
}

$queue = Join-Path $Root "queue"
New-Item -ItemType Directory -Force -Path $queue | Out-Null

$jobId = [guid]::NewGuid().ToString("n")
$job = [ordered]@{
    action = $Action
    created_at = (Get-Date).ToUniversalTime().ToString("o")
    created_by = $env:USERNAME
}

if ($PackageId) { $job.packageId = $PackageId }
if ($Scope) { $job.scope = $Scope }
if ($ScriptPath) { $job.scriptPath = $ScriptPath }
if ($Arguments) { $job.arguments = $Arguments }
if ($ServiceName) { $job.serviceName = $ServiceName }
if ($Port) { $job.port = $Port }
if ($Protocol) { $job.protocol = $Protocol }
if ($DevTaskName) { $job.taskName = $DevTaskName }

$jobPath = Join-Path $queue ($jobId + ".json")
$job | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jobPath -Encoding UTF8

Start-ScheduledTask -TaskName $TaskName

@{
    queued = $true
    job_id = $jobId
    job_path = $jobPath
    task_name = $TaskName
    root = $Root
} | ConvertTo-Json -Depth 4

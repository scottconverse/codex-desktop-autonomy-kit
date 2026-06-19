param(
    [string]$Root = "C:\dev\CodexElevatedHelper"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function New-DirectoryIfMissing {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Write-JsonLog {
    param(
        [string]$LogPath,
        [hashtable]$Record
    )
    $Record.timestamp = (Get-Date).ToUniversalTime().ToString("o")
    ($Record | ConvertTo-Json -Depth 12 -Compress) | Add-Content -LiteralPath $LogPath -Encoding UTF8
}

function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "ElevatedDevHelper is not running with administrator rights."
    }
}

function Assert-TrustedPath {
    param([string]$Path)
    $resolved = [System.IO.Path]::GetFullPath($Path)
    $trustedRoots = @(
        "C:\dev\",
        "C:\Users\scott\Documents\Codex\",
        "C:\Users\scott\.codex\",
        "C:\Users\scott\AppData\Local\Temp\CodexElevatedHelper\"
    )
    foreach ($root in $trustedRoots) {
        if ($resolved.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $resolved
        }
    }
    throw "Path is not under a trusted development root: $Path"
}

function Invoke-LoggedProcess {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 1800
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    foreach ($arg in $Arguments) {
        [void]$psi.ArgumentList.Add($arg)
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()

    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        try { $proc.Kill() } catch {}
        throw "Process timed out: $FilePath"
    }

    return @{
        exit_code = $proc.ExitCode
        stdout = $proc.StandardOutput.ReadToEnd()
        stderr = $proc.StandardError.ReadToEnd()
    }
}

function Invoke-HelperAction {
    param([pscustomobject]$Job)

    if (-not $Job.action) {
        throw "Job is missing action."
    }

    switch ($Job.action) {
        "CheckAdmin" {
            return @{ ok = $true; is_admin = $true }
        }

        "WingetInstall" {
            if (-not $Job.packageId) { throw "WingetInstall requires packageId." }
            $args = @("install", "--id", [string]$Job.packageId, "--exact", "--accept-package-agreements", "--accept-source-agreements")
            if ($Job.scope -eq "user") { $args += @("--scope", "user") }
            return Invoke-LoggedProcess -FilePath "winget.exe" -Arguments $args -TimeoutSeconds 3600
        }

        "WingetUpgrade" {
            if (-not $Job.packageId) { throw "WingetUpgrade requires packageId." }
            $args = @("upgrade", "--id", [string]$Job.packageId, "--exact", "--accept-package-agreements", "--accept-source-agreements")
            return Invoke-LoggedProcess -FilePath "winget.exe" -Arguments $args -TimeoutSeconds 3600
        }

        "RunTrustedPowerShellScript" {
            if (-not $Job.scriptPath) { throw "RunTrustedPowerShellScript requires scriptPath." }
            $script = Assert-TrustedPath -Path ([string]$Job.scriptPath)
            if (-not (Test-Path -LiteralPath $script)) { throw "Trusted script does not exist: $script" }
            $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script)
            if ($Job.arguments) {
                foreach ($arg in @($Job.arguments)) {
                    $args += [string]$arg
                }
            }
            return Invoke-LoggedProcess -FilePath "powershell.exe" -Arguments $args -TimeoutSeconds 3600
        }

        "StartService" {
            if (-not $Job.serviceName) { throw "StartService requires serviceName." }
            Start-Service -Name ([string]$Job.serviceName)
            return @{ ok = $true; service = $Job.serviceName; state = "start_requested" }
        }

        "StopService" {
            if (-not $Job.serviceName) { throw "StopService requires serviceName." }
            Stop-Service -Name ([string]$Job.serviceName)
            return @{ ok = $true; service = $Job.serviceName; state = "stop_requested" }
        }

        "RestartService" {
            if (-not $Job.serviceName) { throw "RestartService requires serviceName." }
            Restart-Service -Name ([string]$Job.serviceName) -Force
            return @{ ok = $true; service = $Job.serviceName; state = "restart_requested" }
        }

        "OpenDevFirewallPort" {
            if (-not $Job.port) { throw "OpenDevFirewallPort requires port." }
            $port = [int]$Job.port
            if ($port -lt 1 -or $port -gt 65535) { throw "Invalid port." }
            $protocol = "TCP"
            if ($Job.protocol -and @("TCP","UDP") -contains ([string]$Job.protocol).ToUpperInvariant()) {
                $protocol = ([string]$Job.protocol).ToUpperInvariant()
            }
            $name = "Codex Dev Port $protocol $port"
            New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Allow -Protocol $protocol -LocalPort $port -Profile Private | Out-Null
            return @{ ok = $true; firewall_rule = $name; port = $port; protocol = $protocol; profile = "Private" }
        }

        "RegisterDevScheduledTask" {
            if (-not $Job.taskName) { throw "RegisterDevScheduledTask requires taskName." }
            if (-not $Job.scriptPath) { throw "RegisterDevScheduledTask requires scriptPath." }
            $taskName = [string]$Job.taskName
            if ($taskName -notmatch "^[A-Za-z0-9._ -]{1,80}$") { throw "Invalid taskName." }
            $script = Assert-TrustedPath -Path ([string]$Job.scriptPath)
            $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
            $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
            Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
            return @{ ok = $true; task = $taskName; script = $script }
        }

        default {
            throw "Unsupported elevated helper action: $($Job.action)"
        }
    }
}

Assert-Admin
New-DirectoryIfMissing -Path $Root
$queue = Join-Path $Root "queue"
$done = Join-Path $Root "done"
$failed = Join-Path $Root "failed"
$logs = Join-Path $Root "logs"
New-DirectoryIfMissing -Path $queue
New-DirectoryIfMissing -Path $done
New-DirectoryIfMissing -Path $failed
New-DirectoryIfMissing -Path $logs
$logPath = Join-Path $logs "helper.jsonl"

Write-JsonLog -LogPath $logPath -Record @{ event = "helper_start"; root = $Root; user = $env:USERNAME }

$jobs = Get-ChildItem -LiteralPath $queue -Filter "*.json" -File | Sort-Object LastWriteTime
foreach ($jobFile in $jobs) {
    $jobId = [System.IO.Path]::GetFileNameWithoutExtension($jobFile.Name)
    try {
        $job = Get-Content -LiteralPath $jobFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-JsonLog -LogPath $logPath -Record @{ event = "job_start"; job_id = $jobId; action = $job.action }
        $result = Invoke-HelperAction -Job $job
        $resultPath = Join-Path $done ($jobId + ".result.json")
        @{
            job_id = $jobId
            status = "ok"
            action = $job.action
            result = $result
            completed_at = (Get-Date).ToUniversalTime().ToString("o")
        } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
        Move-Item -LiteralPath $jobFile.FullName -Destination (Join-Path $done $jobFile.Name) -Force
        Write-JsonLog -LogPath $logPath -Record @{ event = "job_ok"; job_id = $jobId; action = $job.action }
    } catch {
        $resultPath = Join-Path $failed ($jobId + ".error.json")
        @{
            job_id = $jobId
            status = "failed"
            error = $_.Exception.Message
            completed_at = (Get-Date).ToUniversalTime().ToString("o")
        } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resultPath -Encoding UTF8
        Move-Item -LiteralPath $jobFile.FullName -Destination (Join-Path $failed $jobFile.Name) -Force
        Write-JsonLog -LogPath $logPath -Record @{ event = "job_failed"; job_id = $jobId; error = $_.Exception.Message }
    }
}

Write-JsonLog -LogPath $logPath -Record @{ event = "helper_stop"; processed = $jobs.Count }

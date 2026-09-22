param(
    [string]$Root
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

    # Match the practical trust semantics of the Claude helper: normalize the supplied
    # path lexically, then compare its full-path prefix against trusted roots. Do not
    # resolve junctions or symlinks. Trusted roots are user-writable by design; this is
    # an accepted single-owner tradeoff, not a sandbox.
    $resolved = [System.IO.Path]::GetFullPath($Path)

    # Resolve the running user's actual profile instead of assuming C:\Users\<name>.
    $trustedRoots = @(
        "C:\dev\",
        "$env:USERPROFILE\Documents\Codex\",
        "$env:USERPROFILE\.codex\",
        "$env:USERPROFILE\AppData\Local\Temp\CodexElevatedHelper\"
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

    # Robust child execution. Two traps avoided:
    #   - Sync ReadToEnd AFTER WaitForExit can deadlock on chatty children.
    #   - Start-Process redirection can hang when grandchildren inherit file handles.
    # Windows PowerShell 5.1 lacks ProcessStartInfo.ArgumentList, so build Arguments.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = (($Arguments | ForEach-Object {
        if ($_ -match '\s') { '"' + $_ + '"' } else { [string]$_ }
    }) -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()

    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        try { $proc.Kill() } catch {}
        throw "Process timed out: $FilePath"
    }
    [void]$outTask.Wait(5000)
    [void]$errTask.Wait(5000)

    return @{
        exit_code = $proc.ExitCode
        stdout = $(if ($outTask.IsCompleted) { $outTask.Result } else { "" })
        stderr = $(if ($errTask.IsCompleted) { $errTask.Result } else { "" })
    }
}

function Resolve-HelperRoot {
    # Single source of truth: an explicit -Root wins, else the pointer written at
    # install time, else the documented default.
    param([string]$Explicit)
    if ($Explicit -and (Test-Path -LiteralPath $Explicit)) { return $Explicit }
    $pointer = Join-Path $env:USERPROFILE ".codex\autonomy-kit\helper-root.json"
    if (Test-Path -LiteralPath $pointer) {
        try {
            $p = Get-Content -LiteralPath $pointer -Raw | ConvertFrom-Json
            if ($p.install_root -and (Test-Path -LiteralPath $p.install_root)) { return $p.install_root }
        } catch { }
    }
    return "C:\dev\CodexElevatedHelper"
}

function Resolve-Winget {
    # The winget App Execution Alias can fail inside non-interactive elevated
    # scheduled-task sessions. Resolve the real DesktopAppInstaller binary.
    $pkg = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending | Select-Object -First 1
    if ($pkg -and $pkg.InstallLocation) {
        $exe = Join-Path $pkg.InstallLocation "winget.exe"
        if (Test-Path -LiteralPath $exe) { return $exe }
    }
    $glob = Get-ChildItem "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($glob) { return $glob.FullName }
    throw "Could not resolve a real winget.exe (DesktopAppInstaller package not found)."
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
            $args = @("install", "--id", [string]$Job.packageId, "--exact", "--silent", "--disable-interactivity", "--accept-package-agreements", "--accept-source-agreements")
            if ($Job.scope -eq "user") { $args += @("--scope", "user") }
            return Invoke-LoggedProcess -FilePath (Resolve-Winget) -Arguments $args -TimeoutSeconds 3600
        }

        "WingetUpgrade" {
            if (-not $Job.packageId) { throw "WingetUpgrade requires packageId." }
            $args = @("upgrade", "--id", [string]$Job.packageId, "--exact", "--silent", "--disable-interactivity", "--accept-package-agreements", "--accept-source-agreements")
            return Invoke-LoggedProcess -FilePath (Resolve-Winget) -Arguments $args -TimeoutSeconds 3600
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
            # Use the resolved identity (DOMAIN\user or UPN) for explicitness. Note:
            # the bare $env:USERNAME form was live-tested on a domain-joined machine and
            # did resolve and run correctly, so this is a clarity choice, not a fix for
            # an observed defect. The resolved form is safer on renamed or ambiguous
            # accounts where the bare name could be unresolved.
            $taskUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
            $principal = New-ScheduledTaskPrincipal -UserId $taskUser -RunLevel Highest
            Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
            return @{ ok = $true; task = $taskName; script = $script }
        }

        default {
            throw "Unsupported elevated helper action: $($Job.action)"
        }
    }
}

# Allow the file to be dot-sourced for testing without executing the helper body.
# A test sets $env:CODEZ_HELPER_SOURCE_ONLY = "1" and gets the functions only.
if ($env:CODEX_HELPER_SOURCE_ONLY -eq "1") { return }

Assert-Admin
$Root = Resolve-HelperRoot -Explicit $Root
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

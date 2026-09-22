<#
.SYNOPSIS
    Executable regression tests for helper queueing and refresh behavior.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$kit = Split-Path $PSScriptRoot -Parent
$helper = Join-Path $kit "elevated-dev-helper\ElevatedDevHelper.ps1"
$invoker = Join-Path $kit "elevated-dev-helper\Invoke-ElevatedDevHelper.ps1"
$setup = Join-Path $kit "Setup-Autonomy.ps1"
$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param([string]$Name, [ValidateSet("PASS","FAIL","INFO")][string]$Status, [string]$Detail)
    $results.Add([pscustomobject]@{ Check = $Name; Status = $Status; Detail = $Detail })
}

function Publish-JsonAtomically {
    param([string]$Directory, [string]$Id, [hashtable]$Value)
    $tmp = Join-Path $Directory ($Id + ".tmp")
    $final = Join-Path $Directory ($Id + ".json")
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tmp -Encoding UTF8
    [System.IO.File]::Move($tmp, $final)
    return $final
}

$scratch = Join-Path $env:TEMP ("codex-helper-runtime-" + [guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Force -Path $scratch | Out-Null

try {
    # Reproduce the former race: add a second request after the worker has begun
    # processing a slow first request. The same worker must drain both requests.
    try {
        $root = Join-Path $scratch "queue-race"
        $queue = Join-Path $root "queue"
        $done = Join-Path $root "done"
        $failed = Join-Path $root "failed"
        $logs = Join-Path $root "logs"
        @($queue,$done,$failed,$logs) | ForEach-Object { New-Item -ItemType Directory -Force -Path $_ | Out-Null }

        $trustedTestDir = Join-Path $env:USERPROFILE ("AppData\Local\Temp\CodexElevatedHelper\runtime-test-" + [guid]::NewGuid().ToString("n"))
        New-Item -ItemType Directory -Force -Path $trustedTestDir | Out-Null
        $delayScript = Join-Path $trustedTestDir "delay.ps1"
        'Start-Sleep -Milliseconds 1200; Write-Output "first-complete"' | Set-Content -LiteralPath $delayScript -Encoding UTF8

        $firstId = "first-" + [guid]::NewGuid().ToString("n")
        $secondId = "second-" + [guid]::NewGuid().ToString("n")
        $null = Publish-JsonAtomically $queue $firstId @{ action = "RunTrustedPowerShellScript"; scriptPath = $delayScript }
        $logPath = Join-Path $logs "helper.jsonl"
        $worker = Start-Job -ScriptBlock {
            param($HelperPath,$QueuePath,$DonePath,$FailedPath,$LogPath)
            $env:CODEX_HELPER_SOURCE_ONLY = "1"
            . $HelperPath
            Remove-Item Env:\CODEX_HELPER_SOURCE_ONLY -ErrorAction SilentlyContinue
            Invoke-QueuedJobs -QueuePath $QueuePath -DonePath $DonePath -FailedPath $FailedPath -LogPath $LogPath
        } -ArgumentList $helper,$queue,$done,$failed,$logPath

        $deadline = (Get-Date).AddSeconds(10)
        while ((Get-Date) -lt $deadline) {
            if ((Test-Path -LiteralPath $logPath) -and ((Get-Content -LiteralPath $logPath -Raw) -match [regex]::Escape($firstId))) { break }
            Start-Sleep -Milliseconds 50
        }
        if (-not (Test-Path -LiteralPath $logPath) -or (Get-Content -LiteralPath $logPath -Raw) -notmatch [regex]::Escape($firstId)) {
            throw "worker did not begin the first request"
        }
        $null = Publish-JsonAtomically $queue $secondId @{ action = "CheckAdmin" }
        $null = Wait-Job -Job $worker -Timeout 20
        if ($worker.State -ne "Completed") { throw "queue worker did not complete: $($worker.State)" }
        $workerOutput = @(Receive-Job -Job $worker -ErrorAction Stop)
        $ok = (
            (Test-Path -LiteralPath (Join-Path $done ($firstId + ".result.json"))) -and
            (Test-Path -LiteralPath (Join-Path $done ($secondId + ".result.json"))) -and
            (@(Get-ChildItem -LiteralPath $queue -File).Count -eq 0) -and
            ([int]$workerOutput[-1] -eq 2)
        )
        Add-Result "queue_arrival_during_run" $(if ($ok) { "PASS" } else { "FAIL" }) "second job queued during first job; processed=$($workerOutput[-1]); queue empty=$(@(Get-ChildItem -LiteralPath $queue -File).Count -eq 0)"
    } catch {
        Add-Result "queue_arrival_during_run" "FAIL" $_.Exception.Message
    } finally {
        if ($worker) { Remove-Job -Job $worker -Force -ErrorAction SilentlyContinue }
        if ($trustedTestDir -and (Test-Path -LiteralPath $trustedTestDir)) { [System.IO.Directory]::Delete($trustedTestDir, $true) }
    }

    # Execute the real invoker against pointer metadata. This proves custom root/task
    # discovery and atomic publication rather than merely grepping for those strings.
    try {
        $profile = Join-Path $scratch "profile"
        $customRoot = Join-Path $scratch "custom-helper"
        $pointerDir = Join-Path $profile ".codex\autonomy-kit"
        New-Item -ItemType Directory -Force -Path $pointerDir | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $customRoot "queue") | Out-Null
        $customTask = "CodexHelperRuntimeTest-" + [guid]::NewGuid().ToString("n")
        @{ install_root = $customRoot; task_name = $customTask; invoker_script = $invoker } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $pointerDir "helper-root.json") -Encoding UTF8

        $oldProfile = $env:USERPROFILE
        $taskReceipt = Join-Path $scratch "task-receipt.txt"
        $env:USERPROFILE = $profile
        function Start-ScheduledTask { param([string]$TaskName) [System.IO.File]::WriteAllText($taskReceipt, $TaskName) }
        $json = (& $invoker -Action CheckAdmin | Out-String) | ConvertFrom-Json
        $env:USERPROFILE = $oldProfile
        Remove-Item Function:\Start-ScheduledTask -ErrorAction SilentlyContinue

        $queuedFiles = @(Get-ChildItem -LiteralPath (Join-Path $customRoot "queue") -Filter "*.json" -File)
        $tempFiles = @(Get-ChildItem -LiteralPath (Join-Path $customRoot "queue") -Filter "*.tmp" -File)
        $queued = Get-Content -LiteralPath $queuedFiles[0].FullName -Raw | ConvertFrom-Json
        $ok = ($json.root -eq $customRoot -and $json.task_name -eq $customTask -and
               [System.IO.File]::ReadAllText($taskReceipt) -eq $customTask -and
               $queuedFiles.Count -eq 1 -and $tempFiles.Count -eq 0 -and $queued.action -eq "CheckAdmin")
        Add-Result "invoker_custom_pointer_atomic" $(if ($ok) { "PASS" } else { "FAIL" }) "custom root/task used; one complete JSON published; no temp file remains"
    } catch {
        if ($oldProfile) { $env:USERPROFILE = $oldProfile }
        Remove-Item Function:\Start-ScheduledTask -ErrorAction SilentlyContinue
        Add-Result "invoker_custom_pointer_atomic" "FAIL" $_.Exception.Message
    }

    # Load Setup's real helper refresh function and exercise both a successful custom
    # install and a non-zero installer exit without UAC in the isolated fixture.
    try {
        $env:CODEX_SETUP_SOURCE_ONLY = "1"
        . $setup
        Remove-Item Env:\CODEX_SETUP_SOURCE_ONLY -ErrorAction SilentlyContinue

        $refreshRoot = Join-Path $scratch "refresh-root"
        New-Item -ItemType Directory -Force -Path $refreshRoot | Out-Null
        $refreshTask = "CustomRefreshTask"
        $info = [pscustomobject]@{
            Root = $refreshRoot
            TaskName = $refreshTask
            InvokerScript = (Join-Path $refreshRoot "Invoke-ElevatedDevHelper.ps1")
        }
        $sourceHelper = Join-Path $kit "elevated-dev-helper\ElevatedDevHelper.ps1"
        $sourceInvoker = Join-Path $kit "elevated-dev-helper\Invoke-ElevatedDevHelper.ps1"
        $successCmd = Join-Path $scratch "successful-refresh.cmd"
        @"
@echo off
copy /y "$sourceHelper" "$refreshRoot\ElevatedDevHelper.ps1" >nul
copy /y "$sourceInvoker" "$($info.InvokerScript)" >nul
exit /b 0
"@ | Set-Content -LiteralPath $successCmd -Encoding ASCII
        $task = Invoke-HelperInstallerAndVerify -InstallerPath $successCmd -InstallInfo $info `
            -ExpectedHelperPath $sourceHelper -ExpectedInvokerPath $sourceInvoker -NoElevation `
            -TaskLookup { param($name) if ($name -eq $refreshTask) { [pscustomobject]@{ TaskName = $name; State = "Ready" } } }
        $success = ($task.TaskName -eq $refreshTask)

        $failureCmd = Join-Path $scratch "failed-refresh.cmd"
        "@echo off`r`nexit /b 23`r`n" | Set-Content -LiteralPath $failureCmd -Encoding ASCII
        $failureCaught = $false
        try {
            $null = Invoke-HelperInstallerAndVerify -InstallerPath $failureCmd -InstallInfo $info `
                -ExpectedHelperPath $sourceHelper -ExpectedInvokerPath $sourceInvoker -NoElevation `
                -TaskLookup { [pscustomobject]@{ TaskName = $refreshTask } }
        } catch {
            $failureCaught = ($_.Exception.Message -match 'exit code 23')
        }
        Add-Result "setup_refresh_behavior" $(if ($success -and $failureCaught) { "PASS" } else { "FAIL" }) "custom root/task hashes verified; non-zero installer exit propagated=$failureCaught"
    } catch {
        Remove-Item Env:\CODEX_SETUP_SOURCE_ONLY -ErrorAction SilentlyContinue
        Add-Result "setup_refresh_behavior" "FAIL" $_.Exception.Message
    }

    try {
        $env:CODEX_HELPER_SOURCE_ONLY = "1"
        . $helper
        Remove-Item Env:\CODEX_HELPER_SOURCE_ONLY -ErrorAction SilentlyContinue
        $cases = @{
            '' = '""'
            'plain' = 'plain'
            'two words' = '"two words"'
            'a"b' = '"a\"b"'
            'C:\tail\' = 'C:\tail\'
            'C:\two words\' = '"C:\two words\\"'
        }
        $bad = @($cases.GetEnumerator() | Where-Object { (ConvertTo-WindowsCommandLineArgument -Argument $_.Key) -ne $_.Value })
        Add-Result "windows_argument_serialization" $(if ($bad.Count -eq 0) { "PASS" } else { "FAIL" }) "$($cases.Count) quoting cases; failures=$($bad.Count)"
    } catch {
        Add-Result "windows_argument_serialization" "FAIL" $_.Exception.Message
    }
} finally {
    if (Test-Path -LiteralPath $scratch) { [System.IO.Directory]::Delete($scratch, $true) }
}

""
$results | Format-Table -AutoSize | Out-String | Write-Host
$pass = @($results | Where-Object Status -eq "PASS").Count
$fail = @($results | Where-Object Status -eq "FAIL").Count
$infoCount = @($results | Where-Object Status -eq "INFO").Count
Write-Host ("SUMMARY: {0} PASS / {1} FAIL / {2} INFO" -f $pass,$fail,$infoCount)
if ($fail -gt 0) { exit 1 }

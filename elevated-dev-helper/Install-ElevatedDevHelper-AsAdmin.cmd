@echo off
setlocal
set "CODEX_HELPER_INSTALLER=%~dp0Install-ElevatedDevHelper.ps1"
set "CODEX_HELPER_INSTALL_ROOT=%~1"
set "CODEX_HELPER_TASK_NAME=%~2"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$root=$env:CODEX_HELPER_INSTALL_ROOT; $task=$env:CODEX_HELPER_TASK_NAME; $ptr=Join-Path $env:USERPROFILE '.codex\autonomy-kit\helper-root.json'; if ((-not $root -or -not $task) -and (Test-Path -LiteralPath $ptr)) { try { $meta=Get-Content -LiteralPath $ptr -Raw ^| ConvertFrom-Json; if (-not $root -and $meta.install_root) { $root=[string]$meta.install_root }; if (-not $task -and $meta.task_name) { $task=[string]$meta.task_name } } catch {} }; if (-not $root) { $root='C:\dev\CodexElevatedHelper' }; if (-not $task) { $task='CodexElevatedDevHelper' }; $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$env:CODEX_HELPER_INSTALLER+'"'),'-InstallRoot',('"'+$root+'"'),'-TaskName',('"'+$task+'"')); $p = Start-Process -FilePath powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList $args; exit $p.ExitCode"
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%

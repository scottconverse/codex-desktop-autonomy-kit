@echo off
setlocal
cd /d "%~dp0"
title Codex Autonomy Kit - Install
echo Installing / updating Codex Desktop Autonomy Kit...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-Autonomy.ps1"
set "code=%ERRORLEVEL%"
echo.
if not "%code%"=="0" (
  echo FAILED with exit code %code%.
  echo.
  pause
  exit /b %code%
)

echo.
echo Running status check...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Doctor-Autonomy.ps1"
set "code=%ERRORLEVEL%"
if not "%code%"=="0" (
  echo.
  echo Doctor failed with exit code %code%.
  echo.
  pause
  exit /b %code%
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "$repoRoot='%~dp0elevated-dev-helper'; $root='C:\dev\CodexElevatedHelper'; $ptr=Join-Path $env:USERPROFILE '.codex\autonomy-kit\helper-root.json'; $installedInvoker=$null; if (Test-Path $ptr) { try { $meta=Get-Content -LiteralPath $ptr -Raw | ConvertFrom-Json; if ($meta.install_root) { $root=[string]$meta.install_root }; if ($meta.invoker_script) { $installedInvoker=[string]$meta.invoker_script } } catch {} }; if (-not $installedInvoker) { $installedInvoker=Join-Path $root 'Invoke-ElevatedDevHelper.ps1' }; $pairs=@(@((Join-Path $repoRoot 'ElevatedDevHelper.ps1'),(Join-Path $root 'ElevatedDevHelper.ps1')), @((Join-Path $repoRoot 'Invoke-ElevatedDevHelper.ps1'),$installedInvoker)); foreach ($pair in $pairs) { if ((-not (Test-Path -LiteralPath $pair[1])) -or ((Get-FileHash -Algorithm SHA256 -LiteralPath $pair[0]).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $pair[1]).Hash)) { exit 2 } }; exit 0"
set "helper_stale=%ERRORLEVEL%"
if "%helper_stale%"=="2" (
  echo.
  echo The elevated helper is installed but not current.
  echo Refreshing it keeps admin-level installs/services/firewall actions on the latest helper.
  echo Windows will ask for administrator approval if you choose yes.
  echo.
  choice /C YN /N /M "Refresh elevated helper now? [Y/N] "
  if not errorlevel 2 (
    echo.
    call "%~dp0elevated-dev-helper\Install-ElevatedDevHelper-AsAdmin.cmd"
    set "code=%ERRORLEVEL%"
    if not "%code%"=="0" (
      echo.
      echo Helper refresh failed with exit code %code%.
      echo.
      pause
      exit /b %code%
    )
    echo.
    echo Re-running status check...
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Doctor-Autonomy.ps1"
  )
)
echo.
echo DONE. Restart Codex Desktop so changes load.
echo.
pause
exit /b 0

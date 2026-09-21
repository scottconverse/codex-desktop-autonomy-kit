@echo off
setlocal
cd /d "%~dp0"
title Codex Autonomy Kit - Uninstall
echo This removes the Codex Autonomy Kit config layer.
echo Tooling and helper files are left alone unless you use the PowerShell script manually.
echo.
choice /C YN /N /M "Continue? [Y/N] "
if errorlevel 2 exit /b 1
echo.
set "helper_arg="
choice /C YN /N /M "Also unregister the elevated helper task? [Y/N] "
if not errorlevel 2 set "helper_arg=-RemoveHelper"
echo.
if defined helper_arg (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall-Autonomy.ps1" -RemoveHelper
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall-Autonomy.ps1"
)
set "code=%ERRORLEVEL%"
echo.
if "%code%"=="0" (
  echo DONE. Restart Codex Desktop so changes load.
) else (
  echo FAILED with exit code %code%.
)
echo.
pause
exit /b %code%

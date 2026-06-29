@echo off
setlocal
cd /d "%~dp0"
title Codex Autonomy Kit - Install
echo Installing Codex Desktop Autonomy Kit...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-Autonomy.ps1"
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

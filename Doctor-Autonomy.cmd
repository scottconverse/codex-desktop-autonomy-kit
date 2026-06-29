@echo off
setlocal
cd /d "%~dp0"
title Codex Autonomy Kit - Doctor
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Doctor-Autonomy.ps1"
set "code=%ERRORLEVEL%"
echo.
pause
exit /b %code%

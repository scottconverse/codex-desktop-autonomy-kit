@echo off
setlocal
cd /d "%~dp0"
title Codex Autonomy Kit - Tests
echo Running Codex Autonomy Kit tests...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\Test-NoHardcodedPaths.ps1"
if errorlevel 1 goto fail
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\Test-InstallSurface.ps1"
if errorlevel 1 goto fail
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\Test-ScriptSyntax.ps1"
if errorlevel 1 goto fail
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\Test-AutonomyKit.ps1"
if errorlevel 1 goto fail
echo.
echo DONE. All tests passed.
echo.
pause
exit /b 0

:fail
set "code=%ERRORLEVEL%"
echo.
echo FAILED with exit code %code%.
echo.
pause
exit /b %code%

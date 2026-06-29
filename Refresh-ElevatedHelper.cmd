@echo off
setlocal
cd /d "%~dp0"
title Codex Autonomy Kit - Refresh Elevated Helper
echo Refreshing the elevated helper.
echo Windows will ask for administrator approval.
echo.
call "%~dp0elevated-dev-helper\Install-ElevatedDevHelper-AsAdmin.cmd"
set "code=%ERRORLEVEL%"
echo.
if "%code%"=="0" (
  echo DONE. Run Doctor-Autonomy.cmd and confirm helper script parity is current.
) else (
  echo FAILED with exit code %code%.
)
echo.
pause
exit /b %code%

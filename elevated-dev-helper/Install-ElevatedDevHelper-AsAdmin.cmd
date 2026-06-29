@echo off
setlocal
set "CODEX_HELPER_INSTALLER=%~dp0Install-ElevatedDevHelper.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$p = Start-Process -FilePath powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$env:CODEX_HELPER_INSTALLER); exit $p.ExitCode"
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%

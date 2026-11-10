@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0b_player\tool\release.ps1" %*
set "EXITCODE=%errorlevel%"
echo.
if not "%EXITCODE%"=="0" echo Release failed - see the messages above.
pause
exit /b %EXITCODE%

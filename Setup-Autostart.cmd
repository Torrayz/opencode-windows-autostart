@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0Autostart.ps1" Install
set "result=%errorlevel%"
pause
exit /b %result%

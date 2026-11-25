@echo off
setlocal
set "AUTOSTART_INSTALLER=%~dp0Autostart.ps1"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "$argsForSetup = '-NoProfile -ExecutionPolicy RemoteSigned -File ' + [char]34 + $env:AUTOSTART_INSTALLER + [char]34 + ' Install'; exit (Start-Process (Join-Path $PSHOME 'powershell.exe') -Verb RunAs -ArgumentList $argsForSetup -Wait -PassThru -ErrorAction Stop).ExitCode"
set "result=%errorlevel%"
pause
exit /b %result%

@echo off

cd /d "%~dp0"

%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0install_gui.ps1"

exit /b %errorlevel%


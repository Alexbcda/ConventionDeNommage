@echo off
cd /d "%~dp0"

set "ASSISTANT_PDF=%~1"

if not exist "%~dp0src\LaunchAssistant.ps1" (
    echo [ERREUR] Fichier introuvable : %~dp0src\LaunchAssistant.ps1
    pause
    exit /b 1
)

%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -STA -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "%~dp0src\LaunchAssistant.ps1"
exit /b %ERRORLEVEL%

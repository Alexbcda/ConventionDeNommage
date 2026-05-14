@echo off
setlocal

echo ============================================
echo  Convention de Nommage - Build Installer
echo ============================================
echo.

:: Verifier que Inno Setup est installe
set "ISCC="
if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" (
    set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
) else if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" (
    set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
) else (
    echo ERREUR : Inno Setup 6 non trouve.
    echo Installez-le depuis https://jrsoftware.org/isdl.php
    exit /b 1
)

echo [OK] Inno Setup trouve : %ISCC%
echo.

:: Verifier les fichiers source requis
set "ROOT=%~dp0.."
if not exist "%ROOT%\src\Main.ps1" (
    echo ERREUR : src\Main.ps1 introuvable
    exit /b 1
)
if not exist "%ROOT%\Launcher.cmd" (
    echo ERREUR : Launcher.cmd introuvable
    exit /b 1
)
if not exist "%ROOT%\config\runtime.json" (
    echo ERREUR : config\runtime.json introuvable
    exit /b 1
)
echo [OK] Fichiers source verifies
echo.

:: Creer le dossier output
if not exist "%ROOT%\output" mkdir "%ROOT%\output"

:: Determiner le mode de build
if "%1"=="full" (
    echo [BUILD] Mode FULL (avec runtime Ghostscript + Poppler)
    echo.
    "%ISCC%" /DBUNDLE_RUNTIME "%~dp0ConventionDeNommage.iss"
) else (
    echo [BUILD] Mode LITE (sans runtime bundle)
    echo.
    "%ISCC%" "%~dp0ConventionDeNommage.iss"
)

if %errorlevel% neq 0 (
    echo.
    echo ERREUR : La compilation a echoue.
    exit /b %errorlevel%
)

echo.
echo ============================================
echo [OK] Installateur cree dans output\
echo ============================================
echo.
echo Commandes de deploiement :
echo   Installation silencieuse : output\ConventionDeNommage-Setup-1.0.0.exe /VERYSILENT /NORESTART /LOG="install.log"
echo   Desinstallation          : "%%ProgramFiles%%\ConventionDeNommage\unins000.exe" /VERYSILENT /NORESTART
echo.

endlocal

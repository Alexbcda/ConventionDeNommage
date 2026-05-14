<#
.SYNOPSIS
    Wrapper d'installation pour deploiement Intune/SCCM.
    Execute l'installeur Inno Setup avec logging standardise.
.PARAMETER SetupExe
    Chemin vers l'installeur. Par defaut : meme dossier que ce script.
.PARAMETER Action
    install ou uninstall.
#>
[CmdletBinding()]
param(
    [string]$SetupExe = '',
    [ValidateSet('install', 'uninstall')]
    [string]$Action = 'install'
)

$ErrorActionPreference = 'Stop'
$logDir = "${env:ProgramData}\ConventionDeNommage\Logs"
if (-not (Test-Path -LiteralPath $logDir -PathType Container)) {
    $null = New-Item -Path $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue
}

$timestamp = [datetime]::Now.ToString('yyyyMMdd-HHmmss')

if ($Action -eq 'install') {
    if ([string]::IsNullOrWhiteSpace($SetupExe)) {
        $SetupExe = Join-Path $PSScriptRoot 'ConventionDeNommage-Setup-1.0.0.exe'
    }
    if (-not (Test-Path -LiteralPath $SetupExe -PathType Leaf)) {
        Write-Error "Installeur introuvable : $SetupExe"
        exit 1603
    }

    $logFile = Join-Path $logDir "install-$timestamp.log"
    $args = @(
        '/VERYSILENT',
        '/NORESTART',
        '/SUPPRESSMSGBOXES',
        "/LOG=`"$logFile`""
    )

    Write-Output "[INSTALL] Demarrage : $SetupExe"
    Write-Output "[INSTALL] Log : $logFile"

    $proc = Start-Process -FilePath $SetupExe -ArgumentList $args -Wait -PassThru -NoNewWindow
    $exitCode = $proc.ExitCode

    Write-Output "[INSTALL] Termine avec code : $exitCode"

    if ($exitCode -eq 0) {
        # Post-install health check
        $healthScript = "${env:ProgramFiles}\ConventionDeNommage\install\Install.ps1"
        if (Test-Path -LiteralPath $healthScript -PathType Leaf) {
            Write-Output "[INSTALL] Validation post-install..."
            & powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File $healthScript -Silent 2>&1 | Out-Null
        }
    }

    exit $exitCode
}
else {
    $uninstaller = "${env:ProgramFiles}\ConventionDeNommage\unins000.exe"
    if (-not (Test-Path -LiteralPath $uninstaller -PathType Leaf)) {
        Write-Output "[UNINSTALL] Application non installee (unins000.exe absent)"
        exit 0
    }

    $logFile = Join-Path $logDir "uninstall-$timestamp.log"
    $args = @(
        '/VERYSILENT',
        '/NORESTART',
        "/LOG=`"$logFile`""
    )

    Write-Output "[UNINSTALL] Demarrage : $uninstaller"
    Write-Output "[UNINSTALL] Log : $logFile"

    $proc = Start-Process -FilePath $uninstaller -ArgumentList $args -Wait -PassThru -NoNewWindow
    $exitCode = $proc.ExitCode

    Write-Output "[UNINSTALL] Termine avec code : $exitCode"
    exit $exitCode
}

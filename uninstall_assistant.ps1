# uninstall_assistant.ps1 - Desinstallation ASSISTANT (utilisateur courant)
param(
    [string]$InstallDir = "$env:LOCALAPPDATA\ASSISTANT"
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = "$env:LOCALAPPDATA\ASSISTANT"
}

Write-Host "Desinstallation ASSISTANT depuis : $InstallDir" -ForegroundColor Cyan

$shortcuts = @(
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'ASSISTANT.lnk'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\ASSISTANT.lnk'),
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\ASSISTANT.lnk')
)
foreach ($lnk in $shortcuts) {
    if (Test-Path -LiteralPath $lnk) {
        Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue
        Write-Host "Raccourci supprime : $lnk"
    }
}

$regKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ASSISTANT_EliseAlpes'
if (Test-Path -LiteralPath $regKey) {
    Remove-Item -LiteralPath $regKey -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'Entree registre Programmes et fonctionnalites supprimee'
}

$pdfContextKey = 'HKCU:\Software\Classes\SystemFileAssociations\.pdf\shell\ASSISTANT'
if (Test-Path -LiteralPath $pdfContextKey) {
    Remove-Item -LiteralPath $pdfContextKey -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'Menu contextuel PDF supprime'
}

if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Dossier supprime : $InstallDir" -ForegroundColor Green
}
else {
    Write-Host "Dossier deja absent : $InstallDir" -ForegroundColor Yellow
}

Write-Host 'Desinstallation terminee.' -ForegroundColor Green

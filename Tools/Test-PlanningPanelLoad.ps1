#Requires -Version 5.1
param([string]$InstallDir = 'C:\ASSISTANT')

Write-Host '========================================' -ForegroundColor Cyan
Write-Host '   TEST CHARGEMENT PLANNING' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

$panelPath = Join-Path $InstallDir 'src\ODM\PdfPlanningOptimizer\PlanningRebuilderPanel.ps1'
$content = Get-Content -LiteralPath $panelPath -Raw

$engineAtTop = $content -match 'PlanningRebuilder\.ps1'
Write-Host "Moteur en tete : $(if ($engineAtTop) { 'OK' } else { 'ECHEC' })" -ForegroundColor $(if ($engineAtTop) { 'Green' } else { 'Red' })

$stylesPath = Join-Path $InstallDir 'src\Common\Styles.ps1'
try {
    . $stylesPath
    Write-Host 'Styles.ps1 seul (sans Add-Type prealable) : OK' -ForegroundColor Green
}
catch {
    Write-Host "Styles.ps1 : ECHEC - $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$src = Join-Path $InstallDir 'src'
try {
    . (Join-Path $src 'Common\CnsSharePointConnector.ps1')
    . (Join-Path $src 'Common\CnsSharePointUI.ps1')
    . (Join-Path $src 'Config.ps1')
    . $panelPath
    Write-Host 'Panel charge : OK' -ForegroundColor Green
}
catch {
    Write-Host "Panel charge : ECHEC - $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

foreach ($fn in @('Show-PlanningRebuilderPanel', 'Safe-UpdateUIControl', 'Update-PlanningExcelPathLabel')) {
    if (Get-Command $fn -ErrorAction SilentlyContinue) {
        Write-Host "$fn : OK" -ForegroundColor Green
    }
    else {
        Write-Host "$fn : MANQUANT" -ForegroundColor Red
    }
}

$ver = Get-Content (Join-Path $InstallDir 'version.txt') -Raw
Write-Host "Version : $($ver.Trim())" -ForegroundColor Cyan

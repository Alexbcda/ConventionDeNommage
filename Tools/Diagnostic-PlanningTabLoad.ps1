#Requires -Version 5.1
param([string]$InstallDir = 'C:\ASSISTANT')

Write-Host '========================================' -ForegroundColor Cyan
Write-Host '   DIAGNOSTIC - CHARGEMENT PLANNING' -ForegroundColor Cyan
Write-Host "   $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Gray
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

$guiPath = Join-Path $InstallDir 'src\GUI.ps1'
$panelPath = Join-Path $InstallDir 'src\ODM\PdfPlanningOptimizer\PlanningRebuilderPanel.ps1'

Write-Host '1. ANALYSE DE GUI.ps1' -ForegroundColor Yellow
if (-not (Test-Path -LiteralPath $guiPath)) {
    Write-Host "  Fichier introuvable : $guiPath" -ForegroundColor Red
    exit 1
}

$guiContent = Get-Content $guiPath -Raw

$imports = [regex]::Matches($guiContent, 'Import-Module[^;\r\n]*Planning[^;\r\n]*')
if ($imports.Count -gt 0) {
    Write-Host '  IMPORTS MODULE PLANNING TROUVES :' -ForegroundColor Red
    foreach ($import in $imports) {
        Write-Host "    - $($import.Value)" -ForegroundColor Gray
    }
}
else {
    Write-Host '  Aucun Import-Module planning dans GUI.ps1' -ForegroundColor Green
}

$eagerDot = $guiContent -match '\.\s*"\$scriptDir\\ODM\\PdfPlanningOptimizer\\PlanningRebuilderPanel\.ps1"'
$lazyEnsure = $guiContent -match 'function Ensure-PlanningTabLoaded'
$bgPreload = $guiContent -match 'Start-PlanningBackgroundPreload'
$showAtBuild = $guiContent -match 'Show-PlanningRebuilderPanel'

Write-Host "  Dot-source PlanningRebuilderPanel au demarrage : $(if ($eagerDot) { 'OUI' } else { 'NON' })" -ForegroundColor $(if ($eagerDot) { 'Green' } else { 'Yellow' })
Write-Host "  Show-PlanningRebuilderPanel a la construction onglet : $(if ($showAtBuild) { 'OUI' } else { 'NON' })" -ForegroundColor $(if ($showAtBuild) { 'Green' } else { 'Yellow' })
Write-Host "  Ensure-PlanningTabLoaded (lazy hotfix) : $(if ($lazyEnsure) { 'OUI' } else { 'NON' })" -ForegroundColor $(if ($lazyEnsure) { 'Red' } else { 'Green' })
Write-Host "  Start-PlanningBackgroundPreload : $(if ($bgPreload) { 'OUI' } else { 'NON' })" -ForegroundColor $(if ($bgPreload) { 'Yellow' } else { 'Green' })
Write-Host ''

Write-Host '2. ANALYSE DE PlanningRebuilderPanel.ps1' -ForegroundColor Yellow
if (Test-Path -LiteralPath $panelPath) {
    $panelContent = Get-Content $panelPath -Raw
    $lines = ($panelContent -split "`n").Count
    $engineAtTop = $panelContent -match '\.\s*"\$PSScriptRoot\\Services\\PlanningRebuilder\.ps1"'
    $uiHelpers = $panelContent -match 'PlanningUIHelpers'
    Write-Host "  Lignes : $lines" -ForegroundColor Gray
    Write-Host "  Moteur PlanningRebuilder.ps1 charge en tete : $(if ($engineAtTop) { 'OUI (v1.0.18)' } else { 'NON (hotfix)' })" -ForegroundColor $(if ($engineAtTop) { 'Green' } else { 'Yellow' })
    Write-Host "  Dependance PlanningUIHelpers : $(if ($uiHelpers) { 'OUI' } else { 'NON' })" -ForegroundColor Gray
}
else {
    Write-Host '  Fichier introuvable' -ForegroundColor Red
}
Write-Host ''

Write-Host '3. FICHIERS HOTFIX' -ForegroundColor Yellow
$hotfixFiles = @(
    'src\ODM\PdfPlanningOptimizer\PlanningUILightImport.psm1',
    'src\ODM\PdfPlanningOptimizer\PlanningEngineImport.psm1',
    'src\ODM\PdfPlanningOptimizer\PlanningLoadTiming.ps1',
    'src\ODM\PdfPlanningOptimizer\PlanningUIHelpers.ps1',
    'Tools\Diagnostic-PlanningSlowLoad.ps1'
)
foreach ($rel in $hotfixFiles) {
    $file = Join-Path $InstallDir $rel
    if (Test-Path -LiteralPath $file) {
        $size = (Get-Item -LiteralPath $file).Length
        Write-Host "  $(Split-Path $rel -Leaf) ($([math]::Round($size / 1KB, 2)) KB) — present, inutilise si restauration OK" -ForegroundColor Gray
    }
    else {
        Write-Host "  $(Split-Path $rel -Leaf) — absent" -ForegroundColor DarkGray
    }
}

$versionFile = Join-Path $InstallDir 'version.txt'
if (Test-Path -LiteralPath $versionFile) {
    Write-Host ''
    Write-Host "Version installee : $((Get-Content -LiteralPath $versionFile -Raw).Trim())" -ForegroundColor Cyan
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '   RESUME' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
if ($eagerDot -and $showAtBuild -and -not $lazyEnsure) {
    Write-Host 'Comportement v1.0.18 restaure : planning charge au demarrage, onglet instantane au clic.' -ForegroundColor Green
}
elseif ($lazyEnsure) {
    Write-Host 'Comportement hotfix actif : chargement differe au clic (risque 2 min sur poste lent).' -ForegroundColor Red
}
else {
    Write-Host 'Configuration intermediaire — verifier manuellement.' -ForegroundColor Yellow
}

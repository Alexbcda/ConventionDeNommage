#Requires -Version 5.1
param([string]$InstallDir = 'C:\ASSISTANT')

$ErrorActionPreference = 'Continue'
$result = [ordered]@{
    GUI_restaure       = $false
    Panel_restaure     = $false
    Version_correcte   = $false
    UI_helpers_fichier = $false
    UI_runtime_panel   = $false
    ImportExcel_bundle = $false
    ImportExcel_module = $false
    Graph_module       = $false
}

Write-Host '========================================' -ForegroundColor Cyan
Write-Host '   AUDIT DU BUILD HOTFIX7-RESTORE' -ForegroundColor Cyan
Write-Host "   $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Gray
Write-Host "   InstallDir: $InstallDir" -ForegroundColor Gray
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

$src = Join-Path $InstallDir 'src'
$guiPath = Join-Path $src 'GUI.ps1'
$panelPath = Join-Path $src 'ODM\PdfPlanningOptimizer\PlanningRebuilderPanel.ps1'
$helperPath = Join-Path $src 'ODM\PdfPlanningOptimizer\PlanningUIHelpers.ps1'

# 1. GUI.ps1
Write-Host '1. GUI.ps1' -ForegroundColor Yellow
if (Test-Path -LiteralPath $guiPath) {
    $gui = Get-Content -LiteralPath $guiPath -Raw
    $hasPlanningImport = $gui -match 'Import-Module.*Planning'
    $hasEnsure = $gui -match 'function Ensure-PlanningTabLoaded'
    $hasBgPreload = $gui -match 'Start-PlanningBackgroundPreload'
    $hasEagerDot = $gui -match 'PdfPlanningOptimizer\\PlanningRebuilderPanel\.ps1'
    $hasShowAtBuild = $gui -match 'Show-PlanningRebuilderPanel'

    if (-not $hasPlanningImport -and -not $hasEnsure -and $hasEagerDot -and $hasShowAtBuild) {
        Write-Host '  OK : dot-source au demarrage, pas de lazy load' -ForegroundColor Green
        $result.GUI_restaure = $true
    }
    else {
        Write-Host '  PROBLEME GUI :' -ForegroundColor Red
        if ($hasPlanningImport) { Write-Host '    - Import-Module Planning present' -ForegroundColor Red }
        if ($hasEnsure) { Write-Host '    - Ensure-PlanningTabLoaded present' -ForegroundColor Red }
        if ($hasBgPreload) { Write-Host '    - Start-PlanningBackgroundPreload present' -ForegroundColor Red }
        if (-not $hasEagerDot) { Write-Host '    - dot-source PlanningRebuilderPanel absent' -ForegroundColor Red }
    }

    if ($hasEnsure) {
        Write-Host '  Ensure-PlanningTabLoaded : PRESENT (hotfix, pas restore)' -ForegroundColor Red
    }
    else {
        Write-Host '  Ensure-PlanningTabLoaded : absent (attendu hotfix7)' -ForegroundColor Green
    }
}
else { Write-Host '  GUI.ps1 introuvable' -ForegroundColor Red }
Write-Host ''

# 2. PlanningRebuilderPanel.ps1
Write-Host '2. PlanningRebuilderPanel.ps1' -ForegroundColor Yellow
if (Test-Path -LiteralPath $panelPath) {
    $panel = Get-Content -LiteralPath $panelPath -Raw
    $hasEngine = $panel -match 'Services\\PlanningRebuilder\.ps1'
    $needsHelpers = $panel -match 'PlanningUIHelpers\.ps1'
    $inlineSafe = $panel -match 'function Safe-UpdateUIControl'
    $inlineLabel = $panel -match 'function Update-PlanningExcelPathLabel'

    if ($hasEngine -and -not $needsHelpers) {
        Write-Host '  OK : moteur en tete, pas de dependance PlanningUIHelpers' -ForegroundColor Green
        $result.Panel_restaure = $true
    }
    else {
        Write-Host '  Panel non restaure ou mixte :' -ForegroundColor Red
        if (-not $hasEngine) { Write-Host '    - PlanningRebuilder.ps1 pas en tete' -ForegroundColor Red }
        if ($needsHelpers) { Write-Host '    - Require PlanningUIHelpers (version hotfix)' -ForegroundColor Red }
    }
    Write-Host "  Safe-UpdateUIControl inline : $(if ($inlineSafe) { 'OUI' } else { 'NON' })"
    Write-Host "  Update-PlanningExcelPathLabel inline : $(if ($inlineLabel) { 'OUI' } else { 'NON' })"
}
else { Write-Host '  Panel introuvable' -ForegroundColor Red }
Write-Host ''

# 3. PlanningUIHelpers.ps1 (fichier orphelin hotfix)
Write-Host '3. PlanningUIHelpers.ps1' -ForegroundColor Yellow
if (Test-Path -LiteralPath $helperPath) {
    $h = Get-Content -LiteralPath $helperPath -Raw
    $result.UI_helpers_fichier = ($h -match 'function Safe-UpdateUIControl') -and ($h -match 'function Update-PlanningExcelPathLabel')
    Write-Host '  Fichier present (hotfix legacy) — NON charge par panel restaure' -ForegroundColor DarkYellow
    Write-Host "  Fonctions definies dans fichier : $(if ($result.UI_helpers_fichier) { 'OUI' } else { 'NON' })"
}
else {
    Write-Host '  Absent (OK pour v1.0.18 restore)' -ForegroundColor Green
}
Write-Host ''

# 4. Version
Write-Host '4. version.txt' -ForegroundColor Yellow
$versionPath = Join-Path $InstallDir 'version.txt'
if (Test-Path -LiteralPath $versionPath) {
    $version = (Get-Content -LiteralPath $versionPath -Raw).Trim()
    Write-Host "  Version : $version" -ForegroundColor Gray
    $result.Version_correcte = $version -match 'hotfix7'
    if ($result.Version_correcte) { Write-Host '  OK hotfix7' -ForegroundColor Green }
    else { Write-Host '  ATTENTION : version.txt pas a jour (fichiers peuvent etre restores quand meme)' -ForegroundColor Yellow }
}
Write-Host ''

# 5. Runtime — fonctions apres dot-source (comme demarrage reel)
Write-Host '5. RUNTIME (dot-source chaine demarrage)' -ForegroundColor Yellow
try {
    $global:WinFormsInitialized = $true
    $global:WinFormsApplicationInitialized = $true
    . (Join-Path $src 'Common\QuietConsole.ps1')
    . (Join-Path $src 'Common\Styles.ps1')
    . (Join-Path $src 'Common\CnsSharePointConnector.ps1')
    . (Join-Path $src 'Common\CnsSharePointUI.ps1')
    . (Join-Path $src 'Config.ps1')
    . $panelPath

    $runtimeChecks = @(
        'Safe-UpdateUIControl',
        'Update-PlanningExcelPathLabel',
        'Show-PlanningRebuilderPanel',
        'Update-PlanningSharePointUiState',
        'Start-SharePointConnectionBackground'
    )
    $allOk = $true
    foreach ($name in $runtimeChecks) {
        $cmd = Get-Command -Name $name -ErrorAction SilentlyContinue
        if ($cmd) {
            Write-Host "  OK $name" -ForegroundColor Green
        }
        else {
            Write-Host "  MANQUANT $name" -ForegroundColor Red
            $allOk = $false
        }
    }
    $result.UI_runtime_panel = $allOk
}
catch {
    Write-Host "  ERREUR dot-source : $($_.Exception.Message)" -ForegroundColor Red
    $result.UI_runtime_panel = $false
}
Write-Host ''

# 6. ImportExcel
Write-Host '6. ImportExcel' -ForegroundColor Yellow
$bundle = Join-Path $InstallDir 'runtime\ImportExcel\ImportExcel.psd1'
$result.ImportExcel_bundle = Test-Path -LiteralPath $bundle
if ($result.ImportExcel_bundle) { Write-Host '  OK bundle embarque' -ForegroundColor Green }
else { Write-Host '  Bundle embarque absent' -ForegroundColor Yellow }

$ie = Get-Module -Name ImportExcel -ListAvailable -ErrorAction SilentlyContinue
$result.ImportExcel_module = ($null -ne $ie)
if ($ie) { Write-Host "  Module installe : $($ie[0].Version)" -ForegroundColor Green }
else { Write-Host '  Module PSGallery non installe (bundle peut suffire)' -ForegroundColor Yellow }
Write-Host ''

# 7. Microsoft.Graph
Write-Host '7. Microsoft.Graph' -ForegroundColor Yellow
$graph = Get-Module -Name Microsoft.Graph.Authentication -ListAvailable -ErrorAction SilentlyContinue
$result.Graph_module = ($null -ne $graph)
if ($graph) { Write-Host '  Module installe' -ForegroundColor Green }
else { Write-Host '  Module NON installe — connexion SharePoint Graph echouera' -ForegroundColor Yellow }
Write-Host ''

# Resume
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '   RESUME' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
$buildOk = $result.GUI_restaure -and $result.Panel_restaure -and $result.UI_runtime_panel
if ($buildOk) {
    Write-Host 'BUILD HOTFIX7 : FICHIERS ET RUNTIME OK' -ForegroundColor Green
}
else {
    Write-Host 'BUILD HOTFIX7 : PROBLEME DETECTE' -ForegroundColor Red
}
Write-Host ''
foreach ($k in $result.Keys) {
    $v = $result[$k]
    $icon = if ($v) { '[OK]' } else { '[--]' }
    Write-Host "  $icon $k"
}
Write-Host ''
if (-not $result.Graph_module) {
    Write-Host 'Microsoft.Graph : installer sur poste cible (externe au build hotfix7)' -ForegroundColor Yellow
}
if (-not $result.ImportExcel_bundle -and -not $result.ImportExcel_module) {
    Write-Host 'ImportExcel : ni bundle ni module — Excel planning echouera' -ForegroundColor Red
}
if ($result.UI_runtime_panel -and $buildOk) {
    Write-Host 'Si plantage Update-PlanningExcelPathLabel sur poste cible : deployment mixte (panel hotfix + GUI restore) ou ancienne version en cache.' -ForegroundColor Yellow
}

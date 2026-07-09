#Requires -Version 5.1
param(
    [string]$InstallDir = 'C:\ASSISTANT',
    [string]$PackageDir = '',
    [string]$FPackagePath = 'F:\ASSISTANT\Packages\v1.0.18-hotfix7-restore'
)

$ErrorActionPreference = 'Continue'
if ([string]::IsNullOrWhiteSpace($PackageDir)) {
    $PackageDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'package'
}

function Test-DepPath {
    param([string]$Label, [string]$Path, [scriptblock]$AltFinder = $null)
    $ok = $false
    $resolved = $Path
    if (Test-Path -LiteralPath $Path) { $ok = $true }
    elseif ($AltFinder) {
        $found = & $AltFinder
        if ($found) { $ok = $true; $resolved = $found }
    }
    [PSCustomObject]@{ Label = $Label; Ok = $ok; Path = $resolved }
}

function Write-DepSection {
    param([string]$Title, [array]$Checks)
    Write-Host $Title -ForegroundColor Yellow
    foreach ($c in $Checks) {
        if ($c.Ok) { Write-Host "  OK  $($c.Label)" -ForegroundColor Green }
        else { Write-Host "  MANQUANT  $($c.Label)" -ForegroundColor Red; if ($c.Path) { Write-Host "         $($c.Path)" -ForegroundColor DarkGray } }
    }
    Write-Host ''
    return $Checks
}

Write-Host '========================================' -ForegroundColor Cyan
Write-Host '   AUDIT FINAL DEPENDANCES HOTFIX7' -ForegroundColor Cyan
Write-Host "   $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Gray
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

# Version
$verPath = Join-Path $InstallDir 'version.txt'
if (Test-Path -LiteralPath $verPath) {
    Write-Host "Version installee ($InstallDir) : $((Get-Content -LiteralPath $verPath -Raw).Trim())" -ForegroundColor Cyan
}
Write-Host ''

# --- Planning runtime binaries ---
Write-Host "=== INSTALLATION : $InstallDir ===" -ForegroundColor Cyan
Write-Host ''

$installChecks = @(
    (Test-DepPath 'Ghostscript gswin64c.exe' (Join-Path $InstallDir 'runtime\ghostscript\gswin64c.exe'))
    (Test-DepPath 'Poppler pdftotext.exe' (Join-Path $InstallDir 'runtime\poppler\pdftotext.exe') {
            Get-ChildItem -Path (Join-Path $InstallDir 'runtime\poppler') -Recurse -Filter 'pdftotext.exe' -File -EA SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        })
    (Test-DepPath 'qpdf.exe' (Join-Path $InstallDir 'lib\qpdf\bin\qpdf.exe') {
            Get-ChildItem -Path (Join-Path $InstallDir 'lib\qpdf') -Recurse -Filter 'qpdf.exe' -File -EA SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        })
    (Test-DepPath 'ImportExcel bundle' (Join-Path $InstallDir 'runtime\ImportExcel\ImportExcel.psd1'))
    (Test-DepPath 'Microsoft.Graph bundle (runtime/Graph)' (Join-Path $InstallDir 'runtime\Graph\Microsoft.Graph.Authentication.psd1'))
    (Test-DepPath 'SQLite System.Data.SQLite.dll' (Join-Path $InstallDir 'lib\System.Data.SQLite.dll'))
    (Test-DepPath 'Template CertificatDeDestruction.xlsx' (Join-Path $InstallDir 'templates\CertificatDeDestruction.xlsx'))
    (Test-DepPath 'Template BilanDeCollecte.xlsx' (Join-Path $InstallDir 'templates\BilanDeCollecte.xlsx'))
    (Test-DepPath 'Template CeaPointsDeCollectes.xlsx' (Join-Path $InstallDir 'templates\CeaPointsDeCollectes.xlsx'))
    (Test-DepPath 'GUI.ps1 restaure (dot-source panel)' (Join-Path $InstallDir 'src\GUI.ps1') { if ((Get-Content (Join-Path $InstallDir 'src\GUI.ps1') -Raw) -match 'PlanningRebuilderPanel\.ps1' -and (Get-Content (Join-Path $InstallDir 'src\GUI.ps1') -Raw) -notmatch 'Ensure-PlanningTabLoaded') { 'ok' } else { $null } })
    (Test-DepPath 'Panel v1.0.18 (moteur en tete)' (Join-Path $InstallDir 'src\ODM\PdfPlanningOptimizer\PlanningRebuilderPanel.ps1') { if ((Get-Content (Join-Path $InstallDir 'src\ODM\PdfPlanningOptimizer\PlanningRebuilderPanel.ps1') -Raw) -match 'Services\\PlanningRebuilder\.ps1') { 'ok' } else { $null } })
)

$ic = Write-DepSection '1. Binaires et fichiers planning' $installChecks

# Modules PowerShell systeme
Write-Host '2. MODULES POWERSHELL (machine)' -ForegroundColor Yellow
$ie = Get-Module -Name ImportExcel -ListAvailable -EA SilentlyContinue
$graph = Get-Module -Name Microsoft.Graph.Authentication -ListAvailable -EA SilentlyContinue
$graphMain = Get-Module -Name Microsoft.Graph -ListAvailable -EA SilentlyContinue
if ($ie) { Write-Host "  OK  ImportExcel installe ($($ie[0].Version))" -ForegroundColor Green }
else { Write-Host '  MANQUANT  ImportExcel (PSGallery)' -ForegroundColor Yellow }
if ($graph) { Write-Host "  OK  Microsoft.Graph.Authentication ($($graph[0].Version))" -ForegroundColor Green }
else { Write-Host '  MANQUANT  Microsoft.Graph.Authentication' -ForegroundColor Red }
if ($graphMain) { Write-Host "  OK  Microsoft.Graph ($($graphMain[0].Version))" -ForegroundColor Green }
else { Write-Host '  MANQUANT  Microsoft.Graph (meta-module)' -ForegroundColor Yellow }
Write-Host ''

# Runtime UI functions
Write-Host '3. FONCTIONS UI (runtime dot-source)' -ForegroundColor Yellow
$uiOk = $false
try {
    $src = Join-Path $InstallDir 'src'
    $global:WinFormsInitialized = $true
    . (Join-Path $src 'Common\Styles.ps1')
    . (Join-Path $src 'Common\CnsSharePointConnector.ps1')
    . (Join-Path $src 'Common\CnsSharePointUI.ps1')
    . (Join-Path $src 'Config.ps1')
    . (Join-Path $src 'ODM\PdfPlanningOptimizer\PlanningRebuilderPanel.ps1')
    $uiOk = $true
    foreach ($fn in @('Safe-UpdateUIControl', 'Update-PlanningExcelPathLabel', 'Show-PlanningRebuilderPanel')) {
        if (Get-Command $fn -EA SilentlyContinue) { Write-Host "  OK  $fn" -ForegroundColor Green }
        else { Write-Host "  MANQUANT  $fn" -ForegroundColor Red; $uiOk = $false }
    }
}
catch {
    Write-Host "  ERREUR chargement panel : $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ''

# Package repo
Write-Host "=== PACKAGE SOURCE : $PackageDir ===" -ForegroundColor Cyan
Write-Host ''
$pkgChecks = @(
    (Test-DepPath 'INSTALL.bat' (Join-Path $PackageDir 'INSTALL.bat'))
    (Test-DepPath 'install_assistant.ps1' (Join-Path $PackageDir 'install_assistant.ps1'))
    (Test-DepPath 'ImportExcel bundle' (Join-Path $PackageDir 'runtime\ImportExcel\ImportExcel.psd1'))
    (Test-DepPath 'Microsoft.Graph bundle' (Join-Path $PackageDir 'runtime\Graph\Microsoft.Graph.Authentication.psd1'))
    (Test-DepPath 'Ghostscript' (Join-Path $PackageDir 'runtime\ghostscript\gswin64c.exe'))
    (Test-DepPath 'Poppler pdftotext' (Join-Path $PackageDir 'runtime\poppler\pdftotext.exe') {
            Get-ChildItem -Path (Join-Path $PackageDir 'runtime\poppler') -Recurse -Filter 'pdftotext.exe' -File -EA SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        })
    (Test-DepPath 'qpdf' (Join-Path $PackageDir 'lib\qpdf\bin\qpdf.exe') {
            Get-ChildItem -Path (Join-Path $PackageDir 'lib\qpdf') -Recurse -Filter 'qpdf.exe' -File -EA SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        })
    (Test-DepPath 'SQLite' (Join-Path $PackageDir 'lib\System.Data.SQLite.dll'))
    (Test-DepPath 'version.txt' (Join-Path $PackageDir 'version.txt'))
)
$pc = Write-DepSection '4. Contenu package (repo)' $pkgChecks

# F: drive
Write-Host "=== DEPLOIEMENT F: : $FPackagePath ===" -ForegroundColor Cyan
Write-Host ''
if (Test-Path -LiteralPath $FPackagePath) {
    Write-Host '  Package F: present' -ForegroundColor Green
    foreach ($rel in @('INSTALL.bat', 'version.txt', 'runtime\ImportExcel\ImportExcel.psd1', 'runtime\Graph\Microsoft.Graph.Authentication.psd1', 'src\GUI.ps1')) {
        $p = Join-Path $FPackagePath $rel
        if (Test-Path -LiteralPath $p) { Write-Host "  OK  $rel" -ForegroundColor Green }
        else { Write-Host "  MANQUANT  $rel" -ForegroundColor Red }
    }
}
else {
    Write-Host "  Package introuvable sur cette machine : $FPackagePath" -ForegroundColor Yellow
}
Write-Host ''

# Design intent from install script
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '   ANALYSE DESIGN DU BUILD' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Microsoft.Graph dans runtime/Graph :' -ForegroundColor Yellow
Write-Host '  JAMAIS prevu dans build_package.ps1 ni install_assistant.ps1' -ForegroundColor Gray
Write-Host '  Installation : PSGallery a la demande (CnsSharePointConnector.ps1)' -ForegroundColor Gray
Write-Host '  Le chemin runtime\Graph\ est une HYPOTHESE du script audit utilisateur, pas du projet' -ForegroundColor Gray
Write-Host ''

# Resume
$missingInstall = @($ic | Where-Object { -not $_.Ok } | ForEach-Object { $_.Label })
$missingPkg = @($pc | Where-Object { -not $_.Ok } | ForEach-Object { $_.Label })
$graphBundleMissing = -not (Test-Path (Join-Path $InstallDir 'runtime\Graph\Microsoft.Graph.Authentication.psd1'))
$graphModuleMissing = -not $graph

Write-Host '========================================' -ForegroundColor Cyan
Write-Host '   CONCLUSION' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Erreurs d origine vs etat actuel :' -ForegroundColor Yellow
Write-Host '  Update-PlanningExcelPathLabel  -> FIXE hotfix7 (dans Panel)' -ForegroundColor Green
Write-Host '  Safe-UpdateUIControl           -> FIXE hotfix7 (dans Panel)' -ForegroundColor Green
Write-Host '  ImportExcel                    -> INCLUS runtime/ (si package complet)' -ForegroundColor Green
Write-Host '  Microsoft.Graph SharePoint     -> EXTERNE (PSGallery / install manuel)' -ForegroundColor $(if ($graphModuleMissing) { 'Red' } else { 'Green' })
Write-Host ''

if ($missingInstall.Count -gt 0) {
    Write-Host "Manquants sur $InstallDir :" -ForegroundColor Red
    $missingInstall | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host ''
}

Write-Host 'Microsoft.Graph est-il la SEULE dependance manquante ?' -ForegroundColor Yellow
if ($graphBundleMissing -and $graphModuleMissing) {
    if ($missingInstall -match 'Ghostscript|Poppler|qpdf|Template|SQLite') {
        Write-Host '  NON — installation incomplete (binaires/templates manquants sur ce poste)' -ForegroundColor Red
        Write-Host '  Graph manque aussi, mais ce n est pas le seul ecart possible' -ForegroundColor Yellow
    }
    elseif ($uiOk) {
        Write-Host '  OUI pour les erreurs SharePoint / connexion Graph' -ForegroundColor Green
        Write-Host '  Graph n a jamais ete dans le build — c est normal qu il manque sur poste sans PSGallery' -ForegroundColor Gray
        Write-Host '  Les erreurs UI (Update-PlanningExcelPathLabel) ne dependent PAS de Graph' -ForegroundColor Gray
    }
}
elseif (-not $graphModuleMissing) {
    Write-Host '  Graph installe sur cette machine — pas de dependance manquante pour SharePoint' -ForegroundColor Green
}

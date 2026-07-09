#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnostic complet du chargement lent de l'onglet Edition planning.
    A executer sur le POSTE CIBLE (PowerShell en administrateur non requis).
#>
param(
    [string]$InstallDir = 'C:\ASSISTANT'
)

$ErrorActionPreference = 'Continue'
$planningDir = Join-Path $InstallDir 'src\ODM\PdfPlanningOptimizer'
$logPath = Join-Path $InstallDir 'planning_load.log'

function Write-Section([string]$Title) {
    Write-Host ''
    Write-Host $Title -ForegroundColor Yellow
}

function Measure-Step([string]$Label, [scriptblock]$Action) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $err = $null
    try { & $Action } catch { $err = $_.Exception.Message }
    $sw.Stop()
    [PSCustomObject]@{
        Label   = $Label
        Ms      = $sw.ElapsedMilliseconds
        Sec     = [math]::Round($sw.ElapsedMilliseconds / 1000, 2)
        Error   = $err
    }
}

Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' DIAGNOSTIC COMPLET - CHARGEMENT PLANNING' -ForegroundColor Cyan
Write-Host " $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Gray
Write-Host " InstallDir: $InstallDir" -ForegroundColor Gray
Write-Host '========================================' -ForegroundColor Cyan

# 1. Systeme
Write-Section '1. INFORMATIONS SYSTEME'
Write-Host "  PowerShell : $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    Write-Host "  OS : $($os.Caption) $($os.OSArchitecture)"
} catch {
    Write-Host "  OS : (indisponible)"
}
Write-Host "  Machine : $env:COMPUTERNAME | User : $env:USERNAME"

# 2. Disque
Write-Section '2. DISQUE C:'
try {
    $drive = Get-PSDrive -Name C
    $freeGb = [math]::Round($drive.Free / 1GB, 2)
    Write-Host "  Espace libre : $freeGb GB" -ForegroundColor $(if ($freeGb -lt 10) { 'Red' } else { 'Gray' })
    $vol = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
    if ($vol) { Write-Host "  Type : $($vol.DriveType) | MediaType : $($vol.MediaType)" }
} catch {
    Write-Host '  (indisponible)'
}

# 3. Antivirus / Defender
Write-Section '3. ANTIVIRUS'
try {
    $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if ($defender) {
        Write-Host "  Windows Defender actif : $($defender.AntivirusEnabled)"
        Write-Host "  Real-time protection : $($defender.RealTimeProtectionEnabled)"
    }
    else {
        Write-Host '  Windows Defender : statut indisponible (autre AV possible)'
    }
} catch {
    Write-Host '  Impossible de lire le statut Defender (autre AV probable)'
}

# 4. PSModulePath (cause #1 des lenteurs entreprise)
Write-Section '4. PSMODULEPATH (cause frequente : chemins UNC lents)'
$modulePaths = @($env:PSModulePath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
Write-Host "  Entrees : $($modulePaths.Count)"
$uncPaths = @()
foreach ($p in $modulePaths) {
    $tag = ''
    if ($p -match '^\\\\') { $tag = ' [UNC - RISQUE TIMEOUT]'; $uncPaths += $p }
    elseif (-not (Test-Path -LiteralPath $p)) { $tag = ' [INEXISTANT]' }
    Write-Host "    $p$tag" -ForegroundColor $(if ($tag) { 'Red' } else { 'DarkGray' })
}
if ($uncPaths.Count -gt 0) {
    Write-Host '  >>> ALERTE : chemins UNC dans PSModulePath peuvent bloquer Get-Module -ListAvailable plusieurs minutes' -ForegroundColor Red
}

# 5. Fichiers planning
Write-Section '5. FICHIERS PLANNING'
if (Test-Path $planningDir) {
    $allFiles = Get-ChildItem -Path $planningDir -Recurse -Filter '*.ps1' -File
    $totalSize = ($allFiles | Measure-Object Length -Sum).Sum
    Write-Host "  Fichiers .ps1 : $($allFiles.Count) | Taille : $([math]::Round($totalSize / 1KB, 0)) KB"
}
else {
    Write-Host "  MANQUANT : $planningDir" -ForegroundColor Red
}

# 6. Modules installes (scan rapide vs lent)
Write-Section '6. MESURE Get-Module -ListAvailable (suspect #1)'
$timings = [System.Collections.Generic.List[object]]::new()
$timings.Add((Measure-Step 'ListAvailable ImportExcel' {
    $null = Get-Module -Name ImportExcel -ListAvailable -ErrorAction SilentlyContinue
}))
$timings.Add((Measure-Step 'ListAvailable Microsoft.Graph' {
    $null = Get-Module -Name 'Microsoft.Graph.Authentication', 'Microsoft.Graph' -ListAvailable -ErrorAction SilentlyContinue
}))
$timings.Add((Measure-Step 'ListAvailable TOUS modules' {
    $null = Get-Module -ListAvailable -ErrorAction SilentlyContinue
}))
foreach ($t in $timings) {
    $c = if ($t.Ms -gt 30000) { 'Red' } elseif ($t.Ms -gt 3000) { 'Yellow' } else { 'Green' }
    Write-Host ("  {0,-35} {1,7} ms ({2} s)" -f $t.Label, $t.Ms, $t.Sec) -ForegroundColor $c
    if ($t.Error) { Write-Host "    Erreur: $($t.Error)" -ForegroundColor Red }
}

# 7. ImportExcel runtime bundle
Write-Section '7. IMPORTEXCEL RUNTIME (bundle ASSISTANT)'
$bundled = Join-Path $InstallDir 'runtime\ImportExcel\ImportExcel.psd1'
Write-Host "  Bundle : $(Test-Path -LiteralPath $bundled) -> $bundled"
$tBundle = Measure-Step 'Import-Module runtime ImportExcel' {
    if (Test-Path -LiteralPath $bundled) {
        Import-Module -Name $bundled -Force -ErrorAction Stop | Out-Null
    }
}
Write-Host "  Import bundle : $($tBundle.Ms) ms ($($tBundle.Sec) s)" -ForegroundColor $(if ($tBundle.Ms -gt 5000) { 'Red' } else { 'Green' })

# 8. Module UI light (simulation onglet)
Write-Section '8. SIMULATION CHARGEMENT ONGLET (PlanningUILightImport)'
$global:WinFormsInitialized = $true
Remove-Module PlanningUILightImport, PlanningEngineImport -ErrorAction SilentlyContinue -Force
$lightMod = Join-Path $planningDir 'PlanningUILightImport.psm1'
if (Test-Path -LiteralPath $lightMod) {
    $tLight = Measure-Step 'Import-Module PlanningUILightImport' {
        Import-Module -Name $lightMod -Scope Global -Force -ErrorAction Stop
    }
    Write-Host "  UI light : $($tLight.Ms) ms ($($tLight.Sec) s)" -ForegroundColor $(if ($tLight.Ms -gt 10000) { 'Red' } elseif ($tLight.Ms -gt 5000) { 'Yellow' } else { 'Green' })

    if (Get-Command Show-PlanningRebuilderPanel -ErrorAction SilentlyContinue) {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        $tShow = Measure-Step 'Show-PlanningRebuilderPanel' {
            $null = Show-PlanningRebuilderPanel
        }
        Write-Host "  Show panel : $($tShow.Ms) ms ($($tShow.Sec) s)"
    }
}
else {
    Write-Host "  MANQUANT : $lightMod" -ForegroundColor Red
}

# 9. HandleCreated suspects
Write-Section '9. OPERATIONS HandleCreated (suspect #2 - UI thread)'
$tExcel = Measure-Step 'Test-PlanningExcelRuntimeReady -OfferInstall' {
    if (Get-Command Test-PlanningExcelRuntimeReady -ErrorAction SilentlyContinue) {
        $null = Test-PlanningExcelRuntimeReady -OfferInstall
    }
}
Write-Host "  Excel OfferInstall : $($tExcel.Ms) ms ($($tExcel.Sec) s)" -ForegroundColor $(if ($tExcel.Ms -gt 5000) { 'Red' } else { 'Green' })
if (Get-Command Test-CnsSharePointGraphModuleAvailable -ErrorAction SilentlyContinue) {
    $script:CnsSharePointGraphModuleChecked = $false
    $tGraph = Measure-Step 'Test-CnsSharePointGraphModuleAvailable' {
        $null = Test-CnsSharePointGraphModuleAvailable
    }
    Write-Host "  Graph module check : $($tGraph.Ms) ms ($($tGraph.Sec) s)" -ForegroundColor $(if ($tGraph.Ms -gt 5000) { 'Red' } else { 'Green' })
}

# 10. BDD
Write-Section '10. BASE DE DONNEES'
$dbPath = Join-Path $InstallDir 'Data\gestion.db'
if (Test-Path -LiteralPath $dbPath) {
    $dbSize = (Get-Item -LiteralPath $dbPath).Length
    Write-Host "  gestion.db : $([math]::Round($dbSize / 1KB, 1)) KB"
    $tDb = Measure-Step 'Get-PlanningRebuildSetting' {
        if (-not (Get-Command Get-PlanningRebuildSetting -ErrorAction SilentlyContinue)) {
            . (Join-Path $InstallDir 'src\Database\Database.ps1')
        }
        if (Get-Command Get-PlanningRebuildSetting -ErrorAction SilentlyContinue) {
            $null = Get-PlanningRebuildSetting -Key 'video_path'
        }
    }
    Write-Host "  Lecture config : $($tDb.Ms) ms"
}
else {
    Write-Host '  gestion.db introuvable' -ForegroundColor Red
}

# 11. Boites de dialogue / reseau dans le code
Write-Section '11. ANALYSE STATIQUE'
$dialogs = Select-String -Path (Join-Path $planningDir '*.ps1') -Pattern 'MessageBox|ShowDialog|OfferInstall|Install-Module' -ErrorAction SilentlyContinue
Write-Host "  Occurrences MessageBox/Install/OfferInstall : $($dialogs.Count)"
$network = Select-String -Path (Join-Path $InstallDir 'src\Common\CnsSharePointConnector.ps1') -Pattern 'Connect-MgGraph|Get-Mg|Invoke-WebRequest' -ErrorAction SilentlyContinue
Write-Host "  Appels reseau SharePoint (connector) : $($network.Count)"

# 12. Log planning
Write-Section '12. FICHIER planning_load.log'
if (Test-Path -LiteralPath $logPath) {
    Write-Host "  Dernieres lignes de $logPath :" -ForegroundColor Gray
    Get-Content -LiteralPath $logPath -Tail 20 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
}
else {
    Write-Host '  (pas encore genere - ouvrir l onglet planning une fois apres hotfix5)'
}

# Resume
Write-Section '========================================'
Write-Host ' RESUME - CAUSES PROBABLES' -ForegroundColor Cyan
$issues = [System.Collections.Generic.List[string]]::new()
$listAllSlow = $timings | Where-Object { $_.Label -like 'ListAvailable*' -and $_.Ms -gt 3000 }
if ($listAllSlow) {
    $issues.Add('CRITIQUE : Get-Module -ListAvailable lent (>3s) - PSModulePath UNC ou trop de chemins')
}
if ($uncPaths.Count -gt 0) {
    $issues.Add("CRITIQUE : $($uncPaths.Count) chemin(s) UNC dans PSModulePath")
}
if ($tExcel.Ms -gt 5000) {
    $issues.Add('CRITIQUE : Test-PlanningExcelRuntimeReady -OfferInstall bloque >5s (MessageBox ou Install-Module ?)')
}
if ($tLight -and $tLight.Ms -gt 15000) {
    $issues.Add('Lourd : Import-Module UI light >15s (antivirus ou disque lent)')
}
if ($tBundle.Ms -gt 10000) {
    $issues.Add('Lourd : ImportExcel bundle >10s (antivirus sur runtime/)')
}
if ($issues.Count -eq 0) {
    Write-Host '  Aucune lenteur extreme detectee sur CE poste.' -ForegroundColor Green
    Write-Host '  Si le probleme persiste ailleurs : comparer PSModulePath et planning_load.log' -ForegroundColor Gray
}
else {
    foreach ($i in $issues) { Write-Host "  - $i" -ForegroundColor Red }
}

Write-Host ''
Write-Host 'Actions recommandees :' -ForegroundColor Yellow
Write-Host '  1. Exclure C:\ASSISTANT de l antivirus' -ForegroundColor Gray
Write-Host '  2. Retirer chemins UNC morts de PSModulePath (variables utilisateur)' -ForegroundColor Gray
Write-Host '  3. Deployer hotfix5 (supprime ListAvailable du chargement onglet)' -ForegroundColor Gray
Write-Host "  4. Rejouer ce script apres ouverture onglet et envoyer $logPath" -ForegroundColor Gray

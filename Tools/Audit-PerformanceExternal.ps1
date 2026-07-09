#Requires -Version 5.1
# Audit performances EXTERNE — aucune modification de code metier
param([string]$InstallDir = 'C:\ASSISTANT')

$ErrorActionPreference = 'Continue'
$src = Join-Path $InstallDir 'src'

Write-Host '========================================' -ForegroundColor Cyan
Write-Host '   AUDIT PERFORMANCES - SANS MODIFICATION' -ForegroundColor Cyan
Write-Host "   $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Gray
Write-Host "   InstallDir: $InstallDir" -ForegroundColor Gray
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

# --- 1. Decomposition demarrage (simulation dot-source chain) ---
Write-Host '1. DECOMPOSITION TEMPS DE CHARGEMENT (simulation)' -ForegroundColor Yellow
$marks = [System.Collections.Generic.List[object]]::new()
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$global:WinFormsInitialized = $true
$global:WinFormsApplicationInitialized = $true

function Mark([string]$Phase) {
    $marks.Add([PSCustomObject]@{ Phase = $Phase; CumulativeMs = $sw.ElapsedMilliseconds })
}

function Dot-Measure([string]$Label, [string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Mark "$Label (missing)"
        return
    }
    $t0 = $sw.ElapsedMilliseconds
    try { . $Path } catch { }
    $delta = $sw.ElapsedMilliseconds - $t0
    Mark $Label
    return $delta
}

Mark 'start'
Dot-Measure 'QuietConsole' (Join-Path $src 'Common\QuietConsole.ps1') | Out-Null
Dot-Measure 'Bootstrap' (Join-Path $src 'Bootstrap.ps1') | Out-Null
Dot-Measure 'WinFormsGuard' (Join-Path $src 'Common\WinFormsGuard.ps1') | Out-Null
Dot-Measure 'TextEncoding+UiText' (Join-Path $src 'Common\TextEncoding.ps1') | Out-Null
. (Join-Path $src 'Common\UiText.ps1')
Mark 'TextEncoding+UiText'
Dot-Measure 'Config' (Join-Path $src 'Config.ps1') | Out-Null
Dot-Measure 'Styles' (Join-Path $src 'Common\Styles.ps1') | Out-Null
Dot-Measure 'Logger' (Join-Path $src 'Core\Logger.ps1') | Out-Null
Mark 'config_styles_logger'
Dot-Measure 'Database.ps1' (Join-Path $src 'Database\Database.ps1') | Out-Null
try { $null = Initialize-Database } catch { }
Mark 'database_init'
Dot-Measure 'ConfigManager' (Join-Path $src 'Core\ConfigManager.ps1') | Out-Null
try { $null = Initialize-CentreFromAppConfig } catch { }
Dot-Measure 'ConventionNommage' (Join-Path $src 'ODM\ConventionNommage\ConventionNommage.ps1') | Out-Null
Dot-Measure 'AgentRepository' (Join-Path $src 'ODM\Agents\AgentRepository.ps1') | Out-Null
Dot-Measure 'VehiculesRepository' (Join-Path $src 'ODM\Vehicules\VehiculesRepository.ps1') | Out-Null
Mark 'odm_repositories'
Dot-Measure 'CnsSharePointConnector' (Join-Path $src 'Common\CnsSharePointConnector.ps1') | Out-Null
Dot-Measure 'CnsSharePointUI' (Join-Path $src 'Common\CnsSharePointUI.ps1') | Out-Null
Dot-Measure 'PlanningRebuilderPanel' (Join-Path $src 'ODM\PdfPlanningOptimizer\PlanningRebuilderPanel.ps1') | Out-Null
Mark 'planning_panel_loaded'
Dot-Measure 'ConventionNommage(panel)' (Join-Path $src 'ODM\ConventionNommage\ConventionNommage.ps1') | Out-Null
Dot-Measure 'AgentPanel' (Join-Path $src 'ODM\Agents\AgentPanel.ps1') | Out-Null
Dot-Measure 'VehiculesPanel' (Join-Path $src 'ODM\Vehicules\VehiculesPanel.ps1') | Out-Null
Dot-Measure 'OutilsPanel' (Join-Path $src 'ODM\Outils\OutilsPanel.ps1') | Out-Null
Mark 'odm_panels_loaded'
Dot-Measure 'GUI.ps1' (Join-Path $src 'GUI.ps1') | Out-Null
Mark 'gui_script_loaded'

$rows = for ($i = 0; $i -lt $marks.Count; $i++) {
    $delta = if ($i -eq 0) { $marks[$i].CumulativeMs } else { $marks[$i].CumulativeMs - $marks[$i - 1].CumulativeMs }
    [PSCustomObject]@{ Phase = $marks[$i].Phase; DeltaMs = $delta; CumulativeMs = $marks[$i].CumulativeMs }
}

$totalSim = $sw.ElapsedMilliseconds
Write-Host "  Total simulation chargement scripts : $totalSim ms ($([math]::Round($totalSim/1000,2)) s)" -ForegroundColor Cyan
Write-Host '  Top goulots (delta) :' -ForegroundColor Gray
$rows | Sort-Object DeltaMs -Descending | Select-Object -First 10 | ForEach-Object {
    $color = if ($_.DeltaMs -gt 2000) { 'Yellow' } elseif ($_.DeltaMs -gt 500) { 'DarkYellow' } else { 'Gray' }
    Write-Host ("    +{0,6} ms  {1}" -f $_.DeltaMs, $_.Phase) -ForegroundColor $color
}
Write-Host ''

# --- 2. Fichiers lourds ---
Write-Host '2. FICHIERS > 100 KB' -ForegroundColor Yellow
$files = Get-ChildItem -Path $src -Recurse -Include '*.ps1', '*.psm1' -File -ErrorAction SilentlyContinue
$totalSize = ($files | Measure-Object Length -Sum).Sum
Write-Host ("  Total : {0} fichiers, {1:N2} MB" -f $files.Count, ($totalSize / 1MB)) -ForegroundColor Gray
$largeFiles = $files | Where-Object { $_.Length -gt 100KB } | Sort-Object Length -Descending
foreach ($f in $largeFiles) {
    $rel = $f.FullName.Replace("$InstallDir\", '')
    Write-Host ("    {0,8:N1} KB  {1}" -f ($f.Length / 1KB), $rel) -ForegroundColor Gray
}
Write-Host ''

# --- 3. Dot-source et Import-Module ---
Write-Host '3. DOT-SOURCE ET IMPORTS' -ForegroundColor Yellow
$dotSources = Select-String -Path (Join-Path $src '*.ps1') -Pattern '^\s*\.\s+' -ErrorAction SilentlyContinue
$dotInSub = Select-String -Path (Join-Path $src '*\*.ps1') -Pattern '^\s*\.\s+' -Recurse -ErrorAction SilentlyContinue
$allDots = @($dotSources) + @($dotInSub) | Select-Object -Unique
Write-Host ("  Dot-source (fichiers racine src) : {0}" -f @($dotSources).Count) -ForegroundColor Gray
Write-Host ("  Dot-source (recursif) : {0}" -f @($allDots).Count) -ForegroundColor Gray
$imports = Select-String -Path $src -Pattern 'Import-Module' -Recurse -ErrorAction SilentlyContinue
Write-Host ("  Import-Module (recursif) : {0}" -f @($imports).Count) -ForegroundColor Gray
$imports | Select-Object -First 12 | ForEach-Object {
    $rel = $_.Path.Replace("$InstallDir\", '')
    Write-Host ("    {0} : {1}" -f $rel, $_.Line.Trim()) -ForegroundColor DarkGray
}
Write-Host ''

# --- 4. Fichiers hotfix inutilises ---
Write-Host '4. FICHIERS HOTFIX (potentiellement inutilises)' -ForegroundColor Yellow
$hotfix = @(
    'ODM\PdfPlanningOptimizer\PlanningUILightImport.psm1',
    'ODM\PdfPlanningOptimizer\PlanningEngineImport.psm1',
    'ODM\PdfPlanningOptimizer\PlanningLoadTiming.ps1',
    'ODM\PdfPlanningOptimizer\PlanningUIHelpers.ps1'
)
foreach ($rel in $hotfix) {
    $p = Join-Path $src $rel
    if (Test-Path -LiteralPath $p) {
        $kb = [math]::Round((Get-Item -LiteralPath $p).Length / 1KB, 1)
        Write-Host "    PRESENT  $rel ($kb KB) — non charge au demarrage hotfix7" -ForegroundColor DarkYellow
    }
}
Write-Host ''

# --- 5. Antivirus ---
Write-Host '5. ANTIVIRUS (Windows Defender)' -ForegroundColor Yellow
$avExcluded = $false
try {
    $defender = Get-MpPreference -ErrorAction Stop
    $exclusions = @($defender.ExclusionPath)
    $avExcluded = ($exclusions | Where-Object { $_ -like '*ASSISTANT*' }).Count -gt 0
    if ($avExcluded) {
        Write-Host '  C:\ASSISTANT exclu : OUI' -ForegroundColor Green
    }
    else {
        Write-Host '  C:\ASSISTANT exclu : NON — facteur de ralentissement probable sur postes lents' -ForegroundColor Yellow
    }
    Write-Host ("  Nombre total exclusions : {0}" -f $exclusions.Count) -ForegroundColor Gray
}
catch {
    Write-Host "  Verification impossible : $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host ''

# --- 6. Disque ---
Write-Host '6. DISQUE' -ForegroundColor Yellow
try {
    $vol = Get-Volume -DriveLetter C -ErrorAction Stop
    $freeGb = [math]::Round($vol.SizeRemaining / 1GB, 2)
    $totalGb = [math]::Round($vol.Size / 1GB, 2)
    Write-Host "  Espace libre C: $freeGb GB / $totalGb GB" -ForegroundColor Gray
    if ($freeGb -lt 10) { Write-Host '  ESPACE FAIBLE (< 10 GB)' -ForegroundColor Yellow }
}
catch {
    $drive = Get-PSDrive -Name C
    $freeGb = [math]::Round($drive.Free / 1GB, 2)
    Write-Host "  Espace libre C: $freeGb GB" -ForegroundColor Gray
}
try {
    Get-PhysicalDisk | ForEach-Object {
        $sizeGb = [math]::Round($_.Size / 1GB, 0)
        Write-Host ("  {0} | {1} | {2} | {3} GB" -f $_.FriendlyName, $_.MediaType, $_.HealthStatus, $sizeGb) -ForegroundColor Gray
    }
}
catch {
    Write-Host '  Type disque non disponible (droits admin ?)' -ForegroundColor Yellow
}
Write-Host ''

# --- 7. Logs TIMING recents ---
Write-Host '7. LOGS TIMING RECENTS' -ForegroundColor Yellow
$logPath = Join-Path $src 'Logs\app.log'
if (Test-Path -LiteralPath $logPath) {
    Select-String -Path $logPath -Pattern '\[TIMING\]' | Select-Object -Last 15 | ForEach-Object {
        Write-Host "  $($_.Line.Trim())" -ForegroundColor DarkGray
    }
}
else {
    Write-Host '  app.log introuvable' -ForegroundColor Gray
}
Write-Host ''

# --- Resume ---
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '   RESUME' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
$planningDelta = ($rows | Where-Object Phase -eq 'planning_panel_loaded' | Select-Object -First 1).DeltaMs
$dbDelta = ($rows | Where-Object Phase -eq 'database_init' | Select-Object -First 1).DeltaMs
Write-Host ''
Write-Host 'OU SONT LES ~6 SECONDES ?' -ForegroundColor Yellow
Write-Host ("  Simulation totale scripts     : {0:N0} ms" -f $totalSim) -ForegroundColor Gray
Write-Host ("  Dont PlanningRebuilderPanel   : ~{0:N0} ms (goulot principal attendu)" -f $planningDelta) -ForegroundColor Gray
Write-Host ("  Dont base SQLite              : ~{0:N0} ms" -f $dbDelta) -ForegroundColor Gray
Write-Host '  + WinForms Application.Run / rendu fenetre : reste (~500ms-1s)' -ForegroundColor Gray
Write-Host ''
Write-Host 'OPTIMISATIONS EXTERNES (zero risque code) :' -ForegroundColor Yellow
if (-not $avExcluded) { Write-Host '  [HAUTE] Add-MpPreference -ExclusionPath C:\ASSISTANT' -ForegroundColor Green }
Write-Host '  [MOYENNE] Supprimer fichiers hotfix inutilises du disque (gain marginal)' -ForegroundColor Gray
Write-Host '  [FAIBLE]  SSD deja present — 6s est deja excellent' -ForegroundColor Gray
Write-Host '  [INFO]    ListAvailable ImportExcel dans Main.ps1 : verifie module a chaque demarrage' -ForegroundColor DarkGray

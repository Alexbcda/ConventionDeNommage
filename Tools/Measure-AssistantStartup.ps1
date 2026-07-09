#Requires -Version 5.1
param([string]$InstallDir = 'C:\ASSISTANT')

$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $InstallDir 'src'
$marks = [System.Collections.Generic.List[object]]::new()
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$global:WinFormsInitialized = $true
$global:WinFormsApplicationInitialized = $true

function Mark([string]$Phase) {
    $marks.Add([PSCustomObject]@{ Phase = $Phase; CumulativeMs = $sw.ElapsedMilliseconds })
}

Mark 'start'
. (Join-Path $scriptPath 'Common\QuietConsole.ps1'); Mark 'QuietConsole'
. (Join-Path $scriptPath 'Bootstrap.ps1'); Mark 'Bootstrap'
. (Join-Path $scriptPath 'Common\WinFormsGuard.ps1'); Mark 'WinFormsGuard'
. (Join-Path $scriptPath 'Common\TextEncoding.ps1'); Mark 'TextEncoding'
. (Join-Path $scriptPath 'Common\UiText.ps1'); Mark 'UiText'
. (Join-Path $scriptPath 'ODM\PdfPlanningOptimizer\PlanningUIHelpers.ps1'); Mark 'Main:PlanningUIHelpers'
. (Join-Path $scriptPath 'Config.ps1'); Mark 'Config'
. (Join-Path $scriptPath 'Common\Styles.ps1'); Mark 'Styles'
. (Join-Path $scriptPath 'Core\Logger.ps1'); Mark 'Logger'
. (Join-Path $scriptPath 'Database\Database.ps1'); Mark 'Database.ps1'
$null = Initialize-Database; Mark 'Initialize-Database'
. (Join-Path $scriptPath 'Core\ConfigManager.ps1'); Mark 'ConfigManager'
$null = Initialize-CentreFromAppConfig; Mark 'Initialize-Centre'
. (Join-Path $scriptPath 'ODM\ConventionNommage\ConventionNommage.ps1'); Mark 'ConventionNommage'
. (Join-Path $scriptPath 'ODM\Agents\AgentRepository.ps1'); Mark 'AgentRepository'
. (Join-Path $scriptPath 'ODM\Vehicules\VehiculesRepository.ps1'); Mark 'VehiculesRepository'
. (Join-Path $scriptPath 'Common\CnsSharePointConnector.ps1'); Mark 'CnsSharePointConnector'
. (Join-Path $scriptPath 'Common\CnsSharePointUI.ps1'); Mark 'CnsSharePointUI'
# PlanningRebuilderPanel charge au 1er clic onglet via PlanningUILightImport.psm1 (moteur differe)
. (Join-Path $scriptPath 'ODM\Agents\AgentPanel.ps1'); Mark 'AgentPanel'
. (Join-Path $scriptPath 'ODM\Vehicules\VehiculesPanel.ps1'); Mark 'VehiculesPanel'
. (Join-Path $scriptPath 'ODM\Outils\OutilsPanel.ps1'); Mark 'OutilsPanel'
Mark 'odm_panels_ready'

$lazySw = [System.Diagnostics.Stopwatch]::StartNew()
$planningModule = Join-Path $scriptPath 'ODM\PdfPlanningOptimizer\PlanningUILightImport.psm1'
Import-Module -Name $planningModule -Scope Global -Force -ErrorAction Stop
$lazyMs = $lazySw.ElapsedMilliseconds
Mark 'PlanningUILightImport-lazy'

$rows = for ($i = 0; $i -lt $marks.Count; $i++) {
    $delta = if ($i -eq 0) { $marks[$i].CumulativeMs } else { $marks[$i].CumulativeMs - $marks[$i - 1].CumulativeMs }
    [PSCustomObject]@{ Phase = $marks[$i].Phase; DeltaMs = $delta; CumulativeMs = $marks[$i].CumulativeMs }
}

Write-Host "TOTAL demarrage (sans planning) : $($marks | Where-Object Phase -eq 'odm_panels_ready' | Select-Object -ExpandProperty CumulativeMs) ms"
Write-Host "TOTAL avec planning lazy      : $($sw.ElapsedMilliseconds) ms ($([math]::Round($sw.ElapsedMilliseconds/1000,2)) s)"
Write-Host "Planning lazy seul            : $lazyMs ms"
Write-Host ''
Write-Host 'Top goulots:'
$rows | Sort-Object DeltaMs -Descending | Select-Object -First 8 | ForEach-Object {
    Write-Host ("  +{0,5} ms  {1}" -f $_.DeltaMs, $_.Phase)
}
Write-Host ''
Write-Host 'Detail cumule:'
$rows | ForEach-Object { Write-Host ("  {0,5} ms (+{1,4}) {2}" -f $_.CumulativeMs, $_.DeltaMs, $_.Phase) }

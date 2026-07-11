#Requires -Version 5.1
<#
.SYNOPSIS
    Mesure l'experience utilisateur reelle de l'onglet Edition planning.
    Simule le flux GUI.ps1 : clic onglet -> placeholder -> Import-Module -> panel -> HandleCreated.
#>
param(
    [string]$InstallDir = 'C:\ASSISTANT'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptPath = Join-Path $InstallDir 'src'
$planningModule = Join-Path $scriptPath 'ODM\PdfPlanningOptimizer\PlanningUILightImport.psm1'
$marks = [System.Collections.Generic.List[object]]::new()
$uxSw = [System.Diagnostics.Stopwatch]::StartNew()

function Add-Mark {
    param(
        [string]$Event,
        [string]$Detail = ''
    )
    $marks.Add([PSCustomObject]@{
            Event     = $Event
            Ms        = $uxSw.ElapsedMilliseconds
            Sec       = [math]::Round($uxSw.ElapsedMilliseconds / 1000, 2)
            Detail    = $Detail
            Timestamp = (Get-Date).ToString('HH:mm:ss.fff')
        })
}

function Find-PlanningPdfButton {
    param([System.Windows.Forms.Control]$Root)
    if ($null -eq $Root) { return $null }
    if ($Root.Name -eq 'btnPdf' -and $Root -is [System.Windows.Forms.Button]) { return $Root }
    foreach ($child in $Root.Controls) {
        $found = Find-PlanningPdfButton -Root $child
        if ($null -ne $found) { return $found }
    }
    return $null
}

function Test-ButtonReactive {
    param([System.Windows.Forms.Button]$Button)
    if ($null -eq $Button) { return $false }
    if ($Button.IsDisposed) { return $false }
    if (-not $Button.Enabled) { return $false }
    if (-not $Button.Visible) { return $false }
    if (-not $Button.IsHandleCreated) { return $false }
    return $true
}

# --- Bootstrap minimal (comme Main.ps1 / GUI.ps1) ---
$global:WinFormsInitialized = $true
$global:WinFormsApplicationInitialized = $true
. (Join-Path $scriptPath 'Common\QuietConsole.ps1')
. (Join-Path $scriptPath 'Common\Styles.ps1')

Add-Mark -Event 'bootstrap_done'

# --- Fenetre simulant Start-GUI ---
$form = [System.Windows.Forms.Form]::new()
$form.Text = 'ASSISTANT UX Probe'
$form.Size = [System.Drawing.Size]::new(1200, 800)
$form.StartPosition = 'CenterScreen'

$tabControl = [System.Windows.Forms.TabControl]::new()
$tabControl.Dock = 'Fill'
$form.Controls.Add($tabControl)

$tabConvention = [System.Windows.Forms.TabPage]::new()
$tabConvention.Text = 'Convention'
$tabConvention.Controls.Add(([System.Windows.Forms.Label]::new()))
$tabControl.TabPages.Add($tabConvention)

$tabPlanning = [System.Windows.Forms.TabPage]::new()
$tabPlanning.Name = 'TabPlanning'
$tabPlanning.Text = 'Edition planning'
$lblLazy = [System.Windows.Forms.Label]::new()
$lblLazy.Name = 'lblPlanningLazyLoad'
$lblLazy.Text = "Chargement de l'onglet Edition planning..."
$lblLazy.Dock = 'Fill'
$lblLazy.TextAlign = 'MiddleCenter'
$lblLazy.ForeColor = [System.Drawing.Color]::Gray
$tabPlanning.Controls.Add($lblLazy)
$tabControl.TabPages.Add($tabPlanning)

$form.Add_Shown({
    $tabControl.SelectedTab = $tabPlanning
})
$form.Show()
[System.Windows.Forms.Application]::DoEvents()
Add-Mark -Event 'tab_planning_selected_placeholder_visible' -Detail 'Utilisateur voit le message Chargement...'

# --- Reproduire Ensure-PlanningTabLoaded (bloquant sur UI thread) ---
$importSw = [System.Diagnostics.Stopwatch]::StartNew()
Import-Module -Name $planningModule -Scope Global -Force -ErrorAction Stop
$importSw.Stop()
Add-Mark -Event 'import_module_done' -Detail ("{0} ms" -f $importSw.ElapsedMilliseconds)

$showSw = [System.Diagnostics.Stopwatch]::StartNew()
$planningPanel = Show-PlanningRebuilderPanel
$showSw.Stop()
Add-Mark -Event 'show_planning_panel_returned' -Detail ("{0} ms" -f $showSw.ElapsedMilliseconds)

$tabPlanning.Controls.Clear()
$planningPanel.Dock = 'Fill'
$tabPlanning.Controls.Add($planningPanel)
[System.Windows.Forms.Application]::DoEvents()
Add-Mark -Event 'panel_added_to_tab' -Detail 'Placeholder remplace par le vrai panel'

# Panel visible (controles dessines)
$planningPanel.Refresh()
$tabPlanning.Refresh()
$form.Refresh()
[System.Windows.Forms.Application]::DoEvents()
Add-Mark -Event 'panel_painted_visible' -Detail 'Panel reel visible pour utilisateur'

# HandleCreated + ImportExcel (UI thread)
$handleSw = [System.Diagnostics.Stopwatch]::StartNew()
$deadline = [DateTime]::UtcNow.AddSeconds(30)
$btnPdf = $null
$btnReactiveMs = $null
while ([DateTime]::UtcNow -lt $deadline) {
    [System.Windows.Forms.Application]::DoEvents()
    if ($null -eq $btnPdf) {
        $btnPdf = Find-PlanningPdfButton -Root $planningPanel
    }
    if ($null -ne $btnPdf -and $null -eq $btnReactiveMs -and (Test-ButtonReactive -Button $btnPdf)) {
        $btnReactiveMs = $uxSw.ElapsedMilliseconds
        Add-Mark -Event 'btn_import_pdf_reactive' -Detail ("Enabled={0} Visible={1}" -f $btnPdf.Enabled, $btnPdf.Visible)
        break
    }
    Start-Sleep -Milliseconds 10
}
$handleSw.Stop()
if ($null -eq $btnReactiveMs) {
    Add-Mark -Event 'btn_import_pdf_not_reactive_30s' -Detail 'Timeout 30s'
}

# Boites de dialogue bloquantes
$dialogs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Id -ne $PID -and $_.MainWindowTitle -match 'ImportExcel|Microsoft\.Graph|Module manquant|ASSISTANT'
    })

$form.Close()

# --- Rapport ---
Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' AUDIT - EXPERIENCE UTILISATEUR' -ForegroundColor Cyan
Write-Host ' ONGLET EDITION PLANNING' -ForegroundColor Cyan
Write-Host " $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Gray
Write-Host " InstallDir: $InstallDir" -ForegroundColor Gray
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

Write-Host 'CHRONOLOGIE UX (depuis clic onglet simule)' -ForegroundColor Yellow
foreach ($m in $marks) {
    Write-Host ("  [{0,6} ms | {1,5} s] {2}" -f $m.Ms, $m.Sec, $m.Event) -ForegroundColor Gray
    if ($m.Detail) { Write-Host ("           {0}" -f $m.Detail) -ForegroundColor DarkGray }
}
Write-Host ''

$placeholderMs = ($marks | Where-Object Event -eq 'tab_planning_selected_placeholder_visible').Ms
$panelVisibleMs = ($marks | Where-Object Event -eq 'panel_painted_visible').Ms
$btnReactiveMark = $marks | Where-Object Event -eq 'btn_import_pdf_reactive' | Select-Object -First 1

Write-Host 'REPONSES AUX QUESTIONS UX' -ForegroundColor Yellow
Write-Host ("  1. Placeholder visible (feedback immediat) : {0} s" -f [math]::Round($placeholderMs / 1000, 2)) -ForegroundColor Green
Write-Host ("  2. Panel reel visible                      : {0} s" -f [math]::Round($panelVisibleMs / 1000, 2)) -ForegroundColor $(if ($panelVisibleMs -le 3000) { 'Green' } elseif ($panelVisibleMs -le 5000) { 'Yellow' } else { 'Red' })
if ($btnReactiveMark) {
    Write-Host ("  3. Bouton Importer PDF reactif             : {0} s" -f $btnReactiveMark.Sec) -ForegroundColor $(if ($btnReactiveMark.Ms -le 2000) { 'Green' } elseif ($btnReactiveMark.Ms -le 5000) { 'Yellow' } else { 'Red' })
}
else {
    Write-Host '  3. Bouton Importer PDF reactif             : > 30 s (echec)' -ForegroundColor Red
}
Write-Host ''

Write-Host 'CRITERES' -ForegroundColor Yellow
$panelOk = $panelVisibleMs -le 5000
$panelIdeal = $panelVisibleMs -le 3000
$btnOk = $btnReactiveMark -and $btnReactiveMark.Ms -le 5000
$btnIdeal = $btnReactiveMark -and $btnReactiveMark.Ms -le 2000
Write-Host ("  Panel < 5 s (acceptable) : {0}" -f $(if ($panelOk) { 'OK' } else { 'ECHEC' })) -ForegroundColor $(if ($panelOk) { 'Green' } else { 'Red' })
Write-Host ("  Panel < 3 s (ideal)      : {0}" -f $(if ($panelIdeal) { 'OK' } else { 'ECHEC' })) -ForegroundColor $(if ($panelIdeal) { 'Green' } else { 'Yellow' })
Write-Host ("  Bouton < 5 s (acceptable): {0}" -f $(if ($btnOk) { 'OK' } else { 'ECHEC' })) -ForegroundColor $(if ($btnOk) { 'Green' } else { 'Red' })
Write-Host ("  Bouton < 2 s (ideal)     : {0}" -f $(if ($btnIdeal) { 'OK' } else { 'ECHEC' })) -ForegroundColor $(if ($btnIdeal) { 'Green' } else { 'Yellow' })
Write-Host ''

Write-Host 'ANALYSE STATIQUE' -ForegroundColor Yellow
$panelFile = Join-Path $scriptPath 'ODM\PdfPlanningOptimizer\PlanningRebuilderPanel.ps1'
$pc = Get-Content $panelFile -Raw
$showStart = $pc.IndexOf('function Show-PlanningRebuilderPanel')
$showEnd = $pc.IndexOf('function ', $showStart + 10)
$showBody = $pc.Substring($showStart, $showEnd - $showStart)
$heavy = @()
if ($showBody -match 'Get-PlanningRebuildSetting') { $heavy += 'Lecture BDD (config video)' }
if ($showBody -match 'Resolve-PlanningRebuildVideoPath') { $heavy += 'Resolution chemin video' }
if ($showBody -match 'ImportExcel|Import-Module') { $heavy += 'ImportExcel (dans Show)' }
if ($showBody -match 'SharePoint|Connect-MgGraph') { $heavy += 'SharePoint (dans Show)' }
if ($heavy.Count -eq 0) { Write-Host '  Show-PlanningRebuilderPanel : pas d''op lourde majeure (UI pure ~500ms)' -ForegroundColor Green }
else { $heavy | ForEach-Object { Write-Host "  Show-PlanningRebuilderPanel : $_" -ForegroundColor Yellow } }

if ($pc -match 'HandleCreated[\s\S]*?Test-PlanningExcelRuntimeReady') {
    Write-Host '  HandleCreated : Test-PlanningExcelRuntimeReady (ImportExcel sur UI thread)' -ForegroundColor Red
}
if ($pc -match 'HandleCreated[\s\S]*?Start-SharePointConnectionBackground') {
    Write-Host '  HandleCreated : SharePoint en BackgroundWorker (non bloquant)' -ForegroundColor Green
}
Write-Host ''

Write-Host 'BOUTONS UI (btnPdf = Importer PDF)' -ForegroundColor Yellow
@('btnPdf', 'btnImportExcel', 'btnResetToSharePoint', 'btnStopPlanning', 'BtnLancer') | ForEach-Object {
    if ($pc -match $_) { Write-Host "  - $_" -ForegroundColor Gray }
}
Write-Host ''

if ($dialogs.Count -gt 0) {
    Write-Host 'BOITES DE DIALOGUE DETECTEES' -ForegroundColor Yellow
    $dialogs | ForEach-Object { Write-Host "  - $($_.MainWindowTitle)" -ForegroundColor Red }
}
else {
    Write-Host 'BOITES DE DIALOGUE BLOQUANTES : aucune detectee pendant le test' -ForegroundColor Green
}

Write-Host ''
Write-Host 'PERCEPTION UTILISATEUR' -ForegroundColor Yellow
Write-Host '  - Clic onglet : feedback immediat (placeholder gris)' -ForegroundColor Gray
Write-Host ("  - Attente bloquee ~{0} s : UI gelee, pas de boutons" -f [math]::Round($panelVisibleMs / 1000, 1)) -ForegroundColor Gray
Write-Host '  - Puis panel complet + boutons disponibles' -ForegroundColor Gray
Write-Host ''

# Export JSON pour CI
[PSCustomObject]@{
    PanelVisibleSec    = [math]::Round($panelVisibleMs / 1000, 2)
    BtnReactiveSec     = if ($btnReactiveMark) { $btnReactiveMark.Sec } else { $null }
    ImportModuleMs     = $importSw.ElapsedMilliseconds
    ShowPanelMs        = $showSw.ElapsedMilliseconds
    Marks              = $marks
} | ConvertTo-Json -Depth 4

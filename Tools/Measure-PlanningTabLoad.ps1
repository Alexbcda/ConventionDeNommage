#Requires -Version 5.1
param(
    [string]$InstallDir = 'C:\ASSISTANT',
    [switch]$IncludeShowPanel
)

$ErrorActionPreference = 'Stop'
$global:WinFormsInitialized = $true
$global:WinFormsApplicationInitialized = $true
$scriptPath = Join-Path $InstallDir 'src'
$planningRoot = Join-Path $scriptPath 'ODM\PdfPlanningOptimizer'

function Measure-DotSource {
    param([string]$Label, [string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return [PSCustomObject]@{ Label = $Label; Path = $Path; Ms = -1; Error = 'missing' }
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        . $Path
        $sw.Stop()
        return [PSCustomObject]@{ Label = $Label; Path = $Path; Ms = $sw.ElapsedMilliseconds; Error = $null }
    }
    catch {
        $sw.Stop()
        return [PSCustomObject]@{ Label = $Label; Path = $Path; Ms = $sw.ElapsedMilliseconds; Error = $_.Exception.Message }
    }
}

Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' AUDIT - TEMPS DE CHARGEMENT PLANNING' -ForegroundColor Cyan
Write-Host " $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Gray
Write-Host " InstallDir: $InstallDir" -ForegroundColor Gray
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

# Prerequis GUI (comme Main.ps1 avant lazy load)
$preSw = [System.Diagnostics.Stopwatch]::StartNew()
. (Join-Path $scriptPath 'Common\QuietConsole.ps1')
. (Join-Path $scriptPath 'Common\Styles.ps1')
$preMs = $preSw.ElapsedMilliseconds
Write-Host "Prerequis Styles/QuietConsole : $preMs ms" -ForegroundColor Gray
Write-Host ''

# 1. Import module (chemin reel lazy load)
Write-Host '1. IMPORT-MODULE PlanningUILightImport' -ForegroundColor Yellow
Remove-Module PlanningUILightImport -ErrorAction SilentlyContinue -Force
Remove-Module PlanningRebuilderImport -ErrorAction SilentlyContinue -Force
$modPath = Join-Path $planningRoot 'PlanningUILightImport.psm1'
$modSw = [System.Diagnostics.Stopwatch]::StartNew()
Import-Module -Name $modPath -Scope Global -Force
$modMs = $modSw.ElapsedMilliseconds
Write-Host "  Total Import-Module : $modMs ms ($([math]::Round($modMs/1000,2)) s)" -ForegroundColor Cyan
Write-Host ''

# 2. Decomposition des imports directs du panel
Write-Host '2. DECOMPOSITION DOT-SOURCE (ordre panel)' -ForegroundColor Yellow
$chain = @(
    @{ Label = 'PlanningUIHelpers.ps1'; Path = Join-Path $planningRoot 'PlanningUIHelpers.ps1' },
    @{ Label = 'PlanningRebuilder.ps1'; Path = Join-Path $planningRoot 'Services\PlanningRebuilder.ps1' },
    @{ Label = 'Styles.ps1'; Path = Join-Path $scriptPath 'Common\Styles.ps1' },
    @{ Label = 'CnsSharePointConnector.ps1'; Path = Join-Path $scriptPath 'Common\CnsSharePointConnector.ps1' },
    @{ Label = 'CnsSharePointUI.ps1'; Path = Join-Path $scriptPath 'Common\CnsSharePointUI.ps1' },
    @{ Label = 'Database.ps1'; Path = Join-Path $scriptPath 'Database\Database.ps1' }
)

# Fresh session per file is impossible in same runspace after module load;
# report file sizes and grep patterns instead for chain analysis
foreach ($item in $chain) {
    $sizeKb = if (Test-Path $item.Path) { [math]::Round((Get-Item $item.Path).Length / 1KB, 1) } else { 0 }
    Write-Host ("  {0,-35} {1,7} KB" -f $item.Label, $sizeKb) -ForegroundColor Gray
}
Write-Host ''

# 3. Cascade PlanningRebuilder.ps1
Write-Host '3. CASCADE PlanningRebuilder.ps1' -ForegroundColor Yellow
$rebuilderChain = @(
    'Extractors\PdfExtractor.ps1',
    'Extractors\EntityExtractor.ps1',
    'Extractors\ExcelLoader.ps1',
    'Services\PageEntityAggregator.ps1',
    'Monitoring\QualityMonitor.ps1',
    'Monitoring\RootCauseEngine.ps1',
    'Common\ScalarGuard.ps1',
    'Common\SortSafe.ps1',
    'Core\PDFReorganizer.ps1',
    'Services\PdfTourneeCoverComposer.ps1',
    'Services\PlanningStep5Prerequisites.ps1',
    'Core\Logger.ps1',
    'Database\Database.ps1'
)
$totalKb = 0
foreach ($rel in $rebuilderChain) {
    $p = if ($rel -like 'Common\*' -or $rel -like 'Core\*' -or $rel -like 'Database\*') {
        Join-Path $scriptPath ($rel -replace '\\','/')
    } else {
        Join-Path $planningRoot $rel
    }
    if (Test-Path -LiteralPath $p) {
        $kb = [math]::Round((Get-Item -LiteralPath $p).Length / 1KB, 1)
        $totalKb += $kb
        Write-Host ("  {0,-45} {1,7} KB" -f (Split-Path $p -Leaf), $kb) -ForegroundColor Gray
    }
}
Write-Host "  Total cascade (fichiers listes) : $totalKb KB" -ForegroundColor Yellow
Write-Host ''

# 4. Patterns risque au chargement
Write-Host '4. APPELS RESEAU / SHAREPOINT / EXCEL / GS (grep)' -ForegroundColor Yellow
$patterns = @{
    SharePoint = 'SharePoint|Connect-MgGraph|Invoke-MgGraph|Get-MgSite|Connect-SharePoint'
    Excel      = 'Import-Excel|Export-Excel|ImportExcel\.psd1'
    Network    = 'Invoke-WebRequest|Invoke-RestMethod|DownloadFile'
    Database   = 'Initialize-Database|SQLiteConnection'
    Ghostscript = 'gswin64c|Get-ResolvedGhostscriptPath'
}
foreach ($key in $patterns.Keys) {
    $hits = Select-String -Path (Join-Path $planningRoot '*.ps1') -Pattern $patterns[$key] -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Filename -Unique
    $svcHits = Select-String -Path (Join-Path $planningRoot 'Services\*.ps1') -Pattern $patterns[$key] -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Filename -Unique
    $all = @($hits + $svcHits) | Select-Object -Unique
    Write-Host "  $key : $($all.Count) fichier(s)" -ForegroundColor $(if ($all.Count -gt 0) { 'Yellow' } else { 'Green' })
    $all | ForEach-Object { Write-Host "    - $_" -ForegroundColor DarkGray }
}
Write-Host ''

# 5. Show-PlanningRebuilderPanel (UI seule)
if ($IncludeShowPanel) {
    Write-Host '5. Show-PlanningRebuilderPanel (construction UI)' -ForegroundColor Yellow
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $uiSw = [System.Diagnostics.Stopwatch]::StartNew()
    $panel = Show-PlanningRebuilderPanel
    $uiMs = $uiSw.ElapsedMilliseconds
    Write-Host "  Construction UI : $uiMs ms" -ForegroundColor Cyan
    Write-Host "  HandleCreated declenche SharePoint au 1er paint (pas mesure ici sans message pump)" -ForegroundColor Gray
    Write-Host ''
}

# 6. Isolated fresh-run timing (nouveau powershell par fichier lourd)
Write-Host '6. TIMING ISOLÉ (nouveau processus par fichier lourd)' -ForegroundColor Yellow
$heavyFiles = @(
    @{ Label = 'PlanningRebuilderPanel via module'; Script = @"
`$ErrorActionPreference='Stop'
`$global:WinFormsInitialized=`$true
Import-Module '$modPath' -Scope Global -Force
"@ },
    @{ Label = 'PlanningRebuilder.ps1 seul'; Script = @"
`$ErrorActionPreference='Stop'
`$global:WinFormsInitialized=`$true
. '$($chain[0].Path)'
. '$($chain[1].Path)'
"@ },
    @{ Label = 'PdfTourneeCoverComposer.ps1'; Script = @"
`$ErrorActionPreference='Stop'
. '$(Join-Path $planningRoot 'Services\PdfTourneeCoverComposer.ps1')'
"@ }
)

foreach ($h in $heavyFiles) {
    $tSw = [System.Diagnostics.Stopwatch]::StartNew()
    $null = powershell -NoProfile -NonInteractive -Command $h.Script 2>&1
    $tSw.Stop()
    Write-Host ("  {0,-40} {1,6} ms" -f $h.Label, $tSw.ElapsedMilliseconds) -ForegroundColor $(if ($tSw.ElapsedMilliseconds -gt 5000) { 'Red' } elseif ($tSw.ElapsedMilliseconds -gt 1000) { 'Yellow' } else { 'Green' })
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host " RESUME: Import-Module = $modMs ms ($([math]::Round($modMs/1000,2)) s)" -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

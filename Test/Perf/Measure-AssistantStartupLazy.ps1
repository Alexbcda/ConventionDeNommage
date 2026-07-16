# Measure-AssistantStartupLazy.ps1
# Mesure froide du lancement ASSISTANT (lazy loading) jusqu'a fenetre visible + onglets lazy.
param(
    [string]$PdfPath = '',
    [string]$SrcRoot = ''
)

$ErrorActionPreference = 'Stop'
$env:ASSISTANT_DIAG = '1'

if ([string]::IsNullOrWhiteSpace($SrcRoot)) {
    $SrcRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\src')).Path
}
if ([string]::IsNullOrWhiteSpace($PdfPath)) {
    $candidate = Join-Path $SrcRoot '..\Test\Fixtures\PdfPlanningOptimizer\1507.pdf'
    if (Test-Path -LiteralPath $candidate) {
        $PdfPath = (Resolve-Path -LiteralPath $candidate).Path
    }
}

$results = [ordered]@{
    SrcRoot = $SrcRoot
    PdfPath = $PdfPath
    ProcessStartUtc = (Get-Date).ToUniversalTime().ToString('o')
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$script:PerfMarks = [ordered]@{}
$script:LazyTabMs = [ordered]@{}
$script:PerfErrors = New-Object System.Collections.Generic.List[string]
$script:ProbeStarted = $false
$script:ConventionReady = $false
$script:ConventionInteractive = $false

function script:Record-PerfMark {
    param([Parameter(Mandatory = $true)][string]$Name)
    if ($script:PerfMarks.Contains($Name)) { return }
    $script:PerfMarks[$Name] = $sw.ElapsedMilliseconds
    Write-Host ("[PERF] {0}={1}ms" -f $Name, $sw.ElapsedMilliseconds) -ForegroundColor Cyan
}

function script:Get-AssistantOpenForm {
    foreach ($f in [System.Windows.Forms.Application]::OpenForms) {
        if ($f.Text -like 'ASSISTANT*') { return $f }
    }
    return $null
}

Record-PerfMark 'process_start'

. (Join-Path $SrcRoot 'Common\QuietConsole.ps1')
. (Join-Path $SrcRoot 'Bootstrap.ps1')
. (Join-Path $SrcRoot 'Common\WinFormsGuard.ps1')
. (Join-Path $SrcRoot 'Common\TextEncoding.ps1')
. (Join-Path $SrcRoot 'Common\UiText.ps1')
Initialize-ConventionAppConsoleUtf8
Record-PerfMark 'after_bootstrap'

$script:AssistantStartupSw = [System.Diagnostics.Stopwatch]::StartNew()
$script:AssistantStartupLastMs = 0L
function Write-AssistantStartupTiming {
    param([string]$Phase, [long]$ElapsedMs, [long]$DeltaMs = -1, [string]$Detail = $null)
    $deltaText = if ($DeltaMs -ge 0) { " (+${DeltaMs}ms)" } else { '' }
    Write-Host ("[TIMING] {0}={1}ms{2}" -f $Phase, $ElapsedMs, $deltaText) -ForegroundColor DarkCyan
    $script:PerfMarks["timing_$Phase"] = $sw.ElapsedMilliseconds
}
function Write-AssistantStartupMark {
    param([string]$Phase, [string]$Detail = $null)
    $elapsed = $script:AssistantStartupSw.ElapsedMilliseconds
    $delta = $elapsed - $script:AssistantStartupLastMs
    $script:AssistantStartupLastMs = $elapsed
    Write-AssistantStartupTiming -Phase $Phase -ElapsedMs $elapsed -DeltaMs $delta -Detail $Detail
}

. (Join-Path $SrcRoot 'Config.ps1')
. (Join-Path $SrcRoot 'Common\Styles.ps1')
. (Join-Path $SrcRoot 'Core\Logger.ps1')
Write-AssistantStartupMark -Phase 'config_styles_logger'
Record-PerfMark 'after_config'

. (Join-Path $SrcRoot 'Database\Database.ps1')
$null = Initialize-Database
$configManagerScript = Join-Path $SrcRoot 'Core\ConfigManager.ps1'
if (Test-Path -LiteralPath $configManagerScript) {
    . $configManagerScript
    $script:ActiveCentre = Initialize-CentreFromAppConfig
}
Write-AssistantStartupMark -Phase 'database_init'
Record-PerfMark 'after_database'

. (Join-Path $SrcRoot 'ODM\ConventionNommage\ConventionNommage.ps1')
. (Join-Path $SrcRoot 'ODM\Agents\AgentRepository.ps1')
. (Join-Path $SrcRoot 'ODM\Vehicules\VehiculesRepository.ps1')
Write-AssistantStartupMark -Phase 'odm_repositories'
Record-PerfMark 'after_odm_repos'

. (Join-Path $SrcRoot 'GUI.ps1')
Write-AssistantStartupMark -Phase 'gui_script_loaded'
Record-PerfMark 'after_gui_script'

$url = Get-SharePointPlanningUrl
if ([string]::IsNullOrWhiteSpace($url)) {
    throw 'Aucune URL SharePoint configuree — le test ne peut pas passer Show-FirstLaunchConfig.'
}

function script:Invoke-AssistantPerfProbe {
    if ($script:ProbeStarted) { return }
    $form = script:Get-AssistantOpenForm
    if ($null -eq $form) { return }
    if (-not $form.Visible) { return }

    $script:ProbeStarted = $true
    script:Record-PerfMark 'form_visible'
    script:Record-PerfMark 'gui_form_visible'

    try {
        $tabs = $form.Controls['MainTabControl']
        if ($null -eq $tabs) {
            [void]$script:PerfErrors.Add('MainTabControl introuvable')
            $form.Close()
            return
        }

        $tabConv = $tabs.TabPages['TabConventionNommage']
        if ($null -ne $tabConv -and $tabConv.Controls.Count -gt 0) {
            $script:ConventionReady = $true
            $root = $tabConv.Controls['ConventionNommageRootPanel']
            if ($null -eq $root -and $tabConv.Controls.Count -gt 0) {
                $root = $tabConv.Controls[0]
            }
            $hasInput = $false
            if ($null -ne $root) {
                foreach ($c in $root.Controls) {
                    if ($c -is [System.Windows.Forms.TextBox] -or $c -is [System.Windows.Forms.Button]) {
                        $hasInput = $true
                        break
                    }
                }
            }
            $script:ConventionInteractive = $hasInput
            script:Record-PerfMark 'convention_interactive'
        }
        else {
            [void]$script:PerfErrors.Add('Onglet Convention vide ou absent')
        }

        $lazyNames = @('TabAgents', 'TabVehicules', 'TabPlanning', 'TabOutils')
        foreach ($name in $lazyNames) {
            $page = $tabs.TabPages[$name]
            if ($null -eq $page) {
                [void]$script:PerfErrors.Add("Onglet manquant: $name")
                continue
            }
            $before = $sw.ElapsedMilliseconds
            $tabs.SelectedTab = $page
            [System.Windows.Forms.Application]::DoEvents()
            $deadline = [datetime]::UtcNow.AddSeconds(90)
            while ($page.Tag -ne $true -and [datetime]::UtcNow -lt $deadline) {
                [System.Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds 25
            }
            $elapsed = $sw.ElapsedMilliseconds - $before
            $script:LazyTabMs[$name] = $elapsed
            Write-Host ("[PERF] lazy_{0}={1}ms tag={2} controls={3}" -f $name, $elapsed, $page.Tag, $page.Controls.Count) -ForegroundColor Yellow
            if ($page.Tag -ne $true) {
                [void]$script:PerfErrors.Add("Lazy load timeout: $name")
            }
        }

        foreach ($name in $lazyNames) {
            $page = $tabs.TabPages[$name]
            $before = $sw.ElapsedMilliseconds
            $tabs.SelectedTab = $page
            [System.Windows.Forms.Application]::DoEvents()
            $script:LazyTabMs["${name}_second"] = ($sw.ElapsedMilliseconds - $before)
        }

        script:Record-PerfMark 'all_lazy_done'
        $form.Close()
    }
    catch {
        [void]$script:PerfErrors.Add($_.Exception.Message)
        try { $form.Close() } catch { }
    }
}

# Poll jusqu'a form Visible, puis probe (lazy tabs) puis Close.
$watchTimer = [System.Windows.Forms.Timer]::new()
$watchTimer.Interval = 50
$watchTimer.Add_Tick({
    param($s, $e)
    try {
        if ($script:ProbeStarted) {
            $s.Stop()
            return
        }
        script:Invoke-AssistantPerfProbe
        if ($script:ProbeStarted) {
            $s.Stop()
            $s.Dispose()
        }
    }
    catch {
        [void]$script:PerfErrors.Add("watchTimer: $($_.Exception.Message)")
        try { $s.Stop(); $s.Dispose() } catch { }
        try { [System.Windows.Forms.Application]::Exit() } catch { }
    }
})

Record-PerfMark 'before_start_gui'
$watchTimer.Start()
try {
    Start-GUI -FichierPDF $PdfPath
}
catch {
    [void]$script:PerfErrors.Add("Start-GUI: $($_.Exception.Message)")
}
Record-PerfMark 'after_application_run'

$results.MarksMs = $script:PerfMarks
$results.LazyTabMs = $script:LazyTabMs
$results.ConventionReady = $script:ConventionReady
$results.ConventionInteractive = $script:ConventionInteractive
$results.Errors = @($script:PerfErrors)
$results.TotalMs = $sw.ElapsedMilliseconds
$formMs = if ($script:PerfMarks.Contains('form_visible')) { [long]$script:PerfMarks['form_visible'] } else { -1 }
$results.FormVisibleMs = $formMs
$results.PassWindowUnder2s = ($formMs -ge 0 -and $formMs -lt 2000)
$results.PassWindowUnder3s = ($formMs -ge 0 -and $formMs -lt 3000)

$outDir = Join-Path $PSScriptRoot 'Results'
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
$outFile = Join-Path $outDir ("startup-lazy-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
($results | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $outFile -Encoding UTF8

Write-Host ''
Write-Host '========== RESUME PERF LANCEMENT ==========' -ForegroundColor Green
Write-Host ("PDF              : {0}" -f $PdfPath)
Write-Host ("form_visible     : {0} ms  (objectif < 2000)" -f $(if ($formMs -ge 0) { $formMs } else { 'N/A' }))
Write-Host ("convention ready : {0} / interactive : {1}" -f $script:ConventionReady, $script:ConventionInteractive)
foreach ($k in @('TabAgents', 'TabVehicules', 'TabPlanning', 'TabOutils')) {
    if ($script:LazyTabMs.Contains($k)) {
        $second = if ($script:LazyTabMs.Contains("${k}_second")) { $script:LazyTabMs["${k}_second"] } else { '?' }
        Write-Host ("lazy {0,-14}: 1er={1} ms | 2e={2} ms" -f $k, $script:LazyTabMs[$k], $second)
    }
}
Write-Host ("PASS <2s         : {0}" -f $results.PassWindowUnder2s)
Write-Host ("PASS <3s         : {0}" -f $results.PassWindowUnder3s)
Write-Host ("Rapport JSON     : {0}" -f $outFile)
if ($script:PerfErrors.Count -gt 0) {
    Write-Host 'ERRORS:' -ForegroundColor Red
    $script:PerfErrors | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}
exit 0

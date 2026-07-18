# ========== MAIN.PS1 - POINT D'ENTRÉE PRINCIPAL NETTOYÉ ==========
# Encodage : UTF-8 (PowerShell 5.1 + fichiers source en UTF-8 avec BOM recommande).

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

$OutputEncoding = [System.Text.Encoding]::UTF8

# Proteger les appels Console (echouent dans exe PS2EXE sans console)
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
}
catch {
    Write-Verbose "Console non disponible: $($_.Exception.Message)"
}

$entryPath = $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($entryPath)) {
    try {
        $entryPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    }
    catch {
        $entryPath = $PSCommandPath
    }
}

$script:IsCompiledExe = ($entryPath -like '*.exe')

if ($script:IsCompiledExe -and $env:CN_VERBOSE -notin @('1', 'true', 'TRUE', 'yes', 'YES')) {
    $global:SuppressConsoleOutput = $true
}

if ($script:IsCompiledExe) {
    $appRoot = Split-Path -Parent $entryPath
    $candidateSrc = Join-Path $appRoot 'src'
    if (Test-Path -LiteralPath $candidateSrc) {
        $scriptPath = $candidateSrc
    }
    else {
        $scriptPath = $appRoot
    }
}
else {
    $scriptPath = Split-Path -Parent $entryPath
    if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        if ($args.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$args[0])) {
            $env:ASSISTANT_PDF = [string]$args[0]
        }
        & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -STA -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File $PSCommandPath @args
        exit $LASTEXITCODE
    }
}

function Resolve-AssistantInputPdfPath {
    param([object]$RawArgument)
    if ($null -eq $RawArgument) { return $null }
    $candidate = [string]$RawArgument
    if ([string]::IsNullOrWhiteSpace($candidate)) { return $null }
    $candidate = $candidate.Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($candidate)) { return $null }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $null }
    try {
        return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
    }
    catch {
        return $candidate
    }
}

function Write-AssistantStartupTiming {
    param(
        [Parameter(Mandatory = $true)][string]$Phase,
        [Parameter(Mandatory = $true)][long]$ElapsedMs,
        [long]$DeltaMs = -1,
        [string]$Detail = $null
    )
    $deltaText = if ($DeltaMs -ge 0) { " (+${DeltaMs}ms)" } else { '' }
    $detailText = if ([string]::IsNullOrWhiteSpace($Detail)) { '' } else { " — $Detail" }
    $line = "[TIMING] {0}={1}ms{2}{3}" -f $Phase, $ElapsedMs, $deltaText, $detailText
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log $line 'INFO'
    }
    if ($env:ASSISTANT_DIAG -eq '1') {
        Write-AppHost $line -ForegroundColor DarkCyan
    }
}

. (Join-Path $scriptPath 'Common\QuietConsole.ps1')

# WinForms : bootstrap Application en premier (aucun proxy New-Object — audit statique : Tools\Find-WinFormsLeaks.ps1).
. (Join-Path $scriptPath 'Bootstrap.ps1')
. (Join-Path $scriptPath 'Common\WinFormsGuard.ps1')

if ($env:CN_WINFORMS_TRACE -eq '1' -or $env:CN_WINFORMS_TRACE -eq 'true') {
    Write-AppHost "[WINFORMS TRACE] Loaded: Main.ps1 (Bootstrap + diagnostics WinFormsGuard)" -ForegroundColor Magenta
}
. (Join-Path $scriptPath 'Common\TextEncoding.ps1')
. (Join-Path $scriptPath 'Common\UiText.ps1')
Initialize-ConventionAppConsoleUtf8

Write-AppHost 'Demarrage ASSISTANT...' -ForegroundColor Cyan

$script:AssistantStartupSw = [System.Diagnostics.Stopwatch]::StartNew()
$script:AssistantStartupLastMs = 0L

function Write-AssistantStartupMark {
    param(
        [Parameter(Mandatory = $true)][string]$Phase,
        [string]$Detail = $null
    )
    $elapsed = $script:AssistantStartupSw.ElapsedMilliseconds
    $delta = $elapsed - $script:AssistantStartupLastMs
    $script:AssistantStartupLastMs = $elapsed
    Write-AssistantStartupTiming -Phase $Phase -ElapsedMs $elapsed -DeltaMs $delta -Detail $Detail
}

function Write-AssistantRenameOnlyLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    $line = "[RenameOnly] $Message"
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log $line 'INFO'
    }
    if (Get-Command Write-AppHost -ErrorAction SilentlyContinue) {
        Write-AppHost $line -ForegroundColor Cyan
    }
}

# ============================================
# 1. CHARGEMENT DES STYLES ET CONFIGURATION
# ============================================
. "$scriptPath\Config.ps1"
# Styles apres UiText (Convert-ToUiText sur libelles boutons).
. "$scriptPath\Common\Styles.ps1"
. "$scriptPath\Core\Logger.ps1"
Write-Log "[MAIN] Application start" "INFO" @{ scriptPath = $scriptPath; compiledExe = $script:IsCompiledExe }
Write-AssistantStartupMark -Phase 'config_styles_logger'

# Detecter le PDF tot pour activer le mode RenameOnly (clic droit) avant BDD / repos / SharePoint.
$script:AssistantInputPdf = $null
$rawPdfArg = if ($args.Count -gt 0) { $args[0] } elseif (-not [string]::IsNullOrWhiteSpace($env:ASSISTANT_PDF)) { $env:ASSISTANT_PDF } else { $null }
if (-not [string]::IsNullOrWhiteSpace($env:ASSISTANT_PDF)) {
    Remove-Item Env:ASSISTANT_PDF -ErrorAction SilentlyContinue
}
$script:AssistantInputPdf = Resolve-AssistantInputPdfPath -RawArgument $rawPdfArg
$script:AssistantRenameOnly = -not [string]::IsNullOrWhiteSpace($script:AssistantInputPdf)

if ($script:AssistantRenameOnly) {
    Write-AssistantRenameOnlyLog ("Mode renommage uniquement — pdf={0}" -f $script:AssistantInputPdf)
    Write-Log '[MAIN] Fichier PDF charge depuis le lanceur' 'INFO' @{ path = $script:AssistantInputPdf; renameOnly = $true }
}
else {
    Write-Log '[MAIN] Aucun fichier PDF valide recu au lancement' 'INFO' @{ rawArgument = [string]$rawPdfArg }
    # Planning PDF + Excel : conseil utile uniquement hors RenameOnly
    if (-not (Get-Module -Name ImportExcel -ListAvailable -ErrorAction SilentlyContinue)) {
        Write-AppHost "[MAIN] Conseil: installez le module ImportExcel pour l'onglet *Edition planning* (fichiers Excel sans Microsoft Excel)." -ForegroundColor Yellow
        Write-AppHost '      Install-Module -Name ImportExcel -Scope CurrentUser -Force' -ForegroundColor DarkGray
    }
}
Write-AssistantStartupMark -Phase 'pdf_detect'

# ============================================
# 2. INITIALISATION DE LA BASE SQLITE (mode normal uniquement)
# ============================================
if (-not $script:AssistantRenameOnly) {
    . "$scriptPath\Database\Database.ps1"
    try {
        $ok = Initialize-Database
        Write-Log "[MAIN] Initialize-Database result" "INFO" @{ ok = $ok }
    }
    catch {
        Write-Log "[MAIN] Initialize-Database failed" "ERROR" @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
        throw
    }

    $configManagerScript = Join-Path $scriptPath 'Core\ConfigManager.ps1'
    if (Test-Path -LiteralPath $configManagerScript) {
        . $configManagerScript
        $script:ActiveCentre = Initialize-CentreFromAppConfig
        if ($script:ActiveCentre) {
            if ([string]$script:ActiveCentre.id -eq 'custom') {
                Write-AppHost '[Centre] Centre non reconnu — verifiez config\centres.json ou reinstallez avec -Centre <nom>' -ForegroundColor Yellow
                Write-AppHost '[Centre] Onglet Outils : bouton « Configurer le centre » pour corriger sans reinstallation' -ForegroundColor Yellow
                if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                    Write-Log '[MAIN] Centre non reconnu au demarrage' 'WARN' @{
                        sharePointUrl = $script:ActiveCentre.sharePointApiUrl
                    }
                }
            }
            else {
                Write-AppHost ("[MAIN] Centre actif : {0}" -f $script:ActiveCentre.name) -ForegroundColor Green
            }
        }
        elseif (-not (Test-CentreAppConfigurationComplete)) {
            Write-AppHost '[Centre] Configuration centre incomplete en BDD (CentreId/CentreName/SharePointApiUrl)' -ForegroundColor Yellow
        }
    }
    Write-AssistantStartupMark -Phase 'database_init'
}
else {
    Write-AssistantRenameOnlyLog 'Skip Initialize-Database / ConfigManager'
    Write-AssistantStartupMark -Phase 'database_init_skipped'
}

# ============================================
# 3. CHARGEMENT DES MODULES METIER
# ============================================
. "$scriptPath\ODM\ConventionNommage\ConventionNommage.ps1"
if (-not $script:AssistantRenameOnly) {
    . "$scriptPath\ODM\Agents\AgentRepository.ps1"
    . "$scriptPath\ODM\Vehicules\VehiculesRepository.ps1"
    Write-AssistantStartupMark -Phase 'odm_repositories'
}
else {
    Write-AssistantRenameOnlyLog 'Skip AgentRepository / VehiculesRepository'
    Write-AssistantStartupMark -Phase 'odm_repositories_skipped'
}

# ============================================
# 4. CHARGEMENT ET LANCEMENT DE LA GUI
# ============================================
. "$scriptPath\GUI.ps1"
Write-AssistantStartupMark -Phase 'gui_script_loaded'

# Extractors planning au scope SCRIPT (hors RenameOnly) — classes Models deja via GUI.ps1.
if (-not $script:AssistantRenameOnly) {
    . Import-AssistantPlanningExtractorScripts
    Write-AssistantStartupMark -Phase 'planning_extractors_loaded'
}

# ============================================
# 5. LANCEMENT
# ============================================
try {
    if ($script:AssistantRenameOnly) {
        Start-GUI -FichierPDF $script:AssistantInputPdf -RenameOnly
    }
    else {
        Start-GUI -FichierPDF $script:AssistantInputPdf
    }
}
catch {
    if (Get-Command Test-AppConsoleVisible -ErrorAction SilentlyContinue) {
        if (Test-AppConsoleVisible) {
            if (Get-Command Write-WinFormsInitStateDiagnostic -ErrorAction SilentlyContinue) {
                Write-WinFormsInitStateDiagnostic
            }
        }
    }
    elseif (Get-Command Write-WinFormsInitStateDiagnostic -ErrorAction SilentlyContinue) {
        Write-WinFormsInitStateDiagnostic
    }
    throw
}

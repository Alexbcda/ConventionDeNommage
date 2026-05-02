# ========== MAIN.PS1 - POINT D'ENTRÉE PRINCIPAL NETTOYÉ ==========
# Encodage : UTF-8 (PowerShell 5.1 + fichiers source en UTF-8 avec BOM recommande).

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# WinForms : bootstrap Application en premier (aucun proxy New-Object — audit statique : Tools\Find-WinFormsLeaks.ps1).
. (Join-Path $scriptPath 'Bootstrap.ps1')
. (Join-Path $scriptPath 'Common\WinFormsGuard.ps1')

if ($env:CN_WINFORMS_TRACE -eq '1' -or $env:CN_WINFORMS_TRACE -eq 'true') {
    Write-Host "[WINFORMS TRACE] Loaded: Main.ps1 (Bootstrap + diagnostics WinFormsGuard)" -ForegroundColor Magenta
}
. (Join-Path $scriptPath 'Common\TextEncoding.ps1')
. (Join-Path $scriptPath 'Common\UiText.ps1')
Initialize-ConventionAppConsoleUtf8

# Planning PDF + Excel (PdfPlanningOptimizer) : lecture .xlsx/.xlsm sans Excel installe
if (-not (Get-Module -Name ImportExcel -ListAvailable -ErrorAction SilentlyContinue)) {
    Write-Host "[MAIN] Conseil: installez le module ImportExcel pour l'onglet *Edition planning* (fichiers Excel sans Microsoft Excel)." -ForegroundColor Yellow
    Write-Host "      Install-Module -Name ImportExcel -Scope CurrentUser -Force" -ForegroundColor DarkGray
}

Write-Host "🚀 DÉMARRAGE DE L'APPLICATION..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ============================================
# 1. CHARGEMENT DES STYLES ET CONFIGURATION
# ============================================
Write-Host "[MAIN] Chargement des styles..." -ForegroundColor Gray
. "$scriptPath\Config.ps1"
# Styles apres UiText (Convert-ToUiText sur libelles boutons).
. "$scriptPath\Common\Styles.ps1"
. "$scriptPath\Core\Logger.ps1"
Write-Log "[MAIN] Application start" "INFO" @{ scriptPath = $scriptPath }

# ============================================
# 2. INITIALISATION DE LA BASE SQLITE
# ============================================
. "$scriptPath\Database\Database.ps1"
try {
    $ok = Initialize-Database
    Write-Log "[MAIN] Initialize-Database result" "INFO" @{ ok = $ok }
} catch {
    Write-Log "[MAIN] Initialize-Database failed" "ERROR" @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
    throw
}

# ============================================
# 3. CHARGEMENT DES MODULES MÉTIER
# ============================================
Write-Host "[MAIN] Chargement des modules métier..." -ForegroundColor Gray
. "$scriptPath\ODM\ConventionNommage\ConventionNommage.ps1"
. "$scriptPath\ODM\Agents\AgentRepository.ps1"
. "$scriptPath\ODM\Vehicules\VehiculesRepository.ps1"


# ============================================
# 4. CHARGEMENT ET LANCEMENT DE LA GUI
# ============================================
Write-Host "[MAIN] Chargement de l'interface..." -ForegroundColor Gray
. "$scriptPath\GUI.ps1"

# ============================================
# 5. LANCEMENT
# ============================================
Write-Host "[MAIN] Lancement..." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

try {
    Start-GUI -FichierPDF $args[0]
}
catch {
    if (Get-Command Write-WinFormsInitStateDiagnostic -ErrorAction SilentlyContinue) {
        Write-WinFormsInitStateDiagnostic
    }
    else {
        Write-Host '=== WINFORMS INIT STATE ===' -ForegroundColor Yellow
        Write-Host ("WinFormsInitialized = {0}" -f $global:WinFormsInitialized)
        Write-Host ("WinFormsApplicationInitialized = {0}" -f $global:WinFormsApplicationInitialized)
        Get-PSCallStack | Format-List *
    }
    throw
}

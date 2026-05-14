# ========== MAIN.PS1 - POINT D'ENTRÉE PRINCIPAL NETTOYÉ ==========
# Encodage : UTF-8 (PowerShell 5.1 + fichiers source en UTF-8 avec BOM recommande).

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# WinForms : bootstrap Application en premier.
. (Join-Path $scriptPath 'Bootstrap.ps1')
. (Join-Path $scriptPath 'Common\WinFormsGuard.ps1')

if ($env:CN_WINFORMS_TRACE -eq '1' -or $env:CN_WINFORMS_TRACE -eq 'true') {
    Write-Host "[WINFORMS TRACE] Loaded: Main.ps1 (Bootstrap + diagnostics WinFormsGuard)" -ForegroundColor Magenta
}
. (Join-Path $scriptPath 'Common\TextEncoding.ps1')
. (Join-Path $scriptPath 'Common\UiText.ps1')
Initialize-ConventionAppConsoleUtf8

# ============================================
# 1. CHARGEMENT DES STYLES ET CONFIGURATION
# ============================================
. "$scriptPath\Config.ps1"
# Styles apres UiText (Convert-ToUiText sur libelles boutons).
. "$scriptPath\Common\Styles.ps1"
. "$scriptPath\Core\Logger.ps1"
. "$scriptPath\Core\DependencyCheck.ps1"
Write-Log "[MAIN] Application start" "INFO" @{ scriptPath = $scriptPath }

# ============================================
# 1b. VALIDATION DEPENDANCES EXTERNES
# ============================================
$deps = Test-RuntimeDependencies
if (-not (Get-Module -Name ImportExcel -ListAvailable -ErrorAction SilentlyContinue)) {
    Write-Log "[MAIN] Module ImportExcel non installe - onglet Edition Planning limite" "WARN"
}
if (-not $deps.sqlite) {
    Write-Log "[MAIN] ARRET : driver SQLite manquant" "ERROR"
    [System.Windows.Forms.MessageBox]::Show(
        "Le driver SQLite (lib\System.Data.SQLite.dll) est manquant.`nL'application ne peut pas demarrer.`n`nLancez install\Install.ps1 pour diagnostiquer.",
        "Erreur de dependance",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
    exit 1
}

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
. "$scriptPath\ODM\ConventionNommage\ConventionNommage.ps1"
. "$scriptPath\ODM\Agents\AgentRepository.ps1"
. "$scriptPath\ODM\Vehicules\VehiculesRepository.ps1"


# ============================================
# 4. CHARGEMENT ET LANCEMENT DE LA GUI
# ============================================
. "$scriptPath\GUI.ps1"

# ============================================
# 5. LANCEMENT
# ============================================
Write-Log "[MAIN] Lancement GUI" "INFO"

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

# ========== MAIN.PS1 - POINT D'ENTRÉE PRINCIPAL NETTOYÉ ==========

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "🚀 DÉMARRAGE DE L'APPLICATION..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ============================================
# 1. CHARGEMENT DES STYLES ET CONFIGURATION
# ============================================
Write-Host "[MAIN] Chargement des styles..." -ForegroundColor Gray
. "$scriptPath\Config.ps1"
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

Start-GUI

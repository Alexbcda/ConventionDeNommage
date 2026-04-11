# ========== MAIN.PS1 - POINT D'ENTRÉE PRINCIPAL ==========

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "🚀 DÉMARRAGE DE L'APPLICATION..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ============================================
# 1. CHARGEMENT DES STYLES ET CONFIGURATION
# ============================================
Write-Host "[MAIN] Chargement des styles..." -ForegroundColor Gray
. "$scriptPath\Config.ps1"
. "$scriptPath\Common\Styles.ps1"

# ============================================
# 1.5 INITIALISATION DE LA BASE SQLITE
# ============================================
. "$scriptPath\Database\Database.ps1"
Initialize-Database

# ============================================
# 2. CHARGEMENT DE LA NOUVELLE ARCHITECTURE
# ============================================
Write-Host "[MAIN] Chargement de la nouvelle architecture..." -ForegroundColor Gray
. "$scriptPath\Framework\Store.ps1"
. "$scriptPath\Framework\Router.ps1"
. "$scriptPath\Framework\Components.ps1"
. "$scriptPath\Services\AffectationService.ps1"
. "$scriptPath\Pages\DatePage.ps1"
. "$scriptPath\Pages\TourneesPage.ps1"
. "$scriptPath\Pages\AffectationPage.ps1"

# ============================================
# 3. CHARGEMENT DES MODULES EXISTANTS
# ============================================
Write-Host "[MAIN] Chargement des modules métier..." -ForegroundColor Gray
. "$scriptPath\ODM\ConventionNommage\ConventionNommage.ps1"
. "$scriptPath\ODM\Agents\AgentRepository.ps1"
. "$scriptPath\ODM\Vehicules\VehiculesManager.ps1"

# ============================================
# 4. CHARGEMENT DE LA GUI
# ============================================
Write-Host "[MAIN] Chargement de l'interface..." -ForegroundColor Gray
. "$scriptPath\GUI.ps1"

# ============================================
# 5. LANCEMENT
# ============================================
Write-Host "[MAIN] Lancement..." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Start-GUI

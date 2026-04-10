# ODMViewer.ps1 - Gestionnaire d'onglets pour l'ODM

function Show-ODMViewer {
    param(
        [array]$Collecteurs,
        [array]$Vehicules
    )
    
    Write-Host "[ODM] ========== ODMViewer DÉMARRAGE ==========" -ForegroundColor Cyan
    Write-Host "[ODM] Collecteurs: $($Collecteurs.Count), Véhicules: $($Vehicules.Count)" -ForegroundColor Cyan
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $mainPanel = New-Object System.Windows.Forms.Panel
    $mainPanel.Dock = "Fill"
    $mainPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    
    # Charger les modules
    . "$PSScriptRoot\Collecteurs\CollecteursPanel.ps1"
    . "$PSScriptRoot\Vehicules\VehiculesPanel.ps1"
    . "$PSScriptRoot\AffectationPanel.ps1"
    
    # Créer les onglets
    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Dock = "Fill"
    
    # Onglet Collecteurs
    $tabCollecteurs = New-Object System.Windows.Forms.TabPage
    $tabCollecteurs.Text = "Collecteurs"
    $collecteursPanel = Show-CollecteursPanel -Collecteurs $Collecteurs
    $collecteursPanel.Dock = "Fill"
    $tabCollecteurs.Controls.Add($collecteursPanel)
    $tabControl.TabPages.Add($tabCollecteurs)
    
    # Onglet Véhicules
    $tabVehicules = New-Object System.Windows.Forms.TabPage
    $tabVehicules.Text = "Véhicules"
    $vehiculesPanel = Show-VehiculesPanel -Vehicules $Vehicules
    $vehiculesPanel.Dock = "Fill"
    $tabVehicules.Controls.Add($vehiculesPanel)
    $tabControl.TabPages.Add($tabVehicules)
    
    # Onglet Affectation - UN SEUL
    $tabAffectation = New-Object System.Windows.Forms.TabPage
    $tabAffectation.Text = "Affectation"
    $affectationPanel = Show-AffectationPanel -Collecteurs $Collecteurs -Vehicules $Vehicules
    $affectationPanel.Dock = "Fill"
    $tabAffectation.Controls.Add($affectationPanel)
    $tabControl.TabPages.Add($tabAffectation)
    
    $mainPanel.Controls.Add($tabControl)
    
    Write-Host "[ODM] ========== ODMViewer TERMINÉ ==========" -ForegroundColor Green
    return $mainPanel
}

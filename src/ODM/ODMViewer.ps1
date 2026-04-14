# ODMViewer.ps1 - Gestionnaire d'onglets pour l'ODM

function Show-ODMViewer {
    param([array]$Vehicules)
    
    Write-Host "[ODM] ========== ODMViewer DÉMARRAGE ==========" -ForegroundColor Cyan
    Write-Host "[ODM] Véhicules: $($Vehicules.Count)" -ForegroundColor Cyan
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $mainPanel = New-Object System.Windows.Forms.Panel
    $mainPanel.Dock = "Fill"
    $mainPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    
    # Charger les modules
    . "$PSScriptRoot\Agents\AgentPanel.ps1"
    . "$PSScriptRoot\Vehicules\VehiculesPanel.ps1"
    . "$PSScriptRoot\AffectationPanel.ps1"
    
    # Créer les onglets
    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Dock = "Fill"
    
    # Onglet Agents
    $tabAgents = New-Object System.Windows.Forms.TabPage
    $tabAgents.Text = "Agents"
    $agentsPanel = Show-AgentsPanel
    $agentsPanel.Dock = "Fill"
    $tabAgents.Controls.Add($agentsPanel)
    $tabControl.TabPages.Add($tabAgents)
    
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
    $affectationPanel = Show-AffectationPanel -Agents $Agents -Vehicules $Vehicules
    $affectationPanel.Dock = "Fill"
    $tabAffectation.Controls.Add($affectationPanel)
    $tabControl.TabPages.Add($tabAffectation)
    
    $mainPanel.Controls.Add($tabControl)
    
    Write-Host "[ODM] ========== ODMViewer TERMINÉ ==========" -ForegroundColor Green
    return $mainPanel
}



# ODMViewer.ps1 - Orchestrateur

function Show-ODMViewer {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    # Charger les composants
    . "$PSScriptRoot\Components\DataManager.ps1"
    . "$PSScriptRoot\Components\PlanningPanel.ps1"
    . "$PSScriptRoot\Components\CollecteursPanel.ps1"
    . "$PSScriptRoot\Components\VehiculesPanel.ps1"
    
    # Charger les données
    $collecteurs = Get-Collecteurs
    $vehicules = Get-Vehicules
    
    # Si pas de données, initialiser
    if ($collecteurs.Count -eq 0) {
        $collecteurs, $vehicules = Initialize-DefaultData
    }
    
    # Variables pour stocker les modifications
    $updatedCollecteurs = $collecteurs
    $updatedVehicules = $vehicules
    $planningData = $null
    
    # Créer le panel principal
    $mainPanel = New-Object System.Windows.Forms.Panel
    $mainPanel.Dock = "Fill"
    $mainPanel.BackColor = [System.Drawing.Color]::White
    
    # TabControl
    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Dock = "Fill"
    $tabControl.Font = New-Object System.Drawing.Font("Arial", 10)
    
    # Onglet PLANNING
    $tabPlanning = New-Object System.Windows.Forms.TabPage
    $tabPlanning.Text = "📋 PLANNING"
    $planningResult = Show-PlanningPanel -Collecteurs $collecteurs -Vehicules $vehicules -PlanningData ([ref]$planningData)
    if ($planningResult -is [array]) {
        $planningPanel = $planningResult[-1]
    } else {
        $planningPanel = $planningResult
    }
    $planningPanel.Dock = "Fill"
    $tabPlanning.Controls.Add($planningPanel)
    $tabControl.TabPages.Add($tabPlanning)
    
    # Onglet COLLECTEURS
    $tabCollecteurs = New-Object System.Windows.Forms.TabPage
    $tabCollecteurs.Text = "👨‍✈️ COLLECTEURS"
    $collecteursResult = Show-CollecteursPanel -Collecteurs $collecteurs -UpdatedCollecteurs ([ref]$updatedCollecteurs)
    if ($collecteursResult -is [array]) {
        $collecteursPanel = $collecteursResult[-1]
    } else {
        $collecteursPanel = $collecteursResult
    }
    $collecteursPanel.Dock = "Fill"
    $tabCollecteurs.Controls.Add($collecteursPanel)
    $tabControl.TabPages.Add($tabCollecteurs)
    
    # Onglet VÉHICULES
    $tabVehicules = New-Object System.Windows.Forms.TabPage
    $tabVehicules.Text = "🚛 VÉHICULES"
    $vehiculesResult = Show-VehiculesPanel -Vehicules $vehicules -UpdatedVehicules ([ref]$updatedVehicules)
    if ($vehiculesResult -is [array]) {
        $vehiculesPanel = $vehiculesResult[-1]
    } else {
        $vehiculesPanel = $vehiculesResult
    }
    $vehiculesPanel.Dock = "Fill"
    $tabVehicules.Controls.Add($vehiculesPanel)
    $tabControl.TabPages.Add($tabVehicules)
    
    $mainPanel.Controls.Add($tabControl)
    
    return $mainPanel
}

# ODMViewer.ps1 - Version simplifi?e

function Show-ODMViewer {
    param(
        [string]$PanelType = "Planning"
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    # Charger les composants
    . "$PSScriptRoot\Components\DataManager.ps1"
    . "$PSScriptRoot\Components\PlanningPanel.ps1"
    . "$PSScriptRoot\Components\CollecteursPanel.ps1"
    . "$PSScriptRoot\Components\VehiculesPanel.ps1"
    
    # Charger les donn?es
    $collecteurs = Get-Collecteurs
    $vehicules = Get-Vehicules
    
    if ($collecteurs.Count -eq 0) {
        $collecteurs, $vehicules = Initialize-DefaultData
    }
    
    $planningData = $null
    $updatedCollecteurs = $collecteurs
    $updatedVehicules = $vehicules
    
    # Cr?er le panel
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    
    if ($PanelType -eq "Planning") {
        $result = Show-PlanningPanel -Collecteurs $collecteurs -Vehicules $vehicules -PlanningData ([ref]$planningData)
        if ($result -is [array]) { $result = $result[-1] }
        $result.Dock = "Fill"
        $panel.Controls.Add($result)
    }
    elseif ($PanelType -eq "Collecteurs") {
        $result = Show-CollecteursPanel -Collecteurs $collecteurs -UpdatedCollecteurs ([ref]$updatedCollecteurs)
        if ($result -is [array]) { $result = $result[-1] }
        $result.Dock = "Fill"
        $panel.Controls.Add($result)
    }
    elseif ($PanelType -eq "Vehicules") {
        $result = Show-VehiculesPanel -Vehicules $vehicules -UpdatedVehicules ([ref]$updatedVehicules)
        if ($result -is [array]) { $result = $result[-1] }
        $result.Dock = "Fill"
        $panel.Controls.Add($result)
    }
    
    return $panel
}

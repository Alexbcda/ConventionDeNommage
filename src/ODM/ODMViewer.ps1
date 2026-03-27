# ODMViewer.ps1 - Point d'entrée du module ODM

function Show-ODMViewer {
    param(
        [string]$PanelType = "Planning"
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    . "$PSScriptRoot\..\Core\DataManager.ps1"
    . "$PSScriptRoot\Screens\Screen1_Date.ps1"
    . "$PSScriptRoot\Screens\Screen2_NbTournees.ps1"
    . "$PSScriptRoot\Screens\Screen3_Affectation.ps1"
    . "$PSScriptRoot\PlanningPanel.ps1"
    . "$PSScriptRoot\CollecteursPanel.ps1"
    . "$PSScriptRoot\VehiculesPanel.ps1"
    
    $collecteurs = Get-Collecteurs
    $vehicules = Get-Vehicules
    
    if ($collecteurs.Count -eq 0) {
        $collecteurs, $vehicules = Initialize-DefaultData
    }
    
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    
    if ($PanelType -eq "Planning") {
        $result = Show-PlanningPanel -Collecteurs $collecteurs -Vehicules $vehicules -PlanningData ([ref]$null)
        if ($result -is [array]) { $result = $result[-1] }
        $result.Dock = "Fill"
        $panel.Controls.Add($result)
    }
    elseif ($PanelType -eq "Collecteurs") {
        $result = Show-CollecteursPanel -Collecteurs $collecteurs -UpdatedCollecteurs ([ref]$null)
        if ($result -is [array]) { $result = $result[-1] }
        $result.Dock = "Fill"
        $panel.Controls.Add($result)
    }
    elseif ($PanelType -eq "Vehicules") {
        $result = Show-VehiculesPanel -Vehicules $vehicules -UpdatedVehicules ([ref]$null)
        if ($result -is [array]) { $result = $result[-1] }
        $result.Dock = "Fill"
        $panel.Controls.Add($result)
    }
    
    return $panel
}

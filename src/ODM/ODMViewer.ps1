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
    . "$PSScriptRoot\Collecteurs\CollecteursPanel.ps1"
    . "$PSScriptRoot\Vehicules\VehiculesPanel.ps1"
    
    $collecteurs = Get-Collecteurs
    if ($collecteurs -eq $null) { $collecteurs = @() }
    
    $vehicules = Get-Vehicules
    if ($vehicules -eq $null) { $vehicules = @() }
    
    Write-Host "[ODM] PanelType: $PanelType" -ForegroundColor Cyan
    Write-Host "[ODM] Collecteurs: $($collecteurs.Count), Véhicules: $($vehicules.Count)" -ForegroundColor Gray
    
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    
    if ($PanelType -eq "Planning") {
        if ($collecteurs.Count -eq 0 -or $vehicules.Count -eq 0) {
            Write-Host "[ODM] PlanningPanel: listes vides" -ForegroundColor Yellow
            $msg = New-Object System.Windows.Forms.Label
            $msg.Text = "Pour utiliser le planning, ajoutez d'abord des collecteurs et des véhicules."
            $msg.Location = New-Object System.Drawing.Point(50, 100)
            $msg.Size = New-Object System.Drawing.Size(800, 50)
            $msg.Font = New-Object System.Drawing.Font("Segoe UI", 12)
            $msg.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
            $panel.Controls.Add($msg)
            return $panel
        }
        $result = Show-PlanningPanel -Collecteurs $collecteurs -Vehicules $vehicules -PlanningData ([ref]$null)
        if ($result -is [array]) { $result = $result[-1] }
        if ($result) { 
            $result.Dock = "Fill"
            $panel.Controls.Add($result)
        }
    }
    elseif ($PanelType -eq "Collecteurs") {
        $result = Show-CollecteursPanel -Collecteurs $collecteurs -UpdatedCollecteurs ([ref]$null)
        if ($result -is [array]) { $result = $result[-1] }
        if ($result) { 
            $result.Dock = "Fill"
            $panel.Controls.Add($result)
        }
    }
    elseif ($PanelType -eq "Vehicules") {
        $result = Show-VehiculesPanel -Vehicules $vehicules -UpdatedVehicules ([ref]$null)
        if ($result -is [array]) { $result = $result[-1] }
        if ($result) { 
            $result.Dock = "Fill"
            $panel.Controls.Add($result)
        }
    }
    
    return $panel
}

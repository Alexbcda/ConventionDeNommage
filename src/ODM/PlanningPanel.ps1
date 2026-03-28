# PlanningPanel.ps1 - Orchestrateur des écrans

function Show-PlanningPanel {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Collecteurs,
        [Parameter(Mandatory=$true)]
        [array]$Vehicules,
        [ref]$PlanningData
    )
    
    Write-Host "`n[DEBUG] ========== PLANNINGPANEL DÉMARRAGE ==========" -ForegroundColor Magenta
    Write-Host "[DEBUG] Collecteurs: $($Collecteurs.Count)" -ForegroundColor Magenta
    Write-Host "[DEBUG] Vehicules: $($Vehicules.Count)" -ForegroundColor Magenta
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $screensPath = "C:\Users\alexa\Documents\ConventionDeNommage\src\ODM\Screens"
    
    . "$screensPath\Screen1_Date.ps1"
    . "$screensPath\Screen2_NbTournees.ps1"
    . "$screensPath\Screen3_Affectation.ps1"
    
    $mainPanel = New-Object System.Windows.Forms.Panel
    $mainPanel.Dock = "Fill"
    $mainPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    
    # Créer screen3 (affectation)
    Write-Host "[DEBUG] Création de screen3..." -ForegroundColor Magenta
    $screen3 = New-Object System.Windows.Forms.Panel
    $screen3.Dock = "Fill"
    $screen3.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $screen3.Visible = $false
    
    # Créer screen2 (nombre tournées)
    Write-Host "[DEBUG] Création de screen2..." -ForegroundColor Magenta
    $screen2 = Show-Screen2_NbTournees -NbTournees $null -Screen1 $null -Screen3 $screen3 -Collecteurs $Collecteurs -Vehicules $Vehicules
    $screen2.Visible = $false
    
    # Créer screen1 (date) avec NextScreen = screen2
    Write-Host "[DEBUG] Création de screen1 avec NextScreen = screen2..." -ForegroundColor Magenta
    $screen1 = Show-Screen1_Date -DateSelectionnee $null -NextScreen $screen2
    $screen1.Visible = $true
    
    # MAJ screen2 pour qu'il connaisse screen1
    Write-Host "[DEBUG] Mise à jour de screen2 avec Screen1 = screen1..." -ForegroundColor Magenta
    $script:targetScreen1 = $screen1
    $screen2.Tag = $screen1
    
    # Stocker screen2 dans screen3 pour le retour
    $screen3.Tag = $screen2
    Write-Host "[DEBUG] screen3.Tag = screen2" -ForegroundColor Green
    
    # Ajouter les panels
    $mainPanel.Controls.Add($screen1)
    $mainPanel.Controls.Add($screen2)
    $mainPanel.Controls.Add($screen3)
    
    Write-Host "[DEBUG] Vérification:" -ForegroundColor Magenta
    Write-Host "[DEBUG] screen1.Visible = $($screen1.Visible)" -ForegroundColor Gray
    Write-Host "[DEBUG] screen2.Visible = $($screen2.Visible)" -ForegroundColor Gray
    Write-Host "[DEBUG] screen3.Visible = $($screen3.Visible)" -ForegroundColor Gray
    Write-Host "[DEBUG] ========== PLANNINGPANEL TERMINÉ ==========" -ForegroundColor Magenta
    
    return $mainPanel
}

# AffectationCollecteurTourneePanel.ps1 - Panneau d'affectation
function Show-AffectationCollecteurTourneePanel {
    param($NextPanel, $CurrentPanel)
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $panel.Padding = New-Object System.Windows.Forms.Padding(50)
    
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Affectation Collecteur → Tournée"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $lblTitle.Location = New-Object System.Drawing.Point(0, 0)
    $lblTitle.Size = New-Object System.Drawing.Size(500, 50)
    $panel.Controls.Add($lblTitle)
    
    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Text = "Module en développement"
    $lblInfo.Font = New-Object System.Drawing.Font("Segoe UI", 12)
    $lblInfo.Location = New-Object System.Drawing.Point(0, 70)
    $lblInfo.Size = New-Object System.Drawing.Size(400, 30)
    $panel.Controls.Add($lblInfo)
    
    return $panel
}




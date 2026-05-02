# AffectationNbTourneesPanel.ps1 - Panneau de sélection du nombre de tournées
function Show-AffectationNbTourneesPanel {
    param($NextPanel, $CurrentPanel)
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $panel = [System.Windows.Forms.Panel]::new()
    $panel.Name = "NbTourneesPanelRoot"
    $panel.Dock = "Fill"
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $panel.Padding = [System.Windows.Forms.Padding]::new(50)
    
    $lblTitle = [System.Windows.Forms.Label]::new()
    $lblTitle.Text = "Nombre de tournées"
    $lblTitle.Font = [System.Drawing.Font]::new("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $lblTitle.Location = [System.Drawing.Point]::new(0, 0)
    $lblTitle.Size = [System.Drawing.Size]::new(400, 50)
    $panel.Controls.Add($lblTitle)
    
    $numTournees = [System.Windows.Forms.NumericUpDown]::new()
    $numTournees.Name = "NbTourneesNumeric"
    $numTournees.Location = [System.Drawing.Point]::new(0, 70)
    $numTournees.Size = [System.Drawing.Size]::new(100, 30)
    $numTournees.Minimum = 1
    $numTournees.Maximum = 10
    $numTournees.Value = Get-NbTournees
    $panel.Controls.Add($numTournees)
    
    $btnValider = [System.Windows.Forms.Button]::new()
    $btnValider.Name = "NbTourneesValidateButton"
    $btnValider.Text = "VALIDER"
    $btnValider.Location = [System.Drawing.Point]::new(0, 120)
    $btnValider.Size = [System.Drawing.Size]::new(100, 40)
    $btnValider.BackColor = [System.Drawing.Color]::FromArgb(175, 71, 11)
    $btnValider.ForeColor = [System.Drawing.Color]::White
    $btnValider.FlatStyle = "Flat"
    $panel.Tag = @{
        NextPanel = $NextPanel
        CurrentPanel = $CurrentPanel
    }
    $btnValider.Add_Click({
        param($sender, $e)
        $root = $sender.Parent
        if ($null -eq $root) { return }
        $num = $root.Controls["NbTourneesNumeric"]
        if ($null -ne $num -and $num -is [System.Windows.Forms.NumericUpDown]) {
            Set-NbTournees -NbTournees $num.Value
        }
        $tag = $root.Tag
        if ($tag -is [hashtable]) {
            if ($tag.NextPanel) { $tag.NextPanel.Visible = $true }
            if ($tag.CurrentPanel) { $tag.CurrentPanel.Visible = $false }
        }
    })
    $panel.Controls.Add($btnValider)
    
    return $panel
}




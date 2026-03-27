# NombreTournees.ps1 - Ecran pour saisir le Nombre de tournées

function Show-NombreTournees {
    param(
        [ref]$NombreTournees,
        $screen1, $datePicker, $screen3, $collecteurs, $vehicules
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Top"
    $panel.Height = 150
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    
    # Label
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Nombre de tournées :"
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $lbl.Location = New-Object System.Drawing.Point(35, 25)
    $lbl.Size = New-Object System.Drawing.Size(150, 25)
    $panel.Controls.Add($lbl)
    
    # TextBox
    $txtTournees = New-Object System.Windows.Forms.TextBox
    $txtTournees.Size = New-Object System.Drawing.Size(50, 25)
    $txtTournees.Location = New-Object System.Drawing.Point(195, 23)
    $txtTournees.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $txtTournees.Text = "5"
    $txtTournees.TextAlign = "Center"
    $panel.Controls.Add($txtTournees)
    
    # Bouton Valider
    $btnValider = New-Object System.Windows.Forms.Button
    $btnValider.Text = "VALIDER"
    $btnValider.Size = New-Object System.Drawing.Size(146, 45)
    $btnValider.Location = New-Object System.Drawing.Point(260, 18)
    $btnValider.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnValider.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnValider.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnValider.FlatStyle = "Flat"
    $btnValider.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $btnValider.FlatAppearance.BorderSize = 2
    $btnValider.Cursor = [System.Windows.Forms.Cursors]::Hand
    
    $btnValider.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(229, 90, 42)
        $this.BackColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $btnValider.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    $btnValider.Add_Click({
        $val = [int]$txtTournees.Text
        if ($val -lt 1) { $val = 1 }
        if ($val -gt 20) { $val = 20 }
        $NombreTournees.Value = $val
        $panel.Visible = $false
        $screen3.Visible = $true
        Show-Affectation -nbTournees $val -panel $screen3 -collecteurs $collecteurs -vehicules $vehicules -affectations ([ref]$null)
    })
    $panel.Controls.Add($btnValider)
    
    # Espace
    $spacer = New-Object System.Windows.Forms.Panel
    $spacer.Dock = "Fill"
    $spacer.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $panel.Controls.Add($spacer)
    
    # Panel boutons bas
    $buttonPanel = New-Object System.Windows.Forms.Panel
    $buttonPanel.Dock = "Bottom"
    $buttonPanel.Height = 60
    $buttonPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    
    # RETOUR
    $btnRetour = New-Object System.Windows.Forms.Button
    $btnRetour.Text = "RETOUR"
    $btnRetour.Size = New-Object System.Drawing.Size(140, 40)
    $btnRetour.Location = New-Object System.Drawing.Point(35, 10)
    $btnRetour.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnRetour.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnRetour.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnRetour.FlatStyle = "Flat"
    $btnRetour.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $btnRetour.FlatAppearance.BorderSize = 2
    $btnRetour.Cursor = [System.Windows.Forms.Cursors]::Hand
    
    $btnRetour.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(229, 90, 42)
        $this.BackColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $btnRetour.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    $btnRetour.Add_Click({
        $panel.Visible = $false
        $screen1.Visible = $true
        $datePicker.Focus()
    })
    $buttonPanel.Controls.Add($btnRetour)
    
    # QUITTER
    $btnQuitter = New-Object System.Windows.Forms.Button
    $btnQuitter.Text = "QUITTER"
    $btnQuitter.Size = New-Object System.Drawing.Size(140, 40)
    $btnQuitter.Location = New-Object System.Drawing.Point(195, 10)
    $btnQuitter.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnQuitter.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnQuitter.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnQuitter.FlatStyle = "Flat"
    $btnQuitter.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnQuitter.FlatAppearance.BorderSize = 2
    $btnQuitter.Cursor = [System.Windows.Forms.Cursors]::Hand
    
    $btnQuitter.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
        $this.BackColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $btnQuitter.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    $btnQuitter.Add_Click({
        [System.Windows.Forms.Application]::Exit()
    })
    $buttonPanel.Controls.Add($btnQuitter)
    
    $panel.Controls.Add($buttonPanel)
    
    return $panel
}





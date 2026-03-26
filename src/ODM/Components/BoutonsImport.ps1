# BoutonsImport.ps1 - Boutons supplémentaires pour l'écran d'import

function Add-ImportButtons {
    param($screen2, $btnImport, $screen1, $datePicker)
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    # Panel pour les boutons secondaires
    $buttonPanel = New-Object System.Windows.Forms.Panel
    $buttonPanel.Size = New-Object System.Drawing.Size(400, 55)
    $buttonPanel.Location = New-Object System.Drawing.Point(20, 95)
    $buttonPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    
    # Bouton RETOUR
    $btnRetour = New-Object System.Windows.Forms.Button
    $btnRetour.Text = "◀ RETOUR"
    $btnRetour.Size = New-Object System.Drawing.Size(180, 40)
    $btnRetour.Location = New-Object System.Drawing.Point(0, 8)
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
        $screen2.Visible = $false
        $screen1.Visible = $true
        $btnImport.Text = "IMPORTER LES ODM DU"
        $datePicker.Focus()
    })
    $buttonPanel.Controls.Add($btnRetour)
    
    # Bouton QUITTER
    $btnQuitter = New-Object System.Windows.Forms.Button
    $btnQuitter.Text = "✖ QUITTER"
    $btnQuitter.Size = New-Object System.Drawing.Size(180, 40)
    $btnQuitter.Location = New-Object System.Drawing.Point(200, 8)
    $btnQuitter.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnQuitter.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnQuitter.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnQuitter.FlatStyle = "Flat"
    $btnQuitter.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 100, 100)
    $btnQuitter.FlatAppearance.BorderSize = 2
    $btnQuitter.Cursor = [System.Windows.Forms.Cursors]::Hand
    
    $btnQuitter.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(180, 80, 80)
        $this.BackColor = [System.Drawing.Color]::FromArgb(200, 80, 80)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $btnQuitter.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 100, 100)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    $btnQuitter.Add_Click({
        [System.Windows.Forms.Application]::Exit()
    })
    $buttonPanel.Controls.Add($btnQuitter)
    
    $screen2.Controls.Add($buttonPanel)
    
    # Augmenter la hauteur de screen2
    $screen2.Height = 160
    
    return $buttonPanel
}

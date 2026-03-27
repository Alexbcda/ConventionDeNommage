# PlanningPanel.ps1 - Version avec workflow complet

function Show-PlanningPanel {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Collecteurs,
        [Parameter(Mandatory=$true)]
        [array]$Vehicules,
        [ref]$PlanningData
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    . "$PSScriptRoot\NombreTournees.ps1"
    . "$PSScriptRoot\Affectation.ps1"
    
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $panel.Padding = New-Object System.Windows.Forms.Padding(20)
    
    # Variables
    $script:nbTournees = 0
    $script:affectations = @()
    
    # ========== ?CRAN 1 : CHOISIR LA DATE ==========
    $script:screen1 = New-Object System.Windows.Forms.Panel
    $script:screen1.Dock = "Top"
    $script:screen1.Height = 70
    $script:screen1.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    
    $lblDate = New-Object System.Windows.Forms.Label
    $lblDate.Text = "Choisir une date"
    $lblDate.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblDate.ForeColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $lblDate.Location = New-Object System.Drawing.Point(35, 22)
    $lblDate.Size = New-Object System.Drawing.Size(130, 25)
    $script:screen1.Controls.Add($lblDate)
    
    $script:datePicker = New-Object System.Windows.Forms.DateTimePicker
    $script:datePicker.Format = "Short"
    $script:datePicker.Value = (Get-Date)
    $script:datePicker.Size = New-Object System.Drawing.Size(120, 25)
    $script:datePicker.Location = New-Object System.Drawing.Point(180, 20)
    $script:screen1.Controls.Add($script:datePicker)
    
    $btnValiderDate = New-Object System.Windows.Forms.Button
    $btnValiderDate.Text = "VALIDER"
    $btnValiderDate.Size = New-Object System.Drawing.Size(146, 45)
    $btnValiderDate.Location = New-Object System.Drawing.Point(315, 15)
    $btnValiderDate.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnValiderDate.FlatStyle = "Flat"
    $btnValiderDate.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $btnValiderDate.FlatAppearance.BorderSize = 2
    $btnValiderDate.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnValiderDate.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnValiderDate.Cursor = [System.Windows.Forms.Cursors]::Hand
    
    $btnValiderDate.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(229, 90, 42)
        $this.BackColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $btnValiderDate.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    
    $script:screen1.Controls.Add($btnValiderDate)
    $panel.Controls.Add($script:screen1)
    
    # ========== ?CRAN 2 : NOMBRE DE TOURN?ES ==========
    $script:screen2 = Show-NombreTournees -NombreTournees ([ref]$script:nbTournees) -screen1 $script:screen1 -datePicker $script:datePicker -screen3 $null -collecteurs $Collecteurs -vehicules $Vehicules
    $script:screen2.Visible = $false
    $panel.Controls.Add($script:screen2)
    
    # ========== ?CRAN 3 : AFFECTATION ==========
    $script:screen3 = New-Object System.Windows.Forms.Panel
    $script:screen3.Dock = "Fill"
    $script:screen3.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $script:screen3.Visible = $false
    $panel.Controls.Add($script:screen3)
    
    # ========== ?CRAN 4 : IMPORTER PDF ==========
    $script:screen4 = New-Object System.Windows.Forms.Panel
    $script:screen4.Dock = "Top"
    $script:screen4.Height = 200
    $script:screen4.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $script:screen4.Visible = $false
    
    $btnImport = New-Object System.Windows.Forms.Button
    $btnImport.Text = "IMPORTER LES ODM DU"
    $btnImport.Size = New-Object System.Drawing.Size(300, 95)
    $btnImport.Location = New-Object System.Drawing.Point(35, 10)
    $btnImport.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnImport.FlatStyle = "Flat"
    $btnImport.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $btnImport.FlatAppearance.BorderSize = 2
    $btnImport.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnImport.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btnImport.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnImport.TextAlign = "MiddleCenter"
    
    $btnImport.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(229, 90, 42)
        $this.BackColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $btnImport.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    $btnImport.Add_Click({
        $openDialog = New-Object System.Windows.Forms.OpenFileDialog
        $openDialog.Filter = "Fichiers PDF (*.pdf)|*.pdf"
        if ($openDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:screen4.Visible = $false
            $script:screen5.Visible = $true
            $lblMessage.Text = "PDF charg? : $(Split-Path $openDialog.FileName -Leaf)"
        }
    })
    $script:screen4.Controls.Add($btnImport)
    
    $btnRetour4 = New-Object System.Windows.Forms.Button
    $btnRetour4.Text = "RETOUR"
    $btnRetour4.Size = New-Object System.Drawing.Size(140, 40)
    $btnRetour4.Location = New-Object System.Drawing.Point(35, 120)
    $btnRetour4.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnRetour4.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnRetour4.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnRetour4.FlatStyle = "Flat"
    $btnRetour4.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $btnRetour4.FlatAppearance.BorderSize = 2
    $btnRetour4.Cursor = [System.Windows.Forms.Cursors]::Hand
    
    $btnRetour4.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(229, 90, 42)
        $this.BackColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $btnRetour4.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    $btnRetour4.Add_Click({
        $script:screen4.Visible = $false
        $script:screen3.Visible = $true
    })
    $script:screen4.Controls.Add($btnRetour4)
    
    $btnQuitter4 = New-Object System.Windows.Forms.Button
    $btnQuitter4.Text = "QUITTER"
    $btnQuitter4.Size = New-Object System.Drawing.Size(140, 40)
    $btnQuitter4.Location = New-Object System.Drawing.Point(195, 120)
    $btnQuitter4.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnQuitter4.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnQuitter4.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnQuitter4.FlatStyle = "Flat"
    $btnQuitter4.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnQuitter4.FlatAppearance.BorderSize = 2
    $btnQuitter4.Cursor = [System.Windows.Forms.Cursors]::Hand
    
    $btnQuitter4.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
        $this.BackColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $btnQuitter4.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    $btnQuitter4.Add_Click({
        [System.Windows.Forms.Application]::Exit()
    })
    $script:screen4.Controls.Add($btnQuitter4)
    
    $panel.Controls.Add($script:screen4)
    
    # ========== ?CRAN 5 : CONFIRMATION ==========
    $script:screen5 = New-Object System.Windows.Forms.Panel
    $script:screen5.Dock = "Fill"
    $script:screen5.BackColor = [System.Drawing.Color]::White
    $script:screen5.Visible = $false
    
    $lblMessage = New-Object System.Windows.Forms.Label
    $lblMessage.Text = ""
    $lblMessage.Font = New-Object System.Drawing.Font("Arial", 11)
    $lblMessage.ForeColor = [System.Drawing.Color]::Gray
    $lblMessage.Dock = "Fill"
    $lblMessage.TextAlign = "MiddleCenter"
    $script:screen5.Controls.Add($lblMessage)
    
    $panel.Controls.Add($script:screen5)
    
    # ========== LOGIQUE ==========
    $btnValiderDate.Add_Click({
        $selectedDate = $script:datePicker.Value
        $btnImport.Text = "IMPORTER LES ODM DU" + "`n" + $selectedDate.ToString("dd/MM/yyyy")
        $script:screen1.Visible = $false
        $script:screen2.Visible = $true
    })
    
    # Mettre ? jour la r?f?rence de screen3 dans screen2
    $script:screen2.Tag = $script:screen3
    
    return ,$panel
}


# PlanningPanel.ps1 - Version avec panel personnalisé

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
    
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $panel.Padding = New-Object System.Windows.Forms.Padding(20)
    
    # ========== ÉCRAN 1 : CHOISIR LA DATE ==========
    $script:screen1 = New-Object System.Windows.Forms.Panel
    $script:screen1.Dock = "Top"
    $script:screen1.Height = 70
    $script:screen1.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    
    $lblDate = New-Object System.Windows.Forms.Label
    $lblDate.Text = "Choisir une date"
    $lblDate.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lblDate.ForeColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $lblDate.Location = New-Object System.Drawing.Point(20, 22)
    $lblDate.Size = New-Object System.Drawing.Size(130, 25)
    $script:screen1.Controls.Add($lblDate)
    
    $script:datePicker = New-Object System.Windows.Forms.DateTimePicker
    $script:datePicker.Format = "Short"
    $script:datePicker.Value = (Get-Date)
    $script:datePicker.Size = New-Object System.Drawing.Size(120, 25)
    $script:datePicker.Location = New-Object System.Drawing.Point(155, 20)
    $script:screen1.Controls.Add($script:datePicker)
    
    $btnValiderDate = New-Object System.Windows.Forms.Button
    $btnValiderDate.Text = "VALIDER"
    $btnValiderDate.Size = New-Object System.Drawing.Size(120, 45)
    $btnValiderDate.Location = New-Object System.Drawing.Point(290, 15)
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
    
    # ========== ÉCRAN 2 : IMPORTER PDF ==========
    $script:screen2 = New-Object System.Windows.Forms.Panel
    $script:screen2.Dock = "Top"
    $script:screen2.Height = 85
    $script:screen2.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $script:screen2.Visible = $false
    
    # Panel personnalisé pour l'import
    $btnImport = New-Object System.Windows.Forms.Button
    $btnImport.Size = New-Object System.Drawing.Size(400, 70)
    $btnImport.Location = New-Object System.Drawing.Point(20, 8)
    $btnImport.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnImport.FlatStyle = "Flat"
    $btnImport.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $btnImport.FlatAppearance.BorderSize = 2
    $btnImport.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnImport.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btnImport.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnImport.TextAlign = "MiddleCenter"
    $btnImport.Text = "IMPORTER LES ODM DU`n`n"
    
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
            $script:screen2.Visible = $false
            $script:screen3.Visible = $true
            $lblMessage.Text = "PDF chargé : $(Split-Path $openDialog.FileName -Leaf)"
        }
    })
    
    $script:screen2.Controls.Add($btnImport)
    $script:btnImport = $btnImport
    $script:importLblDate = $lblDate
    $script:importPanel = $importPanel
    $script:importLblDate = $lblDate
    $panel.Controls.Add($script:screen2)
    
    # ========== ÉCRAN 3 : ZONE VIDE ==========
    $script:screen3 = New-Object System.Windows.Forms.Panel
    $script:screen3.Dock = "Fill"
    $script:screen3.BackColor = [System.Drawing.Color]::White
    $script:screen3.Visible = $false
    
    $lblMessage = New-Object System.Windows.Forms.Label
    $lblMessage.Text = ""
    $lblMessage.Font = New-Object System.Drawing.Font("Arial", 11)
    $lblMessage.ForeColor = [System.Drawing.Color]::Gray
    $lblMessage.Dock = "Fill"
    $lblMessage.TextAlign = "MiddleCenter"
    $script:screen3.Controls.Add($lblMessage)
    
    $panel.Controls.Add($script:screen3)
    
    # ========== LOGIQUE ==========
    $btnValiderDate.Add_Click({
        $selectedDate = $script:datePicker.Value
        $script:lblDateDisplay.Text = $selectedDate.ToString("dd/MM/yyyy")
        $script:screen1.Visible = $false
        $script:screen2.Visible = $true
    })
    
    return ,$panel
}









# PlanningPanel.ps1 - Version avec variables de script

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
    $lblDate.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $lblDate.ForeColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $lblDate.Location = New-Object System.Drawing.Point(20, 25)
    $lblDate.Size = New-Object System.Drawing.Size(120, 25)
    $script:screen1.Controls.Add($lblDate)
    
    $script:datePicker = New-Object System.Windows.Forms.DateTimePicker
    $script:datePicker.Format = "Short"
    $script:datePicker.Value = (Get-Date)
    $script:datePicker.Size = New-Object System.Drawing.Size(120, 25)
    $script:datePicker.Location = New-Object System.Drawing.Point(150, 23)
    $script:screen1.Controls.Add($script:datePicker)
    
    $btnValiderDate = New-Object System.Windows.Forms.Button
    $btnValiderDate.Text = "Valider"
    $btnValiderDate.Size = New-Object System.Drawing.Size(100, 30)
    $btnValiderDate.Location = New-Object System.Drawing.Point(280, 20)
    $btnValiderDate.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnValiderDate.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnValiderDate.Font = New-Object System.Drawing.Font("Arial", 10)
    $btnValiderDate.FlatStyle = "Flat"
    $btnValiderDate.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $btnValiderDate.FlatAppearance.BorderSize = 2
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
    $script:screen2.Height = 70
    $script:screen2.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $script:screen2.Visible = $false
    
    $script:btnImportPDF = New-Object System.Windows.Forms.Button
    $script:btnImportPDF.Size = New-Object System.Drawing.Size(280, 40)
    $script:btnImportPDF.Location = New-Object System.Drawing.Point(20, 15)
    $script:btnImportPDF.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $script:btnImportPDF.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $script:btnImportPDF.Font = New-Object System.Drawing.Font("Arial", 10)
    $script:btnImportPDF.FlatStyle = "Flat"
    $script:btnImportPDF.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $script:btnImportPDF.FlatAppearance.BorderSize = 2
    $script:btnImportPDF.Cursor = [System.Windows.Forms.Cursors]::Hand
    
    $script:btnImportPDF.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(229, 90, 42)
        $this.BackColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $script:btnImportPDF.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    
    $script:screen2.Controls.Add($script:btnImportPDF)
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
        Write-Host "=== BOUTON VALIDER CLIQUÉ ===" -ForegroundColor Cyan
        $selectedDate = $script:datePicker.Value
        Write-Host "Date: $selectedDate" -ForegroundColor Yellow
        $script:btnImportPDF.Text = "Importer les ODM du " + $selectedDate.ToString("dd/MM/yyyy")
        Write-Host "Texte: $($script:btnImportPDF.Text)" -ForegroundColor Green
        $script:screen1.Visible = $false
        $script:screen2.Visible = $true
    })
    
    $script:btnImportPDF.Add_Click({
        $openDialog = New-Object System.Windows.Forms.OpenFileDialog
        $openDialog.Filter = "Fichiers PDF (*.pdf)|*.pdf"
        if ($openDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:screen2.Visible = $false
            $script:screen3.Visible = $true
            $lblMessage.Text = "PDF chargé : $(Split-Path $openDialog.FileName -Leaf)"
        }
    })
    
    return ,$panel
}

# PlanningPanel.ps1 - Calendrier sur une ligne

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
    $screen1 = New-Object System.Windows.Forms.Panel
    $screen1.Dock = "Top"
    $screen1.Height = 70
    $screen1.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    
    $lblDate = New-Object System.Windows.Forms.Label
    $lblDate.Text = "Choisir une date"
    $lblDate.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $lblDate.ForeColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $lblDate.Location = New-Object System.Drawing.Point(20, 25)
    $lblDate.Size = New-Object System.Drawing.Size(120, 25)
    $screen1.Controls.Add($lblDate)
    
    $datePicker = New-Object System.Windows.Forms.DateTimePicker
    $datePicker.Format = "Short"
    $datePicker.Value = (Get-Date)
    $datePicker.Size = New-Object System.Drawing.Size(120, 25)
    $datePicker.Location = New-Object System.Drawing.Point(150, 23)
    $screen1.Controls.Add($datePicker)
    
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
    
    $screen1.Controls.Add($btnValiderDate)
    $panel.Controls.Add($screen1)
    
    # ========== ÉCRAN 2 : IMPORTER PDF ==========
    $screen2 = New-Object System.Windows.Forms.Panel
    $screen2.Dock = "Top"
    $screen2.Height = 70
    $screen2.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $screen2.Visible = $false
    
    $lblImport = New-Object System.Windows.Forms.Label
    $lblImport.Text = "Importer le PDF des ODM"
    $lblImport.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $lblImport.ForeColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $lblImport.Location = New-Object System.Drawing.Point(20, 25)
    $lblImport.Size = New-Object System.Drawing.Size(180, 25)
    $screen2.Controls.Add($lblImport)
    
    $btnImportPDF = New-Object System.Windows.Forms.Button
    $btnImportPDF.Text = "Importer PDF"
    $btnImportPDF.Size = New-Object System.Drawing.Size(100, 30)
    $btnImportPDF.Location = New-Object System.Drawing.Point(210, 20)
    $btnImportPDF.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnImportPDF.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnImportPDF.Font = New-Object System.Drawing.Font("Arial", 10)
    $btnImportPDF.FlatStyle = "Flat"
    $btnImportPDF.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $btnImportPDF.FlatAppearance.BorderSize = 2
    $btnImportPDF.Cursor = [System.Windows.Forms.Cursors]::Hand
    
    $btnImportPDF.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(229, 90, 42)
        $this.BackColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $btnImportPDF.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    
    $screen2.Controls.Add($btnImportPDF)
    $panel.Controls.Add($screen2)
    
    # ========== ÉCRAN 3 : ZONE VIDE POUR L'INSTANT ==========
    $screen3 = New-Object System.Windows.Forms.Panel
    $screen3.Dock = "Fill"
    $screen3.BackColor = [System.Drawing.Color]::White
    $screen3.Visible = $false
    
    $lblMessage = New-Object System.Windows.Forms.Label
    $lblMessage.Text = "PDF chargé, en attente de développement..."
    $lblMessage.Font = New-Object System.Drawing.Font("Arial", 11)
    $lblMessage.ForeColor = [System.Drawing.Color]::Gray
    $lblMessage.Dock = "Fill"
    $lblMessage.TextAlign = "MiddleCenter"
    $screen3.Controls.Add($lblMessage)
    
    $panel.Controls.Add($screen3)
    
    # ========== LOGIQUE ==========
    $script:pdfFile = $null
    
    $btnValiderDate.Add_Click({
        $screen1.Visible = $false
        $screen2.Visible = $true
        [System.Windows.Forms.MessageBox]::Show("Date validée : $($datePicker.Value.ToString('dd/MM/yyyy'))", "Succès")
    })
    
    $btnImportPDF.Add_Click({
        $openDialog = New-Object System.Windows.Forms.OpenFileDialog
        $openDialog.Filter = "Fichiers PDF (*.pdf)|*.pdf"
        if ($openDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:pdfFile = $openDialog.FileName
            $screen2.Visible = $false
            $screen3.Visible = $true
            $lblMessage.Text = "PDF chargé : $(Split-Path $script:pdfFile -Leaf)"
            [System.Windows.Forms.MessageBox]::Show("PDF chargé avec succès !", "Succès")
        }
    })
    
    return ,$panel
}

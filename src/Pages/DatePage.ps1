# Pages/DatePage.ps1

function New-DatePage {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $panel.Padding = New-Object System.Windows.Forms.Padding(50)
    
    $title = New-Object System.Windows.Forms.Label
    $title.Text = "📅 Étape 1/3 - Choisir la date"
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $title.Location = New-Object System.Drawing.Point(0, 0)
    $title.Size = New-Object System.Drawing.Size(500, 50)
    $panel.Controls.Add($title)
    
    $lblDate = New-Object System.Windows.Forms.Label
    $lblDate.Text = "Date d'affectation :"
    $lblDate.Font = New-Object System.Drawing.Font("Segoe UI", 12)
    $lblDate.Location = New-Object System.Drawing.Point(0, 70)
    $lblDate.Size = New-Object System.Drawing.Size(150, 35)
    $panel.Controls.Add($lblDate)
    
    $datePicker = New-Object System.Windows.Forms.DateTimePicker
    $datePicker.Format = "Short"
    # Valeur par défaut sécurisée
    try {
        $datePicker.Value = Get-Date
    } catch {
        $datePicker.Value = [DateTime]::Now
    }
    $datePicker.Size = New-Object System.Drawing.Size(180, 35)
    $datePicker.Location = New-Object System.Drawing.Point(160, 70)
    $datePicker.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $panel.Controls.Add($datePicker)
    
    $btnNext = New-Button -Text "Suivant →" -X 350 -Y 70 -Width 120 -Type "primary" -OnClick {
        $date = $datePicker.Value.ToShortDateString()
        Set-Date -Date $date
        Show-Modal -Title "Succès" -Message "Date enregistrée : $date"
        Navigate -Path "/tournees"
    }
    $panel.Controls.Add($btnNext)
    
    $btnQuit = New-Button -Text "Quitter" -X 500 -Y 0 -Width 100 -Type "secondary" -OnClick {
        if (Show-Confirm -Message "Voulez-vous vraiment quitter ?") { [System.Windows.Forms.Application]::Exit() }
    }
    $panel.Controls.Add($btnQuit)
    
    return $panel
}

# Pages/TourneesPage.ps1

function New-TourneesPage {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $panel.Padding = New-Object System.Windows.Forms.Padding(50)
    
    $title = New-Object System.Windows.Forms.Label
    $title.Text = "🔢 Étape 2/3 - Nombre de tournées"
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $title.Location = New-Object System.Drawing.Point(0, 0)
    $title.Size = New-Object System.Drawing.Size(500, 50)
    $panel.Controls.Add($title)
    
    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Text = "Date sélectionnée : $(Get-Date)"
    $lblInfo.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $lblInfo.ForeColor = [System.Drawing.Color]::Gray
    $lblInfo.Location = New-Object System.Drawing.Point(0, 60)
    $lblInfo.Size = New-Object System.Drawing.Size(300, 25)
    $panel.Controls.Add($lblInfo)
    
    $lblNb = New-Object System.Windows.Forms.Label
    $lblNb.Text = "Nombre de tournées :"
    $lblNb.Font = New-Object System.Drawing.Font("Segoe UI", 12)
    $lblNb.Location = New-Object System.Drawing.Point(0, 110)
    $lblNb.Size = New-Object System.Drawing.Size(180, 35)
    $panel.Controls.Add($lblNb)
    
    $numTournees = New-Object System.Windows.Forms.NumericUpDown
    $numTournees.Minimum = 1
    $numTournees.Maximum = 20
    $numTournees.Value = 5
    $numTournees.Size = New-Object System.Drawing.Size(80, 35)
    $numTournees.Location = New-Object System.Drawing.Point(190, 110)
    $numTournees.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $numTournees.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center
    $panel.Controls.Add($numTournees)
    
    $btnNext = New-Button -Text "Suivant →" -X 350 -Y 110 -Width 120 -Type "primary" -OnClick {
        $nb = [int]$numTournees.Value
        Set-NbTournees -Nb $nb
        Show-Modal -Title "Succès" -Message "$nb tournées configurées"
        Navigate -Path "/affectation"
    }
    $panel.Controls.Add($btnNext)
    
    $btnBack = New-Button -Text "← Retour" -X 0 -Y 0 -Width 100 -Type "secondary" -OnClick { Navigate-Back }
    $panel.Controls.Add($btnBack)
    
    $btnQuit = New-Button -Text "Quitter" -X 500 -Y 0 -Width 100 -Type "secondary" -OnClick {
        if (Show-Confirm -Message "Voulez-vous vraiment quitter ?") { [System.Windows.Forms.Application]::Exit() }
    }
    $panel.Controls.Add($btnQuit)
    
    return $panel
}

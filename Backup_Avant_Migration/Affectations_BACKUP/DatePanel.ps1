# DatePanel.ps1 - Interface utilisateur pour la sélection de date

# ============================================================
# FONCTION DE SECOURS
# ============================================================
function Save-DateAffectation {
    param([string]$Date)
    $script:AffectationDate = $Date
    Write-Host "[METIER] Date sauvegardée: $Date" -ForegroundColor Green
}

function Show-DatePanel {
    param(
        $NextPanel,
        $CurrentPanel
    )
    
    Write-Host "[UI-Date] Création du panel de sélection de date" -ForegroundColor Magenta
    
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = $script:CouleurGrisFond
    $panel.Name = "DatePanel"
    
    # Titre
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Affectation des tournées"
    $lblTitle.Font = $script:PoliceTitre
    $lblTitle.ForeColor = $script:CouleurOrange
    $lblTitle.Location = New-Object System.Drawing.Point(50, 30)
    $lblTitle.Size = New-Object System.Drawing.Size(300, 40)
    $panel.Controls.Add($lblTitle)
    
    # Bouton Quitter
    $btnQuitter = New-Object System.Windows.Forms.Button
    Set-BtnQuitterStyle -BtnQuitter $btnQuitter
    $btnQuitter.Location = New-Object System.Drawing.Point(480, 30)
    $btnQuitter.Add_Click({
        [System.Windows.Forms.Application]::Exit()
    }.GetNewClosure())
    $panel.Controls.Add($btnQuitter)
    
    # Label
    $lblChoisir = New-Object System.Windows.Forms.Label
    $lblChoisir.Text = "Choisir une date :"
    $lblChoisir.Font = $script:PoliceNormal
    $lblChoisir.ForeColor = $script:CouleurGrisFonce
    $lblChoisir.Location = New-Object System.Drawing.Point(50, 90)
    $lblChoisir.Size = New-Object System.Drawing.Size(150, 35)
    $panel.Controls.Add($lblChoisir)
    
    # DateTimePicker
    $datePicker = New-Object System.Windows.Forms.DateTimePicker
    $datePicker.Format = "Short"
    $datePicker.Value = Get-Date
    $datePicker.Size = New-Object System.Drawing.Size(150, 35)
    $datePicker.Location = New-Object System.Drawing.Point(200, 90)
    $datePicker.Font = $script:PoliceNormal
    $panel.Controls.Add($datePicker)
    
    # Bouton Valider
    $btnValider = New-Object System.Windows.Forms.Button
    Set-BtnValiderStyle -BtnValider $btnValider
    $btnValider.Location = New-Object System.Drawing.Point(480, 90)
    $btnValider.Add_Click({
        $selectedDate = $datePicker.Value.ToShortDateString()
        Save-DateAffectation -Date $selectedDate
        Write-Host "[UI-Date] Date validée: $selectedDate" -ForegroundColor Green
        
        $form = $this.FindForm()
        $panels = $form.Tag
        $panels["DatePanel"].Visible = $false
        $panels["TourneesPanel"].Visible = $true
    }.GetNewClosure())
    $panel.Controls.Add($btnValider)
    
    return $panel
}
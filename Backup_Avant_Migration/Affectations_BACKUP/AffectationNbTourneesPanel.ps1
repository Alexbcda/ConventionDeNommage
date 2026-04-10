# AffectationNbTourneesPanel.ps1

# SUPPRIMER les fonctions Save-NbTournees et Get-NbTournees ici !
# Elles sont déjà dans Date.ps1

function Show-AffectationNbTourneesPanel {
    param(
        $NextPanel,
        $CurrentPanel,
        $PreviousPanel
    )
    
    Write-Host "[UI-NbTournees] Création du panel" -ForegroundColor Magenta
    
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = $script:CouleurGrisFond
    $panel.Name = "TourneesPanel"
    
    # Titre
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Affectation des tournées"
    $lblTitle.Font = $script:PoliceTitre
    $lblTitle.ForeColor = $script:CouleurOrange
    $lblTitle.Location = New-Object System.Drawing.Point(50, 30)
    $lblTitle.Size = New-Object System.Drawing.Size(300, 40)
    $panel.Controls.Add($lblTitle)
    
    # Bouton RETOUR
    $btnRetour = New-Object System.Windows.Forms.Button
    Set-BtnRetourStyle -BtnRetour $btnRetour
    $btnRetour.Location = New-Object System.Drawing.Point(370, 30)
    $btnRetour.Add_Click({
        $form = $this.FindForm()
        $panels = $form.Tag
        $panels["TourneesPanel"].Visible = $false
        $panels["DatePanel"].Visible = $true
    }.GetNewClosure())
    $panel.Controls.Add($btnRetour)
    
    # Bouton QUITTER
    $btnQuitter = New-Object System.Windows.Forms.Button
    Set-BtnQuitterStyle -BtnQuitter $btnQuitter
    $btnQuitter.Location = New-Object System.Drawing.Point(480, 30)
    $btnQuitter.Add_Click({
        [System.Windows.Forms.Application]::Exit()
    }.GetNewClosure())
    $panel.Controls.Add($btnQuitter)
    
    # Label
    $lblInstruction = New-Object System.Windows.Forms.Label
    $lblInstruction.Text = "Indiquer le nombre de tournées :"
    $lblInstruction.Font = $script:PoliceNormal
    $lblInstruction.ForeColor = $script:CouleurGrisFonce
    $lblInstruction.Location = New-Object System.Drawing.Point(50, 90)
    $lblInstruction.Size = New-Object System.Drawing.Size(250, 35)
    $panel.Controls.Add($lblInstruction)
    
    # NumericUpDown
    $numTournees = New-Object System.Windows.Forms.NumericUpDown
    $numTournees.Minimum = 1
    $numTournees.Maximum = 50
    $numTournees.Value = (Get-NbTournees)
    if ($numTournees.Value -eq 0) { $numTournees.Value = 5 }
    $numTournees.Size = New-Object System.Drawing.Size(80, 35)
    $numTournees.Location = New-Object System.Drawing.Point(300, 90)
    $numTournees.Font = $script:PoliceNormal
    $numTournees.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center
    $panel.Controls.Add($numTournees)
    
    # Label erreur
    $lblError = New-Object System.Windows.Forms.Label
    $lblError.Text = ""
    $lblError.ForeColor = [System.Drawing.Color]::Red
    $lblError.Location = New-Object System.Drawing.Point(50, 135)
    $lblError.Size = New-Object System.Drawing.Size(400, 25)
    $panel.Controls.Add($lblError)
    
    # Bouton VALIDER
    $btnValider = New-Object System.Windows.Forms.Button
    Set-BtnValiderStyle -BtnValider $btnValider
    $btnValider.Location = New-Object System.Drawing.Point(480, 90)
    $btnValider.Add_Click({
        $nbTournees = $numTournees.Value
        
        if ($nbTournees -le 0) {
            $lblError.Text = "❌ Vous devez renseigner le nombre de tournées"
            return
        }
        
        $lblError.Text = ""
        
        # Sauvegarder (la fonction vient de Date.ps1)
        Save-NbTournees -NbTournees $nbTournees
        Write-Host "[UI-Tournees] Nombre de tournées: $nbTournees" -ForegroundColor Green
        
        $form = $this.FindForm()
        $panels = $form.Tag
        
        # Rafraîchir le panel 3 avant de l'afficher
        if ($panels["CollecteurTourneePanel"] -ne $null -and $panels["CollecteurTourneePanel"].Tag -ne $null) {
            $refreshFunc = $panels["CollecteurTourneePanel"].Tag.RefreshData
            if ($refreshFunc) {
                & $refreshFunc
                Write-Host "[UI-NbTournees] Panel 3 rafraîchi avec $nbTournees tournées" -ForegroundColor Green
            }
        }
        
        # Navigation
        $panels["TourneesPanel"].Visible = $false
        $panels["CollecteurTourneePanel"].Visible = $true
    }.GetNewClosure())
    $panel.Controls.Add($btnValider)
    
    return $panel
}
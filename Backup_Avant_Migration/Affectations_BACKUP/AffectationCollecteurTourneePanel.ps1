# AffectationCollecteurTourneePanel.ps1

function Show-AffectationCollecteurTourneePanel {
    param($NextPanel, $CurrentPanel, $PreviousPanel)
    
    Write-Host "[UI-CollecteurTournee] Création du panel" -ForegroundColor Magenta
    
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $panel.Name = "CollecteurTourneePanel"
    $panel.AutoScroll = $true
    
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Affectation collecteur / tournée"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $lblTitle.Location = New-Object System.Drawing.Point(50, 30)
    $lblTitle.Size = New-Object System.Drawing.Size(400, 40)
    $panel.Controls.Add($lblTitle)
    
    $btnRetour = New-Object System.Windows.Forms.Button
    $btnRetour.Text = "RETOUR"
    $btnRetour.Size = New-Object System.Drawing.Size(100, 40)
    $btnRetour.Location = New-Object System.Drawing.Point(370, 30)
    $btnRetour.BackColor = [System.Drawing.Color]::White
    $btnRetour.FlatStyle = "Flat"
    $btnRetour.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $btnRetour.FlatAppearance.BorderSize = 2
    $btnRetour.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnRetour.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnRetour.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnRetour.Add_Click({
        $form = $this.FindForm()
        $panels = $form.Tag
        if ($panels -ne $null) {
            $panels["CollecteurTourneePanel"].Visible = $false
            $panels["TourneesPanel"].Visible = $true
        }
    }.GetNewClosure())
    $panel.Controls.Add($btnRetour)
    
    $btnQuitter = New-Object System.Windows.Forms.Button
    $btnQuitter.Text = "QUITTER"
    $btnQuitter.Size = New-Object System.Drawing.Size(100, 40)
    $btnQuitter.Location = New-Object System.Drawing.Point(480, 30)
    $btnQuitter.BackColor = [System.Drawing.Color]::White
    $btnQuitter.FlatStyle = "Flat"
    $btnQuitter.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnQuitter.FlatAppearance.BorderSize = 2
    $btnQuitter.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnQuitter.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnQuitter.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnQuitter.Add_Click({
        [System.Windows.Forms.Application]::Exit()
    }.GetNewClosure())
    $panel.Controls.Add($btnQuitter)
    
    # Conteneur dynamique pour les tournées
    $dynamicContainer = New-Object System.Windows.Forms.Panel
    $dynamicContainer.Location = New-Object System.Drawing.Point(30, 90)
    $dynamicContainer.Size = New-Object System.Drawing.Size(600, 500)
    $dynamicContainer.AutoScroll = $true
    $panel.Controls.Add($dynamicContainer)
    
    # Fonction de rafraîchissement
    $refreshAction = {
        $nbTournees = Get-NbTournees
        Write-Host "[UI-CollecteurTournee] Rafraîchissement - Nombre de tournées: $nbTournees" -ForegroundColor Yellow
        
        # Nettoyer le conteneur
        $dynamicContainer.Controls.Clear()
        
        if ($nbTournees -eq 0) {
            $lblEmpty = New-Object System.Windows.Forms.Label
            $lblEmpty.Text = "⚠️ Aucune tournée définie. Veuillez d'abord définir le nombre de tournées."
            $lblEmpty.ForeColor = [System.Drawing.Color]::Red
            $lblEmpty.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
            $lblEmpty.Location = New-Object System.Drawing.Point(20, 20)
            $lblEmpty.Size = New-Object System.Drawing.Size(500, 40)
            $dynamicContainer.Controls.Add($lblEmpty)
            return
        }
        
        # Récupérer les collecteurs et véhicules
        $collecteurs = @()
        $collecteursList = Get-Collecteurs
        foreach ($c in $collecteursList) {
            $nomComplet = "$($c.prenom) $($c.nom)".Trim()
            if ($nomComplet) { $collecteurs += $nomComplet }
        }
        if ($collecteurs.Count -eq 0) { $collecteurs = @("Collecteur 1", "Collecteur 2", "Collecteur 3", "Collecteur 4") }
        
        $vehicules = @()
        $vehiculesList = Get-Vehicules
        foreach ($v in $vehiculesList) {
            if ($v.numeroParc) { $vehicules += $v.numeroParc }
        }
        if ($vehicules.Count -eq 0) { $vehicules = @("Véhicule A", "Véhicule B", "Véhicule C") }
        
        $yPos = 10
        $lineHeight = 80
        
        for ($i = 1; $i -le $nbTournees; $i++) {
            $groupBox = New-Object System.Windows.Forms.GroupBox
            $groupBox.Text = "Tournée n°$i"
            $groupBox.Location = New-Object System.Drawing.Point(10, $yPos)
            $groupBox.Size = New-Object System.Drawing.Size(550, 70)
            $groupBox.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
            
            $lblCollecteur = New-Object System.Windows.Forms.Label
            $lblCollecteur.Text = "Collecteur :"
            $lblCollecteur.Font = New-Object System.Drawing.Font("Segoe UI", 10)
            $lblCollecteur.Location = New-Object System.Drawing.Point(20, 30)
            $lblCollecteur.Size = New-Object System.Drawing.Size(80, 25)
            $groupBox.Controls.Add($lblCollecteur)
            
            $cmbCollecteur = New-Object System.Windows.Forms.ComboBox
            $cmbCollecteur.Size = New-Object System.Drawing.Size(200, 25)
            $cmbCollecteur.Location = New-Object System.Drawing.Point(110, 28)
            $cmbCollecteur.Font = New-Object System.Drawing.Font("Segoe UI", 10)
            $cmbCollecteur.DropDownStyle = "DropDownList"
            foreach ($c in $collecteurs) { $cmbCollecteur.Items.Add($c) }
            if ($cmbCollecteur.Items.Count -gt 0) { $cmbCollecteur.SelectedIndex = 0 }
            $groupBox.Controls.Add($cmbCollecteur)
            
            $lblVehicule = New-Object System.Windows.Forms.Label
            $lblVehicule.Text = "Véhicule :"
            $lblVehicule.Font = New-Object System.Drawing.Font("Segoe UI", 10)
            $lblVehicule.Location = New-Object System.Drawing.Point(20, 55)
            $lblVehicule.Size = New-Object System.Drawing.Size(80, 25)
            $groupBox.Controls.Add($lblVehicule)
            
            $cmbVehicule = New-Object System.Windows.Forms.ComboBox
            $cmbVehicule.Size = New-Object System.Drawing.Size(200, 25)
            $cmbVehicule.Location = New-Object System.Drawing.Point(110, 53)
            $cmbVehicule.Font = New-Object System.Drawing.Font("Segoe UI", 10)
            $cmbVehicule.DropDownStyle = "DropDownList"
            foreach ($v in $vehicules) { $cmbVehicule.Items.Add($v) }
            if ($cmbVehicule.Items.Count -gt 0) { $cmbVehicule.SelectedIndex = 0 }
            $groupBox.Controls.Add($cmbVehicule)
            
            $dynamicContainer.Controls.Add($groupBox)
            $yPos += $lineHeight
        }
        
        # Bouton Valider
        $btnValider = New-Object System.Windows.Forms.Button
        $btnValider.Text = "VALIDER TOUTES LES AFFECTATIONS"
        $btnValider.Size = New-Object System.Drawing.Size(200, 40)
        $btnValider.Location = New-Object System.Drawing.Point(180, $yPos + 10)
        $btnValider.BackColor = [System.Drawing.Color]::White
        $btnValider.FlatStyle = "Flat"
        $btnValider.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
        $btnValider.FlatAppearance.BorderSize = 2
        $btnValider.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
        $btnValider.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $btnValider.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btnValider.Add_Click({
            Write-Host "[UI-CollecteurTournee] Affectations sauvegardées" -ForegroundColor Green
            [System.Windows.Forms.MessageBox]::Show("Affectations sauvegardées avec succès !", "Succès")
        }.GetNewClosure())
        $dynamicContainer.Controls.Add($btnValider)
    }
    
    # Stocker la fonction de rafraîchissement dans le tag
    $panel.Tag = @{ RefreshData = $refreshAction }
    
    # Exécuter le rafraîchissement initial
    & $refreshAction
    
    Write-Host "[UI-CollecteurTournee] Panel créé avec fonction de rafraîchissement" -ForegroundColor Green
    
    return $panel
}
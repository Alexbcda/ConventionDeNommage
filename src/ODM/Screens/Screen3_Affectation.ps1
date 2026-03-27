# Screen3_Affectation.ps1 - Version avec conservation de la sélection

function Show-Screen3_Affectation {
    param(
        [int]$NbTournees,
        [System.Windows.Forms.Panel]$Panel,
        [array]$Collecteurs,
        [array]$Vehicules
    )
    
    Write-Host "`n[DEBUG] ========== SCREEN3 AFFECTATION ==========" -ForegroundColor Magenta
    Write-Host "[DEBUG] NbTournees: $NbTournees" -ForegroundColor Magenta
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $Panel.Controls.Clear()
    
    # Données
    $script:AllCollecteurs = $Collecteurs
    $script:AllVehicules = $Vehicules
    $script:SelectedCollecteurs = @()
    $script:SelectedVehicules = @()
    $script:CollecteurComboBoxes = @()
    $script:VehiculeComboBoxes = @()
    $script:Updating = $false
    
    # Fonction de mise à jour (conserve la sélection actuelle)
    $script:UpdateDropdowns = {
        if ($script:Updating) { return }
        $script:Updating = $true
        
        try {
            # Récupérer les IDs déjà sélectionnés (pour les exclure des autres lignes)
            $usedCollecteurIds = @()
            $usedVehiculeIds = @()
            for ($i = 0; $i -lt $script:SelectedCollecteurs.Count; $i++) {
                if ($script:SelectedCollecteurs[$i]) { $usedCollecteurIds += $script:SelectedCollecteurs[$i].id }
                if ($script:SelectedVehicules[$i]) { $usedVehiculeIds += $script:SelectedVehicules[$i].id }
            }
            
            # Collecteurs disponibles (ceux non utilisés PAR D'AUTRES lignes)
            $availableCollecteurs = $script:AllCollecteurs | Where-Object { $_.id -notin $usedCollecteurIds }
            
            # Mettre à jour chaque ComboBox collecteur
            for ($i = 0; $i -lt $script:CollecteurComboBoxes.Count; $i++) {
                $cb = $script:CollecteurComboBoxes[$i]
                $current = $script:SelectedCollecteurs[$i]
                
                $cb.Items.Clear()
                $cb.Items.Add("-- Sélectionner --")
                
                # Ajouter tous les collecteurs disponibles
                foreach ($c in $availableCollecteurs) {
                    $cb.Items.Add("$($c.nom) $($c.prenom)")
                }
                
                # Si un collecteur est sélectionné sur cette ligne, il doit être dans la liste
                if ($current) {
                    $currentItem = "$($current.nom) $($current.prenom)"
                    # Vérifier si l'élément est déjà dans la liste
                    if (-not $cb.Items.Contains($currentItem)) {
                        # Ajouter l'élément sélectionné (même s'il est utilisé)
                        $cb.Items.Add($currentItem)
                        Write-Host "[DEBUG]   -> Ajout de l'élément sélectionné: $currentItem" -ForegroundColor Green
                    }
                    $cb.SelectedItem = $currentItem
                } else {
                    $cb.SelectedIndex = 0
                }
            }
            
            # Véhicules disponibles
            $availableVehicules = $script:AllVehicules | Where-Object { $_.id -notin $usedVehiculeIds }
            
            # Mettre à jour chaque ComboBox véhicule
            for ($i = 0; $i -lt $script:VehiculeComboBoxes.Count; $i++) {
                $cb = $script:VehiculeComboBoxes[$i]
                $current = $script:SelectedVehicules[$i]
                
                $cb.Items.Clear()
                $cb.Items.Add("-- Sélectionner --")
                
                # Ajouter tous les véhicules disponibles
                foreach ($v in $availableVehicules) {
                    $cb.Items.Add("$($v.immatriculation) - $($v.marque) $($v.modele)")
                }
                
                # Si un véhicule est sélectionné sur cette ligne, il doit être dans la liste
                if ($current) {
                    $currentItem = "$($current.immatriculation) - $($current.marque) $($current.modele)"
                    if (-not $cb.Items.Contains($currentItem)) {
                        $cb.Items.Add($currentItem)
                        Write-Host "[DEBUG]   -> Ajout de l'élément sélectionné: $currentItem" -ForegroundColor Green
                    }
                    $cb.SelectedItem = $currentItem
                } else {
                    $cb.SelectedIndex = 0
                }
            }
            
            $usedC = $usedCollecteurIds.Count
            $usedV = $usedVehiculeIds.Count
            Write-Host "[DEBUG] Filtrage: $usedC collecteurs utilisés, $($availableCollecteurs.Count) disponibles" -ForegroundColor Cyan
            
        } finally {
            $script:Updating = $false
        }
    }
    
    # Titre
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "AFFECTATION DES COLLECTEURS ET VÉHICULES"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $lblTitle.Location = New-Object System.Drawing.Point(35, 20)
    $lblTitle.Size = New-Object System.Drawing.Size(600, 35)
    $Panel.Controls.Add($lblTitle)
    
    $lblSubTitle = New-Object System.Windows.Forms.Label
    $lblSubTitle.Text = "$NbTournees tournée(s) à affecter"
    $lblSubTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $lblSubTitle.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $lblSubTitle.Location = New-Object System.Drawing.Point(35, 55)
    $lblSubTitle.Size = New-Object System.Drawing.Size(300, 25)
    $Panel.Controls.Add($lblSubTitle)
    
    # Conteneur des lignes
    $rowsContainer = New-Object System.Windows.Forms.Panel
    $rowsContainer.Location = New-Object System.Drawing.Point(35, 90)
    $rowsContainer.Size = New-Object System.Drawing.Size(1100, 400)
    $rowsContainer.AutoScroll = $true
    $rowsContainer.BackColor = [System.Drawing.Color]::White
    $rowsContainer.BorderStyle = "FixedSingle"
    
    # Création des lignes
    $yPos = 10
    for ($i = 1; $i -le $NbTournees; $i++) {
        Write-Host "[DEBUG] Création ligne $i" -ForegroundColor Gray
        
        $rowPanel = New-Object System.Windows.Forms.Panel
        $rowPanel.Location = New-Object System.Drawing.Point(5, $yPos)
        $rowPanel.Size = New-Object System.Drawing.Size(1080, 50)
        $rowPanel.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
        $rowPanel.BorderStyle = "FixedSingle"
        
        # Numéro
        $lblNum = New-Object System.Windows.Forms.Label
        $lblNum.Text = "Tournée $i"
        $lblNum.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        $lblNum.Location = New-Object System.Drawing.Point(10, 15)
        $lblNum.Size = New-Object System.Drawing.Size(80, 25)
        $rowPanel.Controls.Add($lblNum)
        
        # ComboBox Collecteur
        $cbCollecteur = New-Object System.Windows.Forms.ComboBox
        $cbCollecteur.Location = New-Object System.Drawing.Point(100, 12)
        $cbCollecteur.Size = New-Object System.Drawing.Size(220, 28)
        $cbCollecteur.DropDownStyle = "DropDownList"
        $cbCollecteur.Tag = $i - 1
        $rowPanel.Controls.Add($cbCollecteur)
        
        # ComboBox Véhicule
        $cbVehicule = New-Object System.Windows.Forms.ComboBox
        $cbVehicule.Location = New-Object System.Drawing.Point(340, 12)
        $cbVehicule.Size = New-Object System.Drawing.Size(250, 28)
        $cbVehicule.DropDownStyle = "DropDownList"
        $cbVehicule.Tag = $i - 1
        $rowPanel.Controls.Add($cbVehicule)
        
        $rowsContainer.Controls.Add($rowPanel)
        
        $script:CollecteurComboBoxes += $cbCollecteur
        $script:VehiculeComboBoxes += $cbVehicule
        $script:SelectedCollecteurs += $null
        $script:SelectedVehicules += $null
        
        $yPos += 55
    }
    
    $hauteurTotale = [Math]::Min($yPos + 10, 400)
    $rowsContainer.Height = $hauteurTotale
    $Panel.Controls.Add($rowsContainer)
    
    # Remplissage initial des listes
    Write-Host "[DEBUG] Remplissage initial des listes..." -ForegroundColor Cyan
    
    for ($i = 0; $i -lt $script:CollecteurComboBoxes.Count; $i++) {
        $cb = $script:CollecteurComboBoxes[$i]
        $cb.Items.Add("-- Sélectionner --")
        foreach ($c in $script:AllCollecteurs) {
            $cb.Items.Add("$($c.nom) $($c.prenom)")
        }
        $cb.SelectedIndex = 0
    }
    
    for ($i = 0; $i -lt $script:VehiculeComboBoxes.Count; $i++) {
        $cb = $script:VehiculeComboBoxes[$i]
        $cb.Items.Add("-- Sélectionner --")
        foreach ($v in $script:AllVehicules) {
            $cb.Items.Add("$($v.immatriculation) - $($v.marque) $($v.modele)")
        }
        $cb.SelectedIndex = 0
    }
    
    # Événements
    for ($i = 0; $i -lt $script:CollecteurComboBoxes.Count; $i++) {
        $idx = $i
        $cbCollecteur = $script:CollecteurComboBoxes[$i]
        $cbCollecteur.Add_SelectedIndexChanged({
            if ($script:Updating) { return }
            $index = $this.Tag
            $selected = $this.SelectedItem
            Write-Host "[DEBUG] Collecteur Tournée $($index+1): '$selected'" -ForegroundColor Yellow
            
            if ($selected -and $selected -ne "-- Sélectionner --") {
                $parts = $selected.Split(' ')
                $collecteur = $script:AllCollecteurs | Where-Object { $_.nom -eq $parts[0] -and $_.prenom -eq $parts[1] }
                $script:SelectedCollecteurs[$index] = $collecteur
            } else {
                $script:SelectedCollecteurs[$index] = $null
            }
            & $script:UpdateDropdowns
        })
        
        $cbVehicule = $script:VehiculeComboBoxes[$i]
        $cbVehicule.Add_SelectedIndexChanged({
            if ($script:Updating) { return }
            $index = $this.Tag
            $selected = $this.SelectedItem
            Write-Host "[DEBUG] Véhicule Tournée $($index+1): '$selected'" -ForegroundColor Yellow
            
            if ($selected -and $selected -ne "-- Sélectionner --") {
                $immat = $selected.Split(' ')[0]
                $vehicule = $script:AllVehicules | Where-Object { $_.immatriculation -eq $immat }
                $script:SelectedVehicules[$index] = $vehicule
            } else {
                $script:SelectedVehicules[$index] = $null
            }
            & $script:UpdateDropdowns
        })
    }
    
    # Position Y pour les boutons
    $buttonY = $rowsContainer.Location.Y + $rowsContainer.Height + 20
    
    # Bouton Valider
    $btnValider = New-Object System.Windows.Forms.Button
    $btnValider.Text = "VALIDER LES AFFECTATIONS"
    $btnValider.Size = New-Object System.Drawing.Size(250, 50)
    $btnValider.Location = New-Object System.Drawing.Point(35, $buttonY)
    $btnValider.BackColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $btnValider.ForeColor = [System.Drawing.Color]::White
    $btnValider.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btnValider.FlatStyle = "Flat"
    
    $btnValider.Add_MouseEnter({ $this.BackColor = [System.Drawing.Color]::FromArgb(229, 90, 42) })
    $btnValider.Add_MouseLeave({ $this.BackColor = [System.Drawing.Color]::FromArgb(255, 107, 53) })
    
    $btnValider.Add_Click({
        Write-Host "[DEBUG] ========== VALIDATION ==========" -ForegroundColor Green
        $incompletes = @()
        for ($i = 0; $i -lt $script:SelectedCollecteurs.Count; $i++) {
            if (-not $script:SelectedCollecteurs[$i] -or -not $script:SelectedVehicules[$i]) {
                $incompletes += ($i + 1)
            }
        }
        
        if ($incompletes.Count -gt 0) {
            $msg = "Tournées incomplètes : " + ($incompletes -join ", ")
            [System.Windows.Forms.MessageBox]::Show($msg, "Erreur", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        $resume = "AFFECTATIONS VALIDÉES :`n`n"
        for ($i = 0; $i -lt $script:SelectedCollecteurs.Count; $i++) {
            $c = $script:SelectedCollecteurs[$i]
            $v = $script:SelectedVehicules[$i]
            $resume += "Tournée $($i+1) : $($c.nom) $($c.prenom) → $($v.immatriculation)`n"
        }
        [System.Windows.Forms.MessageBox]::Show($resume, "Succès", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    })
    $Panel.Controls.Add($btnValider)
    
    # Bouton RETOUR
    $btnRetourY = $buttonY + 60
    $btnRetour = New-Object System.Windows.Forms.Button
    $btnRetour.Text = "RETOUR"
    $btnRetour.Size = New-Object System.Drawing.Size(140, 45)
    $btnRetour.Location = New-Object System.Drawing.Point(35, $btnRetourY)
    $btnRetour.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnRetour.FlatStyle = "Flat"
    $btnRetour.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $btnRetour.FlatAppearance.BorderSize = 2
    $btnRetour.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    
    $btnRetour.Add_Click({
        Write-Host "[DEBUG] RETOUR vers Screen2" -ForegroundColor Yellow
        $Panel.Visible = $false
        $parent = $Panel.Parent
        if ($parent) {
            foreach ($ctrl in $parent.Controls) {
                if ($ctrl -is [System.Windows.Forms.Panel] -and $ctrl -ne $Panel) {
                    $ctrl.Visible = $true
                    break
                }
            }
        }
    })
    $Panel.Controls.Add($btnRetour)
    
    # Bouton QUITTER
    $btnQuitter = New-Object System.Windows.Forms.Button
    $btnQuitter.Text = "QUITTER"
    $btnQuitter.Size = New-Object System.Drawing.Size(140, 45)
    $btnQuitter.Location = New-Object System.Drawing.Point(195, $btnRetourY)
    $btnQuitter.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnQuitter.FlatStyle = "Flat"
    $btnQuitter.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnQuitter.FlatAppearance.BorderSize = 2
    $btnQuitter.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    
    $btnQuitter.Add_Click({ 
        Write-Host "[DEBUG] QUITTER" -ForegroundColor Red
        [System.Windows.Forms.Application]::Exit() 
    })
    $Panel.Controls.Add($btnQuitter)
    
    Write-Host "[DEBUG] SCREEN3 OK - $NbTournees lignes" -ForegroundColor Green
    return $Panel
}

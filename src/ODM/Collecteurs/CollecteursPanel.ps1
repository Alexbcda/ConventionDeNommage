# CollecteursPanel.ps1 - Interface de gestion des collecteurs

function Show-CollecteursPanel {
    param([array]$Collecteurs, [ref]$UpdatedCollecteurs)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $panel.Padding = New-Object System.Windows.Forms.Padding(20)

    Write-Host "[PANEL] ========== COLLECTEURS PANEL ==========" -ForegroundColor Cyan

    # ============================================
    # TITRE
    # ============================================
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "GESTION DES COLLECTEURS"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $lblTitle.Location = New-Object System.Drawing.Point(20, 20)
    $lblTitle.Size = New-Object System.Drawing.Size(400, 35)
    $panel.Controls.Add($lblTitle)

    # ============================================
    # BOUTON AJOUTER (style orange au survol)
    # ============================================
    $btnAjouter = New-Object System.Windows.Forms.Button
    $btnAjouter.Text = "➕ AJOUTER UN COLLECTEUR"
    $btnAjouter.Size = New-Object System.Drawing.Size(200, 45)
    $btnAjouter.Location = New-Object System.Drawing.Point(900, 20)
    $btnAjouter.BackColor = [System.Drawing.Color]::White
    $btnAjouter.FlatStyle = "Flat"
    $btnAjouter.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $btnAjouter.FlatAppearance.BorderSize = 2
    $btnAjouter.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnAjouter.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnAjouter.Cursor = [System.Windows.Forms.Cursors]::Hand

    $btnAjouter.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 140, 60)
        $this.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
        $this.ForeColor = [System.Drawing.Color]::White
    })

    $btnAjouter.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
        $this.BackColor = [System.Drawing.Color]::White
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    $panel.Controls.Add($btnAjouter)

    # ============================================
    # DATAGRIDVIEW - SANS COLONNE ID
    # ============================================
    $global:dgvCollecteurs = New-Object System.Windows.Forms.DataGridView
    $global:dgvCollecteurs.Location = New-Object System.Drawing.Point(20, 80)
    $global:dgvCollecteurs.Size = New-Object System.Drawing.Size(1100, 450)
    $global:dgvCollecteurs.BackgroundColor = [System.Drawing.Color]::White
    $global:dgvCollecteurs.AllowUserToAddRows = $false
    $global:dgvCollecteurs.AllowUserToDeleteRows = $false
    $global:dgvCollecteurs.RowHeadersVisible = $false
    $global:dgvCollecteurs.SelectionMode = "FullRowSelect"
    $global:dgvCollecteurs.BorderStyle = "FixedSingle"
    
    $global:dgvCollecteurs.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(229, 90, 42)
    $global:dgvCollecteurs.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
    $global:dgvCollecteurs.RowHeadersDefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(229, 90, 42)

    # Colonnes (sans ID)
    $global:dgvCollecteurs.Columns.Add("Nom", "Nom") | Out-Null
    $global:dgvCollecteurs.Columns.Add("Prenom", "Prénom") | Out-Null
    $global:dgvCollecteurs.Columns.Add("Telephone", "Téléphone") | Out-Null
    $global:dgvCollecteurs.Columns.Add("Email", "Email") | Out-Null
    $global:dgvCollecteurs.Columns.Add("Vehicule", "Véhicule attitré") | Out-Null
    $global:dgvCollecteurs.Columns.Add("Modifier", "Modifier") | Out-Null
    $global:dgvCollecteurs.Columns.Add("Supprimer", "Supprimer") | Out-Null

    $global:dgvCollecteurs.Columns[0].Width = 150
    $global:dgvCollecteurs.Columns[1].Width = 150
    $global:dgvCollecteurs.Columns[2].Width = 120
    $global:dgvCollecteurs.Columns[3].Width = 200
    $global:dgvCollecteurs.Columns[4].Width = 150
    $global:dgvCollecteurs.Columns[5].Width = 70
    $global:dgvCollecteurs.Columns[6].Width = 70

    $panel.Controls.Add($global:dgvCollecteurs)

    # ============================================
    # FONCTION POUR RÉCUPÉRER LE VÉHICULE D'UN COLLECTEUR
    # ============================================
    $global:GetVehiculeForCollecteur = {
        param($CollecteurId)
        $vehicules = Get-Vehicules
        $vehicule = $vehicules | Where-Object { $_.conducteurId -eq $CollecteurId } | Select-Object -First 1
        if ($vehicule) {
            return "$($vehicule.numeroParc) - $($vehicule.immatriculation)"
        }
        return "(Aucun)"
    }

    # ============================================
    # FONCTION DE RAFRAÎCHISSEMENT (tri alphabétique par nom puis prénom)
    # ============================================
    $global:RefreshCollecteursGrid = {
        Write-Host "[REFRESH] Rafraîchissement de la grille collecteurs..." -ForegroundColor Yellow
        $liste = Get-Collecteurs
        $listeTriee = $liste | Sort-Object -Property nom, prenom
        $global:dgvCollecteurs.Rows.Clear()
        $i = 0
        foreach ($c in $listeTriee) {
            $row = $global:dgvCollecteurs.Rows.Add()
            $global:dgvCollecteurs.Rows[$row].Cells[0].Value = $c.nom
            $global:dgvCollecteurs.Rows[$row].Cells[1].Value = $c.prenom
            $global:dgvCollecteurs.Rows[$row].Cells[2].Value = $c.telephone
            $global:dgvCollecteurs.Rows[$row].Cells[3].Value = $c.email
            $global:dgvCollecteurs.Rows[$row].Cells[4].Value = & $global:GetVehiculeForCollecteur -CollecteurId $c.id
            $global:dgvCollecteurs.Rows[$row].Cells[5].Value = "✏️"
            $global:dgvCollecteurs.Rows[$row].Cells[6].Value = "🗑️"
            $global:dgvCollecteurs.Rows[$row].Tag = $c.id
            
            if ($i % 2 -eq 1) {
                $global:dgvCollecteurs.Rows[$row].DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(255, 245, 235)
            }
            $i++
        }
        Write-Host "[REFRESH] Terminé - $($liste.Count) collecteurs affichés" -ForegroundColor Green
    }

    # Remplissage initial
    & $global:RefreshCollecteursGrid

    # ============================================
    # ÉVÉNEMENT AJOUTER
    # ============================================
    $btnAjouter.Add_Click({
        Write-Host "[PANEL] Clic sur Ajouter" -ForegroundColor Cyan
        $nouveau = Show-CollecteurForm -Mode "Ajouter"
        if ($nouveau) {
            Write-Host "[PANEL] Création du collecteur..." -ForegroundColor Yellow
            $resultat = Add-Collecteur -Nom $nouveau.nom -Prenom $nouveau.prenom -Telephone $nouveau.telephone -Email $nouveau.email -VehiculeId $nouveau.vehiculeId
            if ($resultat) {
                Write-Host "[PANEL] Collecteur créé, rafraîchissement..." -ForegroundColor Green
                & $global:RefreshCollecteursGrid
            } else {
                Write-Host "[PANEL] Erreur lors de la création" -ForegroundColor Red
                [System.Windows.Forms.MessageBox]::Show("Erreur lors de l'ajout du collecteur", "Erreur", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        }
    })

    # ============================================
    # ÉVÉNEMENT MODIFIER/SUPPRIMER
    # ============================================
    $global:dgvCollecteurs.Add_CellClick({
        if ($_.RowIndex -ge 0 -and ($_.ColumnIndex -eq 5 -or $_.ColumnIndex -eq 6)) {
            $row = $global:dgvCollecteurs.Rows[$_.RowIndex]
            $id = $row.Tag
            
            $vehiculeActuel = Get-VehiculeByCollecteurId -CollecteurId $id
            $vehiculeActuelId = if ($vehiculeActuel) { $vehiculeActuel.id } else { $null }
            
            if ($_.ColumnIndex -eq 5) {
                Write-Host "[PANEL] Modification du collecteur ID: $id" -ForegroundColor Cyan
                $collecteur = @{
                    id = $id
                    nom = $row.Cells[0].Value
                    prenom = $row.Cells[1].Value
                    telephone = $row.Cells[2].Value
                    email = $row.Cells[3].Value
                    vehiculeActuelId = $vehiculeActuelId
                }
                
                $modifie = Show-CollecteurForm -Mode "Modifier" -Collecteur $collecteur
                if ($modifie) {
                    Write-Host "[PANEL] Sauvegarde des modifications..." -ForegroundColor Yellow
                    $resultat = Update-Collecteur -Id $id -Nom $modifie.nom -Prenom $modifie.prenom -Telephone $modifie.telephone -Email $modifie.email -VehiculeId $modifie.vehiculeId
                    if ($resultat) {
                        Write-Host "[PANEL] Collecteur modifié, rafraîchissement..." -ForegroundColor Green
                        & $global:RefreshCollecteursGrid
                    } else {
                        Write-Host "[PANEL] Erreur lors de la modification" -ForegroundColor Red
                        [System.Windows.Forms.MessageBox]::Show("Erreur lors de la modification du collecteur", "Erreur", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    }
                }
            }
            elseif ($_.ColumnIndex -eq 6) {
                $nomComplet = "$($row.Cells[0].Value) $($row.Cells[1].Value)"
                $confirm = [System.Windows.Forms.MessageBox]::Show("Supprimer le collecteur $nomComplet ?`n`nTous ses véhicules seront libérés.", "Confirmation", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
                if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Write-Host "[PANEL] Suppression du collecteur ID: $id" -ForegroundColor Yellow
                    $resultat = Remove-Collecteur -Id $id
                    if ($resultat) {
                        Write-Host "[PANEL] Collecteur supprimé, rafraîchissement..." -ForegroundColor Green
                        & $global:RefreshCollecteursGrid
                    } else {
                        Write-Host "[PANEL] Erreur lors de la suppression" -ForegroundColor Red
                        [System.Windows.Forms.MessageBox]::Show("Erreur lors de la suppression du collecteur", "Erreur", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    }
                }
            }
        }
    })

    return $panel
}


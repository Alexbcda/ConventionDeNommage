. "$PSScriptRoot\..\..\Database\Database.ps1"
# AgentPanel.ps1 - Interface de gestion des agents

. "$PSScriptRoot\AgentRepository.ps1"
. "$PSScriptRoot\AgentForm.ps1"
. "$PSScriptRoot\..\..\Common\Styles.ps1"

function Show-AgentsPanel {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = $CouleurGrisFond
    $panel.Padding = New-Object System.Windows.Forms.Padding(20)

    Write-Host "[PANEL] ========== AGENTS PANEL ==========" -ForegroundColor Cyan

    # ============================================
    # TITRE
    # ============================================
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Gestion des agents"
    $lblTitle.Font = $script:PoliceTitre1
    $lblTitle.ForeColor = $script:CouleurOrange
    $lblTitle.Location = New-Object System.Drawing.Point(20, 20)
    $lblTitle.Size = New-Object System.Drawing.Size(600, 50)
    $panel.Controls.Add($lblTitle)

    # ============================================
    # BOUTON AJOUTER
    # ============================================
    $btnAjouter = New-Object System.Windows.Forms.Button
    $btnAjouter.Text = "➕ AJOUTER UN AGENT"
    $btnAjouter.Size = New-Object System.Drawing.Size(200, 45)
    $btnAjouter.Location = New-Object System.Drawing.Point(900, 20)
    $btnAjouter.BackColor = [System.Drawing.Color]::White
    $btnAjouter.FlatStyle = "Flat"
    $btnAjouter.FlatAppearance.BorderColor = $CouleurOrange
    $btnAjouter.FlatAppearance.BorderSize = 2
    $btnAjouter.ForeColor = $CouleurGrisFonce
    $btnAjouter.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnAjouter.Cursor = [System.Windows.Forms.Cursors]::Hand

    $btnAjouter.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = $CouleurOrangeClair
        $this.BackColor = $CouleurOrange
        $this.ForeColor = [System.Drawing.Color]::White
    })

    $btnAjouter.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = $CouleurOrange
        $this.BackColor = [System.Drawing.Color]::White
        $this.ForeColor = $CouleurGrisFonce
    })
    $panel.Controls.Add($btnAjouter)

    # ============================================
    # DATAGRIDVIEW
    # ============================================
    $global:dgvAgents = New-Object System.Windows.Forms.DataGridView
    $global:dgvAgents.Location = New-Object System.Drawing.Point(20, 80)
    $global:dgvAgents.Size = New-Object System.Drawing.Size(1100, 450)
    $global:dgvAgents.BackgroundColor = [System.Drawing.Color]::White
    $global:dgvAgents.AllowUserToAddRows = $false
    $global:dgvAgents.AllowUserToDeleteRows = $false
    $global:dgvAgents.RowHeadersVisible = $false
    $global:dgvAgents.SelectionMode = "FullRowSelect"
    $global:dgvAgents.BorderStyle = "FixedSingle"
    
    $global:dgvAgents.DefaultCellStyle.SelectionBackColor = $CouleurSelection
    $global:dgvAgents.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White

    # Colonnes
    $global:dgvAgents.Columns.Add("Nom", "Nom") | Out-Null
    $global:dgvAgents.Columns.Add("Prenom", "Prénom") | Out-Null
    $global:dgvAgents.Columns.Add("Telephone", "Téléphone") | Out-Null
    $global:dgvAgents.Columns.Add("Email", "Email") | Out-Null
    $global:dgvAgents.Columns.Add("Contrat", "Contrat") | Out-Null
    $global:dgvAgents.Columns.Add("Vehicule", "Véhicule attitré") | Out-Null
    $global:dgvAgents.Columns.Add("Modifier", "Modifier") | Out-Null
    $global:dgvAgents.Columns.Add("Supprimer", "Supprimer") | Out-Null

    $global:dgvAgents.Columns[0].Width = 150
    $global:dgvAgents.Columns[1].Width = 150
    $global:dgvAgents.Columns[2].Width = 120
    $global:dgvAgents.Columns[3].Width = 200
    $global:dgvAgents.Columns[4].Width = 100
    $global:dgvAgents.Columns[5].Width = 150
    $global:dgvAgents.Columns[6].Width = 70
    $global:dgvAgents.Columns[7].Width = 70

    $panel.Controls.Add($global:dgvAgents)

    # ============================================
    # FONCTION DE RAFRAÎCHISSEMENT
    # ============================================
    $global:RefreshAgentsGrid = {
        Write-Host "[REFRESH] Rafraîchissement de la grille agents..." -ForegroundColor Yellow
        $liste = Get-Agents
        $listeTriee = $liste | Sort-Object -Property nom, prenom
        $global:dgvAgents.Rows.Clear()
        $i = 0
        foreach ($a in $listeTriee) {
            $row = $global:dgvAgents.Rows.Add()
            $global:dgvAgents.Rows[$row].Cells[0].Value = $a.nom
            $global:dgvAgents.Rows[$row].Cells[1].Value = $a.prenom
            $global:dgvAgents.Rows[$row].Cells[2].Value = $a.telephone
            $global:dgvAgents.Rows[$row].Cells[3].Value = $a.email
            $global:dgvAgents.Rows[$row].Cells[4].Value = $a.type_contrat
            $global:dgvAgents.Rows[$row].Cells[5].Value = if ($a.vehicule_parc) { "$($a.vehicule_parc) - $($a.vehicule_immat)" } else { "(Aucun)" }
            $global:dgvAgents.Rows[$row].Cells[6].Value = "✏️"
            $global:dgvAgents.Rows[$row].Cells[7].Value = "🗑️"
            $global:dgvAgents.Rows[$row].Tag = $a.id
            
            if ($i % 2 -eq 1) {
                $global:dgvAgents.Rows[$row].DefaultCellStyle.BackColor = $CouleurLigneAlternee
            }
            $i++
        }
        Write-Host "[REFRESH] Terminé - $($liste.Count) agents affichés" -ForegroundColor Green
    }

    # Remplissage initial
    & $global:RefreshAgentsGrid

    # ============================================
    # ÉVÉNEMENT AJOUTER
    # ============================================
    $btnAjouter.Add_Click({
        Write-Host "[PANEL] Clic sur Ajouter" -ForegroundColor Cyan
        $nouveau = Show-AgentForm -Mode "Ajouter"
        if ($nouveau) {
            Write-Host "[PANEL] Création de l'agent..." -ForegroundColor Yellow
            $resultat = Add-Agent -Nom $nouveau.nom -Prenom $nouveau.prenom -Telephone $nouveau.telephone -Email $nouveau.email -DateEntree $nouveau.date_entree -TypeContrat $nouveau.type_contrat -BaseHeuresSemaine $nouveau.base_heures_semaine -VehiculeId $nouveau.vehicule_id
            if ($resultat) {
                Write-Host "[PANEL] Agent créé, rafraîchissement..." -ForegroundColor Green
                & $global:RefreshAgentsGrid
            } else {
                Write-Host "[PANEL] Erreur lors de la création" -ForegroundColor Red
                [System.Windows.Forms.MessageBox]::Show("Erreur lors de l'ajout de l'agent", "Erreur", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        }
    })

    # ============================================
    # ÉVÉNEMENT MODIFIER/SUPPRIMER
    # ============================================
    $global:dgvAgents.Add_CellClick({
        if ($_.RowIndex -ge 0 -and ($_.ColumnIndex -eq 6 -or $_.ColumnIndex -eq 7)) {
            $row = $global:dgvAgents.Rows[$_.RowIndex]
            $id = $row.Tag
            
            if ($_.ColumnIndex -eq 6) {
                Write-Host "[PANEL] Modification de l'agent ID: $id" -ForegroundColor Cyan
                $agent = Get-AgentById -Id $id
                
                $agentHash = @{
                    id = $agent.id
                    nom = $agent.nom
                    prenom = $agent.prenom
                    telephone = $agent.telephone
                    email = $agent.email
                    date_entree = $agent.date_entree
                    date_sortie = $agent.date_sortie
                    type_contrat = $agent.type_contrat
                    base_heures_semaine = $agent.base_heures_semaine
                    vehicule_id = $agent.vehicule_id
                }
                
                $modifie = Show-AgentForm -Mode "Modifier" -Agent $agentHash
                if ($modifie) {
                    Write-Host "[PANEL] Sauvegarde des modifications..." -ForegroundColor Yellow
                    $resultat = Update-Agent -Id $id -Nom $modifie.nom -Prenom $modifie.prenom -Telephone $modifie.telephone -Email $modifie.email -DateEntree $modifie.date_entree -DateSortie $null -TypeContrat $modifie.type_contrat -BaseHeuresSemaine $modifie.base_heures_semaine -VehiculeId $modifie.vehicule_id -Poste $modifie.poste
                    if ($resultat) {
                        Write-Host "[PANEL] Agent modifié, rafraîchissement..." -ForegroundColor Green
                        & $global:RefreshAgentsGrid
                    } else {
                        Write-Host "[PANEL] Erreur lors de la modification" -ForegroundColor Red
                        [System.Windows.Forms.MessageBox]::Show("Erreur lors de la modification de l'agent", "Erreur", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    }
                }
            }
            elseif ($_.ColumnIndex -eq 7) {
                $nomComplet = "$($row.Cells[0].Value) $($row.Cells[1].Value)"
                $confirm = [System.Windows.Forms.MessageBox]::Show("Supprimer l'agent $nomComplet ?`n`nTous ses véhicules seront libérés.", "Confirmation", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
                if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Write-Host "[PANEL] Suppression de l'agent ID: $id" -ForegroundColor Yellow
                    $resultat = Remove-Agent -Id $id
                    if ($resultat) {
                        Write-Host "[PANEL] Agent supprimé, rafraîchissement..." -ForegroundColor Green
                        & $global:RefreshAgentsGrid
                    } else {
                        Write-Host "[PANEL] Erreur lors de la suppression" -ForegroundColor Red
                        [System.Windows.Forms.MessageBox]::Show("Erreur lors de la suppression de l'agent", "Erreur", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    }
                }
            }
        }
    })

    return $panel
}




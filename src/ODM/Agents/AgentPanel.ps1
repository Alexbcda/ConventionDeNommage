# AgentPanel.ps1

. "$PSScriptRoot\..\..\Database\Database.ps1"
. "$PSScriptRoot\AgentForm.ps1"

function Show-AgentsPanel {
    Write-Host "[AgentPanel] Démarrage..." -ForegroundColor Cyan
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Création du panel
    $mainPanel = New-Object System.Windows.Forms.Panel
    $mainPanel.Dock = "Fill"
    $mainPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)

    # Titre
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Gestion des agents"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $lblTitle.Location = New-Object System.Drawing.Point(20, 20)
    $lblTitle.Size = New-Object System.Drawing.Size(300, 40)
    $mainPanel.Controls.Add($lblTitle)

    # Bouton Ajouter
    $btnAjouter = New-Object System.Windows.Forms.Button
    $btnAjouter.Text = "+ AJOUTER UN AGENT"
    $btnAjouter.Location = New-Object System.Drawing.Point(900, 20)
    $btnAjouter.Size = New-Object System.Drawing.Size(180, 40)
    $btnAjouter.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $btnAjouter.ForeColor = [System.Drawing.Color]::White
    $btnAjouter.FlatStyle = "Flat"
    $mainPanel.Controls.Add($btnAjouter)

    # DataGridView
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point(20, 80)
    $grid.Size = New-Object System.Drawing.Size(1060, 500)
    $grid.AllowUserToAddRows = $false
    $grid.RowHeadersVisible = $false
    $grid.BackgroundColor = [System.Drawing.Color]::White
    $grid.SelectionMode = "FullRowSelect"
    $grid.BorderStyle = "FixedSingle"

    # Colonnes
    $grid.Columns.Add("Nom", "Nom") | Out-Null
    $grid.Columns.Add("Prenom", "Prénom") | Out-Null
    $grid.Columns.Add("Tel", "Téléphone") | Out-Null
    $grid.Columns.Add("Email", "Email") | Out-Null
    $grid.Columns.Add("Contrat", "Contrat") | Out-Null
    $grid.Columns.Add("Heures", "H/semaine") | Out-Null
    $grid.Columns.Add("Poste", "Poste") | Out-Null
    $grid.Columns.Add("Edit", "") | Out-Null
    $grid.Columns.Add("Delete", "") | Out-Null

    $grid.Columns[0].Width = 120
    $grid.Columns[1].Width = 120
    $grid.Columns[2].Width = 100
    $grid.Columns[3].Width = 180
    $grid.Columns[4].Width = 80
    $grid.Columns[5].Width = 80
    $grid.Columns[6].Width = 120
    $grid.Columns[7].Width = 50
    $grid.Columns[8].Width = 50

    $mainPanel.Controls.Add($grid)

    # Refresh
    function RefreshGrid {
        $grid.Rows.Clear()
        $agents = Get-Agents
        $i = 0
        foreach ($a in $agents) {
            $grid.Rows.Add()
            $grid.Rows[$i].Cells[0].Value = $a.nom
            $grid.Rows[$i].Cells[1].Value = $a.prenom
            $grid.Rows[$i].Cells[2].Value = $a.telephone
            $grid.Rows[$i].Cells[3].Value = $a.email
            $grid.Rows[$i].Cells[4].Value = $a.type_contrat
            $grid.Rows[$i].Cells[5].Value = $a.base_heures_semaine
            $grid.Rows[$i].Cells[6].Value = $a.poste
            $grid.Rows[$i].Cells[7].Value = "✏️"
            $grid.Rows[$i].Cells[8].Value = "🗑️"
            $grid.Rows[$i].Tag = $a.id
            $i++
        }
        Write-Host "[AgentPanel] $i agents" -ForegroundColor Gray
    }

    RefreshGrid

    # Événements
    $btnAjouter.Add_Click({
        $nouveau = Show-AgentForm -Mode "Ajouter"
        if ($nouveau) {
            Add-Agent -Nom $nouveau.nom -Prenom $nouveau.prenom -Telephone $nouveau.telephone -Email $nouveau.email -DateEntree $nouveau.date_entree -DateSortie $nouveau.date_sortie -TypeContrat $nouveau.type_contrat -BaseHeuresSemaine $nouveau.base_heures_semaine -Poste $nouveau.poste
            RefreshGrid
        }
    })

    $grid.Add_CellClick({
        if ($_.RowIndex -ge 0) {
            $id = [int]$grid.Rows[$_.RowIndex].Tag
            
            if ($_.ColumnIndex -eq 7) {
                $agent = Get-AgentById -Id $id
                $modif = Show-AgentForm -Mode "Modifier" -Agent $agent
                if ($modif) {
                    Update-Agent -Id $id -Nom $modif.nom -Prenom $modif.prenom -Telephone $modif.telephone -Email $modif.email -DateEntree $modif.date_entree -DateSortie $modif.date_sortie -TypeContrat $modif.type_contrat -BaseHeuresSemaine $modif.base_heures_semaine -VehiculeId $null -Poste $modif.poste
                    RefreshGrid
                }
            }
            
            if ($_.ColumnIndex -eq 8) {
                $confirm = [System.Windows.Forms.MessageBox]::Show("Supprimer cet agent ?", "Confirmation", "YesNo")
                if ($confirm -eq "Yes") {
                    Remove-Agent -Id $id
                    RefreshGrid
                }
            }
        }
    })

    Write-Host "[AgentPanel] Panel retourné" -ForegroundColor Green
    return $mainPanel
}

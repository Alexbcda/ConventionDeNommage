# AgentPanel.ps1 - VERSION SANS LOGS

. "$PSScriptRoot\..\..\Database\Database.ps1"
. "$PSScriptRoot\AgentRepository.ps1"
. "$PSScriptRoot\AgentForm.ps1"
. "$PSScriptRoot\..\..\Common\Styles.ps1"
. "$PSScriptRoot\..\..\Core\Logger.ps1"

$script:DebugAgentsUI = $false

function Refresh-AgentsGrid {
    <#
    Refresh-AgentsGrid
    - Charge les agents selon le mode historique
    - Centralise la logique d'affichage et le style des lignes
    #>
    param(
        [Parameter(Mandatory=$true)] $Grid,
        [bool]$IncludeHistorique = $false
    )

    Write-Log "[AgentsUI] RefreshGrid begin" "INFO"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $Grid) { throw "Grid is null" }
        $null = $Grid.Rows.Clear()

        # Optimisation: une seule lecture DB selon le mode
        $agents = if ($IncludeHistorique) { Get-AllAgents } else { Get-Agents }
        Write-Log "[AgentsUI] RefreshGrid loaded agents" "INFO" @{ count = $agents.Count }

        $baseFont = if ($Grid.DefaultCellStyle.Font) { $Grid.DefaultCellStyle.Font } else { $Grid.Font }
        $boldFont = New-Object System.Drawing.Font($baseFont, ([System.Drawing.FontStyle]::Bold))
        $normalFont = New-Object System.Drawing.Font($baseFont, ([System.Drawing.FontStyle]::Regular))
        $inactiveColor = [System.Drawing.Color]::FromArgb(150, 150, 150)

        $i = 0
        foreach ($a in $agents) {
            $null = $Grid.Rows.Add()
            $Grid.Rows[$i].Cells[0].Value = $a.nom
            $Grid.Rows[$i].Cells[1].Value = $a.prenom
            $Grid.Rows[$i].Cells[2].Value = $a.telephone
            $Grid.Rows[$i].Cells[3].Value = $a.email
            $Grid.Rows[$i].Cells[4].Value = $a.poste
            $Grid.Rows[$i].Cells[5].Value = $a.type_contrat
            $Grid.Rows[$i].Cells[6].Value = $a.base_heures_semaine
            $Grid.Rows[$i].Cells[7].Value = if ($a.date_entree) { ([datetime]$a.date_entree).ToString("dd/MM/yyyy") } else { "" }
            $Grid.Rows[$i].Cells[8].Value = if ($a.date_sortie) { ([datetime]$a.date_sortie).ToString("dd/MM/yyyy") } else { "" }
            $Grid.Rows[$i].Cells[9].Value = if ($a.numero_parc -and $a.numero_parc -ne [System.DBNull]::Value) { $a.numero_parc } else { "" }
            $Grid.Rows[$i].Cells[10].Value = "✏️"
            $Grid.Rows[$i].Cells[11].Value = "🗑️"
            $Grid.Rows[$i].Tag = $a.id

            # Style visuel: Actifs en gras, Inactifs en gris clair
            $isActif = ([int]$a.actif -eq 1)
            if ($isActif) {
                $Grid.Rows[$i].DefaultCellStyle.Font = $boldFont
                # On garde la couleur par défaut
            } else {
                $Grid.Rows[$i].DefaultCellStyle.Font = $normalFont
                $Grid.Rows[$i].DefaultCellStyle.ForeColor = $inactiveColor
            }
            $i++
        }
        # Tri visuel (en plus du ORDER BY côté SQL)
        if ($Grid.Columns.Contains("Nom")) {
            $Grid.Sort($Grid.Columns["Nom"], [System.ComponentModel.ListSortDirection]::Ascending)
        }
        $Grid.Refresh()
    } catch {
        Write-Log "[AgentsUI] RefreshGrid failed" "ERROR" @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
        throw
    } finally {
        $sw.Stop()
        Write-Log "[AgentsUI] RefreshGrid end" "INFO" @{ rows = $(if ($Grid) { $Grid.Rows.Count } else { $null }); elapsed_ms = $sw.ElapsedMilliseconds }
    }
}

function Show-AgentsPanel {
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $mainPanel = New-Object System.Windows.Forms.Panel
    $mainPanel.Dock = "Fill"
    $mainPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $mainPanel.Padding = New-Object System.Windows.Forms.Padding(20)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Gestion des agents"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $lblTitle.Location = New-Object System.Drawing.Point(20, 20)
    $lblTitle.Size = New-Object System.Drawing.Size(400, 50)
    $mainPanel.Controls.Add($lblTitle)

    # ===== Option historique (actifs + inactifs) =====
    $lblHistorique = New-Object System.Windows.Forms.Label
    $lblHistorique.Text = "Afficher l’historique des agents"
    $lblHistorique.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)
    $lblHistorique.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $lblHistorique.Location = New-Object System.Drawing.Point(20, 62)
    $lblHistorique.Size = New-Object System.Drawing.Size(260, 20)
    $mainPanel.Controls.Add($lblHistorique)

    $chkHistoriqueAgents = New-Object System.Windows.Forms.CheckBox
    $chkHistoriqueAgents.Name = "chkHistoriqueAgents"
    $chkHistoriqueAgents.Location = New-Object System.Drawing.Point(285, 63)
    $chkHistoriqueAgents.Size = New-Object System.Drawing.Size(20, 20)
    $chkHistoriqueAgents.Checked = $false
    $chkHistoriqueAgents.Cursor = [System.Windows.Forms.Cursors]::Hand
    $mainPanel.Controls.Add($chkHistoriqueAgents)

    $btnAjouter = New-Object System.Windows.Forms.Button
    $btnAjouter.Text = "+ AJOUTER UN AGENT"
    $btnAjouter.Location = New-Object System.Drawing.Point(900, 20)
    $btnAjouter.Size = New-Object System.Drawing.Size(200, 45)
    Set-BtnAjouterStyle -BtnAjouter $btnAjouter
    $btnAjouter.Cursor = [System.Windows.Forms.Cursors]::Hand
    $mainPanel.Controls.Add($btnAjouter)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Name = "AgentsGrid"
    $grid.Location = New-Object System.Drawing.Point(20, 95)
    $grid.Size = New-Object System.Drawing.Size(1100, 500)
    $grid.AllowUserToAddRows = $false
    $grid.RowHeadersVisible = $false
    $grid.BackgroundColor = [System.Drawing.Color]::White
    $grid.SelectionMode = "FullRowSelect"
    $grid.BorderStyle = "FixedSingle"
    $grid.AutoSizeColumnsMode = "Fill"
    Set-GridStyle -Grid $grid

    $grid.Columns.Add("Nom", "Nom") | Out-Null
    $grid.Columns.Add("Prenom", "Prénom") | Out-Null
    $grid.Columns.Add("Tel", "Téléphone") | Out-Null
    $grid.Columns.Add("Email", "Email") | Out-Null
    $grid.Columns.Add("Poste", "Poste") | Out-Null
    $grid.Columns.Add("Contrat", "Contrat") | Out-Null
    $grid.Columns.Add("Heures", "Base horaire") | Out-Null
    $grid.Columns.Add("Entree", "Date entrée") | Out-Null
    $grid.Columns.Add("Sortie", "Date sortie") | Out-Null
    $grid.Columns.Add("Parc", "N° parc") | Out-Null
    $grid.Columns.Add("Edit", "Modifier") | Out-Null
    $grid.Columns.Add("Delete", "Supprimer") | Out-Null

    $grid.Columns[0].Width = 110
    $grid.Columns[1].Width = 110
    $grid.Columns[2].Width = 110
    $grid.Columns[3].Width = 190
    $grid.Columns[4].Width = 140
    $grid.Columns[5].Width = 90
    $grid.Columns[6].Width = 90
    $grid.Columns[7].Width = 95
    $grid.Columns[8].Width = 95
    $grid.Columns[9].Width = 80
    $grid.Columns[10].Width = 80
    $grid.Columns[11].Width = 90

    $mainPanel.Controls.Add($grid)
    Refresh-AgentsGrid -Grid $grid -IncludeHistorique $chkHistoriqueAgents.Checked

    $chkHistoriqueAgents.Add_CheckedChanged({
        $mode = if ($this.Checked) { "ON" } else { "OFF" }
        Write-Log "[AgentsUI] Historique mode $mode" "INFO"
        $g = $this.Parent.Controls["AgentsGrid"]
        Refresh-AgentsGrid -Grid $g -IncludeHistorique $this.Checked
    })

    $btnAjouter.Add_Click({
        # $mainPanel peut être $null dans certains contextes d'event; utiliser le bouton comme point d'ancrage.
        try {
            Write-Log "[AgentsUI] Click add agent" "INFO"
            if ($script:DebugAgentsUI) {
                [System.Windows.Forms.MessageBox]::Show("Click: ouverture du formulaire Agent", "Debug", "OK", "Information") | Out-Null
            }
            $owner = $this.FindForm()
            $nouveau = Show-AgentForm -Mode "Ajouter" -Owner $owner
            if (-not $nouveau) {
                Write-Log "[AgentsUI] Add agent cancelled (form returned null)" "INFO"
                return
            }

            if ($script:DebugAgentsUI) {
                [System.Windows.Forms.MessageBox]::Show(
                    ("Form OK:`nnom={0}`nprenom={1}`nentree={2:dd/MM/yyyy}`nsortie={3}" -f $nouveau.nom, $nouveau.prenom, $nouveau.date_entree, $nouveau.date_sortie),
                    "Debug",
                    "OK",
                    "Information"
                ) | Out-Null
            }
            Write-Log "[AgentsUI] Form data ready" "INFO" $nouveau
            $newId = Add-AgentWithValidation -Nom $nouveau.nom -Prenom $nouveau.prenom -Telephone $nouveau.telephone -Email $nouveau.email -DateEntree $nouveau.date_entree -DateSortie $nouveau.date_sortie -TypeContrat $nouveau.type_contrat -BaseHeuresSemaine $nouveau.base_heures_semaine -Poste $nouveau.poste
            Write-Log "[AgentsUI] Add-AgentWithValidation returned" "INFO" @{ id = $newId }
            try {
                $created = Get-AgentById -Id $newId
                if ($created) {
                    Write-Log "[AgentsUI] Created agent loaded from DB" "INFO" @{ id = $created.id; actif = $created.actif }
                } else {
                    Write-Log "[AgentsUI] Created agent not found after insert" "WARN" @{ id = $newId }
                }
            } catch {
                Write-Log "[AgentsUI] Post-insert Get-AgentById failed" "ERROR" @{ id = $newId; message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
            }
            if ($script:DebugAgentsUI) {
                [System.Windows.Forms.MessageBox]::Show(("Ajout OK (id={0})" -f $newId), "Agents", "OK", "Information") | Out-Null
            }
            $g = $this.Parent.Controls["AgentsGrid"]
            $chk = $this.Parent.Controls["chkHistoriqueAgents"]
            Refresh-AgentsGrid -Grid $g -IncludeHistorique $chk.Checked
        } catch {
            Write-Log "[AgentsUI] Add agent failed" "ERROR" @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
            [System.Windows.Forms.MessageBox]::Show(
                ("Erreur lors de l'ajout de l'agent:`n`n{0}" -f $_.Exception.Message),
                "Erreur",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })

    $grid.Add_CellClick({
        param($sender, $e)

        if (-not $sender) { return }
        if (-not $e) { return }
        if ($e.RowIndex -lt 0) { return }
        if ($e.ColumnIndex -lt 0) { return }
        if ($e.RowIndex -ge $sender.Rows.Count) { return }

        $row = $sender.Rows[$e.RowIndex]
        if (-not $row) { return }
        if ($null -eq $row.Tag) { return }

        $id = [int]$row.Tag

        if ($e.ColumnIndex -eq 10) {
            $agent = Get-AgentById -Id $id
            $owner = $sender.FindForm()
            $modif = Show-AgentForm -Mode "Modifier" -Agent $agent -Owner $owner
            if ($modif) {
                Update-Agent -Id $id -Nom $modif.nom -Prenom $modif.prenom -Telephone $modif.telephone -Email $modif.email -DateEntree $modif.date_entree -DateSortie $modif.date_sortie -TypeContrat $modif.type_contrat -BaseHeuresSemaine $modif.base_heures_semaine -Poste $modif.poste | Out-Null
                $chk = $sender.Parent.Controls["chkHistoriqueAgents"]
                Refresh-AgentsGrid -Grid $sender -IncludeHistorique $chk.Checked
            }
            return
        }

        if ($e.ColumnIndex -eq 11) {
            $confirm = [System.Windows.Forms.MessageBox]::Show("Supprimer cet agent ?", "Confirmation", "YesNo")
            if ($confirm -eq "Yes") {
                Remove-Agent -Id $id | Out-Null
                $chk = $sender.Parent.Controls["chkHistoriqueAgents"]
                Refresh-AgentsGrid -Grid $sender -IncludeHistorique $chk.Checked
            }
            return
        }
    })

    # Double-clic sur une ligne: ouvrir le formulaire de modification
    # Ne casse pas le clic sur les colonnes Modifier/Supprimer (on ignore ces colonnes au double-clic).
    $grid.Add_CellDoubleClick({
        param($sender, $e)

        if (-not $sender) { return }
        if (-not $e) { return }
        if ($e.RowIndex -lt 0) { return }
        if ($e.ColumnIndex -lt 0) { return }
        if ($e.RowIndex -ge $sender.Rows.Count) { return }

        # Colonnes actions: laisser le comportement existant du simple clic
        if ($e.ColumnIndex -in 10, 11) { return }

        $row = $sender.Rows[$e.RowIndex]
        if (-not $row) { return }
        if ($null -eq $row.Tag) { return }

        # Bonus: surligner la ligne
        try {
            $sender.ClearSelection()
            $row.Selected = $true
        } catch {}

        $id = [int]$row.Tag
        Write-Log "[AgentsUI] Double-click edit agent ID = $id" "INFO"

        try {
            $agent = Get-AgentById -Id $id
            if (-not $agent) { return }

            $owner = $sender.FindForm()
            $modif = Show-AgentForm -Mode "Modifier" -Agent $agent -Owner $owner
            if ($modif) {
                Update-Agent -Id $id -Nom $modif.nom -Prenom $modif.prenom -Telephone $modif.telephone -Email $modif.email -DateEntree $modif.date_entree -DateSortie $modif.date_sortie -TypeContrat $modif.type_contrat -BaseHeuresSemaine $modif.base_heures_semaine -Poste $modif.poste | Out-Null
                $chk = $sender.Parent.Controls["chkHistoriqueAgents"]
                Refresh-AgentsGrid -Grid $sender -IncludeHistorique $chk.Checked
            }
        } catch {
            Write-Log "[AgentsUI] Double-click edit failed" "ERROR" @{ id = $id; message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
            [System.Windows.Forms.MessageBox]::Show(
                ("Erreur lors de la modification de l'agent:`n`n{0}" -f $_.Exception.Message),
                "Erreur",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })

    return $mainPanel
}
# AgentPanel.ps1 - VERSION SANS LOGS

. "$PSScriptRoot\..\..\Services\AgentService.ps1"
. "$PSScriptRoot\AgentForm.ps1"
. "$PSScriptRoot\..\..\Common\Styles.ps1"
. "$PSScriptRoot\..\..\Common\WinFormsHelpers.ps1"
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
        $agents = if ($IncludeHistorique) { Get-AgentList -IncludeInactive } else { Get-AgentList }
        Write-Log "[AgentsUI] RefreshGrid loaded agents" "INFO" @{ count = $agents.Count }

        $i = 0
        foreach ($a in $agents) {
            $null = $Grid.Rows.Add()
            $Grid.Rows[$i].Cells[$Grid.Columns["Nom"].Index].Value = $a.nom
            $Grid.Rows[$i].Cells[$Grid.Columns["Prenom"].Index].Value = $a.prenom
            $Grid.Rows[$i].Cells[$Grid.Columns["Tel"].Index].Value = $a.telephone
            $Grid.Rows[$i].Cells[$Grid.Columns["Email"].Index].Value = $a.email
            $Grid.Rows[$i].Cells[$Grid.Columns["Parc"].Index].Value = if ($a.numero_parc -and $a.numero_parc -ne [System.DBNull]::Value) { $a.numero_parc } else { "" }
            $Grid.Rows[$i].Cells[$Grid.Columns["Contrat"].Index].Value = $a.type_contrat
            $Grid.Rows[$i].Cells[$Grid.Columns["Heures"].Index].Value = $a.base_heures_semaine
            $Grid.Rows[$i].Cells[$Grid.Columns["Edit"].Index].Value = "✏️"
            $Grid.Rows[$i].Cells[$Grid.Columns["Delete"].Index].Value = "🗑️"
            $Grid.Rows[$i].Tag = $a.id

            Set-CrudGridRowStyle -Grid $Grid -RowIndex $i -IsActif ([int]$a.actif -eq 1)
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

    $header = New-CrudPanelHeader -Title $script:TitrePanelAgents -HistoriqueLabel "Afficher l'historique des agents" -CheckboxName "chkHistoriqueAgents" -ButtonText "AJOUTER" -ButtonWidth 180
    $mainPanel = $header.Panel
    $chkHistoriqueAgents = $header.Checkbox
    $btnAjouter = $header.Button

    $grid = New-CrudDataGrid -Name "AgentsGrid" -ColumnDefs @(
        @{ Name = "Nom";     Header = "Nom";              Width = 150 },
        @{ Name = "Prenom";  Header = "Prénom";           Width = 120 },
        @{ Name = "Tel";     Header = "Téléphone";        Width = 110 },
        @{ Name = "Email";   Header = "Email";            Width = 120 },
        @{ Name = "Parc";    Header = "N° parc";          Width = 90  },
        @{ Name = "Contrat"; Header = "Type de contrat";  Width = 130 },
        @{ Name = "Heures";  Header = "Base heures";      Width = 100 },
        @{ Name = "Edit";    Header = "Modifier";         Width = 90  },
        @{ Name = "Delete";  Header = "Supprimer";        Width = 90  }
    )
    $grid.Columns["Email"].DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::False
    $grid.Columns["Email"].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleLeft

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
            Write-Log "[AgentsUI] Form data ready" "INFO" @{ ok = $true }
            $newId = Add-AgentEntry -Nom $nouveau.nom -Prenom $nouveau.prenom -Telephone $nouveau.telephone -Email $nouveau.email -DateEntree $nouveau.date_entree -DateSortie $nouveau.date_sortie -TypeContrat $nouveau.type_contrat -BaseHeuresSemaine $nouveau.base_heures_semaine -Poste $nouveau.poste
            Write-Log "[AgentsUI] Add-AgentEntry returned" "INFO" @{ id = $newId }
            try {
                $created = Get-AgentDetails -Id $newId
                if ($created) {
                    Write-Log "[AgentsUI] Created agent loaded from DB" "INFO" @{ id = $created.id; actif = $created.actif }
                } else {
                    Write-Log "[AgentsUI] Created agent not found after insert" "WARN" @{ id = $newId }
                }
            } catch {
                Write-Log "[AgentsUI] Post-insert Get-AgentDetails failed" "ERROR" @{ id = $newId; message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
            }
            if ($script:DebugAgentsUI) {
                [System.Windows.Forms.MessageBox]::Show(("Ajout OK (id={0})" -f $newId), "Agents", "OK", "Information") | Out-Null
            }
            $g = $this.Parent.Controls["AgentsGrid"]
            $chk = $this.Parent.Controls["chkHistoriqueAgents"]
            Refresh-AgentsGrid -Grid $g -IncludeHistorique $chk.Checked
        } catch {
            Write-Log "[AgentsUI] Add agent failed" "ERROR" @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
            Show-CrudErrorDialog -OperationLabel "l'ajout de l'agent" -ErrorMessage $_.Exception.Message
        }
    })

    $grid.Add_CellClick({
        param($sender, $e)

        $row = Test-CellClickGuards -Sender $sender -EventArgs $e
        if (-not $row) { return }

        $id = [int]$row.Tag

        $editCol = $sender.Columns["Edit"].Index
        $delCol = $sender.Columns["Delete"].Index

        if ($e.ColumnIndex -eq $editCol) {
            $agent = Get-AgentDetails -Id $id
            $owner = $sender.FindForm()
            $modif = Show-AgentForm -Mode "Modifier" -Agent $agent -Owner $owner
            if ($modif) {
                Update-AgentEntry -Id $id -Nom $modif.nom -Prenom $modif.prenom -Telephone $modif.telephone -Email $modif.email -DateEntree $modif.date_entree -DateSortie $modif.date_sortie -TypeContrat $modif.type_contrat -BaseHeuresSemaine $modif.base_heures_semaine -Poste $modif.poste | Out-Null
                $chk = $sender.Parent.Controls["chkHistoriqueAgents"]
                Refresh-AgentsGrid -Grid $sender -IncludeHistorique $chk.Checked
            }
            return
        }

        if ($e.ColumnIndex -eq $delCol) {
            $confirm = [System.Windows.Forms.MessageBox]::Show("Supprimer cet agent ?", "Confirmation", "YesNo")
            if ($confirm -eq "Yes") {
                Remove-AgentEntry -Id $id | Out-Null
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

        $row = Test-CellClickGuards -Sender $sender -EventArgs $e
        if (-not $row) { return }

        try {
            $editCol = $sender.Columns["Edit"].Index
            $delCol = $sender.Columns["Delete"].Index
            if ($e.ColumnIndex -in @($editCol, $delCol)) { return }
        } catch {}

        # Bonus: surligner la ligne
        try {
            $sender.ClearSelection()
            $row.Selected = $true
        } catch {}

        $id = [int]$row.Tag
        Write-Log "[AgentsUI] Double-click edit agent ID = $id" "INFO"

        try {
            $agent = Get-AgentDetails -Id $id
            if (-not $agent) { return }

            $owner = $sender.FindForm()
            $modif = Show-AgentForm -Mode "Modifier" -Agent $agent -Owner $owner
            if ($modif) {
                Update-AgentEntry -Id $id -Nom $modif.nom -Prenom $modif.prenom -Telephone $modif.telephone -Email $modif.email -DateEntree $modif.date_entree -DateSortie $modif.date_sortie -TypeContrat $modif.type_contrat -BaseHeuresSemaine $modif.base_heures_semaine -Poste $modif.poste | Out-Null
                $chk = $sender.Parent.Controls["chkHistoriqueAgents"]
                Refresh-AgentsGrid -Grid $sender -IncludeHistorique $chk.Checked
            }
        } catch {
            Write-Log "[AgentsUI] Double-click edit failed" "ERROR" @{ id = $id; message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
            Show-CrudErrorDialog -OperationLabel "la modification de l'agent" -ErrorMessage $_.Exception.Message
        }
    })

    return $mainPanel
}
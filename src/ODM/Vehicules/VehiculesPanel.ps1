# VehiculesPanel.ps1 - Version refactorisée selon charte AgentPanel
#
# Objet véhicule (données liste / DB, propriétés snake_case côté repository) :
#   id: string|number ; numero_parc ; immatriculation ; numero_chassis ; actif: 0|1 ; …

. "$PSScriptRoot\..\..\Common\Styles.ps1"
. "$PSScriptRoot\..\..\Common\WinFormsHelpers.ps1"
. "$PSScriptRoot\..\..\Core\Logger.ps1"
. "$PSScriptRoot\..\..\Services\VehiculeService.ps1"
. "$PSScriptRoot\VehiculesForm.ps1"

function Invoke-EditVehicule {
    param([Parameter(Mandatory=$true)] $Id, [Parameter(Mandatory=$true)] $Grid)
    $vehiculeComplet = Get-VehiculeDetails -Id $Id
    if (-not $vehiculeComplet) { return }
    $vehiculeData = ConvertTo-VehiculeFormData $vehiculeComplet
    $owner = $Grid.FindForm()
    $modifie = Show-VehiculeForm -Mode "Modifier" -Vehicule $vehiculeData -Owner $owner
    if ($modifie) {
        Update-VehiculeEntry `
            -Id $Id `
            -NumeroParc $modifie.numeroParc `
            -Immatriculation $modifie.immatriculation `
            -NumeroChassis $modifie.numeroChassis `
            -Marque $modifie.marque `
            -Modele $modifie.modele `
            -DateMiseCirculation $modifie.dateMiseCirculation `
            -DateControle $modifie.dateControle `
            -DateEntree $modifie.dateEntree `
            -DateSortie $modifie.dateSortie `
            -DateFinControleTechnique $modifie.dateFinControleTechnique | Out-Null
        $chk = $Grid.Parent.Controls["chkHistoriqueVehicules"]
        $empty = $Grid.Parent.Controls["lblVehiculesEmpty"]
        Refresh-VehiculesGrid -Grid $Grid -IncludeHistorique $chk.Checked -EmptyStateLabel $empty
    }
}

function Refresh-VehiculesGrid {
    <#
    Refresh-VehiculesGrid
    - Charge les véhicules selon le mode historique (actif = 1 seul, ou tous si IncludeHistorique)
    - Colonnes grille : N° parc, Immatriculation, Numéro de châssis, Fin contrôle technique, Modifier, Supprimer
    #>
    param(
        [Parameter(Mandatory=$true)] $Grid,
        [bool]$IncludeHistorique = $false,
        [System.Windows.Forms.Label]$EmptyStateLabel = $null
    )

    Write-Log "[VehiculesUI] RefreshGrid begin" "INFO"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ownerForm = $null
    try {
        if (-not $Grid) { throw "Grid is null" }
        $ownerForm = $Grid.FindForm()
        if ($ownerForm) {
            $ownerForm.UseWaitCursor = $true
            $ownerForm.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        }

        $null = $Grid.Rows.Clear()

        # Une seule lecture DB selon le mode
        $vehicules = @(
            if ($IncludeHistorique) { Get-VehiculeList -IncludeInactive } else { Get-VehiculeList }
        )
        Write-Log "[VehiculesUI] RefreshGrid loaded vehicles" "INFO" @{ count = $vehicules.Count }

        $i = 0
        foreach ($v in $vehicules) {
            $null = $Grid.Rows.Add()
            $Grid.Rows[$i].Cells[$Grid.Columns["NumeroParc"].Index].Value = if ($v.numero_parc -and $v.numero_parc -ne [System.DBNull]::Value) { $v.numero_parc } else { "" }
            $Grid.Rows[$i].Cells[$Grid.Columns["Immatriculation"].Index].Value = if ($v.immatriculation -and $v.immatriculation -ne [System.DBNull]::Value) { $v.immatriculation } else { "" }
            $Grid.Rows[$i].Cells[$Grid.Columns["NumeroChassis"].Index].Value = if ($v.numero_chassis -and $v.numero_chassis -ne [System.DBNull]::Value) { $v.numero_chassis } else { "" }
            $Grid.Rows[$i].Cells[$Grid.Columns["DateFinControleTechnique"].Index].Value = if ($v.date_fin_controle_technique -and $v.date_fin_controle_technique -ne [System.DBNull]::Value) { $v.date_fin_controle_technique } else { "" }
            $Grid.Rows[$i].Cells[$Grid.Columns["Edit"].Index].Value = "✏️"
            $Grid.Rows[$i].Cells[$Grid.Columns["Delete"].Index].Value = "🗑️"
            $Grid.Rows[$i].Tag = $v.id

            Set-CrudGridRowStyle -Grid $Grid -RowIndex $i -IsActif ([int]$v.actif -eq 1)
            $i++
        }

        if ($Grid.Columns.Contains("NumeroParc")) {
            $Grid.Sort($Grid.Columns["NumeroParc"], [System.ComponentModel.ListSortDirection]::Ascending)
        }
        $Grid.Refresh()

        if ($EmptyStateLabel) {
            $EmptyStateLabel.Visible = ($vehicules.Count -eq 0)
            if ($EmptyStateLabel.Visible) { $EmptyStateLabel.BringToFront() }
        }
    } catch {
        Write-Log "[VehiculesUI] RefreshGrid failed" "ERROR" @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
        throw
    } finally {
        if ($ownerForm) {
            $ownerForm.UseWaitCursor = $false
            $ownerForm.Cursor = [System.Windows.Forms.Cursors]::Default
        }
        $sw.Stop()
        Write-Log "[VehiculesUI] RefreshGrid end" "INFO" @{ rows = $(if ($Grid) { $Grid.Rows.Count } else { $null }); elapsed_ms = $sw.ElapsedMilliseconds }
    }
}

function Show-VehiculesPanel {

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $header = New-CrudPanelHeader -Title $script:TitrePanelVehicules -HistoriqueLabel "Afficher l'historique des véhicules" -CheckboxName "chkHistoriqueVehicules" -ButtonText "Ajouter un véhicule" -ButtonWidth 220
    $mainPanel = $header.Panel
    $chkHistoriqueVehicules = $header.Checkbox
    $btnAjouter = $header.Button

    $grid = New-CrudDataGrid -Name "VehiculesGrid" -ColumnDefs @(
        @{ Name = "NumeroParc";               Header = "N° parc";                          Width = 120 },
        @{ Name = "Immatriculation";          Header = "Immatriculation";                  Width = 160 },
        @{ Name = "NumeroChassis";            Header = "Numéro de châssis";                Width = 230 },
        @{ Name = "DateFinControleTechnique"; Header = "Contrôle technique (date limite)"; Width = 160 },
        @{ Name = "Edit";                     Header = "Modifier";                         Width = 90  },
        @{ Name = "Delete";                   Header = "Supprimer";                        Width = 90  }
    )

    $mainPanel.Controls.Add($grid)

    # Liste vide (optionnel, charte lisible)
    $lblVehiculesEmpty = [System.Windows.Forms.Label]::new()
    $lblVehiculesEmpty.Name = "lblVehiculesEmpty"
    $lblVehiculesEmpty.Text = "Aucun véhicule à afficher."
    $lblVehiculesEmpty.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lblVehiculesEmpty.Font = [System.Drawing.Font]::new("Segoe UI", 11, [System.Drawing.FontStyle]::Regular)
    $lblVehiculesEmpty.ForeColor = [System.Drawing.Color]::FromArgb(120, 120, 120)
    $lblVehiculesEmpty.BackColor = [System.Drawing.Color]::White
    $lblVehiculesEmpty.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $lblVehiculesEmpty.Location = $grid.Location
    $lblVehiculesEmpty.Size = $grid.Size
    $lblVehiculesEmpty.Anchor = $grid.Anchor
    $lblVehiculesEmpty.Visible = $false
    $mainPanel.Controls.Add($lblVehiculesEmpty)
    $lblVehiculesEmpty.BringToFront()

    # ===== CHARGEMENT INITIAL =====
    Refresh-VehiculesGrid -Grid $grid -IncludeHistorique $chkHistoriqueVehicules.Checked -EmptyStateLabel $lblVehiculesEmpty

    # ===== ÉVÉNEMENT HISTORIQUE =====
    $chkHistoriqueVehicules.Add_CheckedChanged({
        $mode = if ($this.Checked) { "ON" } else { "OFF" }
        Write-Log "[VehiculesUI] Historique mode $mode" "INFO"
        $g = $this.Parent.Controls["VehiculesGrid"]
        $empty = $this.Parent.Controls["lblVehiculesEmpty"]
        Refresh-VehiculesGrid -Grid $g -IncludeHistorique $this.Checked -EmptyStateLabel $empty
    })

    # ===== ÉVÉNEMENT AJOUTER =====
    $btnAjouter.Add_Click({
        try {
            Write-Log "[VehiculesUI] Click add vehicle" "INFO"
            $owner = $this.FindForm()
            $nouveau = Show-VehiculeForm -Mode "Ajouter" -Owner $owner
            
            if (-not $nouveau) {
                Write-Log "[VehiculesUI] Add vehicle cancelled (form returned null)" "INFO"
                return
            }

            $newId = Add-VehiculeEntry `
                -NumeroParc $nouveau.numeroParc `
                -Immatriculation $nouveau.immatriculation `
                -NumeroChassis $nouveau.numeroChassis `
                -Marque $nouveau.marque `
                -Modele $nouveau.modele `
                -DateMiseCirculation $nouveau.dateMiseCirculation `
                -DateControle $nouveau.dateControle `
                -DateEntree $nouveau.dateEntree `
                -DateSortie $nouveau.dateSortie `
                -DateFinControleTechnique $nouveau.dateFinControleTechnique
            Write-Log "[VehiculesUI] Vehicle added" "INFO" @{ id = $newId }
            $g = $this.Parent.Controls["VehiculesGrid"]
            $chk = $this.Parent.Controls["chkHistoriqueVehicules"]
            $empty = $this.Parent.Controls["lblVehiculesEmpty"]
            Refresh-VehiculesGrid -Grid $g -IncludeHistorique $chk.Checked -EmptyStateLabel $empty
        } catch {
            Write-Log "[VehiculesUI] Add vehicle failed" "ERROR" @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
            Show-CrudErrorDialog -OperationLabel "l'ajout du véhicule" -ErrorMessage $_.Exception.Message
        }
    })

    # Clic sur icônes Modifier / Supprimer (même logique AgentPanel)
    $grid.Add_CellClick({
        param($sender, $e)

        $row = Test-CellClickGuards -Sender $sender -EventArgs $e
        if (-not $row) { return }

        $id = $row.Tag
        $editCol = $sender.Columns["Edit"].Index
        $delCol = $sender.Columns["Delete"].Index

        if ($e.ColumnIndex -eq $editCol) {
            Invoke-EditVehicule -Id $id -Grid $sender
            return
        }

        if ($e.ColumnIndex -eq $delCol) {
            $confirm = [System.Windows.Forms.MessageBox]::Show("Supprimer ce véhicule ?", "Confirmation", "YesNo")
            if ($confirm -eq "Yes") {
                Remove-VehiculeEntry -Id $id | Out-Null
                $chk = $sender.Parent.Controls["chkHistoriqueVehicules"]
                $empty = $sender.Parent.Controls["lblVehiculesEmpty"]
                Refresh-VehiculesGrid -Grid $sender -IncludeHistorique $chk.Checked -EmptyStateLabel $empty
            }
            return
        }
    })

    # Double-clic sur une ligne : ouvrir VehiculeForm en édition (données complètes depuis la DB)
    $grid.Add_CellDoubleClick({
        param($sender, $e)

        $row = Test-CellClickGuards -Sender $sender -EventArgs $e
        if (-not $row) { return }

        try {
            $editCol = $sender.Columns["Edit"].Index
            $delCol = $sender.Columns["Delete"].Index
            if ($e.ColumnIndex -in @($editCol, $delCol)) { return }
        } catch {}

        try {
            $sender.ClearSelection()
            $row.Selected = $true
        } catch {}

        $id = $row.Tag
        Write-Log "[VehiculesUI] Double-click edit vehicle ID = $id" "INFO"

        try {
            Invoke-EditVehicule -Id $id -Grid $sender
        } catch {
            Write-Log "[VehiculesUI] Double-click edit failed" "ERROR" @{ id = $id; message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
            Show-CrudErrorDialog -OperationLabel "la modification du véhicule" -ErrorMessage $_.Exception.Message
        }
    })

    return $mainPanel
}
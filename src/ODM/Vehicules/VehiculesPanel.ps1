# VehiculesPanel.ps1 - Version refactorisée selon charte AgentPanel
#
# Objet véhicule (données liste / DB, propriétés snake_case côté repository) :
#   id: string|number ; numero_parc ; immatriculation ; numero_chassis ; actif: 0|1 ; …

. "$PSScriptRoot\..\..\Common\Styles.ps1"
. "$PSScriptRoot\..\..\Common\WinFormsHelpers.ps1"
. "$PSScriptRoot\..\..\Core\Logger.ps1"
. "$PSScriptRoot\VehiculesRepository.ps1"
. "$PSScriptRoot\VehiculesForm.ps1"

$script:DebugVehiculesUI = $false

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
            if ($IncludeHistorique) { Get-AllVehicules } else { Get-Vehicules }
        )
        Write-Log "[VehiculesUI] RefreshGrid loaded vehicles" "INFO" @{ count = $vehicules.Count }

        # Style texte: actifs en police normale, inactifs en gris clair
        $baseFont = $script:PoliceNormal
        if (-not $baseFont) { $baseFont = (if ($Grid.DefaultCellStyle.Font) { $Grid.DefaultCellStyle.Font } else { $Grid.Font }) }
        $normalFont = [System.Drawing.Font]::new($baseFont, ([System.Drawing.FontStyle]::Regular))
        $inactiveColor = [System.Drawing.Color]::FromArgb(150, 150, 150)

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

            $isActif = ([int]$v.actif -eq 1)
            $Grid.Rows[$i].DefaultCellStyle.Font = $normalFont
            if (-not $isActif) {
                $Grid.Rows[$i].DefaultCellStyle.ForeColor = $inactiveColor
            } else {
                $Grid.Rows[$i].DefaultCellStyle.ForeColor = $Grid.DefaultCellStyle.ForeColor
            }

            try { Apply-AlternateRowColor -Grid $Grid -RowIndex $i -Row $i } catch {}
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
    param(
        [array]$Vehicules = $null  # Gardé pour compatibilité, mais on utilise Get-Vehicules/Get-AllVehicules
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $mainPanel = [System.Windows.Forms.Panel]::new()
    $mainPanel.Dock = "Fill"
    $mainPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $mainPanel.Padding = [System.Windows.Forms.Padding]::new(20)

    # ===== TITRE =====
    $lblTitle = [System.Windows.Forms.Label]::new()
    $lblTitle.Text = $script:TitrePanelVehicules
    $lblTitle.Font = $script:PoliceTitreGestionFenetre
    $lblTitle.ForeColor = $script:CouleurOrange
    $lblTitle.Location = [System.Drawing.Point]::new(20, 20)
    $lblTitle.Size = [System.Drawing.Size]::new(400, 50)
    $mainPanel.Controls.Add($lblTitle)

    # ===== Option historique (actifs + inactifs) — même ordre que AgentPanel =====
    $lblHistorique = [System.Windows.Forms.Label]::new()
    $lblHistorique.Text = "Afficher l’historique des véhicules"
    $lblHistorique.Font = $script:PoliceLabelSecondaireFenetre
    $lblHistorique.ForeColor = $script:CouleurTexteSecondairePanel
    $lblHistorique.Location = [System.Drawing.Point]::new(20, 77)
    $lblHistorique.Size = [System.Drawing.Size]::new(260, 20)
    $mainPanel.Controls.Add($lblHistorique)

    $chkHistoriqueVehicules = [System.Windows.Forms.CheckBox]::new()
    $chkHistoriqueVehicules.Name = "chkHistoriqueVehicules"
    $chkHistoriqueVehicules.Location = [System.Drawing.Point]::new(285, 78)
    $chkHistoriqueVehicules.Size = [System.Drawing.Size]::new(20, 20)
    $chkHistoriqueVehicules.Checked = $false
    $chkHistoriqueVehicules.Cursor = [System.Windows.Forms.Cursors]::Hand
    $mainPanel.Controls.Add($chkHistoriqueVehicules)

    $btnAjouter = [System.Windows.Forms.Button]::new()
    $btnAjouter.Text = "Ajouter un véhicule"
    $btnAjouter.Location = [System.Drawing.Point]::new(900, 20)
    $btnAjouter.Size = [System.Drawing.Size]::new(200, 45)
    Set-BtnAjouterStyle -BtnAjouter $btnAjouter
    $btnAjouter.Text = "Ajouter un véhicule"
    $btnAjouter.Size = [System.Drawing.Size]::new(220, 45)
    $btnAjouter.Cursor = [System.Windows.Forms.Cursors]::Hand
    $mainPanel.Controls.Add($btnAjouter)

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
            if ($script:DebugVehiculesUI) {
                [System.Windows.Forms.MessageBox]::Show("Click: ouverture du formulaire Véhicule", "Debug", "OK", "Information") | Out-Null
            }
            $owner = $this.FindForm()
            $nouveau = Show-VehiculeForm -Mode "Ajouter" -Owner $owner
            
            if (-not $nouveau) {
                Write-Log "[VehiculesUI] Add vehicle cancelled (form returned null)" "INFO"
                return
            }

            Write-Log "[VehiculesUI] Form data ready" "INFO" @{ ok = $true }
            
            $newId = Add-VehiculeWithValidation `
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
            
            Write-Log "[VehiculesUI] Add-VehiculeWithValidation returned" "INFO" @{ id = $newId }
            
            if ($script:DebugVehiculesUI) {
                [System.Windows.Forms.MessageBox]::Show(("Ajout OK (id={0})" -f $newId), "Véhicules", "OK", "Information") | Out-Null
            }
            
            $g = $this.Parent.Controls["VehiculesGrid"]
            $chk = $this.Parent.Controls["chkHistoriqueVehicules"]
            $empty = $this.Parent.Controls["lblVehiculesEmpty"]
            Refresh-VehiculesGrid -Grid $g -IncludeHistorique $chk.Checked -EmptyStateLabel $empty
        } catch {
            Write-Log "[VehiculesUI] Add vehicle failed" "ERROR" @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
            [System.Windows.Forms.MessageBox]::Show(
                ("Erreur lors de l'ajout du véhicule:`n`n{0}" -f $_.Exception.Message),
                "Erreur",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })

    # Clic sur icônes Modifier / Supprimer (même logique AgentPanel)
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

        $id = $row.Tag
        $editCol = $sender.Columns["Edit"].Index
        $delCol = $sender.Columns["Delete"].Index

        if ($e.ColumnIndex -eq $editCol) {
            $vehiculeComplet = Get-VehiculeById -Id $id
            if (-not $vehiculeComplet) { return }

            $vehiculeData = @{
                id = $vehiculeComplet.id
                numeroParc = $vehiculeComplet.numero_parc
                immatriculation = $vehiculeComplet.immatriculation
                numeroChassis = $vehiculeComplet.numero_chassis
                marque = $vehiculeComplet.marque
                modele = $vehiculeComplet.modele
                dateMiseCirculation = $vehiculeComplet.date_mise_circulation
                dateControle = $vehiculeComplet.date_controle
                dateEntree = $vehiculeComplet.date_entree
                dateSortie = $vehiculeComplet.date_sortie
                dateFinControleTechnique = $vehiculeComplet.date_fin_controle_technique
            }

            $owner = $sender.FindForm()
            $modifie = Show-VehiculeForm -Mode "Modifier" -Vehicule $vehiculeData -Owner $owner
            if ($modifie) {
                Update-Vehicule `
                    -Id $id `
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

                $chk = $sender.Parent.Controls["chkHistoriqueVehicules"]
                $empty = $sender.Parent.Controls["lblVehiculesEmpty"]
                Refresh-VehiculesGrid -Grid $sender -IncludeHistorique $chk.Checked -EmptyStateLabel $empty
            }
            return
        }

        if ($e.ColumnIndex -eq $delCol) {
            $confirm = [System.Windows.Forms.MessageBox]::Show("Supprimer ce véhicule ?", "Confirmation", "YesNo")
            if ($confirm -eq "Yes") {
                Remove-Vehicule -Id $id | Out-Null
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

        if (-not $sender) { return }
        if (-not $e) { return }
        if ($e.RowIndex -lt 0) { return }
        if ($e.ColumnIndex -lt 0) { return }
        if ($e.RowIndex -ge $sender.Rows.Count) { return }

        try {
            $editCol = $sender.Columns["Edit"].Index
            $delCol = $sender.Columns["Delete"].Index
            if ($e.ColumnIndex -in @($editCol, $delCol)) { return }
        } catch {}

        $row = $sender.Rows[$e.RowIndex]
        if (-not $row) { return }
        if ($null -eq $row.Tag) { return }

        try {
            $sender.ClearSelection()
            $row.Selected = $true
        } catch {}

        $id = $row.Tag
        Write-Log "[VehiculesUI] Double-click edit vehicle ID = $id" "INFO"

        try {
            $vehiculeComplet = Get-VehiculeById -Id $id
            if (-not $vehiculeComplet) { return }

            $vehiculeData = @{
                id = $vehiculeComplet.id
                numeroParc = $vehiculeComplet.numero_parc
                immatriculation = $vehiculeComplet.immatriculation
                numeroChassis = $vehiculeComplet.numero_chassis
                marque = $vehiculeComplet.marque
                modele = $vehiculeComplet.modele
                dateMiseCirculation = $vehiculeComplet.date_mise_circulation
                dateControle = $vehiculeComplet.date_controle
                dateEntree = $vehiculeComplet.date_entree
                dateSortie = $vehiculeComplet.date_sortie
                dateFinControleTechnique = $vehiculeComplet.date_fin_controle_technique
            }

            $owner = $sender.FindForm()
            $modifie = Show-VehiculeForm -Mode "Modifier" -Vehicule $vehiculeData -Owner $owner
            
            if ($modifie) {
                Update-Vehicule `
                    -Id $id `
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
                
                $chk = $sender.Parent.Controls["chkHistoriqueVehicules"]
                $empty = $sender.Parent.Controls["lblVehiculesEmpty"]
                Refresh-VehiculesGrid -Grid $sender -IncludeHistorique $chk.Checked -EmptyStateLabel $empty
            }
        } catch {
            Write-Log "[VehiculesUI] Double-click edit failed" "ERROR" @{ id = $id; message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
            [System.Windows.Forms.MessageBox]::Show(
                ("Erreur lors de la modification du véhicule:`n`n{0}" -f $_.Exception.Message),
                "Erreur",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })

    return $mainPanel
}
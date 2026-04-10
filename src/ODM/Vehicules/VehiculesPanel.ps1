# VehiculesPanel.ps1 - Interface de gestion des véhicules

function Show-VehiculesPanel {
    param(
        [array]$Vehicules,
        [ref]$UpdatedVehicules
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $panel.Padding = New-Object System.Windows.Forms.Padding(20)

    Write-Host "[PANEL] ========== VEHICULES PANEL ==========" -ForegroundColor Cyan
    Write-Host "[PANEL] Véhicules reçus: $($Vehicules.Count)" -ForegroundColor Cyan

    # Titre
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "GESTION DES VÉHICULES"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $lblTitle.Location = New-Object System.Drawing.Point(20, 20)
    $lblTitle.Size = New-Object System.Drawing.Size(400, 35)
    $panel.Controls.Add($lblTitle)

    # Bouton AJOUTER
    $btnAjouter = New-Object System.Windows.Forms.Button
    $btnAjouter.Text = "➕ AJOUTER UN VÉHICULE"
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

    # DataGridView
    $global:dgvVehicules = New-Object System.Windows.Forms.DataGridView
    $global:dgvVehicules.Location = New-Object System.Drawing.Point(20, 80)
    $global:dgvVehicules.Size = New-Object System.Drawing.Size(1100, 450)
    $global:dgvVehicules.BackgroundColor = [System.Drawing.Color]::White
    $global:dgvVehicules.AllowUserToAddRows = $false
    $global:dgvVehicules.AllowUserToDeleteRows = $false
    $global:dgvVehicules.RowHeadersVisible = $false
    $global:dgvVehicules.SelectionMode = "FullRowSelect"
    $global:dgvVehicules.BorderStyle = "FixedSingle"
    
    $global:dgvVehicules.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(229, 90, 42)
    $global:dgvVehicules.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White

    # Colonnes
    $global:dgvVehicules.Columns.Add("NumeroParc", "Numéro parc") | Out-Null
    $global:dgvVehicules.Columns.Add("Immatriculation", "Immatriculation") | Out-Null
    $global:dgvVehicules.Columns.Add("NumeroChassis", "Numéro châssis") | Out-Null
    $global:dgvVehicules.Columns.Add("Marque", "Marque") | Out-Null
    $global:dgvVehicules.Columns.Add("Modele", "Modèle") | Out-Null
    $global:dgvVehicules.Columns.Add("DateMiseCirculation", "Mise en circulation") | Out-Null
    $global:dgvVehicules.Columns.Add("DateControle", "Contrôle technique") | Out-Null
    $global:dgvVehicules.Columns.Add("Alerte", "Alerte") | Out-Null
    $global:dgvVehicules.Columns.Add("DateAlerte", "Date alerte") | Out-Null
    $global:dgvVehicules.Columns.Add("Modifier", "Modifier") | Out-Null
    $global:dgvVehicules.Columns.Add("Supprimer", "Supprimer") | Out-Null

    $global:dgvVehicules.Columns[0].Width = 100
    $global:dgvVehicules.Columns[1].Width = 100
    $global:dgvVehicules.Columns[2].Width = 120
    $global:dgvVehicules.Columns[3].Width = 80
    $global:dgvVehicules.Columns[4].Width = 100
    $global:dgvVehicules.Columns[5].Width = 110
    $global:dgvVehicules.Columns[6].Width = 110
    $global:dgvVehicules.Columns[7].Width = 150
    $global:dgvVehicules.Columns[8].Width = 100
    $global:dgvVehicules.Columns[9].Width = 70
    $global:dgvVehicules.Columns[10].Width = 70

    $panel.Controls.Add($global:dgvVehicules)

    # Fonction de refresh globale (tri par numéro de parc croissant)
    $global:RefreshVehiculesGrid = {
        Write-Host "[REFRESH] Rafraîchissement de la grille véhicules..." -ForegroundColor Yellow
        $liste = Get-Vehicules
        $listeTriee = $liste | Sort-Object -Property { [int]$_.numeroParc }
        $global:dgvVehicules.Rows.Clear()
        $i = 0
        foreach ($v in $listeTriee) {
            $row = $global:dgvVehicules.Rows.Add()
            $global:dgvVehicules.Rows[$row].Cells[0].Value = $v.numeroParc
            $global:dgvVehicules.Rows[$row].Cells[1].Value = $v.immatriculation
            $global:dgvVehicules.Rows[$row].Cells[2].Value = $v.numeroChassis
            $global:dgvVehicules.Rows[$row].Cells[3].Value = $v.marque
            $global:dgvVehicules.Rows[$row].Cells[4].Value = $v.modele
            $global:dgvVehicules.Rows[$row].Cells[5].Value = $v.dateMiseCirculation
            $global:dgvVehicules.Rows[$row].Cells[6].Value = $v.dateControle
            $global:dgvVehicules.Rows[$row].Cells[7].Value = $v.alerte
            $global:dgvVehicules.Rows[$row].Cells[8].Value = $v.dateAlerte
            $global:dgvVehicules.Rows[$row].Cells[9].Value = "✏️"
            $global:dgvVehicules.Rows[$row].Cells[10].Value = "🗑️"
            $global:dgvVehicules.Rows[$row].Tag = $v.id
            if ($i % 2 -eq 1) {
                $global:dgvVehicules.Rows[$row].DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(255, 245, 235)
            }
            $i++
        }
        Write-Host "[REFRESH] Terminé - $($liste.Count) véhicules affichés" -ForegroundColor Green
    }

    # Remplissage initial
    & $global:RefreshVehiculesGrid

    # Événement AJOUTER
    $btnAjouter.Add_Click({
        Write-Host "[EVT] ========== AJOUT VEHICULE ==========" -ForegroundColor Cyan
        $nouveau = Show-VehiculeForm -Mode "Ajouter"
        
        if ($nouveau) {
            Write-Host "[EVT] Données reçues" -ForegroundColor Green
            $resultat = Add-Vehicule -NumeroParc $nouveau.numeroParc -Immatriculation $nouveau.immatriculation -NumeroChassis $nouveau.numeroChassis -Marque $nouveau.marque -Modele $nouveau.modele -DateMiseCirculation $nouveau.dateMiseCirculation -DateControle $nouveau.dateControle -Alerte $nouveau.alerte -DateAlerte $nouveau.dateAlerte
            
            if ($resultat) {
                & $global:RefreshVehiculesGrid
                Write-Host "[EVT] Vehicule ajoute avec succes" -ForegroundColor Green
            } else {
                Write-Host "[EVT] Erreur lors de l ajout" -ForegroundColor Red
                [System.Windows.Forms.MessageBox]::Show("Erreur lors de l'ajout du véhicule", "Erreur", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        }
    })

    # Événement MODIFIER/SUPPRIMER
    $global:dgvVehicules.Add_CellClick({
        if ($_.RowIndex -ge 0 -and ($_.ColumnIndex -eq 9 -or $_.ColumnIndex -eq 10)) {
            $row = $global:dgvVehicules.Rows[$_.RowIndex]
            $id = $row.Tag
            
            if ($_.ColumnIndex -eq 9) {
                Write-Host "[EVT] ========== MODIFICATION VEHICULE ==========" -ForegroundColor Yellow
                $vehicule = @{
                    id = $id
                    numeroParc = $row.Cells[0].Value
                    immatriculation = $row.Cells[1].Value
                    numeroChassis = $row.Cells[2].Value
                    marque = $row.Cells[3].Value
                    modele = $row.Cells[4].Value
                    dateMiseCirculation = $row.Cells[5].Value
                    dateControle = $row.Cells[6].Value
                    alerte = $row.Cells[7].Value
                    dateAlerte = $row.Cells[8].Value
                }
                
                $modifie = Show-VehiculeForm -Mode "Modifier" -Vehicule $vehicule
                
                if ($modifie) {
                    $resultat = Update-Vehicule -Id $id -NumeroParc $modifie.numeroParc -Immatriculation $modifie.immatriculation -NumeroChassis $modifie.numeroChassis -Marque $modifie.marque -Modele $modifie.modele -DateMiseCirculation $modifie.dateMiseCirculation -DateControle $modifie.dateControle -Alerte $modifie.alerte -DateAlerte $modifie.dateAlerte
                    
                    if ($resultat) {
                        & $global:RefreshVehiculesGrid
                        Write-Host "[EVT] Vehicule modifie avec succes" -ForegroundColor Green
                    } else {
                        Write-Host "[EVT] Erreur lors de la modification" -ForegroundColor Red
                        [System.Windows.Forms.MessageBox]::Show("Erreur lors de la modification du véhicule", "Erreur", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    }
                }
            } 
            elseif ($_.ColumnIndex -eq 10) {
                Write-Host "[EVT] ========== SUPPRESSION VEHICULE ==========" -ForegroundColor Red
                $immat = $row.Cells[1].Value
                
                $confirm = [System.Windows.Forms.MessageBox]::Show(
                    "Supprimer définitivement le véhicule $immat ?`n`nCette action est irréversible.", 
                    "Confirmation de suppression", 
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                
                if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
                    $resultat = Remove-Vehicule -Id $id
                    if ($resultat) {
                        & $global:RefreshVehiculesGrid
                        Write-Host "[EVT] Vehicule supprime avec succes" -ForegroundColor Green
                    } else {
                        Write-Host "[EVT] Erreur lors de la suppression" -ForegroundColor Red
                        [System.Windows.Forms.MessageBox]::Show("Erreur lors de la suppression du véhicule", "Erreur", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    }
                }
            }
        }
    })

    return $panel
}
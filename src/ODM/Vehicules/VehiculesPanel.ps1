# VehiculesPanel.ps1 - Interface de gestion des véhicules

. "$PSScriptRoot\VehiculesForm.ps1"
. "$PSScriptRoot\VehiculesManager.ps1"

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
    $btnAjouter.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnAjouter.FlatStyle = "Flat"
    $btnAjouter.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $btnAjouter.FlatAppearance.BorderSize = 2
    $btnAjouter.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnAjouter.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnAjouter.Cursor = [System.Windows.Forms.Cursors]::Hand
    
    $btnAjouter.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(229, 90, 42)
        $this.BackColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $btnAjouter.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    $panel.Controls.Add($btnAjouter)

    # DataGridView
    $script:dgv = New-Object System.Windows.Forms.DataGridView
    $script:dgv.Location = New-Object System.Drawing.Point(20, 80)
    $script:dgv.Size = New-Object System.Drawing.Size(1100, 450)
    $script:dgv.BackgroundColor = [System.Drawing.Color]::White
    $script:dgv.AllowUserToAddRows = $false
    $script:dgv.AllowUserToDeleteRows = $false
    $script:dgv.RowHeadersVisible = $false
    $script:dgv.SelectionMode = "FullRowSelect"
    $script:dgv.BorderStyle = "FixedSingle"
    
    # Styles de sélection orange
    $script:dgv.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(229, 90, 42)
    $script:dgv.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::White
    $script:dgv.RowHeadersDefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(229, 90, 42)

    # Colonnes
    $script:dgv.Columns.Add("NumeroParc", "Numéro parc") | Out-Null
    $script:dgv.Columns.Add("Immatriculation", "Immatriculation") | Out-Null
    $script:dgv.Columns.Add("NumeroChassis", "Numéro châssis") | Out-Null
    $script:dgv.Columns.Add("Marque", "Marque") | Out-Null
    $script:dgv.Columns.Add("Modele", "Modèle") | Out-Null
    $script:dgv.Columns.Add("DateMiseCirculation", "Mise en circulation") | Out-Null
    $script:dgv.Columns.Add("DateControle", "Contrôle technique") | Out-Null
    $script:dgv.Columns.Add("Alerte", "Alerte") | Out-Null
    $script:dgv.Columns.Add("DateAlerte", "Date alerte") | Out-Null
    $script:dgv.Columns.Add("Modifier", "Modifier") | Out-Null
    $script:dgv.Columns.Add("Supprimer", "Supprimer") | Out-Null

    $script:dgv.Columns[0].Width = 100
    $script:dgv.Columns[1].Width = 100
    $script:dgv.Columns[2].Width = 120
    $script:dgv.Columns[3].Width = 80
    $script:dgv.Columns[4].Width = 100
    $script:dgv.Columns[5].Width = 110
    $script:dgv.Columns[6].Width = 110
    $script:dgv.Columns[7].Width = 150
    $script:dgv.Columns[8].Width = 100
    $script:dgv.Columns[9].Width = 70
    $script:dgv.Columns[10].Width = 70

    $panel.Controls.Add($script:dgv)

    # Remplissage initial
    $listeTriee = $Vehicules | Sort-Object -Property immatriculation
    $idx = 0
    foreach ($v in $listeTriee) {
        $row = $script:dgv.Rows.Add()
        $script:dgv.Rows[$row].Cells[0].Value = $v.numeroParc
        $script:dgv.Rows[$row].Cells[1].Value = $v.immatriculation
        $script:dgv.Rows[$row].Cells[2].Value = $v.numeroChassis
        $script:dgv.Rows[$row].Cells[3].Value = $v.marque
        $script:dgv.Rows[$row].Cells[4].Value = $v.modele
        $script:dgv.Rows[$row].Cells[5].Value = $v.dateMiseCirculation
        $script:dgv.Rows[$row].Cells[6].Value = $v.dateControle
        $script:dgv.Rows[$row].Cells[7].Value = $v.alerte
        $script:dgv.Rows[$row].Cells[8].Value = $v.dateAlerte
        $script:dgv.Rows[$row].Cells[9].Value = "✏️"
        $script:dgv.Rows[$row].Cells[10].Value = "🗑️"
        $script:dgv.Rows[$row].Tag = $v.id
        if ($idx % 2 -eq 1) {
            $script:dgv.Rows[$row].DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(255, 245, 235)
        }
        $idx++
    }

    # Scriptblock de rafraîchissement
    $script:Refresh = {
        Write-Host "[REFRESH] Rafraîchissement..." -ForegroundColor Yellow
        $liste = Get-Vehicules
        $listeTriee = $liste | Sort-Object -Property immatriculation
        $script:dgv.Rows.Clear()
        $i = 0
        foreach ($v in $listeTriee) {
            $row = $script:dgv.Rows.Add()
            $script:dgv.Rows[$row].Cells[0].Value = $v.numeroParc
            $script:dgv.Rows[$row].Cells[1].Value = $v.immatriculation
            $script:dgv.Rows[$row].Cells[2].Value = $v.numeroChassis
            $script:dgv.Rows[$row].Cells[3].Value = $v.marque
            $script:dgv.Rows[$row].Cells[4].Value = $v.modele
            $script:dgv.Rows[$row].Cells[5].Value = $v.dateMiseCirculation
            $script:dgv.Rows[$row].Cells[6].Value = $v.dateControle
            $script:dgv.Rows[$row].Cells[7].Value = $v.alerte
            $script:dgv.Rows[$row].Cells[8].Value = $v.dateAlerte
            $script:dgv.Rows[$row].Cells[9].Value = "✏️"
            $script:dgv.Rows[$row].Cells[10].Value = "🗑️"
            $script:dgv.Rows[$row].Tag = $v.id
            if ($i % 2 -eq 1) {
                $script:dgv.Rows[$row].DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(255, 245, 235)
            }
            $i++
        }
        Write-Host "[REFRESH] ✅ Terminé" -ForegroundColor Green
    }

    # ========== ÉVÉNEMENT AJOUTER ==========
    $btnAjouter.Add_Click({
        . "$PSScriptRoot\VehiculesForm.ps1"
        . "$PSScriptRoot\VehiculesManager.ps1"
        
        Write-Host "[EVT] ========== AJOUT VÉHICULE ==========" -ForegroundColor Cyan
        $nouveau = Show-VehiculeForm -Mode "Ajouter"
        
        if ($nouveau) {
            Write-Host "[EVT] Données reçues:" -ForegroundColor Green
            Write-Host "[EVT]   - Numéro parc: '$($nouveau.numeroParc)'" -ForegroundColor Gray
            Write-Host "[EVT]   - Immatriculation: '$($nouveau.immatriculation)'" -ForegroundColor Gray
            Write-Host "[EVT]   - Numéro châssis: '$($nouveau.numeroChassis)'" -ForegroundColor Gray
            Write-Host "[EVT]   - Marque: '$($nouveau.marque)'" -ForegroundColor Gray
            Write-Host "[EVT]   - Modèle: '$($nouveau.modele)'" -ForegroundColor Gray
            Write-Host "[EVT]   - Mise circulation: '$($nouveau.dateMiseCirculation)'" -ForegroundColor Gray
            Write-Host "[EVT]   - Contrôle: '$($nouveau.dateControle)'" -ForegroundColor Gray
            Write-Host "[EVT]   - Alerte: '$($nouveau.alerte)'" -ForegroundColor Gray
            Write-Host "[EVT]   - Date alerte: '$($nouveau.dateAlerte)'" -ForegroundColor Gray
            
            $resultat = Add-Vehicule -NumeroParc $nouveau.numeroParc -Immatriculation $nouveau.immatriculation -NumeroChassis $nouveau.numeroChassis -Marque $nouveau.marque -Modele $nouveau.modele -DateMiseCirculation $nouveau.dateMiseCirculation -DateControle $nouveau.dateControle -Alerte $nouveau.alerte -DateAlerte $nouveau.dateAlerte
            
            if ($resultat) {
                & $script:Refresh
                Write-Host "[EVT] ✅ Véhicule ajouté !" -ForegroundColor Green
            } else {
                Write-Host "[EVT] ❌ Erreur ajout" -ForegroundColor Red
            }
        }
    })

    # ========== ÉVÉNEMENT MODIFIER/SUPPRIMER ==========
    $script:dgv.Add_CellClick({
        . "$PSScriptRoot\VehiculesForm.ps1"
        . "$PSScriptRoot\VehiculesManager.ps1"
        
        if ($_.RowIndex -ge 0 -and ($_.ColumnIndex -eq 9 -or $_.ColumnIndex -eq 10)) {
            $row = $script:dgv.Rows[$_.RowIndex]
            $id = $row.Tag
            
            if ($_.ColumnIndex -eq 9) {
                # MODIFIER
                Write-Host "[EVT] ========== MODIFICATION ==========" -ForegroundColor Yellow
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
                
                Write-Host "[EVT] Données actuelles: $($vehicule.immatriculation)" -ForegroundColor Gray
                $modifie = Show-VehiculeForm -Mode "Modifier" -Vehicule $vehicule
                
                if ($modifie) {
                    Write-Host "[EVT] Nouvelles données reçues" -ForegroundColor Green
                    $resultat = Update-Vehicule -Id $id -NumeroParc $modifie.numeroParc -Immatriculation $modifie.immatriculation -NumeroChassis $modifie.numeroChassis -Marque $modifie.marque -Modele $modifie.modele -DateMiseCirculation $modifie.dateMiseCirculation -DateControle $modifie.dateControle -Alerte $modifie.alerte -DateAlerte $modifie.dateAlerte
                    
                    if ($resultat) {
                        & $script:Refresh
                        Write-Host "[EVT] ✅ Véhicule modifié" -ForegroundColor Green
                    }
                }
            } 
            elseif ($_.ColumnIndex -eq 10) {
                # SUPPRIMER
                Write-Host "[EVT] ========== SUPPRESSION ==========" -ForegroundColor Red
                $immat = $row.Cells[1].Value
                Write-Host "[EVT] Véhicule: $immat" -ForegroundColor Yellow
                
                $confirm = [System.Windows.Forms.MessageBox]::Show(
                    "Supprimer définitivement le véhicule $immat ?`n`nCette action est irréversible.", 
                    "Confirmation de suppression", 
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                
                if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
                    $resultat = Remove-Vehicule -Id $id
                    if ($resultat) {
                        & $script:Refresh
                        Write-Host "[EVT] ✅ Véhicule supprimé" -ForegroundColor Green
                    }
                }
            }
        }
    })

    return $panel
}



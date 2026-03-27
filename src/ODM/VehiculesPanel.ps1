# VehiculesPanel.ps1 - Onglet Données véhicules

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
    
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "GESTION DES VÉHICULES"
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $lbl.Location = New-Object System.Drawing.Point(20, 20)
    $lbl.Size = New-Object System.Drawing.Size(400, 35)
    $panel.Controls.Add($lbl)
    
    $dgv = New-Object System.Windows.Forms.DataGridView
    $dgv.Location = New-Object System.Drawing.Point(20, 70)
    $dgv.Size = New-Object System.Drawing.Size(800, 300)
    $dgv.AllowUserToAddRows = $true
    $dgv.Columns.Add("Immatriculation", "Immatriculation") | Out-Null
    $dgv.Columns.Add("Marque", "Marque") | Out-Null
    $dgv.Columns.Add("Modele", "Modèle") | Out-Null
    $dgv.Columns.Add("Annee", "Année") | Out-Null
    $dgv.Columns[0].Width = 150
    $dgv.Columns[1].Width = 120
    $dgv.Columns[2].Width = 150
    $dgv.Columns[3].Width = 80
    
    foreach ($v in $Vehicules) {
        $dgv.Rows.Add($v.immatriculation, $v.marque, $v.modele, $v.annee)
    }
    $panel.Controls.Add($dgv)
    
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "SAUVEGARDER"
    $btnSave.Size = New-Object System.Drawing.Size(150, 40)
    $btnSave.Location = New-Object System.Drawing.Point(20, 390)
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $btnSave.ForeColor = [System.Drawing.Color]::White
    $btnSave.FlatStyle = "Flat"
    $btnSave.Add_Click({
        $nouveaux = @()
        $id = 1
        foreach ($row in $dgv.Rows) {
            if (-not $row.IsNewRow) {
                $immat = $row.Cells[0].Value
                $marque = $row.Cells[1].Value
                $modele = $row.Cells[2].Value
                $annee = $row.Cells[3].Value
                if ($immat -and $marque -and $modele) {
                    $nouveaux += @{
                        id = $id
                        immatriculation = $immat
                        marque = $marque
                        modele = $modele
                        annee = $annee
                    }
                    $id++
                }
            }
        }
        $UpdatedVehicules.Value = $nouveaux
        [System.Windows.Forms.MessageBox]::Show("Véhicules sauvegardés !", "Succès")
    })
    $panel.Controls.Add($btnSave)
    
    return $panel
}

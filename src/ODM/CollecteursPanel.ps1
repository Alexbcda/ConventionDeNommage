# CollecteursPanel.ps1 - Onglet Données collecteurs

function Show-CollecteursPanel {
    param(
        [array]$Collecteurs,
        [ref]$UpdatedCollecteurs
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $panel.Padding = New-Object System.Windows.Forms.Padding(20)
    
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "GESTION DES COLLECTEURS"
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $lbl.Location = New-Object System.Drawing.Point(20, 20)
    $lbl.Size = New-Object System.Drawing.Size(400, 35)
    $panel.Controls.Add($lbl)
    
    $dgv = New-Object System.Windows.Forms.DataGridView
    $dgv.Location = New-Object System.Drawing.Point(20, 70)
    $dgv.Size = New-Object System.Drawing.Size(800, 300)
    $dgv.AllowUserToAddRows = $true
    $dgv.Columns.Add("Nom", "Nom") | Out-Null
    $dgv.Columns.Add("Prenom", "Prénom") | Out-Null
    $dgv.Columns.Add("Telephone", "Téléphone") | Out-Null
    $dgv.Columns[0].Width = 150
    $dgv.Columns[1].Width = 150
    $dgv.Columns[2].Width = 150
    
    foreach ($c in $Collecteurs) {
        $dgv.Rows.Add($c.nom, $c.prenom, $c.telephone)
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
                $nom = $row.Cells[0].Value
                $prenom = $row.Cells[1].Value
                $telephone = $row.Cells[2].Value
                if ($nom -and $prenom) {
                    $nouveaux += @{
                        id = $id
                        nom = $nom
                        prenom = $prenom
                        telephone = $telephone
                    }
                    $id++
                }
            }
        }
        $UpdatedCollecteurs.Value = $nouveaux
        [System.Windows.Forms.MessageBox]::Show("Collecteurs sauvegardés !", "Succès")
    })
    $panel.Controls.Add($btnSave)
    
    return $panel
}

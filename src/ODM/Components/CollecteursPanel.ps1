# CollecteursPanel.ps1 - Gestion simple des collecteurs

function Show-CollecteursPanel {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Collecteurs,
        [ref]$UpdatedCollecteurs
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.Padding = New-Object System.Windows.Forms.Padding(20)
    
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "????? GESTION DES COLLECTEURS"
    $lblTitle.Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)
    $lblTitle.Location = New-Object System.Drawing.Point(20, 20)
    $lblTitle.Size = New-Object System.Drawing.Size(400, 30)
    $panel.Controls.Add($lblTitle)
    
    $dgv = New-Object System.Windows.Forms.DataGridView
    $dgv.Location = New-Object System.Drawing.Point(20, 60)
    $dgv.Size = New-Object System.Drawing.Size(800, 300)
    $dgv.BackgroundColor = [System.Drawing.Color]::White
    $dgv.AllowUserToAddRows = $true
    $dgv.AllowUserToDeleteRows = $true
    
    $dgv.Columns.Add("Nom", "Nom") | Out-Null
    $dgv.Columns.Add("Prenom", "Pr?nom") | Out-Null
    $dgv.Columns.Add("Telephone", "T?l?phone") | Out-Null
    
    $dgv.Columns[0].Width = 150
    $dgv.Columns[1].Width = 150
    $dgv.Columns[2].Width = 150
    
    foreach ($c in $Collecteurs) {
        $dgv.Rows.Add($c.nom, $c.prenom, $c.telephone)
    }
    
    $panel.Controls.Add($dgv)
    
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "?? SAUVEGARDER"
    $btnSave.Size = New-Object System.Drawing.Size(150, 40)
    $btnSave.Location = New-Object System.Drawing.Point(20, 380)
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(27, 91, 74)
    $btnSave.ForeColor = [System.Drawing.Color]::White
    $btnSave.FlatStyle = "Flat"
    $panel.Controls.Add($btnSave)
    
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
        [System.Windows.Forms.MessageBox]::Show("Collecteurs sauvegard?s !", "Succ?s")
    })
    
    return $panel
}

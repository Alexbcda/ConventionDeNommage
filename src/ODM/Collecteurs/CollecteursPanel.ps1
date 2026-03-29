. "$PSScriptRoot\CollecteursForm.ps1"
. "$PSScriptRoot\CollecteursManager.ps1"

function Show-CollecteursPanel {
    param($Collecteurs, $UpdatedCollecteurs)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $panel.Padding = New-Object System.Windows.Forms.Padding(20)

    # Titre
    $title = New-Object System.Windows.Forms.Label
    $title.Text = "GESTION DES COLLECTEURS"
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $title.Location = New-Object System.Drawing.Point(20, 20)
    $title.Size = New-Object System.Drawing.Size(400, 35)
    $panel.Controls.Add($title)

    # Bouton Ajouter
    $btnAdd = New-Object System.Windows.Forms.Button
    $btnAdd.Text = "AJOUTER"
    $btnAdd.Size = New-Object System.Drawing.Size(150, 40)
    $btnAdd.Location = New-Object System.Drawing.Point(900, 20)
    $panel.Controls.Add($btnAdd)

    # Grille en script scope pour y accéder partout
    $script:grid = New-Object System.Windows.Forms.DataGridView
    $script:grid.Location = New-Object System.Drawing.Point(20, 80)
    $script:grid.Size = New-Object System.Drawing.Size(1000, 450)
    $script:grid.AllowUserToAddRows = $false
    $script:grid.RowHeadersVisible = $false
    $script:grid.SelectionMode = "FullRowSelect"

    $script:grid.Columns.Add("ID", "ID") | Out-Null
    $script:grid.Columns.Add("Nom", "Nom") | Out-Null
    $script:grid.Columns.Add("Prenom", "Prenom") | Out-Null
    $script:grid.Columns.Add("Tel", "Telephone") | Out-Null
    $script:grid.Columns.Add("Email", "Email") | Out-Null
    $script:grid.Columns.Add("Edit", "") | Out-Null
    $script:grid.Columns.Add("Delete", "") | Out-Null

    $script:grid.Columns[0].Width = 50
    $script:grid.Columns[1].Width = 150
    $script:grid.Columns[2].Width = 150
    $script:grid.Columns[3].Width = 120
    $script:grid.Columns[4].Width = 200
    $script:grid.Columns[5].Width = 50
    $script:grid.Columns[6].Width = 50

    $panel.Controls.Add($script:grid)

    # Fonction de chargement
    $script:LoadData = {
        Write-Host "[LOAD] Chargement des données..." -ForegroundColor Cyan
        $script:grid.Rows.Clear()
        $data = Get-Collecteurs
        foreach ($item in $data) {
            $row = $script:grid.Rows.Add()
            $script:grid.Rows[$row].Cells[0].Value = $item.id
            $script:grid.Rows[$row].Cells[1].Value = $item.nom
            $script:grid.Rows[$row].Cells[2].Value = $item.prenom
            $script:grid.Rows[$row].Cells[3].Value = $item.telephone
            $script:grid.Rows[$row].Cells[4].Value = $item.email
            $script:grid.Rows[$row].Cells[5].Value = "✏️"
            $script:grid.Rows[$row].Cells[6].Value = "🗑️"
        }
        Write-Host "[LOAD] $($data.Count) collecteurs chargés" -ForegroundColor Green
    }

    # Chargement initial
    & $script:LoadData

    # Bouton Ajouter
    $btnAdd.Add_Click({
        $new = Show-CollecteurForm -Mode "Ajouter"
        if ($new) {
            Add-Collecteur -Nom $new.nom -Prenom $new.prenom -Telephone $new.telephone -Email $new.email
            & $script:LoadData
        }
    })

    # Clic sur cellule
    $script:grid.Add_CellClick({
        if ($_.RowIndex -ge 0) {
            $row = $script:grid.Rows[$_.RowIndex]
            $id = $row.Cells[0].Value
            
            if ($_.ColumnIndex -eq 5) {
                $data = @{
                    id = $id
                    nom = $row.Cells[1].Value
                    prenom = $row.Cells[2].Value
                    telephone = $row.Cells[3].Value
                    email = $row.Cells[4].Value
                }
                $modified = Show-CollecteurForm -Mode "Modifier" -Collecteur $data
                if ($modified) {
                    Update-Collecteur -Id $id -Nom $modified.nom -Prenom $modified.prenom -Telephone $modified.telephone -Email $modified.email
                    & $script:LoadData
                }
            }
            elseif ($_.ColumnIndex -eq 6) {
                $confirm = [System.Windows.Forms.MessageBox]::Show("Supprimer ?", "Confirmation", [System.Windows.Forms.MessageBoxButtons]::YesNo)
                if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Remove-Collecteur -Id $id
                    & $script:LoadData
                }
            }
        }
    })

    return $panel
}

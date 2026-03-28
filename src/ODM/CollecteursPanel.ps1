# CollecteursPanel.ps1

. "C:\Users\alexa\Documents\ConventionDeNommage\src\ODM\Collecteurs\CollecteursForm.ps1"
. "C:\Users\alexa\Documents\ConventionDeNommage\src\ODM\Collecteurs\CollecteursManager.ps1"

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

    Write-Host "[PANEL] Démarrage" -ForegroundColor Cyan

    # Titre
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "GESTION DES COLLECTEURS"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $lblTitle.Location = New-Object System.Drawing.Point(20, 20)
    $lblTitle.Size = New-Object System.Drawing.Size(400, 35)
    $panel.Controls.Add($lblTitle)

    # Bouton AJOUTER
    $btnAjouter = New-Object System.Windows.Forms.Button
    $btnAjouter.Text = "➕ AJOUTER UN COLLECTEUR"
    $btnAjouter.Size = New-Object System.Drawing.Size(200, 45)
    $btnAjouter.Location = New-Object System.Drawing.Point(900, 20)
    $btnAjouter.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnAjouter.FlatStyle = "Flat"
    $btnAjouter.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $btnAjouter.FlatAppearance.BorderSize = 2
    $btnAjouter.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnAjouter.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnAjouter.Cursor = [System.Windows.Forms.Cursors]::Hand
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

    # Colonnes
    $script:dgv.Columns.Add("Nom", "Nom") | Out-Null
    $script:dgv.Columns.Add("Prenom", "Prénom") | Out-Null
    $script:dgv.Columns.Add("Telephone", "Téléphone") | Out-Null
    $script:dgv.Columns.Add("Email", "Email") | Out-Null
    $script:dgv.Columns.Add("VehiculeDefaut", "Véhicule") | Out-Null
    $script:dgv.Columns.Add("Modifier", "Modifier") | Out-Null
    $script:dgv.Columns.Add("Supprimer", "Supprimer") | Out-Null

    $script:dgv.Columns[0].Width = 120
    $script:dgv.Columns[1].Width = 120
    $script:dgv.Columns[2].Width = 150
    $script:dgv.Columns[3].Width = 200
    $script:dgv.Columns[4].Width = 150
    $script:dgv.Columns[5].Width = 80
    $script:dgv.Columns[6].Width = 80

    $panel.Controls.Add($script:dgv)

    # Remplissage initial
    $listeTriee = $Collecteurs | Sort-Object -Property nom
    $idx = 0
    foreach ($c in $listeTriee) {
        $row = $script:dgv.Rows.Add()
        $script:dgv.Rows[$row].Cells[0].Value = $c.nom
        $script:dgv.Rows[$row].Cells[1].Value = $c.prenom
        $script:dgv.Rows[$row].Cells[2].Value = $c.telephone
        $script:dgv.Rows[$row].Cells[3].Value = $c.email
        $script:dgv.Rows[$row].Cells[4].Value = $c.vehiculeDefaut
        $script:dgv.Rows[$row].Cells[5].Value = "✏️"
        $script:dgv.Rows[$row].Cells[6].Value = "🗑️"
        $script:dgv.Rows[$row].Tag = $c.id
        if ($idx % 2 -eq 1) {
            $script:dgv.Rows[$row].DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(255, 245, 235)
        }
        $idx++
    }

    # Scriptblock de rafraîchissement
    $script:Refresh = {
        Write-Host "[REFRESH] Début" -ForegroundColor Yellow
        $liste = Get-Collecteurs
        Write-Host "[REFRESH] $($liste.Count) collecteurs trouvés" -ForegroundColor Green
        
        $listeTriee = $liste | Sort-Object -Property nom
        $script:dgv.Rows.Clear()
        $i = 0
        foreach ($c in $listeTriee) {
            $row = $script:dgv.Rows.Add()
            $script:dgv.Rows[$row].Cells[0].Value = $c.nom
            $script:dgv.Rows[$row].Cells[1].Value = $c.prenom
            $script:dgv.Rows[$row].Cells[2].Value = $c.telephone
            $script:dgv.Rows[$row].Cells[3].Value = $c.email
            $script:dgv.Rows[$row].Cells[4].Value = $c.vehiculeDefaut
            $script:dgv.Rows[$row].Cells[5].Value = "✏️"
            $script:dgv.Rows[$row].Cells[6].Value = "🗑️"
            $script:dgv.Rows[$row].Tag = $c.id
            if ($i % 2 -eq 1) {
                $script:dgv.Rows[$row].DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(255, 245, 235)
            }
            $i++
        }
        Write-Host "[REFRESH] Terminé - $($listeTriee.Count) collecteurs affichés" -ForegroundColor Green
    }

    # Événement AJOUTER
    $btnAjouter.Add_Click({
        . "C:\Users\alexa\Documents\ConventionDeNommage\src\ODM\Collecteurs\CollecteursForm.ps1"
        . "C:\Users\alexa\Documents\ConventionDeNommage\src\ODM\Collecteurs\CollecteursManager.ps1"
        
        Write-Host "[EVT] AJOUT" -ForegroundColor Cyan
        $nouveau = Show-CollecteurForm -Mode "Ajouter"
        if ($nouveau) {
            Write-Host "[EVT] $($nouveau.prenom) $($nouveau.nom)" -ForegroundColor Green
            Add-Collecteur -Prenom $nouveau.prenom -Nom $nouveau.nom -Telephone $nouveau.telephone -Email $nouveau.email -VehiculeDefaut $nouveau.vehiculeDefaut
            & $script:Refresh
            Write-Host "[EVT] ✅ Ajouté" -ForegroundColor Green
        }
    })

    # Événement MODIFIER/SUPPRIMER
    $script:dgv.Add_CellClick({
        . "C:\Users\alexa\Documents\ConventionDeNommage\src\ODM\Collecteurs\CollecteursForm.ps1"
        . "C:\Users\alexa\Documents\ConventionDeNommage\src\ODM\Collecteurs\CollecteursManager.ps1"
        
        if ($_.RowIndex -ge 0 -and ($_.ColumnIndex -eq 5 -or $_.ColumnIndex -eq 6)) {
            $row = $script:dgv.Rows[$_.RowIndex]
            $id = $row.Tag
            $nom = $row.Cells[0].Value
            $prenom = $row.Cells[1].Value
            
            if ($_.ColumnIndex -eq 5) {
                Write-Host "[EVT] MODIFIER: $nom $prenom" -ForegroundColor Yellow
                $collecteur = @{
                    id = $id
                    nom = $nom
                    prenom = $prenom
                    telephone = $row.Cells[2].Value
                    email = $row.Cells[3].Value
                    vehiculeDefaut = $row.Cells[4].Value
                }
                $modifie = Show-CollecteurForm -Mode "Modifier" -Collecteur $collecteur
                if ($modifie) {
                    Update-Collecteur -Id $id -Prenom $modifie.prenom -Nom $modifie.nom -Telephone $modifie.telephone -Email $modifie.email -VehiculeDefaut $modifie.vehiculeDefaut
                    & $script:Refresh
                    Write-Host "[EVT] ✅ Modifié" -ForegroundColor Green
                }
            } 
            elseif ($_.ColumnIndex -eq 6) {
                Write-Host "[EVT] SUPPRIMER: $nom $prenom" -ForegroundColor Red
                $confirm = [System.Windows.Forms.MessageBox]::Show("Supprimer $nom $prenom ?", "Confirmation", [System.Windows.Forms.MessageBoxButtons]::YesNo)
                if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Remove-Collecteur -Id $id
                    & $script:Refresh
                    Write-Host "[EVT] ✅ Supprimé" -ForegroundColor Green
                }
            }
        }
    })

    Write-Host "[PANEL] Terminé" -ForegroundColor Cyan
    return $panel
}

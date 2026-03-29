Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Simuler Get-Collecteurs avec des données
function Get-Collecteurs {
    return @(
        @{ id = 1; nom = "DUPONT"; prenom = "Jean"; telephone = "0601020304"; email = "jean@email.com"; vehiculeDefaut = "" },
        @{ id = 2; nom = "MARTIN"; prenom = "Pierre"; telephone = "0605060708"; email = "pierre@email.com"; vehiculeDefaut = "" },
        @{ id = 3; nom = "BERNARD"; prenom = "Philippe"; telephone = "0610111213"; email = "philippe@email.com"; vehiculeDefaut = "" }
    )
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "TEST COLLECTEURS - Rafraîchissement"
$form.Size = New-Object System.Drawing.Size(800, 600)
$form.StartPosition = "CenterScreen"

$panel = New-Object System.Windows.Forms.Panel
$panel.Dock = "Fill"

$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Text = "AJOUTER UN COLLECTEUR"
$btnAdd.Size = New-Object System.Drawing.Size(200, 40)
$btnAdd.Location = New-Object System.Drawing.Point(20, 20)

$dgv = New-Object System.Windows.Forms.DataGridView
$dgv.Location = New-Object System.Drawing.Point(20, 80)
$dgv.Size = New-Object System.Drawing.Size(700, 400)
$dgv.Columns.Add("Nom", "Nom")
$dgv.Columns.Add("Prenom", "Prénom")
$dgv.Columns.Add("Telephone", "Téléphone")
$dgv.Columns.Add("Email", "Email")

$counter = 3

function Refresh-DataGrid {
    Write-Host "[REFRESH] Début refresh..." -ForegroundColor Yellow
    $liste = Get-Collecteurs
    Write-Host "[REFRESH] $($liste.Count) collecteurs dans la liste" -ForegroundColor Cyan
    
    $dgv.Rows.Clear()
    foreach ($c in $liste) {
        $row = $dgv.Rows.Add()
        $dgv.Rows[$row].Cells[0].Value = $c.nom
        $dgv.Rows[$row].Cells[1].Value = $c.prenom
        $dgv.Rows[$row].Cells[2].Value = $c.telephone
        $dgv.Rows[$row].Cells[3].Value = $c.email
    }
    Write-Host "[REFRESH] Terminé - $($dgv.Rows.Count) lignes affichées" -ForegroundColor Green
}

$btnAdd.Add_Click({
    $global:counter++
    Write-Host "[ADD] Ajout du collecteur $counter" -ForegroundColor Cyan
    
    # Ajouter un nouveau collecteur à la liste
    $newCollecteur = @{
        id = $counter
        nom = "NOUVEAU$counter"
        prenom = "Test$counter"
        telephone = "060000000$counter"
        email = "test$counter@email.com"
        vehiculeDefaut = ""
    }
    
    # Simuler l'ajout dans la liste globale
    $script:collecteursList = Get-Collecteurs
    $script:collecteursList += $newCollecteur
    
    # Redéfinir Get-Collecteurs pour retourner la liste mise à jour
    function Get-Collecteurs { return $script:collecteursList }
    
    Refresh-DataGrid
})

# Remplissage initial
Refresh-DataGrid

$panel.Controls.Add($btnAdd)
$panel.Controls.Add($dgv)
$form.Controls.Add($panel)

Write-Host "[INFO] Formulaire chargé - cliquez sur AJOUTER pour tester" -ForegroundColor Green
$form.ShowDialog()

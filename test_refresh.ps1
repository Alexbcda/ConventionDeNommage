Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "TEST REFRESH"
$form.Size = New-Object System.Drawing.Size(800, 600)
$form.StartPosition = "CenterScreen"

$panel = New-Object System.Windows.Forms.Panel
$panel.Dock = "Fill"

$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Text = "AJOUTER"
$btnAdd.Size = New-Object System.Drawing.Size(150, 40)
$btnAdd.Location = New-Object System.Drawing.Point(20, 20)

$dgv = New-Object System.Windows.Forms.DataGridView
$dgv.Location = New-Object System.Drawing.Point(20, 80)
$dgv.Size = New-Object System.Drawing.Size(700, 400)
$dgv.Columns.Add("Nom", "Nom")
$dgv.Columns.Add("Prenom", "Prénom")

$counter = 0

function Refresh-DataGrid {
    Write-Host "[REFRESH] Début refresh" -ForegroundColor Yellow
    # Simuler la récupération des données (ici juste des données factices)
    $dgv.Rows.Clear()
    for ($i = 1; $i -le $counter; $i++) {
        $row = $dgv.Rows.Add()
        $dgv.Rows[$row].Cells[0].Value = "Nom$i"
        $dgv.Rows[$row].Cells[1].Value = "Prenom$i"
    }
    Write-Host "[REFRESH] Fini - $($dgv.Rows.Count) lignes" -ForegroundColor Green
}

$btnAdd.Add_Click({
    $counter++
    Write-Host "[ADD] Ajout numéro $counter" -ForegroundColor Cyan
    Refresh-DataGrid
})

$panel.Controls.Add($btnAdd)
$panel.Controls.Add($dgv)
$form.Controls.Add($panel)

$form.ShowDialog()

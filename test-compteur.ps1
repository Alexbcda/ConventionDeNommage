# test-compteur.ps1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "Test Compteur"
$form.Size = New-Object System.Drawing.Size(400, 300)

$lblCount = New-Object System.Windows.Forms.Label
$lblCount.Text = "Compteur: 0"
$lblCount.Font = New-Object System.Drawing.Font("Arial", 14)
$lblCount.Location = New-Object System.Drawing.Point(50, 30)
$lblCount.Size = New-Object System.Drawing.Size(200, 30)
$form.Controls.Add($lblCount)

$btnPlus = New-Object System.Windows.Forms.Button
$btnPlus.Text = "+"
$btnPlus.Location = New-Object System.Drawing.Point(50, 80)
$btnPlus.Size = New-Object System.Drawing.Size(80, 50)
$btnPlus.Font = New-Object System.Drawing.Font("Arial", 18)
$form.Controls.Add($btnPlus)

$btnMinus = New-Object System.Windows.Forms.Button
$btnMinus.Text = "-"
$btnMinus.Location = New-Object System.Drawing.Point(150, 80)
$btnMinus.Size = New-Object System.Drawing.Size(80, 50)
$btnMinus.Font = New-Object System.Drawing.Font("Arial", 18)
$form.Controls.Add($btnMinus)

$counter = 0

$btnPlus.Add_Click({
    $counter++
    $lblCount.Text = "Compteur: $counter"
    Write-Host "Plus: $counter"
})

$btnMinus.Add_Click({
    if ($counter -gt 0) {
        $counter--
        $lblCount.Text = "Compteur: $counter"
        Write-Host "Moins: $counter"
    }
})

$form.ShowDialog()

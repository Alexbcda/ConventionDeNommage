Add-Type -AssemblyName System.Windows.Forms

$form = New-Object System.Windows.Forms.Form
$form.Text = "TEST BOUTON AVEC GetNewClosure()"
$form.Size = New-Object System.Drawing.Size(400, 300)

$btn = New-Object System.Windows.Forms.Button
$btn.Text = "CLIQUEZ-MOI"
$btn.Size = New-Object System.Drawing.Size(200, 50)
$btn.Location = New-Object System.Drawing.Point(100, 100)

$label = New-Object System.Windows.Forms.Label
$label.Text = "Clics: 0"
$label.Location = New-Object System.Drawing.Point(150, 200)
$label.Size = New-Object System.Drawing.Size(100, 30)

$count = 0
$btn.Add_Click({
    $count++
    $label.Text = "Clics: $count"
    Write-Host "Clic numéro $count" -ForegroundColor Green
}.GetNewClosure())

$form.Controls.Add($btn)
$form.Controls.Add($label)
$form.ShowDialog()

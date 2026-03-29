Add-Type -AssemblyName System.Windows.Forms

$form = New-Object System.Windows.Forms.Form
$form.Text = "TEST ULTRA SIMPLE"
$form.Size = New-Object System.Drawing.Size(400, 300)

$btn = New-Object System.Windows.Forms.Button
$btn.Text = "CLIQUEZ"
$btn.Location = New-Object System.Drawing.Point(150, 100)
$btn.Size = New-Object System.Drawing.Size(100, 50)

$label = New-Object System.Windows.Forms.Label
$label.Text = "0"
$label.Location = New-Object System.Drawing.Point(180, 200)
$label.Size = New-Object System.Drawing.Size(40, 30)
$label.Font = New-Object System.Drawing.Font("Arial", 14)

$count = 0

$btn.Add_Click({
    $count = $count + 1
    $label.Text = $count.ToString()
    Write-Host "Clic: $count"
})

$form.Controls.Add($btn)
$form.Controls.Add($label)
$form.ShowDialog()

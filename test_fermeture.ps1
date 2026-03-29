Add-Type -AssemblyName System.Windows.Forms

function Show-MonFormulaire {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "TEST - Cliquez plusieurs fois"
    $form.Size = New-Object System.Drawing.Size(400, 300)
    $form.StartPosition = "CenterScreen"

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
        $count++
        $label.Text = $count.ToString()
        Write-Host "Clic: $count"
    })

    $form.Controls.Add($btn)
    $form.Controls.Add($label)
    $form.ShowDialog()
}

Show-MonFormulaire

# DatePanel.ps1 - Panneau de sélection de date
function Show-DatePanel {
    param($NextPanel, $CurrentPanel)
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $panel.Padding = New-Object System.Windows.Forms.Padding(50)
    
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Sélectionnez la date"
    $lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $lblTitle.Location = New-Object System.Drawing.Point(0, 0)
    $lblTitle.Size = New-Object System.Drawing.Size(400, 50)
    $panel.Controls.Add($lblTitle)
    
    $datePicker = New-Object System.Windows.Forms.DateTimePicker
    $datePicker.Location = New-Object System.Drawing.Point(0, 70)
    $datePicker.Size = New-Object System.Drawing.Size(200, 30)
    $datePicker.Value = Get-CNDateParDefaut
    $panel.Controls.Add($datePicker)
    
    $btnValider = New-Object System.Windows.Forms.Button
    $btnValider.Text = "VALIDER"
    $btnValider.Location = New-Object System.Drawing.Point(0, 120)
    $btnValider.Size = New-Object System.Drawing.Size(100, 40)
    $btnValider.BackColor = [System.Drawing.Color]::FromArgb(175, 71, 11)
    $btnValider.ForeColor = [System.Drawing.Color]::White
    $btnValider.FlatStyle = "Flat"
    $btnValider.Add_Click({
        Set-CNDate -Date $datePicker.Value
        if ($NextPanel) { $NextPanel.Visible = $true }
        if ($CurrentPanel) { $CurrentPanel.Visible = $false }
    })
    $panel.Controls.Add($btnValider)
    
    return $panel
}




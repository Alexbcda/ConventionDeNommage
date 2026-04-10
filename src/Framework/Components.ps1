Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function New-Button {
    param([string]$Text,[int]$X,[int]$Y,[ScriptBlock]$OnClick,[string]$Type="primary",[int]$Width=120,[int]$Height=40)
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.Size = New-Object System.Drawing.Size($Width, $Height)
    $btn.FlatStyle = "Flat"
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    switch ($Type) {
        "primary" {
            $btn.BackColor = $script:CouleurOrange
            $btn.ForeColor = $script:CouleurBlanc
            $btn.FlatAppearance.BorderSize = 0
        }
        "secondary" {
            $btn.BackColor = $script:CouleurBlanc
            $btn.ForeColor = $script:CouleurGrisFonce
            $btn.FlatAppearance.BorderColor = $script:CouleurOrange
            $btn.FlatAppearance.BorderSize = 2
        }
    }
    $btn.Add_Click($OnClick)
    return $btn
}

function Show-Modal {
    param([string]$Title,[string]$Message,[string]$Type="info")
    $icon = switch ($Type) {
        "error" { [System.Windows.Forms.MessageBoxIcon]::Error }
        "warning" { [System.Windows.Forms.MessageBoxIcon]::Warning }
        default { [System.Windows.Forms.MessageBoxIcon]::Information }
    }
    return [System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $icon)
}

function Show-Confirm {
    param([string]$Message,[string]$Title="Confirmation")
    $result = [System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
}

Write-Host "[COMPONENTS] Charge" -ForegroundColor Green

# test-odm-simple.ps1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Fonction simple qui retourne un panel
function Get-TestPanel {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.BackColor = [System.Drawing.Color]::LightBlue
    $panel.Dock = "Fill"
    
    $label = New-Object System.Windows.Forms.Label
    $label.Text = "TEST - Interface ODM"
    $label.Font = New-Object System.Drawing.Font("Arial", 20)
    $label.ForeColor = [System.Drawing.Color]::White
    $label.Dock = "Fill"
    $label.TextAlign = "MiddleCenter"
    $panel.Controls.Add($label)
    
    return $panel
}

# Créer une fenêtre
$form = New-Object System.Windows.Forms.Form
$form.Text = "Test ODM"
$form.Size = New-Object System.Drawing.Size(800, 600)

$testPanel = Get-TestPanel
$form.Controls.Add($testPanel)

$form.ShowDialog()

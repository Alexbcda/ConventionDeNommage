# test-panel-simple.ps1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-SimplePanel {
    $p = New-Object System.Windows.Forms.Panel
    $p.BackColor = [System.Drawing.Color]::Red
    $p.Dock = "Fill"
    
    $l = New-Object System.Windows.Forms.Label
    $l.Text = "TEST - Ceci est un panel simple"
    $l.ForeColor = [System.Drawing.Color]::White
    $l.Font = New-Object System.Drawing.Font("Arial", 14)
    $l.Dock = "Fill"
    $l.TextAlign = "MiddleCenter"
    $p.Controls.Add($l)
    
    return $p
}

# Créer une fenêtre
$form = New-Object System.Windows.Forms.Form
$form.Text = "Test Panel Simple"
$form.Size = New-Object System.Drawing.Size(600, 400)

$panel = Get-SimplePanel
$form.Controls.Add($panel)

Write-Host "Type du panel: $($panel.GetType())" -ForegroundColor Cyan
Write-Host "Est-ce un Panel? $($panel -is [System.Windows.Forms.Panel])" -ForegroundColor Cyan

$form.ShowDialog()

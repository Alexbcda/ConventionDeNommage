# test-gui-context.ps1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Fonction simple qui retourne un panel
function Get-MonPanel {
    $p = New-Object System.Windows.Forms.Panel
    $p.BackColor = [System.Drawing.Color]::FromArgb(27, 91, 74)
    $p.Dock = "Fill"
    
    $l = New-Object System.Windows.Forms.Label
    $l.Text = "PLANNING ODM - Version test"
    $l.Font = New-Object System.Drawing.Font("Arial", 16, [System.Drawing.FontStyle]::Bold)
    $l.ForeColor = [System.Drawing.Color]::White
    $l.TextAlign = "MiddleCenter"
    $l.Dock = "Fill"
    $p.Controls.Add($l)
    
    return $p
}

# Créer une fenêtre avec un TabControl (comme dans GUI.ps1)
$form = New-Object System.Windows.Forms.Form
$form.Text = "Test avec TabControl"
$form.Size = New-Object System.Drawing.Size(800, 600)

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = "Fill"

# Onglet 1
$tab1 = New-Object System.Windows.Forms.TabPage
$tab1.Text = "Onglet 1"
$label1 = New-Object System.Windows.Forms.Label
$label1.Text = "Contenu de l'onglet 1"
$label1.Dock = "Fill"
$label1.TextAlign = "MiddleCenter"
$tab1.Controls.Add($label1)
$tabControl.TabPages.Add($tab1)

# Onglet 2 avec le panel
$tab2 = New-Object System.Windows.Forms.TabPage
$tab2.Text = "Planning ODM"

# Appeler la fonction qui retourne le panel
$monPanel = Get-MonPanel

Write-Host "Type de monPanel: $($monPanel.GetType())" -ForegroundColor Yellow
Write-Host "Est-ce un Panel? $($monPanel -is [System.Windows.Forms.Panel])" -ForegroundColor Yellow

# Ajouter le panel à l'onglet
$tab2.Controls.Add($monPanel)
$tabControl.TabPages.Add($tab2)

$form.Controls.Add($tabControl)

$form.ShowDialog()

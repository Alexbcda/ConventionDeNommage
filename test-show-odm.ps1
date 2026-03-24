# test-show-odm.ps1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Charger le vrai module
$scriptPath = "C:\Users\alexa\Documents\ConventionDeNommage\src"
. "$scriptPath\ODM\ODMViewer.ps1"

$panel = Show-ODMViewer

$form = New-Object System.Windows.Forms.Form
$form.Text = "Test Show-ODMViewer"
$form.Size = New-Object System.Drawing.Size(1200, 800)

$form.Controls.Add($panel)

$form.ShowDialog()

# test-gui.ps1

Write-Host "=== TEST DE L'INTERFACE ===" -ForegroundColor Cyan

# Charger les assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Write-Host "✓ Assemblies chargées" -ForegroundColor Green

# Charger les modules
Write-Host "Chargement des modules..." -ForegroundColor Yellow

$scriptPath = "C:\Users\alexa\Documents\ConventionDeNommage\src"

try {
    . "$scriptPath\Config.ps1"
    Write-Host "✓ Config.ps1 chargé" -ForegroundColor Green
} catch { Write-Host "✗ Erreur Config.ps1: $_" -ForegroundColor Red }

try {
    . "$scriptPath\Core\TemplateManager.ps1"
    Write-Host "✓ TemplateManager.ps1 chargé" -ForegroundColor Green
} catch { Write-Host "✗ Erreur TemplateManager.ps1: $_" -ForegroundColor Red }

try {
    . "$scriptPath\Core\Rename.ps1"
    Write-Host "✓ Rename.ps1 chargé" -ForegroundColor Green
} catch { Write-Host "✗ Erreur Rename.ps1: $_" -ForegroundColor Red }

try {
    . "$scriptPath\Core\TemplateEditor.ps1"
    Write-Host "✓ TemplateEditor.ps1 chargé" -ForegroundColor Green
} catch { Write-Host "✗ Erreur TemplateEditor.ps1: $_" -ForegroundColor Red }

# Tester Get-Templates
Write-Host "`nTest Get-Templates:" -ForegroundColor Yellow
try {
    $templates = Get-Templates
    Write-Host "✓ Get-Templates réussi, $($templates.Count) templates" -ForegroundColor Green
    foreach ($t in $templates) {
        Write-Host "  - $($t.name) : $($t.format)" -ForegroundColor Gray
    }
} catch {
    Write-Host "✗ Erreur Get-Templates: $_" -ForegroundColor Red
}

# Créer une fenêtre simple pour tester
Write-Host "`nCréation d'une fenêtre de test..." -ForegroundColor Yellow

$form = New-Object System.Windows.Forms.Form
$form.Text = "Test Convention de nommage"
$form.Size = New-Object System.Drawing.Size(500, 400)
$form.StartPosition = "CenterScreen"

$label = New-Object System.Windows.Forms.Label
$label.Text = "Test de chargement réussi !"
$label.Location = New-Object System.Drawing.Point(50, 50)
$label.Size = New-Object System.Drawing.Size(400, 30)
$label.Font = New-Object System.Drawing.Font("Arial", 12)
$form.Controls.Add($label)

$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Location = New-Object System.Drawing.Point(50, 100)
$listBox.Size = New-Object System.Drawing.Size(400, 150)
foreach ($t in $templates) {
    $listBox.Items.Add("$($t.name) - $($t.format)")
}
$form.Controls.Add($listBox)

$btn = New-Object System.Windows.Forms.Button
$btn.Text = "Fermer"
$btn.Location = New-Object System.Drawing.Point(200, 280)
$btn.Size = New-Object System.Drawing.Size(100, 40)
$btn.Add_Click({ $form.Close() })
$form.Controls.Add($btn)

Write-Host "✓ Fenêtre créée, affichage..." -ForegroundColor Green
$form.ShowDialog() | Out-Null

Write-Host "=== FIN DU TEST ===" -ForegroundColor Cyan

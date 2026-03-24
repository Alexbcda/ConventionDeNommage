# test-odm.ps1
Write-Host "=== TEST DIRECT ODMViewer ===" -ForegroundColor Cyan

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptPath = "C:\Users\alexa\Documents\ConventionDeNommage\src"

Write-Host "1. Chargement des modules..." -ForegroundColor Yellow
try {
    . "$scriptPath\Config.ps1"
    . "$scriptPath\Core\TemplateManager.ps1"
    . "$scriptPath\Core\Rename.ps1"
    . "$scriptPath\Core\TemplateEditor.ps1"
    . "$scriptPath\ODM\ODMViewer.ps1"
    Write-Host "   ✅ Modules chargés" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Erreur: $_" -ForegroundColor Red
    exit
}

Write-Host "2. Appel de Show-ODMViewer..." -ForegroundColor Yellow
try {
    $panel = Show-ODMViewer
    Write-Host "   ✅ Panel créé" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Erreur: $_" -ForegroundColor Red
    Write-Host "   Stack: $($_.ScriptStackTrace)" -ForegroundColor Gray
    exit
}

Write-Host "3. Création d'une fenêtre de test..." -ForegroundColor Yellow
try {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Test ODMViewer"
    $form.Size = New-Object System.Drawing.Size(1200, 800)
    $form.StartPosition = "CenterScreen"
    
    $panel.Dock = "Fill"
    $form.Controls.Add($panel)
    
    Write-Host "   ✅ Fenêtre créée" -ForegroundColor Green
    Write-Host "   📌 Fermez la fenêtre pour continuer..." -ForegroundColor Yellow
    
    $form.ShowDialog() | Out-Null
    Write-Host "   ✅ Fenêtre fermée" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Erreur: $_" -ForegroundColor Red
    Write-Host "   Stack: $($_.ScriptStackTrace)" -ForegroundColor Gray
}

Write-Host "`n=== FIN DU TEST ===" -ForegroundColor Cyan
Read-Host "Appuyez sur Entrée pour continuer"

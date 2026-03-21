# test-start-gui.ps1

Write-Host "=== TEST DIRECT DE START-GUI ===" -ForegroundColor Cyan

# Charger les modules nécessaires
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptPath = "C:\Users\alexa\Documents\ConventionDeNommage\src"

Write-Host "1. Chargement des modules..." -ForegroundColor Yellow
try {
    . "$scriptPath\Config.ps1"
    Write-Host "   ✓ Config.ps1" -ForegroundColor Green
} catch { Write-Host "   ✗ $_" -ForegroundColor Red }

try {
    . "$scriptPath\Core\TemplateManager.ps1"
    Write-Host "   ✓ TemplateManager.ps1" -ForegroundColor Green
} catch { Write-Host "   ✗ $_" -ForegroundColor Red }

try {
    . "$scriptPath\Core\Rename.ps1"
    Write-Host "   ✓ Rename.ps1" -ForegroundColor Green
} catch { Write-Host "   ✗ $_" -ForegroundColor Red }

try {
    . "$scriptPath\Core\TemplateEditor.ps1"
    Write-Host "   ✓ TemplateEditor.ps1" -ForegroundColor Green
} catch { Write-Host "   ✗ $_" -ForegroundColor Red }

try {
    . "$scriptPath\GUI.ps1"
    Write-Host "   ✓ GUI.ps1" -ForegroundColor Green
} catch { Write-Host "   ✗ $_" -ForegroundColor Red }

Write-Host "`n2. Vérification de la fonction Start-GUI..." -ForegroundColor Yellow
if (Get-Command Start-GUI -ErrorAction SilentlyContinue) {
    Write-Host "   ✓ Start-GUI est disponible" -ForegroundColor Green
} else {
    Write-Host "   ✗ Start-GUI n'est pas disponible !" -ForegroundColor Red
    Write-Host "   Vérification des fonctions disponibles dans GUI.ps1:" -ForegroundColor Yellow
    Get-Command -Module (Get-Module -Name (Get-Content "$scriptPath\GUI.ps1")) -ErrorAction SilentlyContinue
}

Write-Host "`n3. Test avec un fichier PDF factice..." -ForegroundColor Yellow
$testFile = "C:\Users\alexa\Documents\ConventionDeNommage\test.pdf"

# Créer un fichier PDF factice pour le test
if (-not (Test-Path $testFile)) {
    "" | Out-File $testFile -Encoding utf8
    Write-Host "   Fichier test créé: $testFile" -ForegroundColor Gray
}

try {
    Write-Host "   Appel de Start-GUI avec fichier test..." -ForegroundColor Gray
    Start-GUI -FichierPDF $testFile
    Write-Host "   ✓ Start-GUI s'est exécuté sans erreur" -ForegroundColor Green
} catch {
    Write-Host "   ✗ Erreur: $_" -ForegroundColor Red
    Write-Host "   StackTrace: $($_.ScriptStackTrace)" -ForegroundColor Gray
}

Write-Host "`n=== FIN DU TEST ===" -ForegroundColor Cyan

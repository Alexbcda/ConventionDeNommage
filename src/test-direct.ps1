# test-direct.ps1
Write-Host "=== TEST DIRECT ===" -ForegroundColor Cyan

# Créer un fichier test
$testFile = "C:\Users\alexa\Documents\ConventionDeNommage\test.pdf"
if (-not (Test-Path $testFile)) {
    "" | Out-File $testFile -Encoding utf8
    Write-Host "Fichier test créé" -ForegroundColor Green
}

Write-Host "1. Chargement des modules..." -ForegroundColor Yellow
cd "C:\Users\alexa\Documents\ConventionDeNommage\src"

. ".\Config.ps1"
. ".\Core\TemplateManager.ps1"
. ".\Core\Rename.ps1"
. ".\Core\TemplateEditor.ps1"
. ".\GUI.ps1"

Write-Host "2. Appel de Start-GUI..." -ForegroundColor Yellow
Start-GUI -FichierPDF $testFile

Write-Host "3. Fin du test" -ForegroundColor Cyan

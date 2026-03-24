# test-minimal.ps1
Write-Host "=== TEST MINIMAL ===" -ForegroundColor Cyan

# Charger les modules de base
$scriptPath = "C:\Users\alexa\Documents\ConventionDeNommage\src"

Write-Host "1. Chargement Config.ps1..." -ForegroundColor Yellow
try {
    . "$scriptPath\Config.ps1"
    Write-Host "   ✅ OK" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Erreur: $_" -ForegroundColor Red
}

Write-Host "2. Chargement TemplateManager.ps1..." -ForegroundColor Yellow
try {
    . "$scriptPath\Core\TemplateManager.ps1"
    Write-Host "   ✅ OK" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Erreur: $_" -ForegroundColor Red
}

Write-Host "3. Chargement Rename.ps1..." -ForegroundColor Yellow
try {
    . "$scriptPath\Core\Rename.ps1"
    Write-Host "   ✅ OK" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Erreur: $_" -ForegroundColor Red
}

Write-Host "4. Chargement TemplateEditor.ps1..." -ForegroundColor Yellow
try {
    . "$scriptPath\Core\TemplateEditor.ps1"
    Write-Host "   ✅ OK" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Erreur: $_" -ForegroundColor Red
}

Write-Host "5. Chargement ODMViewer.ps1..." -ForegroundColor Yellow
try {
    . "$scriptPath\ODM\ODMViewer.ps1"
    Write-Host "   ✅ OK" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Erreur: $_" -ForegroundColor Red
}

Write-Host "6. Chargement GUI.ps1..." -ForegroundColor Yellow
try {
    . "$scriptPath\GUI.ps1"
    Write-Host "   ✅ OK" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Erreur: $_" -ForegroundColor Red
}

Write-Host "7. Vérification fonction Start-GUI..." -ForegroundColor Yellow
if (Get-Command Start-GUI -ErrorAction SilentlyContinue) {
    Write-Host "   ✅ Start-GUI disponible" -ForegroundColor Green
} else {
    Write-Host "   ❌ Start-GUI non disponible" -ForegroundColor Red
}

Write-Host "`n=== FIN DU TEST ===" -ForegroundColor Cyan

# diagnostic.ps1
Write-Host "=== DIAGNOSTIC COMPLET ===" -ForegroundColor Cyan

$scriptPath = "C:\Users\alexa\Documents\ConventionDeNommage\src"

# Test 1 : Vérifier les fichiers
Write-Host "`n1. VÉRIFICATION DES FICHIERS" -ForegroundColor Yellow
$files = @(
    "Config.ps1",
    "Core\TemplateManager.ps1",
    "Core\Rename.ps1",
    "Core\TemplateEditor.ps1",
    "ODM\ODMViewer.ps1",
    "GUI.ps1",
    "Main.ps1"
)

foreach ($file in $files) {
    $fullPath = Join-Path $scriptPath $file
    if (Test-Path $fullPath) {
        Write-Host "  ✅ $file" -ForegroundColor Green
    } else {
        Write-Host "  ❌ $file MANQUANT" -ForegroundColor Red
    }
}

# Test 2 : Charger Config.ps1
Write-Host "`n2. CHARGEMENT Config.ps1" -ForegroundColor Yellow
try {
    . "$scriptPath\Config.ps1"
    Write-Host "  ✅ OK" -ForegroundColor Green
    Write-Host "  formBackColor = $formBackColor" -ForegroundColor Gray
    Write-Host "  font = $font" -ForegroundColor Gray
} catch {
    Write-Host "  ❌ Erreur: $_" -ForegroundColor Red
    exit
}

# Test 3 : Charger TemplateManager.ps1
Write-Host "`n3. CHARGEMENT TemplateManager.ps1" -ForegroundColor Yellow
try {
    . "$scriptPath\Core\TemplateManager.ps1"
    Write-Host "  ✅ OK" -ForegroundColor Green
    $templates = Get-Templates
    Write-Host "  Templates chargés: $($templates.Count)" -ForegroundColor Gray
} catch {
    Write-Host "  ❌ Erreur: $_" -ForegroundColor Red
    Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor Gray
}

# Test 4 : Charger Rename.ps1
Write-Host "`n4. CHARGEMENT Rename.ps1" -ForegroundColor Yellow
try {
    . "$scriptPath\Core\Rename.ps1"
    Write-Host "  ✅ OK" -ForegroundColor Green
} catch {
    Write-Host "  ❌ Erreur: $_" -ForegroundColor Red
}

# Test 5 : Charger TemplateEditor.ps1
Write-Host "`n5. CHARGEMENT TemplateEditor.ps1" -ForegroundColor Yellow
try {
    . "$scriptPath\Core\TemplateEditor.ps1"
    Write-Host "  ✅ OK" -ForegroundColor Green
} catch {
    Write-Host "  ❌ Erreur: $_" -ForegroundColor Red
}

# Test 6 : Charger ODMViewer.ps1
Write-Host "`n6. CHARGEMENT ODMViewer.ps1" -ForegroundColor Yellow
try {
    . "$scriptPath\ODM\ODMViewer.ps1"
    Write-Host "  ✅ OK" -ForegroundColor Green
    if (Get-Command Show-ODMViewer -ErrorAction SilentlyContinue) {
        Write-Host "  ✅ Show-ODMViewer disponible" -ForegroundColor Green
    } else {
        Write-Host "  ❌ Show-ODMViewer non disponible" -ForegroundColor Red
    }
} catch {
    Write-Host "  ❌ Erreur: $_" -ForegroundColor Red
    Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor Gray
}

# Test 7 : Charger GUI.ps1
Write-Host "`n7. CHARGEMENT GUI.ps1" -ForegroundColor Yellow
try {
    . "$scriptPath\GUI.ps1"
    Write-Host "  ✅ OK" -ForegroundColor Green
    if (Get-Command Start-GUI -ErrorAction SilentlyContinue) {
        Write-Host "  ✅ Start-GUI disponible" -ForegroundColor Green
    } else {
        Write-Host "  ❌ Start-GUI non disponible" -ForegroundColor Red
    }
} catch {
    Write-Host "  ❌ Erreur: $_" -ForegroundColor Red
    Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor Gray
}

# Test 8 : Vérifier la syntaxe de GUI.ps1
Write-Host "`n8. SYNTAXE GUI.ps1" -ForegroundColor Yellow
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile("$scriptPath\GUI.ps1", [ref]$null, [ref]$errors)
if ($errors.Count -gt 0) {
    Write-Host "  ❌ Erreurs de syntaxe:" -ForegroundColor Red
    foreach ($err in $errors) {
        Write-Host "     $err" -ForegroundColor Yellow
    }
} else {
    Write-Host "  ✅ Syntaxe OK" -ForegroundColor Green
}

# Test 9 : Vérifier la syntaxe de ODMViewer.ps1
Write-Host "`n9. SYNTAXE ODMViewer.ps1" -ForegroundColor Yellow
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile("$scriptPath\ODM\ODMViewer.ps1", [ref]$null, [ref]$errors)
if ($errors.Count -gt 0) {
    Write-Host "  ❌ Erreurs de syntaxe:" -ForegroundColor Red
    foreach ($err in $errors) {
        Write-Host "     $err" -ForegroundColor Yellow
    }
} else {
    Write-Host "  ✅ Syntaxe OK" -ForegroundColor Green
}

Write-Host "`n=== FIN DIAGNOSTIC ===" -ForegroundColor Cyan
Read-Host "Appuyez sur Entrée pour continuer"

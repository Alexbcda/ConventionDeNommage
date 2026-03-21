# test-templates.ps1

Write-Host "=== TEST DE CHARGEMENT DES TEMPLATES ===" -ForegroundColor Cyan

# Chemins
$scriptPath = "C:\Users\alexa\Documents\ConventionDeNommage\src"
$dataPath = "$scriptPath\Data\templates.json"

Write-Host "1. Vérification du chemin des templates..." -ForegroundColor Yellow
Write-Host "   Chemin: $dataPath" -ForegroundColor White

# Vérifier si le fichier existe
if (Test-Path $dataPath) {
    Write-Host "   ✓ Fichier trouvé" -ForegroundColor Green
} else {
    Write-Host "   ✗ Fichier NON trouvé !" -ForegroundColor Red
}

# Lire et afficher le contenu du fichier
Write-Host "`n2. Contenu du fichier templates.json:" -ForegroundColor Yellow
try {
    $content = Get-Content $dataPath -Raw -ErrorAction Stop
    Write-Host "   Longueur: $($content.Length) caractères" -ForegroundColor White
    Write-Host "   Contenu: " -ForegroundColor White
    Write-Host $content -ForegroundColor Gray
} catch {
    Write-Host "   ✗ Erreur lecture: $_" -ForegroundColor Red
}

# Tenter de convertir en JSON
Write-Host "`n3. Conversion JSON:" -ForegroundColor Yellow
try {
    if (Test-Path $dataPath) {
        $templatesData = Get-Content $dataPath -Raw
        $templates = $templatesData | ConvertFrom-Json -ErrorAction Stop
        Write-Host "   ✓ Conversion réussie" -ForegroundColor Green
        Write-Host "   Nombre de templates: $($templates.templates.Count)" -ForegroundColor Green
    } else {
        Write-Host "   ✗ Fichier inexistant" -ForegroundColor Red
    }
}
catch {
    Write-Host "   ✗ Erreur conversion JSON: $_" -ForegroundColor Red
    Write-Host "   L'erreur indique que le fichier JSON est mal formé" -ForegroundColor Yellow
}

Write-Host "`n=== FIN DU TEST ===" -ForegroundColor Cyan
Read-Host "Appuyez sur Entrée pour continuer"

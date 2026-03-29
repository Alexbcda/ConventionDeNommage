$script:DataPath = Join-Path $PSScriptRoot "..\..\Data\ressources.json"

function Get-Collecteurs {
    Write-Host "[DATA] Get-Collecteurs appelé" -ForegroundColor Cyan
    $data = Load-ODMData
    if ($data -and $data.collecteurs) {
        Write-Host "[DATA] Get-Collecteurs retourne $($data.collecteurs.Count) collecteurs" -ForegroundColor Green
        return $data.collecteurs
    }
    Write-Host "[DATA] Get-Collecteurs retourne 0 collecteur" -ForegroundColor Red
    return @()
}

function Get-Vehicules {
    $data = Load-ODMData
    if ($data -and $data.vehicules) {
        return $data.vehicules
    }
    return @()
}

function Load-ODMData {
    Write-Host "[DATA] Load-ODMData - Lecture du fichier" -ForegroundColor Gray
    if (Test-Path $script:DataPath) {
        $content = Get-Content $script:DataPath -Raw
        Write-Host "[DATA] Fichier lu" -ForegroundColor Gray
        $data = $content | ConvertFrom-Json
        Write-Host "[DATA] collecteurs trouvés: $($data.collecteurs.Count)" -ForegroundColor Yellow
        return $data
    }
    Write-Host "[DATA] Fichier non trouvé" -ForegroundColor Red
    return $null
}

function Save-ODMData {
    param($Collecteurs, $Vehicules)
    
    Write-Host "[DATA] ========== SAVE ==========" -ForegroundColor Magenta
    Write-Host "[DATA] Sauvegarde de $($Collecteurs.Count) collecteurs" -ForegroundColor Yellow
    
    $data = @{
        collecteurs = $Collecteurs
        vehicules = $Vehicules
        clients = @()
    }
    
    $json = $data | ConvertTo-Json -Depth 10
    $json | Out-File $script:DataPath -Encoding utf8 -Force
    
    Write-Host "[DATA] ✅ Sauvegarde terminée" -ForegroundColor Green
    return $true
}

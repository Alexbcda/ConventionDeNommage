# DataManager.ps1 - Gestion des données avec logs

$script:DataPath = Join-Path $PSScriptRoot "..\Data\ressources.json"
Write-Host "[DATA] DataManager chargé" -ForegroundColor Cyan
Write-Host "[DATA] Chemin JSON: $script:DataPath" -ForegroundColor Gray

function Get-Collecteurs {
    Write-Host "[DATA] Get-Collecteurs appelé" -ForegroundColor Gray
    $data = Load-ODMData
    if ($data -and $data.chauffeurs) {
        Write-Host "[DATA] Get-Collecteurs retourne $($data.chauffeurs.Count) collecteurs" -ForegroundColor Green
        return $data.chauffeurs
    }
    Write-Host "[DATA] Get-Collecteurs retourne 0 collecteur" -ForegroundColor Yellow
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
    Write-Host "[DATA] Load-ODMData - Lecture du fichier JSON" -ForegroundColor Gray
    if (Test-Path $script:DataPath) {
        try {
            $content = Get-Content $script:DataPath -Raw -ErrorAction Stop
            Write-Host "[DATA] Fichier lu, taille: $($content.Length) caractères" -ForegroundColor Gray
            $data = $content | ConvertFrom-Json -ErrorAction Stop
            Write-Host "[DATA] JSON parsé avec succès" -ForegroundColor Green
            return $data
        } catch {
            Write-Host "[DATA] ❌ Erreur lecture JSON: $_" -ForegroundColor Red
            return $null
        }
    }
    Write-Host "[DATA] Fichier non trouvé: $script:DataPath" -ForegroundColor Yellow
    return $null
}

function Save-ODMData {
    param($Collecteurs, $Vehicules)
    
    Write-Host "[DATA] ========== Save-ODMData DEBUT ==========" -ForegroundColor Cyan
    Write-Host "[DATA] Collecteurs à sauvegarder: $($Collecteurs.Count)" -ForegroundColor Yellow
    Write-Host "[DATA] Véhicules à sauvegarder: $($Vehicules.Count)" -ForegroundColor Yellow
    
    # Afficher les collecteurs qui seront sauvegardés
    foreach ($c in $Collecteurs) {
        Write-Host "[DATA]   - $($c.prenom) $($c.nom) (ID=$($c.id))" -ForegroundColor Gray
    }
    
    $data = @{
        chauffeurs = $Collecteurs
        vehicules = $Vehicules
        clients = @()
    }
    
    try {
        $json = $data | ConvertTo-Json -Depth 10
        Write-Host "[DATA] JSON généré, taille: $($json.Length) caractères" -ForegroundColor Gray
        
        $json | Out-File $script:DataPath -Encoding utf8 -Force
        Write-Host "[DATA] ✅ Fichier écrit: $script:DataPath" -ForegroundColor Green
        
        # Vérifier que le fichier a bien été écrit
        if (Test-Path $script:DataPath) {
            $fileInfo = Get-Item $script:DataPath
            Write-Host "[DATA] Vérification: $($fileInfo.Length) octets, modifié à $($fileInfo.LastWriteTime)" -ForegroundColor Gray
        }
        
        Write-Host "[DATA] ========== Save-ODMData SUCCES ==========" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[DATA] ❌ Erreur sauvegarde: $_" -ForegroundColor Red
        Write-Host "[DATA] ========== Save-ODMData ECHEC ==========" -ForegroundColor Red
        return $false
    }
}

function Initialize-DefaultData {
    Write-Host "[DATA] Initialisation des données par défaut" -ForegroundColor Yellow
    $defaultCollecteurs = @(
        @{ id = 1; nom = "DUPONT"; prenom = "Jean"; telephone = "0601020304"; email = "jean.dupont@email.com"; vehiculeDefaut = "" },
        @{ id = 2; nom = "MARTIN"; prenom = "Pierre"; telephone = "0605060708"; email = "pierre.martin@email.com"; vehiculeDefaut = "" }
    )
    
    $defaultVehicules = @(
        @{ id = 1; immatriculation = "AA-123-BB"; marque = "Renault"; modele = "Master"; annee = 2020 },
        @{ id = 2; immatriculation = "CC-456-DD"; marque = "Citroen"; modele = "Jumper"; annee = 2021 }
    )
    
    Save-ODMData -Collecteurs $defaultCollecteurs -Vehicules $defaultVehicules
    return $defaultCollecteurs, $defaultVehicules
}

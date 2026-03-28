# CollecteursManager.ps1 - Gestion des collecteurs avec logs

Write-Host "[MGR] Chargement de CollecteursManager.ps1" -ForegroundColor Cyan

$dataManagerPath = Join-Path $PSScriptRoot "..\..\Core\DataManager.ps1"
if (Test-Path $dataManagerPath) {
    . $dataManagerPath
    Write-Host "[MGR] DataManager.ps1 chargé" -ForegroundColor Green
} else {
    Write-Host "[MGR] ERREUR: DataManager.ps1 non trouvé" -ForegroundColor Red
}

function Add-Collecteur {
    param($Prenom, $Nom, $Telephone, $Email, $VehiculeDefaut)

    Write-Host ""
    Write-Host "[MGR] ========== Add-Collecteur DEBUT ==========" -ForegroundColor Magenta
    Write-Host "[MGR] Paramètres reçus:" -ForegroundColor Yellow
    Write-Host "[MGR]   - Prenom: '$Prenom'" -ForegroundColor White
    Write-Host "[MGR]   - Nom: '$Nom'" -ForegroundColor White
    Write-Host "[MGR]   - Telephone: '$Telephone'" -ForegroundColor White
    Write-Host "[MGR]   - Email: '$Email'" -ForegroundColor White
    Write-Host "[MGR]   - VehiculeDefaut: '$VehiculeDefaut'" -ForegroundColor White

    try {
        # Étape 1: Récupérer les collecteurs existants
        Write-Host "[MGR] Étape 1: Appel de Get-Collecteurs..." -ForegroundColor Cyan
        $collecteurs = Get-Collecteurs
        Write-Host "[MGR] Get-Collecteurs retourné: $($collecteurs.Count) collecteurs" -ForegroundColor Green
        foreach ($c in $collecteurs) {
            Write-Host "[MGR]   Existant: $($c.prenom) $($c.nom) (ID=$($c.id))" -ForegroundColor Gray
        }

        # Étape 2: Générer un ID
        $newId = (Get-Random -Minimum 100 -Maximum 999)
        Write-Host "[MGR] Étape 2: Nouvel ID généré = $newId" -ForegroundColor Cyan

        # Étape 3: Créer le nouveau collecteur
        $newCollecteur = @{
            id = $newId
            prenom = $Prenom
            nom = $Nom
            telephone = $Telephone
            email = $Email
            vehiculeDefaut = $VehiculeDefaut
        }
        Write-Host "[MGR] Étape 3: Nouveau collecteur créé" -ForegroundColor Green
        Write-Host "[MGR]   Données: $($newCollecteur | ConvertTo-Json -Compress)" -ForegroundColor Gray

        # Étape 4: Ajouter à la liste
        $collecteurs += $newCollecteur
        Write-Host "[MGR] Étape 4: Collecteur ajouté - nouvelle taille: $($collecteurs.Count)" -ForegroundColor Green

        # Étape 5: Récupérer les véhicules
        Write-Host "[MGR] Étape 5: Appel de Get-Vehicules..." -ForegroundColor Cyan
        $vehicules = Get-Vehicules
        Write-Host "[MGR] Get-Vehicules retourné: $($vehicules.Count) véhicules" -ForegroundColor Green

        # Étape 6: Sauvegarder
        Write-Host "[MGR] Étape 6: Appel de Save-ODMData..." -ForegroundColor Cyan
        $result = Save-ODMData -Collecteurs $collecteurs -Vehicules $vehicules
        Write-Host "[MGR] Save-ODMData retourné: $result" -ForegroundColor Yellow

        Write-Host "[MGR] ========== Add-Collecteur SUCCES ==========" -ForegroundColor Green
        Write-Host ""
        return $newCollecteur
    } catch {
        Write-Host "[MGR] ❌ ERREUR: $_" -ForegroundColor Red
        Write-Host "[MGR] StackTrace: $($_.ScriptStackTrace)" -ForegroundColor Red
        Write-Host "[MGR] ========== Add-Collecteur ECHEC ==========" -ForegroundColor Red
        Write-Host ""
        return $null
    }
}

function Update-Collecteur {
    param($Id, $Prenom, $Nom, $Telephone, $Email, $VehiculeDefaut)
    Write-Host "[MGR] Update-Collecteur - Id=$Id, $Prenom $Nom" -ForegroundColor Cyan
    $collecteurs = Get-Collecteurs
    for ($i = 0; $i -lt $collecteurs.Count; $i++) {
        if ($collecteurs[$i].id -eq $Id) {
            $collecteurs[$i] = @{ id = $Id; prenom = $Prenom; nom = $Nom; telephone = $Telephone; email = $Email; vehiculeDefaut = $VehiculeDefaut }
            break
        }
    }
    Save-ODMData -Collecteurs $collecteurs -Vehicules (Get-Vehicules)
    Write-Host "[MGR] ✅ Update OK" -ForegroundColor Green
    return $true
}

function Remove-Collecteur {
    param($Id)
    Write-Host "[MGR] Remove-Collecteur - Id=$Id" -ForegroundColor Cyan
    $collecteurs = Get-Collecteurs
    $newCollecteurs = $collecteurs | Where-Object { $_.id -ne $Id }
    Save-ODMData -Collecteurs $newCollecteurs -Vehicules (Get-Vehicules)
    Write-Host "[MGR] ✅ Remove OK" -ForegroundColor Green
    return $true
}

Write-Host "[MGR] CollecteursManager.ps1 chargé" -ForegroundColor Green

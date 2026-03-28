# VehiculesManager.ps1 - Gestion des véhicules (CRUD)

Write-Host "[MGR] Chargement de VehiculesManager.ps1" -ForegroundColor Cyan

$dataManagerPath = Join-Path $PSScriptRoot "..\..\Core\DataManager.ps1"
if (Test-Path $dataManagerPath) {
    . $dataManagerPath
    Write-Host "[MGR] DataManager.ps1 chargé" -ForegroundColor Green
} else {
    Write-Host "[MGR] ERREUR: DataManager.ps1 non trouvé" -ForegroundColor Red
}

function Add-Vehicule {
    param(
        [string]$NumeroParc,
        [string]$Immatriculation,
        [string]$NumeroChassis,
        [string]$Marque,
        [string]$Modele,
        [string]$DateMiseCirculation,
        [string]$DateControle,
        [string]$Alerte,
        [string]$DateAlerte
    )

    Write-Host ""
    Write-Host "[MGR] ========== Add-Vehicule DEBUT ==========" -ForegroundColor Magenta
    Write-Host "[MGR] Numéro parc: '$NumeroParc'" -ForegroundColor Yellow
    Write-Host "[MGR] Immatriculation: '$Immatriculation'" -ForegroundColor Yellow
    Write-Host "[MGR] Numéro châssis: '$NumeroChassis'" -ForegroundColor Yellow
    Write-Host "[MGR] Marque: '$Marque'" -ForegroundColor Yellow
    Write-Host "[MGR] Modèle: '$Modele'" -ForegroundColor Yellow
    Write-Host "[MGR] Mise circulation: '$DateMiseCirculation'" -ForegroundColor Yellow
    Write-Host "[MGR] Contrôle: '$DateControle'" -ForegroundColor Yellow
    Write-Host "[MGR] Alerte: '$Alerte'" -ForegroundColor Yellow
    Write-Host "[MGR] Date alerte: '$DateAlerte'" -ForegroundColor Yellow

    try {
        # Récupérer les véhicules existants et forcer en tableau
        $vehiculesTemp = Get-Vehicules
        if ($vehiculesTemp -eq $null) {
            $vehicules = @()
        } elseif ($vehiculesTemp -is [array]) {
            $vehicules = $vehiculesTemp
        } else {
            # Si c'est un objet unique, le mettre dans un tableau
            $vehicules = @($vehiculesTemp)
        }
        Write-Host "[MGR] Véhicules existants: $($vehicules.Count)" -ForegroundColor Gray
        
        # Générer un nouvel ID
        $newId = (Get-Random -Minimum 100 -Maximum 999)
        Write-Host "[MGR] Nouvel ID: $newId" -ForegroundColor Cyan
        
        # Créer le nouveau véhicule
        $newVehicule = [PSCustomObject]@{
            id = $newId
            numeroParc = $NumeroParc
            immatriculation = $Immatriculation.ToUpper()
            numeroChassis = $NumeroChassis.ToUpper()
            marque = $Marque
            modele = $Modele
            dateMiseCirculation = $DateMiseCirculation
            dateControle = $DateControle
            alerte = $Alerte
            dateAlerte = $DateAlerte
        }
        
        # Ajouter à la liste en créant un nouveau tableau
        $vehicules = @($vehicules) + @($newVehicule)
        Write-Host "[MGR] Nouvelle liste: $($vehicules.Count) véhicules" -ForegroundColor Green

        # Récupérer les collecteurs et sauvegarder
        $collecteursTemp = Get-Collecteurs
        if ($collecteursTemp -eq $null) {
            $collecteurs = @()
        } elseif ($collecteursTemp -is [array]) {
            $collecteurs = $collecteursTemp
        } else {
            $collecteurs = @($collecteursTemp)
        }
        
        $result = Save-ODMData -Collecteurs $collecteurs -Vehicules $vehicules
        Write-Host "[MGR] Save-ODMData retourné: $result" -ForegroundColor Gray
        
        Write-Host "[MGR] ✅ Succès, ID=$newId" -ForegroundColor Green
        return $newVehicule
    } catch {
        Write-Host "[MGR] ❌ Erreur: $_" -ForegroundColor Red
        Write-Host "[MGR] Stack: $($_.ScriptStackTrace)" -ForegroundColor Red
        return $null
    }
}

function Update-Vehicule {
    param(
        $Id,
        $NumeroParc,
        $Immatriculation,
        $NumeroChassis,
        $Marque,
        $Modele,
        $DateMiseCirculation,
        $DateControle,
        $Alerte,
        $DateAlerte
    )

    Write-Host "[MGR] Update-Vehicule - Id=$Id" -ForegroundColor Cyan

    # Récupérer les véhicules et forcer en tableau
    $vehiculesTemp = Get-Vehicules
    if ($vehiculesTemp -eq $null) {
        $vehicules = @()
    } elseif ($vehiculesTemp -is [array]) {
        $vehicules = $vehiculesTemp
    } else {
        $vehicules = @($vehiculesTemp)
    }
    
    $trouve = $false
    for ($i = 0; $i -lt $vehicules.Count; $i++) {
        if ($vehicules[$i].id -eq $Id) {
            $vehicules[$i] = [PSCustomObject]@{
                id = $Id
                numeroParc = $NumeroParc
                immatriculation = $Immatriculation.ToUpper()
                numeroChassis = $NumeroChassis.ToUpper()
                marque = $Marque
                modele = $Modele
                dateMiseCirculation = $DateMiseCirculation
                dateControle = $DateControle
                alerte = $Alerte
                dateAlerte = $DateAlerte
            }
            $trouve = $true
            Write-Host "[MGR] Véhicule modifié à l'index $i" -ForegroundColor Green
            break
        }
    }
    
    if (-not $trouve) {
        Write-Host "[MGR] ❌ Véhicule non trouvé (ID=$Id)" -ForegroundColor Red
        return $false
    }
    
    # Récupérer les collecteurs et forcer en tableau
    $collecteursTemp = Get-Collecteurs
    if ($collecteursTemp -eq $null) {
        $collecteurs = @()
    } elseif ($collecteursTemp -is [array]) {
        $collecteurs = $collecteursTemp
    } else {
        $collecteurs = @($collecteursTemp)
    }
    
    Save-ODMData -Collecteurs $collecteurs -Vehicules $vehicules
    Write-Host "[MGR] ✅ Update OK" -ForegroundColor Green
    return $true
}

function Remove-Vehicule {
    param($Id)

    Write-Host "[MGR] Remove-Vehicule - Id=$Id" -ForegroundColor Cyan

    # Récupérer les véhicules et forcer en tableau
    $vehiculesTemp = Get-Vehicules
    if ($vehiculesTemp -eq $null) {
        $vehicules = @()
    } elseif ($vehiculesTemp -is [array]) {
        $vehicules = $vehiculesTemp
    } else {
        $vehicules = @($vehiculesTemp)
    }
    
    $ancienCount = $vehicules.Count
    $newVehicules = $vehicules | Where-Object { $_.id -ne $Id }
    Write-Host "[MGR] Avant: $ancienCount, Après: $($newVehicules.Count)" -ForegroundColor Gray
    
    # Récupérer les collecteurs et forcer en tableau
    $collecteursTemp = Get-Collecteurs
    if ($collecteursTemp -eq $null) {
        $collecteurs = @()
    } elseif ($collecteursTemp -is [array]) {
        $collecteurs = $collecteursTemp
    } else {
        $collecteurs = @($collecteursTemp)
    }
    
    Save-ODMData -Collecteurs $collecteurs -Vehicules $newVehicules
    
    Write-Host "[MGR] ✅ Remove OK" -ForegroundColor Green
    return $true
}

Write-Host "[MGR] VehiculesManager.ps1 chargé" -ForegroundColor Green

. "$PSScriptRoot\..\..\Core\DataManager.ps1"

function Add-Vehicule {
    param(
        $NumeroParc, $Immatriculation, $NumeroChassis,
        $Marque, $Modele, $DateMiseCirculation, $DateControle,
        $Alerte, $DateAlerte
    )
    
    $vehicules = @(Get-Vehicules)
    $newId = (Get-Random -Minimum 100 -Maximum 999)
    while ($vehicules.id -contains $newId) { $newId = (Get-Random -Minimum 100 -Maximum 999) }
    
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
        conducteurId = $null
    }
    
    $vehicules = $vehicules + @($newVehicule)
    $collecteurs = @(Get-Collecteurs)
    Save-ODMData -Collecteurs $collecteurs -Vehicules $vehicules
    return $newVehicule
}

function Update-Vehicule {
    param($Id, $NumeroParc, $Immatriculation, $NumeroChassis,
          $Marque, $Modele, $DateMiseCirculation, $DateControle,
          $Alerte, $DateAlerte)
    
    $vehicules = @(Get-Vehicules)
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
                conducteurId = $vehicules[$i].conducteurId
            }
            break
        }
    }
    $collecteurs = @(Get-Collecteurs)
    Save-ODMData -Collecteurs $collecteurs -Vehicules $vehicules
    return $true
}

function Remove-Vehicule {
    param($Id)
    
    $vehicules = @(Get-Vehicules)
    $newVehicules = @()
    foreach ($v in $vehicules) {
        if ($v.id -ne $Id) { $newVehicules += $v }
    }
    $collecteurs = @(Get-Collecteurs)
    Save-ODMData -Collecteurs $collecteurs -Vehicules $newVehicules
    return $true
}

function Update-AffectationVehicule {
    param($VehiculeId, $CollecteurId)
    
    Write-Host "[DATA] Update-AffectationVehicule - Vehicule: $VehiculeId, Collecteur: $CollecteurId" -ForegroundColor Cyan
    
    $vehicules = @(Get-Vehicules)
    for ($i = 0; $i -lt $vehicules.Count; $i++) {
        if ($vehicules[$i].id -eq $VehiculeId) {
            $vehicules[$i] = [PSCustomObject]@{
                id = $vehicules[$i].id
                numeroParc = $vehicules[$i].numeroParc
                immatriculation = $vehicules[$i].immatriculation
                numeroChassis = $vehicules[$i].numeroChassis
                marque = $vehicules[$i].marque
                modele = $vehicules[$i].modele
                dateMiseCirculation = $vehicules[$i].dateMiseCirculation
                dateControle = $vehicules[$i].dateControle
                alerte = $vehicules[$i].alerte
                dateAlerte = $vehicules[$i].dateAlerte
                conducteurId = $CollecteurId
            }
            break
        }
    }
    $collecteurs = @(Get-Collecteurs)
    Save-ODMData -Collecteurs $collecteurs -Vehicules $vehicules
    Write-Host "[DATA] Affectation sauvegardée" -ForegroundColor Green
    return $true
}

function Get-VehiculeByCollecteurId {
    param($CollecteurId)
    $vehicules = @(Get-Vehicules)
    return $vehicules | Where-Object { $_.conducteurId -eq $CollecteurId } | Select-Object -First 1
}

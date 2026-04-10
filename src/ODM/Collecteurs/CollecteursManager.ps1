. "$PSScriptRoot\..\..\Core\DataManager.ps1"

function Add-Collecteur {
    param($Nom, $Prenom, $Telephone, $Email, $VehiculeId = $null)
    
    $collecteurs = @(Get-Collecteurs)
    $newId = (Get-Random -Minimum 100 -Maximum 999)
    while ($collecteurs.id -contains $newId) { $newId = (Get-Random -Minimum 100 -Maximum 999) }
    
    $newCollecteur = [PSCustomObject]@{
        id = $newId
        nom = $Nom
        prenom = $Prenom
        telephone = $Telephone
        email = $Email
        vehiculeId = $VehiculeId
    }
    
    $collecteurs = $collecteurs + @($newCollecteur)
    $vehicules = @(Get-Vehicules)
    
    if ($VehiculeId) {
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
                    conducteurId = $newId
                }
                break
            }
        }
    }
    
    Save-ODMData -Collecteurs $collecteurs -Vehicules $vehicules
    return $newCollecteur
}

function Update-Collecteur {
    param($Id, $Nom, $Prenom, $Telephone, $Email, $VehiculeId = $null)
    
    $collecteurs = @(Get-Collecteurs)
    $ancienVehiculeId = $null
    
    for ($i = 0; $i -lt $collecteurs.Count; $i++) {
        if ($collecteurs[$i].id -eq $Id) {
            $ancienVehiculeId = $collecteurs[$i].vehiculeId
            $collecteurs[$i] = [PSCustomObject]@{
                id = $Id
                nom = $Nom
                prenom = $Prenom
                telephone = $Telephone
                email = $Email
                vehiculeId = $VehiculeId
            }
            break
        }
    }
    
    $vehicules = @(Get-Vehicules)
    
    if ($ancienVehiculeId -ne $VehiculeId) {
        if ($ancienVehiculeId) {
            for ($i = 0; $i -lt $vehicules.Count; $i++) {
                if ($vehicules[$i].id -eq $ancienVehiculeId) {
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
                        conducteurId = $null
                    }
                    break
                }
            }
        }
        
        if ($VehiculeId) {
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
                        conducteurId = $Id
                    }
                    break
                }
            }
        }
    }
    
    Save-ODMData -Collecteurs $collecteurs -Vehicules $vehicules
    return $true
}

function Remove-Collecteur {
    param($Id)
    
    $collecteurs = @(Get-Collecteurs)
    $newCollecteurs = @()
    foreach ($c in $collecteurs) {
        if ($c.id -ne $Id) { $newCollecteurs += $c }
    }
    
    $vehicules = @(Get-Vehicules)
    for ($i = 0; $i -lt $vehicules.Count; $i++) {
        if ($vehicules[$i].conducteurId -eq $Id) {
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
                conducteurId = $null
            }
        }
    }
    
    Save-ODMData -Collecteurs $newCollecteurs -Vehicules $vehicules
    return $true
}

# DataManager.ps1 - Gestion des données (collecteurs, véhicules)

$script:DataPath = Join-Path $PSScriptRoot "..\Data\ressources.json"

function Get-Collecteurs {
    $data = Load-ODMData
    if ($data -and $data.chauffeurs) {
        return $data.chauffeurs
    }
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
    if (Test-Path $script:DataPath) {
        try {
            $data = Get-Content $script:DataPath -Raw | ConvertFrom-Json
            return $data
        } catch {
            return $null
        }
    }
    return $null
}

function Save-ODMData {
    param($Collecteurs, $Vehicules)
    
    $data = @{
        chauffeurs = $Collecteurs
        vehicules = $Vehicules
        clients = @()
    }
    
    $data | ConvertTo-Json -Depth 10 | Out-File $script:DataPath -Encoding utf8
    return $true
}

function Initialize-DefaultData {
    $defaultCollecteurs = @(
        @{ id = 1; nom = "DUPONT"; prenom = "Jean"; telephone = "0601020304"; email = "jean.dupont@email.com" },
        @{ id = 2; nom = "MARTIN"; prenom = "Pierre"; telephone = "0605060708"; email = "pierre.martin@email.com" }
    )
    
    $defaultVehicules = @(
        @{ id = 1; immatriculation = "AA-123-BB"; marque = "Renault"; modele = "Master"; annee = 2020 },
        @{ id = 2; immatriculation = "CC-456-DD"; marque = "Citroen"; modele = "Jumper"; annee = 2021 }
    )
    
    Save-ODMData -Collecteurs $defaultCollecteurs -Vehicules $defaultVehicules
    return $defaultCollecteurs, $defaultVehicules
}

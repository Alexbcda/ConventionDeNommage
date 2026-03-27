# DataManager.ps1 - Gestion des donn?es

$script:DataPath = Join-Path $PSScriptRoot "..\..\Data\ressources.json"

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
        @{ id = 1; nom = "DUPONT"; prenom = "Jean"; telephone = "0601020304" },
        @{ id = 2; nom = "MARTIN"; prenom = "Pierre"; telephone = "0605060708" },
        @{ id = 3; nom = "BERNARD"; prenom = "Philippe"; telephone = "0610111213" },
        @{ id = 4; nom = "THOMAS"; prenom = "Michel"; telephone = "0614151617" },
        @{ id = 5; nom = "ROBERT"; prenom = "Nicolas"; telephone = "0618192021" }
    )
    
    $defaultVehicules = @(
        @{ id = 1; immatriculation = "AA-123-BB"; marque = "Renault"; modele = "Master"; annee = 2020 },
        @{ id = 2; immatriculation = "CC-456-DD"; marque = "Citro?n"; modele = "Jumper"; annee = 2021 },
        @{ id = 3; immatriculation = "EE-789-FF"; marque = "Mercedes"; modele = "Sprinter"; annee = 2022 },
        @{ id = 4; immatriculation = "FF-012-GG"; marque = "Iveco"; modele = "Daily"; annee = 2020 },
        @{ id = 5; immatriculation = "GG-345-HH"; marque = "Ford"; modele = "Transit"; annee = 2021 }
    )
    
    Save-ODMData -Collecteurs $defaultCollecteurs -Vehicules $defaultVehicules
    return $defaultCollecteurs, $defaultVehicules
}

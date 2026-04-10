# Services/AffectationService.ps1

function Load-InitialData {
    $collecteurs = Get-Collecteurs
    $vehicules = Get-Vehicules
    Set-State -Key "Collecteurs" -Value $collecteurs
    Set-State -Key "Vehicules" -Value $vehicules
    return @{ Collecteurs = $collecteurs; Vehicules = $vehicules }
}

function Set-Date { param([string]$Date) Set-State -Key "Date" -Value $Date }
function Get-Date { return Get-State -Key "Date" }

function Set-NbTournees {
    param([int]$Nb)
    Set-State -Key "NbTournees" -Value $Nb
    $affectations = @{}
    for ($i = 1; $i -le $Nb; $i++) { $affectations[$i] = @{ Collecteur = $null; Vehicule = $null } }
    Set-State -Key "Affectations" -Value $affectations
}

function Get-NbTournees { return Get-State -Key "NbTournees" }

function Set-Affectation {
    param([int]$TourneeId, [string]$Collecteur, [string]$Vehicule)
    $affectations = Get-State -Key "Affectations"
    if (-not $affectations) { $affectations = @{} }
    $affectations[$TourneeId] = @{ Collecteur = $Collecteur; Vehicule = $Vehicule; TourneeId = $TourneeId }
    Set-State -Key "Affectations" -Value $affectations
}

function Get-Affectations { return Get-State -Key "Affectations" }

function Get-CollecteursList {
    $collecteurs = Get-State -Key "Collecteurs"
    if ($collecteurs.Count -eq 0) { return @("Collecteur 1", "Collecteur 2", "Collecteur 3") }
    $names = @(); foreach ($c in $collecteurs) { $names += "$($c.prenom) $($c.nom)".Trim() }
    return $names
}

function Get-VehiculesList {
    $vehicules = Get-State -Key "Vehicules"
    if ($vehicules.Count -eq 0) { return @("Véhicule A", "Véhicule B", "Véhicule C") }
    $parcs = @(); foreach ($v in $vehicules) { if ($v.numeroParc) { $parcs += $v.numeroParc } }
    return $parcs
}

function Reset-Wizard { Reset-State; Load-InitialData }

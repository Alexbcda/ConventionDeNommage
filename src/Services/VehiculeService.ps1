# VehiculeService.ps1 — Service layer for vehicle operations
# UI (Panels/Forms) should ONLY call functions defined here.
# Architecture: UI → Service → Repository → Database

. "$PSScriptRoot\..\ODM\Vehicules\VehiculesRepository.ps1"

function Get-VehiculeList {
    param([switch]$IncludeInactive)
    if ($IncludeInactive) { return Get-AllVehicules } else { return Get-Vehicules }
}

function Get-VehiculeDetails {
    param([Parameter(Mandatory=$true)] $Id)
    return Get-VehiculeById -Id $Id
}

function Add-VehiculeEntry {
    param(
        $NumeroParc,
        $Immatriculation,
        $NumeroChassis,
        $Marque,
        $Modele,
        $DateMiseCirculation,
        $DateControle,
        $DateEntree,
        $DateSortie,
        $DateFinControleTechnique
    )
    return Add-VehiculeWithValidation @PSBoundParameters
}

function Update-VehiculeEntry {
    param(
        $Id,
        $NumeroParc,
        $Immatriculation,
        $NumeroChassis,
        $Marque,
        $Modele,
        $DateMiseCirculation,
        $DateControle,
        $DateEntree,
        $DateSortie,
        $DateFinControleTechnique
    )
    return Update-Vehicule @PSBoundParameters
}

function Remove-VehiculeEntry {
    param([Parameter(Mandatory=$true)] $Id)
    return Remove-Vehicule -Id $Id
}

function Test-VehiculeDoublonParc {
    param([Parameter(Mandatory=$true)] [string]$NumeroParc, [int]$ExcludeId = 0)
    return (Test-VehiculeExistsByParc -NumeroParc $NumeroParc -ExcludeId $ExcludeId)
}

function Test-VehiculeDoublonImmat {
    param([Parameter(Mandatory=$true)] [string]$Immatriculation, [int]$ExcludeId = 0)
    return (Test-VehiculeExistsByImmat -Immatriculation $Immatriculation -ExcludeId $ExcludeId)
}

function Test-VehiculeDoublonChassis {
    param([Parameter(Mandatory=$true)] [string]$NumeroChassis, [int]$ExcludeId = 0)
    return (Test-VehiculeExistsByChassis -NumeroChassis $NumeroChassis -ExcludeId $ExcludeId)
}

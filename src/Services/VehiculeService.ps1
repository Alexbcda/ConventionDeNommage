# VehiculeService.ps1 — Service layer for vehicle operations
# UI (Panels/Forms) should ONLY call functions defined here.
# Architecture: UI → Service (guard) → Repository (validation) → Database

. "$PSScriptRoot\..\ODM\Vehicules\VehiculesRepository.ps1"

function Assert-VehiculeServiceInput {
    param($NumeroParc, $Immatriculation, $NumeroChassis)
    Assert-RequiredString "Numero de parc" $NumeroParc -MaxLength 50
    Assert-RequiredString "Immatriculation" $Immatriculation -MaxLength 20
    if ([string]::IsNullOrWhiteSpace($NumeroChassis)) {
        throw "Numero de chassis est obligatoire."
    }
    if ($NumeroChassis.Trim().Length -ne 17) {
        throw "Numero de chassis doit contenir exactement 17 caracteres."
    }
}

function Get-VehiculeList {
    param([switch]$IncludeInactive)
    return Get-VehiculeRecords -IncludeInactive:$IncludeInactive
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
    Assert-VehiculeServiceInput -NumeroParc $NumeroParc -Immatriculation $Immatriculation -NumeroChassis $NumeroChassis
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
    Assert-VehiculeServiceInput -NumeroParc $NumeroParc -Immatriculation $Immatriculation -NumeroChassis $NumeroChassis
    return Update-Vehicule @PSBoundParameters
}

function Remove-VehiculeEntry {
    param([Parameter(Mandatory=$true)] $Id)
    return Remove-Vehicule -Id $Id
}

function ConvertTo-VehiculeFormData {
    param([Parameter(Mandatory=$true)] $VehiculeRecord)
    return @{
        id                       = $VehiculeRecord.id
        numeroParc               = $VehiculeRecord.numero_parc
        immatriculation          = $VehiculeRecord.immatriculation
        numeroChassis            = $VehiculeRecord.numero_chassis
        marque                   = $VehiculeRecord.marque
        modele                   = $VehiculeRecord.modele
        dateMiseCirculation      = $VehiculeRecord.date_mise_circulation
        dateControle             = $VehiculeRecord.date_controle
        dateEntree               = $VehiculeRecord.date_entree
        dateSortie               = $VehiculeRecord.date_sortie
        dateFinControleTechnique = $VehiculeRecord.date_fin_controle_technique
    }
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

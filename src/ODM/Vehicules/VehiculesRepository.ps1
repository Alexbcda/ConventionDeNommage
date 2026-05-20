# VehiculesRepository.ps1 — Logique métier véhicules (validation + appels Database.ps1)
# Couche persistance : Add-VehiculeRecord, Update-VehiculeRecord, Remove-VehiculeRecord, Get-VehiculeRowById

. "$PSScriptRoot\..\..\Database\Database.ps1"
. "$PSScriptRoot\..\..\Common\Validation.ps1"
. "$PSScriptRoot\..\..\Core\Logger.ps1"

function Normalize-VehiculeParc {
    param([string]$NumeroParc)
    $p = Sanitize-TextInput (Normalize-Whitespace $NumeroParc)
    if ([string]::IsNullOrWhiteSpace($p)) {
        throw "Le numéro de parc est obligatoire."
    }
    if (-not (Test-NumeroParcVehicule $p)) {
        throw "Numéro de parc invalide."
    }
    return $p
}

function Normalize-VehiculeTextOptional {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    $t = Sanitize-TextInput (Normalize-Whitespace $Text)
    if ([string]::IsNullOrWhiteSpace($t)) { return "" }
    if (-not (Test-SecuriteInput $t)) {
        throw "Une entrée texte contient des caractères interdits."
    }
    if ($t.Length -gt 120) { throw "Texte trop long." }
    return $t
}

function Assert-YyyyMmDdOrNull {
    param([string]$DateStr, [string]$FieldName, [bool]$Required)
    if ([string]::IsNullOrWhiteSpace($DateStr)) {
        if ($Required) { throw "$FieldName est obligatoire." }
        return $null
    }
    if (-not (Test-YyyyMmDdDate $DateStr)) {
        throw "$FieldName : format de date invalide."
    }
    return $DateStr
}

function Assert-VehiculeId {
    param($Id)
    return Assert-EntityId "vehicule" $Id
}

function Assert-VehiculeFields {
    param($NumeroParc, $Immatriculation, $NumeroChassis, $Marque, $Modele,
          $DateMiseCirculation, $DateControle, $DateEntree, $DateSortie, $DateFinControleTechnique)

    $NumeroParc = Normalize-VehiculeParc $NumeroParc
    $Immatriculation = (Sanitize-TextInput $Immatriculation).Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($Immatriculation) -or -not (Test-SecuriteInput $Immatriculation)) {
        throw "Immatriculation invalide."
    }
    $NumeroChassis = (Sanitize-TextInput $NumeroChassis).Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($NumeroChassis) -or $NumeroChassis -notmatch '^[A-HJ-NPR-Z0-9]{17}$') {
        throw "Numero de chassis (VIN) invalide."
    }
    $Marque = Normalize-VehiculeTextOptional $Marque
    $Modele = Normalize-VehiculeTextOptional $Modele

    $DateMiseCirculation = Assert-YyyyMmDdOrNull $DateMiseCirculation "Date de mise en circulation" $true
    $DateControle = Assert-YyyyMmDdOrNull $DateControle "Date de controle technique" $false
    $DateEntree = Assert-YyyyMmDdOrNull $DateEntree "Date d'entree" $true
    $DateSortie = Assert-YyyyMmDdOrNull $DateSortie "Date de sortie" $false
    $DateFinControleTechnique = Assert-YyyyMmDdOrNull $DateFinControleTechnique "Date fin controle technique" $false

    $actif = if ([string]::IsNullOrWhiteSpace($DateSortie)) { 1 } else { 0 }

    return @{
        NumeroParc = $NumeroParc; Immatriculation = $Immatriculation; NumeroChassis = $NumeroChassis
        Marque = $Marque; Modele = $Modele
        DateMiseCirculation = $DateMiseCirculation; DateControle = $DateControle
        DateEntree = $DateEntree; DateSortie = $DateSortie
        DateFinControleTechnique = $DateFinControleTechnique; Actif = $actif
    }
}

function Add-VehiculeWithValidation {
    <#
    Même rôle que Add-AgentWithValidation : journalisation + validation puis persistance.
    #>
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

    try {
        return Add-Vehicule @PSBoundParameters
    } catch {
        Write-Log "[Vehicules] Add failed" "ERROR" @{ message = $_.Exception.Message }
        throw
    }
}

function Add-Vehicule {
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

    $f = Assert-VehiculeFields @PSBoundParameters

    return Add-VehiculeRecord `
        -NumeroParc $f.NumeroParc `
        -Immatriculation $f.Immatriculation `
        -NumeroChassis $f.NumeroChassis `
        -Marque $f.Marque `
        -Modele $f.Modele `
        -DateMiseCirculation $f.DateMiseCirculation `
        -DateControle $f.DateControle `
        -DateEntree $f.DateEntree `
        -DateSortie $f.DateSortie `
        -DateFinControleTechnique $f.DateFinControleTechnique `
        -Actif $f.Actif
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
        $DateEntree,
        $DateSortie,
        $DateFinControleTechnique
    )

    $Id = Assert-VehiculeId $Id
    $fieldParams = $PSBoundParameters
    $fieldParams.Remove('Id') | Out-Null
    $f = Assert-VehiculeFields @fieldParams

    return Update-VehiculeRecord `
        -Id $Id `
        -NumeroParc $f.NumeroParc `
        -Immatriculation $f.Immatriculation `
        -NumeroChassis $f.NumeroChassis `
        -Marque $f.Marque `
        -Modele $f.Modele `
        -DateMiseCirculation $f.DateMiseCirculation `
        -DateControle $f.DateControle `
        -DateEntree $f.DateEntree `
        -DateSortie $f.DateSortie `
        -DateFinControleTechnique $f.DateFinControleTechnique `
        -Actif $f.Actif
}

function Remove-Vehicule {
    param($Id)
    $Id = Assert-VehiculeId $Id
    return Remove-VehiculeRecord -Id $Id
}

function Get-VehiculeById {
    <#
    Charge un véhicule par id (actif ou historique), pour édition depuis la grille.
    #>
    param($Id)
    $Id = Assert-VehiculeId $Id
    return Get-VehiculeRowById -Id $Id
}

function Get-VehiculeRecords {
    param([switch]$IncludeInactive)
    if ($IncludeInactive) { return Get-AllVehicules } else { return Get-Vehicules }
}

function Test-VehiculeExistsByParc {
    param([Parameter(Mandatory=$true)] [string]$NumeroParc, [int]$ExcludeId = 0)
    return (Test-VehiculeRecordExistsByColumn -ColumnName 'numero_parc' -Value $NumeroParc -ExcludeId $ExcludeId)
}

function Test-VehiculeExistsByImmat {
    param([Parameter(Mandatory=$true)] [string]$Immatriculation, [int]$ExcludeId = 0)
    return (Test-VehiculeRecordExistsByColumn -ColumnName 'immatriculation' -Value $Immatriculation -ExcludeId $ExcludeId)
}

function Test-VehiculeExistsByChassis {
    param([Parameter(Mandatory=$true)] [string]$NumeroChassis, [int]$ExcludeId = 0)
    return (Test-VehiculeRecordExistsByColumn -ColumnName 'numero_chassis' -Value $NumeroChassis -ExcludeId $ExcludeId)
}

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
    if ($null -eq $Id -or "$Id" -notmatch '^\d+$') {
        throw "Identifiant véhicule invalide."
    }
    return [int]$Id
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

    Write-Log "[Vehicules] Add-VehiculeWithValidation begin" "INFO" @{ action = 'AddVehicule' }

    try {
        $id = Add-Vehicule @PSBoundParameters
        Write-Log "[Vehicules] Add-VehiculeWithValidation success" "INFO" @{ id = $id }
        return $id
    } catch {
        Write-Log "[Vehicules] Add-VehiculeWithValidation failed" "ERROR" @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
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

    $NumeroParc = Normalize-VehiculeParc $NumeroParc
    $Immatriculation = (Sanitize-TextInput $Immatriculation).Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($Immatriculation) -or -not (Test-SecuriteInput $Immatriculation)) {
        throw "Immatriculation invalide."
    }
    $NumeroChassis = (Sanitize-TextInput $NumeroChassis).Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($NumeroChassis) -or $NumeroChassis -notmatch '^[A-HJ-NPR-Z0-9]{17}$') {
        throw "Numéro de châssis (VIN) invalide."
    }
    $Marque = Normalize-VehiculeTextOptional $Marque
    $Modele = Normalize-VehiculeTextOptional $Modele

    $DateMiseCirculation = Assert-YyyyMmDdOrNull $DateMiseCirculation "Date de mise en circulation" $true
    $DateControle = Assert-YyyyMmDdOrNull $DateControle "Date de contrôle technique" $false
    $DateEntree = Assert-YyyyMmDdOrNull $DateEntree "Date d'entrée" $true
    $DateSortie = Assert-YyyyMmDdOrNull $DateSortie "Date de sortie" $false
    $DateFinControleTechnique = Assert-YyyyMmDdOrNull $DateFinControleTechnique "Date fin contrôle technique" $false

    $actif = if ([string]::IsNullOrWhiteSpace($DateSortie)) { 1 } else { 0 }

    return Add-VehiculeRecord `
        -NumeroParc $NumeroParc `
        -Immatriculation $Immatriculation `
        -NumeroChassis $NumeroChassis `
        -Marque $Marque `
        -Modele $Modele `
        -DateMiseCirculation $DateMiseCirculation `
        -DateControle $DateControle `
        -DateEntree $DateEntree `
        -DateSortie $DateSortie `
        -DateFinControleTechnique $DateFinControleTechnique `
        -Actif $actif
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

    $NumeroParc = Normalize-VehiculeParc $NumeroParc
    $Immatriculation = (Sanitize-TextInput $Immatriculation).Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($Immatriculation) -or -not (Test-SecuriteInput $Immatriculation)) {
        throw "Immatriculation invalide."
    }
    $NumeroChassis = (Sanitize-TextInput $NumeroChassis).Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($NumeroChassis) -or $NumeroChassis -notmatch '^[A-HJ-NPR-Z0-9]{17}$') {
        throw "Numéro de châssis (VIN) invalide."
    }
    $Marque = Normalize-VehiculeTextOptional $Marque
    $Modele = Normalize-VehiculeTextOptional $Modele

    $DateMiseCirculation = Assert-YyyyMmDdOrNull $DateMiseCirculation "Date de mise en circulation" $true
    $DateControle = Assert-YyyyMmDdOrNull $DateControle "Date de contrôle technique" $false
    $DateEntree = Assert-YyyyMmDdOrNull $DateEntree "Date d'entrée" $true
    $DateSortie = Assert-YyyyMmDdOrNull $DateSortie "Date de sortie" $false
    $DateFinControleTechnique = Assert-YyyyMmDdOrNull $DateFinControleTechnique "Date fin contrôle technique" $false

    $actif = if ([string]::IsNullOrWhiteSpace($DateSortie)) { 1 } else { 0 }

    return Update-VehiculeRecord `
        -Id $Id `
        -NumeroParc $NumeroParc `
        -Immatriculation $Immatriculation `
        -NumeroChassis $NumeroChassis `
        -Marque $Marque `
        -Modele $Modele `
        -DateMiseCirculation $DateMiseCirculation `
        -DateControle $DateControle `
        -DateEntree $DateEntree `
        -DateSortie $DateSortie `
        -DateFinControleTechnique $DateFinControleTechnique `
        -Actif $actif
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

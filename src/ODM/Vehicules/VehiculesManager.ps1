# VehiculesManager.ps1 - Version SQLite

. "$PSScriptRoot\..\..\Database\Database.ps1"
. "$PSScriptRoot\..\..\Common\Validation.ps1"

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

    $conn = Open-Connection
    try {
        $actif = if ([string]::IsNullOrWhiteSpace($DateSortie)) { 1 } else { 0 }
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
INSERT INTO Vehicule (
    numero_parc, immatriculation, numero_chassis, marque, modele,
    date_mise_circulation, date_controle, date_entree, date_sortie,
    date_fin_controle_technique, actif
)
VALUES (
    @parc, @immat, @chassis, @marque, @modele,
    @date_mise, @date_ctrl, @date_entree, @date_sortie,
    @date_fin_ctrl_tech, @actif
)
"@
        $cmd.Parameters.AddWithValue("@parc", $NumeroParc) | Out-Null
        $cmd.Parameters.AddWithValue("@immat", $Immatriculation) | Out-Null
        $cmd.Parameters.AddWithValue("@chassis", $NumeroChassis) | Out-Null
        $cmd.Parameters.AddWithValue("@marque", $(if ($Marque) { $Marque } else { [DBNull]::Value })) | Out-Null
        $cmd.Parameters.AddWithValue("@modele", $(if ($Modele) { $Modele } else { [DBNull]::Value })) | Out-Null
        $cmd.Parameters.AddWithValue("@date_mise", $DateMiseCirculation) | Out-Null
        $cmd.Parameters.AddWithValue("@date_ctrl", $(if ($DateControle) { $DateControle } else { [DBNull]::Value })) | Out-Null
        $cmd.Parameters.AddWithValue("@date_entree", $DateEntree) | Out-Null
        $cmd.Parameters.AddWithValue("@date_sortie", $(if ($DateSortie) { $DateSortie } else { [DBNull]::Value })) | Out-Null
        $cmd.Parameters.AddWithValue("@date_fin_ctrl_tech", $(if ($DateFinControleTechnique) { $DateFinControleTechnique } else { [DBNull]::Value })) | Out-Null
        $cmd.Parameters.AddWithValue("@actif", $actif) | Out-Null
        
        $cmd.ExecuteNonQuery()
        $cmd.CommandText = "SELECT last_insert_rowid()"
        return $cmd.ExecuteScalar()
    } finally {
        Close-Connection $conn
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
        $DateEntree,
        $DateSortie,
        $DateFinControleTechnique
    )

    if ($null -eq $Id -or "$Id" -notmatch '^\d+$') {
        throw "Identifiant véhicule invalide."
    }

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

    $conn = Open-Connection
    try {
        $actif = if ([string]::IsNullOrWhiteSpace($DateSortie)) { 1 } else { 0 }
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
UPDATE Vehicule 
SET numero_parc = @parc, immatriculation = @immat, numero_chassis = @chassis, 
    marque = @marque, modele = @modele, date_mise_circulation = @date_mise, date_controle = @date_ctrl,
    date_entree = @date_entree, date_sortie = @date_sortie,
    date_fin_controle_technique = @date_fin_ctrl_tech, actif = @actif
WHERE id_vehicule = @id
"@
        $cmd.Parameters.AddWithValue("@id", $Id) | Out-Null
        $cmd.Parameters.AddWithValue("@parc", $NumeroParc) | Out-Null
        $cmd.Parameters.AddWithValue("@immat", $Immatriculation) | Out-Null
        $cmd.Parameters.AddWithValue("@chassis", $NumeroChassis) | Out-Null
        $cmd.Parameters.AddWithValue("@marque", $(if ($Marque) { $Marque } else { [DBNull]::Value })) | Out-Null
        $cmd.Parameters.AddWithValue("@modele", $(if ($Modele) { $Modele } else { [DBNull]::Value })) | Out-Null
        $cmd.Parameters.AddWithValue("@date_mise", $DateMiseCirculation) | Out-Null
        $cmd.Parameters.AddWithValue("@date_ctrl", $(if ($DateControle) { $DateControle } else { [DBNull]::Value })) | Out-Null
        $cmd.Parameters.AddWithValue("@date_entree", $DateEntree) | Out-Null
        $cmd.Parameters.AddWithValue("@date_sortie", $(if ($DateSortie) { $DateSortie } else { [DBNull]::Value })) | Out-Null
        $cmd.Parameters.AddWithValue("@date_fin_ctrl_tech", $(if ($DateFinControleTechnique) { $DateFinControleTechnique } else { [DBNull]::Value })) | Out-Null
        $cmd.Parameters.AddWithValue("@actif", $actif) | Out-Null
        
        return $cmd.ExecuteNonQuery()
    } finally {
        Close-Connection $conn
    }
}

function Remove-Vehicule {
    param($Id)

    if ($null -eq $Id -or "$Id" -notmatch '^\d+$') {
        throw "Identifiant véhicule invalide."
    }

    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "DELETE FROM Vehicule WHERE id_vehicule = @id"
        $cmd.Parameters.AddWithValue("@id", $Id) | Out-Null
        return $cmd.ExecuteNonQuery()
    } finally {
        Close-Connection $conn
    }
}

function Get-VehiculeById {
    <#
    Charge un véhicule par id, y compris inactif (historique), pour édition depuis la grille.
    #>
    param($Id)

    if ($null -eq $Id -or "$Id" -notmatch '^\d+$') {
        throw "Identifiant véhicule invalide."
    }

    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
SELECT id_vehicule, numero_parc, immatriculation, numero_chassis, marque, modele,
       date_mise_circulation, date_controle, date_entree, date_sortie,
       date_fin_controle_technique, capacite, conducteur_id, actif
FROM Vehicule
WHERE id_vehicule = @id
"@
        $cmd.Parameters.AddWithValue("@id", $Id) | Out-Null
        $reader = $cmd.ExecuteReader()
        try {
            if (-not $reader.Read()) { return $null }
            return [PSCustomObject]@{
                id = $reader["id_vehicule"]
                numero_parc = $reader["numero_parc"]
                immatriculation = $reader["immatriculation"]
                numero_chassis = $reader["numero_chassis"]
                marque = $reader["marque"]
                modele = $reader["modele"]
                date_mise_circulation = $reader["date_mise_circulation"]
                date_controle = $reader["date_controle"]
                date_entree = $reader["date_entree"]
                date_sortie = $reader["date_sortie"]
                date_fin_controle_technique = $reader["date_fin_controle_technique"]
                capacite = $reader["capacite"]
                conducteur_id = $reader["conducteur_id"]
                actif = $reader["actif"]
            }
        } finally {
            if ($reader) { $reader.Close() }
        }
    } finally {
        Close-Connection $conn
    }
}

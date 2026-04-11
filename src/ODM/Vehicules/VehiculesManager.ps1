# VehiculesManager.ps1 - Version SQLite

. "$PSScriptRoot\..\..\Database\Database.ps1"

function Add-Vehicule {
    param($NumeroParc, $Immatriculation, $NumeroChassis, $Marque, $Modele, $DateMiseCirculation, $DateControle)
    
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
INSERT INTO Vehicule (numero_parc, immatriculation, numero_chassis, marque, modele, date_mise_circulation, date_controle, actif)
VALUES (@parc, @immat, @chassis, @marque, @modele, @date_mise, @date_ctrl, 1)
"@
        $cmd.Parameters.AddWithValue("@parc", $NumeroParc) | Out-Null
        $cmd.Parameters.AddWithValue("@immat", $Immatriculation.ToUpper()) | Out-Null
        $cmd.Parameters.AddWithValue("@chassis", $NumeroChassis.ToUpper()) | Out-Null
        $cmd.Parameters.AddWithValue("@marque", $Marque) | Out-Null
        $cmd.Parameters.AddWithValue("@modele", $Modele) | Out-Null
        $cmd.Parameters.AddWithValue("@date_mise", $DateMiseCirculation) | Out-Null
        $cmd.Parameters.AddWithValue("@date_ctrl", $DateControle) | Out-Null
        
        $cmd.ExecuteNonQuery()
        $cmd.CommandText = "SELECT last_insert_rowid()"
        return $cmd.ExecuteScalar()
    } finally {
        Close-Connection $conn
    }
}

function Update-Vehicule {
    param($Id, $NumeroParc, $Immatriculation, $NumeroChassis, $Marque, $Modele, $DateMiseCirculation, $DateControle)
    
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
UPDATE Vehicule 
SET numero_parc = @parc, immatriculation = @immat, numero_chassis = @chassis, 
    marque = @marque, modele = @modele, date_mise_circulation = @date_mise, date_controle = @date_ctrl
WHERE id_vehicule = @id
"@
        $cmd.Parameters.AddWithValue("@id", $Id) | Out-Null
        $cmd.Parameters.AddWithValue("@parc", $NumeroParc) | Out-Null
        $cmd.Parameters.AddWithValue("@immat", $Immatriculation.ToUpper()) | Out-Null
        $cmd.Parameters.AddWithValue("@chassis", $NumeroChassis.ToUpper()) | Out-Null
        $cmd.Parameters.AddWithValue("@marque", $Marque) | Out-Null
        $cmd.Parameters.AddWithValue("@modele", $Modele) | Out-Null
        $cmd.Parameters.AddWithValue("@date_mise", $DateMiseCirculation) | Out-Null
        $cmd.Parameters.AddWithValue("@date_ctrl", $DateControle) | Out-Null
        
        return $cmd.ExecuteNonQuery()
    } finally {
        Close-Connection $conn
    }
}

function Remove-Vehicule {
    param($Id)
    
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
    param($Id)
    $vehicules = Get-Vehicules
    return $vehicules | Where-Object { $_.id -eq $Id }
}

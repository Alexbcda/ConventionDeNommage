# AgentRepository.ps1 - CRUD Agent avec SQLite

. "$PSScriptRoot\..\..\Database\Database.ps1"

function Add-Agent {
    param($Nom, $Prenom, $Telephone, $Email, $DateEntree, $TypeContrat, $BaseHeuresSemaine = 35, $VehiculeId = $null)
    
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
INSERT INTO Agent (nom, prenom, telephone, email, date_entree, type_contrat, base_heures_semaine, actif)
VALUES (@nom, @prenom, @tel, @email, @date_entree, @type_contrat, @base_heures, 1)
"@
        $cmd.Parameters.AddWithValue("@nom", $Nom) | Out-Null
        $cmd.Parameters.AddWithValue("@prenom", $Prenom) | Out-Null
        $cmd.Parameters.AddWithValue("@tel", $Telephone) | Out-Null
        $cmd.Parameters.AddWithValue("@email", $Email) | Out-Null
        $cmd.Parameters.AddWithValue("@date_entree", $DateEntree) | Out-Null
        $cmd.Parameters.AddWithValue("@type_contrat", $TypeContrat) | Out-Null
        $cmd.Parameters.AddWithValue("@base_heures", $BaseHeuresSemaine) | Out-Null
        
        $cmd.ExecuteNonQuery()
        $cmd.CommandText = "SELECT last_insert_rowid()"
        return $cmd.ExecuteScalar()
    } finally {
        Close-Connection $conn
    }
}

function Update-Agent {
    param($Id, $Nom, $Prenom, $Telephone, $Email, $DateSortie = $null, $Actif = 1)
    
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
UPDATE Agent 
SET nom = @nom, prenom = @prenom, telephone = @tel, email = @email, date_sortie = @date_sortie, actif = @actif
WHERE id_agent = @id
"@
        $cmd.Parameters.AddWithValue("@id", $Id) | Out-Null
        $cmd.Parameters.AddWithValue("@nom", $Nom) | Out-Null
        $cmd.Parameters.AddWithValue("@prenom", $Prenom) | Out-Null
        $cmd.Parameters.AddWithValue("@tel", $Telephone) | Out-Null
        $cmd.Parameters.AddWithValue("@email", $Email) | Out-Null
        $cmd.Parameters.AddWithValue("@date_sortie", $DateSortie) | Out-Null
        $cmd.Parameters.AddWithValue("@actif", $Actif) | Out-Null
        
        return $cmd.ExecuteNonQuery()
    } finally {
        Close-Connection $conn
    }
}

function Remove-Agent {
    param($Id)
    
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "UPDATE Vehicule SET conducteur_id = NULL WHERE conducteur_id = @id"
        $cmd.Parameters.AddWithValue("@id", $Id) | Out-Null
        $cmd.ExecuteNonQuery()
        
        $cmd.CommandText = "DELETE FROM Agent WHERE id_agent = @id"
        return $cmd.ExecuteNonQuery()
    } finally {
        Close-Connection $conn
    }
}

function Get-AgentById {
    param($Id)
    
    $agents = Get-Agents
    return $agents | Where-Object { $_.id -eq $Id }
}

function Get-Agents {
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT id_agent, nom, prenom, telephone, email, date_entree, type_contrat, base_heures_semaine, actif FROM Agent WHERE actif = 1 ORDER BY nom, prenom"
        $reader = $cmd.ExecuteReader()
        $agents = @()
        while ($reader.Read()) {
            $agents += [PSCustomObject]@{
                id = $reader["id_agent"]
                nom = $reader["nom"]
                prenom = $reader["prenom"]
                telephone = $reader["telephone"]
                email = $reader["email"]
                date_entree = $reader["date_entree"]
                type_contrat = $reader["type_contrat"]
                base_heures_semaine = $reader["base_heures_semaine"]
                actif = $reader["actif"]
            }
        }
        return $agents
    } finally {
        Close-Connection $conn
    }
}

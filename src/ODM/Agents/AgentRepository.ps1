# AgentRepository.ps1 - CRUD Agent avec SQLite

. "$PSScriptRoot\..\..\Database\Database.ps1"

function Add-Agent {
    param($Nom, $Prenom, $Telephone, $Email, $DateEntree, $TypeContrat, $BaseHeuresSemaine = 35, $VehiculeId = $null, $Poste = "Collecteur")
    
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
INSERT INTO Agent (nom, prenom, telephone, email, date_entree, type_contrat, base_heures_semaine, poste, actif)
VALUES (@nom, @prenom, @tel, @email, @date_entree, @type_contrat, @base_heures, @poste, 1)
"@
        $cmd.Parameters.AddWithValue("@nom", $Nom) | Out-Null
        $cmd.Parameters.AddWithValue("@prenom", $Prenom) | Out-Null
        $cmd.Parameters.AddWithValue("@tel", $Telephone) | Out-Null
        $cmd.Parameters.AddWithValue("@email", $Email) | Out-Null
        $cmd.Parameters.AddWithValue("@date_entree", $DateEntree) | Out-Null
        $cmd.Parameters.AddWithValue("@type_contrat", $TypeContrat) | Out-Null
        $cmd.Parameters.AddWithValue("@base_heures", $BaseHeuresSemaine) | Out-Null
        $cmd.Parameters.AddWithValue("@poste", $Poste) | Out-Null
        
        $cmd.ExecuteNonQuery()
        $cmd.CommandText = "SELECT last_insert_rowid()"
        return $cmd.ExecuteScalar()
    } finally {
        Close-Connection $conn
    }
}

function Update-Agent {
    param($Id, $Nom, $Prenom, $Telephone, $Email, $DateEntree, $DateSortie = $null, $TypeContrat, $BaseHeuresSemaine, $VehiculeId = $null, $Poste)
    
    $conn = Open-Connection
    try {
        $actif = if ($DateSortie) { 0 } else { 1 }
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
UPDATE Agent 
SET nom = @nom, prenom = @prenom, telephone = @tel, email = @email, 
    date_entree = @date_entree, date_sortie = @date_sortie, type_contrat = @type_contrat, 
    base_heures_semaine = @base_heures, vehicule_id = @vehicule_id, poste = @poste, actif = @actif
WHERE id_agent = @id
"@
        $cmd.Parameters.AddWithValue("@id", $Id) | Out-Null
        $cmd.Parameters.AddWithValue("@nom", $Nom) | Out-Null
        $cmd.Parameters.AddWithValue("@prenom", $Prenom) | Out-Null
        $cmd.Parameters.AddWithValue("@tel", $Telephone) | Out-Null
        $cmd.Parameters.AddWithValue("@email", $Email) | Out-Null
        $cmd.Parameters.AddWithValue("@date_entree", $DateEntree) | Out-Null
        $cmd.Parameters.AddWithValue("@date_sortie", $DateSortie) | Out-Null
        $cmd.Parameters.AddWithValue("@type_contrat", $TypeContrat) | Out-Null
        $cmd.Parameters.AddWithValue("@base_heures", $BaseHeuresSemaine) | Out-Null
        $cmd.Parameters.AddWithValue("@vehicule_id", $VehiculeId) | Out-Null
        $cmd.Parameters.AddWithValue("@poste", $Poste) | Out-Null
        $cmd.Parameters.AddWithValue("@actif", $actif) | Out-Null
        
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
        $cmd.CommandText = "DELETE FROM Agent WHERE id_agent = @id"
        return $cmd.ExecuteNonQuery()
    } finally {
        Close-Connection $conn
    }
}

function Get-AgentById {
    param($Id)
    
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT * FROM Agent WHERE id_agent = @id"
        $cmd.Parameters.AddWithValue("@id", $Id) | Out-Null
        $reader = $cmd.ExecuteReader()
        if ($reader.Read()) {
            return [PSCustomObject]@{
                id = $reader["id_agent"]
                nom = $reader["nom"]
                prenom = $reader["prenom"]
                telephone = $reader["telephone"]
                email = $reader["email"]
                date_entree = $reader["date_entree"]
                date_sortie = $reader["date_sortie"]
                type_contrat = $reader["type_contrat"]
                base_heures_semaine = $reader["base_heures_semaine"]
                poste = $reader["poste"]
                vehicule_id = $reader["vehicule_id"]
                actif = $reader["actif"]
            }
        }
        return $null
    } finally {
        Close-Connection $conn
    }
}

function Get-Agents {
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT id_agent, nom, prenom, telephone, email, date_entree, date_sortie, type_contrat, base_heures_semaine, poste, actif FROM Agent WHERE actif = 1 ORDER BY nom, prenom"
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
                date_sortie = $reader["date_sortie"]
                type_contrat = $reader["type_contrat"]
                base_heures_semaine = $reader["base_heures_semaine"]
                poste = $reader["poste"]
                actif = $reader["actif"]
            }
        }
        return $agents
    } finally {
        Close-Connection $conn
    }
}

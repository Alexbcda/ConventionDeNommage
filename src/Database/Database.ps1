# ============================================================
# Database.ps1 - VERSION FINALE STABLE
# ============================================================

$script:DbPath  = Join-Path $PSScriptRoot "..\..\Data\gestion.db"
$script:DllPath = Join-Path $PSScriptRoot "..\..\lib\System.Data.SQLite.dll"

$script:POSTES = @(
    'Collecteur',
    'Trieur',
    'Assistant planning',
    'REX',
    'Commercial',
    'Responsable des exploitations'
)

function Get-PostesListe { return $script:POSTES }

# ============================================================
# DATE - CORRIGÉE
# ============================================================

function ToDbDate {
    param($Date)
    if (-not $Date) { return $null }
    try {
        if ($Date -is [datetime]) {
            return [int]($Date - [datetime]"1970-01-01").TotalSeconds
        }
        $d = [datetime]::Parse($Date)
        return [int]($d - [datetime]"1970-01-01").TotalSeconds
    } catch {
        return $null
    }
}

function FromDbDate {
    param($Timestamp)
    if (-not $Timestamp) { return $null }
    try {
        $epoch = [datetime]"1970-01-01"
        return $epoch.AddSeconds([int]$Timestamp)
    } catch {
        return $null
    }
}

# ============================================================
# CONNEXION
# ============================================================

function Initialize-Database {
    if (-not (Test-Path $script:DllPath)) {
        Write-Host "❌ DLL manquante" -ForegroundColor Red
        return $false
    }

    Add-Type -Path $script:DllPath -ErrorAction Stop

    if (-not (Test-Path $script:DbPath)) {
        $schema = Get-Content (Join-Path $PSScriptRoot "Schema.sql") -Raw
        $conn = Open-Connection
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $schema
        $null = $cmd.ExecuteNonQuery()
        Close-Connection $conn
        Write-Host "✅ Base créée" -ForegroundColor Green
    }
    return $true
}

function Open-Connection {
    $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$script:DbPath;Version=3;")
    $conn.Open()
    return $conn
}

function Close-Connection {
    param($c)
    if ($c) {
        $c.Close()
        $c.Dispose()
    }
}

# ============================================================
# AGENTS
# ============================================================

function Add-Agent {
    param(
        $Nom,
        $Prenom,
        $Telephone,
        $Email,
        $DateEntree,
        $DateSortie,
        $TypeContrat,
        $BaseHeuresSemaine = 35,
        $VehiculeId = $null,
        $Poste = "Collecteur"
    )

    if ($Poste -notin $script:POSTES) {
        throw "Poste invalide"
    }

    $actif = if ($DateSortie) { 0 } else { 1 }

    $conn = Open-Connection

    try {
        $cmd = $conn.CreateCommand()

        $cmd.CommandText = @"
INSERT INTO Agent (
nom, prenom, telephone, email,
date_entree, date_sortie,
type_contrat, base_heures_semaine,
vehicule_id, poste, actif
)
VALUES (
@nom, @prenom, @tel, @email,
@de, @ds,
@tc, @bh,
@vid, @poste, @actif
)
"@

        $cmd.Parameters.AddWithValue("@nom", $Nom) | Out-Null
        $cmd.Parameters.AddWithValue("@prenom", $Prenom) | Out-Null
        $cmd.Parameters.AddWithValue("@tel", $Telephone) | Out-Null
        $cmd.Parameters.AddWithValue("@email", $Email) | Out-Null
        $cmd.Parameters.AddWithValue("@de", (ToDbDate $DateEntree)) | Out-Null
        $cmd.Parameters.AddWithValue("@ds", (ToDbDate $DateSortie)) | Out-Null
        $cmd.Parameters.AddWithValue("@tc", $TypeContrat) | Out-Null
        $cmd.Parameters.AddWithValue("@bh", $BaseHeuresSemaine) | Out-Null
        $cmd.Parameters.AddWithValue("@vid", $VehiculeId) | Out-Null
        $cmd.Parameters.AddWithValue("@poste", $Poste) | Out-Null
        $cmd.Parameters.AddWithValue("@actif", $actif) | Out-Null

        $null = $cmd.ExecuteNonQuery()

        $cmd.CommandText = "SELECT last_insert_rowid()"
        $result = $cmd.ExecuteScalar()
        
        # Extraire le nombre (gère le cas "1 1")
        $resultString = $result.ToString()
        $match = [regex]::Match($resultString, '\d+$')
        if ($match.Success) {
            return [int]$match.Value
        }
        return [int]$resultString
    }
    finally {
        Close-Connection $conn
    }
}

function Get-AgentById {
    param($Id)

    $conn = Open-Connection

    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT * FROM Agent WHERE id_agent = @id"
        $cmd.Parameters.AddWithValue("@id", [int]$Id) | Out-Null

        $reader = $cmd.ExecuteReader()

        $result = $null

        if ($reader.Read()) {
            $result = [PSCustomObject]@{
                id = $reader["id_agent"]
                nom = $reader["nom"]
                prenom = $reader["prenom"]
                telephone = $reader["telephone"]
                email = $reader["email"]
                date_entree = FromDbDate $reader["date_entree"]
                date_sortie = FromDbDate $reader["date_sortie"]
                type_contrat = $reader["type_contrat"]
                base_heures_semaine = $reader["base_heures_semaine"]
                poste = $reader["poste"]
                actif = $reader["actif"]
                vehicule_id = $reader["vehicule_id"]
            }
        }

        $reader.Close()
        return $result
    }
    finally {
        Close-Connection $conn
    }
}

function Remove-Agent {
    param($Id)

    $conn = Open-Connection

    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "DELETE FROM Agent WHERE id_agent = @id"
        $cmd.Parameters.AddWithValue("@id", [int]$Id) | Out-Null
        return $cmd.ExecuteNonQuery()
    }
    finally {
        Close-Connection $conn
    }
}

function Get-Agents {
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
SELECT id_agent, nom, prenom, telephone, email,
date_entree, date_sortie, type_contrat,
base_heures_semaine, poste, actif, vehicule_id
FROM Agent
WHERE actif = 1
ORDER BY nom, prenom
"@
        $reader = $cmd.ExecuteReader()
        $agents = @()
        while ($reader.Read()) {
            $agents += [PSCustomObject]@{
                id = $reader["id_agent"]
                nom = $reader["nom"]
                prenom = $reader["prenom"]
                telephone = $reader["telephone"]
                email = $reader["email"]
                date_entree = FromDbDate $reader["date_entree"]
                date_sortie = FromDbDate $reader["date_sortie"]
                type_contrat = $reader["type_contrat"]
                base_heures_semaine = $reader["base_heures_semaine"]
                poste = $reader["poste"]
                actif = $reader["actif"]
                vehicule_id = $reader["vehicule_id"]
            }
        }
        return $agents
    } finally { Close-Connection $conn }
}

function Get-Vehicules {
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT id_vehicule, numero_parc, immatriculation, marque, modele, capacite, conducteur_id, actif FROM Vehicule WHERE actif = 1 ORDER BY numero_parc"
        $reader = $cmd.ExecuteReader()
        $vehicules = @()
        while ($reader.Read()) {
            $vehicules += [PSCustomObject]@{
                id = $reader["id_vehicule"]
                numero_parc = $reader["numero_parc"]
                immatriculation = $reader["immatriculation"]
                marque = $reader["marque"]
                modele = $reader["modele"]
                capacite = $reader["capacite"]
                conducteur_id = $reader["conducteur_id"]
                actif = $reader["actif"]
            }
        }
        return $vehicules
    } finally { Close-Connection $conn }
}

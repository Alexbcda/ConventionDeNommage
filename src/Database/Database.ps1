# ============================================================
# Database.ps1 - VERSION FINALE STABLE
# ============================================================

$script:DbPath  = Join-Path $PSScriptRoot "..\..\Data\gestion.db"
$script:DllPath = Join-Path $PSScriptRoot "..\..\lib\System.Data.SQLite.dll"
. (Join-Path $PSScriptRoot "..\Core\Logger.ps1")

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
        if ($Date -is [System.DBNull]) { return $null }

        $dt =
            if ($Date -is [datetime]) { [datetime]$Date }
            else { [datetime]::Parse($Date) }

        # DateTimePicker.Value est souvent Kind=Unspecified : on l'interprète en heure locale,
        # puis on stocke un timestamp Unix en secondes (UTC) en base.
        if ($dt.Kind -eq [System.DateTimeKind]::Unspecified) {
            $dt = [datetime]::SpecifyKind($dt, [System.DateTimeKind]::Local)
        }

        return [long]([DateTimeOffset]$dt.ToUniversalTime()).ToUnixTimeSeconds()
    } catch {
        return $null
    }
}

function FromDbDate {
    param($Timestamp)
    if (-not $Timestamp) { return $null }
    try {
        if ($Timestamp -is [System.DBNull]) { return $null }

        $ts = [long]$Timestamp

        # Compat: certaines bases stockent en millisecondes.
        # 1e12 ms ~= 2001-09-09, donc au-delà on considère des millisecondes.
        if ($ts -ge 1000000000000) {
            return [DateTimeOffset]::FromUnixTimeMilliseconds($ts).LocalDateTime
        }

        return [DateTimeOffset]::FromUnixTimeSeconds($ts).LocalDateTime
    } catch {
        return $null
    }
}

# ============================================================
# CONNEXION
# ============================================================

function Ensure-SqliteLoaded {
    if ("System.Data.SQLite.SQLiteConnection" -as [type]) { return $true }

    if (-not (Test-Path $script:DllPath)) {
        throw "DLL SQLite manquante: $script:DllPath"
    }

    Add-Type -Path $script:DllPath -ErrorAction Stop
    return $true
}

function Initialize-Database {
    if (-not (Test-Path $script:DllPath)) {
        Write-Host "❌ DLL manquante" -ForegroundColor Red
        Write-Log "[DB] SQLite DLL missing" "ERROR" @{ dllPath = $script:DllPath }
        return $false
    }

    Ensure-SqliteLoaded | Out-Null

    if (-not (Test-Path $script:DbPath)) {
        Write-Log "[DB] Creating database" "INFO" @{ dbPath = $script:DbPath }
        $schema = Get-Content (Join-Path $PSScriptRoot "Schema.sql") -Raw
        $conn = Open-Connection
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $schema
        $null = $cmd.ExecuteNonQuery()
        Close-Connection $conn
        Write-Host "✅ Base créée" -ForegroundColor Green
        Write-Log "[DB] Database created" "INFO" @{ dbPath = $script:DbPath }
    }
    return $true
}

function Open-Connection {
    Ensure-SqliteLoaded | Out-Null
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
    $deTs = ToDbDate $DateEntree
    $dsTs = ToDbDate $DateSortie
    Write-Log "[DB] Add-Agent begin" "INFO" @{
        nom = $Nom; prenom = $Prenom; telephone = $Telephone; email = $Email
        type_contrat = $TypeContrat; base_heures_semaine = $BaseHeuresSemaine
        poste = $Poste; vehicule_id = $VehiculeId; actif = $actif
        date_entree_ts = $deTs; date_sortie_ts = $dsTs
    }

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
        $cmd.Parameters.AddWithValue("@de", $deTs) | Out-Null
        $cmd.Parameters.AddWithValue("@ds", $dsTs) | Out-Null
        $cmd.Parameters.AddWithValue("@tc", $TypeContrat) | Out-Null
        $cmd.Parameters.AddWithValue("@bh", $BaseHeuresSemaine) | Out-Null
        $cmd.Parameters.AddWithValue("@vid", $VehiculeId) | Out-Null
        $cmd.Parameters.AddWithValue("@poste", $Poste) | Out-Null
        $cmd.Parameters.AddWithValue("@actif", $actif) | Out-Null

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $null = $cmd.ExecuteNonQuery()
        $sw.Stop()

        $cmd.CommandText = "SELECT last_insert_rowid()"
        $result = $cmd.ExecuteScalar()
        
        # Extraire le nombre (gère le cas "1 1")
        $resultString = $result.ToString()
        $match = [regex]::Match($resultString, '\d+$')
        $newId =
            if ($match.Success) { [int]$match.Value }
            else { [int]$resultString }

        Write-Log "[DB] Add-Agent success" "INFO" @{ id = $newId; elapsed_ms = $sw.ElapsedMilliseconds }
        return $newId
    } catch {
        Write-Log "[DB] Add-Agent failed" "ERROR" @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
        throw
    }
    finally {
        Close-Connection $conn
    }
}

function Update-Agent {
    param(
        $Id,
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
UPDATE Agent SET
nom=@nom, prenom=@prenom, telephone=@tel, email=@email,
date_entree=@de, date_sortie=@ds,
type_contrat=@tc, base_heures_semaine=@bh,
vehicule_id=@vid, poste=@poste, actif=@actif
WHERE id_agent=@id
"@

        $cmd.Parameters.AddWithValue("@id", [int]$Id) | Out-Null
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

        return $cmd.ExecuteNonQuery()
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
SELECT
  a.id_agent, a.nom, a.prenom, a.telephone, a.email,
  a.date_entree, a.date_sortie, a.type_contrat,
  a.base_heures_semaine, a.poste, a.actif, a.vehicule_id,
  v.numero_parc AS numero_parc
FROM Agent a
LEFT JOIN Vehicule v ON v.id_vehicule = a.vehicule_id
WHERE a.actif = 1
ORDER BY a.nom, a.prenom
"@
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
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
                numero_parc = $reader["numero_parc"]
            }
        }
        $sw.Stop()
        Write-Log "[DB] Get-Agents" "INFO" @{ count = $agents.Count; elapsed_ms = $sw.ElapsedMilliseconds }
        return $agents
    } catch {
        Write-Log "[DB] Get-Agents failed" "ERROR" @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
        throw
    } finally { Close-Connection $conn }
}

function Get-AllAgents {
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
SELECT
  a.id_agent, a.nom, a.prenom, a.telephone, a.email,
  a.date_entree, a.date_sortie, a.type_contrat,
  a.base_heures_semaine, a.poste, a.actif, a.vehicule_id,
  v.numero_parc AS numero_parc
FROM Agent a
LEFT JOIN Vehicule v ON v.id_vehicule = a.vehicule_id
ORDER BY a.nom, a.prenom
"@
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
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
                numero_parc = $reader["numero_parc"]
            }
        }
        $sw.Stop()
        Write-Log "[DB] Get-AllAgents" "INFO" @{ count = $agents.Count; elapsed_ms = $sw.ElapsedMilliseconds }
        return $agents
    } catch {
        Write-Log "[DB] Get-AllAgents failed" "ERROR" @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
        throw
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

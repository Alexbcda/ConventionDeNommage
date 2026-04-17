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

function Test-SafeSqlIdentifier {
    <#
    Identifiant SQL (table/colonne) : lettres, chiffres, underscore uniquement.
    Évite l'injection via PRAGMA / ALTER lorsque des paramètres dynamiques sont utilisés.
    #>
    param([Parameter(Mandatory=$true)] [string]$Name)
    if ($Name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        throw "Identifiant SQL invalide: $Name"
    }
    return $true
}

function Get-SqliteLastInsertRowId {
    param(
        [Parameter(Mandatory=$true)]
        [System.Data.SQLite.SQLiteCommand]$Command
    )
    $Command.Parameters.Clear()
    $Command.CommandText = "SELECT last_insert_rowid()"
    $result = $Command.ExecuteScalar()
    $resultString = $result.ToString()
    $match = [regex]::Match($resultString, '\d+$')
    if ($match.Success) { return [int64]$match.Value }
    return [int64]$resultString
}

function New-VehiculeRowObject {
    param(
        [Parameter(Mandatory=$true)]
        $Reader
    )
    [PSCustomObject]@{
        id = $Reader["id_vehicule"]
        numero_parc = $Reader["numero_parc"]
        immatriculation = $Reader["immatriculation"]
        numero_chassis = $Reader["numero_chassis"]
        marque = $Reader["marque"]
        modele = $Reader["modele"]
        date_mise_circulation = $Reader["date_mise_circulation"]
        date_controle = $Reader["date_controle"]
        date_entree = $Reader["date_entree"]
        date_sortie = $Reader["date_sortie"]
        date_fin_controle_technique = $Reader["date_fin_controle_technique"]
        capacite = $Reader["capacite"]
        conducteur_id = $Reader["conducteur_id"]
        actif = $Reader["actif"]
    }
}

function Test-SqliteColumnExists {
    param(
        [Parameter(Mandatory=$true)] $Connection,
        [Parameter(Mandatory=$true)] [string]$TableName,
        [Parameter(Mandatory=$true)] [string]$ColumnName
    )

    $null = Test-SafeSqlIdentifier $TableName
    $null = Test-SafeSqlIdentifier $ColumnName

    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = "PRAGMA table_info($TableName)"
    $reader = $cmd.ExecuteReader()
    try {
        while ($reader.Read()) {
            if ([string]$reader["name"] -eq $ColumnName) { return $true }
        }
        return $false
    } finally {
        if ($reader) { $reader.Close() }
    }
}

function Add-SqliteColumnIfMissing {
    param(
        [Parameter(Mandatory=$true)] $Connection,
        [Parameter(Mandatory=$true)] [string]$TableName,
        [Parameter(Mandatory=$true)] [string]$ColumnName,
        [Parameter(Mandatory=$true)] [string]$ColumnDefinition
    )

    $null = Test-SafeSqlIdentifier $TableName
    $null = Test-SafeSqlIdentifier $ColumnName
    if ($ColumnDefinition -notmatch '^[A-Za-z0-9_, ()]+$') {
        throw "Définition de colonne SQL non autorisée."
    }

    if (Test-SqliteColumnExists -Connection $Connection -TableName $TableName -ColumnName $ColumnName) {
        return $false
    }

    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = "ALTER TABLE $TableName ADD COLUMN $ColumnName $ColumnDefinition"
    $null = $cmd.ExecuteNonQuery()
    Write-Log "[DB] Added missing column" "INFO" @{ table = $TableName; column = $ColumnName; definition = $ColumnDefinition }
    return $true
}

function Update-VehiculeActifFromDates {
    param([Parameter(Mandatory=$true)] $Connection)

    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = @"
UPDATE Vehicule
SET actif = CASE
    WHEN date_sortie IS NULL OR TRIM(date_sortie) = '' THEN 1
    ELSE 0
END
"@
    $rows = $cmd.ExecuteNonQuery()
    Write-Log "[DB] Synced Vehicule.actif from date_sortie" "INFO" @{ rows = $rows }
}

function Invoke-DatabaseMigrations {
    $conn = Open-Connection
    try {
        $null = Add-SqliteColumnIfMissing -Connection $conn -TableName "Vehicule" -ColumnName "date_entree" -ColumnDefinition "TEXT"
        $null = Add-SqliteColumnIfMissing -Connection $conn -TableName "Vehicule" -ColumnName "date_sortie" -ColumnDefinition "TEXT"
        $null = Add-SqliteColumnIfMissing -Connection $conn -TableName "Vehicule" -ColumnName "date_fin_controle_technique" -ColumnDefinition "TEXT"

        # Données : numéro de parc obligatoire — compléter les lignes historiques vides (avant contrainte métier côté app)
        $cmdFixParc = $conn.CreateCommand()
        $cmdFixParc.CommandText = @"
UPDATE Vehicule
SET numero_parc = TRIM(immatriculation)
WHERE numero_parc IS NULL OR TRIM(numero_parc) = ''
"@
        $null = $cmdFixParc.ExecuteNonQuery()

        Update-VehiculeActifFromDates -Connection $conn
    } finally {
        Close-Connection $conn
    }
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

    Invoke-DatabaseMigrations
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

        $newId = [int](Get-SqliteLastInsertRowId -Command $cmd)

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
    <#
    Véhicules actifs uniquement (actif = 1). Propriétés alignées usage grille / formulaires.
    Typage logique véhicule : id (number), numero_parc, immatriculation, numero_chassis, actif (1|0), etc.
    #>
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
SELECT id_vehicule, numero_parc, immatriculation, numero_chassis, marque, modele,
       date_mise_circulation, date_controle, date_entree, date_sortie,
       date_fin_controle_technique, capacite, conducteur_id, actif
FROM Vehicule
WHERE actif = 1
ORDER BY numero_parc
"@
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $reader = $cmd.ExecuteReader()
        $vehicules = @()
        try {
            while ($reader.Read()) {
                $vehicules += (New-VehiculeRowObject -Reader $reader)
            }
        } finally {
            if ($reader) { $reader.Close() }
        }
        $sw.Stop()
        Write-Log "[DB] Get-Vehicules" "INFO" @{ count = $vehicules.Count; elapsed_ms = $sw.ElapsedMilliseconds }
        return $vehicules
    } catch {
        Write-Log "[DB] Get-Vehicules failed" "ERROR" @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
        throw
    } finally { Close-Connection $conn }
}

function Get-AllVehicules {
    <#
    Tous les véhicules (actifs et inactifs / historique), même schéma que Get-Vehicules.
    #>
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
SELECT id_vehicule, numero_parc, immatriculation, numero_chassis, marque, modele,
       date_mise_circulation, date_controle, date_entree, date_sortie,
       date_fin_controle_technique, capacite, conducteur_id, actif
FROM Vehicule
ORDER BY numero_parc
"@
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $reader = $cmd.ExecuteReader()
        $vehicules = @()
        try {
            while ($reader.Read()) {
                $vehicules += (New-VehiculeRowObject -Reader $reader)
            }
        } finally {
            if ($reader) { $reader.Close() }
        }
        $sw.Stop()
        Write-Log "[DB] Get-AllVehicules" "INFO" @{ count = $vehicules.Count; elapsed_ms = $sw.ElapsedMilliseconds }
        return $vehicules
    } catch {
        Write-Log "[DB] Get-AllVehicules failed" "ERROR" @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
        throw
    } finally { Close-Connection $conn }
}

# ============================================================
# VÉHICULES — persistance uniquement (requêtes paramétrées)
# La validation métier est dans ODM/Vehicules/VehiculesRepository.ps1
# ============================================================

function Add-VehiculeRecord {
    param(
        [string]$NumeroParc,
        [string]$Immatriculation,
        [string]$NumeroChassis,
        $Marque,
        $Modele,
        [string]$DateMiseCirculation,
        $DateControle,
        [string]$DateEntree,
        $DateSortie,
        $DateFinControleTechnique,
        [int]$Actif
    )

    Write-Log "[DB] Add-VehiculeRecord begin" "INFO" @{
        numero_parc = $NumeroParc; immatriculation = $Immatriculation; actif = $Actif
    }

    $conn = Open-Connection
    try {
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
        $cmd.Parameters.AddWithValue("@actif", $Actif) | Out-Null

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $null = $cmd.ExecuteNonQuery()
        $sw.Stop()
        $newId = [int](Get-SqliteLastInsertRowId -Command $cmd)
        Write-Log "[DB] Add-VehiculeRecord success" "INFO" @{ id = $newId; elapsed_ms = $sw.ElapsedMilliseconds }
        return $newId
    } catch {
        Write-Log "[DB] Add-VehiculeRecord failed" "ERROR" @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
        throw
    } finally {
        Close-Connection $conn
    }
}

function Update-VehiculeRecord {
    param(
        [int]$Id,
        [string]$NumeroParc,
        [string]$Immatriculation,
        [string]$NumeroChassis,
        $Marque,
        $Modele,
        [string]$DateMiseCirculation,
        $DateControle,
        [string]$DateEntree,
        $DateSortie,
        $DateFinControleTechnique,
        [int]$Actif
    )

    Write-Log "[DB] Update-VehiculeRecord begin" "INFO" @{ id = $Id; numero_parc = $NumeroParc }

    $conn = Open-Connection
    try {
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
        $cmd.Parameters.AddWithValue("@actif", $Actif) | Out-Null

        $n = $cmd.ExecuteNonQuery()
        Write-Log "[DB] Update-VehiculeRecord success" "INFO" @{ id = $Id; rows = $n }
        return $n
    } catch {
        Write-Log "[DB] Update-VehiculeRecord failed" "ERROR" @{ id = $Id; message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
        throw
    } finally {
        Close-Connection $conn
    }
}

function Remove-VehiculeRecord {
    param([int]$Id)

    Write-Log "[DB] Remove-VehiculeRecord begin" "INFO" @{ id = $Id }

    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "DELETE FROM Vehicule WHERE id_vehicule = @id"
        $cmd.Parameters.AddWithValue("@id", $Id) | Out-Null
        $n = $cmd.ExecuteNonQuery()
        Write-Log "[DB] Remove-VehiculeRecord success" "INFO" @{ id = $Id; rows = $n }
        return $n
    } catch {
        Write-Log "[DB] Remove-VehiculeRecord failed" "ERROR" @{ id = $Id; message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
        throw
    } finally {
        Close-Connection $conn
    }
}

function Get-VehiculeRowById {
    param([int]$Id)

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
            return (New-VehiculeRowObject -Reader $reader)
        } finally {
            if ($reader) { $reader.Close() }
        }
    } finally {
        Close-Connection $conn
    }
}

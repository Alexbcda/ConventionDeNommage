# ============================================================
# Database.ps1 - VERSION FINALE STABLE
# Sécurité : requêtes paramétrées (@param) — pas de concaténation de valeurs utilisateur dans le SQL.
# Identifiants dynamiques (PRAGMA table_info) : validés via Test-SafeSqlIdentifier.
# ============================================================

$script:DbPath = if (-not [string]::IsNullOrWhiteSpace($global:CN_DataRoot)) {
    Join-Path $global:CN_DataRoot 'Data\gestion.db'
} else {
    Join-Path $PSScriptRoot "..\..\Data\gestion.db"
}
$script:DllPath = if (-not [string]::IsNullOrWhiteSpace($global:CN_InstallRoot)) {
    Join-Path $global:CN_InstallRoot 'lib\System.Data.SQLite.dll'
} else {
    Join-Path $PSScriptRoot "..\..\lib\System.Data.SQLite.dll"
}
. (Join-Path $PSScriptRoot '..\Common\DesktopSecurity.ps1')
. (Join-Path $PSScriptRoot "..\Core\Logger.ps1")
. (Join-Path $PSScriptRoot "..\Common\ScalarGuard.ps1")

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
    Write-Log "[DB] Synced Vehicule.actif from date_sortie" "INFO" @{ rows = $rows     }
}

function Initialize-CalendarIndexTable {
    <#
    .SYNOPSIS
        Table d’index planning (fichier Excel importé) : cache SQLite pour résolution date → colonne.
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Connection
    )
    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = @"
CREATE TABLE IF NOT EXISTS calendar_index (
  file_id TEXT NOT NULL,
  sheet TEXT NOT NULL,
  semaine TEXT NOT NULL,
  date TEXT NOT NULL,
  column_index INTEGER NOT NULL,
  header_row INTEGER NOT NULL,
  header_text TEXT
);
"@
    $null = $cmd.ExecuteNonQuery()
    $c2 = $Connection.CreateCommand()
    $c2.CommandText = "CREATE UNIQUE INDEX IF NOT EXISTS uq_calendar_file_date ON calendar_index (file_id, date);"
    $null = $c2.ExecuteNonQuery()
    $c3 = $Connection.CreateCommand()
    $c3.CommandText = "CREATE INDEX IF NOT EXISTS idx_calendar_semaine_date ON calendar_index (semaine, date);"
    $null = $c3.ExecuteNonQuery()
    $c4 = $Connection.CreateCommand()
    $c4.CommandText = "CREATE INDEX IF NOT EXISTS idx_calendar_file_id ON calendar_index (file_id);"
    $null = $c4.ExecuteNonQuery()
}

function Get-CalendarIndexFileRowCount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileId
    )
    $FileId = [string](Normalize-Scalar -Value $FileId -Name "Get-CalendarIndexFileRowCount.file_id")
    Ensure-SqliteLoaded | Out-Null
    $conn = Open-Connection
    try {
        $null = Initialize-CalendarIndexTable -Connection $conn
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT COUNT(1) FROM calendar_index WHERE file_id = @fid"
        $cmd.Parameters.AddWithValue("@fid", $FileId) | Out-Null
        $n = $cmd.ExecuteScalar()
        if ($null -eq $n -or [System.DBNull]::Value.Equals($n)) { return 0L }
        return [int64][Math]::Round([double]("$n"))
    } finally {
        Close-Connection $conn
    }
}

function Get-CalendarIndexPlanningRow {
    <#
    .SYNOPSIS
        Recherche index planning : d’abord (file_id, date, semaine), puis (file_id, date) seul.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileId,
        [Parameter(Mandatory = $true)]
        [string]$DateNorm,
        [Parameter(Mandatory = $true)]
        [string]$Semaine
    )
    $FileId = [string](Normalize-Scalar -Value $FileId -Name "Get-CalendarIndexPlanningRow.file_id")
    $DateNorm = [string](Normalize-Scalar -Value $DateNorm -Name "Get-CalendarIndexPlanningRow.date")
    $Semaine = [string](Normalize-Scalar -Value $Semaine -Name "Get-CalendarIndexPlanningRow.semaine")
    Ensure-SqliteLoaded | Out-Null
    $conn = Open-Connection
    try {
        $null = Initialize-CalendarIndexTable -Connection $conn
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @"
SELECT sheet, column_index, header_row, header_text, semaine
FROM calendar_index
WHERE file_id = @fid AND date = @d AND semaine = @w
LIMIT 1
"@
        $cmd.Parameters.AddWithValue("@fid", $FileId) | Out-Null
        $cmd.Parameters.AddWithValue("@d", $DateNorm) | Out-Null
        $cmd.Parameters.AddWithValue("@w", $Semaine) | Out-Null
        $r = $cmd.ExecuteReader()
        try {
                if ($r.Read()) {
                $hRaw = $r["header_text"]
                $hTxt = if ($null -eq $hRaw -or [System.DBNull]::Value.Equals($hRaw)) { '' } else { [string]$hRaw }
                $ci = (ConvertTo-SafeInt -Value $r["column_index"] -Name "calendar_index.column_index")
                $hr = (ConvertTo-SafeInt -Value $r["header_row"] -Name "calendar_index.header_row")
                return [pscustomobject]@{
                    sheet         = [string](Normalize-Scalar -Value $r["sheet"] -Name "calendar_index.sheet")
                    column_index  = $ci
                    header_row    = $hr
                    header_text   = $hTxt
                    semaine       = [string](Normalize-Scalar -Value $r["semaine"] -Name "calendar_index.semaine")
                }
            }
        } finally { if ($r) { $r.Close() } }

        $cmd2 = $conn.CreateCommand()
        $cmd2.CommandText = @"
SELECT sheet, column_index, header_row, header_text, semaine
FROM calendar_index
WHERE file_id = @fid AND date = @d
LIMIT 1
"@
        $cmd2.Parameters.AddWithValue("@fid", $FileId) | Out-Null
        $cmd2.Parameters.AddWithValue("@d", $DateNorm) | Out-Null
        $r2 = $cmd2.ExecuteReader()
        try {
            if ($r2.Read()) {
                $h2 = $r2["header_text"]
                $h2t = if ($null -eq $h2 -or [System.DBNull]::Value.Equals($h2)) { '' } else { [string]$h2 }
                $ci2 = (ConvertTo-SafeInt -Value $r2["column_index"] -Name "calendar_index.column_index.b")
                $hr2 = (ConvertTo-SafeInt -Value $r2["header_row"] -Name "calendar_index.header_row.b")
                return [pscustomobject]@{
                    sheet         = [string](Normalize-Scalar -Value $r2["sheet"] -Name "calendar_index.sheet.b")
                    column_index  = $ci2
                    header_row    = $hr2
                    header_text   = $h2t
                    semaine       = [string](Normalize-Scalar -Value $r2["semaine"] -Name "calendar_index.semaine.b")
                }
            }
        } finally { if ($r2) { $r2.Close() } }
        return $null
    } finally {
        Close-Connection $conn
    }
}

function Save-CalendarIndexForFile {
    <#
    .SYNOPSIS
        Remplace toutes les entrées d’index pour un file_id (réimport Excel).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileId,
        [Parameter(Mandatory = $true)]
        [object[]]$Rows
    )
    $FileId = [string](Normalize-Scalar -Value $FileId -Name "Save-CalendarIndexForFile.file_id")
    Ensure-SqliteLoaded | Out-Null
    $parent = Split-Path -Parent -Path $script:DbPath
    if (-not [string]::IsNullOrEmpty($parent) -and -not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    if (-not (Test-Path -LiteralPath $script:DbPath)) {
        $null = [System.IO.File]::WriteAllBytes($script:DbPath, [byte[]]@())
    }
    $conn = Open-Connection
    $trans = $null
    try {
        $null = Initialize-CalendarIndexTable -Connection $conn
        $trans = $conn.BeginTransaction()
        $cmdDel = $conn.CreateCommand()
        $cmdDel.Transaction = $trans
        $cmdDel.CommandText = "DELETE FROM calendar_index WHERE file_id = @fid"
        $cmdDel.Parameters.AddWithValue("@fid", $FileId) | Out-Null
        $null = $cmdDel.ExecuteNonQuery()

        $ins = @"
INSERT INTO calendar_index (file_id, sheet, semaine, date, column_index, header_row, header_text)
VALUES (@fid, @s, @sem, @d, @ci, @hr, @ht)
"@
        foreach ($row in $Rows) {
            if ($null -eq $row) { continue }
            $cmdI = $conn.CreateCommand()
            $cmdI.Transaction = $trans
            $cmdI.CommandText = $ins
            $cmdI.Parameters.AddWithValue("@fid", $FileId) | Out-Null
            $cmdI.Parameters.AddWithValue("@s", [string](Normalize-Scalar -Value $row.sheet -Name "row.sheet")) | Out-Null
            $cmdI.Parameters.AddWithValue("@sem", [string](Normalize-Scalar -Value $row.semaine -Name "row.semaine")) | Out-Null
            $cmdI.Parameters.AddWithValue("@d", [string](Normalize-Scalar -Value $row.date -Name "row.date")) | Out-Null
            $ciIns = (ConvertTo-SafeInt -Value $row.column_index -Name "row.column_index")
            $hrIns = (ConvertTo-SafeInt -Value $row.header_row -Name "row.header_row")
            $cmdI.Parameters.AddWithValue("@ci", $ciIns) | Out-Null
            $cmdI.Parameters.AddWithValue("@hr", $hrIns) | Out-Null
            $ht = if ($null -ne $row.PSObject.Properties['header_text'] -and $null -ne $row.header_text) { [string]$row.header_text } else { [string]::Empty }
            $cmdI.Parameters.AddWithValue("@ht", $ht) | Out-Null
            $null = $cmdI.ExecuteNonQuery()
        }
        $trans.Commit()
        $trans = $null
    } catch {
        if ($null -ne $trans) { try { $trans.Rollback() } catch { } }
        throw
    } finally {
        Close-Connection $conn
    }
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

        $null = Initialize-CalendarIndexTable -Connection $conn

        $cmdIdx = $conn.CreateCommand()
        $cmdIdx.CommandText = "CREATE INDEX IF NOT EXISTS idx_vehicule_chassis ON Vehicule(numero_chassis)"
        $null = $cmdIdx.ExecuteNonQuery()

        $cmdIdx2 = $conn.CreateCommand()
        $cmdIdx2.CommandText = "CREATE INDEX IF NOT EXISTS idx_vehicule_immat ON Vehicule(immatriculation)"
        $null = $cmdIdx2.ExecuteNonQuery()

        $cmdIdx3 = $conn.CreateCommand()
        $cmdIdx3.CommandText = "CREATE INDEX IF NOT EXISTS idx_vehicule_parc ON Vehicule(numero_parc)"
        $null = $cmdIdx3.ExecuteNonQuery()

        $cmdIdx4 = $conn.CreateCommand()
        $cmdIdx4.CommandText = "CREATE INDEX IF NOT EXISTS idx_vehicule_actif ON Vehicule(actif)"
        $null = $cmdIdx4.ExecuteNonQuery()

        $cmdIdx5 = $conn.CreateCommand()
        $cmdIdx5.CommandText = "CREATE INDEX IF NOT EXISTS idx_agent_poste ON Agent(poste)"
        $null = $cmdIdx5.ExecuteNonQuery()

        $cmdIdx6 = $conn.CreateCommand()
        $cmdIdx6.CommandText = "CREATE INDEX IF NOT EXISTS idx_agent_actif ON Agent(actif)"
        $null = $cmdIdx6.ExecuteNonQuery()
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
        $schema = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Schema.sql') -Raw -Encoding UTF8
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
    $conn = [System.Data.SQLite.SQLiteConnection]::new("Data Source=$script:DbPath;Version=3;")
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

    Test-CNRateLimit

    if ($Poste -notin $script:POSTES) {
        throw "Poste invalide"
    }

    $actif = if ($DateSortie) { 0 } else { 1 }
    $deTs = ToDbDate $DateEntree
    $dsTs = ToDbDate $DateSortie
    Write-Log "[DB] Add-Agent begin" "INFO" @{
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

    Test-CNRateLimit

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
        $cmd.CommandText = @"
SELECT id_agent, nom, prenom, telephone, email,
       date_entree, date_sortie, type_contrat,
       base_heures_semaine, poste, actif, vehicule_id
FROM Agent WHERE id_agent = @id
"@
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

    Test-CNRateLimit

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
    <#
    Agents : actifs seuls par défaut, ou tous (historique) avec -IncludeInactive.
    Inclut le numéro de parc véhicule via LEFT JOIN.
    #>
    param([switch]$IncludeInactive)
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $baseSql = @"
SELECT
  a.id_agent, a.nom, a.prenom, a.telephone, a.email,
  a.date_entree, a.date_sortie, a.type_contrat,
  a.base_heures_semaine, a.poste, a.actif, a.vehicule_id,
  v.numero_parc AS numero_parc
FROM Agent a
LEFT JOIN Vehicule v ON v.id_vehicule = a.vehicule_id
"@
        $cmd.CommandText = if ($IncludeInactive) {
            "$baseSql ORDER BY a.nom, a.prenom"
        } else {
            "$baseSql WHERE a.actif = 1 ORDER BY a.nom, a.prenom"
        }
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
        $label = if ($IncludeInactive) { "Get-Agents(All)" } else { "Get-Agents(Active)" }
        Write-Log "[DB] $label" "INFO" @{ count = $agents.Count; elapsed_ms = $sw.ElapsedMilliseconds }
        return $agents
    } catch {
        Write-Log "[DB] Get-Agents failed" "ERROR" @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
        throw
    } finally { Close-Connection $conn }
}

function Get-AllAgents {
    <# Alias de compatibilité : retourne tous les agents (actifs + inactifs). #>
    return (Get-Agents -IncludeInactive)
}

function Get-Vehicules {
    <#
    Véhicules : actifs seuls par défaut, ou tous (historique) avec -IncludeInactive.
    Typage logique véhicule : id (number), numero_parc, immatriculation, numero_chassis, actif (1|0), etc.
    #>
    param([switch]$IncludeInactive)
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $baseSql = @"
SELECT id_vehicule, numero_parc, immatriculation, numero_chassis, marque, modele,
       date_mise_circulation, date_controle, date_entree, date_sortie,
       date_fin_controle_technique, capacite, conducteur_id, actif
FROM Vehicule
"@
        $cmd.CommandText = if ($IncludeInactive) {
            "$baseSql ORDER BY numero_parc"
        } else {
            "$baseSql WHERE actif = 1 ORDER BY numero_parc"
        }
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
        $label = if ($IncludeInactive) { "Get-Vehicules(All)" } else { "Get-Vehicules(Active)" }
        Write-Log "[DB] $label" "INFO" @{ count = $vehicules.Count; elapsed_ms = $sw.ElapsedMilliseconds }
        return $vehicules
    } catch {
        Write-Log "[DB] Get-Vehicules failed" "ERROR" @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
        throw
    } finally { Close-Connection $conn }
}

function Get-AllVehicules {
    <# Alias de compatibilité : retourne tous les véhicules (actifs + inactifs). #>
    return (Get-Vehicules -IncludeInactive)
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

    Test-CNRateLimit

    Write-Log "[DB] Add-VehiculeRecord begin" "INFO" @{ actif = $Actif }

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

    Test-CNRateLimit

    Write-Log "[DB] Update-VehiculeRecord begin" "INFO" @{ id = $Id }

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

    Test-CNRateLimit

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

function Test-VehiculeRecordExistsByColumn {
    <#
    .SYNOPSIS
        Targeted duplicate check: SELECT 1 WHERE column = @value LIMIT 1.
        O(1) index lookup instead of full table scan.
    #>
    param(
        [Parameter(Mandatory=$true)] [string]$ColumnName,
        [Parameter(Mandatory=$true)] [string]$Value,
        [int]$ExcludeId = 0
    )
    $null = Test-SafeSqlIdentifier $ColumnName
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        if ($ExcludeId -gt 0) {
            $cmd.CommandText = "SELECT 1 FROM Vehicule WHERE $ColumnName = @val AND id_vehicule != @eid LIMIT 1"
            $cmd.Parameters.AddWithValue("@eid", $ExcludeId) | Out-Null
        } else {
            $cmd.CommandText = "SELECT 1 FROM Vehicule WHERE $ColumnName = @val LIMIT 1"
        }
        $cmd.Parameters.AddWithValue("@val", $Value) | Out-Null
        $result = $cmd.ExecuteScalar()
        return ($null -ne $result -and -not [System.DBNull]::Value.Equals($result))
    } finally {
        Close-Connection $conn
    }
}

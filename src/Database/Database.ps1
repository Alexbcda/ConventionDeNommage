# Database.ps1 - Version complète avec toutes les tables

$script:DbPath = Join-Path $PSScriptRoot "..\..\Data\gestion.db"
$script:DllPath = Join-Path $PSScriptRoot "..\..\lib\System.Data.SQLite.dll"

# Liste centralisée des postes
$script:POSTES = @(
    'Collecteur',
    'Trieur',
    'Assistant planning',
    'REX',
    'Commercial',
    'Responsable des exploitations'
)

function Get-PostesListe { return $script:POSTES }

function Initialize-Database {
    if (-not (Test-Path $script:DllPath)) {
        Write-Host "❌ DLL manquante: $script:DllPath" -ForegroundColor Red
        return $false
    }

    Add-Type -Path $script:DllPath -ErrorAction Stop

    if (-not (Test-Path $script:DbPath)) {
        $schemaPath = Join-Path $PSScriptRoot "Schema.sql"
        if (-not (Test-Path $schemaPath)) {
            Write-Host "❌ Fichier Schema.sql manquant: $schemaPath" -ForegroundColor Red
            return $false
        }
        
        $schema = Get-Content $schemaPath -Raw
        $conn = Open-Connection
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $schema
        $cmd.ExecuteNonQuery()
        $conn.Close()
        Write-Host "✅ Base créée: $script:DbPath" -ForegroundColor Green
    }
    
    Ensure-PosteColumn
    return $true
}

function Ensure-PosteColumn {
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "PRAGMA table_info(Agent)"
        $reader = $cmd.ExecuteReader()
        $hasPosteColumn = $false
        while ($reader.Read()) {
            if ($reader["name"] -eq "poste") { $hasPosteColumn = $true }
        }
        $reader.Close()
        if (-not $hasPosteColumn) {
            $cmd.CommandText = "ALTER TABLE Agent ADD COLUMN poste TEXT DEFAULT 'Collecteur'"
            $cmd.ExecuteNonQuery()
            Write-Host "✅ Colonne poste ajoutée" -ForegroundColor Green
        }
    } catch { Write-Host "Note: Table Agent peut ne pas exister" -ForegroundColor Yellow }
    finally { Close-Connection $conn }
}

function Open-Connection {
    $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$script:DbPath;Version=3;")
    $conn.Open()
    return $conn
}

function Close-Connection { param($Connection) if ($Connection) { $Connection.Close() } }

# ================================
# AGENTS
# ================================

function Get-Agents {
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT id_agent, nom, prenom, telephone, email, date_entree, date_sortie, type_contrat, base_heures_semaine, poste, actif, vehicule_id FROM Agent WHERE actif = 1 ORDER BY nom, prenom"
        $reader = $cmd.ExecuteReader()
        $agents = @()
        while ($reader.Read()) {
            $agents += [PSCustomObject]@{
                id = $reader["id_agent"]; nom = $reader["nom"]; prenom = $reader["prenom"]
                telephone = $reader["telephone"]; email = $reader["email"]
                date_entree = $reader["date_entree"]; date_sortie = $reader["date_sortie"]
                type_contrat = $reader["type_contrat"]; base_heures_semaine = $reader["base_heures_semaine"]
                poste = $reader["poste"]; actif = $reader["actif"]; vehicule_id = $reader["vehicule_id"]
            }
        }
        return $agents
    } finally { Close-Connection $conn }
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
                id = $reader["id_agent"]; nom = $reader["nom"]; prenom = $reader["prenom"]
                telephone = $reader["telephone"]; email = $reader["email"]
                date_entree = $reader["date_entree"]; date_sortie = $reader["date_sortie"]
                type_contrat = $reader["type_contrat"]; base_heures_semaine = $reader["base_heures_semaine"]
                poste = $reader["poste"]; actif = $reader["actif"]; vehicule_id = $reader["vehicule_id"]
            }
        }
        return $null
    } finally { Close-Connection $conn }
}

function Add-Agent {
    param($Nom, $Prenom, $Telephone, $Email, $DateEntree, $DateSortie, $TypeContrat, $BaseHeuresSemaine = 35, $VehiculeId = $null, $Poste = "Collecteur")
    if ($Poste -notin $script:POSTES) { throw "Poste invalide" }
    $actif = if ($DateSortie) { 0 } else { 1 }
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "INSERT INTO Agent (nom, prenom, telephone, email, date_entree, date_sortie, type_contrat, base_heures_semaine, vehicule_id, poste, actif) VALUES (@nom, @prenom, @tel, @email, @date_entree, @date_sortie, @type_contrat, @base_heures, @vehicule_id, @poste, @actif)"
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
        $cmd.ExecuteNonQuery()
        $cmd.CommandText = "SELECT last_insert_rowid()"
        return $cmd.ExecuteScalar()
    } finally { Close-Connection $conn }
}

function Update-Agent {
    param($Id, $Nom, $Prenom, $Telephone, $Email, $DateEntree, $DateSortie, $TypeContrat, $BaseHeuresSemaine, $VehiculeId, $Poste)
    if ($Poste -notin $script:POSTES) { throw "Poste invalide" }
    $actif = if ($DateSortie) { 0 } else { 1 }
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "UPDATE Agent SET nom=@nom, prenom=@prenom, telephone=@tel, email=@email, date_entree=@date_entree, date_sortie=@date_sortie, type_contrat=@type_contrat, base_heures_semaine=@base_heures, vehicule_id=@vehicule_id, poste=@poste, actif=@actif WHERE id_agent=@id"
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
    } finally { Close-Connection $conn }
}

function Remove-Agent {
    param($Id)
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "DELETE FROM Agent WHERE id_agent = @id"
        $cmd.Parameters.AddWithValue("@id", $Id) | Out-Null
        return $cmd.ExecuteNonQuery()
    } finally { Close-Connection $conn }
}

# ================================
# VEHICULES
# ================================

function Get-Vehicules {
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT id_vehicule, immatriculation, marque, modele, capacite, actif FROM Vehicule WHERE actif = 1 ORDER BY immatriculation"
        $reader = $cmd.ExecuteReader()
        $vehicules = @()
        while ($reader.Read()) {
            $vehicules += [PSCustomObject]@{
                id = $reader["id_vehicule"]
                immatriculation = $reader["immatriculation"]
                marque = $reader["marque"]
                modele = $reader["modele"]
                capacite = $reader["capacite"]
                actif = $reader["actif"]
            }
        }
        return $vehicules
    } finally { Close-Connection $conn }
}

function Get-VehiculeById {
    param($Id)
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT * FROM Vehicule WHERE id_vehicule = @id"
        $cmd.Parameters.AddWithValue("@id", $Id) | Out-Null
        $reader = $cmd.ExecuteReader()
        if ($reader.Read()) {
            return [PSCustomObject]@{
                id = $reader["id_vehicule"]
                immatriculation = $reader["immatriculation"]
                marque = $reader["marque"]
                modele = $reader["modele"]
                capacite = $reader["capacite"]
                actif = $reader["actif"]
            }
        }
        return $null
    } finally { Close-Connection $conn }
}

function Add-Vehicule {
    param($Immatriculation, $Marque, $Modele, $Capacite)
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "INSERT INTO Vehicule (immatriculation, marque, modele, capacite, actif) VALUES (@immat, @marque, @modele, @capacite, 1)"
        $cmd.Parameters.AddWithValue("@immat", $Immatriculation) | Out-Null
        $cmd.Parameters.AddWithValue("@marque", $Marque) | Out-Null
        $cmd.Parameters.AddWithValue("@modele", $Modele) | Out-Null
        $cmd.Parameters.AddWithValue("@capacite", $Capacite) | Out-Null
        $cmd.ExecuteNonQuery()
        $cmd.CommandText = "SELECT last_insert_rowid()"
        return $cmd.ExecuteScalar()
    } finally { Close-Connection $conn }
}

function Update-Vehicule {
    param($Id, $Immatriculation, $Marque, $Modele, $Capacite)
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "UPDATE Vehicule SET immatriculation=@immat, marque=@marque, modele=@modele, capacite=@capacite WHERE id_vehicule=@id"
        $cmd.Parameters.AddWithValue("@id", $Id) | Out-Null
        $cmd.Parameters.AddWithValue("@immat", $Immatriculation) | Out-Null
        $cmd.Parameters.AddWithValue("@marque", $Marque) | Out-Null
        $cmd.Parameters.AddWithValue("@modele", $Modele) | Out-Null
        $cmd.Parameters.AddWithValue("@capacite", $Capacite) | Out-Null
        return $cmd.ExecuteNonQuery()
    } finally { Close-Connection $conn }
}

function Remove-Vehicule {
    param($Id)
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "DELETE FROM Vehicule WHERE id_vehicule = @id"
        $cmd.Parameters.AddWithValue("@id", $Id) | Out-Null
        return $cmd.ExecuteNonQuery()
    } finally { Close-Connection $conn }
}

# ================================
# PLANNING
# ================================

function Get-Plannings {
    param($DateDebut = $null, $DateFin = $null)
    $conn = Open-Connection
    try {
        $query = "SELECT p.id_planning, p.agent_id, a.nom as agent_nom, a.prenom as agent_prenom, p.date, p.heure_debut, p.heure_fin, p.tournee_id, p.statut FROM Planning p JOIN Agent a ON p.agent_id = a.id_agent WHERE 1=1"
        if ($DateDebut) { $query += " AND p.date >= @date_debut" }
        if ($DateFin) { $query += " AND p.date <= @date_fin" }
        $query += " ORDER BY p.date, p.heure_debut"
        
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $query
        if ($DateDebut) { $cmd.Parameters.AddWithValue("@date_debut", $DateDebut) | Out-Null }
        if ($DateFin) { $cmd.Parameters.AddWithValue("@date_fin", $DateFin) | Out-Null }
        
        $reader = $cmd.ExecuteReader()
        $plannings = @()
        while ($reader.Read()) {
            $plannings += [PSCustomObject]@{
                id = $reader["id_planning"]
                agent_id = $reader["agent_id"]
                agent_nom = $reader["agent_nom"]
                agent_prenom = $reader["agent_prenom"]
                date = $reader["date"]
                heure_debut = $reader["heure_debut"]
                heure_fin = $reader["heure_fin"]
                tournee_id = $reader["tournee_id"]
                statut = $reader["statut"]
            }
        }
        return $plannings
    } finally { Close-Connection $conn }
}

function Add-Planning {
    param($AgentId, $Date, $HeureDebut, $HeureFin, $TourneeId = $null, $Statut = "Planifié")
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "INSERT INTO Planning (agent_id, date, heure_debut, heure_fin, tournee_id, statut) VALUES (@agent_id, @date, @heure_debut, @heure_fin, @tournee_id, @statut)"
        $cmd.Parameters.AddWithValue("@agent_id", $AgentId) | Out-Null
        $cmd.Parameters.AddWithValue("@date", $Date) | Out-Null
        $cmd.Parameters.AddWithValue("@heure_debut", $HeureDebut) | Out-Null
        $cmd.Parameters.AddWithValue("@heure_fin", $HeureFin) | Out-Null
        $cmd.Parameters.AddWithValue("@tournee_id", $TourneeId) | Out-Null
        $cmd.Parameters.AddWithValue("@statut", $Statut) | Out-Null
        $cmd.ExecuteNonQuery()
        $cmd.CommandText = "SELECT last_insert_rowid()"
        return $cmd.ExecuteScalar()
    } finally { Close-Connection $conn }
}

function Update-Planning {
    param($Id, $AgentId, $Date, $HeureDebut, $HeureFin, $TourneeId, $Statut)
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "UPDATE Planning SET agent_id=@agent_id, date=@date, heure_debut=@heure_debut, heure_fin=@heure_fin, tournee_id=@tournee_id, statut=@statut WHERE id_planning=@id"
        $cmd.Parameters.AddWithValue("@id", $Id) | Out-Null
        $cmd.Parameters.AddWithValue("@agent_id", $AgentId) | Out-Null
        $cmd.Parameters.AddWithValue("@date", $Date) | Out-Null
        $cmd.Parameters.AddWithValue("@heure_debut", $HeureDebut) | Out-Null
        $cmd.Parameters.AddWithValue("@heure_fin", $HeureFin) | Out-Null
        $cmd.Parameters.AddWithValue("@tournee_id", $TourneeId) | Out-Null
        $cmd.Parameters.AddWithValue("@statut", $Statut) | Out-Null
        return $cmd.ExecuteNonQuery()
    } finally { Close-Connection $conn }
}

function Remove-Planning {
    param($Id)
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "DELETE FROM Planning WHERE id_planning = @id"
        $cmd.Parameters.AddWithValue("@id", $Id) | Out-Null
        return $cmd.ExecuteNonQuery()
    } finally { Close-Connection $conn }
}

# ================================
# TOURNEES
# ================================

function Get-Tournees {
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT id_tournee, nom, secteur, duree_estimee, actif FROM Tournee WHERE actif = 1 ORDER BY nom"
        $reader = $cmd.ExecuteReader()
        $tournees = @()
        while ($reader.Read()) {
            $tournees += [PSCustomObject]@{
                id = $reader["id_tournee"]
                nom = $reader["nom"]
                secteur = $reader["secteur"]
                duree_estimee = $reader["duree_estimee"]
                actif = $reader["actif"]
            }
        }
        return $tournees
    } finally { Close-Connection $conn }
}

function Add-Tournee {
    param($Nom, $Secteur, $DureeEstimee)
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "INSERT INTO Tournee (nom, secteur, duree_estimee, actif) VALUES (@nom, @secteur, @duree, 1)"
        $cmd.Parameters.AddWithValue("@nom", $Nom) | Out-Null
        $cmd.Parameters.AddWithValue("@secteur", $Secteur) | Out-Null
        $cmd.Parameters.AddWithValue("@duree", $DureeEstimee) | Out-Null
        $cmd.ExecuteNonQuery()
        $cmd.CommandText = "SELECT last_insert_rowid()"
        return $cmd.ExecuteScalar()
    } finally { Close-Connection $conn }
}

function Remove-Tournee {
    param($Id)
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "DELETE FROM Tournee WHERE id_tournee = @id"
        $cmd.Parameters.AddWithValue("@id", $Id) | Out-Null
        return $cmd.ExecuteNonQuery()
    } finally { Close-Connection $conn }
}

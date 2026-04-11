# Database.ps1
$script:DbPath = Join-Path $PSScriptRoot "..\..\Data\gestion.db"
$script:DllPath = Join-Path $PSScriptRoot "..\..\lib\System.Data.SQLite.dll"

function Initialize-Database {
    if (-not (Test-Path $script:DllPath)) {
        Write-Host "❌ DLL manquante: $script:DllPath" -ForegroundColor Red
        return $false
    }
    
    Write-Host "[DB] Chargement de SQLite depuis: $script:DllPath" -ForegroundColor Cyan
    Add-Type -Path $script:DllPath -ErrorAction Stop
    
    if (-not (Test-Path $script:DbPath)) {
        $schema = Get-Content (Join-Path $PSScriptRoot "Schema.sql") -Raw
        $conn = Open-Connection
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $schema
        $cmd.ExecuteNonQuery()
        $conn.Close()
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
    param($Connection)
    if ($Connection) { $Connection.Close() }
}

function Get-Agents {
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT id_agent, nom, prenom, telephone, email, date_entree, date_sortie, type_contrat, base_heures_semaine, actif FROM Agent ORDER BY nom, prenom"
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
                actif = $reader["actif"]
            }
        }
        return $agents
    } finally {
        Close-Connection $conn
    }
}

function Get-Vehicules {
    $conn = Open-Connection
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT id_vehicule, immatriculation, numero_parc, marque, modele, capacite, actif, statut FROM Vehicule ORDER BY numero_parc"
        $reader = $cmd.ExecuteReader()
        $vehicules = @()
        while ($reader.Read()) {
            $vehicules += [PSCustomObject]@{
                id = $reader["id_vehicule"]
                immatriculation = $reader["immatriculation"]
                numero_parc = $reader["numero_parc"]
                marque = $reader["marque"]
                modele = $reader["modele"]
                capacite = $reader["capacite"]
                actif = $reader["actif"]
                statut = $reader["statut"]
            }
        }
        return $vehicules
    } finally {
        Close-Connection $conn
    }
}

function Add-Agent {
    param($Nom, $Prenom, $Telephone, $Email, $DateEntree, $TypeContrat, $BaseHeuresSemaine = 35)
    
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

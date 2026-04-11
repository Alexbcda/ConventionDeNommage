# Database.ps1
$script:DbPath = Join-Path $PSScriptRoot "..\..\Data\gestion.db"
$script:DllPath = Join-Path $PSScriptRoot "..\..\lib\System.Data.SQLite.dll"

function Initialize-Database {
    if (-not (Test-Path $script:DllPath)) {
        Write-Host "❌ DLL manquante: $script:DllPath" -ForegroundColor Red
        return $false
    }
    Add-Type -Path $script:DllPath
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

function Get-Agents {
    $conn = Open-Connection
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT id_agent, nom, prenom, telephone FROM Agent WHERE actif = 1"
    $reader = $cmd.ExecuteReader()
    $agents = @()
    while ($reader.Read()) {
        $agents += [PSCustomObject]@{
            id = $reader["id_agent"]
            nom = $reader["nom"]
            prenom = $reader["prenom"]
            telephone = $reader["telephone"]
        }
    }
    $conn.Close()
    return $agents
}

function Add-Agent {
    param($Nom, $Prenom, $Telephone)
    $conn = Open-Connection
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "INSERT INTO Agent (nom, prenom, telephone, actif) VALUES (@nom, @prenom, @tel, 1)"
    $cmd.Parameters.AddWithValue("@nom", $Nom) | Out-Null
    $cmd.Parameters.AddWithValue("@prenom", $Prenom) | Out-Null
    $cmd.Parameters.AddWithValue("@tel", $Telephone) | Out-Null
    $cmd.ExecuteNonQuery()
    $cmd.CommandText = "SELECT last_insert_rowid()"
    $id = $cmd.ExecuteScalar()
    $conn.Close()
    return $id
}

function Get-Vehicules {
    $conn = Open-Connection
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = "SELECT id_vehicule, immatriculation, numero_parc FROM Vehicule WHERE actif = 1"
    $reader = $cmd.ExecuteReader()
    $vehicules = @()
    while ($reader.Read()) {
        $vehicules += [PSCustomObject]@{
            id = $reader["id_vehicule"]
            immatriculation = $reader["immatriculation"]
            numero_parc = $reader["numero_parc"]
        }
    }
    $conn.Close()
    return $vehicules
}




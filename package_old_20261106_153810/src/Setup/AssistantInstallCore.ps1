# AssistantInstallCore.ps1 - Initialisation BDD minimale pour l'installateur (sans Logger / WinForms)
# Dot-source depuis InstallDir apres copie des fichiers.

function Initialize-AssistantInstallDatabase {
    param(
        [Parameter(Mandatory = $true)][string]$AppRoot,
        [Parameter(Mandatory = $true)][hashtable]$CentreConfig
    )

    $dllPath = Join-Path $AppRoot 'lib\System.Data.SQLite.dll'
    $dbPath = Join-Path $AppRoot 'Data\gestion.db'
    $schemaPath = Join-Path $AppRoot 'src\Database\Schema.sql'

    if (-not (Test-Path -LiteralPath $dllPath)) {
        throw "DLL SQLite introuvable : $dllPath"
    }

    $dataDir = Split-Path -Parent $dbPath
    if (-not (Test-Path -LiteralPath $dataDir)) {
        $null = New-Item -ItemType Directory -Path $dataDir -Force
    }

    if (-not ('System.Data.SQLite.SQLiteConnection' -as [type])) {
        Add-Type -Path $dllPath -ErrorAction Stop
    }

    $newDb = -not (Test-Path -LiteralPath $dbPath)
    if ($newDb) {
        if (-not (Test-Path -LiteralPath $schemaPath)) {
            throw "Schema.sql introuvable : $schemaPath"
        }
        $schema = Get-Content -LiteralPath $schemaPath -Raw -Encoding UTF8
        $conn = [System.Data.SQLite.SQLiteConnection]::new("Data Source=$dbPath;Version=3;")
        $conn.Open()
        try {
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = $schema
            $null = $cmd.ExecuteNonQuery()
        }
        finally {
            $conn.Close()
            $conn.Dispose()
        }
    }

    $conn = [System.Data.SQLite.SQLiteConnection]::new("Data Source=$dbPath;Version=3;")
    $conn.Open()
    try {
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = @'
CREATE TABLE IF NOT EXISTS AppConfig (
    key TEXT PRIMARY KEY,
    value TEXT,
    date_modification DATETIME DEFAULT CURRENT_TIMESTAMP
);
'@
        $null = $cmd.ExecuteNonQuery()

        foreach ($entry in $CentreConfig.GetEnumerator()) {
            if ([string]::IsNullOrWhiteSpace([string]$entry.Key)) { continue }
            $set = $conn.CreateCommand()
            $set.CommandText = @'
INSERT OR REPLACE INTO AppConfig (key, value, date_modification)
VALUES (@key, @value, CURRENT_TIMESTAMP)
'@
            $null = $set.Parameters.AddWithValue('@key', [string]$entry.Key)
            $null = $set.Parameters.AddWithValue('@value', $(if ($null -eq $entry.Value) { '' } else { [string]$entry.Value }))
            $null = $set.ExecuteNonQuery()
            $set.Dispose()
        }
    }
    finally {
        $conn.Close()
        $conn.Dispose()
    }
}

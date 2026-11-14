# Logger.ps1 - Système de journalisation

$script:logFile = Join-Path $PSScriptRoot "..\Logs\app.log"

$_deskSec = Join-Path $PSScriptRoot "..\Common\DesktopSecurity.ps1"
if (Test-Path -LiteralPath $_deskSec) {
    . $_deskSec
}

function Ensure-LogPath {
    try {
        $dir = Split-Path -Parent $script:logFile
        if (-not (Test-Path $dir)) {
            $null = New-Item -Path $dir -ItemType Directory -Force
        }
    } catch {}
}

function Format-LogData {
    param($Data)
    if ($null -eq $Data) { return "" }
    try {
        if ($Data -is [string]) { return $Data }
        return ($Data | ConvertTo-Json -Compress -Depth 6)
    } catch {
        try { return ($Data | Out-String).Trim() } catch { return "" }
    }
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        $Data = $null
    )
    
    Ensure-LogPath
    if (Get-Command Rotate-LogIfNeeded -ErrorAction SilentlyContinue) {
        Rotate-LogIfNeeded -LogFile $script:logFile
    }
    # Ne pas utiliser Get-Date: une fonction Get-Date du projet peut masquer la cmdlet.
    $timestamp = [datetime]::Now.ToString("yyyy-MM-dd HH:mm:ss")
    $dataText = Format-LogData $Data
    $suffix = if ([string]::IsNullOrWhiteSpace($dataText)) { "" } else { " | data=$dataText" }
    $logEntry = "[$timestamp] [$Level] [pid=$PID] $Message$suffix"
    
    # Afficher dans la console (si console disponible et mode non silencieux)
    $echoConsole = $true
    if ($global:SuppressConsoleOutput -eq $true -and $env:CN_VERBOSE -notin @('1', 'true', 'TRUE', 'yes', 'YES')) {
        $echoConsole = $false
    }
    if ($echoConsole) {
        try {
            Write-Host $logEntry
        }
        catch { }
    }
    
    # Écrire dans le fichier
    try {
        Add-Content -Path $script:logFile -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

try {
    Export-ModuleMember -Function Write-Log
} catch {
    # Logger.ps1 est souvent dot-sourcé (pas importé comme module) : on ignore l'export.
}

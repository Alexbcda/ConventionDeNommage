# Logger.ps1 - Système de journalisation

$script:logFile = Join-Path $PSScriptRoot "..\Logs\app.log"

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Afficher dans la console (si console disponible)
    try {
        Write-Host $logEntry
    } catch {}
    
    # Écrire dans le fichier
    try {
        Add-Content -Path $script:logFile -Value $logEntry -ErrorAction SilentlyContinue
    } catch {}
}

function Clear-Log {
    Remove-Item $script:logFile -ErrorAction SilentlyContinue
    Write-Log "Log effacé" "INFO"
}

Export-ModuleMember -Function Write-Log, Clear-Log

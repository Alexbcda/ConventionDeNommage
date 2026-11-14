# Selection aleatoire d'un agent Trieur actif (certificat destruction).

function Initialize-CnsTrieurDbAccess {
    if ($script:CnsTrieurDbLoadAttempted) { return }
    $script:CnsTrieurDbLoadAttempted = $true
    $dbScript = Join-Path $PSScriptRoot '..\..\Database\Database.ps1'
    if (-not (Test-Path -LiteralPath $dbScript)) {
        Write-Warning ("[TRIEUR] Database.ps1 introuvable : {0}" -f $dbScript)
        return
    }
    try {
        . $dbScript
    }
    catch {
        Write-Warning ("[TRIEUR] Chargement Database.ps1 echoue : {0}" -f $_.Exception.Message)
    }
}

function Get-RandomTrieurFromDatabase {
    <#
    .SYNOPSIS
        Retourne @{ Nom; Prenom } d'un trieur actif choisi aleatoirement, ou fallback Non assigne.
    #>
    Initialize-CnsTrieurDbAccess

    $fallback = @{
        Nom    = 'Non assigne'
        Prenom = 'Non assigne'
    }

    if (Get-Command Open-Connection -ErrorAction SilentlyContinue) {
        $conn = $null
        try {
            $conn = Open-Connection
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = @"
SELECT nom, prenom
FROM Agent
WHERE actif = 1 AND poste = 'Trieur'
ORDER BY RANDOM()
LIMIT 1
"@
            $reader = $cmd.ExecuteReader()
            if ($reader.Read()) {
                $nom = [string]$reader['nom']
                $prenom = [string]$reader['prenom']
                $reader.Close()
                if (-not [string]::IsNullOrWhiteSpace($nom) -and -not [string]::IsNullOrWhiteSpace($prenom)) {
                    $result = @{ Nom = $nom.Trim(); Prenom = $prenom.Trim() }
                    $logMsg = "[TRIEUR] Selection aleatoire : {0} {1}" -f $result.Prenom, $result.Nom
                    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                        Write-Log $logMsg 'INFO'
                    }
                    else {
                        Write-Host $logMsg -ForegroundColor DarkCyan
                    }
                    return $result
                }
            }
            else {
                $reader.Close()
            }
        }
        catch {
            Write-Warning ("[TRIEUR] Requete SQL echouee : {0}" -f $_.Exception.Message)
        }
        finally {
            if ($null -ne $conn -and (Get-Command Close-Connection -ErrorAction SilentlyContinue)) {
                Close-Connection $conn
            }
        }
    }

    if (Get-Command Get-Agents -ErrorAction SilentlyContinue) {
        try {
            $trieurs = @(Get-Agents | Where-Object {
                    $null -ne $_ -and [string]$_.poste -eq 'Trieur'
                })
            if ($trieurs.Count -gt 0) {
                $chosen = $trieurs[(Get-Random -Minimum 0 -Maximum $trieurs.Count)]
                $result = @{
                    Nom    = ([string]$chosen.nom).Trim()
                    Prenom = ([string]$chosen.prenom).Trim()
                }
                $logMsg = "[TRIEUR] Selection aleatoire : {0} {1}" -f $result.Prenom, $result.Nom
                if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                    Write-Log $logMsg 'INFO'
                }
                else {
                    Write-Host $logMsg -ForegroundColor DarkCyan
                }
                return $result
            }
        }
        catch {
            Write-Warning ("[TRIEUR] Get-Agents echoue : {0}" -f $_.Exception.Message)
        }
    }

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log '[TRIEUR] Aucun trieur actif — fallback Non assigne' 'WARN'
    }
    return $fallback
}

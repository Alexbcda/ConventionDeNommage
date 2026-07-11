# ConfigManager.ps1 - Gestion centralisee des configurations centre (Phase 8)

if (-not (Get-Command Get-AppConfig -ErrorAction SilentlyContinue)) {
    $dbScript = Join-Path $PSScriptRoot '..\Database\Database.ps1'
    if (Test-Path -LiteralPath $dbScript) {
        . $dbScript
    }
}
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    $loggerScript = Join-Path $PSScriptRoot 'Logger.ps1'
    if (Test-Path -LiteralPath $loggerScript) {
        . $loggerScript
    }
}

function Get-ConfigRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..\config')).Path
}

function Get-CentresList {
    <#
    .SYNOPSIS
        Retourne la liste des centres disponibles depuis config/centres.json.
    #>
    $configPath = Join-Path (Get-ConfigRoot) 'centres.json'

    if (-not (Test-Path -LiteralPath $configPath)) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[ConfigManager] centres.json introuvable' 'WARN' @{ path = $configPath }
        }
        return @()
    }

    try {
        $json = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return @($json.centres)
    }
    catch {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[ConfigManager] Erreur lecture centres.json' 'ERROR' @{ message = $_.Exception.Message }
        }
        return @()
    }
}

function Get-CentreConfig {
    <#
    .SYNOPSIS
        Recupere la configuration d'un centre par son ID.
    .PARAMETER CentreId
        Identifiant du centre (argonay, fontaine, bourg-en-bresse, valence, etc.)
    #>
    param([Parameter(Mandatory = $true)][string]$CentreId)

    $centreIdNorm = $CentreId.Trim().ToLowerInvariant()
    $fromList = Get-CentresList | Where-Object { $_.id -eq $centreIdNorm } | Select-Object -First 1
    if ($fromList) { return $fromList }

    $individualPath = Join-Path (Get-ConfigRoot) ("{0}.json" -f $centreIdNorm)
    if (Test-Path -LiteralPath $individualPath) {
        try {
            return Get-Content -LiteralPath $individualPath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log '[ConfigManager] Erreur lecture config individuelle' 'WARN' @{ path = $individualPath }
            }
        }
    }

    return $null
}

function Get-CurrentCentre {
    <#
    .SYNOPSIS
        Retourne le centre actuellement configure (BDD ou correspondance URL).
    #>
    if (-not (Get-Command Get-AppConfig -ErrorAction SilentlyContinue)) {
        return $null
    }

    $storedId = Get-AppConfig -Key 'CentreId'
    $storedName = Get-AppConfig -Key 'CentreName'
    $currentUrl = Get-AppConfig -Key 'SharePointApiUrl'

    if (-not [string]::IsNullOrWhiteSpace($storedId)) {
        $byId = Get-CentreConfig -CentreId $storedId
        if ($byId) { return $byId }
    }

    if (-not [string]::IsNullOrWhiteSpace($currentUrl)) {
        $urlNorm = $currentUrl.Trim()
        foreach ($centre in Get-CentresList) {
            if ($centre.sharePointApiUrl -eq $urlNorm) {
                return $centre
            }
        }

        return [PSCustomObject]@{
            id               = 'custom'
            name             = if ([string]::IsNullOrWhiteSpace($storedName)) { 'Personnalise' } else { $storedName }
            sharePointApiUrl = $urlNorm
            default          = $false
        }
    }

    return $null
}

function Set-CurrentCentre {
    <#
    .SYNOPSIS
        Configure le centre actif dans la BDD.
    .PARAMETER CentreId
        Identifiant du centre (argonay, fontaine, bourg-en-bresse, valence, etc.)
    #>
    param([Parameter(Mandatory = $true)][string]$CentreId)

    $centre = Get-CentreConfig -CentreId $CentreId
    if (-not $centre) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[ConfigManager] Centre inconnu' 'ERROR' @{ centreId = $CentreId }
        }
        return $false
    }

    if (-not (Get-Command Set-AppConfig -ErrorAction SilentlyContinue)) {
        return $false
    }

    Set-AppConfig -Key 'SharePointApiUrl' -Value ([string]$centre.sharePointApiUrl)
    Set-AppConfig -Key 'CentreId' -Value ([string]$centre.id)
    Set-AppConfig -Key 'CentreName' -Value ([string]$centre.name)

    if (-not [string]::IsNullOrWhiteSpace([string]$centre.planningFileName)) {
        Set-AppConfig -Key 'PlanningFileName' -Value ([string]$centre.planningFileName)
    }

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log '[ConfigManager] Centre configure' 'INFO' @{ centre = $centre.name; id = $centre.id }
    }
    return $true
}

function Sync-CentreMetadataFromAppConfig {
    <#
    .SYNOPSIS
        Synchronise CentreId/CentreName depuis centres.json si l'URL SharePoint correspond.
    #>
    if (-not (Get-Command Get-AppConfig -ErrorAction SilentlyContinue)) {
        return $null
    }

    $currentUrl = Get-AppConfig -Key 'SharePointApiUrl'
    if ([string]::IsNullOrWhiteSpace($currentUrl)) {
        return $null
    }

    $matched = $null
    foreach ($centre in Get-CentresList) {
        if ($centre.sharePointApiUrl -eq $currentUrl.Trim()) {
            $matched = $centre
            break
        }
    }

    if ($matched) {
        $existingId = Get-AppConfig -Key 'CentreId'
        if ($existingId -ne $matched.id) {
            Set-AppConfig -Key 'CentreId' -Value ([string]$matched.id)
        }
        $existingName = Get-AppConfig -Key 'CentreName'
        if ($existingName -ne $matched.name) {
            Set-AppConfig -Key 'CentreName' -Value ([string]$matched.name)
        }
    }

    return (Get-CurrentCentre)
}

function Initialize-CentreFromAppConfig {
    <#
    .SYNOPSIS
        Initialise la configuration centre au demarrage (variable script + sync BDD).
    #>
    $centre = Sync-CentreMetadataFromAppConfig
    if ($centre) {
        $script:CurrentCentre = $centre
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[ConfigManager] Centre actif' 'INFO' @{ name = $centre.name; id = $centre.id }
        }
        return $centre
    }

    $envCentre = $env:CN_CENTRE_ID
    if (-not [string]::IsNullOrWhiteSpace($envCentre)) {
        if (Set-CurrentCentre -CentreId $envCentre) {
            $script:CurrentCentre = Get-CurrentCentre
            return $script:CurrentCentre
        }
    }

    $script:CurrentCentre = $null
    return $null
}

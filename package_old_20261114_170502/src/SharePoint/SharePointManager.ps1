# Point d'entree SharePoint — reutilise CnsSharePointConnector.ps1 (pas de duplication de logique).

$connectorScript = Join-Path $PSScriptRoot '..\Common\CnsSharePointConnector.ps1'
if (-not (Test-Path -LiteralPath $connectorScript)) {
    throw "SharePointManager.ps1 : CnsSharePointConnector.ps1 introuvable ($connectorScript)"
}
. $connectorScript

function Import-SharePointFile {
    <#
    .SYNOPSIS
        Telecharge un fichier planning SharePoint vers un chemin local via l'URL Graph configuree.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [string]$SharePointUrl
    )

    if (-not (Test-SharePointConnection -Interactive)) {
        throw 'Impossible de se connecter a SharePoint'
    }

    if ([string]::IsNullOrWhiteSpace($SharePointUrl)) {
        $SharePointUrl = Get-SharePointPlanningUrl
    }
    if ([string]::IsNullOrWhiteSpace($SharePointUrl)) {
        throw 'Aucune URL SharePoint configuree'
    }

    $ok = Get-SharePointPlanningFile -Url $SharePointUrl -LocalPath $DestinationPath
    if (-not $ok) {
        throw 'Echec du telechargement SharePoint'
    }
    return $true
}

function Get-SharePointDriveItem {
    <#
    .SYNOPSIS
        Retourne les metadonnees du site et du drive principal (diagnostic).
    #>
    [CmdletBinding()]
    param(
        [string]$SiteUrl = $script:CnsSharePointSiteUrl
    )

    if (-not (Test-SharePointConnection -Interactive)) {
        throw 'Impossible de se connecter a SharePoint'
    }

    Import-CnsSharePointGraphModule
    $site = Get-MgSite -SiteId $SiteUrl -ErrorAction Stop
    $drives = Get-MgSiteDrive -SiteId $site.Id -ErrorAction Stop
    $drive = $drives | Where-Object { $_.Name -eq 'Documents' } | Select-Object -First 1
    if (-not $drive) {
        $drive = $drives | Select-Object -First 1
    }
    $items = Get-MgDriveItem -DriveId $drive.Id -ErrorAction Stop

    return @{
        Site  = $site
        Drive = $drive
        Items = $items
    }
}

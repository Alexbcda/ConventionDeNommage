# SharePoint / Microsoft Graph — telechargement de fichiers (module autonome, hors pipeline principal).
#Requires -Version 5.1

function script:Write-SharePointLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    $prefix = '[SHAREPOINT]'
    switch ($Level) {
        'WARN' { Write-Warning ("{0} {1}" -f $prefix, $Message) }
        'ERROR' { Write-Warning ("{0} {1}" -f $prefix, $Message) }
        default { Write-Host ("{0} {1}" -f $prefix, $Message) }
    }
}

function Ensure-MicrosoftGraphModule {
    <#
    .SYNOPSIS
        Charge uniquement les commandes Graph necessaires (evite la limite 4096 fonctions de PS 5.1).
    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    param()

    $requiredCommands = @('Connect-MgGraph', 'Get-MgContext', 'Invoke-MgGraphRequest')
    $allPresent = $true
    foreach ($cmd in $requiredCommands) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            $allPresent = $false
            break
        }
    }
    if ($allPresent) {
        return $true
    }

    $authMod = Get-Module -ListAvailable -Name Microsoft.Graph.Authentication -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1
    $graphMod = Get-Module -ListAvailable -Name Microsoft.Graph -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $authMod -and -not $graphMod) {
        Write-Warning '[SHAREPOINT] Le module Microsoft Graph est requis mais pas installe.'
        Write-Warning 'Installez-le : Install-Module Microsoft.Graph -Scope CurrentUser -Force'
        Write-Warning 'Puis chargez uniquement les commandes necessaires : Import-Module Microsoft.Graph.Authentication -Function Connect-MgGraph, Get-MgContext, Invoke-MgGraphRequest'
        return $false
    }

    try {
        $toImport = @($requiredCommands | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
        if ($toImport.Count -gt 0 -and $authMod) {
            Import-Module Microsoft.Graph.Authentication -Function $toImport -ErrorAction Stop
        }

        $stillMissing = @($requiredCommands | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
        if ($stillMissing.Count -gt 0 -and $graphMod) {
            Import-Module Microsoft.Graph -Function $stillMissing -ErrorAction Stop
        }
    }
    catch {
        Write-Warning ("[SHAREPOINT] Echec import leger Microsoft Graph : {0}" -f $_.Exception.Message)
        Write-Warning 'Import-Module Microsoft.Graph.Authentication -Function Connect-MgGraph, Get-MgContext, Invoke-MgGraphRequest'
        return $false
    }

    foreach ($cmd in $requiredCommands) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            Write-Warning ("[SHAREPOINT] Commande Graph introuvable apres import leger : {0}" -f $cmd)
            Write-Warning 'Import-Module Microsoft.Graph.Authentication -Function Connect-MgGraph, Get-MgContext, Invoke-MgGraphRequest'
            return $false
        }
    }

    return $true
}

function Get-SharePointGraphRequiredScopes {
    return @('Files.Read.All', 'Sites.Read.All')
}

function Test-SharePointGraphContextReady {
    <#
    .SYNOPSIS
        Verifie qu'une session Graph active couvre les scopes requis.
    #>
    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if ($null -eq $ctx) { return $false }
    if ([string]::IsNullOrWhiteSpace([string]$ctx.Account)) { return $false }

    $required = @(Get-SharePointGraphRequiredScopes)
    $scopes = @($ctx.Scopes | ForEach-Object { [string]$_ })
    if ($scopes.Count -lt 1) {
        return $true
    }

    foreach ($need in $required) {
        $found = $false
        foreach ($s in $scopes) {
            if ($s -eq $need -or $s -like "*$need") {
                $found = $true
                break
            }
        }
        if (-not $found) { return $false }
    }
    return $true
}

function Connect-SharePointGraph {
    <#
    .SYNOPSIS
        Connecte a Microsoft Graph avec les scopes requis pour lire les fichiers SharePoint.
    .OUTPUTS
        [bool] $true si connecte, $false sinon
    #>
    [CmdletBinding()]
    param()

    if (-not (Ensure-MicrosoftGraphModule)) {
        return $false
    }

    if (Test-SharePointGraphContextReady) {
        $ctx = Get-MgContext
        script:Write-SharePointLog -Message ("Deja connecte a Microsoft Graph (compte={0})." -f $ctx.Account)
        return $true
    }

    $scopes = Get-SharePointGraphRequiredScopes
    try {
        script:Write-SharePointLog -Message ("Connexion interactive Microsoft Graph (scopes: {0})..." -f ($scopes -join ', '))
        Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop | Out-Null
        $ctx = Get-MgContext
        if ($null -eq $ctx -or [string]::IsNullOrWhiteSpace([string]$ctx.Account)) {
            script:Write-SharePointLog -Message 'Connect-MgGraph termine mais Get-MgContext est vide.' -Level 'WARN'
            return $false
        }
        script:Write-SharePointLog -Message ("Connexion reussie (compte={0})." -f $ctx.Account)
        return $true
    }
    catch {
        script:Write-SharePointLog -Message ("Connexion echouee : {0}" -f $_.Exception.Message) -Level 'ERROR'
        return $false
    }
}

function Get-SharePointGraphEncodedItemPath {
    <#
    .SYNOPSIS
        Encode un chemin d'item drive (segments separes par /, espaces -> %20).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    $path = $FilePath.Trim().TrimStart('/').TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($path)) { return '' }
    $segments = $path -split '/'
    return (($segments | ForEach-Object { [System.Uri]::EscapeDataString($_.Trim()) }) -join '/')
}

function Get-SharePointGraphDriveItemContentUri {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteUrl,
        [Parameter(Mandatory = $true)]
        [string]$FilePathOnSharePoint
    )
    $siteRef = $SiteUrl.Trim().Trim('/')
    $itemPath = Get-SharePointGraphEncodedItemPath -FilePath $FilePathOnSharePoint
    return ('https://graph.microsoft.com/v1.0/sites/{0}/drive/root:/{1}:/content' -f $siteRef, $itemPath)
}

function Get-SharePointGraphDriveItemMetadataUri {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteUrl,
        [Parameter(Mandatory = $true)]
        [string]$FilePathOnSharePoint
    )
    $siteRef = $SiteUrl.Trim().Trim('/')
    $itemPath = Get-SharePointGraphEncodedItemPath -FilePath $FilePathOnSharePoint
    return ('https://graph.microsoft.com/v1.0/sites/{0}/drive/root:/{1}' -f $siteRef, $itemPath)
}

function Get-SharePointFile {
    <#
    .SYNOPSIS
        Telecharge un fichier depuis SharePoint via Microsoft Graph.
    .PARAMETER SiteUrl
        Ex: "naevaelisealpes.sharepoint.com:/sites/EliseAlpes"
    .PARAMETER FilePathOnSharePoint
        Ex: "Planning GRENOBLE 2026.xlsm"
    .PARAMETER DestinationPath
        Chemin local de destination.
    .OUTPUTS
        [bool] $true si telechargement reussi, $false sinon
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteUrl,
        [Parameter(Mandatory = $true)]
        [string]$FilePathOnSharePoint,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    if (-not (Connect-SharePointGraph)) {
        return $false
    }

    $destAbs = [System.IO.Path]::GetFullPath($DestinationPath)
    $destDir = Split-Path -Parent $destAbs
    if (-not (Test-Path -LiteralPath $destDir)) {
        $null = New-Item -ItemType Directory -Path $destDir -Force -ErrorAction Stop
    }

    $contentUri = Get-SharePointGraphDriveItemContentUri -SiteUrl $SiteUrl -FilePathOnSharePoint $FilePathOnSharePoint
    script:Write-SharePointLog -Message ("Telechargement Graph : {0}" -f $FilePathOnSharePoint)
    script:Write-SharePointLog -Message ("URI : {0}" -f $contentUri)

    try {
        if (Test-Path -LiteralPath $destAbs) {
            Remove-Item -LiteralPath $destAbs -Force -ErrorAction SilentlyContinue
        }

        if (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue) {
            Invoke-MgGraphRequest -Uri $contentUri -Method GET -OutputFilePath $destAbs -ErrorAction Stop | Out-Null
        }
        else {
            throw 'Invoke-MgGraphRequest indisponible apres import Microsoft.Graph.'
        }
    }
    catch {
        script:Write-SharePointLog -Message ("Telechargement echoue : {0}" -f $_.Exception.Message) -Level 'ERROR'
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            script:Write-SharePointLog -Message ("Detail Graph : {0}" -f $_.ErrorDetails.Message) -Level 'WARN'
        }
        return $false
    }

    if (-not (Test-Path -LiteralPath $destAbs -PathType Leaf)) {
        script:Write-SharePointLog -Message 'Fichier local non cree apres telechargement.' -Level 'ERROR'
        return $false
    }

    $len = (Get-Item -LiteralPath $destAbs).Length
    if ($len -lt 1) {
        script:Write-SharePointLog -Message 'Fichier telecharge vide.' -Level 'ERROR'
        return $false
    }

    script:Write-SharePointLog -Message ("Telechargement reussi : {0} ({1:N0} octets)" -f $destAbs, $len)
    return $true
}

function Test-SharePointDriveItemExists {
    <#
    .SYNOPSIS
        Verifie l'existence d'un fichier SharePoint via les metadonnees Graph (sans telechargement complet).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteUrl,
        [Parameter(Mandatory = $true)]
        [string]$FilePathOnSharePoint
    )

    if (-not (Connect-SharePointGraph)) {
        return $false
    }

    $metaUri = Get-SharePointGraphDriveItemMetadataUri -SiteUrl $SiteUrl -FilePathOnSharePoint $FilePathOnSharePoint
    try {
        $item = Invoke-MgGraphRequest -Uri $metaUri -Method GET -ErrorAction Stop
        if ($null -eq $item) { return $false }
        script:Write-SharePointLog -Message ("Fichier trouve sur SharePoint : {0} (id={1})" -f $FilePathOnSharePoint, $item.id)
        return $true
    }
    catch {
        script:Write-SharePointLog -Message ("Fichier introuvable ou acces refuse : {0}" -f $_.Exception.Message) -Level 'WARN'
        return $false
    }
}

function Test-SharePointConnection {
    <#
    .SYNOPSIS
        Test complet : connexion Graph + verification existence + telechargement du fichier planning.
    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    param(
        [string]$SiteUrl = $(if (-not [string]::IsNullOrWhiteSpace($env:CN_SHAREPOINT_SITE_URL)) { $env:CN_SHAREPOINT_SITE_URL.Trim() } else { 'naevaelisealpes.sharepoint.com:/sites/EliseAlpes' }),
        [string]$FilePathOnSharePoint = $(if (-not [string]::IsNullOrWhiteSpace($env:CN_SHAREPOINT_PLANNING_FILE)) { $env:CN_SHAREPOINT_PLANNING_FILE.Trim() } else { 'Planning GRENOBLE 2026.xlsm' }),
        [string]$DestinationPath = $(Join-Path $env:TEMP 'Planning_GRENOBLE_2026.xlsm')
    )

    script:Write-SharePointLog -Message 'Debut du test de connexion SharePoint / Graph.'

    if (-not (Connect-SharePointGraph)) {
        return $false
    }

    if (-not (Test-SharePointDriveItemExists -SiteUrl $SiteUrl -FilePathOnSharePoint $FilePathOnSharePoint)) {
        script:Write-SharePointLog -Message 'Echec verification existence du fichier sur SharePoint.' -Level 'ERROR'
        return $false
    }

    return (Get-SharePointFile -SiteUrl $SiteUrl -FilePathOnSharePoint $FilePathOnSharePoint -DestinationPath $DestinationPath)
}

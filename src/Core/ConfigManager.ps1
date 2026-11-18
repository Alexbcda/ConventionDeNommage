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

# Lot 1 / multi-centre — cles stables SharePoint (globales legacy + scopes .{centreId}).
$script:SharePointIdConfigKeyBases = @(
    'SharePointDriveId'
    'SharePointItemId'
    'SharePointLastValidatedAt'
    'SharePointSourceUrl'
)

function Get-SharePointStableIdsCentreKey {
    param([AllowNull()][AllowEmptyString()][string]$CentreId)
    if ([string]::IsNullOrWhiteSpace($CentreId)) { return $null }
    return $CentreId.Trim().ToLowerInvariant()
}

function Resolve-SharePointStableIdsCentreId {
    param([AllowNull()][AllowEmptyString()][string]$CentreId)
    $cid = Get-SharePointStableIdsCentreKey -CentreId $CentreId
    if (-not [string]::IsNullOrWhiteSpace($cid) -and $cid -ne 'custom') { return $cid }
    if (Get-Command Get-AppConfig -ErrorAction SilentlyContinue) {
        $cid = Get-SharePointStableIdsCentreKey -CentreId (Get-AppConfig -Key 'CentreId')
        if (-not [string]::IsNullOrWhiteSpace($cid) -and $cid -ne 'custom') { return $cid }
    }
    if (Get-Command Get-CurrentCentre -ErrorAction SilentlyContinue) {
        $c = Get-CurrentCentre
        if ($null -ne $c -and -not [string]::IsNullOrWhiteSpace([string]$c.id) -and [string]$c.id -ne 'custom') {
            return (Get-SharePointStableIdsCentreKey -CentreId ([string]$c.id))
        }
    }
    return $null
}

function Get-SharePointStableIdAppConfigKey {
    <#
    .SYNOPSIS
        Cle AppConfig pour un ID SharePoint : SharePointDriveId.{centre} ou legacy globale.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('SharePointDriveId', 'SharePointItemId', 'SharePointLastValidatedAt', 'SharePointSourceUrl')]
        [string]$BaseKey,
        [AllowNull()][AllowEmptyString()][string]$CentreId
    )
    $cid = Resolve-SharePointStableIdsCentreId -CentreId $CentreId
    if ([string]::IsNullOrWhiteSpace($cid)) { return $BaseKey }
    return ('{0}.{1}' -f $BaseKey, $cid)
}

function Clear-SharePointLegacyGlobalStableIdKeys {
    <#
    .SYNOPSIS
        Vide les anciennes cles globales (pre-multi-centre) pour eviter un ID orphelin au switch.
    #>
    if (-not (Get-Command Set-AppConfig -ErrorAction SilentlyContinue)) { return }
    foreach ($base in @($script:SharePointIdConfigKeyBases)) {
        Set-AppConfig -Key $base -Value ''
    }
}

function Get-GraphClientId {
    <#
    .SYNOPSIS
        Lit le ClientId Entra (App Registration ASSISTANT) depuis AppConfig.
    .OUTPUTS
        [string] ClientId, ou $null si absent/vide.
    #>
    if (-not (Get-Command Get-AppConfig -ErrorAction SilentlyContinue)) {
        return $null
    }
    $id = Get-AppConfig -Key 'GraphClientId'
    if ([string]::IsNullOrWhiteSpace($id)) { return $null }
    return $id.Trim()
}

function Format-GraphClientIdMasked {
    <#
    .SYNOPSIS
        Masque un Client ID pour affichage UI (4 premiers + 4 derniers caracteres).
    #>
    param([AllowNull()][AllowEmptyString()][string]$ClientId)
    if ([string]::IsNullOrWhiteSpace($ClientId)) { return '' }
    $id = $ClientId.Trim()
    if ($id.Length -lt 8) { return '****' }
    return ('{0}...{1}' -f $id.Substring(0, 4), $id.Substring($id.Length - 4))
}

function Set-GraphClientId {
    <#
    .SYNOPSIS
        Enregistre le ClientId Entra (App Registration ASSISTANT) dans AppConfig.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ClientId
    )
    if ([string]::IsNullOrWhiteSpace($ClientId)) {
        throw 'Client ID ASSISTANT invalide : valeur vide.'
    }
    $trimmed = $ClientId.Trim()
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($trimmed, [ref]$parsed)) {
        throw 'Client ID ASSISTANT invalide : format GUID attendu.'
    }
    if (-not (Get-Command Set-AppConfig -ErrorAction SilentlyContinue)) {
        throw 'Set-AppConfig indisponible — impossible d''enregistrer GraphClientId.'
    }
    Set-AppConfig -Key 'GraphClientId' -Value $trimmed
    return $trimmed
}

function Get-CnsUnrecognizedCentreDisplayName {
    return 'Centre non reconnu'
}

function Get-ConfigRoot {
    $configDir = Join-Path $PSScriptRoot '..\..\config'
    if (-not (Test-Path -LiteralPath $configDir)) {
        return $configDir
    }
    return (Resolve-Path -LiteralPath $configDir).Path
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

function Test-CentreAppConfigurationComplete {
    <#
    .SYNOPSIS
        True si CentreId, CentreName et SharePointApiUrl sont renseignes en BDD.
    #>
    if (-not (Get-Command Get-AppConfig -ErrorAction SilentlyContinue)) {
        return $false
    }
    $storedId = Get-AppConfig -Key 'CentreId'
    $storedName = Get-AppConfig -Key 'CentreName'
    $currentUrl = Get-AppConfig -Key 'SharePointApiUrl'
    return (-not [string]::IsNullOrWhiteSpace($storedId)) `
        -and (-not [string]::IsNullOrWhiteSpace($storedName)) `
        -and (-not [string]::IsNullOrWhiteSpace($currentUrl))
}

function Get-SharePointStableIds {
    <#
    .SYNOPSIS
        Lit les identifiants SharePoint stables (scopes par centre si CentreId connu).
    .OUTPUTS
        [pscustomobject] DriveId, ItemId, PlanningFileName, LastValidatedAt, SourceUrl, CentreId
        (valeur $null si cle absente). Sans centre resolu : cles globales legacy.
    #>
    param([AllowNull()][AllowEmptyString()][string]$CentreId)

    if (-not (Get-Command Get-AppConfig -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{
            DriveId          = $null
            ItemId           = $null
            PlanningFileName = $null
            LastValidatedAt  = $null
            SourceUrl        = $null
            CentreId         = $null
        }
    }

    $resolvedCentre = Resolve-SharePointStableIdsCentreId -CentreId $CentreId
    $driveId = Get-AppConfig -Key (Get-SharePointStableIdAppConfigKey -BaseKey 'SharePointDriveId' -CentreId $CentreId)
    $itemId = Get-AppConfig -Key (Get-SharePointStableIdAppConfigKey -BaseKey 'SharePointItemId' -CentreId $CentreId)
    $planningFileName = Get-AppConfig -Key 'PlanningFileName'
    $lastValidatedAt = Get-AppConfig -Key (Get-SharePointStableIdAppConfigKey -BaseKey 'SharePointLastValidatedAt' -CentreId $CentreId)
    $sourceUrl = Get-AppConfig -Key (Get-SharePointStableIdAppConfigKey -BaseKey 'SharePointSourceUrl' -CentreId $CentreId)

    return [pscustomobject]@{
        DriveId          = $(if ([string]::IsNullOrWhiteSpace($driveId)) { $null } else { [string]$driveId })
        ItemId           = $(if ([string]::IsNullOrWhiteSpace($itemId)) { $null } else { [string]$itemId })
        PlanningFileName = $(if ([string]::IsNullOrWhiteSpace($planningFileName)) { $null } else { [string]$planningFileName })
        LastValidatedAt  = $(if ([string]::IsNullOrWhiteSpace($lastValidatedAt)) { $null } else { [string]$lastValidatedAt })
        SourceUrl        = $(if ([string]::IsNullOrWhiteSpace($sourceUrl)) { $null } else { [string]$sourceUrl })
        CentreId         = $resolvedCentre
    }
}

function Set-SharePointStableIds {
    <#
    .SYNOPSIS
        Ecrit les identifiants SharePoint stables (scopes par centre si CentreId connu).
    .NOTES
        Ne modifie pas SharePointApiUrl, CentreId, CentreName.
        Seuls les parametres explicitement fournis sont ecrits.
        Sans centre resolu : cles globales legacy (retrocompatibilite Lot 1).
    #>
    param(
        [AllowNull()][string]$DriveId,
        [AllowNull()][string]$ItemId,
        [AllowNull()][string]$PlanningFileName,
        [AllowNull()][string]$LastValidatedAt,
        [AllowNull()][string]$SourceUrl,
        [AllowNull()][AllowEmptyString()][string]$CentreId
    )

    if (-not (Get-Command Set-AppConfig -ErrorAction SilentlyContinue)) {
        return
    }

    if ($PSBoundParameters.ContainsKey('DriveId')) {
        Set-AppConfig -Key (Get-SharePointStableIdAppConfigKey -BaseKey 'SharePointDriveId' -CentreId $CentreId) -Value $DriveId
    }
    if ($PSBoundParameters.ContainsKey('ItemId')) {
        Set-AppConfig -Key (Get-SharePointStableIdAppConfigKey -BaseKey 'SharePointItemId' -CentreId $CentreId) -Value $ItemId
    }
    if ($PSBoundParameters.ContainsKey('PlanningFileName')) {
        Set-AppConfig -Key 'PlanningFileName' -Value $PlanningFileName
    }
    if ($PSBoundParameters.ContainsKey('LastValidatedAt')) {
        Set-AppConfig -Key (Get-SharePointStableIdAppConfigKey -BaseKey 'SharePointLastValidatedAt' -CentreId $CentreId) -Value $LastValidatedAt
    }
    if ($PSBoundParameters.ContainsKey('SourceUrl')) {
        Set-AppConfig -Key (Get-SharePointStableIdAppConfigKey -BaseKey 'SharePointSourceUrl' -CentreId $CentreId) -Value $SourceUrl
    }
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

        $fallbackName = Get-CnsUnrecognizedCentreDisplayName
        if (-not [string]::IsNullOrWhiteSpace($storedName) -and $storedName -ne 'Personnalise') {
            $fallbackName = $storedName
        }

        return [PSCustomObject]@{
            id               = 'custom'
            name             = $fallbackName
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

    $centreIdNorm = $CentreId.Trim().ToLowerInvariant()
    $centre = Get-CentreConfig -CentreId $centreIdNorm
    if (-not $centre) {
        $msg = "Centre '$CentreId' non trouve dans centres.json"
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[ConfigManager] Centre inconnu' 'ERROR' @{ centreId = $CentreId; message = $msg }
        }
        Write-Error "[Centre] $msg"
        return $false
    }

    if (-not (Get-Command Set-AppConfig -ErrorAction SilentlyContinue)) {
        Write-Error '[Centre] Set-AppConfig indisponible'
        return $false
    }

    Set-AppConfig -Key 'CentreId' -Value ([string]$centre.id)
    Set-AppConfig -Key 'CentreName' -Value ([string]$centre.name)
    Set-AppConfig -Key 'SharePointApiUrl' -Value ([string]$centre.sharePointApiUrl)

    if (-not [string]::IsNullOrWhiteSpace([string]$centre.planningFileName)) {
        Set-AppConfig -Key 'PlanningFileName' -Value ([string]$centre.planningFileName)
    }

    # IDs scopes isoles par centre : ne pas effacer SharePointDriveId.{nouveauCentre}.
    # Purge uniquement les anciennes cles globales orphelines.
    Clear-SharePointLegacyGlobalStableIdKeys

    $checkId = Get-AppConfig -Key 'CentreId'
    $checkName = Get-AppConfig -Key 'CentreName'
    $checkUrl = Get-AppConfig -Key 'SharePointApiUrl'
    if ($checkId -ne [string]$centre.id -or $checkName -ne [string]$centre.name -or $checkUrl -ne [string]$centre.sharePointApiUrl) {
        Write-Error '[Centre] Echec de verification post-ecriture (CentreId/CentreName/SharePointApiUrl)'
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[ConfigManager] Echec verification post-ecriture' 'ERROR' @{
                expectedId   = $centre.id
                actualId     = $checkId
                expectedName = $centre.name
                actualName   = $checkName
            }
        }
        return $false
    }

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log '[ConfigManager] Centre configure' 'INFO' @{ centre = $centre.name; id = $centre.id }
    }
    Write-Host ("[Centre] Centre configure : {0}" -f $centre.name) -ForegroundColor Green
    return $true
}

function Repair-CentreConfiguration {
    <#
    .SYNOPSIS
        Reassocie l'installation a un centre connu (par id ou par URL SharePoint).
    #>
    param([AllowNull()][AllowEmptyString()][string]$NewCentreId = $null)

    if (-not (Get-Command Get-AppConfig -ErrorAction SilentlyContinue)) {
        Write-Error '[Centre] Get-AppConfig indisponible'
        return $false
    }

    if (-not [string]::IsNullOrWhiteSpace($NewCentreId)) {
        return (Set-CurrentCentre -CentreId $NewCentreId)
    }

    $currentUrl = Get-AppConfig -Key 'SharePointApiUrl'
    if (-not [string]::IsNullOrWhiteSpace($currentUrl)) {
        $urlNorm = $currentUrl.Trim()
        foreach ($centre in Get-CentresList) {
            if ($centre.sharePointApiUrl -eq $urlNorm) {
                return (Set-CurrentCentre -CentreId ([string]$centre.id))
            }
        }
    }

    $storedId = Get-AppConfig -Key 'CentreId'
    if (-not [string]::IsNullOrWhiteSpace($storedId) -and (Get-CentreConfig -CentreId $storedId)) {
        return (Set-CurrentCentre -CentreId $storedId)
    }

    Write-Warning '[Centre] URL non reconnue. Utilise Repair-CentreConfiguration -NewCentreId <id> ou reinstalle avec -Centre <nom>'
    return $false
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
    if ($centre -and [string]$centre.id -eq 'custom') {
        if (Repair-CentreConfiguration) {
            $centre = Get-CurrentCentre
        }
    }

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

function Show-ConfigureCentreDialog {
    <#
    .SYNOPSIS
        Dialogue WinForms pour selectionner un centre connu et l'enregistrer en BDD.
    .OUTPUTS
        [bool] True si le centre a ete configure.
    #>
    $centres = @(Get-CentresList)
    if ($centres.Count -lt 1) {
        [System.Windows.Forms.MessageBox]::Show(
            'Aucun centre disponible (config\centres.json introuvable ou vide).',
            'Configuration centre',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return $false
    }

    $current = Get-CurrentCentre
    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'Configurer le centre'
    $form.Size = [System.Drawing.Size]::new(460, 220)
    $form.StartPosition = 'CenterParent'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $lbl = [System.Windows.Forms.Label]::new()
    $lbl.Text = 'Selectionnez le centre de cette installation :'
    $lbl.Location = [System.Drawing.Point]::new(15, 15)
    $lbl.Size = [System.Drawing.Size]::new(410, 24)
    $form.Controls.Add($lbl)

    $combo = [System.Windows.Forms.ComboBox]::new()
    $combo.DropDownStyle = 'DropDownList'
    $combo.Location = [System.Drawing.Point]::new(15, 45)
    $combo.Size = [System.Drawing.Size]::new(410, 28)
    $selectedIndex = 0
    for ($i = 0; $i -lt $centres.Count; $i++) {
        $c = $centres[$i]
        [void]$combo.Items.Add([string]$c.name)
        if ($null -ne $current -and [string]$current.id -eq [string]$c.id) {
            $selectedIndex = $i
        }
    }
    $combo.SelectedIndex = $selectedIndex
    $form.Controls.Add($combo)

    $btnOk = [System.Windows.Forms.Button]::new()
    $btnOk.Text = 'Enregistrer'
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnOk.Location = [System.Drawing.Point]::new(250, 120)
    $btnOk.Size = [System.Drawing.Size]::new(85, 32)
    $form.Controls.Add($btnOk)

    $btnCancel = [System.Windows.Forms.Button]::new()
    $btnCancel.Text = 'Annuler'
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $btnCancel.Location = [System.Drawing.Point]::new(340, 120)
    $btnCancel.Size = [System.Drawing.Size]::new(85, 32)
    $form.Controls.Add($btnCancel)

    $form.AcceptButton = $btnOk
    $form.CancelButton = $btnCancel

    if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        $form.Dispose()
        return $false
    }

    $idx = $combo.SelectedIndex
    $form.Dispose()
    if ($idx -lt 0 -or $idx -ge $centres.Count) {
        return $false
    }

    return (Set-CurrentCentre -CentreId ([string]$centres[$idx].id))
}

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

# Connexion SharePoint / Microsoft Graph — telechargement du planning Excel.

if (-not (Get-Command Get-AppConfig -ErrorAction SilentlyContinue)) {
    $dbScript = Join-Path $PSScriptRoot '..\Database\Database.ps1'
    if (Test-Path -LiteralPath $dbScript) {
        . $dbScript
    }
}

$script:CnsSharePointGraphScopes = @('Files.Read.All', 'Sites.Read.All', 'offline_access')
$script:CnsGraphUserAgent = 'ASSISTANT/1.0 (PowerShell; Microsoft Graph)'
$script:CnsSharePointPlanningFileName = $(if (-not [string]::IsNullOrWhiteSpace($env:CN_SHAREPOINT_PLANNING_FILE)) {
        $env:CN_SHAREPOINT_PLANNING_FILE.Trim()
    }
    else {
        'Planning ARGONAY 2026.xlsm'
    })
$script:CnsSharePointSiteUrl = $(if (-not [string]::IsNullOrWhiteSpace($env:CN_SHAREPOINT_SITE_URL)) {
        $env:CN_SHAREPOINT_SITE_URL.Trim()
    }
    else {
        'naevaelisealpes.sharepoint.com:/sites/EliseAlpesArgonay'
    })
$script:CnsSharePointCacheDir = Join-Path $env:LOCALAPPDATA 'ASSISTANT\SharePoint'
$script:CnsSharePointLocalDir = Join-Path $script:CnsSharePointCacheDir 'local'
$script:CnsSharePointSyncMetaPath = Join-Path $script:CnsSharePointCacheDir 'sync-meta.json'
$script:CnsSharePointRegistryRoot = 'HKCU:\Software\ASSISTANT\Planning'
$script:CnsSharePointConnectCancel = $false
$script:CnsSharePointGraphModuleChecked = $false
$script:CnsSharePointGraphAvailable = $false
$script:CnsSharePointConnectionState = $null
$script:CnsSharePointAuthInProgress = $false
$script:CnsSharePointDeviceBrowserOpened = $false

function Get-SharePointPlanningUrl {
    <#
    .SYNOPSIS
        Résout l'URL Graph du fichier planning (évaluée à chaque appel).
    .DESCRIPTION
        Priorité : AppConfig (SharePointApiUrl) > CN_SHAREPOINT_CONTENT_URL > $null.
        Pas de fallback centre codé en dur : une URL non configurée retourne $null.
    .OUTPUTS
        [string] URL Graph, ou $null si non configurée.

    .EXAMPLE
        # Test 1 — aucune config (BDD vide + env vide) :
        #   Get-SharePointPlanningUrl   # => $null
    .EXAMPLE
        # Test 2 — config BDD :
        #   Set-AppConfig -Key "SharePointApiUrl" -Value "https://graph.microsoft.com/v1.0/sites/xxx"
        #   Get-SharePointPlanningUrl   # => URL BDD
    .EXAMPLE
        # Test 3 — fallback env (si BDD vide) :
        #   $env:CN_SHAREPOINT_CONTENT_URL = "https://graph.microsoft.com/v1.0/sites/yyy"
        #   Get-SharePointPlanningUrl   # => URL env
    #>
    if (-not (Get-Command Get-AppConfig -ErrorAction SilentlyContinue)) {
        $dbScript = Join-Path $PSScriptRoot '..\Database\Database.ps1'
        if (Test-Path -LiteralPath $dbScript) {
            . $dbScript
        }
    }

    $url = $null
    $source = 'null'

    if (Get-Command Get-AppConfig -ErrorAction SilentlyContinue) {
        try {
            $dbUrl = Get-AppConfig -Key 'SharePointApiUrl'
            if (-not [string]::IsNullOrWhiteSpace($dbUrl)) {
                $url = [string]$dbUrl.Trim()
                $source = 'database'
            }
        }
        catch {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log '[SharePoint] Get-AppConfig failed' 'WARN' @{ message = $_.Exception.Message }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($url) -and -not [string]::IsNullOrWhiteSpace($env:CN_SHAREPOINT_CONTENT_URL)) {
        $url = $env:CN_SHAREPOINT_CONTENT_URL.Trim()
        $source = 'environment'
    }

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log '[SharePoint] Planning URL resolution' 'INFO' @{
            source     = $source
            configured = (-not [string]::IsNullOrWhiteSpace($url))
        }
    }

    if ([string]::IsNullOrWhiteSpace($url)) { return $null }
    return $url
}

function Convert-SharePointUrlToApiUrl {
    <#
    .SYNOPSIS
        Transforme un lien SharePoint navigateur en URL Microsoft Graph (idempotent).
    .OUTPUTS
        [string] URL Graph, ou $null si le format est invalide.
    #>
    param([Parameter(Mandatory = $true)][string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[SharePoint] Convert-SharePointUrlToApiUrl: URL vide' 'WARN' @{}
        }
        return $null
    }

    $trimmed = $Url.Trim()

    if ($trimmed -match '^(?i)https://graph\.microsoft\.com/') {
        return $trimmed
    }

    try {
        $uriString = $trimmed
        if ($uriString -match '^([^#?]+)') {
            $uriString = $matches[1]
        }

        $uri = [System.Uri]$uriString
        if ($uri.Scheme -notin @('http', 'https')) {
            throw 'Scheme invalide'
        }

        $hostName = $uri.Host
        if ($hostName -notmatch '(?i)\.sharepoint\.com$') {
            throw 'Hote SharePoint invalide'
        }

        $path = [System.Uri]::UnescapeDataString($uri.AbsolutePath)
        if ($path -eq '/') { $path = '' }
        $sitePath = if ([string]::IsNullOrEmpty($path)) { '' } else { $path.TrimStart('/') }

        if ([string]::IsNullOrEmpty($sitePath)) {
            return "https://graph.microsoft.com/v1.0/sites/${hostName}:/"
        }
        return "https://graph.microsoft.com/v1.0/sites/${hostName}:/${sitePath}"
    }
    catch {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[SharePoint] Convert-SharePointUrlToApiUrl failed' 'WARN' @{ message = $_.Exception.Message }
        }
        return $null
    }
}

function Get-SharePointBrowserUrlFromGraph {
    param([AllowNull()][string]$GraphUrl)
    if ([string]::IsNullOrWhiteSpace($GraphUrl)) { return '' }
    $trimmed = $GraphUrl.Trim()
    if ($trimmed -match '^(?i)https://graph\.microsoft\.com/v1\.0/sites/(?<host>[^:]+):/(?<path>.*)$') {
        $siteHost = $matches.host
        $sitePath = $matches.path
        if ([string]::IsNullOrWhiteSpace($sitePath)) { return "https://$siteHost" }
        return "https://$siteHost/$sitePath"
    }
    return $trimmed
}

function Show-SharePointUrlConfigDialog {
    <#
    .SYNOPSIS
        Dialogue de configuration URL SharePoint (1er lancement et changement d'adresse).
    .OUTPUTS
        [string] URL Graph configurée, ou $null si annulation/erreur.
    #>
    param(
        [string]$Title = 'Configuration SharePoint',
        [string]$InitialUrl = '',
        [switch]$AllowCancelWithoutExit,
        [switch]$ShowTestButton
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    }
    catch {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[SharePoint] Show-SharePointUrlConfigDialog: WinForms indisponible' 'ERROR' @{ message = $_.Exception.Message }
        }
        return $null
    }

    $padding = 20
    $labelWidth = 120
    $fieldWidth = 400
    $btnWidth = 100
    $btnHeight = 35
    $y = 20

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = $Title
    $form.Size = [System.Drawing.Size]::new(600, 320)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $form.Font = [System.Drawing.Font]::new('Segoe UI', 9)
    $form.TopMost = $true

    $lblInstruction = [System.Windows.Forms.Label]::new()
    $lblInstruction.Text = 'Saisissez l''URL de votre site SharePoint :'
    $lblInstruction.Location = [System.Drawing.Point]::new($padding, $y)
    $lblInstruction.Size = [System.Drawing.Size]::new($fieldWidth + $labelWidth, 25)
    $form.Controls.Add($lblInstruction)
    $y += 35

    $lblExample = [System.Windows.Forms.Label]::new()
    $lblExample.Text = 'Exemple: https://monsite.sharepoint.com/sites/MonCentre'
    $lblExample.Font = [System.Drawing.Font]::new('Segoe UI', 8, [System.Drawing.FontStyle]::Italic)
    $lblExample.ForeColor = [System.Drawing.Color]::Gray
    $lblExample.Location = [System.Drawing.Point]::new($padding, $y)
    $lblExample.Size = [System.Drawing.Size]::new($fieldWidth + $labelWidth, 20)
    $form.Controls.Add($lblExample)
    $y += 30

    $lblUrl = [System.Windows.Forms.Label]::new()
    $lblUrl.Text = 'URL SharePoint :'
    $lblUrl.Location = [System.Drawing.Point]::new($padding, $y)
    $lblUrl.Size = [System.Drawing.Size]::new($labelWidth, 30)
    $form.Controls.Add($lblUrl)

    $txtUrl = [System.Windows.Forms.TextBox]::new()
    $txtUrl.Location = [System.Drawing.Point]::new($padding + $labelWidth, $y)
    $txtUrl.Size = [System.Drawing.Size]::new($fieldWidth, 30)
    $txtUrl.Text = $InitialUrl
    $form.Controls.Add($txtUrl)
    $y += 45

    $lblConverted = [System.Windows.Forms.Label]::new()
    $lblConverted.Text = ''
    $lblConverted.Font = [System.Drawing.Font]::new('Segoe UI', 8)
    $lblConverted.ForeColor = [System.Drawing.Color]::DarkGreen
    $lblConverted.Location = [System.Drawing.Point]::new($padding + $labelWidth, $y)
    $lblConverted.Size = [System.Drawing.Size]::new($fieldWidth, 20)
    $form.Controls.Add($lblConverted)
    $y += 30

    $lblError = [System.Windows.Forms.Label]::new()
    $lblError.Text = ''
    $lblError.Font = [System.Drawing.Font]::new('Segoe UI', 8)
    $lblError.ForeColor = [System.Drawing.Color]::Red
    $lblError.Location = [System.Drawing.Point]::new($padding + $labelWidth, $y)
    $lblError.Size = [System.Drawing.Size]::new($fieldWidth, 40)
    $form.Controls.Add($lblError)
    $y += 50

    $flowPanel = [System.Windows.Forms.FlowLayoutPanel]::new()
    $flowPanel.Location = [System.Drawing.Point]::new($padding, $y)
    $flowPanel.Size = [System.Drawing.Size]::new($fieldWidth + $labelWidth, $btnHeight + 8)
    $flowPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft

    $btnOk = [System.Windows.Forms.Button]::new()
    $btnOk.Text = 'Valider'
    $btnOk.Size = [System.Drawing.Size]::new($btnWidth, $btnHeight)
    $btnOk.BackColor = [System.Drawing.Color]::FromArgb(26, 106, 168)
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $btnOk.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnOk.Cursor = [System.Windows.Forms.Cursors]::Hand

    $btnCancel = [System.Windows.Forms.Button]::new()
    $btnCancel.Text = 'Annuler'
    $btnCancel.Size = [System.Drawing.Size]::new($btnWidth, $btnHeight)
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
    $btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCancel.Cursor = [System.Windows.Forms.Cursors]::Hand

    $btnTest = $null
    if ($ShowTestButton) {
        $btnTest = [System.Windows.Forms.Button]::new()
        $btnTest.Text = 'Tester'
        $btnTest.Size = [System.Drawing.Size]::new($btnWidth, $btnHeight)
        $btnTest.BackColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
        $btnTest.ForeColor = [System.Drawing.Color]::White
        $btnTest.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $btnTest.Cursor = [System.Windows.Forms.Cursors]::Hand
    }

    $dialogState = @{ ConvertedUrl = $null }
    $form.Tag = $dialogState

    $updatePreview = {
        $rawUrl = $txtUrl.Text
        if ([string]::IsNullOrWhiteSpace($rawUrl)) {
            $lblConverted.Text = ''
            $lblError.Text = ''
            return
        }
        $converted = Convert-SharePointUrlToApiUrl -Url $rawUrl
        if ($converted) {
            $display = $converted
            if ($display.Length -gt 60) { $display = $display.Substring(0, 57) + '...' }
            $lblConverted.Text = "URL API: $display"
            $lblError.Text = ''
        }
        else {
            $lblConverted.Text = ''
            $lblError.Text = 'Format d''URL invalide'
            $lblError.ForeColor = [System.Drawing.Color]::Red
        }
    }

    $txtUrl.Add_TextChanged({ & $updatePreview })
    if (-not [string]::IsNullOrWhiteSpace($InitialUrl)) { & $updatePreview }

    $btnOk.Add_Click({
        $rawUrl = $txtUrl.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($rawUrl)) {
            $lblError.Text = 'Veuillez saisir une URL'
            $lblError.ForeColor = [System.Drawing.Color]::Red
            return
        }
        $converted = Convert-SharePointUrlToApiUrl -Url $rawUrl
        if (-not $converted) {
            $lblError.Text = 'Format d''URL invalide'
            $lblError.ForeColor = [System.Drawing.Color]::Red
            return
        }
        $dialogState.ConvertedUrl = $converted
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })

    $btnCancel.Add_Click({
        $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Close()
    })

    if ($btnTest) {
        $btnTest.Add_Click({
            $rawUrl = $txtUrl.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($rawUrl)) {
                $lblError.Text = 'Veuillez saisir une URL a tester'
                $lblError.ForeColor = [System.Drawing.Color]::Red
                return
            }
            $converted = Convert-SharePointUrlToApiUrl -Url $rawUrl
            if (-not $converted) {
                $lblError.Text = 'Format d''URL invalide'
                $lblError.ForeColor = [System.Drawing.Color]::Red
                return
            }
            $lblError.Text = 'Test en cours (authentification possible)...'
            $lblError.ForeColor = [System.Drawing.Color]::DarkOrange
            [System.Windows.Forms.Application]::DoEvents()

            $testResult = Test-SharePointPlanningGraphUrl -GraphUrl $converted -InteractiveLogin
            if ($testResult.Ok) {
                $lblError.Text = $testResult.Message
                $lblError.ForeColor = [System.Drawing.Color]::DarkGreen
            }
            else {
                $lblError.Text = $testResult.Message
                $lblError.ForeColor = [System.Drawing.Color]::Red
            }
            $clearTimer = [System.Windows.Forms.Timer]::new()
            $clearTimer.Interval = 5000
            $clearTimer.Add_Tick({
                if ($null -ne $lblError -and $lblError -is [System.Windows.Forms.Control] -and -not $lblError.IsDisposed) {
                    $lblError.Text = ''
                    $lblError.ForeColor = [System.Drawing.Color]::Red
                }
                try { $clearTimer.Stop() } catch { }
                try { $clearTimer.Dispose() } catch { }
            })
            $clearTimer.Start()
        })
    }

    [void]$flowPanel.Controls.Add($btnOk)
    [void]$flowPanel.Controls.Add($btnCancel)
    if ($btnTest) { [void]$flowPanel.Controls.Add($btnTest) }
    $form.Controls.Add($flowPanel)
    $form.AcceptButton = $btnOk
    $form.CancelButton = $btnCancel

    $null = $AllowCancelWithoutExit

    $result = $form.ShowDialog()
    $form.Dispose()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialogState.ConvertedUrl
    }
    return $null
}

function Save-SharePointApiUrlConfig {
    param([Parameter(Mandatory = $true)][string]$ApiUrl)
    if (-not (Get-Command Set-AppConfig -ErrorAction SilentlyContinue)) {
        $dbScript = Join-Path $PSScriptRoot '..\Database\Database.ps1'
        if (Test-Path -LiteralPath $dbScript) {
            . $dbScript
        }
    }
    if (-not (Get-Command Set-AppConfig -ErrorAction SilentlyContinue)) {
        throw 'Impossible d''acceder a la base de donnees.'
    }
    Set-AppConfig -Key 'SharePointApiUrl' -Value $ApiUrl
}

function Show-ChangeUrlDialog {
    <#
    .SYNOPSIS
        Affiche le dialogue de changement d'URL SharePoint.
    .OUTPUTS
        [bool] True si l'URL a été changée, False si annulation ou erreur.
    #>
    $currentUrl = Get-SharePointPlanningUrl
    $initialDisplay = Get-SharePointBrowserUrlFromGraph -GraphUrl $currentUrl

    $newUrl = Show-SharePointUrlConfigDialog `
        -Title 'Changer l''adresse SharePoint' `
        -InitialUrl $initialDisplay `
        -AllowCancelWithoutExit `
        -ShowTestButton

    if ([string]::IsNullOrWhiteSpace($newUrl)) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[ChangeUrl] Annulation par l utilisateur' 'INFO' @{}
        }
        return $false
    }

    if ($currentUrl -eq $newUrl) {
        [System.Windows.Forms.MessageBox]::Show(
            'L''URL configuree est identique a l''URL actuelle.',
            'Aucun changement',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return $false
    }

    try {
        Save-SharePointApiUrlConfig -ApiUrl $newUrl
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[ChangeUrl] URL mise a jour' 'INFO' @{ configured = $true }
        }

        [System.Windows.Forms.MessageBox]::Show(
            "Configuration enregistree.`n`nL'application va redemarrer pour appliquer les changements.",
            'URL modifiee',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return $true
    }
    catch {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[ChangeUrl] Erreur sauvegarde' 'ERROR' @{ message = $_.Exception.Message }
        }
        [System.Windows.Forms.MessageBox]::Show(
            ("Erreur lors de la sauvegarde : {0}" -f $_.Exception.Message),
            'Erreur',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return $false
    }
}

function Show-FirstLaunchConfig {
    <#
    .SYNOPSIS
        Affiche la fenêtre de configuration au premier lancement.
    .OUTPUTS
        [bool] $true si configuré, $false si annulation.
    #>
    $newUrl = Show-SharePointUrlConfigDialog `
        -Title 'Configuration initiale - Convention de nommage' `
        -ShowTestButton

    if ([string]::IsNullOrWhiteSpace($newUrl)) {
        return $false
    }

    try {
        Save-SharePointApiUrlConfig -ApiUrl $newUrl
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[FirstLaunch] URL configuree' 'INFO' @{ configured = $true }
        }

        [System.Windows.Forms.MessageBox]::Show(
            'Configuration enregistree avec succes !',
            'Bienvenue',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return $true
    }
    catch {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[FirstLaunch] Erreur sauvegarde' 'ERROR' @{ message = $_.Exception.Message }
        }
        [System.Windows.Forms.MessageBox]::Show(
            ("Erreur lors de la sauvegarde : {0}" -f $_.Exception.Message),
            'Erreur',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return $false
    }
}

function Test-CnsSharePointAuthInProgress {
    return ($true -eq $script:CnsSharePointAuthInProgress)
}

function Enter-CnsSharePointAuthLock {
    if ($script:CnsSharePointAuthInProgress) {
        return $false
    }
    $script:CnsSharePointAuthInProgress = $true
    $script:CnsSharePointDeviceBrowserOpened = $false
    return $true
}

function Exit-CnsSharePointAuthLock {
    $script:CnsSharePointAuthInProgress = $false
    $script:CnsSharePointDeviceBrowserOpened = $false
}

function Open-CnsSharePointDeviceLoginBrowser {
    if ($script:CnsSharePointDeviceBrowserOpened) { return }
    try {
        Start-Process 'https://login.microsoftonline.com/common/oauth2/deviceauth' -ErrorAction SilentlyContinue | Out-Null
        $script:CnsSharePointDeviceBrowserOpened = $true
    }
    catch { }
}

function Get-CnsSharePointLocalPlanningPath {
    $safeName = ($script:CnsSharePointPlanningFileName -replace '[\\/:*?"<>|]', '_')
    return (Join-Path $script:CnsSharePointCacheDir $safeName)
}

function Ensure-CnsSharePointCacheDir {
    foreach ($dir in @($script:CnsSharePointCacheDir, $script:CnsSharePointLocalDir)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            $null = New-Item -ItemType Directory -Path $dir -Force
        }
    }
}

function Get-CnsSharePointSyncMeta {
    Ensure-CnsSharePointCacheDir
    if (-not (Test-Path -LiteralPath $script:CnsSharePointSyncMetaPath)) {
        return $null
    }
    try {
        $raw = Get-Content -LiteralPath $script:CnsSharePointSyncMetaPath -Raw -Encoding UTF8
        return ($raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Set-CnsSharePointSyncMeta {
    param(
        [string]$LocalPath,
        [datetime]$LastSync,
        [string]$SourceFile = $script:CnsSharePointPlanningFileName,
        [ValidateSet('SharePoint', 'Local')]
        [string]$Source = 'SharePoint'
    )
    Ensure-CnsSharePointCacheDir
    $payload = [ordered]@{
        lastSync   = $LastSync.ToString('o')
        sourceFile = $SourceFile
        localPath  = $LocalPath
        source     = $Source
    }
    ($payload | ConvertTo-Json) | Set-Content -LiteralPath $script:CnsSharePointSyncMetaPath -Encoding UTF8
}

function Get-CnsPlanningRegistryValue {
    param([Parameter(Mandatory = $true)][string]$Name)
    $path = $script:CnsSharePointRegistryRoot
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $item = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
        if ($null -eq $item -or -not $item.PSObject.Properties[$Name]) { return $null }
        $val = [string]$item.$Name
        if ([string]::IsNullOrWhiteSpace($val)) { return $null }
        return $val.Trim()
    }
    catch {
        return $null
    }
}

function Set-CnsPlanningRegistryValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][string]$Value
    )
    $path = $script:CnsSharePointRegistryRoot
    if (-not (Test-Path -LiteralPath $path)) {
        $null = New-Item -Path $path -Force
    }
    if ([string]::IsNullOrWhiteSpace($Value)) {
        Remove-ItemProperty -LiteralPath $path -Name $Name -ErrorAction SilentlyContinue
        return
    }
    Set-ItemProperty -LiteralPath $path -Name $Name -Value $Value
}

function Reset-CnsSharePointGraphModuleCache {
    $script:CnsSharePointGraphModuleChecked = $false
    $script:CnsSharePointGraphAvailable = $false
}

function Get-CnsAssistantInstallRoot {
    if (-not [string]::IsNullOrWhiteSpace($env:ASSISTANT_HOME)) {
        $homeMain = Join-Path $env:ASSISTANT_HOME 'src\Main.ps1'
        if (Test-Path -LiteralPath $homeMain) {
            try { return (Resolve-Path -LiteralPath $env:ASSISTANT_HOME -ErrorAction Stop).Path } catch { return $env:ASSISTANT_HOME }
        }
    }
    $candidate = Join-Path $PSScriptRoot '..\..'
    try {
        $resolved = (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
        if (Test-Path -LiteralPath (Join-Path $resolved 'src\Main.ps1')) { return $resolved }
    }
    catch { }
    return $null
}

function Register-CnsBundledGraphModulePath {
    $installRoot = Get-CnsAssistantInstallRoot
    if ([string]::IsNullOrWhiteSpace($installRoot)) { return $false }
    $graphRoot = Join-Path $installRoot 'runtime\Graph'
    if (-not (Test-Path -LiteralPath $graphRoot)) { return $false }
    if ($env:PSModulePath -notlike "*$graphRoot*") {
        $env:PSModulePath = "$graphRoot;$env:PSModulePath"
    }
    return $true
}

function Get-CnsBundledGraphAuthenticationModulePath {
    $installRoot = Get-CnsAssistantInstallRoot
    if ([string]::IsNullOrWhiteSpace($installRoot)) { return $null }
    $flatPsd1 = Join-Path $installRoot 'runtime\Graph\Microsoft.Graph.Authentication\Microsoft.Graph.Authentication.psd1'
    if (Test-Path -LiteralPath $flatPsd1) { return $flatPsd1 }
    $authRoot = Join-Path $installRoot 'runtime\Graph\Microsoft.Graph.Authentication'
    if (-not (Test-Path -LiteralPath $authRoot)) { return $null }
    $nested = Get-ChildItem -LiteralPath $authRoot -Recurse -Filter 'Microsoft.Graph.Authentication.psd1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($nested) { return $nested.FullName }
    return $null
}

function Test-CnsSharePointGraphModuleAvailable {
    if ($script:CnsSharePointGraphModuleChecked) {
        return [bool]$script:CnsSharePointGraphAvailable
    }
    $script:CnsSharePointGraphModuleChecked = $true

    $installRoot = Get-CnsAssistantInstallRoot
    if ($installRoot) {
        $bundledPsd1 = Get-CnsBundledGraphAuthenticationModulePath
        if (-not [string]::IsNullOrWhiteSpace($bundledPsd1)) {
            $script:CnsSharePointGraphAvailable = $true
            return $true
        }
    }

    # Chemin rapide : Test-Path sur emplacements connus (evite Get-Module -ListAvailable qui peut prendre des minutes si PSModulePath contient des UNC).
    $moduleNames = @('Microsoft.Graph.Authentication', 'Microsoft.Graph')
    $searchRoots = @(
        (Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules')
        (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Modules')
        (Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules')
    )
    if (${env:ProgramFiles(x86)}) {
        $searchRoots += Join-Path ${env:ProgramFiles(x86)} 'WindowsPowerShell\Modules'
    }
    foreach ($modName in $moduleNames) {
        foreach ($root in $searchRoots) {
            if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) { continue }
            $modDir = Join-Path $root $modName
            if (Test-Path -LiteralPath $modDir) {
                $script:CnsSharePointGraphAvailable = $true
                return $true
            }
        }
    }

    if ($env:CN_ASSISTANT_SLOW_MODULE_SCAN -eq '1') {
        $authMod = Get-Module -ListAvailable -Name 'Microsoft.Graph.Authentication' -ErrorAction SilentlyContinue
        $graphMod = Get-Module -ListAvailable -Name 'Microsoft.Graph' -ErrorAction SilentlyContinue
        $script:CnsSharePointGraphAvailable = ($null -ne $authMod) -or ($null -ne $graphMod)
        return [bool]$script:CnsSharePointGraphAvailable
    }

    $script:CnsSharePointGraphAvailable = $false
    return $false
}

function Test-MicrosoftGraphModule {
    [CmdletBinding()]
    param(
        [switch]$PromptInstall
    )
    if (Test-CnsSharePointGraphModuleAvailable) {
        return $true
    }
    if (-not $PromptInstall) {
        return $false
    }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    }
    catch {
        return $false
    }
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Le module Microsoft.Graph est requis pour la connexion SharePoint.`n`nVoulez-vous l'installer automatiquement ?",
        'Module manquant',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
        return $false
    }
    try {
        Write-Host 'Installation du module Microsoft.Graph...' -ForegroundColor Cyan
        Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Reset-CnsSharePointGraphModuleCache
        Import-Module Microsoft.Graph.Authentication -Force -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            'Installation Microsoft.Graph',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return $false
    }
    return (Test-CnsSharePointGraphModuleAvailable)
}

function Get-WindowsAccountInfo {
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    Write-Host "Compte Windows actuel : $currentUser" -ForegroundColor Cyan
    Write-Host "  Si ce n'est pas votre compte Microsoft 365, reconnectez-vous a Windows avec votre compte entreprise." -ForegroundColor Yellow
    return $currentUser
}

function Write-CnsSharePointDeviceCodeInstructions {
    Write-Host ''
    Write-Host 'Connexion SharePoint via Device Code Authentication...' -ForegroundColor Cyan
    Write-Host '=== SUIVEZ CES INSTRUCTIONS ===' -ForegroundColor Cyan
    Write-Host '1. Un code va s''afficher ci-dessous ou dans une fenetre de l''application' -ForegroundColor Yellow
    Write-Host '2. Ouvrez https://microsoft.com/devicelogin sur n''importe quel appareil' -ForegroundColor Yellow
    Write-Host '3. Saisissez le code affiche' -ForegroundColor Yellow
    Write-Host '4. Connectez-vous avec votre compte Microsoft 365 entreprise' -ForegroundColor Yellow
    Write-Host '================================' -ForegroundColor Cyan
    Write-Host ''
}

function Get-CnsSharePointDeviceCodeFromGraphOutput {
    param([string[]]$Lines)
    foreach ($line in @($Lines)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '(?i)enter the code(?:\s*:\s*|\s+)([A-Z0-9]+)') {
            return $matches[1]
        }
        if ($line -match '(?i)code[:\s]+([A-Z0-9-]+)') {
            return $matches[1]
        }
        if ($line -match '(?i)device(?:\s*code)?[:\s]+([A-Z0-9]{6,12})') {
            return $matches[1]
        }
        $wordMatch = [regex]::Match($line, '\b([A-Z0-9]{8,12})\b')
        if ($wordMatch.Success -and $line -match '(?i)devicelogin|authenticate|sign in|microsoft\.com') {
            return $wordMatch.Groups[1].Value
        }
    }
    return $null
}

function Show-CnsSharePointDeviceCodeDialog {
    param(
        [Parameter(Mandatory = $true)][string]$Code
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    }
    catch {
        return
    }

    $codeValue = [string]$Code
    $deviceAuthUrl = 'https://login.microsoftonline.com/common/oauth2/deviceauth'

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'Connexion au fichier planning'
    $form.Size = [System.Drawing.Size]::new(480, 300)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true

    # Titre (centré, police 14, gras)
    $labelTitle = [System.Windows.Forms.Label]::new()
    $labelTitle.Text = 'Processus de connexion au planning :'
    $labelTitle.Font = [System.Drawing.Font]::new('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
    $labelTitle.Location = [System.Drawing.Point]::new(20, 20)
    $labelTitle.Size = [System.Drawing.Size]::new(430, 35)
    $labelTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

    # Code (centré, police 12 bold)
    $labelCode = [System.Windows.Forms.Label]::new()
    $labelCode.Text = ('Code : {0}' -f $codeValue)
    $labelCode.Font = [System.Drawing.Font]::new('Consolas', 12, [System.Drawing.FontStyle]::Bold)
    $labelCode.Location = [System.Drawing.Point]::new(20, 70)
    $labelCode.Size = [System.Drawing.Size]::new(430, 35)
    $labelCode.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

    # Message copie (centré, police 10, gris)
    $labelCopyMsg = [System.Windows.Forms.Label]::new()
    $labelCopyMsg.Text = '(le code est automatiquement copié)'
    $labelCopyMsg.Font = [System.Drawing.Font]::new('Segoe UI', 10, [System.Drawing.FontStyle]::Italic)
    $labelCopyMsg.ForeColor = [System.Drawing.Color]::Gray
    $labelCopyMsg.Location = [System.Drawing.Point]::new(20, 105)
    $labelCopyMsg.Size = [System.Drawing.Size]::new(430, 25)
    $labelCopyMsg.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

    # Bouton
    $btnGo = [System.Windows.Forms.Button]::new()
    $btnGo.Text = 'Aller sur Microsoft'
    $btnGo.Size = [System.Drawing.Size]::new(220, 45)
    $btnGo.Location = [System.Drawing.Point]::new(120, 170)
    $btnGo.Font = [System.Drawing.Font]::new('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $btnGo.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $btnGo.ForeColor = [System.Drawing.Color]::White
    $btnGo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat

    $btnGo.Add_Click({
        try {
            [System.Windows.Forms.Clipboard]::SetText($codeValue)
        }
        catch { }
        try {
            Start-Process $deviceAuthUrl -ErrorAction SilentlyContinue
            $script:CnsSharePointDeviceBrowserOpened = $true
        }
        catch { }
        $form.Close()
    })

    $form.Controls.AddRange(@($labelTitle, $labelCode, $labelCopyMsg, $btnGo))
    $form.AcceptButton = $btnGo

    [void]$form.ShowDialog()
    $form.Dispose()
}

function Invoke-CnsSharePointGraphConnectInteractive {
    # Ne pas ouvrir de navigateur ici : Connect-MgGraph -UseDeviceAuthentication ouvre deja sa propre fenetre.
    $connectParams = @{
        Scopes                  = $script:CnsSharePointGraphScopes
        NoWelcome               = $true
        UseDeviceAuthentication = $true
        ErrorAction             = 'Stop'
    }

    $capturedLines = [System.Collections.Generic.List[string]]::new()
    $deviceCode = $null
    $codeDialogShown = $false

    try {
        Connect-MgGraph @connectParams *>&1 | ForEach-Object {
            $line = [string]$_
            if ([string]::IsNullOrWhiteSpace($line)) { return }
            [void]$capturedLines.Add($line)
            Write-Host $line
            if (-not $codeDialogShown) {
                $parsed = Get-CnsSharePointDeviceCodeFromGraphOutput -Lines @($line)
                if (-not [string]::IsNullOrWhiteSpace($parsed)) {
                    $deviceCode = $parsed
                    Show-CnsSharePointDeviceCodeDialog -Code $deviceCode
                    $codeDialogShown = $true
                }
            }
        }
        if ([string]::IsNullOrWhiteSpace($deviceCode)) {
            $deviceCode = Get-CnsSharePointDeviceCodeFromGraphOutput -Lines $capturedLines
            if (-not [string]::IsNullOrWhiteSpace($deviceCode) -and -not $codeDialogShown) {
                Show-CnsSharePointDeviceCodeDialog -Code $deviceCode
                $codeDialogShown = $true
            }
        }
    }
    catch {
        $deviceErr = [string]$_.Exception.Message
        Write-Host ("Device Code echoue : {0}" -f $deviceErr) -ForegroundColor Yellow
        if ($deviceErr -match '(?i)WAM|web account manager|interactive.*block') {
            Write-Host 'Tentative Web Authentication (fenetre navigateur)...' -ForegroundColor Yellow
            try {
                Connect-MgGraph -Scopes $script:CnsSharePointGraphScopes -UseWebAuthentication -NoWelcome -ErrorAction Stop
                return
            }
            catch {
                throw
            }
        }
        throw
    }

    if (-not $codeDialogShown) {
        Write-Host 'Code Device introuvable dans la sortie Graph — consultez la console ou reessayez.' -ForegroundColor Yellow
    }
}

function Resolve-CnsSharePointConnectError {
    param([string]$ErrorMessage)
    $msg = [string]$ErrorMessage
    if ($msg -match '(?i)interactive|browser|WAM|web account manager') {
        return @{
            Status  = 'WamBlocked'
            Message = 'Connexion interactive bloquee - suivez la fenetre Device Code ou le navigateur'
        }
    }
    if ($msg -match '(?i)expired|AADSTS70008|login') {
        return @{
            Status  = 'Expired'
            Message = 'Session expiree - reconnectez-vous'
        }
    }
    if ($msg -match '(?i)403|Forbidden|Access denied|unauthorized') {
        return @{
            Status  = 'Denied'
            Message = 'Acces refuse - verifier vos droits SharePoint'
        }
    }
    if ($msg -match '(?i)timeout|timed out|Unable to connect|No such host|network') {
        return @{
            Status  = 'Offline'
            Message = 'Connexion échouée – cliquez sur "Connexion" pour réessayer'
        }
    }
    return @{
        Status  = 'Error'
        Message = "Erreur technique : $msg"
    }
}

function Set-CnsSharePointConnectionState {
    param($State)
    $script:CnsSharePointConnectionState = $State
}

function Get-SharePointConnectionState {
    return $script:CnsSharePointConnectionState
}

function Import-CnsSharePointGraphModule {
    if (-not (Test-CnsSharePointGraphModuleAvailable)) {
        throw 'Le module Microsoft.Graph.Authentication est requis. Installez-le avec : Install-Module Microsoft.Graph -Scope CurrentUser'
    }
    $bundledPsd1 = Get-CnsBundledGraphAuthenticationModulePath
    if (-not [string]::IsNullOrWhiteSpace($bundledPsd1)) {
        Import-Module -Name $bundledPsd1 -Force -ErrorAction Stop | Out-Null
        return
    }
    $null = Register-CnsBundledGraphModulePath
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop | Out-Null
}

function Test-CnsSharePointGraphContextPresent {
    if (-not (Test-CnsSharePointGraphModuleAvailable)) {
        return $false
    }
    try {
        Import-CnsSharePointGraphModule
    }
    catch {
        return $false
    }
    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if ($null -eq $ctx -or [string]::IsNullOrWhiteSpace([string]$ctx.Account)) {
        return $false
    }
    if ($null -ne $ctx.ExpiresOn) {
        try {
            $expiresOn = [datetime]$ctx.ExpiresOn
            if ($expiresOn -le (Get-Date)) {
                return $false
            }
        }
        catch { }
    }
    return (Test-CnsSharePointGraphSessionValid)
}

function Test-CnsSharePointGraphSessionValid {
    if (-not (Test-CnsSharePointGraphModuleAvailable)) {
        return $false
    }
    try {
        Import-CnsSharePointGraphModule
    }
    catch {
        return $false
    }
    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if ($null -eq $ctx -or [string]::IsNullOrWhiteSpace([string]$ctx.Account)) {
        return $false
    }
    if ($null -ne $ctx.ExpiresOn) {
        try {
            $expiresOn = [datetime]$ctx.ExpiresOn
            if ($expiresOn -le (Get-Date)) {
                return $false
            }
        }
        catch { }
    }
    try {
        Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        $msg = [string]$_.Exception.Message
        if ($msg -match '(?i)expired|401|unauthorized|AADSTS70008|login') {
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        }
        return $false
    }
}

function Test-CnsSharePointPlanningCacheFresh {
    param([int]$MaxAgeHours = 24)
    $localPath = Get-CnsSharePointLocalPlanningPath
    if ([string]::IsNullOrWhiteSpace($localPath) -or -not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
        return $false
    }
    if ((Get-Item -LiteralPath $localPath).Length -lt 1) {
        return $false
    }
    $meta = Get-CnsSharePointSyncMeta
    if ($null -eq $meta -or [string]$meta.source -ne 'SharePoint') {
        return $false
    }
    try {
        $lastSync = [datetime]$meta.lastSync
        return ((Get-Date) - $lastSync).TotalHours -lt $MaxAgeHours
    }
    catch {
        return $false
    }
}

function Connect-SharePointGraph {
    [CmdletBinding()]
    param(
        [switch]$Interactive
    )
    if ($Interactive -and (Test-CnsSharePointAuthInProgress)) {
        throw 'Authentification Microsoft 365 deja en cours.'
    }
    $authLocked = $false
    if ($Interactive) {
        if (-not (Enter-CnsSharePointAuthLock)) {
            throw 'Authentification Microsoft 365 deja en cours.'
        }
        $authLocked = $true
    }
    try {
        Import-CnsSharePointGraphModule
        if ($Interactive) {
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        }
        elseif (Test-CnsSharePointGraphSessionValid) {
            $ctx = Get-MgContext -ErrorAction SilentlyContinue
            if ($null -ne $ctx -and -not [string]::IsNullOrWhiteSpace([string]$ctx.Account)) {
                Write-Host "Deja connecte avec : $($ctx.Account)" -ForegroundColor Green
            }
            return $true
        }
        if (-not $Interactive) {
            if (Test-CnsSharePointGraphSessionValid) {
                return $true
            }
            throw 'Session Microsoft Graph invalide. Lancez la connexion depuis l''onglet Edition planning.'
        }
        Get-WindowsAccountInfo | Out-Null
        Write-CnsSharePointDeviceCodeInstructions
        Invoke-CnsSharePointGraphConnectInteractive
        $ctx = Get-MgContext -ErrorAction SilentlyContinue
        if ($null -ne $ctx -and -not [string]::IsNullOrWhiteSpace([string]$ctx.Account)) {
            Write-Host "Connecte avec : $($ctx.Account)" -ForegroundColor Green
        }
        return $true
    }
    finally {
        if ($authLocked) {
            Exit-CnsSharePointAuthLock
        }
    }
}

function Get-CnsSharePointGraphAccessToken {
    Import-CnsSharePointGraphModule
    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if ($null -eq $ctx) { return $null }
    try {
        $token = [Microsoft.Graph.PowerShell.Authentication.GraphSession]::Instance.AuthContext.TokenCache.ReadItems() |
            Select-Object -First 1
        if ($null -ne $token -and -not [string]::IsNullOrWhiteSpace([string]$token.AccessToken)) {
            return [string]$token.AccessToken
        }
    }
    catch { }

    try {
        $auth = [Microsoft.Graph.PowerShell.Authentication.GraphSession]::Instance.AuthContext
        if ($null -ne $auth -and $auth.GetType().GetMethod('GetAccessToken')) {
            return [string]$auth.GetAccessToken()
        }
    }
    catch { }

    return $null
}

function Test-SharePointPlanningGraphUrl {
    <#
    .SYNOPSIS
        Verifie l'acces Graph a une URL planning sans modifier la configuration enregistree.
  #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$GraphUrl,
        [switch]$InteractiveLogin
    )

    if (-not (Test-CnsSharePointGraphModuleAvailable)) {
        if (-not (Test-MicrosoftGraphModule -PromptInstall)) {
            return @{ Ok = $false; Message = 'Module Microsoft.Graph manquant' }
        }
    }

    try {
        Import-CnsSharePointGraphModule
        if (-not (Test-CnsSharePointGraphSessionValid)) {
            if (-not $InteractiveLogin) {
                return @{
                    Ok      = $false
                    Message = 'Session Microsoft 365 requise - relancez le test pour vous authentifier'
                }
            }
            Connect-SharePointGraph -Interactive | Out-Null
        }

        $testUri = $GraphUrl.Trim()
        if ($testUri -match '/content$') {
            $testUri = $testUri -replace '/content$', ''
        }

        $meta = Invoke-MgGraphRequest -Method GET -Uri $testUri -ErrorAction Stop
        $displayName = if ($null -ne $meta -and $meta.PSObject.Properties['name']) {
            [string]$meta.name
        }
        else {
            'fichier'
        }
        return @{ Ok = $true; Message = ("Acces OK : {0}" -f $displayName) }
    }
    catch {
        $resolved = Resolve-CnsSharePointConnectError -ErrorMessage ([string]$_.Exception.Message)
        return @{ Ok = $false; Message = $resolved.Message }
    }
}

function Test-SharePointConnection {
    [CmdletBinding()]
    param(
        [string]$SiteUrl = $script:CnsSharePointSiteUrl,
        [string]$FilePathOnSharePoint = $script:CnsSharePointPlanningFileName,
        [string]$DestinationPath = $null,
        [switch]$Interactive
    )
    if (-not (Test-CnsSharePointGraphModuleAvailable)) {
        if ($Interactive) {
            if (-not (Test-MicrosoftGraphModule -PromptInstall)) { return $false }
        }
        else {
            return $false
        }
    }
    try {
        Import-CnsSharePointGraphModule
        $ctx = Get-MgContext -ErrorAction SilentlyContinue
        if ($null -eq $ctx -or [string]::IsNullOrWhiteSpace([string]$ctx.Account) -or -not (Test-CnsSharePointGraphSessionValid)) {
            if (-not (Connect-SharePointGraph -Interactive:$Interactive)) { return $false }
        }
        $exists = Test-SharePointDriveItemExists -SiteUrl $SiteUrl -FilePathOnSharePoint $FilePathOnSharePoint
        if (-not $exists) { return $false }
        if (-not [string]::IsNullOrWhiteSpace($DestinationPath)) {
            $planningUrl = Get-SharePointPlanningUrl
            if ([string]::IsNullOrWhiteSpace($planningUrl)) { return $false }
            return (Get-SharePointPlanningFile -Url $planningUrl -LocalPath $DestinationPath)
        }
        return $true
    }
    catch {
        return $false
    }
}

function Test-SharePointDriveItemExists {
    [CmdletBinding()]
    param(
        [string]$SiteUrl = $script:CnsSharePointSiteUrl,
        [string]$FilePathOnSharePoint = $script:CnsSharePointPlanningFileName
    )
    Import-CnsSharePointGraphModule
    if ($null -eq (Get-MgContext -ErrorAction SilentlyContinue)) {
        Connect-SharePointGraph | Out-Null
    }
    $encoded = [Uri]::EscapeDataString($FilePathOnSharePoint)
    $uri = "https://graph.microsoft.com/v1.0/sites/$SiteUrl/drive/root:/$encoded"
    try {
        Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Get-SharePointFile {
    [CmdletBinding()]
    param(
        [string]$SiteUrl = $script:CnsSharePointSiteUrl,
        [string]$FilePathOnSharePoint = $script:CnsSharePointPlanningFileName,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )
    $encoded = [Uri]::EscapeDataString($FilePathOnSharePoint)
    $url = "https://graph.microsoft.com/v1.0/sites/$SiteUrl/drive/root:/$encoded`:/content"
    return (Get-SharePointPlanningFile -Url $url -LocalPath $DestinationPath)
}

function Get-SharePointPlanningFile {
    [CmdletBinding()]
    param(
        [string]$Url,
        [Parameter(Mandatory = $true)][string]$LocalPath
    )
    if ($script:CnsSharePointConnectCancel) {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace($Url)) {
        $Url = Get-SharePointPlanningUrl
    }
    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $false
    }
    Import-CnsSharePointGraphModule
    if ($null -eq (Get-MgContext -ErrorAction SilentlyContinue)) {
        Connect-SharePointGraph | Out-Null
    }

    $destDir = Split-Path -Parent $LocalPath
    if (-not [string]::IsNullOrWhiteSpace($destDir) -and -not (Test-Path -LiteralPath $destDir)) {
        $null = New-Item -ItemType Directory -Path $destDir -Force
    }
    $tempPath = "$LocalPath.download"
    if (Test-Path -LiteralPath $tempPath) {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }

    try {
        Invoke-MgGraphRequest -Method GET -Uri $Url -OutputFilePath $tempPath -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $tempPath -PathType Leaf)) {
            return $false
        }
        if ((Get-Item -LiteralPath $tempPath).Length -lt 1) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
            return $false
        }
        if (Test-Path -LiteralPath $LocalPath) {
            Remove-Item -LiteralPath $LocalPath -Force -ErrorAction SilentlyContinue
        }
        Move-Item -LiteralPath $tempPath -Destination $LocalPath -Force
        return $true
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function New-CnsSharePointResult {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [string]$FilePath = $null,
        [datetime]$LastSync = [datetime]::MinValue,
        [string]$Message = $null,
        [string]$ErrorDetail = $null
    )
    return [pscustomobject]@{
        Status      = $Status
        FilePath    = $FilePath
        LastSync    = if ($LastSync -eq [datetime]::MinValue) { $null } else { $LastSync }
        Message     = $Message
        ErrorDetail = $ErrorDetail
    }
}

function Connect-SharePointPlanning {
    [CmdletBinding()]
    param(
        [switch]$ForceRefresh,
        [switch]$InteractiveLogin
    )
    if ($script:CnsSharePointConnectCancel) {
        return (New-CnsSharePointResult -Status 'Error' -Message 'Connexion annulee')
    }

    Ensure-CnsSharePointCacheDir
    $localPath = Get-CnsSharePointLocalPlanningPath

    $planningUrl = Get-SharePointPlanningUrl
    if ([string]::IsNullOrWhiteSpace($planningUrl)) {
        return (New-CnsSharePointResult -Status 'Offline' `
            -Message "Aucune URL SharePoint configurée. Utilisez l'onglet Outils ou la BDD." `
            -ErrorDetail 'SharePointApiUrl absent')
    }

    if (-not (Test-CnsSharePointGraphModuleAvailable)) {
        return (New-CnsSharePointResult -Status 'Error' `
            -Message 'Module Microsoft.Graph requis - installez-le depuis l''onglet Edition planning' `
            -ErrorDetail 'Microsoft.Graph absent')
    }

    $mustAuthenticate = $InteractiveLogin -or -not (Test-CnsSharePointGraphSessionValid)
    if ($mustAuthenticate) {
        if (-not $InteractiveLogin) {
            return (New-CnsSharePointResult -Status 'Offline' `
                -Message 'Connexion échouée – cliquez sur "Connexion" pour réessayer')
        }
        Get-WindowsAccountInfo | Out-Null
    }

    try {
        Connect-SharePointGraph -Interactive:$InteractiveLogin | Out-Null
    }
    catch {
        $msg = [string]$_.Exception.Message
        $resolved = Resolve-CnsSharePointConnectError -ErrorMessage $msg
        return (New-CnsSharePointResult -Status $resolved.Status -Message $resolved.Message -ErrorDetail $msg)
    }

    if ($script:CnsSharePointConnectCancel) {
        return (New-CnsSharePointResult -Status 'Error' -Message 'Connexion annulee')
    }

    try {
        $ok = Get-SharePointPlanningFile -Url $planningUrl -LocalPath $localPath
        if (-not $ok) {
            return (New-CnsSharePointResult -Status 'Error' -Message 'Echec du telechargement' `
                -ErrorDetail 'Fichier vide ou absent apres telechargement')
        }
        $now = Get-Date
        Set-CnsSharePointSyncMeta -LocalPath $localPath -LastSync $now -Source 'SharePoint'
        return (New-CnsSharePointResult -Status 'Connected' -FilePath $localPath -LastSync $now `
            -Message ("Connecte - {0}" -f $script:CnsSharePointPlanningFileName))
    }
    catch {
        $msg = [string]$_.Exception.Message
        if ($msg -match '(?i)404|itemNotFound|Not Found') {
            return (New-CnsSharePointResult -Status 'Denied' `
                -Message 'Fichier planning introuvable sur SharePoint' -ErrorDetail $msg)
        }
        $resolved = Resolve-CnsSharePointConnectError -ErrorMessage $msg
        return (New-CnsSharePointResult -Status $resolved.Status -Message $resolved.Message -ErrorDetail $msg)
    }
}

function Sync-SharePointPlanningFile {
    [CmdletBinding()]
    param(
        [switch]$InteractiveLogin
    )
    return (Connect-SharePointPlanning -ForceRefresh -InteractiveLogin:$InteractiveLogin)
}

function Set-CnsSharePointLocalPlanningFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath
    )
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        throw "Fichier introuvable : $SourcePath"
    }
    Ensure-CnsSharePointCacheDir
    $dest = Join-Path $script:CnsSharePointLocalDir ([IO.Path]::GetFileName($SourcePath))
    Copy-Item -LiteralPath $SourcePath -Destination $dest -Force
    $now = Get-Date
    Set-CnsPlanningRegistryValue -Name 'LocalExcelPath' -Value $dest
    Set-CnsPlanningRegistryValue -Name 'PreferLocalMode' -Value '1'
    Set-CnsSharePointSyncMeta -LocalPath $dest -LastSync $now -Source 'Local'
    return $dest
}

function Get-CnsSharePointEffectiveExcelPath {
    return $null
}

function Request-CnsSharePointConnectCancel {
    $script:CnsSharePointConnectCancel = $true
}

function Reset-CnsSharePointConnectCancel {
    $script:CnsSharePointConnectCancel = $false
}

$null = Register-CnsBundledGraphModulePath

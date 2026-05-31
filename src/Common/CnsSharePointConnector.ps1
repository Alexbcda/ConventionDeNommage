# Connexion SharePoint / Microsoft Graph — telechargement du planning Excel.

$script:CnsSharePointGraphScopes = @('Files.Read.All', 'Sites.Read.All', 'offline_access')
$script:CnsSharePointPlanningContentUrl = $(if (-not [string]::IsNullOrWhiteSpace($env:CN_SHAREPOINT_CONTENT_URL)) {
        $env:CN_SHAREPOINT_CONTENT_URL.Trim()
    }
    else {
        'https://graph.microsoft.com/v1.0/sites/naevaelisealpes.sharepoint.com:/sites/EliseAlpes/drive/root:/Planning%20GRENOBLE%202026.xlsm:/content'
    })
$script:CnsSharePointPlanningFileName = $(if (-not [string]::IsNullOrWhiteSpace($env:CN_SHAREPOINT_PLANNING_FILE)) {
        $env:CN_SHAREPOINT_PLANNING_FILE.Trim()
    }
    else {
        'Planning GRENOBLE 2026.xlsm'
    })
$script:CnsSharePointSiteUrl = $(if (-not [string]::IsNullOrWhiteSpace($env:CN_SHAREPOINT_SITE_URL)) {
        $env:CN_SHAREPOINT_SITE_URL.Trim()
    }
    else {
        'naevaelisealpes.sharepoint.com:/sites/EliseAlpes'
    })
$script:CnsSharePointCacheDir = Join-Path $env:LOCALAPPDATA 'ConventionDeNommage\SharePoint'
$script:CnsSharePointLocalDir = Join-Path $script:CnsSharePointCacheDir 'local'
$script:CnsSharePointSyncMetaPath = Join-Path $script:CnsSharePointCacheDir 'sync-meta.json'
$script:CnsSharePointRegistryRoot = 'HKCU:\Software\ConventionDeNommage\Planning'
$script:CnsSharePointConnectCancel = $false
$script:CnsSharePointGraphModuleChecked = $false
$script:CnsSharePointGraphAvailable = $false
$script:CnsSharePointConnectionState = $null
$script:CnsSharePointAuthInProgress = $false
$script:CnsSharePointDeviceBrowserOpened = $false

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

function Test-CnsSharePointGraphModuleAvailable {
    if ($script:CnsSharePointGraphModuleChecked) {
        return [bool]$script:CnsSharePointGraphAvailable
    }
    $script:CnsSharePointGraphModuleChecked = $true
    $authMod = Get-Module -ListAvailable -Name 'Microsoft.Graph.Authentication' -ErrorAction SilentlyContinue
    $graphMod = Get-Module -ListAvailable -Name 'Microsoft.Graph' -ErrorAction SilentlyContinue
    $script:CnsSharePointGraphAvailable = ($null -ne $authMod) -or ($null -ne $graphMod)
    return [bool]$script:CnsSharePointGraphAvailable
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
    $form.Text = 'Connexion au fichier planning Grenoble'
    $form.Size = [System.Drawing.Size]::new(480, 300)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true

    # Titre (centré, police 14, gras)
    $labelTitle = [System.Windows.Forms.Label]::new()
    $labelTitle.Text = 'Processus de connexion au planning Grenoble :'
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

function Test-SharePointConnection {
    [CmdletBinding()]
    param(
        [string]$SiteUrl = $script:CnsSharePointSiteUrl,
        [string]$FilePathOnSharePoint = $script:CnsSharePointPlanningFileName,
        [string]$DestinationPath = $null
    )
    if (-not (Test-CnsSharePointGraphModuleAvailable)) {
        return $false
    }
    try {
        Import-CnsSharePointGraphModule
        $ctx = Get-MgContext -ErrorAction SilentlyContinue
        if ($null -eq $ctx -or [string]::IsNullOrWhiteSpace([string]$ctx.Account)) {
            if (-not (Connect-SharePointGraph)) { return $false }
        }
        $exists = Test-SharePointDriveItemExists -SiteUrl $SiteUrl -FilePathOnSharePoint $FilePathOnSharePoint
        if (-not $exists) { return $false }
        if (-not [string]::IsNullOrWhiteSpace($DestinationPath)) {
            return (Get-SharePointPlanningFile -Url $script:CnsSharePointPlanningContentUrl -LocalPath $DestinationPath)
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
        [string]$Url = $script:CnsSharePointPlanningContentUrl,
        [Parameter(Mandatory = $true)][string]$LocalPath
    )
    if ($script:CnsSharePointConnectCancel) {
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
    $meta = Get-CnsSharePointSyncMeta

    if (-not $ForceRefresh -and (Test-Path -LiteralPath $localPath -PathType Leaf) -and $null -ne $meta -and $meta.source -eq 'SharePoint') {
        try {
            $lastSync = [datetime]$meta.lastSync
        }
        catch {
            $lastSync = (Get-Item -LiteralPath $localPath).LastWriteTime
        }
        if ((Get-Item -LiteralPath $localPath).Length -lt 1) {
            Remove-Item -LiteralPath $localPath -Force -ErrorAction SilentlyContinue
        }
        elseif (Test-CnsSharePointGraphSessionValid) {
            return (New-CnsSharePointResult -Status 'Connected' -FilePath $localPath -LastSync $lastSync `
                -Message ("Connecte - {0}" -f $script:CnsSharePointPlanningFileName))
        }
        else {
            return (New-CnsSharePointResult -Status 'Expired' -FilePath $localPath -LastSync $lastSync `
                -Message 'Fichier en cache - cliquez Se connecter pour synchroniser SharePoint')
        }
    }

    if (-not (Test-CnsSharePointGraphModuleAvailable)) {
        $localFallback = Get-CnsPlanningRegistryValue -Name 'LocalExcelPath'
        if (-not [string]::IsNullOrWhiteSpace($localFallback) -and (Test-Path -LiteralPath $localFallback)) {
            return (New-CnsSharePointResult -Status 'Expired' -FilePath $localFallback `
                -Message ('Mode local - {0}' -f (Split-Path -Leaf $localFallback)) -ErrorDetail 'Microsoft.Graph absent')
        }
        return (New-CnsSharePointResult -Status 'Error' `
            -Message 'Module Microsoft.Graph requis - installez-le depuis l''onglet Edition planning' `
            -ErrorDetail 'Microsoft.Graph absent')
    }

    $mustAuthenticate = $InteractiveLogin -or -not (Test-CnsSharePointGraphSessionValid)
    if ($mustAuthenticate) {
        if (-not $InteractiveLogin) {
            if (Test-Path -LiteralPath $localPath -PathType Leaf) {
                try { $lastSync = [datetime]$meta.lastSync } catch { $lastSync = (Get-Item -LiteralPath $localPath).LastWriteTime }
                return (New-CnsSharePointResult -Status 'Expired' -FilePath $localPath -LastSync $lastSync `
                    -Message 'Session SharePoint absente - cliquez Se connecter')
            }
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
        $ok = Get-SharePointPlanningFile -Url $script:CnsSharePointPlanningContentUrl -LocalPath $localPath
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
    $preferLocal = Get-CnsPlanningRegistryValue -Name 'PreferLocalMode'
    if ($preferLocal -in @('1', 'true', 'TRUE')) {
        $local = Get-CnsPlanningRegistryValue -Name 'LocalExcelPath'
        if (-not [string]::IsNullOrWhiteSpace($local) -and (Test-Path -LiteralPath $local)) {
            return $local
        }
    }
    $meta = Get-CnsSharePointSyncMeta
    if ($null -ne $meta -and -not [string]::IsNullOrWhiteSpace([string]$meta.localPath) -and (Test-Path -LiteralPath ([string]$meta.localPath))) {
        return [string]$meta.localPath
    }
    $cached = Get-CnsSharePointLocalPlanningPath
    if (Test-Path -LiteralPath $cached) { return $cached }
    return $null
}

function Request-CnsSharePointConnectCancel {
    $script:CnsSharePointConnectCancel = $true
}

function Reset-CnsSharePointConnectCancel {
    $script:CnsSharePointConnectCancel = $false
}

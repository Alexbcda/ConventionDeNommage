# UpdateManager.ps1 — mise à jour automatique depuis SharePoint (Phase 4)

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
if (-not (Get-Command Get-SharePointPlanningUrl -ErrorAction SilentlyContinue)) {
    $spScript = Join-Path $PSScriptRoot '..\Common\CnsSharePointConnector.ps1'
    if (Test-Path -LiteralPath $spScript) {
        . $spScript
    }
}

$script:CnsUpdateWebTimeoutMs = 10000
$script:CnsUpdateUserAgent = 'ASSISTANT/1.0'
$script:CnsUpdateHttpClientReady = $false

function Get-CnsUpdateLocalDataDir {
    $dir = Join-Path $env:LOCALAPPDATA 'ASSISTANT'
    if (-not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }
    return $dir
}

function Get-CnsUpdateTempDir {
    $dir = Join-Path (Get-CnsUpdateLocalDataDir) 'Update'
    if (-not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }
    return $dir
}

function Initialize-CnsUpdateHttpClient {
    if ($script:CnsUpdateHttpClientReady) { return $true }
    try {
        Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
        $script:CnsUpdateHttpClientReady = $true
        return $true
    }
    catch {
        return $false
    }
}

function New-CnsUpdateHttpClient {
    param([int]$TimeoutSeconds = 10)

    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.UseDefaultCredentials = $true
    $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate

    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
    $null = $client.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent', $script:CnsUpdateUserAgent)
    $null = $client.DefaultRequestHeaders.TryAddWithoutValidation('Accept-Encoding', 'gzip, deflate')

    return @{ Client = $client; Handler = $handler }
}

function Invoke-CnsUpdateWebDownloadString {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$TimeoutMs = $script:CnsUpdateWebTimeoutMs
    )
    $timeoutSeconds = [Math]::Max(1, [int][Math]::Ceiling($TimeoutMs / 1000.0))

    if (Initialize-CnsUpdateHttpClient) {
        $http = $null
        try {
            $http = New-CnsUpdateHttpClient -TimeoutSeconds $timeoutSeconds
            $response = $http.Client.GetAsync($Url).GetAwaiter().GetResult()
            $response.EnsureSuccessStatusCode() | Out-Null
            return $response.Content.ReadAsStringAsync().GetAwaiter().GetResult().Trim()
        }
        catch {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log '[UpdateManager] HttpClient string download failed, fallback HttpWebRequest' 'DEBUG' @{ message = $_.Exception.Message }
            }
        }
        finally {
            if ($http) {
                if ($http.Client) { $http.Client.Dispose() }
                if ($http.Handler) { $http.Handler.Dispose() }
            }
        }
    }

    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.Timeout = $TimeoutMs
    $request.ReadWriteTimeout = $TimeoutMs
    $request.UserAgent = $script:CnsUpdateUserAgent
    $request.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $response = $null
    $reader = $null
    try {
        $response = $request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        return $reader.ReadToEnd().Trim()
    }
    finally {
        if ($reader) { $reader.Close(); $reader.Dispose() }
        if ($response) { $response.Close(); $response.Dispose() }
    }
}

function Invoke-CnsUpdateWebDownloadFile {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )
    $timeoutSeconds = [Math]::Max(1, [int][Math]::Ceiling($script:CnsUpdateWebTimeoutMs / 1000.0))

    if (Initialize-CnsUpdateHttpClient) {
        $http = $null
        try {
            $http = New-CnsUpdateHttpClient -TimeoutSeconds ($timeoutSeconds * 6)
            $response = $http.Client.GetAsync($Url).GetAwaiter().GetResult()
            $response.EnsureSuccessStatusCode() | Out-Null
            $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            [System.IO.File]::WriteAllBytes($DestinationPath, $bytes)
            return
        }
        catch {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log '[UpdateManager] HttpClient file download failed, fallback HttpWebRequest' 'DEBUG' @{ message = $_.Exception.Message }
            }
        }
        finally {
            if ($http) {
                if ($http.Client) { $http.Client.Dispose() }
                if ($http.Handler) { $http.Handler.Dispose() }
            }
        }
    }

    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.Timeout = $script:CnsUpdateWebTimeoutMs * 6
    $request.ReadWriteTimeout = $script:CnsUpdateWebTimeoutMs * 6
    $request.UserAgent = $script:CnsUpdateUserAgent
    $request.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $response = $null
    $stream = $null
    $fileStream = $null
    try {
        $response = $request.GetResponse()
        $stream = $response.GetResponseStream()
        $fileStream = [System.IO.File]::Create($DestinationPath)
        $stream.CopyTo($fileStream)
    }
    finally {
        if ($fileStream) { $fileStream.Close(); $fileStream.Dispose() }
        if ($stream) { $stream.Close(); $stream.Dispose() }
        if ($response) { $response.Close(); $response.Dispose() }
    }
}

function Test-IsCompiledExe {
    <#
    .SYNOPSIS
        Detecte si l'application tourne en tant qu'exe PS2EXE.
    #>
    $entry = $MyInvocation.PSCommandPath
    if ([string]::IsNullOrWhiteSpace($entry)) {
        try {
            $entry = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        }
        catch {
            return $false
        }
    }
    return ($entry -like '*.exe')
}

function Get-CnsUpdateRepoRoot {
    if (Test-IsCompiledExe) {
        try {
            return (Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName))
        }
        catch {
            return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        }
    }
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Test-CnsVersionFormat {
    param([Parameter(Mandatory = $true)][string]$Version)
    return ($Version -match '^\d+(\.\d+){0,2}$')
}

function Test-CnsVersionIsNewer {
    param(
        [Parameter(Mandatory = $true)][string]$Latest,
        [Parameter(Mandatory = $true)][string]$Current
    )
    try {
        $latestParts = @($Latest.Split('.'))
        $currentParts = @($Current.Split('.'))
        while ($latestParts.Count -lt 3) { $latestParts += '0' }
        while ($currentParts.Count -lt 3) { $currentParts += '0' }
        $l = [Version]::new([int]$latestParts[0], [int]$latestParts[1], [int]$latestParts[2])
        $c = [Version]::new([int]$currentParts[0], [int]$currentParts[1], [int]$currentParts[2])
        return ($l -gt $c)
    }
    catch {
        return ($Latest -ne $Current)
    }
}

function Get-SharePointSiblingGraphUrl {
    <#
    .SYNOPSIS
        Remplace le dernier segment Graph (fichier) par un autre fichier dans le même dossier drive.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][string]$FileName
    )
    $url = $BaseUrl.Trim() -replace '/content$', ''
    if ($url -match '^(?<prefix>.+):/(?<last>[^/]+)$') {
        return ('{0}:/{1}' -f $matches.prefix, $FileName)
    }
    return $null
}

function Get-CurrentVersion {
    <#
    .SYNOPSIS
        Récupère la version actuelle de l'application depuis AppConfig.
    .OUTPUTS
        [string] Version au format "1.0.0" ou "0.0.0" par défaut
    #>
    $version = Get-AppConfig -Key 'AppVersion'
    if ([string]::IsNullOrWhiteSpace($version)) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[UpdateManager] Aucune version trouvée, utilisation 0.0.0' 'WARN' @{}
        }
        return '0.0.0'
    }
    return [string]$version.Trim()
}

function Set-CurrentVersion {
    <#
    .SYNOPSIS
        Met à jour la version de l'application dans AppConfig.
    .PARAMETER Version
        Version au format "1.0.0" (validation basique)
    #>
    param([Parameter(Mandatory = $true)][string]$Version)

    $Version = $Version.Trim()
    if (-not (Test-CnsVersionFormat -Version $Version)) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[UpdateManager] Format de version invalide' 'ERROR' @{ version = $Version }
        }
        throw 'Format de version invalide. Attendu: 1.0.0'
    }

    Set-AppConfig -Key 'AppVersion' -Value $Version
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log '[UpdateManager] Version mise à jour' 'INFO' @{ version = $Version }
    }
}

function Get-LatestVersionFromSharePoint {
    <#
    .SYNOPSIS
        Télécharge le fichier version.txt depuis SharePoint et retourne la version.
    .OUTPUTS
        [string] Dernière version disponible, ou $null en cas d'erreur
    #>
    $baseUrl = Get-SharePointPlanningUrl
    if ([string]::IsNullOrWhiteSpace($baseUrl)) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[UpdateManager] URL SharePoint non configurée' 'WARN' @{}
        }
        return $null
    }

    $versionUrl = Get-SharePointSiblingGraphUrl -BaseUrl $baseUrl -FileName 'version.txt'
    if ([string]::IsNullOrWhiteSpace($versionUrl)) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[UpdateManager] Impossible de construire l URL version.txt' 'WARN' @{}
        }
        return $null
    }

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log '[UpdateManager] Téléchargement version.txt' 'DEBUG' @{ configured = $true }
    }

    try {
        $versionText = Invoke-CnsUpdateWebDownloadString -Url $versionUrl
        if (Test-CnsVersionFormat -Version $versionText) {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log '[UpdateManager] Dernière version disponible' 'INFO' @{ version = $versionText }
            }
            return $versionText
        }

        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[UpdateManager] Format de version invalide dans version.txt' 'WARN' @{ raw = $versionText }
        }
        return $null
    }
    catch {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[UpdateManager] Erreur téléchargement version.txt' 'WARN' @{ message = $_.Exception.Message }
        }
        return $null
    }
}

function Download-Update {
    <#
    .SYNOPSIS
        Télécharge la nouvelle version de l'application depuis SharePoint.
    .PARAMETER Version
        Version à télécharger (ex: "1.0.1")
    .OUTPUTS
        [string] Chemin du fichier téléchargé, ou $null en cas d'échec
    #>
    param([Parameter(Mandatory = $true)][string]$Version)

    if (-not (Test-CnsVersionFormat -Version $Version)) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[UpdateManager] Version invalide pour téléchargement' 'ERROR' @{ version = $Version }
        }
        return $null
    }

    $baseUrl = Get-SharePointPlanningUrl
    if ([string]::IsNullOrWhiteSpace($baseUrl)) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[UpdateManager] URL SharePoint non configurée' 'WARN' @{}
        }
        return $null
    }

    $zipName = "update_v$Version.zip"
    $updateUrl = Get-SharePointSiblingGraphUrl -BaseUrl $baseUrl -FileName $zipName
    if ([string]::IsNullOrWhiteSpace($updateUrl)) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[UpdateManager] Impossible de construire l URL de mise à jour' 'ERROR' @{ version = $Version }
        }
        return $null
    }

    $tempDir = Get-CnsUpdateTempDir

    $zipPath = Join-Path $tempDir $zipName
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    }

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log '[UpdateManager] Téléchargement mise à jour' 'INFO' @{ version = $Version }
    }

    try {
        Invoke-CnsUpdateWebDownloadFile -Url $updateUrl -DestinationPath $zipPath

        $fileInfo = Get-Item -LiteralPath $zipPath
        if ($fileInfo.Length -lt 1024) {
            throw 'Fichier téléchargé trop petit (moins de 1 Ko)'
        }

        Unblock-File -LiteralPath $zipPath -ErrorAction SilentlyContinue

        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[UpdateManager] Téléchargement terminé' 'INFO' @{ bytes = $fileInfo.Length; version = $Version }
        }
        return $zipPath
    }
    catch {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[UpdateManager] Erreur téléchargement' 'ERROR' @{ message = $_.Exception.Message; version = $Version }
        }
        if (Test-Path -LiteralPath $zipPath) {
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        }
        return $null
    }
}

function Apply-Update {
    <#
    .SYNOPSIS
        Applique la mise à jour téléchargée via un script de post-mise à jour différé.
    .PARAMETER UpdateZipPath
        Chemin du fichier ZIP contenant la nouvelle version
    .PARAMETER Version
        Version installée (mise à jour en BDD après copie des fichiers)
    .OUTPUTS
        [bool] True si le script de post-mise à jour a été lancé
    #>
    param(
        [Parameter(Mandatory = $true)][string]$UpdateZipPath,
        [Parameter(Mandatory = $true)][string]$Version
    )

    if (-not (Test-Path -LiteralPath $UpdateZipPath)) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[UpdateManager] Fichier ZIP introuvable' 'ERROR' @{ path = $UpdateZipPath }
        }
        return $false
    }

    $repoRoot = Get-CnsUpdateRepoRoot
    $backupDir = Join-Path $repoRoot ("Backup_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $srcDir = Join-Path $repoRoot 'src'

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log '[UpdateManager] Création du backup' 'INFO' @{ backupDir = $backupDir }
    }

    try {
        if (Test-Path -LiteralPath $srcDir) {
            Copy-Item -LiteralPath $srcDir -Destination $backupDir -Recurse -Force
        }

        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        $tempExtract = Join-Path (Get-CnsUpdateTempDir) ("Update_Extract_{0}" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        if (Test-Path -LiteralPath $tempExtract) {
            Remove-Item -LiteralPath $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
        }
        [System.IO.Compression.ZipFile]::ExtractToDirectory($UpdateZipPath, $tempExtract)

        Get-ChildItem -LiteralPath $tempExtract -Recurse -File -ErrorAction SilentlyContinue |
            ForEach-Object { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue }

        $dbScript = Join-Path $repoRoot 'src\Database\Database.ps1'
        $mainScript = Join-Path $repoRoot 'src\Main.ps1'
        $exePath = $null
        if (Test-IsCompiledExe) {
            try {
                $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
            }
            catch { }
        }
        $postUpdatePath = Join-Path (Get-CnsUpdateLocalDataDir) 'post_update.ps1'

        $restartExeBlock = ''
        if ($exePath) {
            $restartExeBlock = @"
if (Test-Path -LiteralPath '$exePath') {
    `$psi = New-Object System.Diagnostics.ProcessStartInfo
    `$psi.FileName = '$exePath'
    `$psi.UseShellExecute = `$true
    [void][System.Diagnostics.Process]::Start(`$psi)
}
"@
        }
        else {
            $restartExeBlock = @"
if (Test-Path -LiteralPath `$mainScript) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-ExecutionPolicy', 'RemoteSigned', '-File', `$mainScript) -WindowStyle Normal
}
"@
        }

        $postUpdateContent = @"
# Post-mise a jour ConventionDeNommage (genere automatiquement)
`$ErrorActionPreference = 'Stop'
`$repoRoot = '$repoRoot'
`$extractDir = '$tempExtract'
`$newVersion = '$Version'
`$dbScript = '$dbScript'
`$mainScript = '$mainScript'
`$zipPath = '$UpdateZipPath'

Start-Sleep -Seconds 3
try {
    if (Test-Path -LiteralPath `$extractDir) {
        Get-ChildItem -LiteralPath `$extractDir -Recurse -File -ErrorAction SilentlyContinue |
            ForEach-Object { Unblock-File -LiteralPath `$_.FullName -ErrorAction SilentlyContinue }
        Copy-Item -LiteralPath "`$extractDir\*" -Destination `$repoRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath `$dbScript) {
        . `$dbScript
        if (Get-Command Set-AppConfig -ErrorAction SilentlyContinue) {
            Set-AppConfig -Key 'AppVersion' -Value `$newVersion
        }
    }
}
catch {
    Write-Host ("Erreur post-update: {0}" -f `$_.Exception.Message) -ForegroundColor Red
}
finally {
    if (Test-Path -LiteralPath `$extractDir) {
        Remove-Item -LiteralPath `$extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath `$zipPath) {
        Remove-Item -LiteralPath `$zipPath -Force -ErrorAction SilentlyContinue
    }
}
$restartExeBlock
"@
        $postUpdateContent | Set-Content -LiteralPath $postUpdatePath -Encoding UTF8
        Unblock-File -LiteralPath $postUpdatePath -ErrorAction SilentlyContinue

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = "-WindowStyle Hidden -ExecutionPolicy RemoteSigned -File `"$postUpdatePath`""
        $psi.UseShellExecute = $true
        [void][System.Diagnostics.Process]::Start($psi)

        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[UpdateManager] Script de post-mise à jour lancé' 'INFO' @{ version = $Version }
        }
        return $true
    }
    catch {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[UpdateManager] Erreur application update' 'ERROR' @{ message = $_.Exception.Message }
        }
        return $false
    }
}

function Restart-Application {
    <#
    .SYNOPSIS
        Redemarre l'application (script PowerShell ou exe compile).
    #>
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log '[UpdateManager] Redemarrage de l application' 'INFO' @{ compiled = (Test-IsCompiledExe) }
    }

    if (Test-IsCompiledExe) {
        try {
            $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $exePath
            $psi.UseShellExecute = $true
            [void][System.Diagnostics.Process]::Start($psi)
            [Environment]::Exit(0)
            return
        }
        catch {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log '[UpdateManager] Erreur redemarrage exe' 'ERROR' @{ message = $_.Exception.Message }
            }
            return
        }
    }

    $mainScript = Join-Path (Get-CnsUpdateRepoRoot) 'src\Main.ps1'
    if (-not (Test-Path -LiteralPath $mainScript)) {
        $mainScript = Join-Path (Get-CnsUpdateRepoRoot) 'Main.ps1'
    }
    if (-not (Test-Path -LiteralPath $mainScript)) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[UpdateManager] Impossible de localiser Main.ps1' 'ERROR' @{ path = $mainScript }
        }
        return
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-STA -ExecutionPolicy RemoteSigned -File `"$mainScript`""
    $psi.UseShellExecute = $true
    [void][System.Diagnostics.Process]::Start($psi)
    [Environment]::Exit(0)
}

function Check-ForUpdates {
    <#
    .SYNOPSIS
        Vérifie les mises à jour disponibles et propose de les installer.
    .PARAMETER Silent
        Mode silencieux : journalise uniquement, sans MessageBox ni installation.
    #>
    param([switch]$Silent)

    if ($env:CN_SKIP_UPDATE -in @('1', 'true', 'TRUE', 'yes', 'YES')) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[UpdateManager] Vérification ignorée (CN_SKIP_UPDATE)' 'INFO' @{}
        }
        return
    }

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log '[UpdateManager] Vérification des mises à jour' 'INFO' @{}
    }

    $currentVersion = Get-CurrentVersion
    $latestVersion = Get-LatestVersionFromSharePoint

    if ([string]::IsNullOrWhiteSpace($latestVersion)) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[UpdateManager] Impossible de vérifier les mises à jour' 'WARN' @{}
        }
        return
    }

    if (-not (Test-CnsVersionIsNewer -Latest $latestVersion -Current $currentVersion)) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[UpdateManager] Application à jour' 'INFO' @{ version = $currentVersion }
        }
        return
    }

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log '[UpdateManager] Nouvelle version disponible' 'INFO' @{
            current = $currentVersion
            latest  = $latestVersion
        }
    }

    if ($Silent) {
        return
    }

    $result = [System.Windows.Forms.MessageBox]::Show(
        ("Une nouvelle version ({0}) est disponible.`n`nVoulez-vous installer la mise à jour maintenant ?`n`nL'application va redémarrer après l'installation." -f $latestVersion),
        'Mise à jour disponible',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[UpdateManager] Mise à jour refusée par l utilisateur' 'INFO' @{}
        }
        return
    }

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log '[UpdateManager] Téléchargement de la mise à jour' 'INFO' @{ version = $latestVersion }
    }

    $zipPath = Download-Update -Version $latestVersion
    if (-not $zipPath) {
        [System.Windows.Forms.MessageBox]::Show(
            "Le téléchargement de la mise à jour a échoué.`n`nVérifiez votre connexion réseau et réessayez.",
            'Erreur de mise à jour',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }

    $success = Apply-Update -UpdateZipPath $zipPath -Version $latestVersion
    if ($success) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[UpdateManager] Mise à jour planifiée, arrêt de l application' 'INFO' @{ version = $latestVersion }
        }
        [Environment]::Exit(0)
    }
    else {
        [System.Windows.Forms.MessageBox]::Show(
            "L'installation de la mise à jour a échoué.`n`nConsultez les logs pour plus de détails.",
            'Erreur de mise à jour',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

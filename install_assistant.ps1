# install_assistant.ps1 - Installation ASSISTANT (version script, sans exe)
# Usage : .\install_assistant.ps1 [-Centre fontaine] [-Quiet] [-InstallDir path] [-Fresh] [-DesktopShortcut]

param(
    [string]$InstallDir = "$env:LOCALAPPDATA\ASSISTANT",
    [string]$Centre = '',
    [string]$SourceRoot = '',
    [switch]$AddExclusions,
    [switch]$Launch,
    [switch]$Quiet,
    [switch]$Fresh = $true,
    [switch]$DesktopShortcut = $true,
    [switch]$RegisterProgramsEntry = $true
)

$ErrorActionPreference = 'Stop'

$script:InstallCopyFailures = [System.Collections.Generic.List[string]]::new()
$script:InstallDirWasNew = $false

function Ensure-InstalledPs1Utf8Bom {
    <#
    .SYNOPSIS
        Normalise les fichiers .ps1 installes en UTF-8 avec BOM.
        Exclut Graph, ImportExcel et binaires tiers (fichiers verrouilles).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallRoot
    )

    $excludeRoots = @(
        (Join-Path $InstallRoot 'runtime\Graph'),
        (Join-Path $InstallRoot 'runtime\ImportExcel'),
        (Join-Path $InstallRoot 'runtime\poppler'),
        (Join-Path $InstallRoot 'runtime\ghostscript'),
        (Join-Path $InstallRoot 'lib')
    )

    function Write-InstallUtf8BomSafe {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][string]$Content
        )
        $utf8Bom = New-Object System.Text.UTF8Encoding $true
        $maxRetries = 5
        $delayMs = 200
        $leaf = Split-Path -Leaf $Path

        for ($i = 1; $i -le $maxRetries; $i++) {
            try {
                [System.IO.File]::WriteAllText($Path, $Content, $utf8Bom)
                return $true
            }
            catch {
                $msg = [string]$_.Exception.Message
                if ($msg -match 'being used by another process|access to the path|used by another process') {
                    if ($i -eq $maxRetries) {
                        Write-Warning ("UTF-8 BOM echoue : {0} — {1}" -f $leaf, $msg)
                        return $false
                    }
                    Start-Sleep -Milliseconds $delayMs
                    [System.GC]::Collect()
                }
                else {
                    Write-Warning ("UTF-8 BOM erreur : {0} — {1}" -f $leaf, $msg)
                    return $false
                }
            }
        }
        return $false
    }

    $files = @(Get-ChildItem -LiteralPath $InstallRoot -Recurse -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
            Where-Object {
                $path = $_.FullName
                if ($_.Name -eq 'ProxyCmdletDefinitions.ps1') { return $false }
                foreach ($root in $excludeRoots) {
                    if ($path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
                        return $false
                    }
                }
                return $true
            })

    $fixed = 0
    $failed = 0

    foreach ($file in $files) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            if ($hasBom) { continue }

            $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop
            if (Write-InstallUtf8BomSafe -Path $file.FullName -Content $content) {
                $fixed++
            }
            else {
                $failed++
            }
        }
        catch {
            Write-Warning ("UTF-8 BOM skip : {0} — {1}" -f $file.Name, $_.Exception.Message)
            $failed++
        }
    }

    if ($fixed -gt 0) {
        Write-InstallStep "Encodage UTF-8 BOM applique a $fixed script(s) .ps1" 'Yellow'
    }
    if ($failed -gt 0) {
        Write-InstallStep "UTF-8 BOM : $failed script(s) non normalises (modules tiers exclus si verrouilles)" 'Yellow'
    }
}

function Resolve-InstallPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    return $Path
}

function Copy-InstallItem {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string]$ContentRoot = ''
    )
    if (-not (Test-Path -LiteralPath $Source)) { return }
    if (Test-Path -LiteralPath $Source -PathType Container) {
        if (Test-Path -LiteralPath $Destination) {
            Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction SilentlyContinue
        }
        $null = New-Item -ItemType Directory -Path $Destination -Force
        Get-ChildItem -LiteralPath $Source -Recurse -File -Force | ForEach-Object {
            $rel = $_.FullName.Substring($Source.Length).TrimStart('\')
            $destFile = Join-Path $Destination $rel
            $destDir = Split-Path -Parent $destFile
            if (-not (Test-Path -LiteralPath $destDir)) { $null = New-Item -ItemType Directory -Path $destDir -Force }
            $displayPath = if ($ContentRoot) {
                $_.FullName.Substring($ContentRoot.Length).TrimStart('\')
            } else { $rel }
            Copy-InstallFile -SourcePath $_.FullName -DestinationPath $destFile -DisplayPath $displayPath
        }
        return
    }
    $destParent = Split-Path -Parent $Destination
    if ($destParent -and -not (Test-Path -LiteralPath $destParent)) {
        $null = New-Item -ItemType Directory -Path $destParent -Force
    }
    $displayPath = if ($ContentRoot) {
        $Source.Substring($ContentRoot.Length).TrimStart('\')
    } else {
        Split-Path -Leaf $Source
    }
    Copy-InstallFile -SourcePath $Source -DestinationPath $Destination -DisplayPath $displayPath
}

function Copy-InstallFile {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [string]$DisplayPath = ''
    )
    if ([string]::IsNullOrWhiteSpace($DisplayPath)) {
        $DisplayPath = Split-Path -Leaf $SourcePath
    }
    try { Unblock-File -LiteralPath $SourcePath -ErrorAction SilentlyContinue } catch {}

    $targets = [System.Collections.Generic.List[string]]::new()
    $null = $targets.Add($DestinationPath)
    if ($DestinationPath -like '*\PdfTextNormalizer.ps1') {
        $dir = Split-Path -Parent $DestinationPath
        foreach ($altName in @('CnsPdfTextNormalizer.ps1', 'CnsPdfNorm.ps1')) {
            $null = $targets.Add((Join-Path $dir $altName))
        }
    }

    $lastError = $null
    foreach ($targetPath in $targets) {
        $targetDir = Split-Path -Parent $targetPath
        if (-not (Test-Path -LiteralPath $targetDir)) {
            $null = New-Item -ItemType Directory -Path $targetDir -Force
        }
        for ($attempt = 1; $attempt -le 5; $attempt++) {
            try {
                Copy-Item -LiteralPath $SourcePath -Destination $targetPath -Force -ErrorAction Stop
                try { Unblock-File -LiteralPath $targetPath -ErrorAction SilentlyContinue } catch {}
                return
            }
            catch {
                $lastError = $_
                Start-Sleep -Milliseconds (200 * $attempt)
                try {
                    $stream = [System.IO.File]::Open($SourcePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    try {
                        $length = $stream.Length
                        $bytes = New-Object byte[] $length
                        $offset = 0
                        while ($offset -lt $length) {
                            $read = $stream.Read($bytes, $offset, $length - $offset)
                            if ($read -le 0) { break }
                            $offset += $read
                        }
                    }
                    finally {
                        $stream.Close()
                        $stream.Dispose()
                    }
                    [System.IO.File]::WriteAllBytes($targetPath, $bytes)
                    try { Unblock-File -LiteralPath $targetPath -ErrorAction SilentlyContinue } catch {}
                    return
                }
                catch {
                    $lastError = $_
                }
            }
        }
    }

    $errMsg = if ($lastError) { $lastError.Exception.Message } else { 'erreur inconnue' }
    $null = $script:InstallCopyFailures.Add("$DisplayPath ($errMsg)")
    if (-not $Quiet) {
        Write-InstallStep "  Echec copie : $DisplayPath" 'Red'
        Write-InstallStep "     $errMsg" 'Red'
    }
}

function Write-InstallStep {
    param([string]$Message, [string]$Color = 'White')
    Write-Host $Message -ForegroundColor $Color
}

function Initialize-AssistantImportExcelModule {
    param([Parameter(Mandatory = $true)][string]$InstallDir)

    Write-InstallStep 'Verification du module ImportExcel...' 'Yellow'
    $bundledPsd1 = Join-Path $InstallDir 'runtime\ImportExcel\ImportExcel.psd1'
    if (Test-Path -LiteralPath $bundledPsd1) {
        try {
            Import-Module -Name $bundledPsd1 -Force -ErrorAction Stop
            Write-InstallStep 'ImportExcel charge depuis runtime/' 'Green'
            return $true
        }
        catch {
            Write-InstallStep ("ImportExcel runtime : echec chargement - $($_.Exception.Message)") 'Yellow'
        }
    }
    else {
        Write-InstallStep 'ImportExcel absent du package (runtime/ImportExcel).' 'Yellow'
    }

    if (Get-Module -Name ImportExcel -ListAvailable -ErrorAction SilentlyContinue) {
        try {
            Import-Module -Name ImportExcel -Force -ErrorAction Stop
            Write-InstallStep 'ImportExcel charge depuis les modules PowerShell' 'Green'
            return $true
        }
        catch {
            Write-InstallStep ("ImportExcel systeme : echec chargement - $($_.Exception.Message)") 'Yellow'
        }
    }

    Write-InstallStep 'Tentative installation ImportExcel depuis PSGallery (connexion Internet requise)...' 'Yellow'
    try {
        Install-Module -Name ImportExcel -Scope CurrentUser -Force -ErrorAction Stop
        Import-Module -Name ImportExcel -Force -ErrorAction Stop
        Write-InstallStep 'ImportExcel installe depuis PSGallery' 'Green'
        return $true
    }
    catch {
        Write-InstallStep ("ImportExcel non disponible : $($_.Exception.Message)") 'Yellow'
        Write-InstallStep 'Le planning Excel necessitera ImportExcel (runtime/ ou Install-Module).' 'Yellow'
        return $false
    }
}

function Register-AssistantBundledGraphModulePath {
    param([Parameter(Mandatory = $true)][string]$InstallDir)
    $graphRoot = Join-Path $InstallDir 'runtime\Graph'
    if (-not (Test-Path -LiteralPath $graphRoot)) { return $false }
    if ($env:PSModulePath -notlike "*$graphRoot*") {
        $env:PSModulePath = "$graphRoot;$env:PSModulePath"
    }
    return $true
}

function Initialize-AssistantGraphModule {
    param([Parameter(Mandatory = $true)][string]$InstallDir)

    Write-InstallStep 'Verification du module Microsoft.Graph...' 'Yellow'
    $bundledPsd1 = Join-Path $InstallDir 'runtime\Graph\Microsoft.Graph.Authentication\Microsoft.Graph.Authentication.psd1'
    if (-not (Test-Path -LiteralPath $bundledPsd1)) {
        $nested = Get-ChildItem -LiteralPath (Join-Path $InstallDir 'runtime\Graph\Microsoft.Graph.Authentication') -Recurse -Filter 'Microsoft.Graph.Authentication.psd1' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($nested) { $bundledPsd1 = $nested.FullName }
    }
    if (Test-Path -LiteralPath $bundledPsd1) {
        try {
            $null = Register-AssistantBundledGraphModulePath -InstallDir $InstallDir
            Import-Module -Name $bundledPsd1 -Force -ErrorAction Stop
            Write-InstallStep 'Microsoft.Graph charge depuis runtime/Graph/' 'Green'
            return $true
        }
        catch {
            Write-InstallStep ("Microsoft.Graph runtime : echec chargement - $($_.Exception.Message)") 'Yellow'
        }
    }
    else {
        Write-InstallStep 'Microsoft.Graph absent du package (runtime/Graph).' 'Yellow'
    }

    if (Get-Module -Name Microsoft.Graph.Authentication -ListAvailable -ErrorAction SilentlyContinue) {
        try {
            Import-Module -Name Microsoft.Graph.Authentication -Force -ErrorAction Stop
            Write-InstallStep 'Microsoft.Graph charge depuis les modules PowerShell' 'Green'
            return $true
        }
        catch {
            Write-InstallStep ("Microsoft.Graph systeme : echec chargement - $($_.Exception.Message)") 'Yellow'
        }
    }

    Write-InstallStep 'Tentative installation Microsoft.Graph depuis PSGallery (connexion Internet requise)...' 'Yellow'
    try {
        Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Import-Module -Name Microsoft.Graph.Authentication -Force -ErrorAction Stop
        Write-InstallStep 'Microsoft.Graph installe depuis PSGallery' 'Green'
        return $true
    }
    catch {
        Write-InstallStep ("Microsoft.Graph non disponible : $($_.Exception.Message)") 'Yellow'
        Write-InstallStep 'SharePoint necessitera Microsoft.Graph (runtime/Graph ou Install-Module).' 'Yellow'
        return $false
    }
}

function Ensure-InstallPopplerLayout {
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot
    )
    $popplerRoot = Join-Path $InstallRoot 'runtime\poppler'
    if (-not (Test-Path -LiteralPath $popplerRoot)) { return $false }
    $flatExe = Join-Path $popplerRoot 'pdftotext.exe'
    if (Test-Path -LiteralPath $flatExe) { return $true }
    $nested = Get-ChildItem -LiteralPath $popplerRoot -Recurse -Filter 'pdftotext.exe' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $nested) { return $false }
    $binDir = $nested.Directory.FullName
    foreach ($file in @(Get-ChildItem -LiteralPath $binDir -File -Force -ErrorAction SilentlyContinue)) {
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $popplerRoot $file.Name) -Force -ErrorAction SilentlyContinue
    }
    return (Test-Path -LiteralPath $flatExe)
}

function Test-InstallPackage {
    param([Parameter(Mandatory = $true)][string]$PackageDir)
    $required = @(
        'ASSISTANT.bat',
        'ASSISTANT.ico',
        'src\Main.ps1',
        'src\LaunchAssistant.ps1',
        'config\centres.json',
        'lib\System.Data.SQLite.dll',
        'lib\SQLite.Interop.dll'
    )
    foreach ($rel in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $PackageDir $rel))) {
            throw "Package incomplet : $rel manquant dans $PackageDir. Relancez .\build_package.ps1 -Clean"
        }
    }
    $hasNormalizer = @(
        'src\ODM\PdfPlanningOptimizer\Extractors\PdfTextNormalizer.ps1',
        'src\ODM\PdfPlanningOptimizer\Extractors\CnsPdfTextNormalizer.ps1',
        'src\ODM\PdfPlanningOptimizer\Extractors\CnsPdfNorm.ps1'
    ) | Where-Object { Test-Path -LiteralPath (Join-Path $PackageDir $_) } | Select-Object -First 1
    if (-not $hasNormalizer) {
        throw 'Package incomplet : PdfTextNormalizer / CnsPdfTextNormalizer manquant. Relancez .\build_package.ps1 -Clean'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $PackageDir 'runtime\ImportExcel\ImportExcel.psd1'))) {
        throw 'Package incomplet : runtime\ImportExcel manquant. Reconstruisez le package sur une machine avec ImportExcel installe.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $PackageDir 'runtime\Graph\Microsoft.Graph.Authentication\Microsoft.Graph.Authentication.psd1'))) {
        $graphNested = Get-ChildItem -LiteralPath (Join-Path $PackageDir 'runtime\Graph\Microsoft.Graph.Authentication') -Recurse -Filter 'Microsoft.Graph.Authentication.psd1' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $graphNested) {
            throw 'Package incomplet : runtime\Graph manquant. Reconstruisez le package sur une machine avec Microsoft.Graph installe.'
        }
    }
    $pdftotext = Get-ChildItem -LiteralPath (Join-Path $PackageDir 'runtime\poppler') -Recurse -Filter 'pdftotext.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $pdftotext) {
        throw 'Package incomplet : pdftotext.exe manquant dans runtime\poppler. Relancez .\build_package.ps1 -Clean'
    }
    $gsEmbedded = Join-Path $PackageDir 'runtime\ghostscript\gswin64c.exe'
    if (-not (Test-Path -LiteralPath $gsEmbedded)) {
        throw 'Package incomplet : runtime\ghostscript\gswin64c.exe manquant. Relancez .\build_package.ps1 -Clean'
    }
    $gsDll = Join-Path $PackageDir 'runtime\ghostscript\gsdll64.dll'
    if (-not (Test-Path -LiteralPath $gsDll)) {
        throw 'Package incomplet : runtime\ghostscript\gsdll64.dll manquant. Relancez .\build_package.ps1 -Clean'
    }
    $qpdf = Get-ChildItem -LiteralPath (Join-Path $PackageDir 'lib\qpdf') -Recurse -Filter 'qpdf.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $qpdf) {
        throw 'Package incomplet : qpdf.exe manquant dans lib\qpdf. Relancez .\build_package.ps1 -Clean'
    }
    foreach ($rel in @(
        'templates\CertificatDeDestruction.xlsx',
        'templates\BilanDeCollecte.xlsx',
        'templates\CeaPointsDeCollectes.xlsx',
        'templates\FT.xlsx'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $PackageDir $rel))) {
            throw "Package incomplet : $rel manquant dans $PackageDir. Relancez .\build_package.ps1 -Clean"
        }
    }
}

function New-AssistantShortcut {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutPath,
        [Parameter(Mandatory = $true)][string]$LauncherBatPath,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [string]$IconPath = ''
    )
    if (-not (Test-Path -LiteralPath $LauncherBatPath)) {
        throw "Lanceur introuvable : $LauncherBatPath"
    }
    $shortcutDir = Split-Path -Parent $ShortcutPath
    if (-not (Test-Path -LiteralPath $shortcutDir)) {
        $null = New-Item -ItemType Directory -Path $shortcutDir -Force
    }
    $ws = New-Object -ComObject WScript.Shell
    $shortcut = $ws.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $LauncherBatPath
    $shortcut.Arguments = ''
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Description = 'ASSISTANT - Elise Alpes'
    $shortcut.WindowStyle = 1
    if (-not [string]::IsNullOrWhiteSpace($IconPath) -and (Test-Path -LiteralPath $IconPath)) {
        $shortcut.IconLocation = ('{0},0' -f (Resolve-Path -LiteralPath $IconPath).Path)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($IconPath)) {
        Write-Warning "Icone introuvable pour le raccourci : $IconPath"
    }
    $shortcut.Save()
}

function Register-AssistantPdfContextMenu {
    param(
        [Parameter(Mandatory = $true)][string]$InstallDir,
        [Parameter(Mandatory = $true)][string]$LauncherBatPath,
        [string]$IconPath = '',
        [string]$MenuLabel = 'Assistant'
    )
    $shellKey = 'HKCU:\Software\Classes\SystemFileAssociations\.pdf\shell\ASSISTANT'
    $cmdKey = Join-Path $shellKey 'command'

    if (-not (Test-Path -LiteralPath $LauncherBatPath)) {
        throw "ASSISTANT.bat introuvable : $LauncherBatPath"
    }
    $batPath = (Resolve-Path -LiteralPath $LauncherBatPath).Path

    $iconCandidate = $IconPath
    if ([string]::IsNullOrWhiteSpace($iconCandidate)) {
        $iconCandidate = Join-Path $InstallDir 'ASSISTANT.ico'
    }
    if (-not (Test-Path -LiteralPath $iconCandidate)) {
        throw "ASSISTANT.ico introuvable : $iconCandidate"
    }
    $iconValue = (Resolve-Path -LiteralPath $iconCandidate).Path
    if ($iconValue -notmatch ',\d+$') {
        $iconValue = '{0},0' -f $iconValue
    }

    $cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
    if (-not (Test-Path -LiteralPath $cmdExe)) {
        throw "cmd.exe introuvable : $cmdExe"
    }
    $commandValue = ('"{0}" /c ""{1}" "%1""' -f $cmdExe, $batPath)

    if (-not (Test-Path -LiteralPath $shellKey)) {
        $null = New-Item -Path $shellKey -Force
    }
    if (-not (Test-Path -LiteralPath $cmdKey)) {
        $null = New-Item -Path $cmdKey -Force
    }
    Set-ItemProperty -LiteralPath $shellKey -Name '(Default)' -Value $MenuLabel
    Set-ItemProperty -LiteralPath $shellKey -Name 'Icon' -Value $iconValue
    Set-ItemProperty -LiteralPath $cmdKey -Name '(Default)' -Value $commandValue

    $verify = Get-ItemProperty -LiteralPath $shellKey -ErrorAction Stop
    $verifyCmd = Get-ItemProperty -LiteralPath $cmdKey -ErrorAction Stop
    if ($verify.'(default)' -ne $MenuLabel) {
        throw "Verification registre echouee : label attendu '$MenuLabel', trouve '$($verify.'(default)')'"
    }
    if ($verify.Icon -ne $iconValue) {
        throw "Verification registre echouee : Icon attendu '$iconValue', trouve '$($verify.Icon)'"
    }
    if ($verifyCmd.'(default)' -ne $commandValue) {
        throw "Verification registre echouee : commande invalide '$($verifyCmd.'(default)')'"
    }
}

function Register-AssistantUninstallRegistry {
    param(
        [Parameter(Mandatory = $true)][string]$InstallDir,
        [string]$DisplayName = 'ASSISTANT - Elise Alpes',
        [string]$Publisher = 'Elise Alpes',
        [string]$Version = '1.0.0'
    )
    $versionFile = Join-Path $InstallDir 'version.txt'
    if (Test-Path -LiteralPath $versionFile) {
        $Version = (Get-Content -LiteralPath $versionFile -Raw).Trim()
    }
    $uninstallPs1 = Join-Path $InstallDir 'uninstall_assistant.ps1'
    $uninstallCmd = "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$uninstallPs1`""
    $keyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ASSISTANT_EliseAlpes'
    if (-not (Test-Path -LiteralPath $keyPath)) {
        $null = New-Item -Path $keyPath -Force
    }
    Set-ItemProperty -LiteralPath $keyPath -Name 'DisplayName' -Value $DisplayName
    Set-ItemProperty -LiteralPath $keyPath -Name 'DisplayVersion' -Value $Version
    Set-ItemProperty -LiteralPath $keyPath -Name 'Publisher' -Value $Publisher
    Set-ItemProperty -LiteralPath $keyPath -Name 'InstallLocation' -Value $InstallDir
    Set-ItemProperty -LiteralPath $keyPath -Name 'UninstallString' -Value $uninstallCmd
    $iconPath = Join-Path $InstallDir 'ASSISTANT.ico'
    if (Test-Path -LiteralPath $iconPath) {
        Set-ItemProperty -LiteralPath $keyPath -Name 'DisplayIcon' -Value $iconPath
    }
    Set-ItemProperty -LiteralPath $keyPath -Name 'NoModify' -Value 1 -Type DWord
    Set-ItemProperty -LiteralPath $keyPath -Name 'NoRepair' -Value 1 -Type DWord
}

Write-InstallStep '=== Installation ASSISTANT (version script) ===' 'Cyan'

try {
$packageDir = Resolve-InstallPath (Split-Path -Parent $MyInvocation.MyCommand.Path)
$contentRoot = if ([string]::IsNullOrWhiteSpace($SourceRoot)) { $packageDir } else { Resolve-InstallPath $SourceRoot }
if (Test-Path -LiteralPath $InstallDir) {
    $InstallDir = Resolve-InstallPath $InstallDir
}
$mainScript = Join-Path $contentRoot 'src\Main.ps1'
$launcherBat = Join-Path $packageDir 'ASSISTANT.bat'
if (-not (Test-Path -LiteralPath $launcherBat)) {
    $launcherBat = Join-Path $contentRoot 'ASSISTANT.bat'
}

Test-InstallPackage -PackageDir $contentRoot

$centresJson = Join-Path $contentRoot 'config\centres.json'
$centresData = Get-Content -LiteralPath $centresJson -Raw -Encoding UTF8 | ConvertFrom-Json
$centres = @($centresData.centres)

if ([string]::IsNullOrWhiteSpace($Centre)) {
    if ($Quiet) {
        throw 'Mode silencieux : parametre -Centre obligatoire (argonay, bourg-en-bresse, fontaine, valence)'
    }
    else {
        Write-Host ''
        Write-InstallStep 'Selectionnez le centre a installer :' 'Cyan'
        for ($i = 0; $i -lt $centres.Count; $i++) {
            $c = $centres[$i]
            Write-Host ("  {0}. {1}" -f ($i + 1), $c.name)
        }
        Write-Host '  C. Annuler'
        $choice = Read-Host 'Votre choix (numero)'
        if ($choice -eq 'C' -or $choice -eq 'c') {
            Write-InstallStep 'Installation annulee.' 'Yellow'
            exit 0
        }
        $choiceNum = 0
        if (-not [int]::TryParse($choice, [ref]$choiceNum)) {
            throw 'Choix invalide'
        }
        $idx = $choiceNum - 1
        if ($idx -lt 0 -or $idx -ge $centres.Count) {
            throw 'Choix invalide'
        }
        $Centre = $centres[$idx].id
    }
}

$Centre = $Centre.Trim().ToLowerInvariant()
$selectedCentre = $centres | Where-Object { $_.id -eq $Centre } | Select-Object -First 1
if (-not $selectedCentre) {
    $valid = ($centres | ForEach-Object { $_.id }) -join ', '
    throw "Centre '$Centre' non trouve. Centres valides : $valid"
}

Write-Host ''
Write-InstallStep ("Installation pour : {0}" -f $selectedCentre.name) 'Green'

if ($AddExclusions) {
    Write-InstallStep 'Ajout des exclusions antivirus (optionnel)...'
    if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {
        Add-MpPreference -ExclusionPath $InstallDir -ErrorAction SilentlyContinue
        Add-MpPreference -ExclusionPath (Join-Path $env:LOCALAPPDATA 'ASSISTANT') -ErrorAction SilentlyContinue
        Write-InstallStep 'Exclusions Windows Defender ajoutees'
    }
    else {
        Write-Warning 'Add-MpPreference indisponible (droits admin ou Defender absent).'
    }
}

if (-not (Test-Path -LiteralPath $InstallDir)) {
    $null = New-Item -ItemType Directory -Path $InstallDir -Force
    $script:InstallDirWasNew = $true
    Write-InstallStep "Dossier cree : $InstallDir"
}

Write-InstallStep 'Copie des fichiers...' 'Yellow'
$itemsFromContent = @('src', 'Data', 'lib', 'runtime', 'config', 'templates', 'version.txt')
foreach ($item in $itemsFromContent) {
    $source = Join-Path $contentRoot $item
    if (-not (Test-Path -LiteralPath $source)) { continue }
    $dest = Join-Path $InstallDir $item
    if (Test-Path -LiteralPath $dest) {
        Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
    }
    Copy-InstallItem -Source $source -Destination $dest -ContentRoot $contentRoot
}
$itemsFromPackage = @('ASSISTANT.bat', 'ASSISTANT.ico', 'INSTALL.bat', 'install_assistant.ps1', 'install_gui.ps1', 'fix_installation.ps1', 'Register-AssistantContextMenu.ps1', 'uninstall_assistant.ps1')
foreach ($item in $itemsFromPackage) {
    $source = Join-Path $packageDir $item
    if (-not (Test-Path -LiteralPath $source)) { continue }
    Copy-InstallItem -Source $source -Destination (Join-Path $InstallDir $item) -ContentRoot $packageDir
}
$registerCtxSource = Join-Path $packageDir 'Tools\Register-AssistantContextMenu.ps1'
if (-not (Test-Path -LiteralPath $registerCtxSource)) {
    $registerCtxSource = Join-Path $packageDir 'Register-AssistantContextMenu.ps1'
}
if (Test-Path -LiteralPath $registerCtxSource) {
    $toolsInstallDir = Join-Path $InstallDir 'Tools'
    if (-not (Test-Path -LiteralPath $toolsInstallDir)) {
        $null = New-Item -ItemType Directory -Path $toolsInstallDir -Force
    }
    Copy-InstallItem -Source $registerCtxSource -Destination (Join-Path $toolsInstallDir 'Register-AssistantContextMenu.ps1') -ContentRoot $packageDir
}

if ($script:InstallCopyFailures.Count -gt 0) {
    Write-Host ''
    Write-InstallStep ("INSTALLATION ECHOUEE - $($script:InstallCopyFailures.Count) fichier(s) non copies") 'Red'
    Write-InstallStep 'Fichiers bloques :' 'Yellow'
    foreach ($failed in $script:InstallCopyFailures) {
        Write-InstallStep "  - $failed" 'Yellow'
    }
    Write-InstallStep 'Solution : desactivez temporairement l antivirus et reessayez.' 'Cyan'
    Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-InstallStep 'Dossier partiel supprime.' 'Yellow'
    throw "Copie echouee : $($script:InstallCopyFailures.Count) fichier(s) bloques"
}

$copiedCount = (Get-ChildItem -LiteralPath $InstallDir -Recurse -File -Force | Measure-Object).Count
Write-InstallStep "Copie terminee ($copiedCount fichiers)" 'Green'

if (Ensure-InstallPopplerLayout -InstallRoot $InstallDir) {
    Write-InstallStep 'pdftotext.exe disponible dans runtime\poppler\' 'Green'
}
else {
    Write-InstallStep 'pdftotext.exe absent de runtime\poppler\ (planning PDF desactive)' 'Yellow'
}

$null = Initialize-AssistantImportExcelModule -InstallDir $InstallDir
$null = Initialize-AssistantGraphModule -InstallDir $InstallDir

Test-InstallPackage -PackageDir $InstallDir

if ($Fresh) {
    $dbPath = Join-Path $InstallDir 'Data\gestion.db'
    if (Test-Path -LiteralPath $dbPath) {
        Remove-Item -LiteralPath $dbPath -Force
        Write-InstallStep 'Ancienne base supprimee (evite centre obsolete type Lyon)' 'Yellow'
    }
}

Write-InstallStep ("Configuration du centre {0}..." -f $selectedCentre.name)
$dbScript = Join-Path $InstallDir 'src\Database\Database.ps1'
. $dbScript
$configManagerScript = Join-Path $InstallDir 'src\Core\ConfigManager.ps1'
if (-not (Test-Path -LiteralPath $configManagerScript)) {
    throw "ConfigManager.ps1 introuvable : $configManagerScript"
}
. $configManagerScript
$null = Initialize-Database
if (-not (Set-CurrentCentre -CentreId ([string]$selectedCentre.id))) {
    throw ("Echec configuration centre {0} en base de donnees" -f $selectedCentre.name)
}
if (-not (Test-CentreAppConfigurationComplete)) {
    throw 'Verification post-installation : CentreId, CentreName ou SharePointApiUrl manquant en BDD'
}
$versionFile = Join-Path $InstallDir 'version.txt'
if (Test-Path -LiteralPath $versionFile) {
    Set-AppConfig -Key 'AppVersion' -Value ((Get-Content -LiteralPath $versionFile -Raw).Trim())
}
Write-InstallStep ("Centre configure : {0}" -f $selectedCentre.name) 'Green'

Get-ChildItem -Path $InstallDir -Recurse -File -Filter '*.ps1' | Unblock-File -ErrorAction SilentlyContinue
Ensure-InstalledPs1Utf8Bom -InstallRoot $InstallDir

$installedMain = Join-Path $InstallDir 'src\Main.ps1'
$installedBat = Join-Path $InstallDir 'ASSISTANT.bat'
$installedIcon = Join-Path $InstallDir 'ASSISTANT.ico'
$shortcutCreated = $false
foreach ($shortcutPath in @(
    (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\ASSISTANT.lnk'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\ASSISTANT.lnk')
)) {
    try {
        New-AssistantShortcut -ShortcutPath $shortcutPath -LauncherBatPath $installedBat -WorkingDirectory $InstallDir -IconPath $installedIcon
        Write-InstallStep "Raccourci cree : $shortcutPath"
        $shortcutCreated = $true
        break
    }
    catch {
        Write-Warning "Raccourci non cree a $shortcutPath : $($_.Exception.Message)"
    }
}

if ($DesktopShortcut) {
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        if (-not [string]::IsNullOrWhiteSpace($desktop)) {
            $desktopLnk = Join-Path $desktop 'ASSISTANT.lnk'
            New-AssistantShortcut -ShortcutPath $desktopLnk -LauncherBatPath $installedBat -WorkingDirectory $InstallDir -IconPath $installedIcon
            Write-InstallStep "Raccourci bureau cree : $desktopLnk"
            $shortcutCreated = $true
        }
    }
    catch {
        Write-Warning "Raccourci bureau non cree : $($_.Exception.Message)"
    }
}

if ($RegisterProgramsEntry) {
    try {
        $uninstallScript = Join-Path $InstallDir 'uninstall_assistant.ps1'
        if (-not (Test-Path -LiteralPath $uninstallScript)) {
            $uninstallSource = Join-Path $packageDir 'uninstall_assistant.ps1'
            if (Test-Path -LiteralPath $uninstallSource) {
                Copy-Item -LiteralPath $uninstallSource -Destination $uninstallScript -Force
            }
        }
        if (Test-Path -LiteralPath $uninstallScript) {
            Register-AssistantUninstallRegistry -InstallDir $InstallDir
            Write-InstallStep 'Entree ajoutee dans Programmes et fonctionnalites (Windows)'
        }
        else {
            Write-Warning 'uninstall_assistant.ps1 manquant — pas d entree Programmes et fonctionnalites'
        }
    }
    catch {
        Write-Warning "Entree Programmes et fonctionnalites non creee : $($_.Exception.Message)"
    }
}

try {
    Register-AssistantPdfContextMenu -InstallDir $InstallDir -LauncherBatPath $installedBat -IconPath $installedIcon
    Write-InstallStep 'Menu contextuel PDF enregistre (clic droit)'
}
catch {
    Write-Warning "Menu contextuel PDF non enregistre : $($_.Exception.Message)"
}

if (-not $shortcutCreated) {
    Write-Warning 'Aucun raccourci cree. Lancez ASSISTANT.bat manuellement.'
}

Write-Host ''
Write-InstallStep 'Installation terminee.' 'Green'
$env:ASSISTANT_INSTALL_DIR = $InstallDir
Write-InstallStep ("Centre installe : {0}" -f $selectedCentre.name)
Write-InstallStep ("URL SharePoint : {0}" -f $selectedCentre.sharePointApiUrl)

if ($Launch) {
    Write-InstallStep 'Lancement de l application...'
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Start-Process -FilePath $psExe `
        -ArgumentList "-WindowStyle Hidden -STA -ExecutionPolicy Bypass -File `"$installedMain`"" `
        -WorkingDirectory $InstallDir
}

Write-Host ''
Write-InstallStep 'Pour lancer : Menu Demarrer > ASSISTANT ou raccourci bureau'
Write-InstallStep ("  ou : $(Join-Path $InstallDir 'ASSISTANT.bat')")

if ($env:ASSISTANT_INSTALL_PAUSE -eq '1') {
    Write-Host ''
    Read-Host 'Appuyez sur Entree pour fermer'
}
}
catch {
    Write-Host ''
    Write-InstallStep ("ERREUR : $($_.Exception.Message)") 'Red'
    if (-not $Quiet) {
        Write-Host ''
        Write-Host 'Astuce : utilisez INSTALL.bat (double-clic) pour une installation graphique.'
        Read-Host 'Appuyez sur Entree pour fermer'
        exit 1
    }
    throw
}

if (-not $Quiet) {
    Write-Host ''
    Read-Host 'Appuyez sur Entree pour fermer'
}

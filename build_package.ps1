# build_package.ps1 - Preparation du package ASSISTANT (version script, sans exe)
# Execution : .\build_package.ps1 [-Version "1.0.8"] [-OutputDir "output"] [-Clean]

param(
    [string]$Version = '1.0.0',
    [string]$OutputDir = 'package',
    [string]$SrcRoot = '',
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'

function Write-BuildStep { param([string]$Message) Write-Host "`n=== $Message ===" -ForegroundColor Cyan }
function Write-BuildInfo { param([string]$Message) Write-Host "  $Message" -ForegroundColor Gray }
function Write-BuildSuccess { param([string]$Message) Write-Host "[OK] $Message" -ForegroundColor Green }
function Write-BuildFail { param([string]$Message) Write-Host "[ERREUR] $Message" -ForegroundColor Red }
function Write-BuildWarn { param([string]$Message) Write-Host "[AVERT] $Message" -ForegroundColor Yellow }

function Copy-FileResilient {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )
    $destDir = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $destDir)) {
        $null = New-Item -ItemType Directory -Path $destDir -Force
    }
    try { Unblock-File -LiteralPath $SourcePath -ErrorAction SilentlyContinue } catch {}
    try {
        Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force -ErrorAction Stop
        return $true
    }
    catch {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($SourcePath)
            [System.IO.File]::WriteAllBytes($DestinationPath, $bytes)
            return $true
        }
        catch {
            return $false
        }
    }
}

function Ensure-PackagePs1Utf8Bom {
    <#
    .SYNOPSIS
        Normalise les fichiers .ps1 du package en UTF-8 avec BOM.
        Exclut les dossiers tiers (Graph, ImportExcel, binaires) pour eviter les verrous.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageRoot
    )

    $excludeRoots = @(
        (Join-Path $PackageRoot 'runtime\Graph'),
        (Join-Path $PackageRoot 'runtime\ImportExcel'),
        (Join-Path $PackageRoot 'runtime\poppler'),
        (Join-Path $PackageRoot 'runtime\ghostscript'),
        (Join-Path $PackageRoot 'lib')
    )

    function Write-PackageUtf8BomSafe {
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
                        Write-BuildWarn ("UTF-8 BOM echoue apres {0} tentatives : {1} — {2}" -f $maxRetries, $leaf, $msg)
                        return $false
                    }
                    Write-BuildInfo ("Retry UTF-8 BOM {0}/{1} : {2}" -f $i, $maxRetries, $leaf)
                    Start-Sleep -Milliseconds $delayMs
                    [System.GC]::Collect()
                }
                else {
                    Write-BuildWarn ("UTF-8 BOM erreur : {0} — {1}" -f $leaf, $msg)
                    return $false
                }
            }
        }
        return $false
    }

    $files = @(Get-ChildItem -LiteralPath $PackageRoot -Recurse -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
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

    if ($files.Count -lt 1) {
        Write-BuildSuccess 'Aucun script .ps1 a normaliser (hors dossiers tiers)'
        return $true
    }

    $fixed = 0
    $alreadyOk = 0
    $failed = 0
    $current = 0

    foreach ($file in $files) {
        $current++
        Write-Progress -Activity 'Normalisation UTF-8 BOM' -Status ("Traitement {0}/{1}" -f $current, $files.Count) `
            -PercentComplete ([math]::Round(($current / $files.Count) * 100)) -CurrentOperation $file.Name

        try {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            if ($hasBom) {
                $alreadyOk++
                continue
            }

            $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop
            if (Write-PackageUtf8BomSafe -Path $file.FullName -Content $content) {
                $fixed++
            }
            else {
                $failed++
            }
        }
        catch {
            Write-BuildWarn ("UTF-8 BOM skip : {0} — {1}" -f $file.Name, $_.Exception.Message)
            $failed++
        }
    }

    Write-Progress -Activity 'Normalisation UTF-8 BOM' -Completed

    if ($fixed -gt 0) {
        Write-BuildSuccess ("UTF-8 BOM ajoute a {0} fichier(s) .ps1" -f $fixed)
    }
    if ($alreadyOk -gt 0) {
        Write-BuildInfo ("{0} fichier(s) .ps1 deja en UTF-8 BOM" -f $alreadyOk)
    }
    if ($failed -gt 0) {
        Write-BuildWarn ("Normalisation UTF-8 BOM : {0} echec(s)" -f $failed)
    }
    elseif ($fixed -eq 0) {
        Write-BuildSuccess 'Encodage UTF-8 BOM deja present sur les scripts applicatifs'
    }

    Write-BuildInfo ("Resume UTF-8 BOM : {0} corriges, {1} deja OK, {2} echecs (Graph/ImportExcel exclus)" -f $fixed, $alreadyOk, $failed)
    return ($failed -eq 0)
}

function Copy-DeployDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDir,
        [Parameter(Mandatory = $true)][string]$TargetDir,
        [string[]]$ExcludeFileNames = @()
    )
    if (Test-Path -LiteralPath $TargetDir) {
        Remove-Item -LiteralPath $TargetDir -Recurse -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 100
    }
    $null = New-Item -ItemType Directory -Path $TargetDir -Force

    Get-ChildItem -LiteralPath $SourceDir -Recurse -File -Force -ErrorAction SilentlyContinue |
        ForEach-Object { try { Unblock-File -LiteralPath $_.FullName -ErrorAction SilentlyContinue } catch {} }

    $robocopy = Join-Path $env:SystemRoot 'System32\robocopy.exe'
    if (Test-Path -LiteralPath $robocopy) {
        & $robocopy $SourceDir $TargetDir /E /R:2 /W:1 /NFL /NDL /NJH /NJS /nc /ns /np
        $robocopyExit = $LASTEXITCODE
        if ($robocopyExit -ge 8) {
            Write-BuildWarn "robocopy code $robocopyExit pour $SourceDir - repli copie fichier par fichier"
        }
        elseif ($robocopyExit -ge 0) {
            $global:LASTEXITCODE = 0
        }
    }

    $failed = [System.Collections.Generic.List[string]]::new()
    Get-ChildItem -LiteralPath $SourceDir -Recurse -File -Force | ForEach-Object {
        if ($ExcludeFileNames -contains $_.Name) { return }
        $relative = $_.FullName.Substring($SourceDir.Length).TrimStart('\')
        $destFile = Join-Path $TargetDir $relative
        if (Test-Path -LiteralPath $destFile) {
            try {
                if ((Get-Item -LiteralPath $destFile -ErrorAction Stop).Length -eq $_.Length) { return }
            }
            catch {
                # Fichier supprime par l'antivirus entre la copie et la verification : recopier
            }
        }
        if (-not (Copy-FileResilient -SourcePath $_.FullName -DestinationPath $destFile)) {
            if ($_.Name -eq 'PdfTextNormalizer.ps1') {
                foreach ($altName in @('CnsPdfTextNormalizer.ps1', 'CnsPdfNorm.ps1')) {
                    $altDest = Join-Path $TargetDir (($relative -replace 'PdfTextNormalizer\.ps1$', $altName))
                    if (Copy-FileResilient -SourcePath $_.FullName -DestinationPath $altDest) {
                        Write-BuildWarn "PdfTextNormalizer.ps1 copie sous $altName (antivirus)"
                        return
                    }
                }
            }
            $failed.Add($relative)
        }
    }

    foreach ($excludeName in $ExcludeFileNames) {
        Get-ChildItem -LiteralPath $TargetDir -Recurse -Filter $excludeName -File -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    }

    if ($failed.Count -gt 0) {
        Write-BuildFail ("Echec copie de {0} fichier(s) depuis {1}" -f $failed.Count, $SourceDir)
        $failed | Select-Object -First 10 | ForEach-Object { Write-BuildFail "  - $_" }
        throw "Copie incomplete : $SourceDir"
    }
}

function Ensure-PackageGhostscriptLayout {
    param(
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [string]$RepoRoot = ''
    )
    $gsDestDir = Join-Path $PackageRoot 'runtime\ghostscript'
    $gsExeDest = Join-Path $gsDestDir 'gswin64c.exe'
    $gsDllDest = Join-Path $gsDestDir 'gsdll64.dll'
    if ((Test-Path -LiteralPath $gsExeDest) -and (Test-Path -LiteralPath $gsDllDest)) {
        Write-BuildSuccess 'runtime\ghostscript\gswin64c.exe (deja present)'
        return $true
    }

    $sources = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        [void]$sources.Add((Join-Path $RepoRoot 'runtime\ghostscript'))
    }
    $gsRoots = @(
        (Join-Path $env:ProgramFiles 'gs'),
        (Join-Path ${env:ProgramFiles(x86)} 'gs')
    )
    foreach ($gsRoot in $gsRoots) {
        if (-not (Test-Path -LiteralPath $gsRoot)) { continue }
        foreach ($d in @(Get-ChildItem -LiteralPath $gsRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
            [void]$sources.Add((Join-Path $d.FullName 'bin'))
        }
    }
    $pdf24Bin = Join-Path $env:ProgramFiles 'PDF24\gs\bin'
    if (Test-Path -LiteralPath $pdf24Bin) {
        [void]$sources.Add($pdf24Bin)
    }

    $null = New-Item -ItemType Directory -Path $gsDestDir -Force -ErrorAction SilentlyContinue
    $copied = $false
    foreach ($srcDir in $sources) {
        if ([string]::IsNullOrWhiteSpace($srcDir) -or -not (Test-Path -LiteralPath $srcDir)) { continue }
        foreach ($name in @('gswin64c.exe', 'gsdll64.dll')) {
            $srcFile = Join-Path $srcDir $name
            if (-not (Test-Path -LiteralPath $srcFile)) { continue }
            $dest = Join-Path $gsDestDir $name
            if (Copy-FileResilient -SourcePath $srcFile -DestinationPath $dest) {
                $copied = $true
            }
        }
        if ((Test-Path -LiteralPath $gsExeDest) -and (Test-Path -LiteralPath $gsDllDest)) { break }
    }

    if ((Test-Path -LiteralPath $gsExeDest) -and (Test-Path -LiteralPath $gsDllDest)) {
        Write-BuildSuccess 'runtime\ghostscript\gswin64c.exe + gsdll64.dll'
        return $true
    }
    Write-BuildWarn 'Ghostscript portable introuvable — installez GS sur la machine de build ou copiez dans runtime/ghostscript/'
    return $false
}

function Ensure-PackagePopplerLayout {
    param(
        [Parameter(Mandatory = $true)][string]$PackageRoot
    )
    $popplerRoot = Join-Path $PackageRoot 'runtime\poppler'
    if (-not (Test-Path -LiteralPath $popplerRoot)) {
        Write-BuildWarn 'runtime\poppler absent du package'
        return $false
    }
    $flatExe = Join-Path $popplerRoot 'pdftotext.exe'
    if (Test-Path -LiteralPath $flatExe) {
        Write-BuildSuccess 'runtime\poppler\pdftotext.exe'
        return $true
    }
    $nested = Get-ChildItem -LiteralPath $popplerRoot -Recurse -Filter 'pdftotext.exe' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $nested) {
        Write-BuildWarn 'pdftotext.exe introuvable dans runtime\poppler\'
        return $false
    }
    $binDir = $nested.Directory.FullName
    foreach ($file in @(Get-ChildItem -LiteralPath $binDir -File -Force -ErrorAction SilentlyContinue)) {
        $dest = Join-Path $popplerRoot $file.Name
        if (-not (Copy-FileResilient -SourcePath $file.FullName -DestinationPath $dest)) {
            Write-BuildWarn ("Echec copie Poppler : {0}" -f $file.Name)
        }
    }
    if (Test-Path -LiteralPath $flatExe) {
        Write-BuildSuccess ("Poppler normalise depuis {0}" -f $binDir)
        return $true
    }
    Write-BuildWarn 'Normalisation Poppler echouee'
    return $false
}

function Copy-PackageGraphModules {
    param(
        [Parameter(Mandatory = $true)][string]$PackageRoot
    )
    $authMod = Get-Module -Name Microsoft.Graph.Authentication -ListAvailable -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $authMod) {
        Write-BuildInfo 'Installation Microsoft.Graph sur la machine de build...'
        try {
            Install-Module -Name Microsoft.Graph -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            $authMod = Get-Module -Name Microsoft.Graph.Authentication -ListAvailable -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        catch {
            Write-BuildWarn ("Microsoft.Graph non installe : {0}" -f $_.Exception.Message)
            return $false
        }
    }
    if (-not $authMod) {
        Write-BuildWarn 'Microsoft.Graph.Authentication introuvable apres installation'
        return $false
    }

    $modulesRoot = $null
    $searchRoots = @(
        (Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules'),
        (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Modules'),
        (Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules')
    )
    if (${env:ProgramFiles(x86)}) {
        $searchRoots += Join-Path ${env:ProgramFiles(x86)} 'WindowsPowerShell\Modules'
    }
    foreach ($root in $searchRoots) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) { continue }
        if (Test-Path -LiteralPath (Join-Path $root 'Microsoft.Graph.Authentication')) {
            $modulesRoot = $root
            break
        }
    }
    if (-not $modulesRoot) {
        $walk = $authMod.ModuleBase
        for ($i = 0; $i -lt 5 -and $walk; $i++) {
            $parent = Split-Path -Parent $walk
            if (-not $parent) { break }
            if (Test-Path -LiteralPath (Join-Path $parent 'Microsoft.Graph.Authentication')) {
                $modulesRoot = $parent
                break
            }
            $walk = $parent
        }
    }
    if (-not $modulesRoot) {
        Write-BuildWarn 'Racine des modules Microsoft.Graph introuvable'
        return $false
    }

    $targetRoot = Join-Path $PackageRoot 'runtime\Graph'
    if (Test-Path -LiteralPath $targetRoot) {
        Remove-Item -LiteralPath $targetRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    $null = New-Item -ItemType Directory -Path $targetRoot -Force

    $graphDirs = @(Get-ChildItem -LiteralPath $modulesRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'Microsoft.Graph*' })
    if ($graphDirs.Count -eq 0) {
        Write-BuildWarn ("Aucun module Microsoft.Graph* dans {0}" -f $modulesRoot)
        return $false
    }

    foreach ($dir in $graphDirs) {
        $destMod = Join-Path $targetRoot $dir.Name
        $sourceDir = $dir.FullName
        $versionDirs = @(Get-ChildItem -LiteralPath $sourceDir -Directory -ErrorAction SilentlyContinue)
        if ($versionDirs.Count -eq 1) {
            $versionPsd1 = Join-Path $versionDirs[0].FullName ("{0}.psd1" -f $dir.Name)
            if (Test-Path -LiteralPath $versionPsd1) {
                $sourceDir = $versionDirs[0].FullName
            }
        }
        $null = New-Item -ItemType Directory -Path $destMod -Force
        Get-ChildItem -LiteralPath $sourceDir -Recurse -File -Force | ForEach-Object {
            $rel = $_.FullName.Substring($sourceDir.Length).TrimStart('\')
            $destFile = Join-Path $destMod $rel
            if (-not (Copy-FileResilient -SourcePath $_.FullName -DestinationPath $destFile)) {
                throw "Echec copie Microsoft.Graph : $rel"
            }
        }
        Write-BuildInfo ("  module : {0}" -f $dir.Name)
    }

    $psd1 = Join-Path $targetRoot 'Microsoft.Graph.Authentication\Microsoft.Graph.Authentication.psd1'
    if (Test-Path -LiteralPath $psd1) {
        Write-BuildSuccess 'runtime\Graph\Microsoft.Graph.Authentication.psd1'
        return $true
    }
    Write-BuildWarn 'Microsoft.Graph.Authentication.psd1 absent apres copie'
    return $false
}

function Test-AssistantPackage {
    param(
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [switch]$FailOnMissing
    )
    $required = @(
        'ASSISTANT.bat',
        'INSTALL.bat',
        'install_assistant.ps1',
        'install_gui.ps1',
        'src\Main.ps1',
        'src\LaunchAssistant.ps1',
        'config\centres.json',
        'lib\System.Data.SQLite.dll'
    )
    $allOk = $true
    foreach ($rel in $required) {
        if (Test-Path -LiteralPath (Join-Path $PackageRoot $rel)) {
            Write-BuildSuccess $rel
        }
        else {
            Write-BuildFail "$rel MANQUANT"
            $allOk = $false
        }
    }
    $normalizerPaths = @(
        'src\ODM\PdfPlanningOptimizer\Extractors\PdfTextNormalizer.ps1',
        'src\ODM\PdfPlanningOptimizer\Extractors\CnsPdfTextNormalizer.ps1',
        'src\ODM\PdfPlanningOptimizer\Extractors\CnsPdfNorm.ps1'
    )
    $hasNormalizer = $false
    foreach ($rel in $normalizerPaths) {
        if (Test-Path -LiteralPath (Join-Path $PackageRoot $rel)) {
            Write-BuildSuccess $rel
            $hasNormalizer = $true
            break
        }
    }
    if (-not $hasNormalizer) {
        Write-BuildFail 'PdfTextNormalizer.ps1 / CnsPdfTextNormalizer.ps1 MANQUANT'
        $allOk = $false
    }
    $importExcelPsd1 = Join-Path $PackageRoot 'runtime\ImportExcel\ImportExcel.psd1'
    if (Test-Path -LiteralPath $importExcelPsd1) {
        Write-BuildSuccess 'runtime\ImportExcel\ImportExcel.psd1'
    }
    else {
        Write-BuildWarn 'runtime\ImportExcel\ImportExcel.psd1 absent (installer ImportExcel sur la machine de build)'
    }
    $graphPsd1 = Join-Path $PackageRoot 'runtime\Graph\Microsoft.Graph.Authentication\Microsoft.Graph.Authentication.psd1'
    if (Test-Path -LiteralPath $graphPsd1) {
        Write-BuildSuccess 'runtime\Graph\Microsoft.Graph.Authentication.psd1'
    }
    else {
        Write-BuildWarn 'runtime\Graph absent (installer Microsoft.Graph sur la machine de build)'
    }
    if (Test-Path -LiteralPath (Join-Path $PackageRoot 'ASSISTANT.ico')) {
        Write-BuildSuccess 'ASSISTANT.ico'
    }
    else {
        Write-BuildWarn 'ASSISTANT.ico absent (Resources\EliseE.ico manquant ?)'
        $allOk = $false
    }
    $pdfTools = @(
        @{ Label = 'runtime\poppler\pdftotext.exe'; Path = (Get-ChildItem -LiteralPath (Join-Path $PackageRoot 'runtime\poppler') -Recurse -Filter 'pdftotext.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1) },
        @{ Label = 'runtime\ghostscript\gswin64c.exe'; Path = (Get-Item -LiteralPath (Join-Path $PackageRoot 'runtime\ghostscript\gswin64c.exe') -ErrorAction SilentlyContinue) },
        @{ Label = 'lib\qpdf\qpdf.exe'; Path = (Get-ChildItem -LiteralPath (Join-Path $PackageRoot 'lib\qpdf') -Recurse -Filter 'qpdf.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1) }
    )
    foreach ($tool in $pdfTools) {
        if ($null -ne $tool.Path) {
            Write-BuildSuccess ("{0} ({1} octets)" -f $tool.Label, $tool.Path.Length)
        }
        else {
            Write-BuildFail "$($tool.Label) MANQUANT"
            $allOk = $false
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $PackageRoot 'lib\SQLite.Interop.dll'))) {
        Write-BuildFail 'lib\SQLite.Interop.dll MANQUANT'
        $allOk = $false
    }
    else {
        Write-BuildSuccess 'lib\SQLite.Interop.dll'
    }
    $criticalTemplates = @(
        'templates\CertificatDeDestruction.xlsx',
        'templates\BilanDeCollecte.xlsx',
        'templates\CeaPointsDeCollectes.xlsx',
        'templates\FT.xlsx'
    )
    foreach ($rel in $criticalTemplates) {
        if (Test-Path -LiteralPath (Join-Path $PackageRoot $rel)) {
            Write-BuildSuccess $rel
        }
        else {
            Write-BuildFail "$rel MANQUANT"
            $allOk = $false
        }
    }
    if (-not $allOk -and $FailOnMissing) {
        throw 'Package incomplet. Verifiez les exclusions antivirus.'
    }
    return $allOk
}

Write-BuildStep "Preparation package ASSISTANT v$Version (version script)"

$repoRoot = $PSScriptRoot
$outputPath = Join-Path $repoRoot $OutputDir

if ($Clean -and (Test-Path -LiteralPath $outputPath)) {
    Write-BuildStep "Nettoyage de $OutputDir"
    try {
        Remove-Item -LiteralPath $outputPath -Recurse -Force -ErrorAction Stop
    }
    catch {
        $archivePath = Join-Path $repoRoot ("{0}_old_{1}" -f $OutputDir, (Get-Date -Format 'yyyyMMdd_HHmmss'))
        Write-BuildWarn "Dossier verrouille - archivage vers $archivePath"
        Rename-Item -LiteralPath $outputPath -NewName (Split-Path -Leaf $archivePath) -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $outputPath) {
            Get-ChildItem -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue |
                ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

if (-not (Test-Path -LiteralPath $outputPath)) {
    $null = New-Item -ItemType Directory -Path $outputPath -Force
}
$outputPath = (Resolve-Path -LiteralPath $outputPath).Path

if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'src\Main.ps1'))) {
    Write-BuildFail 'src\Main.ps1 introuvable'
    exit 1
}

Write-BuildStep 'Copie des dependances dans le package de deploiement'
if (-not [string]::IsNullOrWhiteSpace($SrcRoot)) {
  $srcRootResolved = (Resolve-Path -LiteralPath $SrcRoot).Path
  Write-BuildInfo "Source src validee : $srcRootResolved"
}
$deployDirs = @(
    @{ Name = 'src'; Exclude = @() },
    @{ Name = 'Data'; Exclude = @('gestion.db') },
    @{ Name = 'lib'; Exclude = @() },
    @{ Name = 'runtime'; Exclude = @() },
    @{ Name = 'config'; Exclude = @() }
)
foreach ($dir in $deployDirs) {
    if ($dir.Name -eq 'src' -and -not [string]::IsNullOrWhiteSpace($SrcRoot)) {
        $sourceDir = Join-Path $srcRootResolved 'src'
    }
    else {
        $sourceDir = Join-Path $repoRoot $dir.Name
    }
    if (-not (Test-Path -LiteralPath $sourceDir)) { continue }
    Copy-DeployDirectory -SourceDir $sourceDir -TargetDir (Join-Path $outputPath $dir.Name) -ExcludeFileNames $dir.Exclude
    Write-BuildSuccess "Copie : $($dir.Name)"
}

Write-BuildStep 'Copie des templates (certificats, bilans, CEA)'
$templatesSource = Join-Path $repoRoot 'templates'
$templatesDest = Join-Path $outputPath 'templates'
if (Test-Path -LiteralPath $templatesSource) {
    Copy-DeployDirectory -SourceDir $templatesSource -TargetDir $templatesDest
    Write-BuildSuccess 'Copie : templates'
    foreach ($tpl in @('CertificatDeDestruction.xlsx', 'BilanDeCollecte.xlsx', 'CeaPointsDeCollectes.xlsx')) {
        $tplPath = Join-Path $templatesDest $tpl
        if (Test-Path -LiteralPath $tplPath) {
            Write-BuildSuccess $tpl
        }
        else {
            Write-BuildFail "$tpl MANQUANT dans templates/"
        }
    }
}
else {
    Write-BuildWarn 'Dossier templates/ introuvable a la racine du projet.'
}

Write-BuildStep 'Copie du module ImportExcel'
$importExcelModule = Get-Module -Name ImportExcel -ListAvailable -ErrorAction SilentlyContinue | Select-Object -First 1
if ($importExcelModule) {
    $modulePath = $importExcelModule.ModuleBase
    Write-BuildInfo "ImportExcel trouve : $modulePath"
    $targetDir = Join-Path $outputPath 'runtime\ImportExcel'
    if (Test-Path -LiteralPath $targetDir) {
        Remove-Item -LiteralPath $targetDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $null = New-Item -ItemType Directory -Path $targetDir -Force
    Get-ChildItem -LiteralPath $modulePath -Recurse -File -Force | ForEach-Object {
        $relative = $_.FullName.Substring($modulePath.Length).TrimStart('\')
        $destFile = Join-Path $targetDir $relative
        if (-not (Copy-FileResilient -SourcePath $_.FullName -DestinationPath $destFile)) {
            throw "Echec copie ImportExcel : $relative"
        }
    }
    Write-BuildSuccess 'ImportExcel copie dans runtime/ImportExcel'
}
else {
    Write-BuildWarn 'ImportExcel non trouve sur la machine de build.'
    Write-BuildWarn 'Installez-le une fois : Install-Module -Name ImportExcel -Scope CurrentUser -Force'
    Write-BuildWarn 'Sinon les postes cibles devront l''installer manuellement ou disposer d''Internet.'
}

Write-BuildStep 'Copie des modules Microsoft.Graph'
$null = Copy-PackageGraphModules -PackageRoot $outputPath

Write-BuildStep 'Copie des lanceurs et scripts'
$launcherFiles = @(
    @{ Name = 'ASSISTANT.bat'; Required = $true }
    @{ Name = 'INSTALL.bat'; Required = $true }
    @{ Name = 'install_assistant.ps1'; Required = $true }
    @{ Name = 'install_gui.ps1'; Required = $true }
    @{ Name = 'fix_installation.ps1'; Required = $false }
    @{ Name = 'clean_install.ps1'; Required = $false }
    @{ Name = 'uninstall_assistant.ps1'; Required = $false }
    @{ Name = 'Register-AssistantContextMenu.ps1'; Required = $false }
)
foreach ($entry in $launcherFiles) {
    $fileName = [string]$entry.Name
    $src = Join-Path $repoRoot $fileName
    if (-not (Test-Path -LiteralPath $src)) {
        $src = Join-Path $repoRoot ("Tools\{0}" -f $fileName)
    }
    $dest = Join-Path $outputPath $fileName
    if (-not (Test-Path -LiteralPath $src)) {
        if ($entry.Required) {
            throw "Fichier source obligatoire introuvable : $fileName (racine ou Tools\). Restaurez-le depuis Git ou verifiez l'antivirus."
        }
        Write-BuildWarn "$fileName absent — ignore"
        continue
    }
    if (-not (Copy-FileResilient -SourcePath $src -DestinationPath $dest)) {
        if ($entry.Required) {
            throw "Echec copie obligatoire : $fileName vers package (antivirus ? exclusion sur $outputPath)"
        }
        Write-BuildWarn "Echec copie optionnelle : $fileName"
        continue
    }
    if (-not (Test-Path -LiteralPath $dest)) {
        if ($entry.Required) {
            throw "Fichier copie mais absent apres copie : $dest (antivirus ?)"
        }
        continue
    }
    Write-BuildSuccess $fileName
}
$registerCtxSrc = Join-Path $repoRoot 'Tools\Register-AssistantContextMenu.ps1'
if (Test-Path -LiteralPath $registerCtxSrc) {
    $toolsOut = Join-Path $outputPath 'Tools'
    if (-not (Test-Path -LiteralPath $toolsOut)) {
        $null = New-Item -ItemType Directory -Path $toolsOut -Force
    }
    Copy-Item -LiteralPath $registerCtxSrc -Destination (Join-Path $toolsOut 'Register-AssistantContextMenu.ps1') -Force
    Copy-Item -LiteralPath $registerCtxSrc -Destination (Join-Path $outputPath 'Register-AssistantContextMenu.ps1') -Force
    Write-BuildSuccess 'Register-AssistantContextMenu.ps1 (racine + Tools/)'
}

$iconSource = Join-Path $repoRoot 'Resources\EliseE.ico'
if (Test-Path -LiteralPath $iconSource) {
    Copy-Item -LiteralPath $iconSource -Destination (Join-Path $outputPath 'ASSISTANT.ico') -Force
    Write-BuildSuccess 'ASSISTANT.ico copie depuis Resources\EliseE.ico'
}
else {
    Write-BuildWarn 'ASSISTANT.ico introuvable dans Resources\EliseE.ico'
}

# Supprimer uniquement les exe applicatifs (ex. ConventionDeNommage.exe) — garder les outils PDF
Get-ChildItem -LiteralPath $outputPath -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Extension -in @('.exe', '.exe.config') -and
        $_.FullName -notmatch '\\runtime\\poppler\\' -and
        $_.FullName -notmatch '\\lib\\qpdf\\'
    } |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }

Write-BuildStep 'Normalisation Poppler (pdftotext.exe + DLL)'
$null = Ensure-PackagePopplerLayout -PackageRoot $outputPath
$null = Ensure-PackageGhostscriptLayout -PackageRoot $outputPath -RepoRoot $repoRoot

$Version | Out-File -FilePath (Join-Path $outputPath 'version.txt') -Encoding ascii -NoNewline
Write-BuildSuccess "version.txt ($Version)"

Write-BuildStep 'Verification integrite du package'
$null = Test-AssistantPackage -PackageRoot $outputPath -FailOnMissing

Write-BuildStep 'Normalisation encodage UTF-8 BOM (scripts .ps1)'
$bomOk = Ensure-PackagePs1Utf8Bom -PackageRoot $outputPath
if (-not $bomOk) {
    Write-BuildWarn 'Normalisation UTF-8 BOM incomplete — le package reste utilisable'
}

$rootVersionFile = Join-Path $repoRoot 'version.txt'
if (-not (Test-Path -LiteralPath $rootVersionFile)) {
    $Version | Out-File -FilePath $rootVersionFile -Encoding utf8 -NoNewline
    Write-BuildSuccess "version.txt cree a la racine ($Version)"
}

Write-BuildStep 'Creation archive ZIP'
$zipPath = Join-Path $repoRoot ("ASSISTANT_v{0}.zip" -f $Version)
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction Stop
}
try {
    $zipSources = @(Get-ChildItem -LiteralPath $outputPath -Force | ForEach-Object { $_.FullName })
    Compress-Archive -Path $zipSources -DestinationPath $zipPath -CompressionLevel Optimal -Force
    $zipSizeMb = [math]::Round(((Get-Item -LiteralPath $zipPath).Length / 1MB), 1)
    Write-BuildSuccess ("ZIP cree : {0} ({1} MB)" -f $zipPath, $zipSizeMb)
}
catch {
    Write-BuildWarn ("Creation ZIP echouee : {0}" -f $_.Exception.Message)
    $zipPath = $null
}

Write-BuildStep 'Package pret'
Write-Host @"

Package  : $outputPath
Version  : $Version
ZIP      : $(if ($zipPath) { $zipPath } else { '(non cree)' })
Cle USB  : copier le ZIP ou tout le dossier package, puis double-clic INSTALL.bat
Install  : .\package\install_assistant.ps1 -Centre fontaine -Quiet -InstallDir `"`$env:LOCALAPPDATA\ASSISTANT`"

"@
$global:LASTEXITCODE = 0
exit 0

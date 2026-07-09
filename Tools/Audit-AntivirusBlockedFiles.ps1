#Requires -Version 5.1
<#
.SYNOPSIS
    Audit des fichiers bloques / en quarantaine pour ASSISTANT (Defender, Bitdefender).
.EXAMPLE
    .\Tools\Audit-AntivirusBlockedFiles.ps1 -InstallDir C:\ASSISTANT
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = '',
    [string]$InstallDir = 'C:\ASSISTANT',
    [string]$PackageDir = '',
    [switch]$ExportCsv
)

$ErrorActionPreference = 'Continue'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = if ($PSScriptRoot) { (Resolve-Path (Join-Path $PSScriptRoot '..')).Path } else { 'C:\Users\alexa\Documents\ConventionDeNommage' }
}
if ([string]::IsNullOrWhiteSpace($PackageDir)) {
    $PackageDir = Join-Path $RepoRoot 'package'
}

$localData = Join-Path $env:LOCALAPPDATA 'ASSISTANT'
$reportRows = [System.Collections.Generic.List[object]]::new()

function Add-ScanRow {
    param(
        [string]$RootLabel,
        [string]$RelativePath,
        [string]$FullPath,
        [string]$Status,
        [string]$Detail = ''
    )
    $script:reportRows.Add([pscustomobject]@{
            Root         = $RootLabel
            RelativePath = $RelativePath
            FullPath     = $FullPath
            Status       = $Status
            Detail       = $Detail
        })
}

function Test-AssistantFileAccessible {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return @{ Status = 'ABSENT'; Detail = 'Fichier ou dossier introuvable' }
    }
    try {
        $fs = [System.IO.File]::OpenRead($Path)
        $fs.Close()
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -eq 0) {
            return @{ Status = 'SUSPECT'; Detail = 'Fichier vide (0 octet)' }
        }
        return @{ Status = 'OK'; Detail = "$($bytes.Length) octets" }
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match 'denied|refus|interdit|virus|malware|quarantine|menace|blocked|bloque') {
            return @{ Status = 'BLOQUE'; Detail = $msg }
        }
        return @{ Status = 'ERREUR'; Detail = $msg }
    }
}

function Resolve-AssistantRelativePath {
    param(
        [string]$Root,
        [string]$RelativePath
    )
    $full = Join-Path $Root $RelativePath
    if (Test-Path -LiteralPath $full) { return $full }
    if ($RelativePath -like '*pdftotext.exe') {
        $f = Get-ChildItem -LiteralPath (Join-Path $Root 'runtime\poppler') -Recurse -Filter 'pdftotext.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($f) { return $f.FullName }
    }
    if ($RelativePath -like '*qpdf.exe') {
        $f = Get-ChildItem -LiteralPath (Join-Path $Root 'lib\qpdf') -Recurse -Filter 'qpdf.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($f) { return $f.FullName }
    }
    return $full
}

Write-Host '=== AUDIT ANTIVIRUS - FICHIERS BLOQUES ASSISTANT ===' -ForegroundColor Cyan
Write-Host "Date : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

Write-Host "`n--- Antivirus actif ---" -ForegroundColor Yellow
$av = @()
foreach ($name in @('bdagent', 'bdredline', 'bdservicehost', 'bdntwrk', 'MsMpEng', 'SecurityHealthService', 'Sense')) {
    $p = Get-Process -Name $name -ErrorAction SilentlyContinue
    if ($p) { $av += $name }
}
if ($av.Count -gt 0) { Write-Host ("Processus AV : {0}" -f ($av -join ', ')) -ForegroundColor Yellow }
else { Write-Host 'Aucun processus AV standard detecte (ou acces refuse).' -ForegroundColor Gray }

Write-Host "`n--- Exclusions Windows Defender ---" -ForegroundColor Yellow
try {
    $pref = Get-MpPreference -ErrorAction Stop
    Write-Host 'ExclusionPath:'
    $pref.ExclusionPath | ForEach-Object { Write-Host "  $_" }
    Write-Host 'ExclusionProcess:'
    $pref.ExclusionProcess | ForEach-Object { Write-Host "  $_" }
} catch {
    Write-Host "Lecture impossible (Defender desactive, 0x800106ba, ou droits insuffisants) : $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "`n--- Menaces Defender (filtre ASSISTANT / Convention / SQLite / EPPlus) ---" -ForegroundColor Yellow
try {
    $threats = Get-MpThreatDetection -ErrorAction Stop | Where-Object {
        $_.Resources -match 'ASSISTANT|Convention|Nommage|SQLite|ImportExcel|EPPlus|PdfTextNormalizer'
    }
    if ($threats) {
        $threats | Select-Object ThreatName, Resources, InitialDetectionTime, ActionSuccess, IsActive |
            Format-Table -AutoSize -Wrap
    }
    else { Write-Host 'Aucune menace recente correspondant au filtre.' -ForegroundColor Gray }
} catch {
    Write-Host "Get-MpThreatDetection : $($_.Exception.Message)" -ForegroundColor Yellow
}

$relativePaths = @(
    'ASSISTANT.bat',
    'INSTALL.bat',
    'install_assistant.ps1',
    'lib\System.Data.SQLite.dll',
    'lib\SQLite.Interop.dll',
    'lib\qpdf\bin\qpdf.exe',
    'runtime\poppler\pdftotext.exe',
    'runtime\ImportExcel\ImportExcel.psd1',
    'runtime\ImportExcel\EPPlus.dll',
    'src\Main.ps1',
    'src\LaunchAssistant.ps1',
    'src\ODM\PdfPlanningOptimizer\Extractors\PdfTextNormalizer.ps1',
    'src\ODM\PdfPlanningOptimizer\Extractors\CnsPdfTextNormalizer.ps1',
    'config\centres.json'
)

$scanRoots = @(
    @{ Label = 'Repo'; Path = $RepoRoot },
    @{ Label = 'Package'; Path = $PackageDir },
    @{ Label = 'Install'; Path = $InstallDir },
    @{ Label = 'LocalAppData'; Path = $localData }
)

Write-Host "`n--- Scan accessibilite fichiers sensibles ---" -ForegroundColor Yellow
foreach ($root in $scanRoots) {
    Write-Host "`n[$($root.Label)] $($root.Path)" -ForegroundColor Cyan
    if (-not (Test-Path -LiteralPath $root.Path)) {
        Write-Host '  (dossier inexistant)' -ForegroundColor Gray
        continue
    }
    foreach ($rel in $relativePaths) {
        $full = Resolve-AssistantRelativePath -Root $root.Path -RelativePath $rel
        $r = Test-AssistantFileAccessible -Path $full
        Add-ScanRow -RootLabel $root.Label -RelativePath $rel -FullPath $full -Status $r.Status -Detail $r.Detail
        $color = switch ($r.Status) { 'OK' { 'Green' } 'ABSENT' { 'Yellow' } default { 'Red' } }
        Write-Host ("  [{0}] {1}" -f $r.Status, $rel) -ForegroundColor $color
        if ($r.Status -ne 'OK' -and $r.Status -ne 'ABSENT') { Write-Host "       $($r.Detail)" -ForegroundColor DarkGray }
    }
    if ($root.Label -eq 'Repo' -or $root.Label -eq 'Package') {
        $ie = Join-Path $root.Path 'runtime\ImportExcel'
        if (Test-Path -LiteralPath $ie) {
            Get-ChildItem -LiteralPath $ie -Recurse -Filter '*.dll' -File -ErrorAction SilentlyContinue | ForEach-Object {
                $r = Test-AssistantFileAccessible -Path $_.FullName
                $relDll = $_.FullName.Substring($root.Path.Length).TrimStart('\')
                Add-ScanRow -RootLabel $root.Label -RelativePath $relDll -FullPath $_.FullName -Status $r.Status -Detail $r.Detail
                if ($r.Status -ne 'OK') {
                    Write-Host ("  [{0}] {1}" -f $r.Status, $relDll) -ForegroundColor Red
                }
            }
        }
    }
}

Write-Host "`n--- Logs installation / application ---" -ForegroundColor Yellow
$logPaths = @(
    (Join-Path $InstallDir 'src\Logs\app.log'),
    (Join-Path $InstallDir 'src\Logs\launcher.log'),
    (Join-Path $InstallDir 'Logs\app.log'),
    (Join-Path $env:TEMP 'ASSISTANT_Setup.log'),
    (Join-Path $env:TEMP 'ASSISTANT_Setup_DEBUG.log')
)
foreach ($log in $logPaths) {
    if (-not (Test-Path -LiteralPath $log)) { continue }
    Write-Host "  $log" -ForegroundColor Gray
    Get-Content -LiteralPath $log -Tail 30 -ErrorAction SilentlyContinue |
        Select-String -Pattern 'bloqu|denied|interdit|Access|WriteAllBytes|Exception|quarant|antivirus|MANQUANT|echoue' -SimpleMatch:$false |
        ForEach-Object { Write-Host "    $_" -ForegroundColor DarkYellow }
}

$blocked = @($reportRows | Where-Object { $_.Status -in @('BLOQUE', 'ERREUR', 'SUSPECT') })
$absent = @($reportRows | Where-Object { $_.Status -eq 'ABSENT' })

Write-Host "`n=== RESUME ===" -ForegroundColor Cyan
Write-Host ("Fichiers OK      : {0}" -f (@($reportRows | Where-Object Status -eq 'OK').Count))
Write-Host ("Fichiers ABSENTS : {0}" -f $absent.Count) -ForegroundColor Yellow
Write-Host ("Fichiers BLOQUES : {0}" -f (@($blocked | Where-Object Status -eq 'BLOQUE').Count)) -ForegroundColor Red

if ($blocked.Count -gt 0) {
    Write-Host "`nListe des fichiers problematiques :" -ForegroundColor Red
    $blocked | Format-Table Root, RelativePath, Status, Detail -AutoSize -Wrap
}

if ($ExportCsv) {
    $out = Join-Path $RepoRoot ("Tools\audit_av_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $reportRows | Export-Csv -LiteralPath $out -NoTypeInformation -Encoding UTF8
    Write-Host "Rapport CSV : $out" -ForegroundColor Green
}

Write-Host "`n=== EXCLUSIONS RECOMMANDEES ===" -ForegroundColor Cyan
Write-Host @"

Windows Defender (PowerShell administrateur) :
  .\config\antivirus_exclusions.ps1 -InstallDir `"$InstallDir`"

Bitdefender (console ou poste utilisateur) :
  Protection > Antivirus > Parametres avances > Exclusions
  Dossiers : $InstallDir ; $localData ; $PackageDir ; $RepoRoot\package

Restauration quarantaine :
  Bitdefender : Protection > Quarantaine > Restaurer (fichiers ASSISTANT)
  Defender    : Get-MpThreatDetection puis gestion via Securite Windows

"@ -ForegroundColor White

if ((@($blocked | Where-Object Status -eq 'BLOQUE').Count) -gt 0) { exit 2 }
if ($absent.Count -gt 10) { exit 1 }
exit 0

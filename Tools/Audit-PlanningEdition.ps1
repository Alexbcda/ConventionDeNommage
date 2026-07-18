#Requires -Version 5.1
<#
.SYNOPSIS
    Triple audit edition planning : code source, package, installation + test fonctionnel optionnel.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$PackageDir = '',
    [string]$InstallDir = 'C:\ASSISTANT',
    [switch]$RunFunctionalTest,
    [switch]$FailOnError
)

if ([string]::IsNullOrWhiteSpace($PackageDir)) {
    $PackageDir = Join-Path $RepoRoot 'package'
}

$script:FailCount = 0

function Write-AuditOk { param([string]$Message) Write-Host "OK  $Message" -ForegroundColor Green }
function Write-AuditWarn { param([string]$Message) Write-Host "??  $Message" -ForegroundColor Yellow }
function Write-AuditKo {
    param([string]$Message)
    Write-Host "KO  $Message" -ForegroundColor Red
    $script:FailCount++
}

function Test-AuditPath {
    param([string]$Label, [string]$Path)
    if (Test-Path -LiteralPath $Path) { Write-AuditOk $Label; return $true }
    Write-AuditKo "$Label — introuvable : $Path"
    return $false
}

Write-Host "=== AUDIT CODE SOURCE ===" -ForegroundColor Cyan

$sourceFiles = @(
    'src\ODM\PdfPlanningOptimizer\Services\PlanningRebuilder.ps1',
    'src\ODM\PdfPlanningOptimizer\Services\PdfTourneeCoverComposer.ps1',
    'src\ODM\PdfPlanningOptimizer\Services\CnsDestructionCertificateExcel.ps1',
    'src\ODM\PdfPlanningOptimizer\Services\CnsBilanCollecteExcel.ps1',
    'src\ODM\PdfPlanningOptimizer\Services\CnsCeaPointsCollecteExcel.ps1'
)
foreach ($rel in $sourceFiles) {
    Test-AuditPath $rel (Join-Path $RepoRoot $rel) | Out-Null
}

$composerPath = Join-Path $RepoRoot 'src\ODM\PdfPlanningOptimizer\Services\PdfTourneeCoverComposer.ps1'
$rebuilderPath = Join-Path $RepoRoot 'src\ODM\PdfPlanningOptimizer\Services\PlanningRebuilder.ps1'
$composer = Get-Content -LiteralPath $composerPath -Raw -ErrorAction SilentlyContinue
$rebuilder = Get-Content -LiteralPath $rebuilderPath -Raw -ErrorAction SilentlyContinue
$mismatchLeftovers = @(
    'Build-PlanningOdmMismatchThreeSectionCoverLines',
    'Build-PlanningOdmMismatchDiagnosticLines',
    'Get-PlanningBestExcelCandidateForPdfWorkOrder',
    'Get-PlanningPdfExcelDifferenceLines',
    'Get-PlanningExcelSlotCollecteurDisplay',
    'Get-PlanningPotentialMatchScore',
    'New-CnsGlobalMismatchCoverPdf',
    'cover_global.pdf'
) | Where-Object {
    ($rebuilder -match [regex]::Escape($_)) -or ($composer -match [regex]::Escape($_))
}
if ($mismatchLeftovers.Count -eq 0) {
    Write-AuditOk 'Traitement mismatch totalement absent (analyse + page synthese)'
}
else {
    Write-AuditKo ("Residus mismatch encore presents : {0}" -f ($mismatchLeftovers -join ', '))
}
if ($composer -match 'function Invoke-PlanningTourneePdfCoverComposition') {
    Write-AuditOk 'Invoke-PlanningTourneePdfCoverComposition'
}
else {
    Write-AuditKo 'Invoke-PlanningTourneePdfCoverComposition manquante'
}
if ($composer -match 'function Test-CnsOdmDuplicationTargetClient') {
    Write-AuditOk 'Test-CnsOdmDuplicationTargetClient'
}
else {
    Write-AuditKo 'Test-CnsOdmDuplicationTargetClient manquante'
}
if ($composer -match "25263" -and $composer -match "61742") {
    Write-AuditOk 'Clients cibles duplication : 25263 (Aguettant), 61742 (Air Liquide)'
}
else {
    Write-AuditKo 'IDs clients duplication Aguettant / Air Liquide manquants'
}

foreach ($rel in @(
    'templates\CertificatDeDestruction.xlsx',
    'templates\BilanDeCollecte.xlsx',
    'templates\CeaPointsDeCollectes.xlsx'
)) {
    Test-AuditPath "source\$rel" (Join-Path $RepoRoot $rel) | Out-Null
}

Write-Host "`n=== AUDIT DU PACKAGE ===" -ForegroundColor Cyan
foreach ($rel in @(
    'templates\CertificatDeDestruction.xlsx',
    'templates\BilanDeCollecte.xlsx',
    'templates\CeaPointsDeCollectes.xlsx',
    'templates\planning\destruction',
    'templates\planning\collecte',
    'templates\planning\cea'
)) {
    Test-AuditPath $rel (Join-Path $PackageDir $rel) | Out-Null
}

Write-Host "`n=== AUDIT DE L'INSTALLATION ($InstallDir) ===" -ForegroundColor Cyan
foreach ($rel in @(
    'templates\CertificatDeDestruction.xlsx',
    'templates\BilanDeCollecte.xlsx',
    'templates\CeaPointsDeCollectes.xlsx',
    'templates\planning\destruction',
    'templates\planning\collecte',
    'templates\planning\cea'
)) {
    Test-AuditPath $rel (Join-Path $InstallDir $rel) | Out-Null
}

Write-Host "`n=== TEST UNITAIRE DUPLICATION ODM ===" -ForegroundColor Cyan
. $composerPath
$woAg = [pscustomobject]@{ ClientID = '25263'; ClientName = 'LABORATOIRES AGUETTANT' }
$woAl = [pscustomobject]@{ ClientID = '61742'; ClientName = 'AIR LIQUIDE INDUSTRIE VOREPPE' }
$woOther = [pscustomobject]@{ ClientID = '99999'; ClientName = 'AUTRE CLIENT' }
if (Test-CnsOdmDuplicationTargetClient -WorkOrderEntity $woAg) { Write-AuditOk 'Duplication active pour Aguettant (25263)' }
else { Write-AuditKo 'Duplication inactive pour Aguettant' }
if (Test-CnsOdmDuplicationTargetClient -WorkOrderEntity $woAl) { Write-AuditOk 'Duplication active pour Air Liquide (61742)' }
else { Write-AuditKo 'Duplication inactive pour Air Liquide' }
if (-not (Test-CnsOdmDuplicationTargetClient -WorkOrderEntity $woOther)) { Write-AuditOk 'Duplication ignore les autres clients' }
else { Write-AuditKo 'Duplication declenchee a tort pour client tiers' }

if ($RunFunctionalTest) {
    Write-Host "`n=== TEST FONCTIONNEL EDITION PLANNING ===" -ForegroundColor Cyan
    $fixtures = Join-Path $RepoRoot 'Test\Fixtures\PdfPlanningOptimizer'
    $planPdf = Join-Path $fixtures '26062026.pdf'
    $planExcel = Join-Path $fixtures 'PlanningGRENOBLE.xlsm'
    if (-not (Test-Path -LiteralPath $planExcel)) {
        $planExcel = Join-Path $fixtures 'Planning GRENOBLEL.xlsm'
    }
    if (-not ((Test-Path -LiteralPath $planPdf) -and (Test-Path -LiteralPath $planExcel))) {
        Write-AuditKo 'Fixtures planning manquantes pour test fonctionnel'
    }
    else {
        $workDir = Join-Path $env:TEMP ('PlanningAudit_' + [Guid]::NewGuid().ToString('n'))
        $null = New-Item -ItemType Directory -Path $workDir -Force
        $logFile = Join-Path $workDir 'planning_run.log'
        try {
            Copy-Item -LiteralPath $planPdf -Destination (Join-Path $workDir '26062026.pdf') -Force
            Copy-Item -LiteralPath $planExcel -Destination (Join-Path $workDir 'Planning GRENOBLE.xlsm') -Force
            $poppler = Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'runtime\poppler') -Recurse -Filter 'pdftotext.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($poppler) { $env:PDFTOTEXT_PATH = $poppler.DirectoryName }
            $importDir = Join-Path $RepoRoot 'runtime\ImportExcel'
            if (Test-Path -LiteralPath $importDir) { $env:PSModulePath = "$importDir;$env:PSModulePath" }
            try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop }
            catch { try { Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop } catch { } }
            $dbDir = Join-Path $workDir 'Data'
            $null = New-Item -ItemType Directory -Path $dbDir -Force
            $env:ASSISTANT_DATA_DIR = $dbDir
            . (Join-Path $RepoRoot 'src\Database\Database.ps1')
            $null = Initialize-Database
            . (Join-Path $RepoRoot 'src\ODM\PdfPlanningOptimizer\Services\PlanningRebuilder.ps1')
            $script:PlanningPipelineRunning = $false
            $out = Start-PlanningRebuild -PdfPath (Join-Path $workDir '26062026.pdf') -ExcelPath (Join-Path $workDir 'Planning GRENOBLE.xlsm') *>&1 | Tee-Object -FilePath $logFile
            $logText = Get-Content -LiteralPath $logFile -Raw -ErrorAction SilentlyContinue
            if ([string]::IsNullOrWhiteSpace($logText)) { $logText = ($out | Out-String) }

            $outPdf = Get-ChildItem -LiteralPath $workDir -Filter 'ODM_*.pdf' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($outPdf -and $outPdf.Length -gt 1000) {
                Write-AuditOk ("PDF genere : {0} ({1} octets)" -f $outPdf.Name, $outPdf.Length)
            }
            else {
                Write-AuditKo 'PDF ODM non genere ou trop petit'
            }

            if ($logText -match 'Page de garde globale OK') { Write-AuditOk 'Page de synthese globale generee' }
            else { Write-AuditKo 'Page de synthese globale absente du log' }

            if ($logText -match 'Section1:\d+ Section2:\d+ Section3:\d+' -or $logText -match 'Tous les ODM sont match' -or $logText -match 'Page de garde globale OK') {
                Write-AuditOk 'Analyse ODM non matches (sections detaillees ou synthese simplifiee)'
            }
            else { Write-AuditKo 'Analyse sections ODM non detectee' }

            if ($logText -match 'Creating cover page for segment') { Write-AuditOk 'Pages de garde de tournees composees' }
            else { Write-AuditKo 'Pages de garde de tournees absentes' }

            if ($logText -match 'DESTRUCTION-CERT|Generation certificat destruction') { Write-AuditOk 'Certificats de destruction generes' }
            else { Write-AuditKo 'Certificats de destruction non detectes' }

            if ($logText -match 'Bilan de collecte dynamique|bilan_seg_') { Write-AuditOk 'Bilans de collecte generes' }
            else { Write-AuditKo 'Bilans de collecte non detectes' }

            if ($logText -match 'CEA-POINTS|Document CEA injecte|Generation document CEA') { Write-AuditOk 'Listings CEA generes' }
            else { Write-AuditWarn 'Listings CEA non detectes (fixture sans page CEA ?)' }

            if ($logText -match 'DUPLICATION-ODM') { Write-AuditOk 'Duplication ODM declenchee dans le run' }
            else { Write-AuditWarn 'Duplication ODM non declenchee (fixture sans Aguettant/Air Liquide ?)' }
        }
        catch {
            Write-AuditKo ("Test fonctionnel : {0}" -f $_.Exception.Message)
        }
        finally {
            Remove-Item Env:ASSISTANT_DATA_DIR -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "`n=== RESULTAT ===" -ForegroundColor Cyan
if ($script:FailCount -eq 0) {
    Write-Host "Audit concluant ($script:FailCount echec)." -ForegroundColor Green
    exit 0
}
Write-Host "$script:FailCount controle(s) en echec." -ForegroundColor Red
if ($FailOnError) { exit 1 }
exit 1

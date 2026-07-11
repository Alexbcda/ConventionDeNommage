#Requires -Version 5.1
# Audit complet pipeline edition planning + templates
param(
    [string]$RepoRoot = 'C:\Users\alexa\Documents\ConventionDeNommage',
    [string]$PackageDir = '',
    [string]$InstallDir = 'C:\ASSISTANT',
    [string]$LogFile = '',
    [switch]$RunFixtureTest
)

if ([string]::IsNullOrWhiteSpace($PackageDir)) { $PackageDir = Join-Path $RepoRoot 'package' }
if ([string]::IsNullOrWhiteSpace($LogFile)) { $LogFile = Join-Path $InstallDir 'src\Logs\app.log' }

$script:Issues = [System.Collections.Generic.List[string]]::new()
$script:Ok = [System.Collections.Generic.List[string]]::new()

function Add-Ok { param([string]$M) $script:Ok.Add($M) }
function Add-Issue { param([string]$M) $script:Issues.Add($M) }

Write-Host "=== VERIFICATION DES TEMPLATES ===" -ForegroundColor Cyan
$tplNames = @('CertificatDeDestruction.xlsx', 'BilanDeCollecte.xlsx', 'CeaPointsDeCollectes.xlsx')
foreach ($root in @(@{ L='package'; P=$PackageDir }, @{ L='installation'; P=$InstallDir })) {
    Write-Host "`n--- $($root.L) ($($root.P)) ---" -ForegroundColor Yellow
    foreach ($tpl in $tplNames) {
        $path = Join-Path $root.P "templates\$tpl"
        if (Test-Path -LiteralPath $path) {
            $sz = (Get-Item -LiteralPath $path).Length
            Write-Host "  OK $tpl ($sz octets)" -ForegroundColor Green
            Add-Ok "$($root.L) : $tpl"
        }
        else {
            Write-Host "  KO $tpl MANQUANT" -ForegroundColor Red
            Add-Issue "$($root.L) : $tpl manquant"
        }
    }
}

Write-Host "`n=== APPELS TEMPLATES DANS LE CODE (install) ===" -ForegroundColor Cyan
$codeFiles = @(
    'src\ODM\PdfPlanningOptimizer\Services\CnsDestructionCertificateExcel.ps1',
    'src\ODM\PdfPlanningOptimizer\Services\CnsBilanCollecteExcel.ps1',
    'src\ODM\PdfPlanningOptimizer\Services\CnsCeaPointsCollecteExcel.ps1',
    'src\ODM\PdfPlanningOptimizer\Services\PdfTourneeCoverComposer.ps1'
)
foreach ($rel in $codeFiles) {
    $path = Join-Path $InstallDir $rel
    if (-not (Test-Path -LiteralPath $path)) { $path = Join-Path $RepoRoot $rel }
    if (Test-Path -LiteralPath $path) {
        $c = Get-Content -LiteralPath $path -Raw
        $fn = Split-Path -Leaf $path
        if ($fn -match 'Excel\.ps1' -and $c -match 'Get-Cns.*TemplatePath') {
            Write-Host "  OK $fn" -ForegroundColor Green
            Add-Ok "Code : $fn"
        }
        elseif ($fn -eq 'PdfTourneeCoverComposer.ps1' -and $c -match 'New-CnsDestructionCertificatePdfFromExcelTemplate' -and $c -match 'New-CnsBilanCollectePdfFromExcelTemplate') {
            Write-Host "  OK $fn (appels etape 5)" -ForegroundColor Green
            Add-Ok 'Code : PdfTourneeCoverComposer appels templates'
        }
        else {
            Write-Host "  KO $fn" -ForegroundColor Red
            Add-Issue "Code incomplet : $fn"
        }
    }
    else {
        Write-Host "  KO $rel MANQUANT" -ForegroundColor Red
        Add-Issue "Fichier code manquant : $rel"
    }
}

# Resolution chemin template depuis install
Write-Host "`n=== RESOLUTION CHEMIN TEMPLATE ===" -ForegroundColor Cyan
$servicesDir = Join-Path $InstallDir 'src\ODM\PdfPlanningOptimizer\Services'
if (Test-Path -LiteralPath $servicesDir) {
    $resolvedRoot = (Resolve-Path (Join-Path $servicesDir '..\..\..\..')).Path
    $tplTest = Join-Path $resolvedRoot 'templates\CertificatDeDestruction.xlsx'
    Write-Host "  Install root resolu : $resolvedRoot"
    if (Test-Path -LiteralPath $tplTest) {
        Write-Host "  OK CertificatDeDestruction.xlsx via resolution code" -ForegroundColor Green
        Add-Ok 'Resolution template -> install root'
    }
    else {
        Write-Host "  KO Template introuvable via resolution code : $tplTest" -ForegroundColor Red
        Add-Issue "Resolution code pointe vers $resolvedRoot mais templates absents"
    }
}

Write-Host "`n=== BINAIRES EXTERNES ===" -ForegroundColor Cyan
. (Join-Path $InstallDir 'src\Core\GhostscriptResolve.ps1')
$gs = Get-ResolvedGhostscriptPath
if ($gs) {
    Write-Host "  OK Ghostscript : $gs" -ForegroundColor Green
    Add-Ok 'Ghostscript'
}
else {
    Write-Host "  KO Ghostscript" -ForegroundColor Red
    Add-Issue 'Ghostscript introuvable - etape 5 abandonnee (aucune page de garde ni fusion templates)'
}

$lo = @(
    'C:\Program Files\LibreOffice\program\soffice.exe',
    'C:\Program Files (x86)\LibreOffice\program\soffice.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($lo) {
    Write-Host "  OK LibreOffice : $lo" -ForegroundColor Green
    Add-Ok 'LibreOffice'
}
else {
    Write-Host "  KO LibreOffice" -ForegroundColor Red
    Add-Issue 'LibreOffice introuvable - XLSX non convertis en PDF'
}

Write-Host "`n=== LOGS ($LogFile) ===" -ForegroundColor Cyan
if (Test-Path -LiteralPath $LogFile) {
    $log = Get-Content -LiteralPath $LogFile -Raw
    $patterns = @{
        'STEP 5 executee'           = 'STEP 5|Composition pages de garde'
        'STEP 5 terminee'           = 'STEP 5 : Termine'
        'Templates utilises'        = 'BILAN-COLLECTE|DESTRUCTION-CERT|CEA-POINTS|XLSX-PDF'
        'Composition abandonnee'    = 'Composition abandonnee|abandonnee \(PDF principal'
        'Ghostscript KO log'        = 'Ghostscript introuvable'
        'LibreOffice KO log'        = 'LibreOffice.*echoue|Conversion.*echouee'
        'Composer non charge'       = 'PdfTourneeCoverComposer non charge'
    }
    foreach ($k in $patterns.Keys) {
        $hit = $log -match $patterns[$k]
        $bad = $k -match 'KO|abandonnee|non charge'
        if ($bad) {
            if ($hit) { Write-Host "  DETECTE $k" -ForegroundColor Red; Add-Issue $k }
            else { Write-Host "  OK pas de $k" -ForegroundColor Green }
        }
        else {
            if ($hit) { Write-Host "  OK $k" -ForegroundColor Green; Add-Ok $k }
            else { Write-Host "  ?? $k (non trouve dans log)" -ForegroundColor Yellow }
        }
    }
    Write-Host "`n--- 20 dernieres lignes pertinentes ---" -ForegroundColor Gray
    Select-String -Path $LogFile -Pattern 'STEP 5|TOURNEE|Certificat|Bilan|CEA|abandonnee|Ghostscript|LibreOffice|XLSX-PDF' | Select-Object -Last 20 | ForEach-Object { $_.Line }
}
else {
    Write-Host "  KO Log introuvable" -ForegroundColor Red
    Add-Issue 'app.log introuvable - lancer un traitement planning puis re-auditer'
}

if ($RunFixtureTest) {
    Write-Host "`n=== TEST FONCTIONNEL FIXTURES ===" -ForegroundColor Cyan
    $pdf = Join-Path $RepoRoot 'Test\Fixtures\PdfPlanningOptimizer\08062026.pdf'
    $xls = @(
        (Join-Path $RepoRoot 'Test\Fixtures\PdfPlanningOptimizer\Planning GRENOBLE.xlsm'),
        (Join-Path $RepoRoot 'Test\Fixtures\PdfPlanningOptimizer\PlanningGRENOBLE.xlsm')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ((Test-Path -LiteralPath $pdf) -and $xls) {
        & (Join-Path $RepoRoot 'Test\Scripts\Audit-PlanningFixtures0806.ps1') -InstallDir $InstallDir -RepoRoot $RepoRoot 2>&1 | Select-Object -Last 25
    }
    else {
        Write-Host "  KO Fixtures manquantes" -ForegroundColor Red
    }
}

Write-Host "`n=== SYNTHESE ===" -ForegroundColor Cyan
Write-Host "OK ($($script:Ok.Count)):" -ForegroundColor Green
$script:Ok | ForEach-Object { Write-Host "  - $_" }
if ($script:Issues.Count -gt 0) {
    Write-Host "PROBLEMES ($($script:Issues.Count)):" -ForegroundColor Red
    $script:Issues | ForEach-Object { Write-Host "  - $_" }
    exit 1
}
Write-Host "Audit statique concluant." -ForegroundColor Green
exit 0

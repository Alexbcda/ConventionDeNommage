# Audit du switch LibreOffice -> Excel pour la generation des templates (Certificat, Bilan, CEA).
param(
    [string]$InstallDir = $(if (Test-Path 'C:\ASSISTANT\src') { 'C:\ASSISTANT' } else { (Resolve-Path (Join-Path $PSScriptRoot '..')).Path })
)

$ErrorActionPreference = 'Continue'

function Write-Section([string]$Title) {
    Write-Host ''
    Write-Host ('=' * 60) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ('=' * 60) -ForegroundColor Cyan
}

function Write-Ok([string]$Msg) { Write-Host "  OK   $Msg" -ForegroundColor Green }
function Write-Warn([string]$Msg) { Write-Host "  WARN $Msg" -ForegroundColor Yellow }
function Write-Err([string]$Msg) { Write-Host "  ERR  $Msg" -ForegroundColor Red }

$results = @{
    OK    = [System.Collections.Generic.List[string]]::new()
    WARN  = [System.Collections.Generic.List[string]]::new()
    ERROR = [System.Collections.Generic.List[string]]::new()
}
function Add-R([string]$Bucket, [string]$Msg) { [void]$results[$Bucket].Add($Msg) }

Write-Section "AUDIT SWITCH LIBREOFFICE -> EXCEL"
Write-Host "  Poste    : $env:COMPUTERNAME"
Write-Host "  Date     : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
Write-Host "  Install  : $InstallDir"

# --- Charger moteur conversion ---
$engineFile = Join-Path $InstallDir 'src\ODM\PdfPlanningOptimizer\Services\CnsExcelTemplateEngine.ps1'
$step5File = Join-Path $InstallDir 'src\ODM\PdfPlanningOptimizer\Services\PlanningStep5Prerequisites.ps1'

if (-not (Test-Path -LiteralPath $engineFile)) {
    Write-Err "CnsExcelTemplateEngine.ps1 introuvable : $engineFile"
    exit 1
}
. $engineFile

# --- 1. LibreOffice ---
Write-Section '1. LIBREOFFICE'
$loPath = Get-CnsLibreOfficeSofficePath
if ($loPath) {
    Write-Ok "soffice.exe : $loPath"
    Add-R OK "LibreOffice present"
}
else {
    Write-Err 'LibreOffice absent'
    Add-R ERROR 'LibreOffice absent'
}

# --- 2. Excel ---
Write-Section '2. MICROSOFT EXCEL'
$excelExe = Get-CnsMicrosoftExcelExecutablePath
$excelOk = Test-CnsMicrosoftExcelAvailable
if ($excelExe) { Write-Ok "excel.exe registre : $excelExe" } else { Write-Warn 'excel.exe non trouve dans App Paths' }
if ($excelOk) {
    Write-Ok 'COM Excel.Application disponible'
    Add-R OK 'Excel COM disponible'
}
else {
    Write-Err 'Excel indisponible (COM + registre)'
    Add-R ERROR 'Excel indisponible'
}

# --- 3. Moteur resolu (Convert-XlsxToPdf) ---
Write-Section '3. MOTEUR CONVERSION (Convert-XlsxToPdf)'
$mode = Get-CnsXlsxToPdfConverterMode
$engine = Resolve-CnsXlsxToPdfEngine -Mode $mode
Write-Host "  CN_PDF_CONVERTER = $(if ($env:CN_PDF_CONVERTER) { $env:CN_PDF_CONVERTER } else { '(non defini -> AUTO)' })"
Write-Host "  Mode effectif    : $mode"
Write-Host "  Moteur selectionne : $(if ($engine) { $engine } else { 'AUCUN' })"

if ($engine -eq 'Excel') { Add-R OK 'Moteur conversion = Excel' }
elseif ($engine -eq 'LibreOffice') { Add-R OK 'Moteur conversion = LibreOffice' }
else { Add-R ERROR 'Aucun moteur XLSX->PDF' }

# --- 4. Prerequis etape 5 (bloquant) ---
Write-Section '4. PREREQUIS ETAPE 5 (PlanningStep5Prerequisites)'
if (Test-Path -LiteralPath $step5File) {
    . $step5File
    $env5 = Test-PlanningStep5Environment
    Write-Host "  Ok global        : $($env5.Ok)"
    Write-Host "  Ghostscript      : $($env5.GhostscriptPath)"
    Write-Host "  LibreOffice      : $($env5.LibreOfficePath)"
    foreach ($issue in @($env5.Issues)) {
        Write-Warn $issue
        Add-R WARN "Step5: $issue"
    }
    if (-not $env5.Ok -and $excelOk -and -not $loPath) {
        Write-Err 'BUG DETECTE : Step5 bloque sans LibreOffice alors qu Excel est disponible'
        Add-R ERROR 'Step5 bloque le pipeline sans considerer Excel'
    }
    elseif ($env5.Ok) { Add-R OK 'Step5 prerequis OK' }
}
else {
    Write-Warn "Fichier absent : $step5File"
}

# --- 5. Fichiers de conversion ---
Write-Section '5. FICHIERS CODE CONVERSION'
$conversionFiles = @(
    'src\ODM\PdfPlanningOptimizer\Services\CnsExcelTemplateEngine.ps1',
    'src\ODM\PdfPlanningOptimizer\Services\CnsDestructionCertificateExcel.ps1',
    'src\ODM\PdfPlanningOptimizer\Services\CnsBilanCollecteExcel.ps1',
    'src\ODM\PdfPlanningOptimizer\Services\CnsCeaPointsCollecteExcel.ps1',
    'src\ODM\PdfPlanningOptimizer\Services\PlanningStep5Prerequisites.ps1',
    'src\ODM\PdfPlanningOptimizer\Services\PdfTourneeCoverComposer.ps1'
)
foreach ($rel in $conversionFiles) {
    $full = Join-Path $InstallDir $rel
    if (Test-Path -LiteralPath $full) { Write-Ok (Split-Path $rel -Leaf) }
    else { Write-Err "Manquant : $rel"; Add-R ERROR "Fichier manquant : $rel" }
}

# --- 6. Templates ---
Write-Section '6. TEMPLATES XLSX'
foreach ($name in @('CertificatDeDestruction.xlsx', 'BilanDeCollecte.xlsx', 'CeaPointsDeCollectes.xlsx')) {
    $p = Join-Path $InstallDir "templates\$name"
    if (Test-Path -LiteralPath $p) { Write-Ok $name } else { Write-Err "$name manquant"; Add-R ERROR "Template $name manquant" }
}

# --- 7. Test conversion reel (optionnel) ---
Write-Section '7. TEST CONVERSION REEL'
$tpl = Join-Path $InstallDir 'templates\BilanDeCollecte.xlsx'
$outPdf = Join-Path $env:TEMP ("cn_audit_bilan_{0}.pdf" -f [Guid]::NewGuid().ToString('N'))
if ((Test-Path -LiteralPath $tpl) -and $engine) {
    $workXlsx = Join-Path $env:TEMP ("cn_audit_bilan_{0}.xlsx" -f [Guid]::NewGuid().ToString('N'))
    Copy-Item -LiteralPath $tpl -Destination $workXlsx -Force
    try {
        if (Get-Command Set-CnsXlsxTemplatePlaceholders -ErrorAction SilentlyContinue) {
            $null = Set-CnsXlsxTemplatePlaceholders -XlsxPath $workXlsx -Placeholders @{ Date_Collecte = '01/01/2026'; Collecteur_Nom = 'Test'; Collecteur_Prenom = 'Audit' }
        }
        $convOk = Convert-XlsxToPdf -XlsxPath $workXlsx -PdfPath $outPdf
        if ($convOk -and (Test-Path -LiteralPath $outPdf)) {
            $sz = (Get-Item -LiteralPath $outPdf).Length
            Write-Ok "PDF genere via $engine ($sz octets) : $outPdf"
            Add-R OK "Conversion test OK via $engine"
        }
        else {
            Write-Err "Conversion echouee via $engine"
            Add-R ERROR "Conversion test echouee via $engine"
        }
    }
    catch {
        Write-Err $_.Exception.Message
        Add-R ERROR "Exception conversion : $($_.Exception.Message)"
    }
    finally {
        Remove-Item -LiteralPath $workXlsx -Force -ErrorAction SilentlyContinue
    }
}
else {
    Write-Warn 'Test conversion ignore (template ou moteur absent)'
}

# --- 8. Diagnostic cause probable ---
Write-Section '8. DIAGNOSTIC'
if (-not $loPath -and -not $excelOk) {
    Write-Err 'CAUSE : ni LibreOffice ni Excel — templates impossibles'
    Add-R ERROR 'Ni LO ni Excel'
}
elseif (-not $loPath -and $excelOk -and -not $env5.Ok) {
    Write-Err 'CAUSE : Excel disponible mais etape 5 BLOQUEE par PlanningStep5Prerequisites (LibreOffice requis)'
    Write-Host '  -> Le switch Convert-XlsxToPdf fonctionne, mais le pipeline ne l atteint jamais.' -ForegroundColor Yellow
}
elseif (-not $loPath -and $excelOk -and $engine -eq 'Excel') {
    Write-Ok 'Switch LO->Excel actif au niveau conversion'
    if ($env5.Ok) { Write-Ok 'Step5 autorise' } else { Write-Warn 'Step5 bloque malgre Excel' }
}
elseif ($loPath) {
    Write-Ok 'LibreOffice present — conversion via LO (Excel non utilise en mode AUTO)'
}

# --- Resume ---
Write-Section 'RESUME'
Write-Host "  OK      : $($results.OK.Count)" -ForegroundColor Green
$results.OK | ForEach-Object { Write-Host "    - $_" -ForegroundColor DarkGray }
if ($results.WARN.Count -gt 0) {
    Write-Host "  WARNING : $($results.WARN.Count)" -ForegroundColor Yellow
    $results.WARN | ForEach-Object { Write-Host "    - $_" -ForegroundColor DarkGray }
}
if ($results.ERROR.Count -gt 0) {
    Write-Host "  ERROR   : $($results.ERROR.Count)" -ForegroundColor Red
    $results.ERROR | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
}

exit $(if ($results.ERROR.Count -gt 0) { 1 } else { 0 })

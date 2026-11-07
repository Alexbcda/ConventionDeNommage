# POC : remplissage CertificatDeDestruction.xlsx + conversion PDF.
param(
    [string]$TemplatePath,
    [string]$OutputPdfPath = (Join-Path $env:TEMP 'test_certificat.pdf')
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

. (Join-Path $repo 'src\Common\CnsFrenchHolidays.ps1')
. (Join-Path $repo 'src\ODM\PdfPlanningOptimizer\Services\CnsCertificatePlaceholderCommon.ps1')
. (Join-Path $repo 'src\ODM\Agents\Get-RandomTrieurFromDatabase.ps1')
. (Join-Path $repo 'src\ODM\PdfPlanningOptimizer\Services\CnsDestructionCertificateExcel.ps1')

if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
    $TemplatePath = Get-CnsDestructionCertificateTemplatePath
}

if (-not (Test-Path -LiteralPath $TemplatePath)) {
    throw "Template introuvable : $TemplatePath"
}

$visitDate = [datetime]'2026-05-29'
$trieur = Get-RandomTrieurFromDatabase
$dateFin = Format-CnsFrenchDate -Date (Add-2WorkingDaysWithFrenchHolidays -StartDate $visitDate)

$placeholders = @{
    Date_Collecte       = '29/05/2026'
    Date_FinDestruction = $dateFin
    Client_ID           = 'CLI-001'
    Client_Nom          = 'Client Test'
    Client_Adresse      = '1 rue Test'
    Client_CP           = '73000'
    Client_Ville        = 'Chambery'
    Collecteur_Nom      = 'Dupont'
    Collecteur_Prenom   = 'Jean'
    Vehicule_Immat      = 'AB-123-CD'
    ODM_Numero          = 'ODM-999'
    Trieur_Nom          = [string]$trieur.Nom
    Trieur_Prenom       = [string]$trieur.Prenom
}

$runId = [Guid]::NewGuid().ToString('N')
$workXlsx = Join-Path $env:TEMP ("test_cert_{0}.xlsx" -f $runId)
Copy-Item -LiteralPath $TemplatePath -Destination $workXlsx -Force

Write-Host ("Template : {0}" -f $TemplatePath)
Write-Host ("Date_FinDestruction calculee : {0}" -f $dateFin)
Write-Host ("Trieur : {0} {1}" -f $trieur.Prenom, $trieur.Nom)

if (-not (Set-CnsXlsxTemplatePlaceholders -XlsxPath $workXlsx -Placeholders $placeholders)) {
    throw 'Echec remplacement placeholders'
}

$found = @(Find-XlsxPlaceholders -XlsxPath $workXlsx)
$remaining = @($found | Where-Object { $_.RawText -match '\{\{' })
if ($remaining.Count -gt 0) {
    throw ("Balises non remplacees : {0}" -f ($remaining.Key -join ', '))
}

if (-not (Convert-XlsxToPdf -XlsxPath $workXlsx -PdfPath $OutputPdfPath)) {
    throw 'Echec conversion PDF (LibreOffice ou Excel requis)'
}

if (-not (Test-Path -LiteralPath $OutputPdfPath)) {
    throw 'PDF absent apres conversion'
}

$pdfSize = (Get-Item -LiteralPath $OutputPdfPath).Length
Write-Host ("PDF genere : {0} ({1} octets)" -f $OutputPdfPath, $pdfSize) -ForegroundColor Green
Write-Host 'Test reussi' -ForegroundColor Green

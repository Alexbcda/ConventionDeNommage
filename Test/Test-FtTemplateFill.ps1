# POC : remplissage FT.xlsx + conversion PDF (fixtures FT 1507).
param(
    [string]$TemplatePath,
    [string]$OutputPdfPath = (Join-Path $env:TEMP 'test_ft_collecte.pdf'),
    [string]$PdfFixture = (Join-Path $PSScriptRoot 'Fixtures\PdfPlanningOptimizer\FT 1507.pdf')
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

. (Join-Path $repo 'src\ODM\PdfPlanningOptimizer\Services\CnsPdfMetierPrestation.ps1')
. (Join-Path $repo 'src\ODM\PdfPlanningOptimizer\Services\CnsFtTemplate.ps1')

if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
    $TemplatePath = Get-CnsFtTemplatePath
}

$pointCollecte = 'FT CHAMBERY GRAND VERGER'
if (Test-Path -LiteralPath $PdfFixture) {
    . (Join-Path $repo 'src\ODM\PdfPlanningOptimizer\Extractors\PdfExtractor.ps1')
    $exe = Get-ResolvedPdfToTextPath
    if (-not [string]::IsNullOrWhiteSpace($exe)) {
        $tempOut = Join-Path $env:TEMP ("cn_ft_fill_{0}.txt" -f [Guid]::NewGuid().ToString('N'))
        try {
            & $exe -enc UTF-8 -q $PdfFixture $tempOut 2>$null | Out-Null
            $lines = @(Get-Content -LiteralPath $tempOut -Encoding UTF8 -ErrorAction SilentlyContinue)
            foreach ($ln in $lines) {
                $detected = Get-CnsFtCollectionPointLabelFromRawLines -RawLines @($ln)
                if (-not [string]::IsNullOrWhiteSpace($detected)) {
                    $pointCollecte = $detected
                    break
                }
            }
        }
        finally {
            Remove-Item -LiteralPath $tempOut -Force -ErrorAction SilentlyContinue
        }
    }
}

$placeholders = Get-CnsFtPlaceholders -WorkOrderEntity $null -PageEntity $null -SegmentMeta $null `
    -VisitDate ([datetime]'2026-07-15') -PointCollecte $pointCollecte
$placeholders.Client_Nom = 'Client fixture'
$placeholders.ODM_Numero = '1507-1'

Write-Host ("Point de collecte : {0}" -f $pointCollecte)
Write-Host ("Template : {0}" -f $TemplatePath)

$result = New-CnsFtPdfFromExcelTemplate -OutPdfPath $OutputPdfPath -Placeholders $placeholders
if ([string]::IsNullOrWhiteSpace($result) -or -not (Test-Path -LiteralPath $OutputPdfPath)) {
    throw 'Echec generation PDF FT (LibreOffice ou Excel requis)'
}

$pdfSize = (Get-Item -LiteralPath $OutputPdfPath).Length
Write-Host ("PDF FT genere : {0} ({1} octets)" -f $OutputPdfPath, $pdfSize) -ForegroundColor Green
Write-Host 'Test FT reussi' -ForegroundColor Green

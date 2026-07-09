$ErrorActionPreference = 'Stop'
$root = 'C:\Users\alexa\Documents\ConventionDeNommage\src\ODM\PdfPlanningOptimizer'
. (Join-Path $root 'Models\MatchResult.ps1')
. (Join-Path $root 'Models\PageEntity.ps1')
. (Join-Path $root 'Models\WorkOrderEntity.ps1')
. (Join-Path $root 'Models\FinalAssignment.ps1')
. (Join-Path $root 'Extractors\PdfExtractor.ps1')
. (Join-Path $root 'Extractors\EntityExtractor.ps1')
if (-not (Get-Command Resolve-PdfTotextPath -ErrorAction SilentlyContinue)) { throw 'Resolve-PdfTotextPath manquant' }
if (-not (Get-Command ConvertTo-PageEntity -ErrorAction SilentlyContinue)) { throw 'ConvertTo-PageEntity manquant' }
exit 0

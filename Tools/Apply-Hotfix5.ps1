#Requires -Version 5.1
<#
.SYNOPSIS
    Deploie hotfix5 sur C:\ASSISTANT (suppression ListAvailable au chargement planning).
#>
param(
    [string]$InstallDir = 'C:\ASSISTANT'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path (Join-Path $repoRoot 'src\GUI.ps1'))) {
    $repoRoot = 'c:\Users\alexa\Documents\ConventionDeNommage'
}

$files = @(
    @{ From = 'src\GUI.ps1'; To = 'src\GUI.ps1' }
    @{ From = 'src\Common\CnsSharePointConnector.ps1'; To = 'src\Common\CnsSharePointConnector.ps1' }
    @{ From = 'src\ODM\PdfPlanningOptimizer\PlanningRebuilderPanel.ps1'; To = 'src\ODM\PdfPlanningOptimizer\PlanningRebuilderPanel.ps1' }
    @{ From = 'src\ODM\PdfPlanningOptimizer\PlanningUILightImport.psm1'; To = 'src\ODM\PdfPlanningOptimizer\PlanningUILightImport.psm1' }
    @{ From = 'src\ODM\PdfPlanningOptimizer\PlanningEngineImport.psm1'; To = 'src\ODM\PdfPlanningOptimizer\PlanningEngineImport.psm1' }
    @{ From = 'src\ODM\PdfPlanningOptimizer\PlanningLoadTiming.ps1'; To = 'src\ODM\PdfPlanningOptimizer\PlanningLoadTiming.ps1' }
    @{ From = 'Tools\Diagnostic-PlanningSlowLoad.ps1'; To = 'Tools\Diagnostic-PlanningSlowLoad.ps1' }
)

Write-Host 'Application hotfix5 vers' $InstallDir -ForegroundColor Cyan
foreach ($item in $files) {
    $from = Join-Path $repoRoot $item.From
    $to = Join-Path $InstallDir $item.To
    if (-not (Test-Path -LiteralPath $from)) {
        throw "Fichier source manquant : $from"
    }
    $dir = Split-Path $to -Parent
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Copy-Item -LiteralPath $from -Destination $to -Force
    Write-Host "  OK $($item.To)" -ForegroundColor Green
}

'1.0.18-hotfix5' | Set-Content -LiteralPath (Join-Path $InstallDir 'version.txt') -Encoding UTF8
Write-Host 'Version -> 1.0.18-hotfix5' -ForegroundColor Green
Write-Host ''
Write-Host 'Executer sur le poste cible :' -ForegroundColor Yellow
Write-Host "  & '$InstallDir\Tools\Diagnostic-PlanningSlowLoad.ps1'" -ForegroundColor Gray

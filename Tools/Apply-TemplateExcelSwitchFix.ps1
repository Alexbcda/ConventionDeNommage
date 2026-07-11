# Applique les 3 corrections switch LibreOffice -> Excel sur une installation ASSISTANT.
param(
    [string]$InstallDir = 'C:\ASSISTANT'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$files = @(
    @{
        Rel = 'src\ODM\PdfPlanningOptimizer\Services\PlanningStep5Prerequisites.ps1'
        Check = 'Test-CnsMicrosoftExcelAvailable'
    },
    @{
        Rel = 'src\ODM\PdfPlanningOptimizer\Services\CnsExcelTemplateEngine.ps1'
        Check = 'fallback vers Excel'
    },
    @{
        Rel = 'src\ODM\PdfPlanningOptimizer\Services\PlanningRebuilder.ps1'
        Check = 'LibreOffice ou Excel'
    }
)

Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  CORRECTION TEMPLATES LO -> EXCEL' -ForegroundColor Cyan
Write-Host "  Cible : $InstallDir" -ForegroundColor Gray
Write-Host '========================================' -ForegroundColor Cyan

$fixed = 0
foreach ($entry in $files) {
    $src = Join-Path $repoRoot $entry.Rel
    $dst = Join-Path $InstallDir $entry.Rel
    Write-Host "`n$($entry.Rel)" -ForegroundColor Yellow
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Host '  ERR source repo introuvable' -ForegroundColor Red
        continue
    }
    if (-not (Test-Path -LiteralPath (Split-Path $dst -Parent))) {
        Write-Host '  ERR dossier cible absent' -ForegroundColor Red
        continue
    }
    $content = Get-Content -LiteralPath $dst -Raw -ErrorAction SilentlyContinue
    if ($content -and $content -match [regex]::Escape($entry.Check)) {
        Write-Host '  OK deja corrige' -ForegroundColor Green
        continue
    }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Write-Host '  OK fichier copie depuis le repo' -ForegroundColor Green
    $fixed++
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  $fixed fichier(s) mis a jour" -ForegroundColor Green
Write-Host '========================================' -ForegroundColor Cyan
Write-Host 'Test : pwsh -File Tools\Audit-LibreOfficeExcelSwitch.ps1 -InstallDir' $InstallDir

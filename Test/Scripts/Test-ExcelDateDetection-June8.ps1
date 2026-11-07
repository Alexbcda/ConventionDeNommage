# Test detection date 8 juin 2026 — Planning GRENOBLE
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location -LiteralPath $repoRoot

. (Join-Path $repoRoot 'src\ODM\PdfPlanningOptimizer\Services\PlanningRebuilder.ps1')

$candidates = @(
    (Join-Path $repoRoot 'Test\Fixtures\Planning GRENOBLE 2026 (1) (1).xlsm'),
    (Join-Path $repoRoot 'Test\Fixtures\PdfPlanningOptimizer\Planning GRENOBLE 2026 (1) (1).xlsm')
)
$excelPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $excelPath) {
    Write-Host 'Fichier Excel introuvable.' -ForegroundColor Red
    exit 1
}
Write-Host "Fichier : $excelPath" -ForegroundColor Gray

$excelData = Import-PlanningExcel -ExcelPath $excelPath

Write-Host "`n=== ONGLETS DISPONIBLES ===" -ForegroundColor Cyan
foreach ($sheet in @($excelData.Sheets)) {
    Write-Host "  - $($sheet.Name)" -ForegroundColor Yellow
}

$visitDate = [datetime]::new(2026, 6, 8)
Write-Host "`n=== DATE RECHERCHEE : $($visitDate.ToString('dddd dd MMMM yyyy', [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR'))) ===" -ForegroundColor Cyan

$week = Get-Iso8601WeekOfYear -Date $visitDate
Write-Host "Semaine ISO : $week" -ForegroundColor Gray

$foundSheet = Get-PlanningExcelSheetForIsoWeek -ExcelData $excelData -Week $week
if ($foundSheet) {
    Write-Host "Onglet trouve (semaine) : $($foundSheet.Name)" -ForegroundColor Green
}
else {
    Write-Host "Aucun onglet trouve pour la semaine $week (recherche par nom)" -ForegroundColor Red
}

$column = Find-ExcelColumnFromDate -ExcelData $excelData -VisitDate $visitDate -ExcelPath $excelPath

if ($column) {
    Write-Host "`nColonne trouvee :" -ForegroundColor Green
    Write-Host "  - Onglet : $($column.SheetName)"
    Write-Host "  - Colonne : $($column.ColumnIndex)"
    Write-Host "  - En-tete : $($column.HeaderText)"
    Write-Host "  - Source : $($column.Source)"
}
else {
    Write-Host "`nColonne NON trouvee pour $($visitDate.ToString('dd/MM/yyyy'))" -ForegroundColor Red

    Write-Host "`n=== DIAGNOSTIC : colonnes fixes lun-ven ===" -ForegroundColor Yellow
    $dayColMap = @{
        'Monday'    = 2
        'Tuesday'   = 25
        'Wednesday' = 48
        'Thursday'  = 71
        'Friday'    = 94
    }
    $targetCol = $dayColMap[$visitDate.DayOfWeek.ToString()]
    $targetDateShort = $visitDate.ToString('dd/MM')

    foreach ($sheet in @($excelData.Sheets)) {
        Write-Host "`nOnglet : $($sheet.Name)" -ForegroundColor Cyan
        $rowCount = [int]$sheet.RowCount
        if ($rowCount -le 4) {
            Write-Host "  -> Trop petit (lignes < 5)" -ForegroundColor DarkGray
            continue
        }
        $colZero = $targetCol - 1
        if ($null -eq $sheet.Grid -or $null -eq $sheet.Grid[4] -or $colZero -ge @($sheet.Grid[4]).Count) {
            Write-Host "  -> Colonne $targetCol inexistante" -ForegroundColor DarkGray
            continue
        }
        $headerCell = [string]$sheet.Grid[4][$colZero]
        Write-Host "  -> Colonne $targetCol (ligne 5) : '$headerCell'" -ForegroundColor White
        if ($headerCell -match [regex]::Escape($targetDateShort)) {
            Write-Host "  -> DATE TROUVEE (match dd/MM)" -ForegroundColor Green
        }
        else {
            Write-Host "  -> Date '$targetDateShort' non trouvee dans l'en-tete" -ForegroundColor Red
        }
    }

    Write-Host "`n=== PREMIERES LIGNES DU PREMIER ONGLET (cols 1-5) ===" -ForegroundColor Yellow
    $firstSheet = $excelData.Sheets[0]
    $maxRow = [Math]::Min(10, [int]$firstSheet.RowCount)
    for ($r = 0; $r -lt $maxRow; $r++) {
        $rowValues = @()
        for ($c = 0; $c -lt 5; $c++) {
            $val = ''
            if ($null -ne $firstSheet.Grid[$r] -and $c -lt @($firstSheet.Grid[$r]).Count) {
                $val = [string]$firstSheet.Grid[$r][$c]
            }
            if ($val.Length -gt 20) { $val = $val.Substring(0, 20) + '...' }
            $rowValues += $val
        }
        Write-Host "Ligne $($r + 1): $($rowValues -join ' | ')" -ForegroundColor Gray
    }
}

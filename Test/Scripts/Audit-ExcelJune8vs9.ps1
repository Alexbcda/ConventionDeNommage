$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repoRoot
. (Join-Path $repoRoot 'src\ODM\PdfPlanningOptimizer\Services\PlanningRebuilder.ps1')

$excelPaths = @(
    'C:\Users\alexa\Downloads\Planning GRENOBLE 2026 (1) (1).xlsm',
    (Join-Path $repoRoot 'Test\Fixtures\PdfPlanningOptimizer\Planning GRENOBLE 2026 (1) (1).xlsm')
) | Where-Object { Test-Path -LiteralPath $_ }

function Test-DateColumn {
    param([object]$ExcelData, [string]$ExcelPath, [datetime]$VisitDate)
    $week = Get-Iso8601WeekOfYear -Date $VisitDate
    $sheetByWeek = Get-PlanningExcelSheetForIsoWeek -ExcelData $ExcelData -Week $week
    $col = Find-ExcelColumnFromDate -ExcelData $ExcelData -VisitDate $VisitDate -ExcelPath $ExcelPath
    $fixedCol = script:Get-PlanningExcelFixedColumnFromVisitDate -VisitDate $VisitDate
    $headerManual = $null
    if ($null -ne $fixedCol) {
        foreach ($sheet in @($ExcelData.Sheets)) {
            if ($null -eq $sheet.Grid -or $null -eq $sheet.Grid[4]) { continue }
            $cz = $fixedCol - 1
            if ($cz -lt @($sheet.Grid[4]).Count) {
                $h = [string]$sheet.Grid[4][$cz]
                if (-not [string]::IsNullOrWhiteSpace($h)) {
                    $headerManual += [pscustomobject]@{ Sheet = $sheet.Name; Header = $h }
                }
            }
        }
    }
    [pscustomobject]@{
        Date          = $VisitDate.ToString('yyyy-MM-dd')
        Day           = $VisitDate.DayOfWeek.ToString()
        IsoWeek       = $week
        SheetByWeek   = if ($sheetByWeek) { $sheetByWeek.Name } else { $null }
        ColumnFound   = if ($col) { $col.ColumnIndex } else { $null }
        SheetFound    = if ($col) { $col.SheetName } else { $null }
        HeaderFound   = if ($col) { $col.HeaderText } else { $null }
        Source        = if ($col) { $col.Source } else { $null }
        ExpectedCol   = $fixedCol
        HeadersCol25  = @($headerManual | Where-Object { $_.Sheet -match 'S24|S25' } | Select-Object -First 6)
    }
}

foreach ($excelPath in $excelPaths) {
    Write-Host "`n========== EXCEL: $(Split-Path -Leaf $excelPath) ==========" -ForegroundColor Magenta
    $excelData = Import-PlanningExcel -ExcelPath $excelPath
    Write-Host "Onglets (fin): $(@($excelData.Sheets | Select-Object -Last 6).Name -join ', ')" -ForegroundColor Gray

    foreach ($d in @([datetime]::new(2026,6,8), [datetime]::new(2026,6,9))) {
        $r = Test-DateColumn -ExcelData $excelData -ExcelPath $excelPath -VisitDate $d
        Write-Host "`n$($r.Date) ($($r.Day)) ISO week $($r.IsoWeek) -> col attendue $($r.ExpectedCol)" -ForegroundColor Cyan
        Write-Host "  Onglet (semaine): $($r.SheetByWeek)"
        if ($r.ColumnFound) {
            Write-Host "  OK colonne $($r.ColumnFound) onglet '$($r.SheetFound)' en-tete '$($r.HeaderFound)' source=$($r.Source)" -ForegroundColor Green
        }
        else {
            Write-Host "  ECHEC Find-ExcelColumnFromDate" -ForegroundColor Red
        }
        Write-Host "  En-tetes col $($r.ExpectedCol) sur S24/S25:" -ForegroundColor Yellow
        foreach ($h in $r.HeadersCol25) {
            Write-Host "    $($h.Sheet) : '$($h.Header)'"
        }
    }
}

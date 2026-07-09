function script:Test-RootCauseAnalysisEnabled {
    $v = [string]$env:CN_ROOT_CAUSE_ANALYSIS
    if ([string]::IsNullOrWhiteSpace($v)) { return $false }
    return $v.Trim() -in @('1', 'true', 'yes', 'on')
}

function script:Get-RootCauseEmptyGapStats {
    param([object[]]$ExcelOrder)
    $rows = @(
        $ExcelOrder |
            Where-Object { $null -ne $_ } |
            ForEach-Object {
                try { [int]$_.ExcelRow } catch { $null }
            } |
            Where-Object { $null -ne $_ } |
            Sort-Object
    )
    if ($rows.Count -lt 2) {
        return [pscustomobject]@{
            MaxGap = 0
            GapStart = 0
            GapEnd = 0
            EmptyDensity = 0.0
        }
    }

    $maxGap = 0
    $gapStart = 0
    $gapEnd = 0
    $sumMissing = 0
    for ($i = 1; $i -lt $rows.Count; $i++) {
        $prev = [int]$rows[$i - 1]
        $cur = [int]$rows[$i]
        $missing = [Math]::Max(0, ($cur - $prev - 1))
        $sumMissing += $missing
        if ($missing -gt $maxGap) {
            $maxGap = $missing
            $gapStart = $prev + 1
            $gapEnd = $cur - 1
        }
    }
    $span = [Math]::Max(1, ([int]$rows[-1] - [int]$rows[0] + 1))
    $density = [double]$sumMissing / [double]$span
    return [pscustomobject]@{
        MaxGap = $maxGap
        GapStart = $gapStart
        GapEnd = $gapEnd
        EmptyDensity = $density
    }
}

function script:Get-RootCauseUnmatchedRate {
    param($MatchResult, [int]$ExcelCount)
    $missingCount = if ($null -eq $MatchResult) { 0 } else { @($MatchResult.Missing).Count }
    if ($ExcelCount -le 0) { return 0.0 }
    return ([double]$missingCount / [double]$ExcelCount)
}

function script:Get-RootCauseTypeFromSignals {
    param(
        [object]$GapStats,
        [double]$MismatchRatio,
        [double]$UnmatchedRate,
        [int]$ExcelClientCount,
        [int]$PdfWorkOrderCount
    )
    $type = 'None'
    $impact = 'LOW'
    $desc = 'No dominant root cause pattern detected'
    $affected = ''
    $confidence = 0.0

    $gap = [int]$GapStats.MaxGap
    $emptyDensity = [double]$GapStats.EmptyDensity
    $hasStrongGap = $gap -ge 8
    $hasHighMismatch = $MismatchRatio -ge 0.20
    $hasHighUnmatched = $UnmatchedRate -ge 0.20
    $pdfGtExcel = $PdfWorkOrderCount -gt $ExcelClientCount

    if ($hasStrongGap -and $hasHighUnmatched) {
        $type = 'ExcelBlockShiftDetected'
        $impact = 'HIGH'
        $desc = 'Client block shift detected after long empty sequence'
        $affected = ("Lines {0}-{1}" -f $GapStats.GapStart, $GapStats.GapEnd)
        $confidence = [Math]::Min(1.0, 0.55 + ([double]$gap / 40.0) + ($UnmatchedRate * 0.30))
    }
    elseif (($pdfGtExcel -and $hasHighMismatch) -or ($hasHighUnmatched -and $ExcelClientCount -lt $PdfWorkOrderCount)) {
        $type = 'MissingClientBlockDetected'
        $impact = 'MEDIUM'
        $desc = 'WorkOrders unmatched increase correlated with Excel gap'
        if ($gap -gt 0) {
            $affected = ("Lines {0}-{1}" -f $GapStats.GapStart, $GapStats.GapEnd)
        }
        $confidence = [Math]::Min(1.0, 0.50 + ($MismatchRatio * 0.60) + ($UnmatchedRate * 0.30))
    }
    elseif ($emptyDensity -ge 0.40 -or ($gap -ge 5 -and $MismatchRatio -ge 0.15)) {
        $type = 'ExcelStructureCorruptionSuspected'
        $impact = 'HIGH'
        $desc = 'High density of empty rows + irregular client grouping'
        if ($gap -gt 0) {
            $affected = ("Lines {0}-{1}" -f $GapStats.GapStart, $GapStats.GapEnd)
        }
        $confidence = [Math]::Min(1.0, 0.45 + ($emptyDensity * 0.80) + ($MismatchRatio * 0.25))
    }

    return [pscustomobject]@{
        Type = $type
        Impact = $impact
        Description = $desc
        AffectedRange = $affected
        Confidence = [Math]::Round($confidence, 2)
    }
}

function Invoke-RootCauseAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$RunContext
    )

    if (-not (Test-RootCauseAnalysisEnabled)) {
        return $null
    }

    $excelOrder = @($RunContext.ExcelOrder)
    $workOrders = @($RunContext.WorkOrders)
    $match = $RunContext.MatchResult
    $metrics = $RunContext.QualityMetrics

    $excelClientCount = @($excelOrder).Count
    $pdfWorkOrderCount = @($workOrders).Count
    $mismatchRatio = if ($null -ne $metrics -and $metrics.PSObject.Properties['MismatchRatio']) {
        [double]$metrics.MismatchRatio
    }
    elseif ($excelClientCount -gt 0) {
        [double][Math]::Abs($excelClientCount - $pdfWorkOrderCount) / [double][Math]::Max(1, $excelClientCount)
    }
    else { 0.0 }

    $gapStats = Get-RootCauseEmptyGapStats -ExcelOrder $excelOrder
    $unmatchedRate = Get-RootCauseUnmatchedRate -MatchResult $match -ExcelCount $excelClientCount
    $finding = Get-RootCauseTypeFromSignals -GapStats $gapStats -MismatchRatio $mismatchRatio -UnmatchedRate $unmatchedRate -ExcelClientCount $excelClientCount -PdfWorkOrderCount $pdfWorkOrderCount

    if ($finding.Type -eq 'None') {
        Write-Host "[ROOT-CAUSE] Type=None Confidence=0.00 Impact=LOW AffectedRange=Lines 0-0 Description=No dominant root cause pattern detected"
        Write-Host "[ROOT-CAUSE] RootCauseConfidenceScore=0"
        return [pscustomobject]@{
            Type = 'None'
            Confidence = 0.0
            Impact = 'LOW'
            AffectedRange = 'Lines 0-0'
            Description = 'No dominant root cause pattern detected'
            RootCauseConfidenceScore = 0
        }
    }

    $range = if ([string]::IsNullOrWhiteSpace($finding.AffectedRange)) { 'Lines 0-0' } else { $finding.AffectedRange }
    Write-Host ("[ROOT-CAUSE] Type={0} Confidence={1} Impact={2} AffectedRange={3} Description={4}" -f $finding.Type, $finding.Confidence, $finding.Impact, $range, $finding.Description)
    $score = [int][Math]::Round([double]$finding.Confidence * 100.0)
    Write-Host ("[ROOT-CAUSE] RootCauseConfidenceScore={0}" -f $score)

    return [pscustomobject]@{
        Type = $finding.Type
        Confidence = $finding.Confidence
        Impact = $finding.Impact
        AffectedRange = $range
        Description = $finding.Description
        RootCauseConfidenceScore = $score
    }
}

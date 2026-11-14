. (Join-Path $PSScriptRoot 'QualityMetricsStore.ps1')
. (Join-Path $PSScriptRoot 'QualityAlertEngine.ps1')

function script:Get-WorkOrderQualityStatusForMonitor {
    param([object]$WorkOrder)
    if ($null -eq $WorkOrder) { return 'OK' }
    $prop = $WorkOrder.PSObject.Properties['QualityStatus']
    if ($null -eq $prop) { return 'OK' }
    $status = [string]$prop.Value
    if ([string]::IsNullOrWhiteSpace($status)) { return 'OK' }
    $up = $status.Trim().ToUpperInvariant()
    if ($up -in @('OK', 'WARN', 'ERROR')) { return $up }
    return 'OK'
}

function script:Get-StdDev {
    param([double[]]$Values)
    if ($null -eq $Values -or $Values.Count -eq 0) { return 0.0 }
    $mean = ($Values | Measure-Object -Average).Average
    $acc = 0.0
    foreach ($v in $Values) {
        $d = ([double]$v - [double]$mean)
        $acc += ($d * $d)
    }
    return [Math]::Sqrt($acc / [Math]::Max(1, $Values.Count))
}

function Invoke-QualityMonitor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$RunContext
    )

    $workOrders = @($RunContext.WorkOrders)
    $match = $RunContext.MatchResult
    $reordered = @($RunContext.ReorderedPlanning)
    $excelOrder = @($RunContext.ExcelOrder)
    $validationSummary = $RunContext.WorkOrderValidation

    $totalWorkOrders = @($workOrders).Count
    $matched = @($match.Matches)
    $missing = @($match.Missing)
    $fallbackUsed = @($reordered | Where-Object { $null -ne $_ -and [int]$_.MatchScore -eq 0 }).Count

    $matchedOk = 0
    $matchedWarn = 0
    $matchedError = 0
    foreach ($m in $matched) {
        if ($null -eq $m -or $null -eq $m.WorkOrder) { continue }
        switch (Get-WorkOrderQualityStatusForMonitor -WorkOrder $m.WorkOrder) {
            'WARN' { $matchedWarn++ }
            'ERROR' { $matchedError++ }
            default { $matchedOk++ }
        }
    }

    $scores = @(
        $reordered |
            Where-Object { $null -ne $_ -and $null -ne $_.MatchScore } |
            ForEach-Object { [double]$_.MatchScore }
    )
    $avgScore = if ($scores.Count -gt 0) { [double](($scores | Measure-Object -Average).Average) } else { 0.0 }
    $minScore = if ($scores.Count -gt 0) { [double](($scores | Measure-Object -Minimum).Minimum) } else { 0.0 }
    $maxScore = if ($scores.Count -gt 0) { [double](($scores | Measure-Object -Maximum).Maximum) } else { 0.0 }
    $stdScore = Get-StdDev -Values ([double[]]$scores)

    $invalidGroups = if ($null -ne $validationSummary -and $null -ne $validationSummary.PSObject.Properties['ERROR']) { [int]$validationSummary.ERROR } else { 0 }
    $multiClientConflicts = @($workOrders | Where-Object { $_ -ne $null -and $_.PSObject.Properties['QualityStatus'] -and [string]$_.QualityStatus -eq 'WARN' }).Count
    $missingClientIdCount = @($workOrders | Where-Object { $_ -ne $null -and [string]::IsNullOrWhiteSpace([string]$_.ClientID) }).Count
    $missingAddressCount = @(
        $workOrders | Where-Object {
            if ($null -eq $_ -or $null -eq $_.Address) { return $true }
            [string]::IsNullOrWhiteSpace([string]$_.Address.Street) -and
            [string]::IsNullOrWhiteSpace([string]$_.Address.PostalCode) -and
            [string]::IsNullOrWhiteSpace([string]$_.Address.City)
        }
    ).Count

    $excelClientCount = @($excelOrder).Count
    $pdfWorkOrderCount = $totalWorkOrders
    $mismatchRatio = if ([Math]::Max(1, $excelClientCount) -gt 0) {
        ([double][Math]::Abs($excelClientCount - $pdfWorkOrderCount) / [double][Math]::Max(1, $excelClientCount))
    } else { 0.0 }

    $okRatio = if ($totalWorkOrders -gt 0) { [double]$matchedOk / [double]$totalWorkOrders } else { 0.0 }
    $warnRatio = if ($totalWorkOrders -gt 0) { [double]$matchedWarn / [double]$totalWorkOrders } else { 0.0 }
    $errorRatio = if ($totalWorkOrders -gt 0) { [double]$matchedError / [double]$totalWorkOrders } else { 0.0 }
    $qualityScore = ($okRatio * 100.0) - ($warnRatio * 30.0) - ($errorRatio * 80.0) - ($mismatchRatio * 50.0)
    if ($qualityScore -lt 0) { $qualityScore = 0 }

    $excelClientsWithoutId = @($excelOrder | Where-Object { $_ -ne $null -and [string]::IsNullOrWhiteSpace([string]$_.ClientId) }).Count

    $metrics = [pscustomobject]@{
        RunDate                = (Get-Date).ToString('o')
        TotalWorkOrders        = $totalWorkOrders
        MatchedOK              = $matchedOk
        MatchedWARN            = $matchedWarn
        MatchedERROR           = $matchedError
        UnmatchedCount         = @($missing).Count
        FallbackUsedCount      = $fallbackUsed
        AvgMatchScore          = [Math]::Round($avgScore, 2)
        MinMatchScore          = [Math]::Round($minScore, 2)
        MaxMatchScore          = [Math]::Round($maxScore, 2)
        StdDeviationScore      = [Math]::Round($stdScore, 2)
        InvalidWorkOrderGroups = $invalidGroups
        MultiClientConflicts   = $multiClientConflicts
        MissingClientIdCount   = $missingClientIdCount
        MissingAddressCount    = $missingAddressCount
        ExcelClientCount       = $excelClientCount
        PDFWorkOrderCount      = $pdfWorkOrderCount
        MismatchRatio          = [Math]::Round($mismatchRatio, 4)
        MismatchRatioPercent   = [Math]::Round($mismatchRatio * 100.0, 2)
        PipelineQualityScore   = [Math]::Round($qualityScore, 2)
        WarnRatioPercent       = [Math]::Round($warnRatio * 100.0, 2)
        ErrorRatioPercent      = [Math]::Round($errorRatio * 100.0, 2)
        MissingClientIdPercent = if ($totalWorkOrders -gt 0) { [Math]::Round(([double]$missingClientIdCount / [double]$totalWorkOrders) * 100.0, 2) } else { 0.0 }
        ExcelClientsWithoutId  = $excelClientsWithoutId
        OutputPdf              = [string]$RunContext.OutputPdf
    }

    Write-Host ("[QUALITY-MONITOR] RunScore={0} TotalWO={1} MatchedOK={2} WARN={3} ERROR={4}" -f $metrics.PipelineQualityScore, $metrics.TotalWorkOrders, $metrics.MatchedOK, $metrics.MatchedWARN, $metrics.MatchedERROR)

    $history = @(Get-QualityMetricsHistory -Last 50)
    Invoke-QualityAlertEngine -Metrics $metrics -History $history
    Save-QualityMetricsRun -Metrics $metrics

    return $metrics
}

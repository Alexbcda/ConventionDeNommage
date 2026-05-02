function script:Invoke-QualityAlertEngine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Metrics,
        [object[]]$History = @()
    )

    $errPct = [double]$Metrics.ErrorRatioPercent
    $warnPct = [double]$Metrics.WarnRatioPercent
    $mismatchPct = [double]$Metrics.MismatchRatioPercent
    $missingCidPct = [double]$Metrics.MissingClientIdPercent

    $hasCritical = ($errPct -gt 30.0) -or ($missingCidPct -gt 20.0)
    $hasWarning = ($warnPct -gt 40.0) -or ($mismatchPct -gt 20.0)

    if ($hasCritical) {
        Write-Host "[QUALITY-ALERT][CRITICAL] Pipeline integrity compromised"
    }
    elseif ($hasWarning) {
        Write-Host "[QUALITY-ALERT][WARNING] Quality degradation detected"
    }
    else {
        Write-Host "[QUALITY-ALERT][INFO] Pipeline stable"
    }

    $all = @($History + @($Metrics))
    if ($all.Count -ge 5) {
        $last5 = @($all | Select-Object -Last 5)
        $firstScore = [double]$last5[0].PipelineQualityScore
        $lastScore = [double]$last5[-1].PipelineQualityScore
        if ($firstScore -gt 0) {
            $dropPct = (($firstScore - $lastScore) / $firstScore) * 100.0
            if ($dropPct -ge 10.0) {
                Write-Host ("[QUALITY-ALERT][WARNING] Slow quality drift detected (ScoreDrop={0:N1}%)" -f $dropPct)
            }
        }
    }

    if ($all.Count -ge 2) {
        $prev = $all[-2]
        $prevErrPct = [double]$prev.ErrorRatioPercent
        if ($prevErrPct -gt 0.0 -and $errPct -ge ($prevErrPct * 2.0)) {
            Write-Host ("[QUALITY-ALERT][CRITICAL] Rapid drift detected (ERROR% {0:N1} -> {1:N1})" -f $prevErrPct, $errPct)
        }
    }

    if (($missingCidPct -gt 20.0) -or ([int]$Metrics.ExcelClientsWithoutId -gt 0)) {
        Write-Host "[EXCEL-CORRUPTION-SUSPECTED]"
    }
    if (([int]$Metrics.InvalidWorkOrderGroups -gt 0) -or (([double]$Metrics.ErrorRatioPercent) -gt 30.0)) {
        Write-Host "[PDF-CORRUPTION-SUSPECTED]"
    }
}

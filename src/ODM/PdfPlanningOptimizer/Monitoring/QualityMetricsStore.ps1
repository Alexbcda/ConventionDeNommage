function script:Get-QualityMetricsStorePath {
    $override = [string]$env:CN_QUALITY_MONITOR_STORE
    if (-not [string]::IsNullOrWhiteSpace($override)) {
        return $override
    }
    $dataDir = Join-Path $PSScriptRoot '..\..\..\..\Data'
    return (Join-Path $dataDir 'quality-monitor-history.jsonl')
}

function script:Get-QualityMetricsHistory {
    param([int]$Last = 50)
    $path = Get-QualityMetricsStorePath
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $lines = @(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)
    if ($lines.Count -eq 0) { return @() }
    $take = if ($Last -gt 0) { $Last } else { $lines.Count }
    $slice = @($lines | Select-Object -Last $take)
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($ln in $slice) {
        if ([string]::IsNullOrWhiteSpace($ln)) { continue }
        try {
            $obj = $ln | ConvertFrom-Json -ErrorAction Stop
            [void]$rows.Add($obj)
        }
        catch {
        }
    }
    return @($rows.ToArray())
}

function script:Save-QualityMetricsRun {
    param([object]$Metrics)
    if ($null -eq $Metrics) { return }
    $path = Get-QualityMetricsStorePath
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Path $dir -Force)
    }
    $line = ($Metrics | ConvertTo-Json -Depth 8 -Compress)
    Add-Content -LiteralPath $path -Value $line
}

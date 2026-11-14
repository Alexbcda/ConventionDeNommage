# Module planning UI — chargement rapide au 1er clic onglet (moteur differe au clic Lancer).

$moduleRoot = $PSScriptRoot
$before = @(Get-Command -CommandType Function -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })

. (Join-Path $moduleRoot 'PlanningLoadTiming.ps1')
. (Join-Path $moduleRoot 'PlanningUIHelpers.ps1')
. (Join-Path $moduleRoot 'PlanningRebuilderPanel.ps1')

$after = @(Get-Command -CommandType Function -ErrorAction SilentlyContinue)
$toExport = @(
    $after | Where-Object { $_.Name -notin $before } | ForEach-Object { $_.Name }
) | Select-Object -Unique

if ($toExport.Count -gt 0) {
    Export-ModuleMember -Function $toExport
}

$safeCmd = Get-Command -Name Safe-UpdateUIControl -ErrorAction SilentlyContinue
if ($null -ne $safeCmd) {
    $global:PlanningSafeUpdateUiCmd = $safeCmd
}
foreach ($helperName in @('Safe-UpdateUIControl', 'Invoke-PlanningSafeUpdateUi', 'Import-PlanningRebuilderEngine', 'Start-PlanningEngine')) {
    $srcFn = Get-Item -Path "function:$helperName" -ErrorAction SilentlyContinue
    if ($null -ne $srcFn) {
        Set-Item -Path "function:global:$helperName" -Value $srcFn
    }
}

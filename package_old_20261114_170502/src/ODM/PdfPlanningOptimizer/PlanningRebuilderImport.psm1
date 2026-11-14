# PlanningRebuilderImport.psm1 — module complet (UI + moteur). Utilise par les tests / chargement anticipe.
# Pour l'onglet GUI, preferer PlanningUILightImport.psm1 (moteur differe au clic Lancer).

$moduleRoot = $PSScriptRoot
$before = @(Get-Command -CommandType Function -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })

. (Join-Path $moduleRoot 'PlanningUIHelpers.ps1')
. (Join-Path $moduleRoot 'PlanningRebuilderPanel.ps1')

if (-not $script:PlanningEngineImported) {
    $null = Import-PlanningRebuilderEngine
}

$after = @(Get-Command -CommandType Function -ErrorAction SilentlyContinue)
$toExport = @(
    $after | Where-Object { $_.Name -notin $before } | ForEach-Object { $_.Name }
) | Select-Object -Unique

if ($toExport.Count -gt 0) {
    Export-ModuleMember -Function $toExport
}

# References stables pour les handlers async (BackgroundWorker, HandleCreated).
$safeCmd = Get-Command -Name Safe-UpdateUIControl -ErrorAction SilentlyContinue
if ($null -ne $safeCmd) {
    $global:PlanningSafeUpdateUiCmd = $safeCmd
}
foreach ($helperName in @('Safe-UpdateUIControl', 'Invoke-PlanningSafeUpdateUi')) {
    $srcFn = Get-Item -Path "function:$helperName" -ErrorAction SilentlyContinue
    if ($null -ne $srcFn) {
        Set-Item -Path "function:global:$helperName" -Value $srcFn
    }
}

# Moteur planning — charge au clic Lancer (pas a l'ouverture de l'onglet).

$moduleRoot = $PSScriptRoot
$before = @(Get-Command -CommandType Function -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })

. (Join-Path $moduleRoot 'Services\PlanningRebuilder.ps1')

$after = @(Get-Command -CommandType Function -ErrorAction SilentlyContinue)
$toExport = @(
    $after | Where-Object { $_.Name -notin $before } | ForEach-Object { $_.Name }
) | Select-Object -Unique

if ($toExport.Count -gt 0) {
    Export-ModuleMember -Function $toExport
}

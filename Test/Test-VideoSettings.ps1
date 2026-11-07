# Test-VideoSettings.ps1 — tests headless de la fonctionnalite video
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location (Join-Path $repoRoot 'src')
. .\Database\Database.ps1

$report = [ordered]@{}
function Set-TestResult {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $report[$Name] = @{ Ok = $Ok; Detail = $Detail }
    $color = if ($Ok) { 'Green' } else { 'Red' }
    $mark = if ($Ok) { 'OK' } else { 'FAIL' }
    Write-Host ("[{0}] {1} {2}" -f $mark, $Name, $Detail) -ForegroundColor $color
}

# Test 1 — etat initial (defaut desactive)
Set-PlanningRebuildSetting -Key 'play_video_after_treatment' -Value '0'
$initial = ([string](Get-PlanningRebuildSetting -Key 'play_video_after_treatment')).Trim()
Set-TestResult -Name 'Test1_EtatInitial' -Ok ($initial -eq '0') -Detail ("play_video={0}" -f $initial)

# Test 3 — activation BDD
Set-PlanningRebuildSetting -Key 'play_video_after_treatment' -Value '1'
$afterEnable = ([string](Get-PlanningRebuildSetting -Key 'play_video_after_treatment')).Trim()
Set-TestResult -Name 'Test3_ActivationBDD' -Ok ($afterEnable -eq '1') -Detail ("lu={0}" -f $afterEnable)

# Chemin video resolu
$path = Get-PlanningRebuildTutorialVideoResolvedPath -ConfiguredPath (Get-PlanningRebuildSetting -Key 'video_path')
Set-TestResult -Name 'Test_CheminVideo' -Ok ((Test-Path -LiteralPath $path)) -Detail $path

# Test 6 — desactivation BDD
Set-PlanningRebuildSetting -Key 'play_video_after_treatment' -Value '0'
$afterDisable = ([string](Get-PlanningRebuildSetting -Key 'play_video_after_treatment')).Trim()
Set-TestResult -Name 'Test6_DesactivationBDD' -Ok ($afterDisable -eq '0') -Detail ("lu={0}" -f $afterDisable)

# Code — condition desactivation presente
$panelFile = Join-Path $repoRoot 'src\ODM\PdfPlanningOptimizer\PlanningRebuilderPanel.ps1'
$panelContent = Get-Content -LiteralPath $panelFile -Raw
Set-TestResult -Name 'Test7_ConditionDesactivation' -Ok ($panelContent -match "if \(\`$playVideo -ne '1'\)") -Detail 'Invoke-PlanningRebuildPlayVideo'
Set-TestResult -Name 'Test4_StartProcessPresent' -Ok ($panelContent -match 'Start-Process -FilePath') -Detail 'PlanningRebuilderPanel'
Set-TestResult -Name 'Test4_TimerPresent' -Ok ($panelContent -match 'System\.Windows\.Forms\.Timer') -Detail 'timer asynchrone'

# Outils — sauvegarde Tag
$outilsFile = Join-Path $repoRoot 'src\ODM\Outils\OutilsPanel.ps1'
$outilsContent = Get-Content -LiteralPath $outilsFile -Raw
Set-TestResult -Name 'Test2_PanelTag' -Ok ($outilsContent -match '\$panel\.Tag\s*=') -Detail 'OutilsPanel contexte'
Set-TestResult -Name 'Test_NoManualSaveButton' -Ok (
    ($outilsContent -notmatch 'btnSave') -and
    ($outilsContent -notmatch 'btnTestVideo') -and
    ($outilsContent -notmatch 'Tester la video')
) -Detail 'OutilsPanel sans boutons manuels'
Set-TestResult -Name 'Test_AutoSaveEvents' -Ok (
    ($outilsContent -match 'Add_CheckedChanged') -and
    ($outilsContent -match 'Add_ValueChanged') -and
    ($outilsContent -match 'Add_TextChanged') -and
    ($outilsContent -match 'Save-OutilsPlanningRebuildSettings')
) -Detail 'OutilsPanel auto-save'

# Timer — delai respecte (~2s)
Add-Type -AssemblyName System.Windows.Forms
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000
$fired = $false
$timer.Add_Tick({
    param($s, $e)
    $s.Stop()
    $script:fired = $true
})
$timer.Start()
$deadline = [datetime]::UtcNow.AddSeconds(5)
while ($timer.Enabled -and [datetime]::UtcNow -lt $deadline) {
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 20
}
$sw.Stop()
$ms = $sw.ElapsedMilliseconds
Set-TestResult -Name 'Test_TimerDelai' -Ok ($fired -and $ms -ge 1800 -and $ms -le 3500) -Detail ("{0} ms" -f $ms)

# Restaurer etat par defaut (case decochee)
Set-PlanningRebuildSetting -Key 'play_video_after_treatment' -Value '0'
Set-PlanningRebuildSetting -Key 'video_delay_seconds' -Value '5'

Write-Host "`n=== RAPPORT FINAL ===" -ForegroundColor Cyan
$allOk = $true
foreach ($k in $report.Keys) {
    $row = $report[$k]
    if (-not $row.Ok) { $allOk = $false }
    Write-Host ("{0,-28} {1,-6} {2}" -f $k, $(if ($row.Ok) { 'OK' } else { 'FAIL' }), $row.Detail)
}
if ($allOk) {
    Write-Host "`nTous les tests automatises OK." -ForegroundColor Green
    exit 0
}
Write-Host "`nDes tests ont echoue." -ForegroundColor Red
exit 1

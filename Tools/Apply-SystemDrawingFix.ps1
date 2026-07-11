#Requires -Version 5.1
param([string]$InstallDir = 'C:\ASSISTANT')
$repo = 'c:\Users\alexa\Documents\ConventionDeNommage'

$files = @(
    'src\Common\Styles.ps1',
    'src\GUI.ps1',
    'src\Main.ps1',
    'src\ODM\PdfPlanningOptimizer\PlanningRebuilderPanel.ps1',
    'src\Database\Database.ps1'
)
foreach ($rel in $files) {
    $src = Join-Path $repo $rel
    $dst = Join-Path $InstallDir $rel
    if (-not (Test-Path -LiteralPath $src)) { throw "Source manquante : $src" }
    Copy-Item -LiteralPath $src -Destination $dst -Force
}
'1.0.18-systemdrawing' | Set-Content (Join-Path $InstallDir 'version.txt') -Encoding UTF8
Write-Host '1.0.18-systemdrawing deploye sur' $InstallDir -ForegroundColor Green

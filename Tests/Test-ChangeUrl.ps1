<#
.SYNOPSIS
    Test du changement d'adresse SharePoint
.NOTES
    Executer depuis la racine du depot : .\Tests\Test-ChangeUrl.ps1
#>

param(
    [string]$TestDir = (Join-Path $env:TEMP 'TestChangeUrl')
)

$ErrorActionPreference = 'Stop'
$script:testPassed = 0
$script:testFailed = 0

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Test-Helpers.ps1')

function Write-Test {
    param([string]$Name, [bool]$Success, [string]$Message = '')
    $status = if ($Success) { '[OK]' } else { '[ECHEC]' }
    Write-Host "$status $Name" -ForegroundColor $(if ($Success) { 'Green' } else { 'Red' })
    if ($Message) { Write-Host "   -> $Message" -ForegroundColor Gray }
    if ($Success) { $script:testPassed++ } else { $script:testFailed++ }
}

Write-Host '=== TEST CHANGEMENT D ADRESSE ===' -ForegroundColor Cyan

Write-Host '--- 1. Preparation ---' -ForegroundColor Yellow

if (Test-Path -LiteralPath $TestDir) { Remove-Item -LiteralPath $TestDir -Recurse -Force }

$packageInfo = Copy-ConventionTestPackage -Destination $TestDir -RepoRoot $repoRoot
if (-not $packageInfo.HasLib) {
    Write-Test -Name 'Package test' -Success $false -Message 'lib/ introuvable dans le depot'
    exit 1
}

. (Join-Path $TestDir 'src\Database\Database.ps1')
$null = Initialize-Database

Write-Host '--- 2. Configuration initiale ---' -ForegroundColor Yellow

$initialUrl = 'https://graph.microsoft.com/v1.0/sites/old.sharepoint.com:/sites/Old'
Set-AppConfig -Key 'SharePointApiUrl' -Value $initialUrl
Set-AppConfig -Key 'CentreName' -Value 'Ancien Centre'

$storedUrl = Get-AppConfig -Key 'SharePointApiUrl'
Write-Test -Name 'URL initiale' -Success ($storedUrl -eq $initialUrl) -Message $storedUrl

Write-Host '--- 3. Conversion URL ---' -ForegroundColor Yellow

. (Join-Path $TestDir 'src\Common\CnsSharePointConnector.ps1')

$browserUrl = 'https://nouveau.sharepoint.com/sites/NouveauCentre'
$convertedUrl = Convert-SharePointUrlToApiUrl -Url $browserUrl
$expectedUrl = 'https://graph.microsoft.com/v1.0/sites/nouveau.sharepoint.com:/sites/NouveauCentre'

Write-Test -Name 'Conversion URL navigateur vers API Graph' -Success ($convertedUrl -eq $expectedUrl) `
    -Message "$browserUrl -> $convertedUrl"

Write-Host '--- 4. Changement adresse ---' -ForegroundColor Yellow

$newUrl = 'https://graph.microsoft.com/v1.0/sites/nouveau.sharepoint.com:/sites/NouveauCentre'
Set-AppConfig -Key 'SharePointApiUrl' -Value $newUrl
Set-AppConfig -Key 'CentreName' -Value 'Nouveau Centre'

$updatedUrl = Get-AppConfig -Key 'SharePointApiUrl'
Write-Test -Name 'Nouvelle URL sauvegardee' -Success ($updatedUrl -eq $newUrl) -Message $updatedUrl

Write-Host '--- 5. Lecture URL configuree ---' -ForegroundColor Yellow

$readUrl = Get-SharePointPlanningUrl
Write-Test -Name 'Get-SharePointPlanningUrl' -Success ($readUrl -eq $newUrl) -Message $readUrl

Write-Host '--- 6. Nettoyage ---' -ForegroundColor Yellow
Remove-Item -LiteralPath $TestDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Test -Name 'Nettoyage' -Success $true

Write-Host ''
Write-Host '=== RESUME ===' -ForegroundColor Cyan
Write-Host "[OK] Reussis : $script:testPassed"
Write-Host "[ECHEC] Echecs : $script:testFailed"

if ($script:testFailed -eq 0) { exit 0 } else { exit 1 }

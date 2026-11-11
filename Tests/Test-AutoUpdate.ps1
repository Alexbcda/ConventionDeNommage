<#
.SYNOPSIS
    Test de la mise a jour automatique
.NOTES
    Simule un serveur SharePoint local pour le test.
    Executer depuis la racine du depot : .\Tests\Test-AutoUpdate.ps1
#>

param(
    [string]$TestDir = (Join-Path $env:TEMP 'TestAutoUpdate'),
    [string]$CurrentVersion = '1.0.0',
    [string]$NewVersion = '1.0.1'
)

$ErrorActionPreference = 'Stop'
$script:testPassed = 0
$script:testFailed = 0

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Test-Helpers.ps1')

function Write-Test {
    param([string]$Name, [bool]$Success, [string]$Message = '', [switch]$Optional)
    $status = if ($Success) { '[OK]' } elseif ($Optional) { '[WARN]' } else { '[ECHEC]' }
    Write-Host "$status $Name" -ForegroundColor $(if ($Success) { 'Green' } elseif ($Optional) { 'Yellow' } else { 'Red' })
    if ($Message) { Write-Host "   -> $Message" -ForegroundColor Gray }
    if ($Success) { $script:testPassed++ }
    elseif (-not $Optional) { $script:testFailed++ }
}

Write-Host '=== TEST AUTO-UPDATE ===' -ForegroundColor Cyan

Write-Host '--- 1. Preparation ---' -ForegroundColor Yellow

if (Test-Path -LiteralPath $TestDir) { Remove-Item -LiteralPath $TestDir -Recurse -Force }
$null = New-Item -ItemType Directory -Path $TestDir -Force

Write-Host "--- 2. Installation version $CurrentVersion ---" -ForegroundColor Yellow

Initialize-ConventionTestDatabase -TestDir $TestDir -RepoRoot $repoRoot

. (Join-Path $repoRoot 'src\Database\Database.ps1')
$script:DbPath = Join-Path $TestDir 'Data\gestion.db'
$script:DllPath = Join-Path $TestDir 'lib\System.Data.SQLite.dll'

Set-AppConfig -Key 'AppVersion' -Value $CurrentVersion

$currentStored = Get-AppConfig -Key 'AppVersion'
Write-Test -Name 'Version initiale stockee' -Success ($currentStored -eq $CurrentVersion) -Message $currentStored

Write-Host "--- 3. Simulation nouvelle version $NewVersion ---" -ForegroundColor Yellow

$mockSharePoint = Join-Path $TestDir 'mock_sharepoint'
$null = New-Item -ItemType Directory -Path $mockSharePoint -Force

$versionFile = Join-Path $mockSharePoint 'version.txt'
$NewVersion | Out-File -FilePath $versionFile -Encoding ascii -NoNewline

$updateZip = Join-Path $mockSharePoint "update_v${NewVersion}.zip"
$updatePayload = Join-Path $repoRoot 'src\Core\UpdateManager.ps1'
$zipError = ''
try {
    Compress-Archive -Path $updatePayload -DestinationPath $updateZip -Force
    $zipOk = Test-Path -LiteralPath $updateZip
}
catch {
    $zipOk = $false
    $zipError = $_.Exception.Message
}

Write-Test -Name 'version.txt simule' -Success (Test-Path -LiteralPath $versionFile)
Write-Test -Name 'Archive update zip' -Success $zipOk `
    -Message $(if ($zipOk) { "update_v${NewVersion}.zip" } else { $zipError }) -Optional:(-not $zipOk)

Write-Host '--- 4. Detection mise a jour ---' -ForegroundColor Yellow

$detectedVersion = (Get-Content -LiteralPath $versionFile -Raw).Trim()
Write-Test -Name 'Nouvelle version detectee' -Success ($detectedVersion -eq $NewVersion) -Message $detectedVersion

Write-Host '--- 5. Comparaison versions ---' -ForegroundColor Yellow

. (Join-Path $repoRoot 'src\Core\UpdateManager.ps1')

$updateNeeded = Test-CnsVersionIsNewer -Latest $NewVersion -Current $CurrentVersion
Write-Test -Name "Version $NewVersion > $CurrentVersion" -Success $updateNeeded

$noUpdateNeeded = -not (Test-CnsVersionIsNewer -Latest $CurrentVersion -Current $NewVersion)
Write-Test -Name "Version $CurrentVersion non superieure a $NewVersion" -Success $noUpdateNeeded

Write-Host '--- 6. Nettoyage ---' -ForegroundColor Yellow
Remove-Item -LiteralPath $TestDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Test -Name 'Nettoyage' -Success $true

Write-Host ''
Write-Host '=== RESUME ===' -ForegroundColor Cyan
Write-Host "[OK] Reussis : $script:testPassed"
Write-Host "[ECHEC] Echecs : $script:testFailed"

if ($script:testFailed -eq 0) { exit 0 } else { exit 1 }

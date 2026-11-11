<#
.SYNOPSIS
    Test de l export/import des donnees superviseur
.NOTES
    Executer depuis la racine du depot : .\Tests\Test-ExportImport.ps1
#>

param(
    [string]$TestDir = (Join-Path $env:TEMP 'TestExportImport')
)

$ErrorActionPreference = 'Stop'
$script:testPassed = 0
$script:testFailed = 0

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Test-Helpers.ps1')
$testSuffix = (Get-Date -Format 'yyyyMMddHHmmss')

function Write-Test {
    param([string]$Name, [bool]$Success, [string]$Message = '')
    $status = if ($Success) { '[OK]' } else { '[ECHEC]' }
    Write-Host "$status $Name" -ForegroundColor $(if ($Success) { 'Green' } else { 'Red' })
    if ($Message) { Write-Host "   -> $Message" -ForegroundColor Gray }
    if ($Success) { $script:testPassed++ } else { $script:testFailed++ }
}

Write-Host '=== TEST EXPORT/IMPORT SUPERVISEUR ===' -ForegroundColor Cyan

Write-Host '--- 1. Preparation ---' -ForegroundColor Yellow

if (Test-Path -LiteralPath $TestDir) { Remove-Item -LiteralPath $TestDir -Recurse -Force }

$packageInfo = Copy-ConventionTestPackage -Destination $TestDir -RepoRoot $repoRoot
if (-not $packageInfo.HasLib) {
    Write-Test -Name 'Package test' -Success $false -Message 'lib/ introuvable dans le depot'
    exit 1
}

. (Join-Path $TestDir 'src\Database\Database.ps1')
$null = Initialize-Database

Write-Host '--- 2. Creation donnees de test ---' -ForegroundColor Yellow

$testParc = "TEST-$testSuffix"
$testImmat = "AB-$testSuffix"
$testEmail = "test-$testSuffix@elise.fr"

$vehiculeId = Add-VehiculeRecord `
    -NumeroParc $testParc `
    -Immatriculation $testImmat `
    -NumeroChassis 'TEST12345678901234' `
    -DateMiseCirculation '2024-01-01' `
    -DateEntree '2024-01-01' `
    -Actif 1

$agentId = Add-Agent `
    -Nom 'TEST' `
    -Prenom 'Agent' `
    -Telephone '0123456789' `
    -Email $testEmail `
    -DateEntree (Get-Date) `
    -TypeContrat 'CDI' `
    -BaseHeuresSemaine 35 `
    -Poste 'Collecteur'

$testVehicule = Get-Vehicules -IncludeInactive | Where-Object { $_.id -eq $vehiculeId } | Select-Object -First 1
$testAgent = Get-Agents -IncludeInactive | Where-Object { $_.id -eq $agentId } | Select-Object -First 1

Write-Test -Name 'Donnees initiales' -Success ($null -ne $testVehicule -and $null -ne $testAgent) `
    -Message "Vehicule $vehiculeId, Agent $agentId"

Write-Host '--- 3. Export des donnees ---' -ForegroundColor Yellow

. (Join-Path $TestDir 'src\Database\ExportImport.ps1')
$exportPath = Join-Path $TestDir 'export_test.json'
$exportResult = Export-CenterData -DestinationPath $exportPath -IncludeAppConfig -SourceCenter 'Test'

Write-Test -Name 'Export reussi' -Success ($null -ne $exportResult) -Message $exportPath
Write-Test -Name 'Fichier JSON cree' -Success (Test-Path -LiteralPath $exportPath)

Write-Host '--- 4. Validation JSON ---' -ForegroundColor Yellow

$jsonContent = Get-Content -LiteralPath $exportPath -Raw -Encoding UTF8 | ConvertFrom-Json
$exportedVehicule = @($jsonContent.vehicules | Where-Object { $_.numero_parc -eq $testParc })
$exportedAgent = @($jsonContent.agents | Where-Object { $_.email -eq $testEmail })

Write-Test -Name 'Version export' -Success ($jsonContent.exportVersion -eq '1.0')
Write-Test -Name 'Vehicules dans export' -Success ($exportedVehicule.Count -ge 1)
Write-Test -Name 'Agents dans export' -Success ($exportedAgent.Count -ge 1)

Write-Host '--- 5. Import sur base modifiee ---' -ForegroundColor Yellow

Remove-VehiculeRecord -Id $vehiculeId | Out-Null
Remove-Agent -Id $agentId | Out-Null

$afterDeleteVehicule = Get-Vehicules -IncludeInactive | Where-Object { $_.id -eq $vehiculeId } | Select-Object -First 1
$afterDeleteAgent = Get-Agents -IncludeInactive | Where-Object { $_.id -eq $agentId } | Select-Object -First 1
Write-Test -Name 'Donnees supprimees avant import' -Success ($null -eq $afterDeleteVehicule -and $null -eq $afterDeleteAgent)

$importDryRun = Import-CenterData -SourcePath $exportPath -DryRun
Write-Test -Name 'Import DryRun' -Success ($importDryRun -eq $true)

$importResult = Import-CenterData -SourcePath $exportPath
Write-Test -Name 'Import reel' -Success ($importResult -eq $true)

$restoredVehicule = Get-Vehicules -IncludeInactive | Where-Object { $_.numero_parc -eq $testParc } | Select-Object -First 1
$restoredAgent = Get-Agents -IncludeInactive | Where-Object { $_.email -eq $testEmail } | Select-Object -First 1

Write-Test -Name 'Donnees restaurees (vehicules)' -Success ($null -ne $restoredVehicule)
Write-Test -Name 'Donnees restaurees (agents)' -Success ($null -ne $restoredAgent)

Write-Host '--- 6. Nettoyage ---' -ForegroundColor Yellow
Remove-Item -LiteralPath $TestDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Test -Name 'Nettoyage' -Success $true

Write-Host ''
Write-Host '=== RESUME ===' -ForegroundColor Cyan
Write-Host "[OK] Reussis : $script:testPassed"
Write-Host "[ECHEC] Echecs : $script:testFailed"

if ($script:testFailed -eq 0) { exit 0 } else { exit 1 }

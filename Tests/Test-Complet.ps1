<#
.SYNOPSIS
    Test complet : installation, configuration, utilisation de base
.NOTES
    Executer depuis la racine du depot : .\Tests\Test-Complet.ps1
    Prerequis : build.ps1 (optionnel pour l exe)
#>

param(
    [string]$TestDir = (Join-Path $env:TEMP 'TestConvention'),
    [string]$CentreId = 'argonay'
)

$ErrorActionPreference = 'Stop'
$script:testPassed = 0
$script:testFailed = 0
$script:testLog = @()

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Test-Helpers.ps1')
$installDir = $TestDir

function Write-Test {
    param(
        [string]$Name,
        [bool]$Success,
        [string]$Message = '',
        [string]$Details = '',
        [switch]$Optional
    )
    $status = if ($Success) { '[OK]' } elseif ($Optional) { '[WARN]' } else { '[ECHEC]' }
    Write-Host "$status $Name" -ForegroundColor $(if ($Success) { 'Green' } elseif ($Optional) { 'Yellow' } else { 'Red' })
    if ($Message) { Write-Host "   -> $Message" -ForegroundColor Gray }
    if ($Details) { Write-Host "   >> $Details" -ForegroundColor DarkGray }

    $script:testLog += [PSCustomObject]@{
        Test    = $Name
        Status  = $status
        Message = $Message
        Details = $Details
    }

    if ($Success) { $script:testPassed++ }
    elseif (-not $Optional) { $script:testFailed++ }
}

Write-Host '=== TEST COMPLET - ConventionDeNommage ===' -ForegroundColor Cyan
Write-Host "Dossier de test : $TestDir"
Write-Host "Installation : $installDir"
Write-Host "Centre teste : $CentreId"
Write-Host "Date : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host ''

Write-Host '--- 1. Preparation ---' -ForegroundColor Yellow

if (Test-Path -LiteralPath $TestDir) {
    Remove-Item -LiteralPath $TestDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Test -Name 'Nettoyage ancienne installation' -Success $true -Message "Dossier $TestDir supprime"
}

Write-Host '--- 2. Copie du package ---' -ForegroundColor Yellow

$packageInfo = $null
try {
    $packageInfo = Copy-ConventionTestPackage -Destination $TestDir -RepoRoot $repoRoot
    Write-Test -Name 'Package assemble' -Success ($packageInfo.HasLib -and $packageInfo.HasConfig) `
        -Message "lib=$($packageInfo.HasLib), config=$($packageInfo.HasConfig), exe=$($packageInfo.HasExe)"
}
catch {
    Write-Test -Name 'Package assemble' -Success $false -Message $_.Exception.Message
}

Write-Host '--- 3. Configuration centre ---' -ForegroundColor Yellow

if ($null -ne $packageInfo -and $packageInfo.HasLib -and $packageInfo.HasConfig) {
    try {
        $centre = Initialize-ConventionCentreConfig -InstallDir $installDir -CentreId $CentreId
        Write-Test -Name 'Configuration centre' -Success $true -Message "$($centre.name) -> $installDir"
    }
    catch {
        Write-Test -Name 'Configuration centre' -Success $false -Message $_.Exception.Message
    }
}
else {
    Write-Test -Name 'Configuration centre' -Success $false -Message 'Package incomplet (lib/config manquants)'
}

Write-Host '--- 4. Verification post-installation ---' -ForegroundColor Yellow

if (Test-Path -LiteralPath $installDir) {
    Write-Test -Name 'Dossier installation' -Success $true -Message $installDir

    $keyFiles = @('ConventionDeNommage.exe', 'src\Main.ps1', 'Data\gestion.db', 'config\centres.json')
    foreach ($file in $keyFiles) {
        $filePath = Join-Path $installDir $file
        $isExe = $file -eq 'ConventionDeNommage.exe'
        Write-Test -Name "Fichier $file" -Success (Test-Path -LiteralPath $filePath) -Message $filePath -Optional:$isExe
    }

    try {
        . (Join-Path $installDir 'src\Database\Database.ps1')
        $null = Initialize-Database
        $url = Get-AppConfig -Key 'SharePointApiUrl'
        $centreName = Get-AppConfig -Key 'CentreName'
        $centreIdStored = Get-AppConfig -Key 'CentreId'

        Write-Test -Name 'Configuration URL SharePoint' -Success (-not [string]::IsNullOrWhiteSpace($url)) -Message $url
        Write-Test -Name 'Configuration CentreName' -Success (-not [string]::IsNullOrWhiteSpace($centreName)) -Message $centreName
        Write-Test -Name 'Configuration CentreId' -Success ($centreIdStored -eq $CentreId) -Message $centreIdStored
    }
    catch {
        Write-Test -Name 'Configuration BDD' -Success $false -Message $_.Exception.Message
    }
}
else {
    Write-Test -Name 'Dossier installation' -Success $false -Message "$installDir n'existe pas"
}

Write-Host '--- 5. Lancement application ---' -ForegroundColor Yellow

$exePath = Join-Path $installDir 'ConventionDeNommage.exe'
if (Test-Path -LiteralPath $exePath) {
    try {
        $process = Start-Process -FilePath $exePath -WorkingDirectory $installDir -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 10

        if (-not $process.HasExited) {
            Write-Test -Name 'Lancement application' -Success $true -Message "PID: $($process.Id)"
            $process.Kill()
            $process.WaitForExit(5000)
        }
        else {
            Write-Test -Name 'Lancement application' -Success $false -Message "Exit code: $($process.ExitCode)"
        }
    }
    catch {
        Write-Test -Name 'Lancement application' -Success $false -Message $_.Exception.Message
    }
}
else {
    Write-Test -Name 'Lancement application' -Success $false `
        -Message 'Exe absent - executez .\build.ps1 ou Tests\Test-Compilation.ps1' -Optional
}

$logDir = Join-Path $PSScriptRoot 'logs'
$null = New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue
$logPath = Join-Path $logDir ("test_complet_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$script:testLog | Export-Csv -Path $logPath -NoTypeInformation -Encoding UTF8

Write-Host '--- 6. Nettoyage ---' -ForegroundColor Yellow

try {
    if (Test-Path -LiteralPath $installDir) {
        Remove-Item -LiteralPath $installDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Test -Name 'Desinstallation' -Success $true -Message "$installDir supprime"
}
catch {
    Write-Test -Name 'Desinstallation' -Success $false -Message $_.Exception.Message
}

Write-Host ''
Write-Host '=== RESUME ===' -ForegroundColor Cyan
Write-Host "[OK] Reussis : $script:testPassed"
Write-Host "[ECHEC] Echecs : $script:testFailed"
Write-Host "Log sauvegarde : $logPath"

if ($script:testFailed -eq 0) {
    Write-Host 'Test complet reussi !' -ForegroundColor Green
    exit 0
}
else {
    Write-Host 'Des tests ont echoue. Verifier les logs.' -ForegroundColor Yellow
    exit 1
}

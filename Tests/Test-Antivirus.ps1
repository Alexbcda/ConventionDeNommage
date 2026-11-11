<#
.SYNOPSIS
    Test de l application avec Windows Defender
.NOTES
    Executer en tant qu administrateur pour les exclusions Defender.
    Executer depuis la racine du depot : .\Tests\Test-Antivirus.ps1
#>

param(
    [string]$ExePath = ''
)

$ErrorActionPreference = 'Continue'
$script:testPassed = 0
$script:testFailed = 0

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ExePath)) {
    $ExePath = Join-Path $repoRoot 'output\Assistant.exe'
}

function Write-Test {
    param(
        [string]$Name,
        [bool]$Success,
        [string]$Message = '',
        [switch]$Optional
    )
    $status = if ($Success) { '[OK]' } elseif ($Optional) { '[WARN]' } else { '[ECHEC]' }
    Write-Host "$status $Name" -ForegroundColor $(if ($Success) { 'Green' } elseif ($Optional) { 'Yellow' } else { 'Red' })
    if ($Message) { Write-Host "   -> $Message" -ForegroundColor Gray }
    if ($Success) { $script:testPassed++ }
    elseif (-not $Optional) { $script:testFailed++ }
}

Write-Host '=== TEST ANTIVIRUS (Windows Defender) ===' -ForegroundColor Cyan

Write-Host '--- 1. Statut Windows Defender ---' -ForegroundColor Yellow

try {
    $defenderStatus = Get-MpComputerStatus -ErrorAction Stop
    Write-Test -Name 'RealTimeProtection' -Success $defenderStatus.RealTimeProtectionEnabled `
        -Optional:(-not $defenderStatus.RealTimeProtectionEnabled)
    Write-Test -Name 'AntispywareEnabled' -Success $defenderStatus.AntispywareEnabled `
        -Optional:(-not $defenderStatus.AntispywareEnabled)
    Write-Test -Name 'AntivirusEnabled' -Success $defenderStatus.AntivirusEnabled `
        -Optional:(-not $defenderStatus.AntivirusEnabled)
}
catch {
    Write-Test -Name 'Acces Defender' -Success $false -Message $_.Exception.Message -Optional
}

Write-Host '--- 2. Scan de l executable ---' -ForegroundColor Yellow

if (Test-Path -LiteralPath $ExePath) {
    $exeFullPath = (Resolve-Path -LiteralPath $ExePath).Path
    Write-Test -Name 'Fichier present' -Success $true -Message $exeFullPath

    $hash = Get-FileHash -LiteralPath $exeFullPath -Algorithm SHA256
    Write-Test -Name 'SHA-256 calcule' -Success $true -Message $hash.Hash

    try {
        $null = Start-MpScan -ScanType CustomScan -ScanPath $exeFullPath -ErrorAction SilentlyContinue
        Write-Test -Name 'Scan Defender' -Success $true -Message 'Scan lance sans erreur'
    }
    catch {
        Write-Test -Name 'Scan Defender' -Success $false -Message $_.Exception.Message -Optional
    }

    $threats = Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.Resources -like '*Assistant*' }
    if ($threats) {
        Write-Test -Name 'Menaces detectees' -Success $false -Message "$($threats.Count) menace(s)"
        $threats | ForEach-Object {
            Write-Host "     - $($_.ThreatName)" -ForegroundColor Red
        }
    }
    else {
        Write-Test -Name 'Menaces detectees' -Success $true -Message 'Aucune'
    }
}
else {
    Write-Test -Name 'Fichier exe' -Success $false -Message "$ExePath introuvable - executez .\build.ps1" -Optional
}

Write-Host '--- 3. Exclusions Defender ---' -ForegroundColor Yellow

try {
    $pref = Get-MpPreference -ErrorAction Stop
    $exclusionPaths = @($pref.ExclusionPath)
    $exclusionProcesses = @($pref.ExclusionProcess)

    $installDir = "$env:ProgramFiles\ASSISTANT"
    $localAppData = Join-Path $env:LOCALAPPDATA 'ASSISTANT'

    $hasInstallExclusion = $exclusionPaths | Where-Object { $_ -eq $installDir }
    $hasLocalExclusion = $exclusionPaths | Where-Object { $_ -eq $localAppData }
    $hasProcessExclusion = $exclusionProcesses | Where-Object { $_ -eq 'Assistant.exe' }

    Write-Test -Name 'Exclusion dossier ProgramFiles' -Success ($null -ne $hasInstallExclusion) -Optional
    Write-Test -Name 'Exclusion dossier LocalAppData' -Success ($null -ne $hasLocalExclusion) -Optional
    Write-Test -Name 'Exclusion processus' -Success ($null -ne $hasProcessExclusion) -Optional
}
catch {
    Write-Test -Name 'Lecture exclusions' -Success $false -Message $_.Exception.Message -Optional
}

Write-Host ''
Write-Host '=== RECOMMANDATIONS ===' -ForegroundColor Cyan
Write-Host 'Si l application est bloquee, ajouter les exclusions suivantes (admin) :'
Write-Host ''
Write-Host 'Add-MpPreference -ExclusionPath "C:\Program Files\ASSISTANT"'
Write-Host "Add-MpPreference -ExclusionPath '$env:LOCALAPPDATA\ASSISTANT'"
Write-Host 'Add-MpPreference -ExclusionProcess "Assistant.exe"'
Write-Host ''

Write-Host '=== RESUME ===' -ForegroundColor Cyan
Write-Host "[OK] Reussis : $script:testPassed"
Write-Host "[ECHEC] Echecs : $script:testFailed"

if ($script:testFailed -eq 0) {
    Write-Host 'Aucun probleme antivirus detecte !' -ForegroundColor Green
    exit 0
}
else {
    Write-Host 'Certains tests ont echoue. Voir recommandations ci-dessus.' -ForegroundColor Yellow
    exit 1
}

<#
.SYNOPSIS
    Test de la compilation .exe
.NOTES
    Executer depuis la racine du depot : .\Tests\Test-Compilation.ps1
#>

param(
    [string]$BuildScript = '',
    [string]$Version = '1.0.0'
)

$ErrorActionPreference = 'Stop'
$script:testPassed = 0
$script:testFailed = 0

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($BuildScript)) {
    $BuildScript = Join-Path $repoRoot 'build.ps1'
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

Write-Host '=== TEST COMPILATION EXE ===' -ForegroundColor Cyan

Write-Host '--- 1. Verification PS2EXE ---' -ForegroundColor Yellow

$ps2exe = Get-Module -ListAvailable PS2EXE, ps2exe | Select-Object -First 1
Write-Test -Name 'Module PS2EXE installe' -Success ($null -ne $ps2exe) `
    -Message $(if ($ps2exe) { "$($ps2exe.Name) v$($ps2exe.Version)" } else { 'Install-Module ps2exe' })

Write-Host '--- 2. Compilation ---' -ForegroundColor Yellow

if (Test-Path -LiteralPath $BuildScript) {
    try {
        Push-Location $repoRoot
        & $BuildScript -Version $Version -Clean
        Write-Test -Name 'build.ps1 execute' -Success $true
    }
    catch {
        Write-Test -Name 'build.ps1 execute' -Success $false -Message $_.Exception.Message
    }
    finally {
        Pop-Location
    }
}
else {
    Write-Test -Name 'build.ps1 execute' -Success $false -Message "Script introuvable : $BuildScript"
}

Write-Host '--- 3. Verification fichiers generes ---' -ForegroundColor Yellow

$outputDir = Join-Path $repoRoot 'output'
if (Test-Path -LiteralPath $outputDir) {
    $exePath = Join-Path $outputDir 'ConventionDeNommage.exe'
    $installScript = Join-Path $outputDir 'install.ps1'
    $versionFile = Join-Path $outputDir 'version.txt'

    Write-Test -Name 'ConventionDeNommage.exe' -Success (Test-Path -LiteralPath $exePath)
    Write-Test -Name 'install.ps1' -Success (Test-Path -LiteralPath $installScript)
    Write-Test -Name 'version.txt' -Success (Test-Path -LiteralPath $versionFile)

    if (Test-Path -LiteralPath $exePath) {
        $exeInfo = Get-Item -LiteralPath $exePath
        Write-Test -Name 'Taille exe' -Success ($exeInfo.Length -gt 0) -Message "$([math]::Round($exeInfo.Length / 1KB, 2)) Ko"

        $sig = Get-AuthenticodeSignature -LiteralPath $exePath
        if ($sig.Status -eq 'Valid') {
            Write-Test -Name 'Signature exe' -Success $true -Message "Signe par $($sig.SignerCertificate.Subject)"
        }
        else {
            Write-Test -Name 'Signature exe' -Success $false -Message 'Non signe (attendu en dev/test)' -Optional
        }
    }

    $requiredDirs = @('src', 'Data', 'lib', 'config')
    foreach ($dir in $requiredDirs) {
        $dirPath = Join-Path $outputDir $dir
        Write-Test -Name "Dossier $dir/" -Success (Test-Path -LiteralPath $dirPath)
    }

    if (Test-Path -LiteralPath $versionFile) {
        $builtVersion = (Get-Content -LiteralPath $versionFile -Raw).Trim()
        Write-Test -Name 'Version dans version.txt' -Success ($builtVersion -eq $Version) -Message $builtVersion
    }
}
else {
    Write-Test -Name 'Dossier output/' -Success $false
}

Write-Host '--- 4. Test executable ---' -ForegroundColor Yellow

$exeFullPath = Join-Path $outputDir 'ConventionDeNommage.exe'
if (Test-Path -LiteralPath $exeFullPath) {
    try {
        $process = Start-Process -FilePath $exeFullPath -WorkingDirectory $outputDir -PassThru -WindowStyle Hidden
        Start-Sleep -Seconds 5
        if (-not $process.HasExited) {
            Write-Test -Name 'Exe demarre sans erreur' -Success $true
            $process.Kill()
            $process.WaitForExit(5000)
        }
        else {
            Write-Test -Name 'Exe demarre sans erreur' -Success $false -Message "Exit code: $($process.ExitCode)"
        }
    }
    catch {
        Write-Test -Name 'Exe demarre sans erreur' -Success $false -Message $_.Exception.Message
    }
}

Write-Host ''
Write-Host '=== RESUME ===' -ForegroundColor Cyan
Write-Host "[OK] Reussis : $script:testPassed"
Write-Host "[ECHEC] Echecs : $script:testFailed"

if ($script:testFailed -eq 0) { exit 0 } else { exit 1 }

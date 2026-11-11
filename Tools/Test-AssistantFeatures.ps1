#Requires -Version 5.1
<#
.SYNOPSIS
    Tests fonctionnels ASSISTANT (clic droit, icone, lancement, Ghostscript, templates).
.EXAMPLE
    .\Tools\Test-AssistantFeatures.ps1 -PackageDir .\package
    .\Tools\Test-AssistantFeatures.ps1 -InstallDir C:\ASSISTANT -Test Ghostscript
#>
[CmdletBinding()]
param(
    [string]$PackageDir = '',
    [string]$InstallDir = 'C:\ASSISTANT',
    [ValidateSet('All', 'ContextMenu', 'Icon', 'Launch', 'Ghostscript', 'Templates')]
    [string[]]$Test = @('All')
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($PackageDir)) {
    $PackageDir = Join-Path $repoRoot 'package'
}
$PackageDir = (Resolve-Path -LiteralPath $PackageDir).Path
$targetRoot = if (Test-Path -LiteralPath (Join-Path $InstallDir 'ASSISTANT.bat')) {
    (Resolve-Path -LiteralPath $InstallDir).Path
} elseif (Test-Path -LiteralPath (Join-Path $PackageDir 'ASSISTANT.bat')) {
    $PackageDir
} else {
    $InstallDir
}

$fail = 0
function Write-FeatureResult {
    param([bool]$Ok, [string]$Message)
    if ($Ok) { Write-Host "  OK  $Message" -ForegroundColor Green }
    else { Write-Host "  KO  $Message" -ForegroundColor Red; $script:fail++ }
}

function Test-AssistantContextMenuFeature {
    param([string]$Root)
    Write-Host '=== TEST 1 : Clic droit / registre PDF ===' -ForegroundColor Cyan
    $regPath = 'HKCU:\Software\Classes\SystemFileAssociations\.pdf\shell\ASSISTANT'
    try {
        $reg = Get-ItemProperty -LiteralPath $regPath -ErrorAction Stop
        Write-FeatureResult ($reg.'(default)' -eq 'Assistant') ("(Default) = '$($reg.'(default)')'")
        Write-FeatureResult ($reg.Icon -like '*ASSISTANT.ico*') ("Icon = '$($reg.Icon)'")
        $cmd = (Get-ItemProperty -LiteralPath (Join-Path $regPath 'command')).'(default)'
        Write-FeatureResult ($cmd -like '*ASSISTANT.bat*"%1"*') ("Command = '$cmd'")
        Write-FeatureResult ($cmd -like '*cmd.exe*') ('Commande via cmd.exe /c')
    }
    catch {
        Write-FeatureResult $false 'Cle registre ASSISTANT absente'
    }
    Write-FeatureResult (Test-Path -LiteralPath (Join-Path $Root 'ASSISTANT.ico')) "$Root\ASSISTANT.ico"
    Write-FeatureResult (Test-Path -LiteralPath (Join-Path $Root 'ASSISTANT.bat')) "$Root\ASSISTANT.bat"
}

function Test-AssistantIconFeature {
    param([string]$Root)
    Write-Host '=== TEST 2 : Icone ===' -ForegroundColor Cyan
    $ico = Join-Path $Root 'ASSISTANT.ico'
    Write-FeatureResult (Test-Path -LiteralPath $ico) 'ASSISTANT.ico present'
    if (Test-Path -LiteralPath $ico) {
        $len = (Get-Item -LiteralPath $ico).Length
        Write-FeatureResult ($len -gt 100) ("Taille icone : $len octets")
    }
}

function Test-AssistantLaunchFeature {
    param([string]$Root)
    Write-Host '=== TEST 3 : Lancement ===' -ForegroundColor Cyan
    foreach ($rel in @('ASSISTANT.bat', 'src\Main.ps1', 'src\LaunchAssistant.ps1')) {
        Write-FeatureResult (Test-Path -LiteralPath (Join-Path $Root $rel)) $rel
    }
    $bat = Join-Path $Root 'ASSISTANT.bat'
    if (Test-Path -LiteralPath $bat) {
        $c = Get-Content -LiteralPath $bat -Raw
        Write-FeatureResult ($c -match 'ASSISTANT_PDF') 'ASSISTANT.bat transmet ASSISTANT_PDF'
        Write-FeatureResult ($c -match 'LaunchAssistant\.ps1') 'ASSISTANT.bat appelle LaunchAssistant.ps1'
    }
}

function Test-AssistantGhostscriptFeature {
    param([string]$Root)
    Write-Host '=== TEST 4 : Ghostscript (etape 5) ===' -ForegroundColor Cyan
    $embeddedExe = Join-Path $Root 'runtime\ghostscript\gswin64c.exe'
    $embeddedDll = Join-Path $Root 'runtime\ghostscript\gsdll64.dll'
    Write-FeatureResult (Test-Path -LiteralPath $embeddedExe) 'runtime\ghostscript\gswin64c.exe'
    Write-FeatureResult (Test-Path -LiteralPath $embeddedDll) 'runtime\ghostscript\gsdll64.dll'

    $gsResolve = Join-Path $repoRoot 'src\Core\GhostscriptResolve.ps1'
    if (-not (Test-Path -LiteralPath $gsResolve)) {
        $gsResolve = Join-Path $Root 'src\Core\GhostscriptResolve.ps1'
    }
    Write-FeatureResult (Test-Path -LiteralPath $gsResolve) 'GhostscriptResolve.ps1'
    if (Test-Path -LiteralPath $gsResolve) {
        $env:ASSISTANT_INSTALL_DIR = $Root
        . $gsResolve
        $resolved = Get-ResolvedGhostscriptPath
        Write-FeatureResult (-not [string]::IsNullOrWhiteSpace($resolved)) "Get-ResolvedGhostscriptPath = $resolved"
        if (-not [string]::IsNullOrWhiteSpace($resolved)) {
            Write-FeatureResult ($resolved -like "*$Root*") 'Ghostscript resolu depuis le package/installation'
        }

        $coverScript = Join-Path $repoRoot 'src\ODM\PdfPlanningOptimizer\Services\PdfTourneeCoverComposer.ps1'
        if (-not (Test-Path -LiteralPath $coverScript)) {
            $coverScript = Join-Path $Root 'src\ODM\PdfPlanningOptimizer\Services\PdfTourneeCoverComposer.ps1'
        }
        if (Test-Path -LiteralPath $coverScript) {
            . $coverScript
            $outPdf = Join-Path $env:TEMP ("cn_feature_gs_{0}.pdf" -f [Guid]::NewGuid().ToString('N'))
            $ok = New-CnsGlobalMismatchCoverPdf -OutPdfPath $outPdf -TotalOdmCount 10 -UnmatchedOdmCount 1 `
                -Section1Count 0 -Section2Count 1 -Section3Count 0
            Write-FeatureResult $ok 'New-CnsGlobalMismatchCoverPdf (page de garde globale)'
            if (Test-Path -LiteralPath $outPdf) {
                $sz = (Get-Item -LiteralPath $outPdf).Length
                Write-FeatureResult ($sz -gt 1000) ("PDF genere : $sz octets")
                Remove-Item -LiteralPath $outPdf -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Test-AssistantTemplatesFeature {
    param([string]$Root)
    Write-Host '=== TEST 5 : Templates ===' -ForegroundColor Cyan
    foreach ($tpl in @('CertificatDeDestruction.xlsx', 'BilanDeCollecte.xlsx', 'CeaPointsDeCollectes.xlsx')) {
        Write-FeatureResult (Test-Path -LiteralPath (Join-Path $Root "templates\$tpl")) "templates\$tpl"
    }
}

$runAll = ($Test -contains 'All') -or $Test.Count -lt 1
if ($runAll -or ($Test -contains 'ContextMenu')) { Test-AssistantContextMenuFeature -Root $targetRoot }
if ($runAll -or ($Test -contains 'Icon')) { Test-AssistantIconFeature -Root $targetRoot }
if ($runAll -or ($Test -contains 'Launch')) { Test-AssistantLaunchFeature -Root $targetRoot }
if ($runAll -or ($Test -contains 'Ghostscript')) { Test-AssistantGhostscriptFeature -Root $targetRoot }
if ($runAll -or ($Test -contains 'Templates')) { Test-AssistantTemplatesFeature -Root $targetRoot }

Write-Host ''
if ($fail -eq 0) {
    Write-Host '=== TOUS LES TESTS FONCTIONNELS OK ===' -ForegroundColor Green
    exit 0
}
Write-Host "=== $fail TEST(S) EN ECHEC ===" -ForegroundColor Red
exit 1

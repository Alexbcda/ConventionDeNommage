#Requires -Version 5.1
<#
.SYNOPSIS
    Re-enregistre le menu contextuel PDF "Assistant" sans reinstallation complete.
.EXAMPLE
    .\Tools\Register-AssistantContextMenu.ps1 -InstallDir C:\ASSISTANT
#>
param(
    [string]$InstallDir = 'C:\ASSISTANT'
)

$ErrorActionPreference = 'Stop'

function Register-AssistantPdfContextMenuLocal {
    param(
        [Parameter(Mandatory = $true)][string]$InstallDir,
        [Parameter(Mandatory = $true)][string]$LauncherPath,
        [string]$IconPath = '',
        [string]$MenuLabel = 'Assistant'
    )
    $shellKey = 'HKCU:\Software\Classes\SystemFileAssociations\.pdf\shell\ASSISTANT'
    $cmdKey = Join-Path $shellKey 'command'

    if (-not (Test-Path -LiteralPath $LauncherPath)) {
        throw "Lanceur introuvable : $LauncherPath"
    }
    $launcherResolved = (Resolve-Path -LiteralPath $LauncherPath).Path

    $iconCandidate = $IconPath
    if ([string]::IsNullOrWhiteSpace($iconCandidate)) {
        $iconCandidate = Join-Path $InstallDir 'ASSISTANT.ico'
    }
    if (-not (Test-Path -LiteralPath $iconCandidate)) {
        throw "ASSISTANT.ico introuvable : $iconCandidate"
    }
    $iconValue = (Resolve-Path -LiteralPath $iconCandidate).Path
    if ($iconValue -notmatch ',\d+$') {
        $iconValue = '{0},0' -f $iconValue
    }

    if ($launcherResolved -like '*.vbs') {
        $wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
        $commandValue = ('"{0}" //nologo "{1}" "%1"' -f $wscript, $launcherResolved)
    }
    else {
        $cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
        $commandValue = ('"{0}" /c ""{1}" "%1""' -f $cmdExe, $launcherResolved)
    }

    if (-not (Test-Path -LiteralPath $shellKey)) { $null = New-Item -Path $shellKey -Force }
    if (-not (Test-Path -LiteralPath $cmdKey)) { $null = New-Item -Path $cmdKey -Force }
    Set-ItemProperty -LiteralPath $shellKey -Name '(Default)' -Value $MenuLabel
    Set-ItemProperty -LiteralPath $shellKey -Name 'Icon' -Value $iconValue
    Set-ItemProperty -LiteralPath $cmdKey -Name '(Default)' -Value $commandValue

    $verify = Get-ItemProperty -LiteralPath $shellKey
    $verifyCmd = Get-ItemProperty -LiteralPath $cmdKey
    if ($verify.'(default)' -ne $MenuLabel) {
        throw 'Verification registre echouee (label)'
    }
    Write-Host "Menu contextuel PDF enregistre : $MenuLabel" -ForegroundColor Green
    Write-Host "  Commande : $($verifyCmd.'(default)')"
    Write-Host "  Icone    : $iconValue"
}

$vbs = Join-Path $InstallDir 'Launcher.vbs'
$bat = Join-Path $InstallDir 'ASSISTANT.bat'
$launcher = if (Test-Path -LiteralPath $vbs) { $vbs } else { $bat }
$icon = Join-Path $InstallDir 'ASSISTANT.ico'
Register-AssistantPdfContextMenuLocal -InstallDir $InstallDir -LauncherPath $launcher -IconPath $icon

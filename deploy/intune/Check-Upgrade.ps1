<#
.SYNOPSIS
    Verifie si une mise a jour est necessaire.
    Utilisable comme requirement rule Intune ou pre-install SCCM.
.PARAMETER TargetVersion
    Version cible a installer.
.OUTPUTS
    Exit 0 = upgrade necessaire (version inferieure ou absente).
    Exit 1 = deja a jour (version identique ou superieure).
#>
[CmdletBinding()]
param(
    [string]$TargetVersion = '1.0.0'
)

$regKey = 'HKLM:\SOFTWARE\ConventionDeNommage'

# App non installee -> upgrade necessaire
if (-not (Test-Path -LiteralPath $regKey)) {
    Write-Output "Not installed - upgrade needed"
    exit 0
}

$currentVersion = (Get-ItemProperty -LiteralPath $regKey -Name 'Version' -ErrorAction SilentlyContinue).Version

# Pas de version en registre -> upgrade necessaire
if ([string]::IsNullOrWhiteSpace($currentVersion)) {
    Write-Output "No version in registry - upgrade needed"
    exit 0
}

try {
    $current = [version]$currentVersion
    $target  = [version]$TargetVersion
}
catch {
    Write-Output "Version parse error (current=$currentVersion, target=$TargetVersion) - upgrade needed"
    exit 0
}

if ($current -lt $target) {
    Write-Output "Current v$current < target v$target - upgrade needed"
    exit 0
}

Write-Output "Current v$current >= target v$target - already up to date"
exit 1

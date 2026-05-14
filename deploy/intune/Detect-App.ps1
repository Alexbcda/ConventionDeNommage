# Detect-App.ps1 - Intune Win32 App Detection Script
# Exit 0 + stdout = app detected (installed)
# Exit 1 / no stdout = app not detected

$installDir = "${env:ProgramFiles}\ConventionDeNommage"

# Check 1 : Launcher.cmd
if (-not (Test-Path -LiteralPath "$installDir\Launcher.cmd" -PathType Leaf)) {
    exit 1
}

# Check 2 : Main.ps1
if (-not (Test-Path -LiteralPath "$installDir\src\Main.ps1" -PathType Leaf)) {
    exit 1
}

# Check 3 : Registry version
$regKey = 'HKLM:\SOFTWARE\ConventionDeNommage'
if (Test-Path -LiteralPath $regKey) {
    $version = (Get-ItemProperty -LiteralPath $regKey -Name 'Version' -ErrorAction SilentlyContinue).Version
    if (-not [string]::IsNullOrWhiteSpace($version)) {
        Write-Output "Convention de Nommage v$version detected"
        exit 0
    }
}

# Fallback : fichiers presents sans registre (install manuelle)
Write-Output "Convention de Nommage detected (no registry)"
exit 0

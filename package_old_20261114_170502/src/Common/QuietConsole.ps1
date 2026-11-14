# QuietConsole.ps1 - Supprime la sortie console en exe ASSISTANT (evite MessageBox PS2EXE).
# Activer les traces : $env:CN_VERBOSE = '1'

function Test-AppConsoleVisible {
    if ($env:CN_VERBOSE -in @('1', 'true', 'TRUE', 'yes', 'YES')) {
        return $true
    }
    if ($global:SuppressConsoleOutput -eq $true) {
        return $false
    }
    return $true
}

# En exe PS2EXE : neutraliser Write-Host/Write-Warning (sinon MessageBox par ligne)
if ($global:SuppressConsoleOutput -eq $true) {
    function global:Write-Host {
        param(
            [object]$Object,
            [switch]$NoNewline,
            [object]$ForegroundColor,
            [object]$BackgroundColor
        )
    }
    function global:Write-Warning {
        param([object]$Message, [switch]$Verbose)
    }
}

function Write-AppHost {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [object]$Object,
        [object]$ForegroundColor,
        [switch]$NoNewline
    )
    if (-not (Test-AppConsoleVisible)) {
        return
    }
    $params = @{ Object = $Object }
    if ($null -ne $ForegroundColor) { $params.ForegroundColor = $ForegroundColor }
    if ($NoNewline) { $params.NoNewline = $true }
    Microsoft.PowerShell.Utility\Write-Host @params
}

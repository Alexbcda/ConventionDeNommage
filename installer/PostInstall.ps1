<#
.SYNOPSIS
    Configuration post-installation pour Convention de Nommage.
    Execute automatiquement par Inno Setup apres copie des fichiers.
.PARAMETER InstallDir
    Repertoire d'installation (Program Files).
.PARAMETER DataDir
    Repertoire de donnees (ProgramData).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InstallDir,

    [Parameter(Mandatory)]
    [string]$DataDir
)

$ErrorActionPreference = 'Stop'

# -- 1. Creer la structure ProgramData --
$dirs = @('config', 'Data', 'Logs', 'Cache')
foreach ($dir in $dirs) {
    $fullPath = Join-Path $DataDir $dir
    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        $null = New-Item -Path $fullPath -ItemType Directory -Force
    }
}

# -- 2. Generer config/runtime.json --
$cfgPath = Join-Path $DataDir 'config\runtime.json'

$gsPath = ''
foreach ($exe in @('gswin64c.exe', 'gswin32c.exe')) {
    $candidate = Join-Path $InstallDir "runtime\ghostscript\bin\$exe"
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $gsPath = $candidate
        break
    }
}
if ([string]::IsNullOrWhiteSpace($gsPath)) {
    $systemCandidates = @(
        "${env:ProgramFiles}\PDF24\gs\bin\gswin64c.exe",
        "${env:ProgramFiles}\Ghostscript\bin\gswin64c.exe"
    )
    $gsRoot = Join-Path $env:ProgramFiles 'gs'
    if (Test-Path -LiteralPath $gsRoot -PathType Container) {
        $gsDir = Get-ChildItem -LiteralPath $gsRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($null -ne $gsDir) {
            $systemCandidates += Join-Path $gsDir.FullName 'bin\gswin64c.exe'
        }
    }
    foreach ($c in $systemCandidates) {
        if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path -LiteralPath $c -PathType Leaf)) {
            $gsPath = $c
            break
        }
    }
}

$ppPath = ''
$popplerCandidates = @(
    (Join-Path $InstallDir 'runtime\poppler\bin\pdftotext.exe'),
    (Join-Path $InstallDir 'runtime\poppler\Library\bin\pdftotext.exe'),
    "${env:ProgramFiles}\Xpdf\pdftotext.exe",
    "${env:LOCALAPPDATA}\Microsoft\WinGet\Links\pdftotext.exe"
)
foreach ($c in $popplerCandidates) {
    if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path -LiteralPath $c -PathType Leaf)) {
        $ppPath = $c
        break
    }
}

$config = [ordered]@{
    version         = "1.0"
    ghostscriptPath = $gsPath
    popplerPath     = $ppPath
    logLevel        = "INFO"
    installDir      = $InstallDir
    dataDir         = $DataDir
    deploymentMode  = "installed"
}

$config | ConvertTo-Json -Depth 2 | Set-Content -Path $cfgPath -Encoding UTF8

# -- 3. Copier templates.json si premier install --
$tplSrc = Join-Path $InstallDir 'Data\templates.json'
$tplDst = Join-Path $DataDir 'Data\templates.json'
if ((Test-Path -LiteralPath $tplSrc -PathType Leaf) -and -not (Test-Path -LiteralPath $tplDst -PathType Leaf)) {
    Copy-Item -LiteralPath $tplSrc -Destination $tplDst -Force
}

# -- 4. Positionner variable machine CN_DATA_ROOT --
try {
    [Environment]::SetEnvironmentVariable('CN_DATA_ROOT', $DataDir, 'Machine')
} catch {
    # Pas critique si echoue (l'app utilise aussi la detection ProgramData)
}

exit 0

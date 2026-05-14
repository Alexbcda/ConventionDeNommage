<#
.SYNOPSIS
    Script d'installation et de validation des dependances pour Convention de Nommage.
.DESCRIPTION
    Verifie la structure du projet, les outils externes (Ghostscript, Poppler),
    et genere la configuration runtime si absente.
    Ne telecharge rien automatiquement - signale les elements manquants.
.EXAMPLE
    powershell.exe -NoProfile -File install\Install.ps1
#>
[CmdletBinding()]
param(
    [switch]$Silent
)

$ErrorActionPreference = 'Stop'
$script:installRoot = Split-Path -Parent $PSScriptRoot
$script:errors = @()
$script:warnings = @()

function Write-Status {
    param([string]$Message, [string]$Status = 'INFO')
    $color = switch ($Status) {
        'OK'    { 'Green' }
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
        default { 'Cyan' }
    }
    if (-not $Silent) {
        Write-Host "[$Status] $Message" -ForegroundColor $color
    }
}

Write-Status "Convention de Nommage - Installation / Validation" "INFO"
Write-Status ("Racine projet : {0}" -f $script:installRoot) "INFO"
Write-Status ("-" * 60) "INFO"

# -- 1. Structure des repertoires --
Write-Status "Verification de la structure du projet..." "INFO"
$requiredDirs = @('src', 'config', 'runtime', 'runtime\ghostscript', 'runtime\poppler', 'Logs', 'Data', 'lib')
foreach ($dir in $requiredDirs) {
    $fullPath = Join-Path $script:installRoot $dir
    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        $null = New-Item -Path $fullPath -ItemType Directory -Force
        Write-Status "Repertoire cree : $dir" "OK"
    }
    else {
        Write-Status "Repertoire OK : $dir" "OK"
    }
}

# -- 2. Configuration runtime.json --
Write-Status "Verification de la configuration..." "INFO"
$cfgPath = Join-Path $script:installRoot 'config\runtime.json'
if (-not (Test-Path -LiteralPath $cfgPath -PathType Leaf)) {
    $defaultCfg = @{
        version        = "1.0"
        ghostscriptPath = ""
        popplerPath    = ""
        logLevel       = "INFO"
    }
    $defaultCfg | ConvertTo-Json -Depth 2 | Set-Content -Path $cfgPath -Encoding UTF8
    Write-Status "config/runtime.json genere avec valeurs par defaut" "OK"
}
else {
    try {
        $cfg = Get-Content -LiteralPath $cfgPath -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($null -eq $cfg.version) {
            $script:warnings += "config/runtime.json : champ 'version' manquant"
            Write-Status "config/runtime.json : champ 'version' manquant" "WARN"
        }
        else {
            Write-Status "config/runtime.json OK (v$($cfg.version))" "OK"
        }
    }
    catch {
        $script:errors += "config/runtime.json invalide : $($_.Exception.Message)"
        Write-Status "config/runtime.json invalide" "ERROR"
    }
}

# -- 3. SQLite driver --
Write-Status "Verification du driver SQLite..." "INFO"
$sqliteDll = Join-Path $script:installRoot 'lib\System.Data.SQLite.dll'
if (Test-Path -LiteralPath $sqliteDll -PathType Leaf) {
    Write-Status "System.Data.SQLite.dll present" "OK"
}
else {
    $script:errors += "lib/System.Data.SQLite.dll manquant - requis pour le fonctionnement de la base de donnees"
    Write-Status "System.Data.SQLite.dll MANQUANT dans lib/" "ERROR"
}

# -- 4. Ghostscript --
Write-Status "Verification de Ghostscript..." "INFO"
$gsFound = $false

$cfgGs = $null
if (Test-Path -LiteralPath $cfgPath -PathType Leaf) {
    try {
        $cfgGs = (Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json).ghostscriptPath
    } catch {}
}

if (-not [string]::IsNullOrWhiteSpace($cfgGs) -and (Test-Path -LiteralPath $cfgGs -PathType Leaf)) {
    Write-Status ("Ghostscript configure : {0}" -f $cfgGs) "OK"
    $gsFound = $true
}

if (-not $gsFound) {
    foreach ($exe in @('gswin64c.exe', 'gswin32c.exe')) {
        $rtPath = Join-Path $script:installRoot "runtime\ghostscript\bin\$exe"
        if (Test-Path -LiteralPath $rtPath -PathType Leaf) {
            Write-Status ("Ghostscript dans runtime/ : {0}" -f $rtPath) "OK"
            $gsFound = $true
            break
        }
    }
}

if (-not $gsFound) {
    foreach ($exe in @('gswin64c.exe', 'gswin32c.exe')) {
        $cmd = Get-Command $exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $cmd -and -not [string]::IsNullOrWhiteSpace($cmd.Source)) {
            Write-Status ("Ghostscript dans PATH : {0}" -f $cmd.Source) "OK"
            $gsFound = $true
            break
        }
    }
}

if (-not $gsFound) {
    $pfCandidates = @(
        "${env:ProgramFiles}\gs",
        "${env:ProgramFiles}\PDF24\gs",
        "${env:ProgramFiles(x86)}\PDF24\gs",
        "${env:ProgramFiles}\Ghostscript"
    )
    foreach ($pfDir in $pfCandidates) {
        if ([string]::IsNullOrWhiteSpace($pfDir) -or -not (Test-Path -LiteralPath $pfDir -PathType Container)) { continue }
        $found = Get-ChildItem -LiteralPath $pfDir -Recurse -Filter 'gswin64c.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $found) {
            Write-Status ("Ghostscript detecte : {0}" -f $found.FullName) "OK"
            $gsFound = $true
            break
        }
    }
}

if (-not $gsFound) {
    $script:warnings += "Ghostscript non detecte - necessaire pour la fusion PDF"
    Write-Status "Ghostscript NON DETECTE" "WARN"
    Write-Status "  -> Placez gswin64c.exe dans runtime\ghostscript\bin\" "INFO"
    Write-Status "  -> Ou renseignez ghostscriptPath dans config\runtime.json" "INFO"
}

# -- 5. Poppler (pdftotext) --
Write-Status "Verification de Poppler (pdftotext)..." "INFO"
$popplerFound = $false

$cfgPoppler = $null
if (Test-Path -LiteralPath $cfgPath -PathType Leaf) {
    try {
        $cfgPoppler = (Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json).popplerPath
    } catch {}
}

if (-not [string]::IsNullOrWhiteSpace($cfgPoppler)) {
    $pdfExe = $cfgPoppler
    if (Test-Path -LiteralPath $pdfExe -PathType Container) {
        $pdfExe = Join-Path $pdfExe 'pdftotext.exe'
    }
    if (Test-Path -LiteralPath $pdfExe -PathType Leaf) {
        Write-Status ("pdftotext configure : {0}" -f $pdfExe) "OK"
        $popplerFound = $true
    }
}

if (-not $popplerFound) {
    $rtCandidates = @(
        (Join-Path $script:installRoot 'runtime\poppler\Library\bin\pdftotext.exe'),
        (Join-Path $script:installRoot 'runtime\poppler\bin\pdftotext.exe')
    )
    foreach ($rtPath in $rtCandidates) {
        if (Test-Path -LiteralPath $rtPath -PathType Leaf) {
            Write-Status ("pdftotext dans runtime/ : {0}" -f $rtPath) "OK"
            $popplerFound = $true
            break
        }
    }
}

if (-not $popplerFound) {
    $cmd = Get-Command 'pdftotext.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $cmd -and -not [string]::IsNullOrWhiteSpace($cmd.Source)) {
        Write-Status ("pdftotext dans PATH : {0}" -f $cmd.Source) "OK"
        $popplerFound = $true
    }
}

if (-not $popplerFound) {
    $script:warnings += "pdftotext (Poppler) non detecte - necessaire pour l'extraction PDF"
    Write-Status "pdftotext NON DETECTE" "WARN"
    Write-Status "  -> Placez pdftotext.exe dans runtime\poppler\bin\" "INFO"
    Write-Status "  -> Ou renseignez popplerPath dans config\runtime.json" "INFO"
}

# -- 6. Verification absence de chemins utilisateur hardcodes --
Write-Status "Verification portabilite (chemins hardcodes)..." "INFO"
$portabilityOk = $true
$ps1Files = Get-ChildItem -LiteralPath (Join-Path $script:installRoot 'src') -Recurse -Filter '*.ps1' -ErrorAction SilentlyContinue
foreach ($file in $ps1Files) {
    $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -match 'C:\\Users\\[^"'']+') {
        $script:errors += "Chemin utilisateur detecte dans $($file.Name)"
        Write-Status ("Chemin utilisateur hardcode dans : {0}" -f $file.FullName) "ERROR"
        $portabilityOk = $false
    }
}
if ($portabilityOk) {
    Write-Status "Aucun chemin utilisateur hardcode detecte" "OK"
}

# -- Rapport final --
Write-Status ("-" * 60) "INFO"
if ($script:errors.Count -gt 0) {
    Write-Status ("RESULTAT : {0} erreur(s), {1} avertissement(s)" -f $script:errors.Count, $script:warnings.Count) "ERROR"
    foreach ($e in $script:errors) { Write-Status "  ERREUR : $e" "ERROR" }
    foreach ($w in $script:warnings) { Write-Status "  AVERTISSEMENT : $w" "WARN" }
    exit 1
}
elseif ($script:warnings.Count -gt 0) {
    Write-Status ("RESULTAT : OK avec {0} avertissement(s)" -f $script:warnings.Count) "WARN"
    foreach ($w in $script:warnings) { Write-Status "  AVERTISSEMENT : $w" "WARN" }
    Write-Status "L'application peut fonctionner mais certaines fonctionnalites PDF seront desactivees." "WARN"
    exit 0
}
else {
    Write-Status "RESULTAT : Installation validee - pret pour le deploiement" "OK"
    exit 0
}

<#
.SYNOPSIS
    Test automatise de l'installation ConventionDeNommage (Phase 8).
.PARAMETER InstallDir
    Repertoire d'installation (defaut : Program Files).
.PARAMETER CentreId
    Identifiant du centre attendu (grenoble, lyon, etc.).
.PARAMETER CheckLaunch
    Tente un lancement bref de l'exe (optionnel, peut afficher une fenetre).
#>

param(
    [string]$InstallDir = "$env:ProgramFiles\ConventionDeNommage",
    [string]$CentreId = 'grenoble',
    [switch]$CheckLaunch
)

$ErrorActionPreference = 'Continue'
$script:TestPassed = 0
$script:TestFailed = 0

function Write-TestResult {
    param(
        [string]$Name,
        [bool]$Success,
        [string]$Message = '',
        [switch]$Optional
    )
    if ($Success) {
        $script:TestPassed++
        Write-Host "[OK] $Name" -ForegroundColor Green
        if ($Message) { Write-Host "     $Message" -ForegroundColor DarkGray }
    }
    elseif ($Optional) {
        Write-Host "[--] $Name (optionnel)" -ForegroundColor DarkYellow
        if ($Message) { Write-Host "     $Message" -ForegroundColor DarkGray }
    }
    else {
        $script:TestFailed++
        Write-Host "[ECHEC] $Name" -ForegroundColor Red
        if ($Message) { Write-Host "     $Message" -ForegroundColor Red }
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path -LiteralPath $InstallDir)) {
    $altDir = Join-Path $repoRoot 'output'
    if (Test-Path -LiteralPath $altDir) {
        Write-Host "InstallDir introuvable, utilisation de output\ pour test local" -ForegroundColor Yellow
        $InstallDir = $altDir
    }
}

Write-Host '=== Test installation ConventionDeNommage ===' -ForegroundColor Cyan
Write-Host "Repertoire : $InstallDir"
Write-Host "Centre attendu : $CentreId"

Write-Host ''
Write-Host '--- Test 1 : Presence des fichiers ---' -ForegroundColor Yellow
$filesToCheck = @(
    'ConventionDeNommage.exe',
    'src\Main.ps1',
    'src\Database\Database.ps1',
    'src\Core\ConfigManager.ps1',
    'lib\System.Data.SQLite.dll',
    'config\centres.json',
    'Data\templates.json'
)
foreach ($file in $filesToCheck) {
    $path = Join-Path $InstallDir $file
    Write-TestResult -Name "Fichier $file" -Success (Test-Path -LiteralPath $path) -Message $path
}

$dbPath = Join-Path $InstallDir 'Data\gestion.db'
Write-TestResult -Name 'Base gestion.db' -Success (Test-Path -LiteralPath $dbPath) -Message $dbPath -Optional:(-not (Test-Path -LiteralPath $dbPath))

Write-Host ''
Write-Host '--- Test 2 : Configuration centre ---' -ForegroundColor Yellow
$dbScript = Join-Path $InstallDir 'src\Database\Database.ps1'
$configScript = Join-Path $InstallDir 'src\Core\ConfigManager.ps1'

if (Test-Path -LiteralPath $dbScript) {
    . $dbScript
    if (-not (Test-Path -LiteralPath $dbPath)) {
        $null = Initialize-Database
    }

    $url = Get-AppConfig -Key 'SharePointApiUrl'
    $centreIdDb = Get-AppConfig -Key 'CentreId'
    $centreName = Get-AppConfig -Key 'CentreName'

    Write-TestResult -Name 'URL SharePoint configuree' -Success (-not [string]::IsNullOrWhiteSpace($url))
    Write-TestResult -Name 'CentreId configure' -Success (-not [string]::IsNullOrWhiteSpace($centreIdDb))
    Write-TestResult -Name 'CentreName configure' -Success (-not [string]::IsNullOrWhiteSpace($centreName))
    Write-TestResult -Name "Centre attendu ($CentreId)" -Success ($centreIdDb -eq $CentreId) -Optional

    if (Test-Path -LiteralPath $configScript) {
        . $configScript
        $centres = Get-CentresList
        Write-TestResult -Name 'centres.json lisible' -Success ($centres.Count -gt 0) -Message ("{0} centre(s)" -f $centres.Count)
        $cfg = Get-CentreConfig -CentreId $CentreId
        Write-TestResult -Name "Config centre $CentreId" -Success ($null -ne $cfg)
    }
}
else {
    Write-TestResult -Name 'Database.ps1 accessible' -Success $false
}

Write-Host ''
Write-Host '--- Test 3 : Executable ---' -ForegroundColor Yellow
$exePath = Join-Path $InstallDir 'ConventionDeNommage.exe'
if (Test-Path -LiteralPath $exePath) {
    $exeInfo = Get-Item -LiteralPath $exePath
    Write-TestResult -Name 'Exe present' -Success $true -Message ("{0} octets" -f $exeInfo.Length)
    $hash = Get-FileHash -LiteralPath $exePath -Algorithm SHA256
    Write-Host "     SHA-256 : $($hash.Hash)" -ForegroundColor DarkGray
    $sig = Get-AuthenticodeSignature -LiteralPath $exePath
    Write-TestResult -Name 'Signature Authenticode' -Success ($sig.Status -eq 'Valid') -Message ("Statut: {0}" -f $sig.Status) -Optional
}
else {
    Write-TestResult -Name 'Exe present' -Success $false -Message 'Executer build.ps1 ou install.ps1'
}

Write-Host ''
Write-Host '--- Test 4 : Dependances PowerShell ---' -ForegroundColor Yellow
$modulesOptional = @(
    @{ Name = 'Microsoft.Graph.Authentication'; Required = $false },
    @{ Name = 'ImportExcel'; Required = $false }
)
foreach ($m in $modulesOptional) {
    $installed = Get-Module -ListAvailable $m.Name -ErrorAction SilentlyContinue | Select-Object -First 1
    Write-TestResult -Name ("Module {0}" -f $m.Name) -Success ($null -ne $installed) -Optional:(-not $m.Required)
}

Write-Host ''
Write-Host '--- Test 5 : Exclusions Defender ---' -ForegroundColor Yellow
if (Get-Command Get-MpPreference -ErrorAction SilentlyContinue) {
    $pref = Get-MpPreference -ErrorAction SilentlyContinue
    if ($pref) {
        $pathExcluded = $pref.ExclusionPath -contains $InstallDir
        $exeExcluded = $pref.ExclusionProcess -contains 'ConventionDeNommage.exe'
        Write-TestResult -Name 'Dossier installation exclu' -Success $pathExcluded -Optional
        Write-TestResult -Name 'Processus exclu' -Success $exeExcluded -Optional
    }
}
else {
    Write-TestResult -Name 'Defender accessible' -Success $false -Message 'Cmdlets indisponibles' -Optional
}

if ($CheckLaunch -and (Test-Path -LiteralPath $exePath)) {
    Write-Host ''
    Write-Host '--- Test 6 : Lancement application ---' -ForegroundColor Yellow
    try {
        $proc = Start-Process -FilePath $exePath -PassThru -WindowStyle Normal
        Start-Sleep -Seconds 4
        if (-not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            Write-TestResult -Name 'Application demarre' -Success $true
        }
        else {
            Write-TestResult -Name 'Application demarre' -Success $false -Message ("Exit code {0}" -f $proc.ExitCode)
        }
    }
    catch {
        Write-TestResult -Name 'Application demarre' -Success $false -Message $_.Exception.Message
    }
}

Write-Host ''
Write-Host '=== Resume des tests ===' -ForegroundColor Cyan
Write-Host "Reussis : $script:TestPassed"
Write-Host "Echecs  : $script:TestFailed"

if ($script:TestFailed -eq 0) {
    Write-Host ''
    Write-Host 'Installation validee.' -ForegroundColor Green
    exit 0
}

Write-Host ''
Write-Host 'Certains tests ont echoue. Verifiez l installation.' -ForegroundColor Yellow
exit 1

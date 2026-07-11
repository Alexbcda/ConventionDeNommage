# antivirus_exclusions.ps1 - Exclusions antivirus pour ASSISTANT (Elise Alpes)
# Executer en tant qu'administrateur AVANT installation ou build package :
#   .\config\antivirus_exclusions.ps1 -InstallDir "C:\ASSISTANT" -PackageDir "F:\package"

param(
    [string]$InstallDir = 'C:\ASSISTANT',
    [string]$PackageDir = '',
    [string]$BuildPackageDir = '',
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'

$localData = Join-Path $env:LOCALAPPDATA 'ASSISTANT'
$updateDir = Join-Path $localData 'Update'
$repoPackage = if ($BuildPackageDir) { $BuildPackageDir } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'package' }

function Write-AvMsg {
    param([string]$Message, [string]$Color = 'White')
    if (-not $Quiet) { Write-Host $Message -ForegroundColor $Color }
}

Write-AvMsg '=== Exclusions antivirus ASSISTANT ===' 'Cyan'
Write-AvMsg "Installation  : $InstallDir"
Write-AvMsg "Donnees       : $localData"
Write-AvMsg "Package build : $repoPackage"
if ($PackageDir) { Write-AvMsg "Package USB   : $PackageDir" }

$paths = @(
    $InstallDir,
    $localData,
    $updateDir,
    $repoPackage
)
if ($PackageDir) { $paths += $PackageDir }

# Windows Defender / Microsoft Defender
if (Get-Command Add-MpPreference -ErrorAction SilentlyContinue) {
    foreach ($p in $paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) {
        try {
            Add-MpPreference -ExclusionPath $p -ErrorAction Stop
            Write-AvMsg "[OK] Exclusion chemin : $p" 'Green'
        }
        catch {
            Write-AvMsg "[WARN] Chemin non ajoute ($p) : $($_.Exception.Message)" 'Yellow'
        }
    }
    foreach ($proc in @('powershell.exe', 'pwsh.exe')) {
        try {
            Add-MpPreference -ExclusionProcess $proc -ErrorAction SilentlyContinue
            Write-AvMsg "[OK] Exclusion processus : $proc" 'Green'
        }
        catch { }
    }
}
else {
    Write-AvMsg '[WARN] Add-MpPreference indisponible (admin requis ou Defender remplace par un autre AV)' 'Yellow'
}

# Bitdefender detecte
$bd = Get-Process -Name 'bdagent', 'bdredline', 'bdservicehost', 'bdntwrk' -ErrorAction SilentlyContinue
if ($bd) {
    Write-AvMsg '' 
    Write-AvMsg '[IMPORTANT] Bitdefender detecte sur ce poste' 'Yellow'
    Write-AvMsg 'Ajoutez les exclusions MANUELLEMENT (console admin ou poste utilisateur) :' 'Yellow'
    Write-AvMsg '  Bitdefender > Protection > Antivirus > Parametres avances > Exclusions' 'White'
    foreach ($p in $paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) {
        Write-AvMsg "    - Dossier : $p" 'White'
    }
    Write-AvMsg '  Processus recommandes : powershell.exe' 'White'
    Write-AvMsg '  Faux positif : https://www.bitdefender.com/submit/' 'DarkGray'
    Write-AvMsg '' 
    Write-AvMsg 'Fichiers frequemment mis en quarantaine par Bitdefender :' 'Yellow'
    Write-AvMsg '  - lib\SQLite.Interop.dll, lib\System.Data.SQLite.dll (DLL natives / P/Invoke)' 'Gray'
    Write-AvMsg '  - runtime\ImportExcel\EPPlus.dll et autres DLL du module ImportExcel' 'Gray'
    Write-AvMsg '  - src\ODM\PdfPlanningOptimizer\Extractors\PdfTextNormalizer.ps1 (renomme CnsPdf*.ps1 si besoin)' 'Gray'
    Write-AvMsg '  - Scripts .ps1 massifs lors du build package (UTF-8 BOM)' 'Gray'
    Write-AvMsg '  - ASSISTANT.bat, install_assistant.ps1 (lanceurs)' 'Gray'
}

Write-AvMsg ''
Write-AvMsg 'Apres exclusion : restaurer la quarantaine puis reinstaller ou relancer build_package.ps1 -Clean' 'Cyan'
Write-AvMsg 'Audit : .\Tools\Audit-AntivirusBlockedFiles.ps1' 'Cyan'
Write-AvMsg 'Termine.' 'Green'

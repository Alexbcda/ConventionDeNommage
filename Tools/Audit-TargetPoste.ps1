#Requires -Version 5.1
<#
.SYNOPSIS
    Audit complet des dependances ASSISTANT sur un poste cible.
.EXAMPLE
    pwsh -File Tools\Audit-TargetPoste.ps1 -InstallDir C:\ASSISTANT
#>
param(
    [string]$InstallDir = '',
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'

function Resolve-AssistantInstallDir {
    param([string]$Preferred)
    if (-not [string]::IsNullOrWhiteSpace($Preferred) -and (Test-Path (Join-Path $Preferred 'src\Main.ps1'))) {
        return (Resolve-Path -LiteralPath $Preferred).Path
    }
    foreach ($c in @($env:ASSISTANT_HOME, 'C:\ASSISTANT', (Join-Path $env:LOCALAPPDATA 'ASSISTANT'))) {
        if ([string]::IsNullOrWhiteSpace($c)) { continue }
        if (Test-Path -LiteralPath (Join-Path $c 'src\Main.ps1')) {
            return (Resolve-Path -LiteralPath $c).Path
        }
    }
    return $Preferred
}

function Write-AuditLine {
    param([string]$Text, [string]$Level = 'Info')
    if ($Quiet -and $Level -eq 'Info') { return }
    $color = switch ($Level) {
        'OK' { 'Green' }
        'Warn' { 'Yellow' }
        'Error' { 'Red' }
        'Title' { 'Cyan' }
        default { 'Gray' }
    }
    Write-Host $Text -ForegroundColor $color
}

function Test-BundledGraph {
    param([string]$Root)
    $flat = Join-Path $Root 'runtime\Graph\Microsoft.Graph.Authentication\Microsoft.Graph.Authentication.psd1'
    if (Test-Path -LiteralPath $flat) { return $true }
    $authDir = Join-Path $Root 'runtime\Graph\Microsoft.Graph.Authentication'
    return $null -ne (Get-ChildItem -LiteralPath $authDir -Recurse -Filter 'Microsoft.Graph.Authentication.psd1' -File -EA SilentlyContinue | Select-Object -First 1)
}

function Test-BundledImportExcel {
    param([string]$Root)
    Test-Path -LiteralPath (Join-Path $Root 'runtime\ImportExcel\ImportExcel.psd1')
}

$installDir = Resolve-AssistantInstallDir -Preferred $InstallDir
$results = @{ OK = [System.Collections.Generic.List[string]]::new(); Warn = [System.Collections.Generic.List[string]]::new(); Error = [System.Collections.Generic.List[string]]::new() }

function Add-Result {
    param([string]$Bucket, [string]$Message)
    $null = $results[$Bucket].Add($Message)
}

Write-AuditLine '========================================' 'Title'
Write-AuditLine '   AUDIT DEPENDANCES - POSTE CIBLE ASSISTANT' 'Title'
Write-AuditLine "   $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" 'Title'
Write-AuditLine "   InstallDir : $installDir" 'Title'
Write-AuditLine '========================================' 'Title'
Write-Host ''

# --- 1. SYSTEME ---
Write-AuditLine '1. PRE-REQUIS SYSTEME' 'Title'
$os = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
if ($os) {
    Write-AuditLine "  OS : $($os.Caption) $($os.OSArchitecture)"
    Write-AuditLine "  Build : $($os.Version)"
    if ($os.OSArchitecture -notmatch '64') {
        Add-Result Error 'Windows 64 bits requis'
        Write-AuditLine '  Windows 64 bits requis' 'Error'
    }
    else {
        Add-Result OK 'Windows 64 bits'
        Write-AuditLine '  Windows 64 bits : OK' 'OK'
    }
}

$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (Test-Path -LiteralPath $ps51) {
    Add-Result OK 'Windows PowerShell 5.1 present'
    Write-AuditLine '  Windows PowerShell 5.1 : OK (utilise par ASSISTANT.bat)' 'OK'
}
else {
    Add-Result Error 'Windows PowerShell 5.1 absent'
    Write-AuditLine '  Windows PowerShell 5.1 : MANQUANT' 'Error'
}
Write-AuditLine "  Session actuelle : $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))"

try {
    $ndp = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -EA Stop
    $release = [int]$ndp.Release
    $dotnetLabel = switch ($release) {
        { $_ -ge 533320 } { '4.8.1+' }
        { $_ -ge 528040 } { '4.8' }
        { $_ -ge 461808 } { '4.7.2' }
        default { "Release $release" }
    }
    Write-AuditLine "  .NET Framework : $dotnetLabel (release $release)"
    if ($release -ge 528040) { Add-Result OK ".NET Framework $dotnetLabel"; Write-AuditLine '  .NET 4.8+ : OK' 'OK' }
    else { Add-Result Warn ".NET Framework $dotnetLabel (< 4.8)"; Write-AuditLine '  .NET 4.8+ recommande' 'Warn' }
}
catch {
    Add-Result Warn '.NET Framework non detecte'
    Write-AuditLine '  .NET Framework : non detecte' 'Warn'
}

$cs = Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue
if ($cs) {
    $ramGb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    Write-AuditLine "  RAM : $ramGb GB"
    if ($ramGb -lt 4) { Add-Result Warn "RAM $ramGb GB (< 4 GB recommandes)" }
    else { Add-Result OK "RAM $ramGb GB" }
}
Write-Host ''

# --- 2. DISQUE ---
Write-AuditLine '2. ESPACE DISQUE' 'Title'
$drive = Get-PSDrive -Name C -EA SilentlyContinue
if ($drive) {
    $freeGb = [math]::Round($drive.Free / 1GB, 2)
    Write-AuditLine "  Libre C: : $freeGb GB"
    if ($freeGb -lt 2) { Add-Result Error "Espace < 2 GB ($freeGb GB)"; Write-AuditLine '  Espace critique' 'Error' }
    elseif ($freeGb -lt 5) { Add-Result Warn "Espace < 5 GB ($freeGb GB)"; Write-AuditLine '  Espace faible' 'Warn' }
    else { Add-Result OK "Espace $freeGb GB"; Write-AuditLine '  Espace OK' 'OK' }
}
Write-Host ''

# --- 3. EXECUTION POLICY ---
Write-AuditLine '3. EXECUTION POLICY' 'Title'
$pol = Get-ExecutionPolicy -Scope CurrentUser
Write-AuditLine "  CurrentUser : $pol"
if ($pol -eq 'Restricted') {
    Add-Result Error "ExecutionPolicy $pol"
    Write-AuditLine '  Restricted — Set-ExecutionPolicy RemoteSigned -Scope CurrentUser' 'Error'
}
else {
    Add-Result OK "ExecutionPolicy $pol"
    Write-AuditLine '  OK (ASSISTANT.bat utilise -ExecutionPolicy Bypass)' 'OK'
}
Write-Host ''

# --- 4. PSMODULEPATH ---
Write-AuditLine '4. PSMODULEPATH' 'Title'
$unc = @($env:PSModulePath -split ';' | Where-Object { $_ -match '^\\\\' })
if ($unc.Count -gt 0) {
    Add-Result Warn "$($unc.Count) chemin(s) UNC"
    foreach ($u in $unc) { Write-AuditLine "  UNC : $u" 'Warn' }
}
else {
    Add-Result OK 'Aucun chemin UNC'
    Write-AuditLine '  Aucun chemin UNC' 'OK'
}
Write-Host ''

# --- 5. PACKAGE EMBARQUE ---
Write-AuditLine '5. DEPENDANCES EMBARQUEES (package)' 'Title'
$embedded = @(
    @{ Label = 'ASSISTANT.bat'; Path = 'ASSISTANT.bat' }
    @{ Label = 'Main.ps1'; Path = 'src\Main.ps1' }
    @{ Label = 'Styles.ps1 (System.Drawing)'; Path = 'src\Common\Styles.ps1' }
    @{ Label = 'Ghostscript'; Path = 'runtime\ghostscript\gswin64c.exe' }
    @{ Label = 'Poppler pdftotext'; Path = 'runtime\poppler\pdftotext.exe'; Alt = 'runtime\poppler' }
    @{ Label = 'ImportExcel bundle'; Path = 'runtime\ImportExcel\ImportExcel.psd1' }
    @{ Label = 'Graph bundle'; Path = 'runtime\Graph\Microsoft.Graph.Authentication\Microsoft.Graph.Authentication.psd1'; Custom = 'Graph' }
    @{ Label = 'qpdf'; Path = 'lib\qpdf\bin\qpdf.exe'; Alt = 'lib\qpdf' }
    @{ Label = 'SQLite DLL'; Path = 'lib\System.Data.SQLite.dll' }
    @{ Label = 'SQLite.Interop'; Path = 'lib\SQLite.Interop.dll' }
    @{ Label = 'Template Certificat'; Path = 'templates\CertificatDeDestruction.xlsx' }
    @{ Label = 'Template Bilan'; Path = 'templates\BilanDeCollecte.xlsx' }
    @{ Label = 'Template CEA'; Path = 'templates\CeaPointsDeCollectes.xlsx' }
    @{ Label = 'version.txt'; Path = 'version.txt' }
)

foreach ($item in $embedded) {
    $full = Join-Path $installDir $item.Path
    $ok = $false
    if ($item.Custom -eq 'Graph') { $ok = Test-BundledGraph -Root $installDir }
    elseif (Test-Path -LiteralPath $full) { $ok = $true }
    elseif ($item.Alt) {
        $altPath = Join-Path $installDir $item.Alt
        if ($item.Label -match 'pdftotext|qpdf') {
            $ok = $null -ne (Get-ChildItem -LiteralPath $altPath -Recurse -Filter (Split-Path $item.Path -Leaf) -File -EA SilentlyContinue | Select-Object -First 1)
        }
    }
    if ($ok) {
        Add-Result OK $item.Label
        Write-AuditLine "  OK  $($item.Label)" 'OK'
    }
    else {
        Add-Result Error "$($item.Label) manquant"
        Write-AuditLine "  MANQUANT  $($item.Label)" 'Error'
    }
}
Write-Host ''

# --- 6. MODULES EXTERNES (secours) ---
Write-AuditLine '6. MODULES POWERSHELL (systeme ou secours)' 'Title'
$ieBundle = Test-BundledImportExcel -Root $installDir
$graphBundle = Test-BundledGraph -Root $installDir

$ieMod = Get-Module ImportExcel -ListAvailable -EA SilentlyContinue | Select-Object -First 1
if ($ieBundle) { Add-Result OK 'ImportExcel via bundle'; Write-AuditLine '  ImportExcel : bundle OK' 'OK' }
elseif ($ieMod) { Add-Result OK "ImportExcel systeme $($ieMod.Version)"; Write-AuditLine "  ImportExcel : systeme $($ieMod.Version)" 'OK' }
else { Add-Result Error 'ImportExcel absent'; Write-AuditLine '  ImportExcel : MANQUANT' 'Error' }

$graphMod = Get-Module Microsoft.Graph.Authentication -ListAvailable -EA SilentlyContinue | Select-Object -First 1
if ($graphBundle) { Add-Result OK 'Microsoft.Graph via bundle'; Write-AuditLine '  Microsoft.Graph : bundle OK' 'OK' }
elseif ($graphMod) { Add-Result OK "Microsoft.Graph systeme $($graphMod.Version)"; Write-AuditLine "  Microsoft.Graph : systeme $($graphMod.Version)" 'OK' }
else { Add-Result Error 'Microsoft.Graph absent'; Write-AuditLine '  Microsoft.Graph : MANQUANT (SharePoint KO)' 'Error' }
Write-Host ''

# --- 7. LIBREOFFICE (externe, templates) ---
Write-AuditLine '7. LIBREOFFICE (externe — templates PDF)' 'Title'
$loPaths = @(
    $env:CN_LIBREOFFICE_SOFFICE,
    'C:\Program Files\LibreOffice\program\soffice.exe',
    'C:\Program Files (x86)\LibreOffice\program\soffice.exe'
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$loFound = $null
foreach ($p in $loPaths) {
    if (Test-Path -LiteralPath $p) { $loFound = $p; break }
}
if ($loFound) {
    Add-Result OK 'LibreOffice installe'
    Write-AuditLine "  OK  $loFound" 'OK'
}
else {
    Add-Result Error 'LibreOffice absent (certificats/bilans/CEA KO)'
    Write-AuditLine '  MANQUANT — requis pour Certificat, Bilan, CEA' 'Error'
    Write-AuditLine '  Installer LibreOffice ou definir CN_LIBREOFFICE_SOFFICE' 'Warn'
}
Write-Host ''

# --- 8. MICROSOFT EXCEL (optionnel) ---
Write-AuditLine '8. MICROSOFT EXCEL (optionnel)' 'Title'
$excel = $null
foreach ($reg in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\excel.exe',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\excel.exe'
    )) {
    try {
        $item = Get-ItemProperty -LiteralPath $reg -EA Stop
        $exe = [string]$item.'(default)'
        if ($exe -and (Test-Path -LiteralPath $exe.Trim('"'))) { $excel = $exe; break }
    }
    catch { }
}
if ($excel) { Write-AuditLine "  Present : $excel" 'OK' }
else { Write-AuditLine '  Absent (fallback LibreOffice ou ImportExcel seul)' 'Warn' }
Write-Host ''

# --- 9. ANTIVIRUS ---
Write-AuditLine '9. ANTIVIRUS' 'Title'
try {
    $def = Get-MpPreference -EA Stop
    $excl = @($def.ExclusionPath) | Where-Object { $_ -and $installDir -like "$_*" }
    if ($excl.Count -gt 0) {
        Add-Result OK 'Exclusion Defender'
        Write-AuditLine "  OK  $installDir exclu" 'OK'
    }
    else {
        Add-Result Warn "$installDir non exclu Defender"
        Write-AuditLine "  NON exclu — Add-MpPreference -ExclusionPath '$installDir'" 'Warn'
    }
}
catch {
    Add-Result Warn 'Defender non verifiable'
    Write-AuditLine '  Defender non verifiable (autre AV ?)' 'Warn'
}
Write-Host ''

# --- 10. RESEAU ---
Write-AuditLine '10. RESEAU (SharePoint / Graph)' 'Title'
$endpoints = @('login.microsoftonline.com', 'graph.microsoft.com')
foreach ($endpoint in $endpoints) {
    try {
        $r = Test-NetConnection -ComputerName $endpoint -Port 443 -WarningAction SilentlyContinue -EA Stop
        if ($r.TcpTestSucceeded) {
            Write-AuditLine "  OK  ${endpoint}:443" 'OK'
            Add-Result OK "${endpoint}:443"
        }
        else {
            Write-AuditLine "  ECHEC  ${endpoint}:443" 'Error'
            Add-Result Error "${endpoint}:443 bloque"
        }
    }
    catch {
        Write-AuditLine "  ?  $endpoint (test impossible)" 'Warn'
    }
}
Write-Host ''

# --- 11. PERMISSIONS ---
Write-AuditLine '11. PERMISSIONS ECRITURE' 'Title'
$dataDir = Join-Path $installDir 'Data'
$testFile = Join-Path $dataDir '.write_test'
try {
    if (-not (Test-Path $dataDir)) { $null = New-Item -ItemType Directory -Path $dataDir -Force }
    'test' | Set-Content -LiteralPath $testFile -Force -EA Stop
    Remove-Item -LiteralPath $testFile -Force -EA SilentlyContinue
    Add-Result OK 'Ecriture Data\'
    Write-AuditLine '  OK  Ecriture Data\' 'OK'
}
catch {
    Add-Result Error 'Ecriture Data\ impossible'
    Write-AuditLine "  ECHEC ecriture Data\ : $($_.Exception.Message)" 'Error'
}
Write-Host ''

# --- 12. VERSION ---
if (Test-Path (Join-Path $installDir 'version.txt')) {
    $ver = (Get-Content (Join-Path $installDir 'version.txt') -Raw).Trim()
    Write-AuditLine "Version installee : $ver" 'Title'
}
Write-Host ''

# --- RESUME ---
Write-AuditLine '========================================' 'Title'
Write-AuditLine '   RESUME' 'Title'
Write-AuditLine '========================================' 'Title'
Write-AuditLine "OK      : $($results.OK.Count)" 'OK'
Write-AuditLine "WARNING : $($results.Warn.Count)" 'Warn'
Write-AuditLine "ERROR   : $($results.Error.Count)" 'Error'
Write-Host ''
if ($results.Error.Count -gt 0) {
    Write-AuditLine 'ERREURS BLOQUANTES :' 'Error'
    $results.Error | ForEach-Object { Write-AuditLine "  - $_" 'Error' }
    Write-Host ''
}
if ($results.Warn.Count -gt 0) {
    Write-AuditLine 'AVERTISSEMENTS :' 'Warn'
    $results.Warn | ForEach-Object { Write-AuditLine "  - $_" 'Warn' }
    Write-Host ''
}

$global:LASTEXITCODE = if ($results.Error.Count -gt 0) { 1 } else { 0 }

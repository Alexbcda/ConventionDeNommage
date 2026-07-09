# Audit triple du workflow clic droit PDF -> ASSISTANT
# Usage: .\Tools\Audit-RightClickWorkflow.ps1 [-InstallDir C:\ASSISTANT]

param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$InstallDir = 'C:\ASSISTANT'
)

$packageDir = Join-Path $RepoRoot 'package'
$fail = 0

function Write-AuditResult {
    param([bool]$Ok, [string]$Message)
    if ($Ok) {
        Write-Host "OK  $Message" -ForegroundColor Green
    }
    else {
        Write-Host "KO  $Message" -ForegroundColor Red
        $script:fail++
    }
}

Write-Host "=== AUDIT CODE SOURCE ===" -ForegroundColor Cyan
$installPs1 = Join-Path $RepoRoot 'install_assistant.ps1'
if (Test-Path -LiteralPath $installPs1) {
    $content = Get-Content -LiteralPath $installPs1 -Raw
    Write-AuditResult ($content -match "MenuLabel = 'Assistant'") 'install_assistant.ps1 : MenuLabel = Assistant'
    Write-AuditResult ($content -match "Set-ItemProperty.*Icon") 'install_assistant.ps1 : registre Icon'
    Write-AuditResult ($content -match "'ASSISTANT\.ico'") 'install_assistant.ps1 : ASSISTANT.ico dans itemsFromPackage'
    Write-AuditResult ($content -match 'Register-AssistantPdfContextMenu') 'install_assistant.ps1 : Register-AssistantPdfContextMenu'
}
else {
    Write-AuditResult $false "install_assistant.ps1 introuvable : $installPs1"
}

$batSource = Join-Path $RepoRoot 'ASSISTANT.bat'
if (Test-Path -LiteralPath $batSource) {
    $batContent = Get-Content -LiteralPath $batSource -Raw
    Write-AuditResult ($batContent -match 'set "ASSISTANT_PDF=%~1"') 'ASSISTANT.bat : set ASSISTANT_PDF=%~1'
    Write-AuditResult ($batContent -match 'LaunchAssistant\.ps1') 'ASSISTANT.bat : LaunchAssistant.ps1'
}
else {
    Write-AuditResult $false 'ASSISTANT.bat introuvable a la racine du depot'
}

$launcher = Join-Path $RepoRoot 'src\LaunchAssistant.ps1'
Write-AuditResult (Test-Path -LiteralPath $launcher) 'src\LaunchAssistant.ps1 present'

Write-Host "`n=== AUDIT DU PACKAGE ===" -ForegroundColor Cyan
Write-AuditResult (Test-Path -LiteralPath (Join-Path $packageDir 'ASSISTANT.ico')) 'package\ASSISTANT.ico'
Write-AuditResult (Test-Path -LiteralPath (Join-Path $packageDir 'ASSISTANT.bat')) 'package\ASSISTANT.bat'
Write-AuditResult (Test-Path -LiteralPath (Join-Path $packageDir 'install_assistant.ps1')) 'package\install_assistant.ps1'
Write-AuditResult (Test-Path -LiteralPath (Join-Path $packageDir 'src\LaunchAssistant.ps1')) 'package\src\LaunchAssistant.ps1'

$pkgBat = Join-Path $packageDir 'ASSISTANT.bat'
if (Test-Path -LiteralPath $pkgBat) {
    $pkgBatContent = Get-Content -LiteralPath $pkgBat -Raw
    Write-AuditResult ($pkgBatContent -match 'set "ASSISTANT_PDF=%~1"') 'package\ASSISTANT.bat : ASSISTANT_PDF'
}

Write-Host "`n=== AUDIT DE L'INSTALLATION ($InstallDir) ===" -ForegroundColor Cyan
Write-AuditResult (Test-Path -LiteralPath (Join-Path $InstallDir 'ASSISTANT.ico')) "$InstallDir\ASSISTANT.ico"
Write-AuditResult (Test-Path -LiteralPath (Join-Path $InstallDir 'ASSISTANT.bat')) "$InstallDir\ASSISTANT.bat"
Write-AuditResult (Test-Path -LiteralPath (Join-Path $InstallDir 'src\Main.ps1')) "$InstallDir\src\Main.ps1"
Write-AuditResult (Test-Path -LiteralPath (Join-Path $InstallDir 'src\LaunchAssistant.ps1')) "$InstallDir\src\LaunchAssistant.ps1"

$instBat = Join-Path $InstallDir 'ASSISTANT.bat'
if (Test-Path -LiteralPath $instBat) {
    $instBatContent = Get-Content -LiteralPath $instBat -Raw
    Write-AuditResult ($instBatContent -match 'set "ASSISTANT_PDF=%~1"') 'installation ASSISTANT.bat : ASSISTANT_PDF'
}

$regPath = 'HKCU:\Software\Classes\SystemFileAssociations\.pdf\shell\ASSISTANT'
try {
    $reg = Get-ItemProperty -LiteralPath $regPath -ErrorAction Stop
    Write-AuditResult ($reg.'(default)' -eq 'Assistant') "Registre : (Default) = '$($reg.'(default)')' (attendu Assistant)"
    Write-AuditResult ($reg.Icon -like '*ASSISTANT.ico*') "Registre : Icon = '$($reg.Icon)'"
    $cmdReg = Get-ItemProperty -LiteralPath (Join-Path $regPath 'command') -ErrorAction Stop
    Write-AuditResult ($cmdReg.'(default)' -like '*cmd.exe*') "Registre : via cmd.exe"
    Write-AuditResult ($cmdReg.'(default)' -like '*ASSISTANT.bat*"%1"*') "Registre : commande = $($cmdReg.'(default)')"
}
catch {
    Write-AuditResult $false 'Cle registre HKCU\...\pdf\shell\ASSISTANT absente'
}

Write-Host "`n=== AUTRES ENTREES PDF SHELL ===" -ForegroundColor Cyan
$shellRoot = 'HKCU:\Software\Classes\SystemFileAssociations\.pdf\shell'
if (Test-Path -LiteralPath $shellRoot) {
    Get-ChildItem -LiteralPath $shellRoot | ForEach-Object {
        $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
        $label = $props.'(default)'
        if ($label -match 'ASSISTANT|Assistant') {
            Write-Host "  $($_.PSChildName) -> label='$label' icon='$($props.Icon)'" -ForegroundColor Yellow
        }
    }
}
else {
    Write-Host '  (aucune cle shell PDF sous HKCU)' -ForegroundColor DarkGray
}

Write-Host "`n=== RESULTAT ===" -ForegroundColor Cyan
if ($fail -eq 0) {
    Write-Host "Tous les controles sont OK ($fail echec)." -ForegroundColor Green
    exit 0
}
Write-Host "$fail controle(s) en echec." -ForegroundColor Red
exit 1

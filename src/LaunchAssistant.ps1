# LaunchAssistant.ps1 - point d'entree depuis Launcher.vbs / ASSISTANT.bat (raccourci + clic droit PDF)
# Lit le chemin PDF via la variable d'environnement ASSISTANT_PDF (chemins avec espaces supportes).
# La console est masquee par le lanceur (VBS Run 0 / powershell -WindowStyle Hidden).

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$script:AssistantLauncherDiag = ($env:ASSISTANT_DIAG -eq '1')

function Write-AssistantLauncherDiag {
    param([string]$Message)
    if (-not $script:AssistantLauncherDiag) { return }
    Write-Host $Message
}

$scriptDir = $PSScriptRoot
$logDir = Join-Path $scriptDir 'Logs'
$logFile = Join-Path $logDir 'launcher.log'

function Write-AssistantLauncherLog {
    param([string]$Message, [string]$Level = 'INFO')
    try {
        if (-not (Test-Path -LiteralPath $logDir)) {
            $null = New-Item -ItemType Directory -Path $logDir -Force
        }
        Add-Content -LiteralPath $logFile -Value ('[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message) -Encoding UTF8
    }
    catch { }
}

function Show-AssistantLauncherError {
    param([string]$Message)
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [System.Windows.Forms.MessageBox]::Show(
            ("ASSISTANT n'a pas pu demarrer :`n`n{0}`n`nConsultez src\Logs\launcher.log" -f $Message),
            'ASSISTANT - Erreur',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    catch {
        Write-Host $Message -ForegroundColor Red
    }
}

try {
    try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop }
    catch { try { Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop } catch { } }

    $pdfPath = $null
    if (-not [string]::IsNullOrWhiteSpace($env:ASSISTANT_PDF)) {
        $pdfPath = [string]$env:ASSISTANT_PDF.Trim().Trim('"')
        Remove-Item Env:ASSISTANT_PDF -ErrorAction SilentlyContinue
    }
    if ([string]::IsNullOrWhiteSpace($pdfPath) -and $RemainingArgs -and $RemainingArgs.Count -gt 0) {
        $pdfPath = [string]$RemainingArgs[0].Trim().Trim('"')
    }

    $pdfLabel = if ($pdfPath) { $pdfPath } else { '(aucun)' }
    Write-AssistantLauncherLog ("Demarrage - pdf={0}" -f $pdfLabel)
    Write-AssistantLauncherDiag ("Fichier transmis a PowerShell : {0}" -f $pdfLabel)

    $mainScript = Join-Path $scriptDir 'Main.ps1'
    if (-not (Test-Path -LiteralPath $mainScript)) {
        throw "Main.ps1 introuvable : $mainScript"
    }

    if (-not [string]::IsNullOrWhiteSpace($pdfPath)) {
        if (-not (Test-Path -LiteralPath $pdfPath -PathType Leaf)) {
            Write-AssistantLauncherLog ("PDF introuvable : {0}" -f $pdfPath) 'WARN'
            Write-AssistantLauncherDiag ("[ERREUR] Le fichier n'existe pas pour PowerShell : {0}" -f $pdfPath)
            & $mainScript
            exit $LASTEXITCODE
        }
        Write-AssistantLauncherDiag '[OK] Le fichier existe pour PowerShell'
        try {
            $pdfPath = (Resolve-Path -LiteralPath $pdfPath -ErrorAction Stop).Path
        }
        catch { }
        Write-AssistantLauncherLog ("PDF transmis : {0}" -f $pdfPath)
        & $mainScript $pdfPath
        exit $LASTEXITCODE
    }

    Write-AssistantLauncherLog 'Demarrage sans PDF'
    & $mainScript
    exit $LASTEXITCODE
}
catch {
    Write-AssistantLauncherLog ("ERREUR : {0}" -f $_.Exception.Message) 'ERROR'
    Write-AssistantLauncherDiag ("[ERREUR] {0}" -f $_.Exception.Message)
    if ($_.ScriptStackTrace) {
        Write-AssistantLauncherDiag $_.ScriptStackTrace
    }
    Show-AssistantLauncherError $_.Exception.Message
    exit 1
}

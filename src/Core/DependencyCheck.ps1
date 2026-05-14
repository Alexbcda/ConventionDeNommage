# DependencyCheck.ps1 - Validation des dependances externes au demarrage.
# Appelee depuis Main.ps1 apres le chargement du Logger.
# Ne bloque PAS le demarrage : les outils PDF sont optionnels pour le CRUD.

function Test-RuntimeDependencies {
    <#
    .SYNOPSIS
        Verifie la disponibilite des outils externes (Ghostscript, Poppler, SQLite).
        Positionne des flags globaux et log les resultats.
    .OUTPUTS
        Hashtable avec les cles : ghostscript, poppler, sqlite (bool chacune).
    #>
    [CmdletBinding()]
    param()

    $installRoot = if (-not [string]::IsNullOrWhiteSpace($global:CN_InstallRoot)) {
        $global:CN_InstallRoot
    } else {
        $r = $PSScriptRoot; for ($i = 0; $i -lt 2; $i++) { $r = Split-Path -Parent $r }; $r
    }
    $dataRoot = if (-not [string]::IsNullOrWhiteSpace($global:CN_DataRoot)) {
        $global:CN_DataRoot
    } else {
        $installRoot
    }

    $cfgPath = Join-Path $dataRoot 'config\runtime.json'
    $cfg = $null
    if (Test-Path -LiteralPath $cfgPath -PathType Leaf) {
        try { $cfg = Get-Content -LiteralPath $cfgPath -Raw -ErrorAction Stop | ConvertFrom-Json } catch {}
    }

    $result = @{ ghostscript = $false; poppler = $false; sqlite = $false }

    # ── SQLite ──
    $sqliteDll = Join-Path $installRoot 'lib\System.Data.SQLite.dll'
    if (Test-Path -LiteralPath $sqliteDll -PathType Leaf) {
        $result.sqlite = $true
    }
    else {
        Write-Log "[STARTUP] System.Data.SQLite.dll manquant dans lib/ - base de donnees indisponible" "ERROR"
    }

    # ── Ghostscript ──
    $gsPath = $null
    if ($null -ne $cfg -and -not [string]::IsNullOrWhiteSpace($cfg.ghostscriptPath)) {
        $candidate = [string]$cfg.ghostscriptPath
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $gsPath = $candidate }
    }
    if ($null -eq $gsPath) {
        foreach ($exe in @('gswin64c.exe', 'gswin32c.exe')) {
            $rtCandidate = Join-Path $installRoot "runtime\ghostscript\bin\$exe"
            if (Test-Path -LiteralPath $rtCandidate -PathType Leaf) { $gsPath = $rtCandidate; break }
        }
    }
    if ($null -eq $gsPath) {
        foreach ($exe in @('gswin64c.exe', 'gswin32c.exe')) {
            $cmd = Get-Command $exe -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $cmd -and -not [string]::IsNullOrWhiteSpace($cmd.Source)) { $gsPath = $cmd.Source; break }
        }
    }
    if ($null -ne $gsPath) {
        $result.ghostscript = $true
        Write-Log "[STARTUP] Ghostscript OK" "INFO" @{ path = $gsPath }
    }
    else {
        Write-Log "[STARTUP] Ghostscript non disponible - fusion PDF desactivee" "WARN"
    }

    # ── Poppler (pdftotext) ──
    $popplerPath = $null
    if ($null -ne $cfg -and -not [string]::IsNullOrWhiteSpace($cfg.popplerPath)) {
        $candidate = [string]$cfg.popplerPath
        if (Test-Path -LiteralPath $candidate -PathType Container) { $candidate = Join-Path $candidate 'pdftotext.exe' }
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $popplerPath = $candidate }
    }
    if ($null -eq $popplerPath) {
        $rtCandidates = @(
            (Join-Path $installRoot 'runtime\poppler\Library\bin\pdftotext.exe'),
            (Join-Path $installRoot 'runtime\poppler\bin\pdftotext.exe')
        )
        foreach ($rtPath in $rtCandidates) {
            if (Test-Path -LiteralPath $rtPath -PathType Leaf) { $popplerPath = $rtPath; break }
        }
    }
    if ($null -eq $popplerPath) {
        $cmd = Get-Command 'pdftotext.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $cmd -and -not [string]::IsNullOrWhiteSpace($cmd.Source)) { $popplerPath = $cmd.Source }
    }
    if ($null -ne $popplerPath) {
        $result.poppler = $true
        Write-Log "[STARTUP] Poppler (pdftotext) OK" "INFO" @{ path = $popplerPath }
    }
    else {
        Write-Log "[STARTUP] pdftotext non disponible - extraction PDF desactivee" "WARN"
    }

    $global:RuntimeDependencies = $result
    return $result
}

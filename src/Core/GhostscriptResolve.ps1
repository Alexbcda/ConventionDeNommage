# Partagé : résolution gswin64c / gswin32c hors PATH (installations Artifex, PDF24, etc.)

function Get-ResolvedGhostscriptPath {
    <#
    .SYNOPSIS
        Retourne le chemin complet d'un exécutable Ghostscript CLI, ou $null.
    .NOTES
        Ordre : config/runtime.json, runtime/ghostscript/, env vars, PATH, emplacements connus,
        puis le plus récent détecté sous Program Files\gs\*\bin\.
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

    $cfgFile = Join-Path $dataRoot 'config\runtime.json'
    if (Test-Path -LiteralPath $cfgFile -PathType Leaf) {
        try {
            $cfg = Get-Content -LiteralPath $cfgFile -Raw -ErrorAction Stop | ConvertFrom-Json
            $cfgGs = [string]$cfg.ghostscriptPath
            if (-not [string]::IsNullOrWhiteSpace($cfgGs)) {
                $cfgGs = $cfgGs.Trim().Trim('"')
                if (Test-Path -LiteralPath $cfgGs -PathType Leaf) {
                    return (Resolve-Path -LiteralPath $cfgGs).Path
                }
            }
        } catch { }
    }

    foreach ($exe in @('gswin64c.exe', 'gswin32c.exe')) {
        $rtCandidate = Join-Path $installRoot "runtime\ghostscript\bin\$exe"
        if (Test-Path -LiteralPath $rtCandidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $rtCandidate).Path
        }
    }

    foreach ($envName in @('GHOSTSCRIPT_EXE', 'GS_EXE', 'GS_PROG')) {
        $raw = [Environment]::GetEnvironmentVariable($envName, 'Process')
        if ([string]::IsNullOrWhiteSpace($raw)) { $raw = [Environment]::GetEnvironmentVariable($envName, 'User') }
        if ([string]::IsNullOrWhiteSpace($raw)) { $raw = [Environment]::GetEnvironmentVariable($envName, 'Machine') }
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        $candidate = $raw.Trim().Trim('"')
        if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and
            ((Split-Path -Leaf $candidate) -match '^(?i)gswin(64|32)c\.exe$')) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    foreach ($exe in @('gswin64c.exe', 'gswin32c.exe')) {
        $c = Get-Command $exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $c -and -not [string]::IsNullOrWhiteSpace($c.Source) -and (Test-Path -LiteralPath $c.Source)) {
            return [string]$c.Source
        }
    }

    $fixed = @(
        "${env:ProgramFiles}\PDF24\gs\bin\gswin64c.exe",
        "${env:ProgramFiles(x86)}\PDF24\gs\bin\gswin64c.exe",
        "${env:ProgramFiles}\gs\gs10.01.1\bin\gswin64c.exe",
        "${env:ProgramFiles}\gs\gs10.00.0\bin\gswin64c.exe",
        "${env:ProgramFiles}\gs\gs9.56.1\bin\gswin64c.exe",
        "${env:ProgramFiles}\gs\gs9.55.0\bin\gswin64c.exe",
        "${env:ProgramFiles}\Ghostscript\bin\gswin64c.exe",
        "${env:ProgramFiles}\Ghostscript\bin\gswin32c.exe"
    )
    foreach ($p in $fixed) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            return (Resolve-Path -LiteralPath $p).Path
        }
    }

    $gsRoot = Join-Path $env:ProgramFiles 'gs'
    if (-not (Test-Path -LiteralPath $gsRoot)) { return $null }

    $dirs = @(Get-ChildItem -LiteralPath $gsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $v = $null
        if ($_.Name -match '(\d+)\.(\d+)\.(\d+)') {
            try { $v = [version]"$($matches[1]).$($matches[2]).$($matches[3])" } catch { }
        }
        if ($null -eq $v) {
            if ($_.Name -match '(\d+)\.(\d+)') {
                try { $v = [version]"$($matches[1]).$($matches[2]).0" } catch { }
            }
        }
        [pscustomobject]@{ Dir = $_.FullName; Ver = $(if ($null -ne $v) { $v } else { [version]'0.0' }) }
    } | Sort-Object -Property Ver -Descending)

    foreach ($d in $dirs) {
        foreach ($name in @('gswin64c.exe', 'gswin32c.exe')) {
            $cand = Join-Path $d.Dir "bin\$name"
            if (Test-Path -LiteralPath $cand -PathType Leaf) {
                return (Resolve-Path -LiteralPath $cand).Path
            }
        }
    }

    return $null
}

# WinFormsBootstrap.ps1 — ordre global garanti avant tout IWin32Window (Form, Control, MessageBox, etc.)
# Charge depuis Config.ps1 (point d'entrée commun) et/ou Ensure-WinFormsInitialized (GUI.ps1).

if (-not (Get-Variable -Name WinFormsApplicationInitialized -Scope Global -ErrorAction SilentlyContinue)) {
    $global:WinFormsApplicationInitialized = $false
}

function Initialize-ApplicationWinForms {
    <#
    .SYNOPSIS
        Add-Type WinForms + Drawing, puis EnableVisualStyles et SetCompatibleTextRenderingDefault($false), une seule fois par processus.
    .NOTES
        Trace : définir $env:CN_WINFORMS_TRACE = '1' pour Write-Host sur la console.
    #>
    [CmdletBinding()]
    param([switch]$Trace)

    $doTrace = $Trace -or ($env:CN_WINFORMS_TRACE -eq '1' -or $env:CN_WINFORMS_TRACE -eq 'true')
    if ($global:WinFormsApplicationInitialized) {
        $global:WinFormsInitialized = $true
        if ($doTrace) {
            Write-Host "[WINFORMS TRACE] Initialize-ApplicationWinForms: déjà fait, ignoré." -ForegroundColor DarkGray
        }
        return
    }

    if ($doTrace) {
        Write-Host "[WINFORMS TRACE] Bootstrap: Add-Type System.Windows.Forms + System.Drawing" -ForegroundColor Cyan
    }
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

    if ($doTrace) {
        Write-Host "[WINFORMS TRACE] Bootstrap: EnableVisualStyles()" -ForegroundColor Cyan
    }
    [System.Windows.Forms.Application]::EnableVisualStyles()

    if ($doTrace) {
        Write-Host "[WINFORMS TRACE] Bootstrap: SetCompatibleTextRenderingDefault(`$false)" -ForegroundColor Cyan
    }
    [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

    $global:WinFormsApplicationInitialized = $true
    $global:WinFormsInitialized = $true

    if ($doTrace) {
        Write-Host "[WINFORMS TRACE] Bootstrap: terminé — création Form/Control/MessageBox autorisée." -ForegroundColor Green
    }
}

if ($env:CN_WINFORMS_TRACE -eq '1' -or $env:CN_WINFORMS_TRACE -eq 'true') {
    if (-not $global:CN_WinFormsExitHookRegistered) {
        $global:CN_WinFormsExitHookRegistered = $true
        Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
            Write-Host "[WINFORMS TRACE] ENGINE EXIT (PowerShell.Exiting)" -ForegroundColor DarkYellow
        } | Out-Null
    }
}

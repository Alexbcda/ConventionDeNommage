# WinFormsGuard.ps1 — diagnostics uniquement (aucun proxy / hook sur New-Object ni cmdlets natives).
# Pour l’ordre d’init WinForms : Bootstrap.ps1 + WinFormsBootstrap.ps1 (Initialize-ApplicationWinForms).
# Pour l’audit statique : src\Tools\Find-WinFormsLeaks.ps1

function Write-WinFormsInitStateDiagnostic {
    Write-Host '=== WINFORMS INIT STATE ===' -ForegroundColor Yellow
    if (Get-Variable -Name WinFormsInitialized -Scope Global -ErrorAction SilentlyContinue) {
        Write-Host ("WinFormsInitialized = {0}" -f $global:WinFormsInitialized)
    }
    if (Get-Variable -Name WinFormsApplicationInitialized -Scope Global -ErrorAction SilentlyContinue) {
        Write-Host ("WinFormsApplicationInitialized = {0}" -f $global:WinFormsApplicationInitialized)
    }
    if (Get-Variable -Name WinFormsStrictMode -Scope Global -ErrorAction SilentlyContinue) {
        Write-Host ("WinFormsStrictMode = {0}" -f $global:WinFormsStrictMode)
    }
    if (Get-Variable -Name FirstWinFormsCreationStack -Scope Global -ErrorAction SilentlyContinue) {
        if ($null -ne $global:FirstWinFormsCreationStack) {
            Write-Host '--- FirstWinFormsCreationStack ---' -ForegroundColor Yellow
            $global:FirstWinFormsCreationStack | Format-List *
        }
    }
    Get-PSCallStack | Format-List *
}

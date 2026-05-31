#Requires -Version 5.1
<#
.SYNOPSIS
    Tests Pester — etats SharePoint UI et annulation planning (simulation).

.NOTES
    Invoke-Pester -Path .\Test\SharePointUI.Tests.ps1
#>

[CmdletBinding()]
param()

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'src\Common\CnsSharePointConnector.ps1')
. (Join-Path $repoRoot 'src\Common\CnsSharePointUI.ps1')
. (Join-Path $repoRoot 'src\ODM\PdfPlanningOptimizer\Services\PlanningRebuilder.ps1')

Describe 'SharePoint UI states' {

    It 'T3 - Etat Denied : definition bouton Copier' {
        $def = Get-SharePointUiStateDefinition -Status 'Denied'
        @($def.Buttons | ForEach-Object { $_.Id }) | Should Be @('Copy')
    }

    It 'T4 - Etat Offline : pas de boutons dynamiques' {
        $def = Get-SharePointUiStateDefinition -Status 'Offline'
        @($def.Buttons).Count | Should Be 0
    }

    It 'Etats degrades : couleur rouge et mode degrade active' {
        foreach ($status in @('Offline', 'Denied', 'Error')) {
            $def = Get-SharePointUiStateDefinition -Status $status
            $def.ForeColor | Should Be ([System.Drawing.Color]::Red)
            $def.StatusDotColor | Should Be ([System.Drawing.Color]::Red)
            $def.DegradedMode | Should Be $true
        }
    }

    It 'Etat Connected : couleur verte sans mode degrade' {
        $def = Get-SharePointUiStateDefinition -Status 'Connected'
        $def.ForeColor | Should Be ([System.Drawing.Color]::Green)
        $def.DegradedMode | Should Be $false
    }

    It 'Etat WamBlocked : bouton Reconnecter' {
        $def = Get-SharePointUiStateDefinition -Status 'WamBlocked'
        @($def.Buttons | ForEach-Object { $_.Id }) | Should Be @('Login')
        $def.DegradedMode | Should Be $true
        ($def.Buttons | Where-Object { $_.Id -eq 'Login' }).Text | Should Be 'Reconnecter'
    }

    It 'Etats Expired et Connecting activent le mode degrade' {
        foreach ($status in @('Expired', 'Connecting')) {
            (Get-SharePointUiStateDefinition -Status $status).DegradedMode | Should Be $true
        }
    }

    It 'Resolve-CnsSharePointConnectError detecte WamBlocked' {
        $resolved = Resolve-CnsSharePointConnectError -ErrorMessage 'Sign in by Web Account Manager (WAM) is enabled'
        $resolved.Status | Should Be 'WamBlocked'
    }

    It 'Get-SharePointConnectionState retourne le dernier etat connu' {
        $sample = [pscustomobject]@{ Status = 'Offline'; Message = 'test' }
        Set-CnsSharePointConnectionState -State $sample
        (Get-SharePointConnectionState).Status | Should Be 'Offline'
    }

    It 'Get-WindowsAccountInfo retourne le compte Windows' {
        $user = Get-WindowsAccountInfo
        $user | Should Not BeNullOrEmpty
    }

    It 'Copy-SharePointErrorToClipboard formate le message' {
        Add-Type -AssemblyName System.Windows.Forms
        $state = [pscustomobject]@{
            Status      = 'Denied'
            Message     = 'Acces refuse'
            ErrorDetail = 'HTTP 403'
        }
        Copy-SharePointErrorToClipboard -State $state
        [System.Windows.Forms.Clipboard]::ContainsText() | Should Be $true
        [System.Windows.Forms.Clipboard]::GetText() | Should Match 'HTTP 403'
    }
}

Describe 'Planning rebuild stop' {

    It 'T6 - Request-PlanningRebuildStop interrompt le pipeline' {
        Reset-PlanningRebuildStop
        Test-PlanningRebuildStopRequested | Should Be $false
        Request-PlanningRebuildStop
        Test-PlanningRebuildStopRequested | Should Be $true
        Reset-PlanningRebuildStop
        Test-PlanningRebuildStopRequested | Should Be $false
    }
}

Describe 'Planning progress percent' {

    It 'T7 - Get-PlanningRebuildStepPercent calcule le pourcentage global' {
        Get-PlanningRebuildStepPercent -StepIndex 1 -StepCount 5 -SubRatio 0.5 | Should Be 10
        Get-PlanningRebuildStepPercent -StepIndex 2 -StepCount 5 -SubRatio 0 | Should Be 20
        Get-PlanningRebuildStepPercent -StepIndex 5 -StepCount 5 -SubRatio 1 | Should Be 100
    }
}

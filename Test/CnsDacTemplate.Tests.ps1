#Requires -Version 5.1
<#
.SYNOPSIS
    Tests Pester : quantite DAC Bio dechets (bioseau / bac / vrac / exclusion CEA).

.NOTES
    Syntaxe Pester 3.x / 4.x (Should Be).
#>

[CmdletBinding()]
param()

Describe 'CnsDacTemplate - quantite DAC Bio dechets' {

    BeforeAll {
        $dacPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\CnsDacTemplate.ps1' | Resolve-Path
        . ([string]$dacPath)
    }

    It 'Bioseau 20 L /5 → 1 DAC' {
        $q = Get-CnsBioDechetsTheoreticalQuantityFromLines -Lines @('Collecte de Bio déchets', 'Bioseau 20 L /5 kg')
        $q | Should Be 1
    }

    It 'Bac 240L /3 → 3 DAC' {
        $q = Get-CnsBioDechetsTheoreticalQuantityFromLines -Lines @('Collecte de Bio déchets', 'Bac 240L /3 kg')
        $q | Should Be 3
    }

    It 'Bac 120L /2 → 2 DAC' {
        $q = Get-CnsBioDechetsTheoreticalQuantityFromLines -Lines @('Collecte de Bio déchets', 'Bac 120L /2 kg')
        $q | Should Be 2
    }

    It 'Vrac /4 → 4 DAC' {
        $q = Get-CnsBioDechetsTheoreticalQuantityFromLines -Lines @('Collecte de Bio déchets', 'Vrac /4 kg')
        $q | Should Be 4
    }

    It 'Collecte Bio sans volume ni /Y → 0 (STEP5 force a 1 hors exclusion)' {
        $q = Get-CnsBioDechetsTheoreticalQuantityFromLines -Lines @('Collecte de Bio déchets')
        $q | Should Be 0
    }

    It 'CEA SLE N°24531 → 0 DAC (exclusion)' {
        $lines = @(
            'CEA - Service Logistique et Environnement (SLE) - N°24531',
            'Collecte de Bio déchets',
            'Bioseau 20 L /5 kg'
        )
        $q = Get-CnsBioDechetsTheoreticalQuantityFromLines -Lines $lines
        $q | Should Be 0
        (Test-CnsBioDechetsDacExcludedFromLines -Lines $lines) | Should Be $true
    }
}

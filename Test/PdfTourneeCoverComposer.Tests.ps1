#Requires -Version 5.1
<#
.SYNOPSIS
    Tests Pester : formats mémos garde (Track => BSD / Ponctuel Client - Prestation)
    et assemblage Get-CnsTourneeMetierMemoLinesForBlock (pas d'exception si vide).

.NOTES
    Ne modifie pas le code métier. Syntaxe Pester 3.x / 4.x (Should Be / Should Match).
#>

[CmdletBinding()]
param()

Describe 'PdfTourneeCoverComposer - memos page de garde (Track / Ponctuel)' {

    BeforeAll {
        $scalarPath = Join-Path $PSScriptRoot '..\src\Common\ScalarGuard.ps1' | Resolve-Path
        $sortSafePath = Join-Path $PSScriptRoot '..\src\Common\SortSafe.ps1' | Resolve-Path
        $segPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\PlanningExcelTourneeSegments.ps1' | Resolve-Path
        $metierPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\CnsPdfMetierPrestation.ps1' | Resolve-Path
        $dacPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\CnsDacTemplate.ps1' | Resolve-Path
        $coverComposerPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\PdfTourneeCoverComposer.ps1' | Resolve-Path
        . ([string]$scalarPath)
        . ([string]$sortSafePath)
        . ([string]$segPath)
        . ([string]$metierPath)
        . ([string]$dacPath)
        . ([string]$coverComposerPath)
    }

    It 'Format Track : BNP Collecte de piles => BSD' {
        $line = Format-CnsCoverGardeTrackDechetMemoLine -Detail 'Collecte de piles' -Client 'BNP'
        $line | Should Be 'BNP Collecte de piles => BSD'
    }

    It 'Format Ponctuel : Mairie Collecte de masques' {
        $line = Format-CnsCoverGardePrestationMemoLine -Detail 'Collecte de masques' -Client 'Mairie'
        $line | Should Be 'Mairie Collecte de masques'
    }

    It 'Get-CnsTourneeMetierMemoLinesForBlock : Track piles + Ponctuel masques (segment fictif Raphaël)' {
        # Segment fictif (contexte métier) : Raphaël / 13H30 / FR-418-CS — les mémos viennent des WO pages.
        $segMeta = [pscustomobject]@{
            Collecteur         = 'Raphaël'
            ServiceDebutHour   = 13
            ServiceDebutMinute = 30
            Plaque             = 'FR-418-CS'
            Vehicule           = '13'
            ServiceRank        = 2
            ServiceLabel       = 'Après-midi'
        }
        $segMeta.Collecteur | Should Be 'Raphaël'
        $segMeta.Plaque | Should Be 'FR-418-CS'
        $segMeta.ServiceDebutHour | Should Be 13
        $segMeta.ServiceDebutMinute | Should Be 30

        $woTrack = [pscustomobject]@{
            ClientName = 'BNP'
            WorkOrder  = '2222222'
            Services   = @(@{ Type = 'Collecte de piles'; ODM = '2222222-1' })
            Pages      = @(1)
        }
        $woPont = [pscustomobject]@{
            ClientName = 'Mairie'
            WorkOrder  = '3333333'
            Services   = @(@{ Type = 'Collecte Ponctuel de masques'; ODM = '3333333-1' })
            Pages      = @(2)
        }

        $pairs = @(
            [pscustomobject]@{ FinalOrder = 1; RawPageNum = 1 },
            [pscustomobject]@{ FinalOrder = 2; RawPageNum = 2 }
        )
        $foToLine = @{
            1 = [pscustomobject]@{ FinalOrder = 1; Source = 'ExcelOrder'; ExcelSourceOrder = 1 }
            2 = [pscustomobject]@{ FinalOrder = 2; Source = 'ExcelOrder'; ExcelSourceOrder = 2 }
        }

        $memos = @(Get-CnsTourneeMetierMemoLinesForBlock `
                -MainFrom1 1 -MainTo1 2 `
                -SortedGsPairs $pairs `
                -FinalOrderToLine $foToLine `
                -WorkOrders @($woTrack, $woPont) `
                -PdfEntities @())

        $joined = ($memos -join '|')
        Write-Host ("[TEST] memos=[{0}]" -f $joined)

        # Regroupement : en-tête client puis prestation indentée (ordre alpha : BNP, Mairie) + ligne vide entre blocs.
        ($memos | Where-Object { $_ -eq 'BNP' }).Count | Should BeGreaterThan 0
        ($memos | Where-Object { $_ -eq '    Collecte de piles => BSD' }).Count | Should BeGreaterThan 0
        ($memos | Where-Object { $_ -eq 'Mairie' }).Count | Should BeGreaterThan 0
        ($memos | Where-Object { $_ -match '(?i)^    Collecte\s+Ponctuel\s+de\s+masques$' }).Count | Should BeGreaterThan 0
        $idxBnp = [array]::IndexOf([string[]]$memos, 'BNP')
        $idxMairie = [array]::IndexOf([string[]]$memos, 'Mairie')
        ($idxBnp -ge 0 -and $idxMairie -gt $idxBnp) | Should Be $true
        ($memos[($idxMairie - 1)] -eq '') | Should Be $true
    }

    It 'Get-CnsTourneeMetierMemoLinesForBlock : assemblage vide sans exception' {
        # SortedGsPairs est Mandatory (pas AllowEmptyCollection) : on passe un bloc PdfFallback
        # qui ne produit aucun mémo, sans faire planter l'assemblage.
        $threw = $false
        $memos = @('sentinel')
        try {
            $pairs = @([pscustomobject]@{ FinalOrder = 1; RawPageNum = 1 })
            $foToLine = @{
                1 = [pscustomobject]@{ FinalOrder = 1; Source = 'PdfFallback' }
            }
            $memos = @(Get-CnsTourneeMetierMemoLinesForBlock `
                    -MainFrom1 1 -MainTo1 1 `
                    -SortedGsPairs $pairs `
                    -FinalOrderToLine $foToLine `
                    -WorkOrders @() `
                    -PdfEntities @())
        }
        catch {
            $threw = $true
            Write-Host ("[TEST] Exception inattendue : {0}" -f $_.Exception.Message)
            throw
        }
        $threw | Should Be $false
        ,$memos | Should Not Be $null
        @($memos).Count | Should Be 0
    }

    It 'Formatters : Detail vide ne jette pas et retourne chaine vide' {
        $threw = $false
        $a = $null
        $b = $null
        try {
            $a = Format-CnsCoverGardeTrackDechetMemoLine -Detail '' -Client 'BNP'
            $b = Format-CnsCoverGardePrestationMemoLine -Detail '' -Client 'Mairie'
        }
        catch {
            $threw = $true
            throw
        }
        $threw | Should Be $false
        $a | Should Be ''
        $b | Should Be ''
    }

    It 'FT : bloc client + Faire inventaire (plus de Inventaire … compter)' {
        function Get-CnsStep5FragSliceFtCollectionPointLabel {
            param($FragSlicePdfPath, $PdfRawLines, $RawPageNumOneBased, $PageEntity, $WorkOrderEntity)
            return 'FT ST MARTIN D''HERES [1234] - N°999'
        }
        function Test-CnsFtCollectionPointLabelEligible {
            param($Label)
            return ([string]$Label -match '(?i)^FT\s+')
        }

        $pairs = @([pscustomobject]@{ FinalOrder = 1; RawPageNum = 1 })
        $foToLine = @{
            1 = [pscustomobject]@{ FinalOrder = 1; Source = 'ExcelOrder'; ExcelSourceOrder = 1 }
        }
        $wo = [pscustomobject]@{
            ClientName = 'FT ST MARTIN'
            WorkOrder  = '1111111'
            Services   = @()
            Pages      = @(1)
        }

        $memos = @(Get-CnsTourneeMetierMemoLinesForBlock `
                -MainFrom1 1 -MainTo1 1 `
                -SortedGsPairs $pairs `
                -FinalOrderToLine $foToLine `
                -WorkOrders @($wo) `
                -PdfEntities @())

        ($memos -join '|') | Should Match '(?i)FT\s+ST\s+MARTIN'
        ($memos | Where-Object { $_ -eq '    Faire inventaire' }).Count | Should BeGreaterThan 0
        ($memos | Where-Object { $_ -match '(?i)Inventaire.+compter\s+le\s+nombre\s+de\s+bacs' }).Count | Should Be 0
    }

    It 'DAC Bio : bloc compact (clients + instruction collés, indent)' {
        function Test-CnsStep5FragSliceRequiresBioDechetsDocument {
            param($FragSlicePdfPath, $PdfRawLinesByPage, $RawPageNumOneBased, $PrecomputedRawLines)
            return $true
        }
        function Get-CnsStep5RawLinesForPhysicalPage {
            param($PageNumberOneBased, $PdfRawLinesByPage)
            return @('BIO')
        }
        function Resolve-CnsWorkOrderEntityFromPdfPage {
            param($RawPageNumOneBased, $WorkOrders, $PdfEntities)
            if ($RawPageNumOneBased -eq 1) {
                return [pscustomobject]@{ ClientName = 'SAMSE SIEGE GRENOBLE' }
            }
            return [pscustomobject]@{ ClientName = 'ATAWEY EX MCPHY' }
        }
        function Get-CnsPdfPageEntityByPhysicalPage {
            param($PageNumberOneBased, $PdfEntities)
            return $null
        }

        $pairs = @(
            [pscustomobject]@{ FinalOrder = 1; RawPageNum = 1 },
            [pscustomobject]@{ FinalOrder = 2; RawPageNum = 2 }
        )
        $foToLine = @{
            1 = [pscustomobject]@{ FinalOrder = 1; Source = 'ExcelOrder' }
            2 = [pscustomobject]@{ FinalOrder = 2; Source = 'ExcelOrder' }
        }

        $memos = @(Get-CnsBioDechetsCoverMemoLinesViaStep5Detection `
                -MainFrom1 1 -MainTo1 2 `
                -SortedGsPairs $pairs `
                -FinalOrderToLine $foToLine `
                -WorkOrders @() `
                -PdfEntities @() `
                -PdfRawLinesByPage @{})

        $instrBody = Get-CnsDacBioCoverInstructionText
        $instr = ('    ' + $instrBody)
        $idxInstr = [array]::IndexOf([string[]]$memos, $instr)
        $idxInstr | Should BeGreaterThan 0
        # Pas de ligne vide avant l'instruction : ligne précédente = dernier client.
        ($memos[($idxInstr - 1)] -eq '') | Should Be $false
        ($memos[($idxInstr - 1)] -match '^\s') | Should Be $false
        ($instr -match '^\s{4}Reporter\s+sur\s+le\s+DAC') | Should Be $true
        # Wrap conserve l'indent sur chaque ligne.
        $wrapped = @(Split-CnsCoverTextToWrappedLines -Text $instr -MaxChars 78)
        ($wrapped.Count -ge 2) | Should Be $true
        (@($wrapped | Where-Object { $_ -notmatch '^\s{4}\S' }).Count) | Should Be 0
        # Pas de ligne vide entre les deux clients DAC.
        $clients = @($memos | Where-Object { $_ -and $_ -ne '' -and $_ -ne $instr })
        $clients.Count | Should Be 2
        $i0 = [array]::IndexOf([string[]]$memos, [string]$clients[0])
        $i1 = [array]::IndexOf([string[]]$memos, [string]$clients[1])
        ([Math]::Abs($i1 - $i0) -eq 1) | Should Be $true
        # Aucune ligne vide dans tout le bloc DAC.
        (@($memos | Where-Object { $_ -eq '' }).Count) | Should Be 0
    }

    It 'CEA SLE : absent de la liste DAC garde (masqué)' {
        function Test-CnsStep5FragSliceRequiresBioDechetsDocument {
            param($FragSlicePdfPath, $PdfRawLinesByPage, $RawPageNumOneBased, $PrecomputedRawLines)
            return $true
        }
        function Get-CnsStep5RawLinesForPhysicalPage {
            param($PageNumberOneBased, $PdfRawLinesByPage)
            return @(
                'CEA - Service Logistique et Environnement (SLE) - N°24531',
                'Collecte de bio-dechets'
            )
        }
        function Resolve-CnsWorkOrderEntityFromPdfPage {
            param($RawPageNumOneBased, $WorkOrders, $PdfEntities)
            return [pscustomobject]@{ ClientName = 'CEA - Service Logistique et Environnement (SLE) - N°24531' }
        }
        function Get-CnsPdfPageEntityByPhysicalPage {
            param($PageNumberOneBased, $PdfEntities)
            return $null
        }

        $pairs = @([pscustomobject]@{ FinalOrder = 1; RawPageNum = 1 })
        $foToLine = @{
            1 = [pscustomobject]@{ FinalOrder = 1; Source = 'ExcelOrder' }
        }

        $memos = @(Get-CnsBioDechetsCoverMemoLinesViaStep5Detection `
                -MainFrom1 1 -MainTo1 1 `
                -SortedGsPairs $pairs `
                -FinalOrderToLine $foToLine `
                -WorkOrders @() `
                -PdfEntities @() `
                -PdfRawLinesByPage @{})

        @($memos).Count | Should Be 0
    }

    It 'Track fragments : Collecte majuscule (DEEE / piles / cartouches)' {
        (Get-CnsCoverGardeTrackDechetCollecteFragment -Detail 'Collecte DEEE') | Should Be 'Collecte DEEE'
        (Get-CnsCoverGardeTrackDechetCollecteFragment -Detail 'Collecte de piles') | Should Be 'Collecte de piles'
        (Get-CnsCoverGardeTrackDechetCollecteFragment -Detail 'Collecte de cartouches') | Should Match '^Collecte\s'
    }
}

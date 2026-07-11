#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '..\src\ODM\PdfPlanningOptimizer\Services\CnsPdfMetierPrestation.ps1')
. (Join-Path $here '..\src\ODM\PdfPlanningOptimizer\Services\CnsFtTemplate.ps1')
. (Join-Path $here '..\src\ODM\PdfPlanningOptimizer\Services\CnsPdfStructureMerge.ps1')
. (Join-Path $here '..\src\ODM\PdfPlanningOptimizer\Extractors\EntityExtractor.ps1')

Describe 'FT collecte' {
    It 'detecte FT CHAMBERY' {
        $label = Get-CnsFtCollectionPointLabelFromRawLines -RawLines @('FT CHAMBERY GRAND VERGER')
        $label | Should Be 'FT CHAMBERY GRAND VERGER'
    }

    It 'nettoie crochets et suffixe FT' {
        $cases = @(
            @{ In = 'FT DT MEYLAN [2352] - N°8796'; Expected = 'FT DT MEYLAN' }
            @{ In = 'FT CHAMBERY GRAND VERGER [1234] - N°5678'; Expected = 'FT CHAMBERY GRAND VERGER' }
            @{ In = 'FT ANNECY [456] - N°789'; Expected = 'FT ANNECY' }
            @{ In = 'FT     - N°8785GRAND VERGER'; Expected = 'FT GRAND VERGER' }
        )
        foreach ($c in $cases) {
            $label = Get-CnsFtCollectionPointLabelFromRawLines -RawLines @($c.In)
            $label | Should Be $c.Expected
        }
    }

    It 'ConvertTo-CnsFtCollectionPointDisplayLabel re-applique le nettoyage' {
        ConvertTo-CnsFtCollectionPointDisplayLabel -Value 'FT DT MEYLAN [2352] - N°8796' | Should Be 'FT DT MEYLAN'
    }

    It 'ConvertTo-CnsFtBracketDisplayLabel - supprime les crochets' {
        ConvertTo-CnsFtBracketDisplayLabel -RawLabel 'FT CHAMBERY GRAND VERGER [2953] - N°8785' |
            Should Be 'FT CHAMBERY GRAND VERGER'
    }

    It 'ConvertTo-CnsFtBracketDisplayLabel - crochets multiples' {
        ConvertTo-CnsFtBracketDisplayLabel -RawLabel 'FT TEST [123] [456] - N°789' |
            Should Be 'FT TEST'
    }

    It 'Get-ClientNameFromLines - fusionne 2 lignes (CHAMBERY)' {
        $lines = @('FT CHAMBERY GRAND', 'VERGER [2953] - N°8785')
        $clientId = '8785'
        $result = Get-ClientNameFromLines -Lines $lines -ClientId $clientId
        $result | Should Be 'FT CHAMBERY GRAND VERGER [2953] - N°8785'
    }

    It 'chaine complete - 2 lignes + nettoyage' {
        $lines = @('FT CHAMBERY GRAND', 'VERGER [2953] - N°8785')
        $clientId = '8785'
        $reconstructed = Get-ClientNameFromLines -Lines $lines -ClientId $clientId
        $cleaned = ConvertTo-CnsFtBracketDisplayLabel -RawLabel $reconstructed
        $cleaned | Should Be 'FT CHAMBERY GRAND VERGER'
    }

    It 'Get-CnsFtCollectionPointLabelFromPageEntity - simule PageEntity' {
        $PageEntity = [PSCustomObject]@{
            ClientNameLines = @('FT CHAMBERY GRAND', 'VERGER [2953] - N°8785')
            ClientName      = 'FT CHAMBERY GRAND VERGER [2953] - N°8785'
        }
        $WorkOrderEntity = [PSCustomObject]@{
            ClientID   = '8785'
            ClientName = 'FT CHAMBERY GRAND VERGER [2953] - N°8785'
        }

        $result = Get-CnsFtCollectionPointLabelFromPageEntity -PageEntity $PageEntity -WorkOrderEntity $WorkOrderEntity
        $result | Should Be 'FT CHAMBERY GRAND VERGER'
    }

    It 'rejette un point de collecte qui ne commence pas par FT' {
        Test-CnsFtCollectionPointLabelEligible -Label 'CHAMBERY FT' | Should Be $false
        Test-CnsFtCollectionPointLabelEligible -Label 'MAIRIE FT GRENOBLE' | Should Be $false
        Test-CnsFtCollectionPointLabelEligible -Label 'FT CHAMBERY' | Should Be $true
        Test-CnsFtCollectionPointLabelEligible -Label 'ft chambery' | Should Be $true

        $PageEntity = [PSCustomObject]@{
            ClientNameLines = @('MAIRIE GRENOBLE', 'CENTRE VILLE [1234] - N°5678')
            ClientName      = 'MAIRIE GRENOBLE CENTRE VILLE [1234] - N°5678'
        }
        $WorkOrderEntity = [PSCustomObject]@{
            ClientID   = '5678'
            ClientName = 'MAIRIE GRENOBLE CENTRE VILLE [1234] - N°5678'
        }
        Get-CnsFtCollectionPointLabelFromPageEntity -PageEntity $PageEntity -WorkOrderEntity $WorkOrderEntity |
            Should Be $null

        Get-CnsStep5FragSliceFtCollectionPointLabel -PrecomputedRawLines @('MAIRIE FT GRENOBLE') |
            Should Be $null
    }

    It 'Get-CnsFtPlaceholders nettoie Point_Collecte MEYLAN' {
        $ph = Get-CnsFtPlaceholders -WorkOrderEntity $null -PageEntity $null -SegmentMeta $null `
            -VisitDate ([datetime]'2026-07-15') -PointCollecte 'FT DT MEYLAN [2352] - N°8796'
        $ph.Point_Collecte | Should Be 'FT DT MEYLAN'
    }

    It 'Get-CnsFtPlaceholders nettoie Client_Nom affiche dans FT.xlsx' {
        $wo = [PSCustomObject]@{
            ClientID   = '8796'
            ClientName = 'FT DT MEYLAN [2352] - N°8796'
            WorkOrder  = '6266185'
            Address    = [PSCustomObject]@{
                Street     = '16c Chemin de Malacher'
                PostalCode = '38240'
                City       = 'Meylan'
            }
            Services   = @()
        }
        $ph = Get-CnsFtPlaceholders -WorkOrderEntity $wo -PageEntity $null -SegmentMeta $null `
            -VisitDate ([datetime]'2026-07-15') -PointCollecte 'FT DT MEYLAN [2352] - N°8796'
        $ph.Client_Nom | Should Be 'FT DT MEYLAN'
        $ph.Point_Collecte | Should Be 'FT DT MEYLAN'
    }

    It 'ConvertTo-CnsFtPointCollecteDisplay fonctionne sans module metier' {
        $saved = Get-Command ConvertTo-CnsFtBracketDisplayLabel -ErrorAction SilentlyContinue
        Remove-Item Function:ConvertTo-CnsFtBracketDisplayLabel -ErrorAction SilentlyContinue
        try {
            ConvertTo-CnsFtPointCollecteDisplay -RawLabel 'FT CHAMBERY GRAND VERGER [2953] - N°8785' |
                Should Be 'FT CHAMBERY GRAND VERGER'
        }
        finally {
            if ($null -eq (Get-Command ConvertTo-CnsFtBracketDisplayLabel -ErrorAction SilentlyContinue)) {
                . (Join-Path $here '..\src\ODM\PdfPlanningOptimizer\Services\CnsPdfMetierPrestation.ps1')
            }
        }
    }

    It 'Fixture 1507.pdf page 72 - detection FT et nettoyage MEYLAN' {
        . (Join-Path $here '..\src\ODM\PdfPlanningOptimizer\Services\CnsPdfMetierPrestation.ps1')
        $pdfFixture = Join-Path $here 'Fixtures\PdfPlanningOptimizer\1507.pdf'
        if (-not (Test-Path -LiteralPath $pdfFixture)) {
            Set-TestInconclusive -Message 'Fixture 1507.pdf absente'
        }
        $pdftotext = Get-ChildItem (Join-Path $here '..\runtime\poppler') -Recurse -Filter pdftotext.exe -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $pdftotext) {
            Set-TestInconclusive -Message 'pdftotext absent'
        }
        $env:PDFTOTEXT_PATH = $pdftotext.FullName
        . (Join-Path $here '..\src\ODM\PdfPlanningOptimizer\Extractors\PdfExtractor.ps1')
        . (Join-Path $here '..\src\ODM\PdfPlanningOptimizer\Services\PageEntityAggregator.ps1')

        $extract = Invoke-PdfExtraction -PdfPath $pdfFixture
        $pg = @($extract.Pages | Where-Object {
                ($_.Lines -join ' ') -match '(?i)FT\s+DT\s+MEYLAN'
            } | Select-Object -First 1)
        if (-not $pg) {
            Set-TestInconclusive -Message 'Page FT DT MEYLAN introuvable dans 1507.pdf'
        }

        $pe = ConvertTo-PageEntity -PageNumber $pg.PageNumber -Lines @($pg.Lines)
        $wo = @(ConvertTo-WorkOrderEntityList -PageEntities @($pe)) | Select-Object -First 1

        $ftLabel = Get-CnsStep5FragSliceFtCollectionPointLabel -PageEntity $pe -WorkOrderEntity $wo `
            -PdfRawLines @($pg.Lines) -PrecomputedRawLines @($pg.Lines)
        Test-CnsFtCollectionPointLabelEligible -Label $ftLabel | Should Be $true
        $ftLabel | Should Be 'FT DT MEYLAN'

        $ph = Get-CnsFtPlaceholders -WorkOrderEntity $wo -PageEntity $pe -SegmentMeta $null `
            -VisitDate ([datetime]'2026-07-15') -PointCollecte $ftLabel
        $ph.Point_Collecte | Should Be 'FT DT MEYLAN'
        $ph.Client_Nom | Should Be 'FT DT MEYLAN'
    }

    It 'fragment ft pdf' {
        (Test-CnsPdfPathIsFtCollecteFragment -Path 'ft_001_00001.pdf') | Should Be $true
    }

    It 'placeholders Point_Collecte' {
        $ph = Get-CnsFtPlaceholders -WorkOrderEntity $null -PageEntity $null -SegmentMeta $null `
            -VisitDate ([datetime]'2026-07-15') -PointCollecte 'FT TEST'
        $ph.Point_Collecte | Should Be 'FT TEST'
    }
}

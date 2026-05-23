#Requires -Version 5.1
<#
.SYNOPSIS
    Tests de non-régression Pester pour le grouping WorkOrder (PageEntity → WorkOrderEntity)
    et un scénario E2E PDF → export CSV (extraction réelle, données Excel depuis fichier CSV).

.NOTES
    Nécessite le module Pester (syntaxe compatible Pester 3.x / 4.x : Should Be, Should BeExactly).
    Grouping : uniquement PageEntity / WorkOrderEntity et ConvertTo-WorkOrderEntityList.
    E2E : Poppler pdftotext — détection stable sans dépendre du PATH machine :
    variable d'environnement PDFTOTEXT_PATH (fichier ou répertoire contenant pdftotext.exe), puis chemins optionnels
    sous la racine du dépôt (tools\Poppler\Library\bin\pdftotext.exe, etc.). Si indisponible : test ignoré (Skip),
    avertissement « PDF extractor unavailable ». PDF minimal octets réels ; jeu Excel = CSV sous Test\Fixtures.
#>

[CmdletBinding()]
param()

function Get-PdfPlanningOptimizerE2EPlanningPdfBytes {
    $enc = [System.Text.Encoding]::ASCII
    $nl = "`n"
    $streamInner = "BT${nl}/F1 11 Tf${nl}48 742 Td${nl}(N 8276 Date de passage: 17/04/2026 Ordre : 9890123 ODM 9890123-1) Tj${nl}ET${nl}"
    $len = $enc.GetByteCount($streamInner)

    $obj1 = "1 0 obj${nl}<<${nl}/Type /Catalog${nl}/Pages 2 0 R${nl}>>${nl}endobj${nl}"
    $obj2 = "2 0 obj${nl}<<${nl}/Type /Pages${nl}/Kids [3 0 R]${nl}/Count 1${nl}>>${nl}endobj${nl}"
    $obj3 = "3 0 obj${nl}<<${nl}/Type /Page${nl}/Parent 2 0 R${nl}/MediaBox [0 0 612 792]${nl}/Contents 4 0 R${nl}/Resources << /Font << /F1 5 0 R >> >>${nl}>>${nl}endobj${nl}"
    $obj5 = "5 0 obj${nl}<<${nl}/Type /Font${nl}/Subtype /Type1${nl}/BaseFont /Helvetica${nl}>>${nl}endobj${nl}"
    $hdr4 = "4 0 obj${nl}<<${nl}/Length $len${nl}>>${nl}stream${nl}"
    $ftr4 = "endstream${nl}endobj${nl}"

    $body = '%PDF-1.4' + $nl + $obj1 + $obj2 + $obj3 + $obj5 + $hdr4 + $streamInner + $ftr4
    $bodyBytes = $enc.GetBytes($body)

    $offsets = @{}
    foreach ($n in 1, 2, 3, 4, 5) {
        $token = "$n 0 obj"
        $idx = $body.IndexOf($token, [StringComparison]::Ordinal)
        if ($idx -lt 0) {
            throw "PDF fixture interne : jeton '$token' introuvable."
        }
        $offsets[$n] = $idx
    }

    $xrefSb = [System.Text.StringBuilder]::new()
    [void]$xrefSb.Append("xref${nl}0 6${nl}")
    [void]$xrefSb.Append("0000000000 65535 f ${nl}")
    foreach ($n in 1..5) {
        [void]$xrefSb.Append(('{0:0000000000} 00000 n {1}' -f $offsets[$n], $nl))
    }

    $xrefBytes = $enc.GetBytes($xrefSb.ToString())
    $xrefPos = $bodyBytes.Length
    $trailer = "trailer${nl}<<${nl}/Size 6${nl}/Root 1 0 R${nl}>>${nl}startxref${nl}$xrefPos${nl}%%EOF${nl}"
    $trailerBytes = $enc.GetBytes($trailer)

    $all = [byte[]]::new(($bodyBytes.Length + $xrefBytes.Length + $trailerBytes.Length))
    [Array]::Copy($bodyBytes, 0, $all, 0, $bodyBytes.Length)
    [Array]::Copy($xrefBytes, 0, $all, $bodyBytes.Length, $xrefBytes.Length)
    [Array]::Copy($trailerBytes, 0, $all, $bodyBytes.Length + $xrefBytes.Length, $trailerBytes.Length)
    return $all
}

function Get-PdfPlanningOptimizerE2EPdfTotextPath {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $candidates = [System.Collections.Generic.List[string]]::new()

    $fromEnv = [string]$env:PDFTOTEXT_PATH
    if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
        $t = $fromEnv.Trim()
        if (Test-Path -LiteralPath $t -PathType Container) {
            $t = Join-Path $t 'pdftotext.exe'
        }
        [void]$candidates.Add($t)
    }

    foreach ($rel in @(
            'tools\Poppler\Library\bin\pdftotext.exe',
            'tools\poppler\Library\bin\pdftotext.exe',
            'vendor\poppler\Library\bin\pdftotext.exe',
            '.tools\poppler\Library\bin\pdftotext.exe'
        )) {
        [void]$candidates.Add((Join-Path $repoRoot $rel))
    }

    foreach ($p in $candidates) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            return (Resolve-Path -LiteralPath $p).ProviderPath
        }
    }

    return $null
}

function Test-PdfPlanningOptimizerE2EPdfTotextProbe {
    <#
    Vérifie que l'exécutable pdftotext produit du texte à partir d'un PDF réel sur disque (même ligne de commande
    que le pipeline). Ne consulte pas ExtractionNote.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PdftotextExe,

        [Parameter(Mandatory = $true)]
        [string]$PdfPath
    )

    $tempOut = [System.IO.Path]::GetTempFileName()
    try {
        $argList = @(
            '-f', '1',
            '-l', '1',
            '-layout',
            '-enc', 'UTF-8',
            $PdfPath,
            $tempOut
        )
        $p = Start-Process -FilePath $PdftotextExe -ArgumentList $argList -Wait -PassThru -NoNewWindow
        if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $tempOut)) {
            return $false
        }
        $raw = [System.IO.File]::ReadAllText($tempOut, [System.Text.UTF8Encoding]::new($false))
        if ([string]::IsNullOrEmpty($raw)) {
            return $false
        }
        return ($raw -match '9890123')
    }
    finally {
        if (Test-Path -LiteralPath $tempOut) {
            Remove-Item -LiteralPath $tempOut -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'PdfPlanningOptimizer - qualite extraction PDF (Test-PdfExtractQuality)' {

    BeforeAll {
        $script:QePdfExPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Extractors\PdfExtractor.ps1' | Resolve-Path
        . $script:QePdfExPath
    }

    It 'Test-PdfExtractQuality : lignes vides => HasText faux, probablement scanne' {
        $q = Test-PdfExtractQuality -Lines @('', '  ') -PageCount 1 -Mode 'layout'
        $q.HasText | Should Be $false
        $q.IsLikelyScanned | Should Be $true
    }

    It 'Test-PdfExtractQuality : texte riche => HasText vrai' {
        $rich = @(
            'N 8276 Date de passage: 17/04/2026 Ordre : 9890123 ODM 9890123-1',
            'Ligne deux avec du texte et 12345678'
        )
        $q = Test-PdfExtractQuality -Lines $rich -PageCount 1 -Mode 'layout'
        $q.HasText | Should Be $true
        $q.IsLikelyScanned | Should Be $false
    }
}

Describe 'PdfPlanningOptimizer - EntityExtractor multiligne (libelle / valeur ligne suivante)' {

    BeforeAll {
        $script:MlEntityPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Extractors\EntityExtractor.ps1' | Resolve-Path
        . $script:MlEntityPath
    }

    It 'Client ID sur la ligne suivante' {
        $lines = @('Client ID :', '8276')
        $e = ConvertTo-PageEntity -PageNumber 1 -Lines $lines
        $e.ClientID | Should Be '8276'
    }

    It 'Intervention (libelle) puis numero sur la ligne suivante' {
        $lines = @('Intervention:', '9890123')
        $e = ConvertTo-PageEntity -PageNumber 1 -Lines $lines
        $e.WorkOrder | Should Be '9890123'
    }

    It 'Date de passage sur la ligne suivante' {
        $lines = @('Date de passage :', '17/04/2026')
        $e = ConvertTo-PageEntity -PageNumber 1 -Lines $lines
        $e.VisitDate | Should Not Be $null
        $e.VisitDate.ToString('dd/MM/yyyy') | Should Be '17/04/2026'
    }

    It 'ClientName : ligne ANDERLAINE avec N+ordinal-U+00BA et id 5 chiffres (pas confondu avec CP)' {
        $lines = @(
            '4/10/26 16:03',
            'ANDERLAINE ALBERTVILLE SR CONSEIL - Nº24896',
            '108 Rue de la Liberation',
            '73400 SAINT JEAN',
            'Date de passage : 22/04/2026'
        )
        $e = ConvertTo-PageEntity -PageNumber 1 -Lines $lines
        $e.ClientID | Should Be '24896'
        $e.ClientName | Should Match 'ANDERLAINE.*ALBERTVILLE.*CONSEIL'
        $e.Address['PostalCode'] | Should Be '73400'
    }

    It 'Prestations Collecte et Destruction avec code ODM ligne suivante (ODM réel)' {
        $lines = @(
            'Collecte de Papier',
            'confidentiel',
            '5330151-19160224',
            'Bac 360L fermé /2 kg',
            'Prendre le protocole de collecte',
            'Destruction confidentielle de Papier confidentiel',
            '5330151-19160235'
        )
        $e = ConvertTo-PageEntity -PageNumber 1 -Lines $lines
        @($e.Services).Count | Should Be 2
        $e.Services[0].Type | Should Match '(?i)Collecte.*confidentiel'
        $e.Services[0].ODM | Should Be '5330151-19160224'
        $e.Services[1].Type | Should Match '(?i)Destruction confidentielle de Papier confidentiel'
        $e.Services[1].ODM | Should Be '5330151-19160235'
    }
}

Describe 'PdfPlanningOptimizer - Compare-PdftotextExtractionModes (layout vs default)' {

    BeforeAll {
        $script:CmpPdfExPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Extractors\PdfExtractor.ps1' | Resolve-Path
        . $script:CmpPdfExPath
        $script:CmpPdfTotext = Get-PdfPlanningOptimizerE2EPdfTotextPath
    }

    It 'retourne des longueurs pour layout et default sur PDF fixture' {
        if ($null -eq $script:CmpPdfTotext) {
            return
        }
        $pdfPath = Join-Path ([System.IO.Path]::GetTempPath()) ('cmp_modes_' + [Guid]::NewGuid().ToString('n') + '.pdf')
        try {
            [System.IO.File]::WriteAllBytes($pdfPath, (Get-PdfPlanningOptimizerE2EPlanningPdfBytes))
            $cmp = Compare-PdftotextExtractionModes -PdfPath $pdfPath -PdftotextExe $script:CmpPdfTotext -PageNumber 1
            ($cmp.Modes.layout.ExtractedLength -gt 0) | Should Be $true
            ($cmp.Modes.default.ExtractedLength -gt 0) | Should Be $true
        }
        finally {
            Remove-Item -LiteralPath $pdfPath -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'PdfPlanningOptimizer - grouping WorkOrderEntity' {

    BeforeAll {
        $aggregatorPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\PageEntityAggregator.ps1' | Resolve-Path
        . $aggregatorPath
    }

    function New-TestPage {
        param(
            [int]$PageNumber,
            [string]$WorkOrder,
            [string[]]$OdmValues = @()
        )
        $p = [PageEntity]::new($PageNumber)
        if ($PSBoundParameters.ContainsKey('WorkOrder') -and $null -ne $WorkOrder -and $WorkOrder -ne '') {
            $p.WorkOrder = $WorkOrder
        }
        $svcList = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($odm in $OdmValues) {
            if (-not [string]::IsNullOrWhiteSpace($odm)) {
                $svcList.Add(@{ ODM = $odm })
            }
        }
        $p.Services = $svcList.ToArray()
        return $p
    }

    function Test-WorkOrderEntitiesHaveAtMostOneDistinctPageWorkOrder {
        param(
            [WorkOrderEntity[]]$Entities,
            [PageEntity[]]$SourcePages
        )
        foreach ($e in $Entities) {
            $distinct = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($pn in @($e.Pages)) {
                $pg = @($SourcePages | Where-Object { $_.PageNumber -eq $pn } | Select-Object -First 1)[0]
                if ($null -eq $pg) { continue }
                if (-not [string]::IsNullOrWhiteSpace($pg.WorkOrder)) {
                    [void]$distinct.Add($pg.WorkOrder.Trim())
                }
            }
            if ($distinct.Count -gt 1) {
                return $false
            }
        }
        return $true
    }

    It '1. Continuité ODM : deux pages sans WO mais fragments ODM même préfixe → un seul WorkOrderEntity' {
        $pages = @(
            (New-TestPage -PageNumber 1 -OdmValues @('1234567-1')),
            (New-TestPage -PageNumber 2 -OdmValues @('1234567-99'))
        )
        $entities = @(ConvertTo-WorkOrderEntityList -PageEntities $pages)

        $entities.Count | Should Be 1
        ($entities[0].Pages -join ',') | Should Be '1,2'
        $entities[0].WorkOrder | Should Be '1234567'
        (Test-WorkOrderEntitiesHaveAtMostOneDistinctPageWorkOrder -Entities $entities -SourcePages $pages) | Should Be $true
    }

    It '1b. Continuité : deux pages avec même WorkOrder explicite et ODM alignés → un seul WorkOrderEntity' {
        $pages = @(
            (New-TestPage -PageNumber 1 -WorkOrder '1234567' -OdmValues @('1234567-1')),
            (New-TestPage -PageNumber 2 -WorkOrder '1234567' -OdmValues @('1234567-2'))
        )
        $entities = @(ConvertTo-WorkOrderEntityList -PageEntities $pages)

        $entities.Count | Should Be 1
        ($entities[0].Pages -join ',') | Should Be '1,2'
        $entities[0].WorkOrder | Should Be '1234567'
        (Test-WorkOrderEntitiesHaveAtMostOneDistinctPageWorkOrder -Entities $entities -SourcePages $pages) | Should Be $true
    }

    It '2. Héritage strict : page sans WO ni ODM après une page avec WO → même groupe' {
        $pages = @(
            (New-TestPage -PageNumber 1 -WorkOrder 'WO-ALPHA'),
            (New-TestPage -PageNumber 2)
        )
        $entities = @(ConvertTo-WorkOrderEntityList -PageEntities $pages)

        $entities.Count | Should Be 1
        $entities[0].WorkOrder | Should Be 'WO-ALPHA'
        ($entities[0].Pages -join ',') | Should Be '1,2'
        (Test-WorkOrderEntitiesHaveAtMostOneDistinctPageWorkOrder -Entities $entities -SourcePages $pages) | Should Be $true
    }

    It '3. Séparation WO : changement de WorkOrder explicite → deux WorkOrderEntity' {
        $pages = @(
            (New-TestPage -PageNumber 1 -WorkOrder 'FIRST'),
            (New-TestPage -PageNumber 2 -WorkOrder 'SECOND')
        )
        $entities = @(ConvertTo-WorkOrderEntityList -PageEntities $pages)

        $entities.Count | Should Be 2
        $byWo = @{}
        foreach ($e in $entities) {
            $byWo[$e.WorkOrder] = @($e.Pages)
        }
        ($byWo['FIRST'] -join ',') | Should Be '1'
        ($byWo['SECOND'] -join ',') | Should Be '2'
        (Test-WorkOrderEntitiesHaveAtMostOneDistinctPageWorkOrder -Entities $entities -SourcePages $pages) | Should Be $true
    }

    It '4. __UNSPECIFIED__ : pages avant premier signal restent isolées, pas de fusion avec le WO suivant' {
        $pages = @(
            (New-TestPage -PageNumber 1),
            (New-TestPage -PageNumber 2),
            (New-TestPage -PageNumber 3 -WorkOrder 'REAL-WO')
        )
        $entities = @(ConvertTo-WorkOrderEntityList -PageEntities $pages)

        $entities.Count | Should Be 2

        $unspec = @($entities | Where-Object { $null -eq $_.WorkOrder -or $_.WorkOrder -eq '' })
        $real = @($entities | Where-Object { $_.WorkOrder -eq 'REAL-WO' })

        $unspec.Count | Should Be 1
        $real.Count | Should Be 1

        (@($unspec[0].Pages | Sort-Object) -join ',') | Should Be '1,2'
        (@($real[0].Pages | Sort-Object) -join ',') | Should Be '3'

        $merged = @($entities | Where-Object { ($_.Pages -contains 1) -and ($_.Pages -contains 3) })
        $merged.Count | Should Be 0

        (Test-WorkOrderEntitiesHaveAtMostOneDistinctPageWorkOrder -Entities $entities -SourcePages $pages) | Should Be $true
    }

    It '5. Non-régression structurelle : scénario combiné (ODM + héritage + WO + pré-signal)' {
        $pages = @(
            (New-TestPage -PageNumber 1),
            (New-TestPage -PageNumber 2 -OdmValues @('9999999-1')),
            (New-TestPage -PageNumber 3),
            (New-TestPage -PageNumber 4 -WorkOrder '9999999'),
            (New-TestPage -PageNumber 5 -WorkOrder 'OTHER')
        )
        $entities = @(ConvertTo-WorkOrderEntityList -PageEntities $pages)

        (Test-WorkOrderEntitiesHaveAtMostOneDistinctPageWorkOrder -Entities $entities -SourcePages $pages) | Should Be $true

        $allPageNums = [System.Collections.Generic.HashSet[int]]::new()
        foreach ($e in $entities) {
            foreach ($pn in @($e.Pages)) {
                [void]$allPageNums.Add($pn)
            }
        }
        foreach ($p in $pages) {
            $allPageNums.Contains($p.PageNumber) | Should Be $true
        }
    }
}

Describe 'PdfPlanningOptimizer - E2E PDF vers export CSV' {

    BeforeAll {
        $script:E2EOptRoot = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer' | Resolve-Path
        $script:E2EFixtureCsv = Join-Path $PSScriptRoot 'Fixtures\PdfPlanningOptimizer\e2e_planning.csv' | Resolve-Path

        $script:SkipPdfE2E = $true
        $script:E2EOriginalPath = $null

        $pdftotextResolved = Get-PdfPlanningOptimizerE2EPdfTotextPath
        $probePath = Join-Path $TestDrive 'e2e_pdftotext_probe.pdf'
        [System.IO.File]::WriteAllBytes($probePath, (Get-PdfPlanningOptimizerE2EPlanningPdfBytes))

        if ($null -eq $pdftotextResolved) {
            Write-Warning 'PDF extractor unavailable'
        }
        elseif (-not (Test-PdfPlanningOptimizerE2EPdfTotextProbe -PdftotextExe $pdftotextResolved -PdfPath $probePath)) {
            Write-Warning 'PDF extractor unavailable'
        }
        else {
            $script:E2EOriginalPath = $env:PATH
            $binDir = Split-Path -Path $pdftotextResolved -Parent
            $env:PATH = $binDir + [System.IO.Path]::PathSeparator + $env:PATH
            $script:SkipPdfE2E = $false
        }

        . (Join-Path $script:E2EOptRoot 'Extractors\PdfExtractor.ps1')
        . (Join-Path $script:E2EOptRoot 'Extractors\EntityExtractor.ps1')
        . (Join-Path $script:E2EOptRoot 'Services\PageEntityAggregator.ps1')
        . (Join-Path $script:E2EOptRoot 'Matching\ExcelWorkOrderMatch.ps1')
        . (Join-Path $script:E2EOptRoot 'Matching\GlobalMatchResolution.ps1')
        . (Join-Path $script:E2EOptRoot 'Export\FinalAssignmentExport.ps1')
    }

    AfterAll {
        if ($null -ne $script:E2EOriginalPath) {
            $env:PATH = $script:E2EOriginalPath
        }
    }

    It 'Pipeline complet : extraction PDF réelle, agrégation, matching, résolution, export CSV métier' -Skip:$script:SkipPdfE2E {
        $pdfPath = Join-Path $TestDrive 'e2e_one_page.pdf'
        [System.IO.File]::WriteAllBytes($pdfPath, (Get-PdfPlanningOptimizerE2EPlanningPdfBytes))

        $pdf = Invoke-PdfExtraction -PdfPath $pdfPath
        $pdf.PageCount | Should Be 1

        $pageEntities = foreach ($pg in @($pdf.Pages)) {
            ConvertTo-PageEntity -PageNumber $pg.PageNumber -Lines @($pg.Lines)
        }
        $entities = @(ConvertTo-WorkOrderEntityList -PageEntities @($pageEntities))
        $entities.Count | Should Be 1
        $entities[0].WorkOrder | Should Be '9890123'

        $excelRows = @(Import-Csv -LiteralPath $script:E2EFixtureCsv)
        $excelRows.Count | Should Be 1
        $planningRow = $excelRows[0]

        $matches = @(Get-WorkOrderExcelMatchResults -WorkOrderEntities $entities -ExcelRows $excelRows)
        $matches.Count | Should Be 1
        $matches[0].WorkOrder | Should Be '9890123'
        [string]$matches[0].ExcelRowId | Should Be ([string]$planningRow.ExcelRowId)
        $matches[0].MatchScore | Should Be 100

        $final = @(Resolve-WorkOrderExcelFinalAssignments -WorkOrderEntities $entities -MatchResults $matches)
        $final.Count | Should Be 1

        $exportPath = Join-Path $TestDrive 'e2e_export.csv'
        $null = Export-FinalAssignmentReport -FinalAssignments $final -OutputPath $exportPath -Format Csv
        (Test-Path -LiteralPath $exportPath) | Should Be $true

        $rawHeader = (Get-Content -LiteralPath $exportPath -TotalCount 1 -Encoding UTF8)
        $headers = @($rawHeader -split ';' | ForEach-Object { $_.Trim('"') })

        foreach ($expected in @('Commande', 'Reference_ligne_planification', 'Score_final', 'Motif_selection', 'Conflit_regle')) {
            ($headers -contains $expected) | Should Be $true
        }

        $technical = @('WorkOrder', 'ExcelRowId', 'FinalScore', 'DecisionReason', 'ConflictResolved', 'ConcurrentSummary')
        foreach ($bad in $technical) {
            ($headers -contains $bad) | Should Be $false
        }

        $exported = @(Import-Csv -LiteralPath $exportPath -Delimiter ';' -Encoding UTF8)
        $exported.Count | Should Be 1
        $r = $exported[0]

        $r.Commande | Should Be '9890123'
        $r.Reference_ligne_planification | Should Be ([string]$planningRow.ExcelRowId)
        [int]$r.Score_final | Should Be 100

        $r.Commande | Should Be $final[0].WorkOrder
        $r.Reference_ligne_planification | Should Be ([string]$final[0].ExcelRowId)
    }
}

Describe 'PdfPlanningOptimizer - HumanMergeAdapter & merge humain > PDF' {

    BeforeAll {
        $script:HmaEnginePath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\EntityTourneeMergeEngine.ps1' | Resolve-Path
        . $script:HmaEnginePath
    }

    function New-HmaTestPdfEntity {
        param(
            [string]$ClientId,
            [string]$WorkOrder
        )
        return [pscustomobject]@{
            ClientId   = $ClientId
            WorkOrder  = $WorkOrder
            WorkOrders = @($WorkOrder)
            Address    = '10 rue Fixture'
            Date       = [datetime]'2026-04-18'
            ClientName = 'Fixture Client'
        }
    }

    function New-HmaTestExcelTournee {
        return [pscustomobject]@{
            TourneeId = 'T-HMA'
            TourDate  = [datetime]'2026-04-18'
            Agent     = 'AgentX'
            Stops     = @(
                [pscustomobject]@{ Position = 1; WorkOrder = 'WO1'; ClientId = 'EXCEL-C1' }
                [pscustomobject]@{ Position = 2; WorkOrder = 'WO2'; ClientId = 'EXCEL-C2' }
                [pscustomobject]@{ Position = 3; WorkOrder = 'WO3'; ClientId = 'EXCEL-C3' }
            )
        }
    }

    function New-HmaTestPdfResolvedMatches {
        return @(
            [pscustomobject]@{
                TourneeId          = 'T-HMA'
                Position           = 1
                OriginalStatus     = 'MATCH'
                ExcelWorkOrder     = 'WO1'
                ExcelClientId      = 'EXCEL-C1'
                FinalEntity        = (New-HmaTestPdfEntity -ClientId 'PDF-C1' -WorkOrder 'WO1')
                ResolutionSource   = 'Passthrough'
            },
            [pscustomobject]@{
                TourneeId          = 'T-HMA'
                Position           = 2
                OriginalStatus     = 'REVIEW'
                ExcelWorkOrder     = 'WO2'
                ExcelClientId      = 'EXCEL-C2'
                FinalEntity        = (New-HmaTestPdfEntity -ClientId 'PDF-C2' -WorkOrder 'WO2')
                ResolutionSource   = 'Passthrough'
            },
            [pscustomobject]@{
                TourneeId          = 'T-HMA'
                Position           = 3
                OriginalStatus     = 'MATCH'
                ExcelWorkOrder     = 'WO3'
                ExcelClientId      = 'EXCEL-C3'
                FinalEntity        = (New-HmaTestPdfEntity -ClientId 'PDF-C3' -WorkOrder 'WO3')
                ResolutionSource   = 'Passthrough'
            }
        )
    }

    It 'Merge-HumanAndPdfDecisions : humain écrase FinalEntity et OriginalStatus sur la clé TourneeId|Position' {
        $pdf = @(New-HmaTestPdfResolvedMatches)
        $humanEnt = New-HmaTestPdfEntity -ClientId 'HUMAN-OVERRIDE' -WorkOrder 'WO1'
        $human = @(
            [pscustomobject]@{
                TourneeId        = 'T-HMA'
                Position         = 1
                OriginalStatus   = 'MATCH'
                ExcelWorkOrder   = 'WO1'
                ExcelClientId    = 'EXCEL-C1'
                FinalEntity      = $humanEnt
                ResolutionSource = 'HumanStore'
                UserId           = 'tester'
                UtcSaved         = '2026-04-18T12:00:00Z'
            }
        )

        $final = @(Merge-HumanAndPdfDecisions -ResolvedMatches $pdf -HumanResolvedMatches $human)
        $final.Count | Should Be 3

        $r1 = @($final | Where-Object { $_.Position -eq 1 })[0]
        [string]$r1.FinalEntity.ClientId | Should Be 'HUMAN-OVERRIDE'
        [string]$r1.ResolutionSource | Should Be 'HumanStore'
        [string]$r1.OriginalStatus | Should Be 'MATCH'

        $r2 = @($final | Where-Object { $_.Position -eq 2 })[0]
        [string]$r2.OriginalStatus | Should Be 'REVIEW'
        [string]$r2.FinalEntity.ClientId | Should Be 'PDF-C2'

        $r3 = @($final | Where-Object { $_.Position -eq 3 })[0]
        [string]$r3.OriginalStatus | Should Be 'MATCH'
        [string]$r3.FinalEntity.ClientId | Should Be 'PDF-C3'
    }

    It 'Merge-EntityTournees : override humain sur ClientId (MATCH + REVIEW + MATCH PDF) est reflété dans la sortie finale' {
        $excel = @(New-HmaTestExcelTournee)
        $pdfRm = @(New-HmaTestPdfResolvedMatches)
        $humanEnt = New-HmaTestPdfEntity -ClientId 'HUMAN-OVERRIDE' -WorkOrder 'WO1'
        $humanRm = @(
            [pscustomobject]@{
                TourneeId        = 'T-HMA'
                Position         = 1
                OriginalStatus   = 'MATCH'
                ExcelWorkOrder   = 'WO1'
                ExcelClientId    = 'EXCEL-C1'
                FinalEntity      = $humanEnt
                ResolutionSource = 'HumanStore'
            }
        )

        $merged = Merge-EntityTournees -ExcelTournees $excel -ResolvedMatches $pdfRm -HumanResolvedMatches $humanRm
        $stops = @($merged.Tournees[0].Stops)

        $s1 = @($stops | Where-Object { $_.Position -eq 1 })[0]
        [string]$s1.ClientId | Should Be 'HUMAN-OVERRIDE'
        [string]$s1.DecisionStatus | Should Be 'MATCH'

        $s2 = @($stops | Where-Object { $_.Position -eq 2 })[0]
        [string]$s2.DecisionStatus | Should Be 'REVIEW'
        [string]$s2.ClientId | Should Be 'PDF-C2'

        $s3 = @($stops | Where-Object { $_.Position -eq 3 })[0]
        [string]$s3.DecisionStatus | Should Be 'MATCH'
        [string]$s3.ClientId | Should Be 'PDF-C3'
    }

    It "Merge-EntityTournees : parametre B l'emporte sur le store disque A (sans lecture store si -HumanResolvedMatches fourni)" {
        $storePath = Get-HumanResolvedMatchesStorePath
        $hadFile = Test-Path -LiteralPath $storePath
        $previousText = $null
        if ($hadFile) {
            $previousText = [System.IO.File]::ReadAllText($storePath, [System.Text.UTF8Encoding]::new($false))
        }
        try {
            if ($hadFile) {
                Remove-Item -LiteralPath $storePath -Force
            }

            $entStore = New-HmaTestPdfEntity -ClientId 'STORE-OVERRIDE-A' -WorkOrder 'WO1'
            Append-HumanEvent -Action SetResolvedStop -TourneeId 'T-HMA' -Position 1 -FinalEntity $entStore -ResolutionSource 'StoreA' -StorePath $storePath

            $excel = @(New-HmaTestExcelTournee)
            $pdfRm = @(New-HmaTestPdfResolvedMatches)
            $entParam = New-HmaTestPdfEntity -ClientId 'PARAM-OVERRIDE-B' -WorkOrder 'WO1'
            $humanB = @(
                [pscustomobject]@{
                    TourneeId        = 'T-HMA'
                    Position         = 1
                    OriginalStatus   = 'MATCH'
                    ExcelWorkOrder   = 'WO1'
                    ExcelClientId    = 'EXCEL-C1'
                    FinalEntity      = $entParam
                    ResolutionSource = 'ParamB'
                }
            )

            $merged = Merge-EntityTournees -ExcelTournees $excel -ResolvedMatches $pdfRm -HumanResolvedMatches $humanB
            $s1 = @($merged.Tournees[0].Stops | Where-Object { $_.Position -eq 1 })[0]
            [string]$s1.ClientId | Should Be 'PARAM-OVERRIDE-B'
            [string]$s1.ResolutionSource | Should Be 'ParamB'
        }
        finally {
            if ($null -ne $previousText) {
                $dir = [System.IO.Path]::GetDirectoryName($storePath)
                if (-not (Test-Path -LiteralPath $dir)) {
                    [void](New-Item -ItemType Directory -LiteralPath $dir -Force)
                }
                [System.IO.File]::WriteAllText($storePath, $previousText, [System.Text.UTF8Encoding]::new($false))
            }
            elseif (Test-Path -LiteralPath $storePath) {
                Remove-Item -LiteralPath $storePath -Force
            }
        }
    }
}

Describe 'PdfPlanningOptimizer - HumanResolvedMatchesStore (event log)' {

    BeforeAll {
        $script:HrmsOnlyPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\HumanResolvedMatchesStore.ps1' | Resolve-Path
        . $script:HrmsOnlyPath
    }

    function Test-LegacyV1RecordToExpectedResolvedMatch {
        param([object]$Item)
        $fe = $Item.FinalEntity
        $out = [ordered]@{
            TourneeId        = [string]$Item.TourneeId
            Position         = [int]$Item.Position
            FinalEntity      = $fe
            ResolutionSource = [string]$Item.ResolutionSource
        }
        if ($null -ne $Item.PSObject.Properties['OriginalStatus'] -and -not [string]::IsNullOrWhiteSpace([string]$Item.OriginalStatus)) {
            $out['OriginalStatus'] = [string]$Item.OriginalStatus
        }
        if ($null -ne $Item.PSObject.Properties['ExcelWorkOrder'] -and -not [string]::IsNullOrWhiteSpace([string]$Item.ExcelWorkOrder)) {
            $out['ExcelWorkOrder'] = [string]$Item.ExcelWorkOrder
        }
        if ($null -ne $Item.PSObject.Properties['ExcelClientId'] -and $null -ne $Item.ExcelClientId -and '' -ne [string]$Item.ExcelClientId) {
            $out['ExcelClientId'] = [string]$Item.ExcelClientId
        }
        if ($null -ne $Item.PSObject.Properties['UserId']) {
            $out['UserId'] = $Item.UserId
        }
        if ($null -ne $Item.PSObject.Properties['UtcSaved']) {
            $out['UtcSaved'] = [string]$Item.UtcSaved
        }
        return [pscustomobject]$out
    }

    It 'Rebuild-HumanResolvedState : replay identique au contrat snapshot items v1 (équivalence ancien Load)' {
        $logPath = Join-Path $TestDrive 'hrms_events.jsonl'
        $ts = [datetime]::new(2025, 3, 20, 15, 1, 2, 0, [System.DateTimeKind]::Utc)
        $fe = [pscustomobject]@{
            ClientId   = 'SNAP-CLIENT'
            WorkOrder  = 'WO-SNAP'
            WorkOrders = @('WO-SNAP')
        }

        $legacyRow = [pscustomobject]@{
            TourneeId        = 'TSNAP'
            Position         = 7
            FinalEntity      = $fe
            ResolutionSource = 'LegacySnapshot'
            UserId           = 'snapUser'
            UtcSaved         = $ts.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
            OriginalStatus   = 'MATCH'
        }

        $expected = Test-LegacyV1RecordToExpectedResolvedMatch -Item $legacyRow

        Append-HumanEvent -Action SetResolvedStop -TourneeId 'TSNAP' -Position 7 -FinalEntity $fe -ResolutionSource 'LegacySnapshot' `
            -UserId 'snapUser' -Timestamp $ts -OriginalStatus 'MATCH' -StorePath $logPath

        $actual = @(Rebuild-HumanResolvedState -StorePath $logPath)
        $actual.Count | Should Be 1
        $a = $actual[0]
        [string]$a.TourneeId | Should Be ([string]$expected.TourneeId)
        [int]$a.Position | Should Be ([int]$expected.Position)
        [string]$a.FinalEntity.ClientId | Should Be ([string]$expected.FinalEntity.ClientId)
        [string]$a.ResolutionSource | Should Be ([string]$expected.ResolutionSource)
        [string]$a.OriginalStatus | Should Be ([string]$expected.OriginalStatus)
        [string]$a.UserId | Should Be ([string]$expected.UserId)
        $ua = [datetime]::Parse([string]$a.UtcSaved, $null, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        $ue = [datetime]::Parse([string]$expected.UtcSaved, $null, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        $ua.Ticks | Should Be $ue.Ticks

        [int]$a.ReplayContractVersion | Should Be (Get-HumanReplayContractVersion)
        [string]$a.EngineVersion | Should Be ([string](Get-HumanReplayEngineFingerprint))
    }

    It 'Rebuild-HumanResolvedState : deux replays consécutifs identiques (champs résolus + contrat)' {
        $logPath = Join-Path $TestDrive 'replay_idem.jsonl'
        $ts = [datetime]::new(2024, 11, 5, 8, 0, 0, 0, [System.DateTimeKind]::Utc)
        $fe1 = [pscustomobject]@{ ClientId = 'R1'; WorkOrder = 'W-R1'; WorkOrders = @('W-R1') }
        $fe2 = [pscustomobject]@{ ClientId = 'R2'; WorkOrder = 'W-R2'; WorkOrders = @('W-R2') }

        Append-HumanEvent -Action SetResolvedStop -TourneeId 'TRID' -Position 1 -FinalEntity $fe1 -ResolutionSource 'Init' -Timestamp $ts -StorePath $logPath
        Append-HumanEvent -Action SetResolvedStop -TourneeId 'TRID' -Position 2 -FinalEntity $fe2 -ResolutionSource 'Init' -Timestamp $ts -StorePath $logPath

        $first = @(Rebuild-HumanResolvedState -StorePath $logPath)
        $second = @(Rebuild-HumanResolvedState -StorePath $logPath)

        $first.Count | Should Be $second.Count
        $first.Count | Should Be 2
        $fp = [string](Get-HumanReplayEngineFingerprint)
        $cv = [int](Get-HumanReplayContractVersion)
        for ($i = 0; $i -lt $first.Count; $i++) {
            $x = $first[$i]
            $y = $second[$i]
            [string]$x.TourneeId | Should Be ([string]$y.TourneeId)
            [int]$x.Position | Should Be ([int]$y.Position)
            [string]$x.FinalEntity.ClientId | Should Be ([string]$y.FinalEntity.ClientId)
            [string]$x.ResolutionSource | Should Be ([string]$y.ResolutionSource)
            [int]$x.ReplayContractVersion | Should Be $cv
            [int]$y.ReplayContractVersion | Should Be $cv
            [string]$x.EngineVersion | Should Be $fp
            [string]$y.EngineVersion | Should Be $fp
        }
    }

    It 'Get-HumanEvents : dernier SetResolvedStop gagne ; tri déterministe' {
        $logPath = Join-Path $TestDrive 'order.jsonl'
        $base = [datetime]::UtcNow.Date
        Append-HumanEvent -Action SetResolvedStop -TourneeId 'TA' -Position 1 -FinalEntity ([pscustomobject]@{ ClientId = '1' }) -ResolutionSource 'S' -Timestamp ($base.AddHours(1)) -StorePath $logPath
        Append-HumanEvent -Action SetResolvedStop -TourneeId 'TA' -Position 1 -FinalEntity ([pscustomobject]@{ ClientId = '2' }) -ResolutionSource 'S' -Timestamp ($base.AddHours(2)) -StorePath $logPath
        $ev = @(Get-HumanEvents -StorePath $logPath)
        $ev.Count | Should Be 2
        $ev[0].Timestamp | Should Not Be $null
        $re = @(Rebuild-HumanResolvedState -StorePath $logPath)
        [string]$re[0].FinalEntity.ClientId | Should Be '2'
        [int]$re[0].ReplayContractVersion | Should Be (Get-HumanReplayContractVersion)
        [string]$re[0].EngineVersion | Should Be ([string](Get-HumanReplayEngineFingerprint))
    }
}

Describe 'PdfPlanningOptimizer - ReplayDiffEngine' {

    BeforeAll {
        $script:RdePath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\ReplayDiffEngine.ps1' | Resolve-Path
        . $script:RdePath
    }

    It 'Invoke-ReplayDiffEngineSelfTest reussit (ClientId detecte)' {
        (Invoke-ReplayDiffEngineSelfTest) | Should Be $true
    }

    It 'Compare-HumanReplayStates : deux arrets identiques sauf ClientId (valeurs distinctes) -> FieldLevelDiffs contient ClientId' {
        $sA = [pscustomobject]@{
            Position   = 2
            ClientId   = 'CLIENT-AAA'
            WorkOrder  = 'WO-ZZ'
            Address    = '10 rue Test'
            Date       = '2026-01-15'
            ClientName = 'Societe X'
        }
        $sB = [pscustomobject]@{
            Position   = 2
            ClientId   = 'CLIENT-BBB'
            WorkOrder  = 'wo-zz'
            Address    = '10 rue Test'
            Date       = '2026-01-15'
            ClientName = 'Societe X'
        }
        $rA = [pscustomobject]@{ Tournees = @([pscustomobject]@{ TourneeId = 'TDIF'; Stops = @($sA) }) }
        $rB = [pscustomobject]@{ Tournees = @([pscustomobject]@{ TourneeId = 'TDIF'; Stops = @($sB) }) }
        $d = Compare-HumanReplayStates -ReplayA $rA -ReplayB $rB
        @($d.FieldLevelDiffs | Where-Object { $_.Field -eq 'ClientId' }).Count | Should Be 1
        [int]$d.Summary.FieldImpact.ClientId | Should Be 1
    }
}

Describe 'PdfPlanningOptimizer - tournee cover (prestations speciales ODM)' {

    BeforeAll {
        $scalarPath = Join-Path $PSScriptRoot '..\src\Common\ScalarGuard.ps1' | Resolve-Path
        $sortSafePath = Join-Path $PSScriptRoot '..\src\Common\SortSafe.ps1' | Resolve-Path
        $segPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\PlanningExcelTourneeSegments.ps1' | Resolve-Path
        $metierPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\CnsPdfMetierPrestation.ps1' | Resolve-Path
        $coverComposerPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\PdfTourneeCoverComposer.ps1' | Resolve-Path
        . ([string]$scalarPath)
        . ([string]$sortSafePath)
        . ([string]$segPath)
        . ([string]$metierPath)
        . ([string]$coverComposerPath)
    }

    It 'Get-CnsPdfPageMetierAnalysis : Track dechet DEEE (PDF, tolerant)' {
        $wo = [pscustomobject]@{
            ClientName = 'HOPITAL CHAMBERY'
            Services   = @(@{ Type = 'Tri Déee express'; ODM = '1234567-1' })
        }
        $a = Get-CnsPdfPageMetierAnalysis -PageEntity $null -WorkOrderEntity $wo
        $a.TrackDechetEntries.Count | Should BeGreaterThan 0
        ($a.TrackDechetEntries[0].Detail) | Should Be 'Collecte DEEE'
    }

    It 'Get-CnsPdfPageMetierAnalysis : destruction cert + memo client' {
        $wo = [pscustomobject]@{
            ClientName = 'EUROFINS LABAZUR'
            WorkOrder  = '5517128'
            Services   = @(@{ Type = 'Destruction confidentielle de Papier'; ODM = '5517128-19811636' })
        }
        $a = Get-CnsPdfPageMetierAnalysis -PageEntity $null -WorkOrderEntity $wo
        $a.RequiresDestructionCertificate | Should Be $true
        $a.DestructionMemoClient | Should Be 'EUROFINS LABAZUR'
    }

    It 'Test-CnsPdfFragPageRequiresCeaDocument : CEA ligne complete avec tirets' {
        $lines = @('CEA - Service Logistique et Environnement (SLE) - N°24531')
        (Test-CnsPdfFragPageRequiresCeaDocument -RawLines $lines) | Should Be $true
    }

    It 'Test-CnsPdfFragPageRequiresCeaDocument : variante compacte SERVICE LOGISTIQUE SLE' {
        $lines = @('CEA SERVICE LOGISTIQUE ENVIRONNEMENT SLE 24531')
        (Test-CnsPdfFragPageRequiresCeaDocument -RawLines $lines) | Should Be $true
    }

    It 'Test-CnsPdfFragPageRequiresCeaDocument : numero 24 531 espace' {
        $lines = @('CEA - SLE - N° 24 531')
        (Test-CnsPdfFragPageRequiresCeaDocument -RawLines $lines) | Should Be $true
    }

    It 'Test-CnsPdfFragPageRequiresCeaDocument : non-CEA si 24531 seul sans cea' {
        $lines = @('MAIRIE GRENOBLE 24531')
        (Test-CnsPdfFragPageRequiresCeaDocument -RawLines $lines) | Should Be $false
    }

    It 'Test-CnsCeaNormalizedTextIsCeaPoint : refuse cea+24531 sans sle ni service logistique' {
        (Test-CnsCeaNormalizedTextIsCeaPoint -NormalizedText 'cea collecte 24531') | Should Be $false
    }

    It 'Test-CnsPdfFragPageRequiresCeaDocument : lignes PDF fragmentees (frag slice)' {
        $lines = @(
            'CEA - Service Logistique et'
            'Environnement (SLE) - N°24531'
        )
        (Test-CnsPdfFragPageRequiresCeaDocument -RawLines $lines) | Should Be $true
    }

    It 'Get-CnsCeaPageSignalsFromNormalizedText : ordre inverse des signaux sur la page' {
        $norm = ConvertTo-CnsCeaDetectionNormalizedText -Text @(
            'Environnement (SLE) - N° 24 531',
            'CEA - Service Logistique et'
        ) -join ' '
        $sig = Get-CnsCeaPageSignalsFromNormalizedText -NormalizedText $norm
        $sig.HasCEA | Should Be $true
        $sig.HasID | Should Be $true
        $sig.HasSLE | Should Be $true
        $sig.IsCea | Should Be $true
    }

    It 'Get-CnsCeaPageSignalsFromNormalizedText : service logistique et environnement sans mot sle' {
        $norm = ConvertTo-CnsCeaDetectionNormalizedText -Text 'CEA service logistique et environnement 24531'
        $sig = Get-CnsCeaPageSignalsFromNormalizedText -NormalizedText $norm
        $sig.HasSLE | Should Be $true
        $sig.IsCea | Should Be $true
    }

    It 'Test-CnsPdfFragPageRequiresCeaDocument : variante No et espaces' {
        $lines = @('CEA - Service Logistique et Environnement (SLE) - No 24531')
        (Test-CnsPdfFragPageRequiresCeaDocument -RawLines $lines) | Should Be $true
    }

    It 'Get-CnsTourneeMetierMemoLinesForBlock : ordre certificat puis track dechet' {
        $wo = [pscustomobject]@{
            ClientName = 'MAIRIE GRENOBLE'
            WorkOrder  = '1111111'
            Services   = @(@{ Type = 'RAMASSAGE PILES'; ODM = '1111111-2' })
            Pages      = @(1)
        }
        $pairs = @([pscustomobject]@{ FinalOrder = 1; RawPageNum = 1 })
        $foLine = [pscustomobject]@{ FinalOrder = 1; Source = 'ExcelOrder'; ExcelSourceOrder = 3 }
        $foToLine = @{ 1 = $foLine }
        $memos = @(Get-CnsTourneeMetierMemoLinesForBlock -MainFrom1 1 -MainTo1 1 -SortedGsPairs $pairs -FinalOrderToLine $foToLine -WorkOrders @($wo) -PdfEntities @())
        ($memos -join '|') | Should Match 'Track dechet'
        ($memos -join '|') | Should Match 'MAIRIE GRENOBLE'
    }

    It 'Get-CnsPlanningWorkOrderKeyFromMatchWorkOrderField : entite vs chaine' {
        $ent = [pscustomobject]@{ WorkOrder = 'WO-99' }
        Get-CnsPlanningWorkOrderKeyFromMatchWorkOrderField -WorkOrderField $ent | Should Be 'WO-99'
        Get-CnsPlanningWorkOrderKeyFromMatchWorkOrderField -WorkOrderField '  AB  ' | Should Be 'AB'
    }

    It 'Test-CnsWorkOrderRequiresDestructionCertificate : bloc Destruction + meme WorkOrderId' {
        $wo = [pscustomobject]@{
            WorkOrder = '5517128'
            Services  = @(
                @{ Type = 'Collecte de papier'; ODM = '5517128-19811616' },
                @{ Type = 'Destruction confidentielle de Papier'; ODM = '5517128-19811636' }
            )
        }
        (Test-CnsWorkOrderRequiresDestructionCertificate -WorkOrderEntity $wo) | Should Be $true
        (Get-CnsWorkOrderBaseIdFromEntity -WorkOrderEntity $wo) | Should Be '5517128'
    }

    It 'Test-CnsWorkOrderRequiresDestructionCertificate : refuse mot destruction seul dans ODM' {
        $wo = [pscustomobject]@{
            WorkOrder = '5517128'
            Services  = @(@{ Type = 'Collecte de papier'; ODM = '5517128-19811636 destruction' })
        }
        (Test-CnsWorkOrderRequiresDestructionCertificate -WorkOrderEntity $wo) | Should Be $false
    }

    It 'Resolve-CnsWorkOrderEntityForStep5 : PDF WorkOrders par page physique (PdfFallback)' {
        $wo = [pscustomobject]@{
            WorkOrder  = '5517128'
            ClientName = 'Site Non Match'
            ClientID   = '99'
            Services   = @(@{ Type = 'Destruction confidentielle de Papier'; ODM = '5517128-19811636' })
            Pages      = @(3)
            Address    = @{ Street = ''; PostalCode = ''; City = '' }
        }
        $gsPair = [pscustomobject]@{ FinalOrder = 1; RawPageNum = 3; Ordinal = 1 }
        $foLine = [pscustomobject]@{ FinalOrder = 1; Source = 'PdfFallback'; ExcelSourceOrder = $null }
        $foToLine = @{ 1 = $foLine }
        $resolved = Resolve-CnsWorkOrderEntityForStep5 -GsPair $gsPair -FinalOrderToLine $foToLine -OrderToWorkOrder @{} -WorkOrders @($wo) -PdfEntities @()
        $null -ne $resolved | Should Be $true
        (Test-CnsPdfPageRequiresDestructionCertificate -PageEntity $null -WorkOrderEntity $resolved) | Should Be $true
    }
}

Describe 'PdfPlanningOptimizer - certificat destruction Word' {

    BeforeAll {
        $wordCertPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\CnsDestructionCertificateWord.ps1' | Resolve-Path
        . ([string]$wordCertPath)
    }

    It 'Get-CnsDestructionCertificateTemplatePath : fichier repo templates' {
        $p = Get-CnsDestructionCertificateTemplatePath
        if ($null -eq $p) {
            Set-ItResult -Inconclusive -Because 'Template CertificatDeDestruction.docx absent du depot'
        }
        else {
            (Test-Path -LiteralPath $p) | Should Be $true
        }
    }

    It 'ConvertTo-CnsDestructionCertificatePlaceholderValue : sentinelles -> vide' {
        (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value 'INCONNU') | Should Be ''
        (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value 'NON SPECIFIE') | Should Be ''
        (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value 'À compléter') | Should Be ''
        (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value '-') | Should Be ''
        (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value 'Jean Martin') | Should Be 'Jean Martin'
    }

    It 'Get-CnsDestructionCertificatePlaceholders : champs client et collecteur' {
        $wo = [pscustomobject]@{
            ClientID   = '12345'
            ClientName = 'Client Test'
            WorkOrder  = 'WO-777'
            VisitDate  = [datetime]'2026-04-17'
            Address    = @{ Street = '1 rue A'; PostalCode = '75001'; City = 'Paris' }
            Services   = @()
        }
        $seg = [pscustomobject]@{ DateJJMMAAAA = '18/04/2026'; Collecteur = 'Jean Martin'; Vehicule = 'AB-123-CD' }
        $ph = Get-CnsDestructionCertificatePlaceholders -WorkOrderEntity $wo -SegmentMeta $seg -VisitDate ([datetime]'2026-01-01')
        $ph.Client_ID | Should Be '12345'
        $ph.Client_Nom | Should Be 'Client Test'
        $ph.Collecteur_Prenom | Should Be 'Jean'
        $ph.Collecteur_Nom | Should Be 'Martin'
        $ph.Vehicule_Immat | Should Be 'AB-123-CD'
        $ph.ODM_Numero | Should Be 'WO-777'
        $ph.Date_Collecte | Should Be '01/01/2026'
    }

    It 'Get-CnsDestructionCertificatePlaceholders : collecteur/vehicule sentinelles Excel -> vide' {
        $wo = [pscustomobject]@{
            ClientID   = '1'
            ClientName = 'Client'
            WorkOrder  = 'WO-1'
            Services   = @()
            Address    = @{ Street = ''; PostalCode = ''; City = '' }
        }
        $seg = [pscustomobject]@{ DateJJMMAAAA = '01/01/2026'; Collecteur = 'INCONNU'; Vehicule = 'NON SPECIFIE' }
        $ph = Get-CnsDestructionCertificatePlaceholders -WorkOrderEntity $wo -SegmentMeta $seg -VisitDate ([datetime]'2026-01-01')
        $ph.Collecteur_Nom | Should Be ''
        $ph.Collecteur_Prenom | Should Be ''
        $ph.Vehicule_Immat | Should Be ''
    }

    It 'Split-CnsCollecteurNomPrenom : un seul mot' {
        $r = Split-CnsCollecteurNomPrenom -CollecteurText 'Dupont'
        $r.Nom | Should Be 'Dupont'
        $r.Prenom | Should Be ''
    }

    It 'Resolve-CnsCollecteurFieldsForCertificate : prenom Excel, nom BDD si match prenom' {
        $script:CnsCertAgentCatalog = @(
            [pscustomobject]@{ nom = 'MARTIN-BDD'; prenom = 'Jean'; poste = 'Collecteur' },
            [pscustomobject]@{ nom = 'AUTRE'; prenom = 'Jean'; poste = 'Trieur' }
        )
        $r = Resolve-CnsCollecteurFieldsForCertificate -CollecteurExcelRaw 'Jean Martin Excel'
        $r.Prenom | Should Be 'Jean'
        $r.Nom | Should Be 'MARTIN-BDD'
    }

    It 'Resolve-CnsCollecteurFieldsForCertificate : fallback split Excel sans BDD' {
        $script:CnsCertAgentCatalog = @()
        $r = Resolve-CnsCollecteurFieldsForCertificate -CollecteurExcelRaw 'Paul Durand'
        $r.Prenom | Should Be 'Paul'
        $r.Nom | Should Be 'Durand'
    }

    It 'Get-CnsLibreOfficeSofficePath : soffice.exe present ou inconclusive' {
        $p = Get-CnsLibreOfficeSofficePath
        if ($null -eq $p) {
            Set-ItResult -Inconclusive -Because 'LibreOffice non installe sur cette machine'
        }
        else {
            (Test-Path -LiteralPath $p) | Should Be $true
        }
    }

    It 'Set-CnsDocxTemplatePlaceholders : remplace balises w:t sans casser structure OOXML' {
        $tpl = Get-CnsDestructionCertificateTemplatePath
        if ($null -eq $tpl) {
            Set-ItResult -Inconclusive -Because 'Template CertificatDeDestruction.docx absent'
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $tplUnzip = Join-Path $env:TEMP ("cn_pester_tpl_{0}" -f ([Guid]::NewGuid().ToString('N')))
        [System.IO.Compression.ZipFile]::ExtractToDirectory($tpl, $tplUnzip)
        $tplDocXml = Join-Path $tplUnzip 'word\document.xml'
        $tplXml = [xml](Get-Content -LiteralPath $tplDocXml -Raw -Encoding UTF8)
        $ns = New-Object System.Xml.XmlNamespaceManager($tplXml.NameTable)
        [void]$ns.AddNamespace('w', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main')
        $drawingsBefore = @($tplXml.SelectNodes('//w:drawing', $ns)).Count
        $txbxBefore = @($tplXml.SelectNodes('//w:txbxContent', $ns)).Count
        $hasMedia = Test-Path -LiteralPath (Join-Path $tplUnzip 'word\media\image1.png')

        $work = Join-Path $env:TEMP ("cn_pester_cert_{0}.docx" -f ([Guid]::NewGuid().ToString('N')))
        Copy-Item -LiteralPath $tpl -Destination $work -Force
        $ph = @{
            Date_Collecte     = '01/02/2026'
            Client_Nom        = 'ACME TEST'
            Client_Adresse    = '10 rue Test'
            Client_CP         = '75002'
            Client_Ville      = 'Paris'
            Collecteur_Nom    = 'DUPONT'
            Collecteur_Prenom = 'Jean'
            Client_ID         = '99999'
            ODM_Numero        = 'ODM-TEST'
            Vehicule_Immat    = 'AB-001-CD'
        }
        $ok = Set-CnsDocxTemplatePlaceholders -DocxPath $work -Placeholders $ph
        $ok | Should Be $true

        $unzip = Join-Path $env:TEMP ("cn_pester_unzip_{0}" -f ([Guid]::NewGuid().ToString('N')))
        [System.IO.Compression.ZipFile]::ExtractToDirectory($work, $unzip)
        $docXml = Join-Path $unzip 'word\document.xml'
        (Test-Path -LiteralPath $docXml) | Should Be $true
        $xml = [xml](Get-Content -LiteralPath $docXml -Raw -Encoding UTF8)
        $ns2 = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        [void]$ns2.AddNamespace('w', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main')
        @($xml.SelectNodes('//w:drawing', $ns2)).Count | Should Be $drawingsBefore
        @($xml.SelectNodes('//w:txbxContent', $ns2)).Count | Should Be $txbxBefore
        if ($hasMedia) {
            (Test-Path -LiteralPath (Join-Path $unzip 'word\media\image1.png')) | Should Be $true
        }
        $plain = (($xml.SelectNodes('//w:t', $ns2) | ForEach-Object { $_.InnerText }) -join '')
        $plain.Contains('{{') | Should Be $false
        $plain.Contains('ACME TEST') | Should Be $true
        $plain.Contains('DUPONT') | Should Be $true
        Remove-Item -LiteralPath $unzip -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tplUnzip -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $work -Force -ErrorAction SilentlyContinue
    }
}

Describe 'PdfPlanningOptimizer - fusion PDF certificat (structure-preserving)' {

    BeforeAll {
        $mergePath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\CnsPdfStructureMerge.ps1' | Resolve-Path
        $wordPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\CnsDestructionCertificateWord.ps1' | Resolve-Path
        . ([string]$mergePath)
        . ([string]$wordPath)
    }

    It 'Test-CnsPdfPathIsDestructionCertificateFragment : detecte cert_dest_*.pdf' {
        (Test-CnsPdfPathIsDestructionCertificateFragment -Path 'C:\tmp\cert_dest_001_00001.pdf') | Should Be $true
        (Test-CnsPdfPathIsDestructionCertificateFragment -Path 'C:\tmp\main_slice_001.pdf') | Should Be $false
    }

    It 'Test-CnsPdfPathIsBilanCollecteFragment : detecte bilan_seg_*.pdf' {
        (Test-CnsPdfPathIsBilanCollecteFragment -Path 'C:\tmp\bilan_seg_001.pdf') | Should Be $true
        (Test-CnsPdfPathIsBilanCollecteFragment -Path 'C:\tmp\cert_dest_001.pdf') | Should Be $false
    }

    It 'Test-CnsPdfPathIsLibreOfficeStep5Fragment : certificat ou bilan' {
        (Test-CnsPdfPathIsLibreOfficeStep5Fragment -Path 'C:\tmp\bilan_seg_002.pdf') | Should Be $true
        (Test-CnsPdfPathIsLibreOfficeStep5Fragment -Path 'C:\tmp\cover_blk_001.pdf') | Should Be $false
    }

    It 'Merge-CnsPdfFilesForStep5TourneeComposition : preserve ToUnicode certificat LO apres qpdf' {
        $qpdf = Get-CnsQpdfExecutablePath
        if ($null -eq $qpdf) {
            Write-Host 'INCONCLUSIVE: qpdf non installe (CN_QPDF_EXE ou PATH requis pour fusion certificat)' -ForegroundColor Yellow
            return
        }
        $tpl = Get-CnsDestructionCertificateTemplatePath
        if ($null -eq $tpl) {
            Write-Host 'INCONCLUSIVE: template certificat absent' -ForegroundColor Yellow
            return
        }
        if (-not (Get-CnsLibreOfficeSofficePath)) {
            Write-Host 'INCONCLUSIVE: LibreOffice absent' -ForegroundColor Yellow
            return
        }
        $docx = Join-Path $env:TEMP ("cn_pester_merge_{0}.docx" -f ([Guid]::NewGuid().ToString('N')))
        $certPdf = Join-Path $env:TEMP ("cert_dest_001_00001.pdf")
        $dummyPdf = Join-Path $env:TEMP ("cn_pester_dummy_{0}.pdf" -f ([Guid]::NewGuid().ToString('N')))
        $merged = Join-Path $env:TEMP ("cn_pester_merged_{0}.pdf" -f ([Guid]::NewGuid().ToString('N')))
        Copy-Item -LiteralPath $tpl -Destination $docx -Force
        $ph = @{
            Date_Collecte = '01/01/2026'; Client_Nom = 'ACME'; Client_Adresse = '1 rue'
            Client_CP = '75001'; Client_Ville = 'Paris'; Collecteur_Nom = 'DUPONT'; Collecteur_Prenom = 'Jean'
        }
        Set-CnsDocxTemplatePlaceholders -DocxPath $docx -Placeholders $ph | Should Be $true
        (Convert-DocxToPdfUsingLibreOffice -DocxPath $docx -PdfPath $certPdf) | Should Be $true
        Copy-Item -LiteralPath $certPdf -Destination $dummyPdf -Force
        $before = Get-CnsPdfFontStructureMarkers -PdfPath $certPdf
        $before.ToUnicode | Should BeGreaterThan 0
        $before.FontFile2 | Should BeGreaterThan 0
        $ok = Merge-CnsPdfFilesForStep5TourneeComposition -InputPdfsOrdered @($dummyPdf, $certPdf) -DestinationPdfPath $merged
        $ok | Should Be $true
        $after = Get-CnsPdfFontStructureMarkers -PdfPath $merged
        $after.ToUnicode | Should BeGreaterThan 0
        $after.FontFile2 | Should BeGreaterThan 0
        Remove-Item -LiteralPath $docx,$certPdf,$dummyPdf,$merged -Force -ErrorAction SilentlyContinue
    }
}

Describe 'PdfPlanningOptimizer - bilan collecte Word' {

    BeforeAll {
        $bilanPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\CnsBilanCollecteWord.ps1' | Resolve-Path
        . ([string]$bilanPath)
    }

    It 'Get-CnsBilanCollectePlaceholders : date segment et collecteur' {
        $seg = [pscustomobject]@{
            DisplayDateJM = '18/04/2026'
            TourDate      = [datetime]'2026-04-18'
            Collecteur    = 'Jean Martin'
            Vehicule      = 'AB-123-CD'
        }
        $ph = Get-CnsBilanCollectePlaceholders -SegmentMeta $seg -VisitDate ([datetime]'2026-01-01')
        $ph.Date_Collecte | Should Be '18/04/2026'
        $ph.Collecteur_Prenom | Should Be 'Jean'
        $ph.Collecteur_Nom | Should Be 'Martin'
    }

    It 'Get-CnsBilanCollectePlaceholders : collecteur sentinelles Excel -> vide' {
        $seg = [pscustomobject]@{ DisplayDateJM = '01/01/2026'; Collecteur = 'INCONNU' }
        $ph = Get-CnsBilanCollectePlaceholders -SegmentMeta $seg -VisitDate ([datetime]'2026-01-01')
        $ph.Collecteur_Nom | Should Be ''
        $ph.Collecteur_Prenom | Should Be ''
    }

    It 'Set-CnsDocxTemplatePlaceholders : remplace balises BilanDeCollecte.docx' {
        $tpl = Get-CnsBilanCollecteTemplatePath
        if ($null -eq $tpl) {
            Set-ItResult -Inconclusive -Because 'Template BilanDeCollecte.docx absent'
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $work = Join-Path $env:TEMP ("cn_pester_bilan_{0}.docx" -f ([Guid]::NewGuid().ToString('N')))
        Copy-Item -LiteralPath $tpl -Destination $work -Force
        $ph = @{
            Date_Collecte     = '15/03/2026'
            Collecteur_Nom    = 'DURAND'
            Collecteur_Prenom = 'Paul'
        }
        $ok = Set-CnsDocxTemplatePlaceholders -DocxPath $work -Placeholders $ph
        $ok | Should Be $true
        $unzip = Join-Path $env:TEMP ("cn_pester_bilan_unzip_{0}" -f ([Guid]::NewGuid().ToString('N')))
        [System.IO.Compression.ZipFile]::ExtractToDirectory($work, $unzip)
        $docXml = Join-Path $unzip 'word\document.xml'
        $plain = ([regex]::Matches([System.IO.File]::ReadAllText($docXml), '<w:t[^>]*>([^<]*)</w:t>') | ForEach-Object { $_.Groups[1].Value }) -join ''
        $plain.Contains('{{') | Should Be $false
        $plain.Contains('DURAND') | Should Be $true
        $plain.Contains('15/03/2026') | Should Be $true
        Remove-Item -LiteralPath $unzip,$work -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Merge-CnsPdfFilesForStep5TourneeComposition : preserve ToUnicode bilan LO apres qpdf' {
        $mergePath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\CnsPdfStructureMerge.ps1' | Resolve-Path
        . ([string]$mergePath)
        $qpdf = Get-CnsQpdfExecutablePath
        if ($null -eq $qpdf) {
            Write-Host 'INCONCLUSIVE: qpdf non installe' -ForegroundColor Yellow
            return
        }
        $tpl = Get-CnsBilanCollecteTemplatePath
        if ($null -eq $tpl -or -not (Get-CnsLibreOfficeSofficePath)) {
            Write-Host 'INCONCLUSIVE: template bilan ou LibreOffice absent' -ForegroundColor Yellow
            return
        }
        $docx = Join-Path $env:TEMP ("cn_pester_bilan_merge_{0}.docx" -f ([Guid]::NewGuid().ToString('N')))
        $bilanPdf = Join-Path $env:TEMP 'bilan_seg_001.pdf'
        $dummyPdf = Join-Path $env:TEMP ("cn_pester_dummy_bilan_{0}.pdf" -f ([Guid]::NewGuid().ToString('N')))
        $merged = Join-Path $env:TEMP ("cn_pester_merged_bilan_{0}.pdf" -f ([Guid]::NewGuid().ToString('N')))
        Copy-Item -LiteralPath $tpl -Destination $docx -Force
        Set-CnsDocxTemplatePlaceholders -DocxPath $docx -Placeholders @{
            Date_Collecte = '01/01/2026'; Collecteur_Nom = 'TEST'; Collecteur_Prenom = 'Jean'
        } | Should Be $true
        (Convert-DocxToPdfUsingLibreOffice -DocxPath $docx -PdfPath $bilanPdf) | Should Be $true
        Copy-Item -LiteralPath $bilanPdf -Destination $dummyPdf -Force
        $before = Get-CnsPdfFontStructureMarkers -PdfPath $bilanPdf
        $before.ToUnicode | Should BeGreaterThan 0
        $before.FontFile2 | Should BeGreaterThan 0
        $ok = Merge-CnsPdfFilesForStep5TourneeComposition -InputPdfsOrdered @($dummyPdf, $bilanPdf) -DestinationPdfPath $merged
        $ok | Should Be $true
        $after = Get-CnsPdfFontStructureMarkers -PdfPath $merged
        $after.ToUnicode | Should BeGreaterThan 0
        $after.FontFile2 | Should BeGreaterThan 0
        Remove-Item -LiteralPath $docx,$bilanPdf,$dummyPdf,$merged -Force -ErrorAction SilentlyContinue
    }
}

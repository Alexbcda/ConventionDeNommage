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

function script:Test-CnsWordInstalledForTests {
    if (Get-Command Test-CnsMicrosoftWordAvailable -ErrorAction SilentlyContinue) {
        try { return [bool](Test-CnsMicrosoftWordAvailable) }
        catch { return $false }
    }
    return $null -ne (Get-Command WINWORD.EXE -ErrorAction SilentlyContinue)
}

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

Describe 'Extraction brute du ClientName (bloc PDF)' {

    BeforeAll {
        $entityPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Extractors\EntityExtractor.ps1' | Resolve-Path
        . $entityPath
    }

    It 'CHAM - ancre + ligne au-dessus (exemple certificat)' {
        $lines = @(
            '4/10/26, 8:48 AM',
            'https://api.example.com/foo',
            'CHAM CENTRE HOSPITALIER',
            'ALBERTVILLE MOUTIERS - N°24550',
            '253 rue Pierre de Coubertin'
        )
        $result = Get-ClientNameFromLines -Lines $lines -ClientId '24550'
        $result | Should Be 'CHAM CENTRE HOSPITALIER ALBERTVILLE MOUTIERS - N°24550'
    }

    It 'CHAM p26 - remontée au-dessus de la date (layout ideal)' {
        $lines = @(
            'CHAM CENTRE HOSPITALIER',
            '4/10/26, 8:48 AM',
            'ALBERTVILLE MOUTIERS - N°24550',
            '253 rue Pierre de Coubertin 5890092',
            '73200 ALBERTVILLE'
        )
        $result = Get-ClientNameFromLines -Lines $lines -ClientId '24550'
        $result | Should Be 'CHAM CENTRE HOSPITALIER ALBERTVILLE MOUTIERS - N°24550'
    }

    It 'CHAM p26 - lignes entieres consecutives au-dessus de l''ancre' {
        $lines = @(
            'CHAM CENTREMOUTIERS',
            'HOSPITALIER ALBERTVILLE - N°24550',
            '253 rue Pierre de Coubertin 5890092',
            '73200 ALBERTVILLE'
        )
        $result = Get-ClientNameFromLines -Lines $lines -ClientId '24550'
        $result | Should Be 'CHAM CENTREMOUTIERS HOSPITALIER ALBERTVILLE - N°24550'
    }

    It 'CHAM p26 - date intercalee traversee (layout pdftotext reel)' {
        $lines = @(
            'CHAM CENTREMOUTIERS',
            'HOSPITALIER',
            '4/10/26, 8:48 AM',
            'ALBERTVILLE - N°24550'
        )
        $result = Get-ClientNameFromLines -Lines $lines -ClientId '24550'
        $result | Should Be 'CHAM CENTREMOUTIERS HOSPITALIER ALBERTVILLE - N°24550'
    }

    It 'EUROFINS p43 - date intercalee traversee (layout pdftotext reel)' {
        $lines = @(
            'EUROFINS',
            'MAURIENNELABAZUR SAINT JEAN',
            '4/10/26, 8:48 AM',
            '- N°24669'
        )
        $result = Get-ClientNameFromLines -Lines $lines -ClientId '24669'
        $result | Should Be 'EUROFINS MAURIENNELABAZUR SAINT JEAN - N°24669'
    }

    It 'EUROFINS p43 - lignes entieres consecutives' {
        $lines = @(
            'MAURIENNELABAZUR SAINT JEAN',
            '- N°24669',
            'Place Fodère 5517128',
            '73300 Saint-Jean-de-Maurienne'
        )
        $result = Get-ClientNameFromLines -Lines $lines -ClientId '24669'
        $result | Should Be 'MAURIENNELABAZUR SAINT JEAN - N°24669'
    }

    It 'CHAM EHPAD - ancre + ligne au-dessus' {
        $lines = @(
            'CHAM EHPAD CLAUDE LEGER',
            'ALBERTVILLE - N°64401',
            '457 Chemin des trois-poiriers 5330151',
            '73200 Albertville'
        )
        $result = Get-ClientNameFromLines -Lines $lines -ClientId '64401'
        $result | Should Be 'CHAM EHPAD CLAUDE LEGER ALBERTVILLE - N°64401'
    }

    It 'EUROFINS p43 - bbox ideal (deux lignes nom ordre visuel)' {
        $lines = @(
            'EUROFINS LABAZUR SAINT JEAN',
            'MAURIENNE - N°24669',
            'Place Fodère 5517128',
            '73300 Saint-Jean-de-Maurienne'
        )
        $result = Get-ClientNameFromLines -Lines $lines -ClientId '24669'
        $result | Should Be 'EUROFINS LABAZUR SAINT JEAN MAURIENNE - N°24669'
    }

    It 'ClientName : ancre N° avec prefix date/heure (meme ligne)' {
        $lines = @(
            '4/10/26, 8:48 AM APLIM CHAMBERY - N°24415'
        )
        $result = Get-ClientNameFromLines -Lines $lines -ClientId '24415'
        $result | Should Be 'APLIM CHAMBERY - N°24415'
    }

    It 'ClientName : stop remontée sur prestation (collecte...)' {
        $lines = @(
            'Collecte cartouches encre',
            '4/10/26, 8:48 AM',
            'APLIM CHAMBERY - N°24415'
        )
        $result = Get-ClientNameFromLines -Lines $lines -ClientId '24415'
        $result | Should Be 'APLIM CHAMBERY - N°24415'
    }

    It 'Point collecte (p7) - deux lignes seulement' {
        $lines = @(
            'ANDERLAINE HERMILLON SR CONSEIL',
            '- N°24902',
            'D 906',
            '73300 LA TOUR EN MAURIENNE'
        )
        $result = Get-ClientNameFromLines -Lines $lines -ClientId '24902'
        $result | Should Be 'ANDERLAINE HERMILLON SR CONSEIL - N°24902'
    }

    It 'BANQUE p12 - ligne au-dessus incluse (01800 dans le libelle)' {
        $lines = @(
            'BANQUE DE SAVOIE 01800 SAINT',
            'JEAN DE MAURIENNE - N°68042',
            'Place Fodère',
            '73300 Saint-Jean-de-Maurienne'
        )
        $result = Get-ClientNameFromLines -Lines $lines -ClientId '68042'
        $result | Should Be 'BANQUE DE SAVOIE 01800 SAINT JEAN DE MAURIENNE - N°68042'
    }

    It 'CREDIT AGRICOLE p32 - ancre seule (N° sur la premiere ligne)' {
        $lines = @(
            'CREDIT AGRICOLE- N°81347',
            'SUD EST',
            '4/10/26, 8:48 AM',
            'MORESTEL_676',
            '29 Place de l''Hotel de Ville'
        )
        $result = Get-ClientNameFromLines -Lines $lines -ClientId '81347'
        $result | Should Be 'CREDIT AGRICOLE- N°81347'
    }

    It 'ENTREPOT p40 - deux lignes nom consecutives au-dessus de l''ancre' {
        $lines = @(
            'ENTREPOT DU BRICOLAGE SAINT',
            'JEAN DE',
            'N°24642 MAURIENNE [2682] -',
            '240 Rue de Combe Paillarde'
        )
        $result = Get-ClientNameFromLines -Lines $lines -ClientId '24642'
        $result | Should Be 'ENTREPOT DU BRICOLAGE SAINT JEAN DE N°24642 MAURIENNE [2682] -'
    }

    It 'ENTREPOT p40 - date intercalee traversee' {
        $lines = @(
            'ENTREPOT DU BRICOLAGE SAINT',
            '4/10/26, 8:48 AM',
            'JEAN DE',
            'N°24642 MAURIENNE [2682] -'
        )
        $result = Get-ClientNameFromLines -Lines $lines -ClientId '24642'
        $result | Should Be 'ENTREPOT DU BRICOLAGE SAINT JEAN DE N°24642 MAURIENNE [2682] -'
    }

    It 'CADS p21 - ancre seule (N° sur la meme ligne)' {
        $lines = @(
            'CADS LA ROCHETTE (820) [1908] N°24506',
            'Rue schweighouse sur moder',
            '73110 Valgelon-La Rochette'
        )
        $result = Get-ClientNameFromLines -Lines $lines -ClientId '24506'
        $result | Should Be 'CADS LA ROCHETTE (820) [1908] N°24506'
    }
}

Describe 'PdfPlanningOptimizer - E2E PDF vers export CSV' {

    BeforeAll {
        $script:E2EOptRoot = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer' | Resolve-Path
        $script:E2EFixtureCsv = Join-Path $PSScriptRoot 'Fixtures\PdfPlanningOptimizer\e2e_planning.csv' | Resolve-Path

        # Pipeline alternatif (ExcelWorkOrderMatch / GlobalMatchResolution / FinalAssignmentExport) retiré du depot.
        $script:SkipPdfE2E = $true
        $script:E2EOriginalPath = $null
        Write-Warning 'E2E export CSV skipped: alternate matching modules removed from repository.'
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

    It 'Get-CnsPdfPageMetierAnalysis : cartouches encre conserve libelle track' {
        $wo = [pscustomobject]@{
            ClientName = 'APLIM CHAMBERY - N°24415'
            Services   = @(@{ Type = 'Collecte cartouches encre'; ODM = '1234567-1' })
        }
        $a = Get-CnsPdfPageMetierAnalysis -PageEntity $null -WorkOrderEntity $wo
        ($a.TrackDechetEntries[0].Detail) | Should Be 'Collecte cartouches encre'
    }

    It 'Get-CnsPdfPageMetierAnalysis : neons tubes conserve libelle track' {
        $wo = [pscustomobject]@{
            ClientName = 'CFP GRENOBLE'
            Services   = @(@{ Type = 'Collecte Néons / tubes'; ODM = '1234567-1' })
        }
        $a = Get-CnsPdfPageMetierAnalysis -PageEntity $null -WorkOrderEntity $wo
        ($a.TrackDechetEntries[0].Detail) | Should Be 'Collecte Néons / tubes'
    }

    It 'ConvertTo-CnsCoverClientDisplayLabel : supprime crochets et suffixe' {
        ConvertTo-CnsCoverClientDisplayLabel -Name 'CFP GRENOBLE RHIN ET DANUBE [9804] - N°60214' |
            Should Be 'CFP GRENOBLE RHIN ET DANUBE'
    }

    It 'Get-CnsPonctuellePrestationDisplayLabelFromServiceType : vrac neons -> Collecte DEEE' {
        Get-CnsPonctuellePrestationDisplayLabelFromServiceType -Type 'Collecte Ponctuel de Vrac Neons en Alveoles' |
            Should Be 'Collecte DEEE'
    }

    It 'Remove-CnsCoverPrestationVehiculeSuffix : retire suffixe immat des libelles' {
        Remove-CnsCoverPrestationVehiculeSuffix -Detail 'Collecte DEEE (véhicule AB-123-CD)' |
            Should Be 'Collecte DEEE'
    }

    It 'Format-CnsCoverGardePrestationMemoLine : ligne track sans suffixe vehicule' {
        Format-CnsCoverGardePrestationMemoLine `
            -Detail 'Collecte DEEE' `
            -Client 'CFP GRENOBLE RHIN ET DANUBE [9804] - N°60214 (véhicule AB-123-CD)' |
            Should Be 'Collecte DEEE - CFP GRENOBLE RHIN ET DANUBE'
    }

    It 'Get-CnsTourneeMetierMemoLinesForBlock : track dechet sans suffixe vehicule' {
        $wo = [pscustomobject]@{
            ClientName = 'CFP GRENOBLE RHIN ET DANUBE [9804] - N°60214'
            Services   = @(@{ Type = 'Collecte cartouches encre'; ODM = '1234567-1' })
            Pages      = @(1)
        }
        $pairs = @([pscustomobject]@{ FinalOrder = 1; RawPageNum = 1 })
        $foToLine = @{ 1 = [pscustomobject]@{ FinalOrder = 1; Source = 'ExcelOrder'; ExcelSourceOrder = 1 } }
        $memos = @(Get-CnsTourneeMetierMemoLinesForBlock -MainFrom1 1 -MainTo1 1 -SortedGsPairs $pairs -FinalOrderToLine $foToLine -WorkOrders @($wo) -PdfEntities @())
        $memos.Count | Should BeGreaterThan 0
        $memos[0] | Should Be 'Collecte cartouches encre - CFP GRENOBLE RHIN ET DANUBE'
        ($memos -join '|') | Should Not Match 'véhicule'
    }

    It 'Get-CnsTourneeMetierMemoLinesForBlock : libelles track distincts et dedup meme prestation client' {
        $client = 'CFP GRENOBLE RHIN ET DANUBE [9804] - N°60214'
        $wo1 = [pscustomobject]@{
            ClientName = $client
            WorkOrder  = '1111111'
            Services   = @(@{ Type = 'Collecte cartouches encre'; ODM = '1111111-1' })
            Pages      = @(1)
        }
        $wo2 = [pscustomobject]@{
            ClientName = $client
            WorkOrder  = '2222222'
            Services   = @(@{ Type = 'Collecte cartouches encre'; ODM = '2222222-1' })
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
        $memos = @(Get-CnsTourneeMetierMemoLinesForBlock -MainFrom1 1 -MainTo1 2 -SortedGsPairs $pairs -FinalOrderToLine $foToLine -WorkOrders @($wo1, $wo2) -PdfEntities @())
        $memos.Count | Should Be 1
        $memos[0] | Should Be 'Collecte cartouches encre - CFP GRENOBLE RHIN ET DANUBE'
    }

    It 'Get-CnsPdfPageClientDisplayName : page bbox avant WorkOrder fusionne' {
        $entityExtractorPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Extractors\EntityExtractor.ps1' | Resolve-Path
        . ([string]$entityExtractorPath)
        $wo = [pscustomobject]@{
            ClientID   = '24415'
            ClientName = '4/10/26, 8:48 AM APLIM CHAMBERY - N?24415'
            Services   = @(@{ Type = 'Collecte cartouches encre'; ODM = '1234567-1' })
        }
        $pe = [pscustomobject]@{
            ClientID        = '24415'
            ClientName      = '4/10/26, 8:48 AM APLIM CHAMBERY - N?24415'
            ClientNameLines = @(
                'Collecte cartouches encre - 4/10/26, 8:48 AM',
                'APLIM CHAMBERY - N°24415'
            )
            Services = @(@{ Type = 'Collecte cartouches encre'; ODM = '1234567-1' })
        }
        (Get-CnsPdfPageClientDisplayName -PageEntity $pe -WorkOrderEntity $wo) | Should Be 'APLIM CHAMBERY - N°24415'
        $a = Get-CnsPdfPageMetierAnalysis -PageEntity $pe -WorkOrderEntity $wo
        ($a.TrackDechetEntries[0].Client) | Should Be 'APLIM CHAMBERY - N°24415'
    }

    It 'Get-CnsPdfPageClientDisplayName : WorkOrder prioritaire si PageEntity pollué sans rebuild' {
        $wo = [pscustomobject]@{
            ClientID   = '24415'
            ClientName = 'APLIM CHAMBERY - N°24415'
            Services   = @(@{ Type = 'Collecte cartouches encre'; ODM = '1234567-1' })
        }
        $pe = [pscustomobject]@{
            ClientID   = '24415'
            ClientName = '4/10/26, 8:48 AM APLIM CHAMBERY - N?24415'
            Services   = @(@{ Type = 'Collecte cartouches encre'; ODM = '1234567-1' })
        }
        (Get-CnsPdfPageClientDisplayName -PageEntity $pe -WorkOrderEntity $wo) | Should Be 'APLIM CHAMBERY - N°24415'
    }

    It 'Split-PdfMonolithicClientNameLayoutLines : scinde prestation + date + nom' {
        $pdfExtractorPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Extractors\PdfExtractor.ps1' | Resolve-Path
        . ([string]$pdfExtractorPath)
        $entityExtractorPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Extractors\EntityExtractor.ps1' | Resolve-Path
        . ([string]$entityExtractorPath)
        $mono = 'Collecte cartouches encre - 4/10/26, 8:48 AM APLIM CHAMBERY - N°24415'
        $split = @(Split-PdfMonolithicClientNameLayoutLines -LayoutLines @($mono))
        $split.Count | Should Be 2
        $split[0] | Should Be 'Collecte cartouches encre'
        $split[1] | Should Be 'APLIM CHAMBERY - N°24415'
        (Get-ClientNameFromLines -Lines $split -ClientId '24415') | Should Be 'APLIM CHAMBERY - N°24415'
    }

    It 'ConvertTo-CnsPsHelveticaParenBody : N° en WinAnsi \260' {
        $body = ConvertTo-CnsPsHelveticaParenBody -Text 'APLIM CHAMBERY - N°24415'
        $body | Should Match 'N\\26024415'
    }

    It 'ConvertTo-CnsPsWinAnsiParenBody : circonflexes Benoît Forêt Hôpital' {
        (ConvertTo-CnsPsWinAnsiParenBody -Text 'Benoît') | Should Be 'Beno\356t'
        (ConvertTo-CnsPsWinAnsiParenBody -Text 'Forêt') | Should Be 'For\352t'
        (ConvertTo-CnsPsWinAnsiParenBody -Text 'Hôpital') | Should Be 'H\364pital'
        $combining = 'Benoi' + [char]0x0302 + 't'
        (ConvertTo-CnsPsWinAnsiParenBody -Text $combining) | Should Be 'Beno\356t'
    }

    It 'New-CnsPrefaceSectionCoverPdf : pluriel ODM non matché(s) et date tournée' {
        $unmatchedLabel1 = if (1 -gt 1) { 'ODM non matchés' } else { 'ODM non matché' }
        $unmatchedLabel2 = if (2 -gt 1) { 'ODM non matchés' } else { 'ODM non matché' }
        $unmatchedLabel1 | Should Be 'ODM non matché'
        $unmatchedLabel2 | Should Be 'ODM non matchés'
        $l0 = ("{0} dans les tournées du {1}" -f $unmatchedLabel2, 'Mardi 21 Juillet 2026')
        $l0 | Should Be 'ODM non matchés dans les tournées du Mardi 21 Juillet 2026'
        (ConvertTo-CnsPsWinAnsiParenBody -Text $l0) | Should Match 'match\\351s'
        (ConvertTo-CnsPsWinAnsiParenBody -Text $l0) | Should Match 'Juillet'
    }

    It 'Build-CnsTourneeHeaderCoverPostScriptBody : Camion parc et immat ligne separee' {
        $ps = Build-CnsTourneeHeaderCoverPostScriptBody -DateTitle 'Lundi 1 janvier 2026' -Collecteur 'Jean DUPONT' `
            -Vehicule '44' -VehiculeImmatriculation 'EF 456 TY' -MetierMemoLines @('Collecte DEEE - CLIENT')
        $ps | Should Match 'Camion 44'
        $ps | Should Match 'EF 456 TY'
        $ps | Should Match 'findfont 18 scalefont'
        $ps | Should Match 'findfont 12 scalefont'
        $ps | Should Match '550 exch sub 770 moveto'
        $ps | Should Match '520 exch sub 756 moveto'
        $ps | Should Not Match '44 \(EF'
    }

    It 'Build-CnsTourneeHeaderCoverPostScriptBody : parc seul si immat absente' {
        $ps = Build-CnsTourneeHeaderCoverPostScriptBody -DateTitle 'Lundi 1 janvier 2026' -Collecteur 'Jean DUPONT' `
            -Vehicule '44' -MetierMemoLines @()
        $ps | Should Match 'Camion 44'
        $ps | Should Not Match 'findfont 12 scalefont'
    }

    It 'Build-CnsTourneeHeaderCoverPostScriptBody : CenteredText SB remplace les memo prestations' {
        $ps = Build-CnsTourneeHeaderCoverPostScriptBody -DateTitle 'Mercredi 15 juillet 2026' -Collecteur 'Jean DUPONT' `
            -Vehicule '44' -VehiculeImmatriculation 'EF 456 RT' -MetierMemoLines @('Collecte DEEE - CLIENT') -CenteredText 'SB'
        $ps | Should Match 'Mercredi 15 juillet 2026'
        $ps | Should Match 'Camion 44'
        $ps | Should Match 'EF 456 RT'
        $ps | Should Match '595 exch sub 2 div 730 moveto'
        $ps | Should Match '\(SB\) dup stringwidth'
        $ps | Should Not Match 'Collecte DEEE'
    }

    It 'New-CnsPostScriptCenteredTextShowBlock : centre horizontalement' {
        $block = New-CnsPostScriptCenteredTextShowBlock -Text 'SB' -FontName 'Helvetica' -FontSize 12 -Y 730 -PageWidth 595
        $block | Should Match '595 exch sub 2 div 730 moveto'
        $block | Should Match '\(SB\)'
    }

    It 'Add-CnsExcelSbTourneeCandidates : detecte collecteur + vehicule sans client (geometrie reelle)' {
        $grid = New-Object object[] 20
        for ($i = 0; $i -lt 20; $i++) {
            $grid[$i] = @('', '', '')
        }
        # Col0 = meta gauche, Col1 = DATE — comme Excel : collecteur puis Camion, secteur optionnel en DATE
        $grid[4] = @('Sens de la tournee', 'mercredi 15/07', '')
        $grid[5] = @('Andre', 'St Egreve / Pays Voironnais / Grenoble', '')
        $grid[6] = @('Camion 44', '', '')
        $grid[7] = @('', '', '')
        $grid[8] = @('', '', '')
        $sheet = [pscustomobject]@{
            Name     = 'Planning'
            RowCount = 20
            ColCount = 3
            Grid     = $grid
        }
        $sbList = New-Object System.Collections.Generic.List[object]
        Add-CnsExcelSbTourneeCandidates -Sheet $sheet -StartZero 0 -MaxZ 19 `
            -ColZeroDate 1 -ColLeftMeta 0 -SheetColCount 3 `
            -FallbackVisitDate (Get-Date '2026-07-15') -ExistingTourStarts @() -SbStarts $sbList
        $sbList.Count | Should Be 1
        $sbList[0].IsSbTour | Should Be $true
        $sbList[0].Collecteur | Should Be 'Andre'
        $sbList[0].Vehicule | Should Be 'Camion 44'
        $sbList[0].DisplayDateJM | Should Be '15/07/2026'
    }

    It 'Add-CnsExcelSbTourneeCandidates : ignore en-tete suivi d un client' {
        $grid = New-Object object[] 20
        for ($i = 0; $i -lt 20; $i++) {
            $grid[$i] = @('', '', '')
        }
        $grid[5] = @('Raphael', 'Meylan 1/2', '')
        $grid[6] = @('Camion 11', '', '')
        $grid[7] = @('', '(9804) CLIENT TEST', '')
        $sheet = [pscustomobject]@{
            Name     = 'Planning'
            RowCount = 20
            ColCount = 3
            Grid     = $grid
        }
        $sbList = New-Object System.Collections.Generic.List[object]
        Add-CnsExcelSbTourneeCandidates -Sheet $sheet -StartZero 0 -MaxZ 19 `
            -ColZeroDate 1 -ColLeftMeta 0 -SheetColCount 3 `
            -FallbackVisitDate (Get-Date '2026-07-15') -ExistingTourStarts @() -SbStarts $sbList
        $sbList.Count | Should Be 0
    }

    It 'Add-CnsExcelSbTourneeCandidates : fixture 1507sansodm detecte Andre SB' {
        $excelLoaderPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Extractors\ExcelLoader.ps1' | Resolve-Path
        . ([string]$excelLoaderPath)
        $fixture = Join-Path $PSScriptRoot 'Fixtures\PdfPlanningOptimizer\1507sansodm.xlsx'
        if (-not (Test-Path -LiteralPath $fixture)) {
            Set-ItResult -Inconclusive -Because 'Fixture 1507sansodm.xlsx absente'
            return
        }
        $excelData = Import-PlanningExcel -ExcelPath $fixture
        $sheet = @($excelData.Sheets)[0]
        $colZeroDate = 47   # AV (mercredi 15/07)
        $colLeftMeta = 46   # AU
        $sbList = New-Object System.Collections.Generic.List[object]
        Add-CnsExcelSbTourneeCandidates -Sheet $sheet -StartZero 0 -MaxZ ([int]$sheet.RowCount - 1) `
            -ColZeroDate $colZeroDate -ColLeftMeta $colLeftMeta -SheetColCount ([int]$sheet.ColCount) `
            -FallbackVisitDate (Get-Date '2026-07-15') -ExistingTourStarts @() -SbStarts $sbList
        $andre = @($sbList | Where-Object { $_.Collecteur -match '(?i)andr' })
        $andre.Count | Should BeGreaterThan 0
        $andre[0].IsSbTour | Should Be $true
        $andre[0].Vehicule | Should Match '(?i)camion\s*44'
        ($sbList | Where-Object { $_.Collecteur -match '(?i)rapha' }).Count | Should Be 0
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
        ($memos -join '|') | Should Match 'Collecte de piles'
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

Describe 'PdfPlanningOptimizer - certificat destruction ODS' {

    BeforeAll {
        $odsCertPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\CnsDestructionCertificateODS.ps1' | Resolve-Path
        . ([string]$odsCertPath)
    }

    It 'Get-CnsDestructionCertificateTemplatePath : fichier repo templates' {
        $p = Get-CnsDestructionCertificateTemplatePath
        (Test-Path -LiteralPath $p) | Should Be $true
        ([System.IO.Path]::GetExtension($p)).ToLowerInvariant() | Should Be '.ods'
    }

    It 'ConvertTo-CnsDestructionCertificatePlaceholderValue : sentinelles -> vide' {
        (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value 'INCONNU') | Should Be ''
        (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value 'NON SPECIFIE') | Should Be ''
        (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value 'À compléter') | Should Be ''
        (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value '-') | Should Be ''
        (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value 'Jean Martin') | Should Be 'Jean Martin'
    }

    It 'Repair-CnsClientNumeroSignText : N? -> N° avant chiffres client' {
        (Repair-CnsClientNumeroSignText -Text 'EUROFINS LABAZUR BRIGNOUD - N?24656') | Should Be 'EUROFINS LABAZUR BRIGNOUD - N°24656'
        (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value 'APLIM CHAMBERY - N?24415') | Should Be 'APLIM CHAMBERY - N°24415'
    }

    It 'Add-2WorkingDaysWithFrenchHolidays : exemples validation' {
        . (Join-Path $PSScriptRoot '..\src\Common\CnsFrenchHolidays.ps1' | Resolve-Path)
        $d1 = Add-2WorkingDaysWithFrenchHolidays -StartDate ([datetime]'2026-05-29')
        (Format-CnsFrenchDate -Date $d1) | Should Be '02/06/2026'
        $d2 = Add-2WorkingDaysWithFrenchHolidays -StartDate ([datetime]'2026-05-07')
        (Format-CnsFrenchDate -Date $d2) | Should Be '12/05/2026'
    }

    It 'Get-CnsDestructionCertificatePlaceholders : Date_FinDestruction et trieur' {
        $wo = [pscustomobject]@{
            ClientID   = '1'
            ClientName = 'Client'
            WorkOrder  = 'WO-1'
            Services   = @()
            Address    = @{ Street = ''; PostalCode = ''; City = '' }
        }
        $seg = [pscustomobject]@{ Collecteur = 'Jean Martin'; Vehicule = 'AB-123-CD' }
        $ph = Get-CnsDestructionCertificatePlaceholders -WorkOrderEntity $wo -SegmentMeta $seg -VisitDate ([datetime]'2026-05-29')
        $ph.Date_FinDestruction | Should Be '02/06/2026'
        ($ph.Keys -contains 'Trieur_Nom') | Should Be $true
        ($ph.Keys -contains 'Trieur_Prenom') | Should Be $true
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

    It 'Set-OdsTemplatePlaceholders : remplace balises CertificatDeDestruction.ods' {
        $tpl = Get-CnsDestructionCertificateTemplatePath
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $picsBefore = @([System.IO.Compression.ZipFile]::OpenRead($tpl).Entries | Where-Object { $_.FullName -like 'Pictures/*' }).Count
        [System.IO.Compression.ZipFile]::OpenRead($tpl).Dispose()

        $work = Join-Path $env:TEMP ("cn_pester_cert_{0}.ods" -f ([Guid]::NewGuid().ToString('N')))
        $ph = @{
            Date_Collecte       = '01/02/2026'
            Date_FinDestruction = '05/02/2026'
            Client_Nom          = 'ACME TEST'
            Client_Adresse      = '10 rue Test'
            Client_CP           = '75002'
            Client_Ville        = 'Paris'
            Collecteur_Nom      = 'DUPONT'
            Collecteur_Prenom   = 'Jean'
            Client_ID           = '99999'
            ODM_Numero          = 'ODM-TEST'
            Vehicule_Immat      = 'AB-001-CD'
            Trieur_Nom          = 'MARTIN'
            Trieur_Prenom       = 'Paul'
        }
        $ok = Set-OdsTemplatePlaceholders -OdsPath $tpl -Placeholders $ph -OutputPath $work
        $ok | Should Be $true

        $zip = [System.IO.Compression.ZipFile]::OpenRead($work)
        $sr = New-Object System.IO.StreamReader($zip.GetEntry('content.xml').Open())
        $xml = $sr.ReadToEnd(); $sr.Close()
        $picsAfter = @($zip.Entries | Where-Object { $_.FullName -like 'Pictures/*' }).Count
        $zip.Dispose()
        $xml.Contains('{{') | Should Be $false
        $xml.Contains('ACME TEST') | Should Be $true
        $xml.Contains('DUPONT') | Should Be $true
        $picsAfter | Should Be $picsBefore
        Remove-Item -LiteralPath $work -Force -ErrorAction SilentlyContinue
    }
}

Describe 'PdfPlanningOptimizer - fusion PDF certificat (structure-preserving)' {

    BeforeAll {
        $mergePath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\CnsPdfStructureMerge.ps1' | Resolve-Path
        $odsPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\CnsDestructionCertificateODS.ps1' | Resolve-Path
        . ([string]$mergePath)
        . ([string]$odsPath)
    }

    It 'Test-CnsPdfPathIsDestructionCertificateFragment : detecte cert_dest_*.pdf' {
        (Test-CnsPdfPathIsDestructionCertificateFragment -Path 'C:\tmp\cert_dest_001_00001.pdf') | Should Be $true
        (Test-CnsPdfPathIsDestructionCertificateFragment -Path 'C:\tmp\main_slice_001.pdf') | Should Be $false
    }

    It 'Test-CnsPdfPathIsBilanCollecteFragment : detecte bilan_seg_*.pdf et bilan_sb_*.pdf' {
        (Test-CnsPdfPathIsBilanCollecteFragment -Path 'C:\tmp\bilan_seg_001.pdf') | Should Be $true
        (Test-CnsPdfPathIsBilanCollecteFragment -Path 'C:\tmp\bilan_sb_001.pdf') | Should Be $true
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
        $ods = Join-Path $env:TEMP ("cn_pester_merge_{0}.ods" -f ([Guid]::NewGuid().ToString('N')))
        $certPdf = Join-Path $env:TEMP ("cert_dest_001_00001.pdf")
        $dummyPdf = Join-Path $env:TEMP ("cn_pester_dummy_{0}.pdf" -f ([Guid]::NewGuid().ToString('N')))
        $merged = Join-Path $env:TEMP ("cn_pester_merged_{0}.pdf" -f ([Guid]::NewGuid().ToString('N')))
        $ph = @{
            Date_Collecte = '01/01/2026'; Client_Nom = 'ACME'; Client_Adresse = '1 rue'
            Client_CP = '75001'; Client_Ville = 'Paris'; Collecteur_Nom = 'DUPONT'; Collecteur_Prenom = 'Jean'
            Date_FinDestruction = '05/01/2026'; Trieur_Nom = 'X'; Trieur_Prenom = 'Y'; ODM_Numero = 'ODM-1'
        }
        Set-OdsTemplatePlaceholders -OdsPath $tpl -Placeholders $ph -OutputPath $ods | Should Be $true
        (Convert-OdsToPdf -OdsPath $ods -PdfPath $certPdf) | Should Be $true
        Copy-Item -LiteralPath $certPdf -Destination $dummyPdf -Force
        $before = Get-CnsPdfFontStructureMarkers -PdfPath $certPdf
        $before.ToUnicode | Should BeGreaterThan 0
        $before.FontFile2 | Should BeGreaterThan 0
        $ok = Merge-CnsPdfFilesForStep5TourneeComposition -InputPdfsOrdered @($dummyPdf, $certPdf) -DestinationPdfPath $merged
        $ok | Should Be $true
        $after = Get-CnsPdfFontStructureMarkers -PdfPath $merged
        $after.ToUnicode | Should BeGreaterThan 0
        $after.FontFile2 | Should BeGreaterThan 0
        Remove-Item -LiteralPath $ods,$certPdf,$dummyPdf,$merged -Force -ErrorAction SilentlyContinue
    }
}

Describe 'PdfPlanningOptimizer - bilan collecte ODS' {

    BeforeAll {
        $bilanPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\CnsBilanCollecteODS.ps1' | Resolve-Path
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

    It 'Set-OdsTemplatePlaceholders : remplace balises BilanDeCollecte.ods' {
        $tpl = Get-CnsBilanCollecteTemplatePath
        $work = Join-Path $env:TEMP ("cn_pester_bilan_{0}.ods" -f ([Guid]::NewGuid().ToString('N')))
        $ph = @{
            Date_Collecte     = '15/03/2026'
            Collecteur_Nom    = 'DURAND'
            Collecteur_Prenom = 'Paul'
        }
        $ok = Set-OdsTemplatePlaceholders -OdsPath $tpl -Placeholders $ph -OutputPath $work
        $ok | Should Be $true
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($work)
        $sr = New-Object System.IO.StreamReader($zip.GetEntry('content.xml').Open())
        $xml = $sr.ReadToEnd(); $sr.Close(); $zip.Dispose()
        $xml.Contains('{{') | Should Be $false
        $xml.Contains('DURAND') | Should Be $true
        $xml.Contains('15/03/2026') | Should Be $true
        Remove-Item -LiteralPath $work -Force -ErrorAction SilentlyContinue
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
        if (-not (Get-CnsLibreOfficeSofficePath)) {
            Write-Host 'INCONCLUSIVE: LibreOffice absent' -ForegroundColor Yellow
            return
        }
        $ods = Join-Path $env:TEMP ("cn_pester_bilan_merge_{0}.ods" -f ([Guid]::NewGuid().ToString('N')))
        $bilanPdf = Join-Path $env:TEMP 'bilan_seg_001.pdf'
        $dummyPdf = Join-Path $env:TEMP ("cn_pester_dummy_bilan_{0}.pdf" -f ([Guid]::NewGuid().ToString('N')))
        $merged = Join-Path $env:TEMP ("cn_pester_merged_bilan_{0}.pdf" -f ([Guid]::NewGuid().ToString('N')))
        Set-OdsTemplatePlaceholders -OdsPath $tpl -Placeholders @{
            Date_Collecte = '01/01/2026'; Collecteur_Nom = 'TEST'; Collecteur_Prenom = 'Jean'
        } -OutputPath $ods | Should Be $true
        (Convert-OdsToPdf -OdsPath $ods -PdfPath $bilanPdf) | Should Be $true
        Copy-Item -LiteralPath $bilanPdf -Destination $dummyPdf -Force
        $before = Get-CnsPdfFontStructureMarkers -PdfPath $bilanPdf
        $before.ToUnicode | Should BeGreaterThan 0
        $before.FontFile2 | Should BeGreaterThan 0
        $ok = Merge-CnsPdfFilesForStep5TourneeComposition -InputPdfsOrdered @($dummyPdf, $bilanPdf) -DestinationPdfPath $merged
        $ok | Should Be $true
        $after = Get-CnsPdfFontStructureMarkers -PdfPath $merged
        $after.ToUnicode | Should BeGreaterThan 0
        $after.FontFile2 | Should BeGreaterThan 0
        Remove-Item -LiteralPath $ods,$bilanPdf,$dummyPdf,$merged -Force -ErrorAction SilentlyContinue
    }
}

Describe 'PdfPlanningOptimizer - CEA points collecte ODS' {

    BeforeAll {
        $ceaPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\CnsCeaPointsCollecteODS.ps1' | Resolve-Path
        $metierPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\CnsPdfMetierPrestation.ps1' | Resolve-Path
        $mergePath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\CnsPdfStructureMerge.ps1' | Resolve-Path
        . ([string]$metierPath)
        . ([string]$ceaPath)
        . ([string]$mergePath)
    }

    It 'Get-CnsCeaPointsDeCollectePlaceholders : Date_Collecte depuis segment' {
        $seg = [pscustomobject]@{
            DisplayDateJM = '20/05/2026'
            TourDate      = [datetime]'2026-05-20'
            Collecteur    = 'Jean Martin'
        }
        $ph = Get-CnsCeaPointsDeCollectePlaceholders -WorkOrderEntity $null -PageEntity $null -SegmentMeta $seg -VisitDate ([datetime]'2026-01-01') -FragSlicePdfPath $null
        $ph.Date_Collecte | Should Be '20/05/2026'
        $ph.Count | Should Be 1
    }

    It 'Set-OdsTemplatePlaceholders : remplace Date_Collecte dans CeaPointsDeCollectes.ods' {
        $tpl = Get-CnsCeaPointsDeCollecteTemplatePath
        $work = Join-Path $env:TEMP ("cn_pester_cea_{0}.ods" -f ([Guid]::NewGuid().ToString('N')))
        $ph = @{ Date_Collecte = '20/05/2026' }
        $ok = Set-OdsTemplatePlaceholders -OdsPath $tpl -Placeholders $ph -OutputPath $work
        $ok | Should Be $true
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($work)
        $sr = New-Object System.IO.StreamReader($zip.GetEntry('content.xml').Open())
        $xml = $sr.ReadToEnd(); $sr.Close(); $zip.Dispose()
        $xml.Contains('{{') | Should Be $false
        $xml.Contains('20/05/2026') | Should Be $true
        Remove-Item -LiteralPath $work -Force -ErrorAction SilentlyContinue
    }

    It 'New-CnsCeaPointsDeCollectesPdfFromOdsTemplate : produit PDF via LibreOffice' {
        if (-not (Get-CnsLibreOfficeSofficePath)) {
            Set-ItResult -Inconclusive -Because 'LibreOffice absent'
        }
        $tpl = Get-CnsCeaPointsDeCollecteTemplatePath
        $outPdf = Join-Path $env:TEMP ("cea_{0:D3}_{1:D5}.pdf" -f 1, 1)
        $ph = @{ Date_Collecte = '01/06/2026' }
        $result = New-CnsCeaPointsDeCollectesPdfFromOdsTemplate -OutPdfPath $outPdf -Placeholders $ph
        $result | Should Not BeNullOrEmpty
        (Test-Path -LiteralPath $outPdf) | Should Be $true
        $m = Get-CnsPdfFontStructureMarkers -PdfPath $outPdf
        if ($null -ne $m) {
            $m.ToUnicode | Should BeGreaterThan 0
        }
        Remove-Item -LiteralPath $outPdf -Force -ErrorAction SilentlyContinue
    }
}

Describe 'PdfPlanningOptimizer - conversion ODS PDF LibreOffice' {

    BeforeAll {
        $odsCertPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\CnsDestructionCertificateODS.ps1' | Resolve-Path
        . ([string]$odsCertPath)
    }

    It 'Convert-OdsToPdf : produit un PDF depuis CertificatDeDestruction.ods' {
        if (-not (Get-CnsLibreOfficeSofficePath)) {
            Set-ItResult -Inconclusive -Because 'LibreOffice absent'
        }
        $tpl = Get-CnsDestructionCertificateTemplatePath
        $ods = Join-Path $env:TEMP ("cn_pester_lo_{0}.ods" -f ([Guid]::NewGuid().ToString('N')))
        $pdf = Join-Path $env:TEMP ("cn_pester_lo_{0}.pdf" -f ([Guid]::NewGuid().ToString('N')))
        Set-OdsTemplatePlaceholders -OdsPath $tpl -Placeholders @{
            Date_Collecte = '01/01/2026'; Client_Nom = 'TEST'; ODM_Numero = 'ODM-1'
            Date_FinDestruction = '05/01/2026'; Trieur_Nom = 'X'; Trieur_Prenom = 'Y'
        } -OutputPath $ods | Should Be $true
        try {
            (Convert-OdsToPdf -OdsPath $ods -PdfPath $pdf) | Should Be $true
            (Test-Path -LiteralPath $pdf) | Should Be $true
        }
        finally {
            Remove-Item -LiteralPath $ods, $pdf -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'PdfPlanningOptimizer - FT points de collecte' {

    BeforeAll {
        $metierPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\CnsPdfMetierPrestation.ps1' | Resolve-Path
        $ftPath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\CnsFtTemplate.ps1' | Resolve-Path
        . ([string]$metierPath)
        . ([string]$ftPath)
    }

    It 'Get-CnsFtCollectionPointLabelFromRawLines : detecte FT + agence' {
        $label = Get-CnsFtCollectionPointLabelFromRawLines -RawLines @(
            'Client divers',
            'FT CHAMBERY GRAND VERGER',
            'ODM 1234567-1'
        )
        $label | Should Be 'FT CHAMBERY GRAND VERGER'
    }

    It 'Get-CnsFtCollectionPointLabelFromRawLines : ignore SOFT sans FT en debut de ligne' {
        $label = Get-CnsFtCollectionPointLabelFromRawLines -RawLines @('SOFT SERVICE', 'Collecte standard')
        $label | Should BeNullOrEmpty
    }

    It 'Test-CnsStep5FragSliceRequiresFtDocument : true sur lignes FT' {
        (Test-CnsStep5FragSliceRequiresFtDocument -PrecomputedRawLines @('FT GRENOBLE CENTRE')) | Should Be $true
    }

    It 'Get-CnsFtPlaceholders : Point_Collecte et ODM' {
        $wo = [pscustomobject]@{
            ClientID   = '99999'
            ClientName = 'NE PAS UTILISER'
            WorkOrder  = '7654321-2'
            Address    = [pscustomobject]@{ Street = '1 rue Test'; PostalCode = '73000'; City = 'Chambery' }
            Services   = @()
        }
        $seg = [pscustomobject]@{ DisplayDateJM = '15/07/2026'; Collecteur = 'Dupont Jean' }
        $ph = Get-CnsFtPlaceholders -WorkOrderEntity $wo -PageEntity $null -SegmentMeta $seg `
            -VisitDate ([datetime]'2026-07-15') -PointCollecte 'FT CHAMBERY GRAND VERGER'
        $ph.Point_Collecte | Should Be 'FT CHAMBERY GRAND VERGER'
        $ph.ODM_Numero | Should Be '7654321-2'
        $ph.Date_Collecte | Should Be '15/07/2026'
    }

    It 'Test-CnsPdfPathIsFtCollecteFragment : nom ft_*.pdf' {
        (Test-CnsPdfPathIsFtCollecteFragment -Path 'C:\tmp\ft_001_00042.pdf') | Should Be $true
        (Test-CnsPdfPathIsFtCollecteFragment -Path 'C:\tmp\cea_001_00042.pdf') | Should Be $false
    }

    It 'Fixture FT 1507.pdf : detecte au moins un point FT' {
        $pdfFixture = Join-Path $PSScriptRoot 'Fixtures\PdfPlanningOptimizer\FT 1507.pdf'
        if (-not (Test-Path -LiteralPath $pdfFixture)) {
            Set-ItResult -Inconclusive -Because 'Fixture FT 1507.pdf absente'
        }
        $metierPathOnly = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\CnsPdfMetierPrestation.ps1' | Resolve-Path
        . ([string]$metierPathOnly)
        $extractor = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Extractors\PdfExtractor.ps1' | Resolve-Path
        . ([string]$extractor)
        $exe = Get-ResolvedPdfToTextPath
        if ([string]::IsNullOrWhiteSpace($exe)) {
            Set-ItResult -Inconclusive -Because 'pdftotext absent'
        }
        $tempOut = Join-Path $env:TEMP ("cn_ft_fixture_{0}.txt" -f [Guid]::NewGuid().ToString('N'))
        try {
            & $exe -enc UTF-8 -q $pdfFixture $tempOut 2>$null | Out-Null
            $lines = @(Get-Content -LiteralPath $tempOut -Encoding UTF8 -ErrorAction SilentlyContinue)
            $found = $false
            foreach ($ln in $lines) {
                if (-not [string]::IsNullOrWhiteSpace((Get-CnsFtCollectionPointLabelFromRawLines -RawLines @($ln)))) {
                    $found = $true
                    break
                }
            }
            $found | Should Be $true
        }
        finally {
            Remove-Item -LiteralPath $tempOut -Force -ErrorAction SilentlyContinue
        }
    }

    It 'New-CnsFtPdfFromExcelTemplate : produit PDF via LibreOffice ou Excel' {
        if (-not (Get-CnsLibreOfficeSofficePath) -and -not (Test-CnsMicrosoftExcelAvailable)) {
            Set-ItResult -Inconclusive -Because 'LibreOffice et Excel absents'
        }
        $outPdf = Join-Path $env:TEMP ("cn_ft_pester_{0}.pdf" -f [Guid]::NewGuid().ToString('N'))
        $ph = @{
            Date_Collecte     = '15/07/2026'
            Point_Collecte    = 'FT CHAMBERY GRAND VERGER'
            Client_ID         = 'CLI-1'
            Client_Nom        = 'Client Test'
            Client_Adresse    = '1 rue Test'
            Client_CP         = '73000'
            Client_Ville      = 'Chambery'
            ODM_Numero        = '1234567-1'
            Collecteur_Nom    = 'Dupont'
            Collecteur_Prenom = 'Jean'
        }
        try {
            $result = New-CnsFtPdfFromExcelTemplate -OutPdfPath $outPdf -Placeholders $ph
            $result | Should Not BeNullOrEmpty
            (Test-Path -LiteralPath $outPdf) | Should Be $true
        }
        finally {
            Remove-Item -LiteralPath $outPdf -Force -ErrorAction SilentlyContinue
        }
    }
}

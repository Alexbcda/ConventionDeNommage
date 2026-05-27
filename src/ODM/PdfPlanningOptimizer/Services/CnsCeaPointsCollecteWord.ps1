# CEA Points de collecte : template DOCX -> PDF (LibreOffice headless ou Microsoft Word COM en secours).
# Reutilise le moteur w:t safe et la conversion LibreOffice du certificat destruction.

. (Join-Path $PSScriptRoot 'CnsDestructionCertificateWord.ps1')

function Get-CnsCeaPointsDeCollecteTemplatePath {
    $candidates = New-Object System.Collections.Generic.List[string]
    try {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
        [void]$candidates.Add((Join-Path $repoRoot 'templates\planning\cea\CeaPointsDeCollectes.docx'))
        [void]$candidates.Add((Join-Path $repoRoot 'templates\CeaPointsDeCollectes.docx'))
    }
    catch { }
    if (-not [string]::IsNullOrWhiteSpace($env:CN_CEA_POINTS_TEMPLATE)) {
        [void]$candidates.Insert(0, $env:CN_CEA_POINTS_TEMPLATE.Trim())
    }
    foreach ($p in @($candidates)) {
        if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path -LiteralPath $p -PathType Leaf)) {
            return ([System.IO.Path]::GetFullPath($p))
        }
    }
    return $null
}

function Get-CnsCeaPointCollecteDescriptionFromFragSlice {
    <#
    .SYNOPSIS
        Extrait une description CEA depuis le texte pdftotext du slice ODM STEP5.
    #>
    param(
        [AllowNull()][AllowEmptyString()][string]$FragSlicePdfPath
    )
    if ([string]::IsNullOrWhiteSpace($FragSlicePdfPath)) { return '' }
    if (-not (Get-Command Get-CnsStep5PdftotextLinesFromSinglePagePdf -ErrorAction SilentlyContinue)) {
        return ''
    }
    $rawLines = @(Get-CnsStep5PdftotextLinesFromSinglePagePdf -SinglePagePdfPath $FragSlicePdfPath)
    if ($rawLines.Count -lt 1) { return '' }

    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($ln in @($rawLines)) {
        if ([string]::IsNullOrWhiteSpace($ln)) { continue }
        $t = ([string]$ln).Trim()
        if ($t.Length -lt 3) { continue }
        if ($t -match '(?i)\bcea\b|24531|service\s+logistique|\bsle\b') {
            [void]$candidates.Add($t)
        }
    }
    if ($candidates.Count -gt 0) {
        return (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value ($candidates -join ' | '))
    }

    $joined = (($rawLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' ').Trim()
    if ($joined.Length -gt 480) {
        $joined = $joined.Substring(0, 480).Trim() + '…'
    }
    return (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $joined)
}

function Get-CnsCeaPointsDeCollectePlaceholders {
    <#
    .SYNOPSIS
        Placeholders CeaPointsDeCollectes.docx (template actuel : Date_Collecte ; cles etendues si ajoutees au DOCX).
    #>
    param(
        [AllowNull()]
        $WorkOrderEntity,
        [AllowNull()]
        $PageEntity,
        [AllowNull()]
        $SegmentMeta,
        [Parameter(Mandatory = $true)]
        [datetime]$VisitDate,
        [AllowNull()][AllowEmptyString()][string]$FragSlicePdfPath
    )

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    [string]$dateCollecte = $VisitDate.ToString('dd/MM/yyyy', $inv)
    [string]$clientId = ''
    [string]$clientNom = ''
    [string]$street = ''
    [string]$cp = ''
    [string]$ville = ''
    [string]$odmNum = ''
    [string]$collecteurNom = ''
    [string]$collecteurPrenom = ''

    if ($null -ne $WorkOrderEntity) {
        $base = Get-CnsDestructionCertificatePlaceholders -WorkOrderEntity $WorkOrderEntity -SegmentMeta $SegmentMeta -VisitDate $VisitDate
        $dateCollecte = [string]$base.Date_Collecte
        $clientId = [string]$base.Client_ID
        $clientNom = [string]$base.Client_Nom
        $street = [string]$base.Client_Adresse
        $cp = [string]$base.Client_CP
        $ville = [string]$base.Client_Ville
        $odmNum = [string]$base.ODM_Numero
        $collecteurNom = [string]$base.Collecteur_Nom
        $collecteurPrenom = [string]$base.Collecteur_Prenom
    }
    else {
        if ($null -ne $PageEntity) {
            try {
                $cn = [string]$PageEntity.ClientName
                if (-not [string]::IsNullOrWhiteSpace($cn)) {
                    $clientNom = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $cn.Trim())
                }
            }
            catch { }
            try {
                $cid = [string]$PageEntity.ClientID
                if (-not [string]::IsNullOrWhiteSpace($cid)) {
                    $clientId = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $cid.Trim())
                }
            }
            catch { }
        }
        if ($null -ne $SegmentMeta) {
            $collecteurResolved = Resolve-CnsCollecteurFieldsForCertificate -CollecteurExcelRaw ([string]$SegmentMeta.Collecteur)
            $collecteurNom = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value ([string]$collecteurResolved.Nom))
            $collecteurPrenom = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value ([string]$collecteurResolved.Prenom))
        }
    }

    if ($null -ne $SegmentMeta) {
        try {
            $dj = [string]$SegmentMeta.DisplayDateJM
            if (-not [string]::IsNullOrWhiteSpace($dj)) {
                $dateCollecte = $dj.Trim()
            }
            elseif ($null -ne $SegmentMeta.TourDate) {
                $dateCollecte = ([datetime]$SegmentMeta.TourDate).ToString('dd/MM/yyyy', $inv)
            }
        }
        catch { }
    }

    [string]$clientAdresse = $street
    if (-not [string]::IsNullOrWhiteSpace($cp) -or -not [string]::IsNullOrWhiteSpace($ville)) {
        $tail = (($cp, $ville | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' ').Trim()
        if (-not [string]::IsNullOrWhiteSpace($tail)) {
            if ([string]::IsNullOrWhiteSpace($clientAdresse)) {
                $clientAdresse = $tail
            }
            else {
                $clientAdresse = ('{0}, {1}' -f $clientAdresse, $tail)
            }
        }
    }
    $clientAdresse = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $clientAdresse)

    [string]$pointDesc = Get-CnsCeaPointCollecteDescriptionFromFragSlice -FragSlicePdfPath $FragSlicePdfPath

    return [ordered]@{
        Date_Collecte               = $dateCollecte
        Client_ID                   = $clientId
        Client_Nom                  = $clientNom
        Client_Adresse              = $clientAdresse
        Client_CP                   = $cp
        Client_Ville                = $ville
        ODM_Numero                  = $odmNum
        Collecteur_Nom              = $collecteurNom
        Collecteur_Prenom           = $collecteurPrenom
        Point_Collecte_Description  = $pointDesc
    }
}

function New-CnsCeaPointsDeCollectesPdfFromWordTemplate {
    <#
    .SYNOPSIS
        Remplit CeaPointsDeCollectes.docx et exporte un PDF (LibreOffice ou Word). Retourne le chemin PDF ou $null.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutPdfPath,
        [Parameter(Mandatory = $true)]
        [hashtable]$Placeholders,
        [string]$TemplatePath
    )
    if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
        $TemplatePath = Get-CnsCeaPointsDeCollecteTemplatePath
    }
    if ([string]::IsNullOrWhiteSpace($TemplatePath) -or -not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
        Write-Warning '[CEA-POINTS] Template DOCX introuvable (templates\CeaPointsDeCollectes.docx ou CN_CEA_POINTS_TEMPLATE).'
        return $null
    }

    $outAbs = [System.IO.Path]::GetFullPath($OutPdfPath)
    $outDir = Split-Path -Parent $outAbs
    if (-not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop
    }

    $runId = [Guid]::NewGuid().ToString('N')
    $workDocx = Join-Path $env:TEMP ("cn_cea_points_{0}.docx" -f $runId)
    Copy-Item -LiteralPath $TemplatePath -Destination $workDocx -Force

    try {
        Write-Host ("[CEA-POINTS] Generation dynamique depuis DOCX : {0}" -f (Split-Path -Leaf $TemplatePath)) -ForegroundColor DarkCyan
        if (-not (Set-CnsDocxTemplatePlaceholders -DocxPath $workDocx -Placeholders $Placeholders)) {
            return $null
        }
        if (-not (Convert-DocxToPdfUsingLibreOffice -DocxPath $workDocx -PdfPath $outAbs)) {
            return $null
        }
    }
    finally {
        if (Test-Path -LiteralPath $workDocx) {
            if (-not [string]::IsNullOrWhiteSpace($env:CN_KEEP_CEA_POINTS_DOCX)) {
                Write-Host ("[CEA-POINTS] DOCX conserve (CN_KEEP_CEA_POINTS_DOCX) : {0}" -f $workDocx) -ForegroundColor DarkYellow
            }
            else {
                Remove-Item -LiteralPath $workDocx -Force -ErrorAction SilentlyContinue
            }
        }
        $loPdfSide = Join-Path $env:TEMP ([System.IO.Path]::GetFileNameWithoutExtension($workDocx) + '.pdf')
        if (Test-Path -LiteralPath $loPdfSide) {
            Remove-Item -LiteralPath $loPdfSide -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not (Test-Path -LiteralPath $outAbs)) {
        Write-Warning '[CEA-POINTS] PDF non produit apres conversion DOCX vers PDF.'
        return $null
    }
    Write-Host ("[CEA-POINTS] PDF genere dynamiquement : {0}" -f (Split-Path -Leaf $outAbs)) -ForegroundColor Green
    return $outAbs
}

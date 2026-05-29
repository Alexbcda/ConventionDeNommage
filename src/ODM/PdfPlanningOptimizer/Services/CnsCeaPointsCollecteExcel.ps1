# CEA Points de collecte : template XLSX -> PDF.

. (Join-Path $PSScriptRoot 'CnsDestructionCertificateExcel.ps1')

function Get-CnsCeaPointsDeCollecteTemplatePath {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    $templatePath = Join-Path $repoRoot 'templates\CeaPointsDeCollectes.xlsx'

    if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
        throw 'Template CeaPointsDeCollectes.xlsx introuvable dans le dossier templates/'
    }

    return [System.IO.Path]::GetFullPath($templatePath)
}

function Get-CnsCeaPointCollecteDescriptionFromFragSlice {
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

function Get-CnsCeaPointsDeCollectePlaceholdersExcel {
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
        $base = Get-CnsDestructionCertificateBasePlaceholders -WorkOrderEntity $WorkOrderEntity -SegmentMeta $SegmentMeta -VisitDate $VisitDate
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
        Date_Collecte              = $dateCollecte
        Client_ID                  = $clientId
        Client_Nom                 = $clientNom
        Client_Adresse             = $clientAdresse
        Client_CP                  = $cp
        Client_Ville               = $ville
        ODM_Numero                 = $odmNum
        Collecteur_Nom             = $collecteurNom
        Collecteur_Prenom          = $collecteurPrenom
        Point_Collecte_Description = $pointDesc
    }
}

function Get-CnsCeaPointsDeCollectePlaceholders {
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
    return (Get-CnsCeaPointsDeCollectePlaceholdersExcel -WorkOrderEntity $WorkOrderEntity -PageEntity $PageEntity -SegmentMeta $SegmentMeta -VisitDate $VisitDate -FragSlicePdfPath $FragSlicePdfPath)
}

function New-CnsCeaPointsDeCollectesPdfFromExcelTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$OutPdfPath,
        [Parameter(Mandatory = $true)][hashtable]$Placeholders,
        [string]$TemplatePath
    )
    if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
        $TemplatePath = Get-CnsCeaPointsDeCollecteTemplatePath
    }
    $result = New-CnsFilledXlsxPdfFromTemplate -TemplatePath $TemplatePath -OutPdfPath $OutPdfPath -Placeholders $Placeholders -TempFilePrefix 'cn_cea_points' -KeepFilledXlsxEnvVar 'CN_KEEP_CEA_POINTS_XLSX'
    if ($null -ne $result) {
        Write-Host ("[CEA-POINTS] PDF genere dynamiquement : {0}" -f (Split-Path -Leaf $result)) -ForegroundColor Green
    }
    return $result
}

function New-CnsCeaPointsDeCollectesPdfFromWordTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$OutPdfPath,
        [Parameter(Mandatory = $true)][hashtable]$Placeholders,
        [string]$TemplatePath
    )
    return (New-CnsCeaPointsDeCollectesPdfFromExcelTemplate -OutPdfPath $OutPdfPath -Placeholders $Placeholders -TemplatePath $TemplatePath)
}

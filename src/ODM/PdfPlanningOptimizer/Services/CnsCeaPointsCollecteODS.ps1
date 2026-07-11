# CEA Points de collecte : template ODS -> PDF (LibreOffice).

. (Join-Path $PSScriptRoot 'CnsDestructionCertificateODS.ps1')

function Get-CnsCeaPointsDeCollecteTemplatePath {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    $templatePath = Join-Path $repoRoot 'templates\CeaPointsDeCollectes.ods'

    if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
        throw 'Template CeaPointsDeCollectes.ods introuvable dans le dossier templates/'
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
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    [string]$dateCollecte = $VisitDate.ToString('dd/MM/yyyy', $inv)

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

    return [ordered]@{
        Date_Collecte = $dateCollecte
    }
}

function New-CnsCeaPointsDeCollectesPdfFromOdsTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$OutPdfPath,
        [Parameter(Mandatory = $true)][hashtable]$Placeholders,
        [string]$TemplatePath
    )
    if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
        $TemplatePath = Get-CnsCeaPointsDeCollecteTemplatePath
    }
    $result = New-CnsFilledOdsPdfFromTemplate -TemplatePath $TemplatePath -OutPdfPath $OutPdfPath -Placeholders $Placeholders -TempFilePrefix 'cn_cea_points' -KeepFilledOdsEnvVar 'CN_KEEP_CEA_POINTS_ODS'
    if ($null -ne $result) {
        $msg = "[CEA-POINTS] PDF genere dynamiquement : {0}" -f (Split-Path -Leaf $result)
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log $msg 'INFO'
        }
        else {
            Write-Host $msg -ForegroundColor Green
        }
    }
    return $result
}

function New-CnsCeaPointsDeCollectesPdfFromWordTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$OutPdfPath,
        [Parameter(Mandatory = $true)][hashtable]$Placeholders,
        [string]$TemplatePath
    )
    return (New-CnsCeaPointsDeCollectesPdfFromOdsTemplate -OutPdfPath $OutPdfPath -Placeholders $Placeholders -TemplatePath $TemplatePath)
}

function New-CnsCeaPointsDeCollectesPdfFromExcelTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$OutPdfPath,
        [Parameter(Mandatory = $true)][hashtable]$Placeholders,
        [string]$TemplatePath
    )
    return (New-CnsCeaPointsDeCollectesPdfFromOdsTemplate -OutPdfPath $OutPdfPath -Placeholders $Placeholders -TemplatePath $TemplatePath)
}

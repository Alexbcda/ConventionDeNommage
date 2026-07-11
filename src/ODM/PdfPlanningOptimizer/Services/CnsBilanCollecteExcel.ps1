# Bilan de collecte : template XLSX -> PDF.

. (Join-Path $PSScriptRoot 'CnsCertificatePlaceholderCommon.ps1')
. (Join-Path $PSScriptRoot 'CnsExcelTemplateEngine.ps1')

function Get-CnsBilanCollecteTemplatePath {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    $templatePath = Join-Path $repoRoot 'templates\BilanDeCollecte.xlsx'

    if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
        throw 'Template BilanDeCollecte.xlsx introuvable dans le dossier templates/'
    }

    return [System.IO.Path]::GetFullPath($templatePath)
}

function Get-CnsBilanCollectePlaceholdersExcel {
    param(
        [AllowNull()]
        $SegmentMeta,
        [Parameter(Mandatory = $true)]
        [datetime]$VisitDate
    )
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    [string]$dateCollecte = $VisitDate.ToString('dd/MM/yyyy', $inv)

    [string]$collecteurRaw = ''
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
        try { $collecteurRaw = [string]$SegmentMeta.Collecteur } catch { }
    }

    $collecteurResolved = Resolve-CnsCollecteurFieldsForCertificate -CollecteurExcelRaw $collecteurRaw

    return [ordered]@{
        Date_Collecte     = $dateCollecte
        Collecteur_Nom    = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value ([string]$collecteurResolved.Nom))
        Collecteur_Prenom = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value ([string]$collecteurResolved.Prenom))
    }
}

function Get-CnsBilanCollectePlaceholders {
    param(
        [AllowNull()]
        $SegmentMeta,
        [Parameter(Mandatory = $true)]
        [datetime]$VisitDate
    )
    return (Get-CnsBilanCollectePlaceholdersExcel -SegmentMeta $SegmentMeta -VisitDate $VisitDate)
}

function New-CnsBilanCollectePdfFromExcelTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$OutPdfPath,
        [Parameter(Mandatory = $true)][hashtable]$Placeholders,
        [string]$TemplatePath
    )
    if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
        $TemplatePath = Get-CnsBilanCollecteTemplatePath
    }
    return (New-CnsFilledXlsxPdfFromTemplate -TemplatePath $TemplatePath -OutPdfPath $OutPdfPath -Placeholders $Placeholders -TempFilePrefix 'cn_bilan_collecte' -KeepFilledXlsxEnvVar 'CN_KEEP_BILAN_COLLECTE_XLSX')
}

function New-CnsBilanCollectePdfFromWordTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$OutPdfPath,
        [Parameter(Mandatory = $true)][hashtable]$Placeholders,
        [string]$TemplatePath
    )
    return (New-CnsBilanCollectePdfFromExcelTemplate -OutPdfPath $OutPdfPath -Placeholders $Placeholders -TemplatePath $TemplatePath)
}

# Certificat de destruction : template ODS -> PDF (LibreOffice).

. (Join-Path $PSScriptRoot 'CnsCertificatePlaceholderCommon.ps1')
. (Join-Path $PSScriptRoot '..\..\..\Common\CnsOdsTemplateEngine.ps1')
. (Join-Path $PSScriptRoot '..\..\..\Common\CnsFrenchHolidays.ps1')
. (Join-Path $PSScriptRoot '..\..\Agents\Get-RandomTrieurFromDatabase.ps1')

function Get-CnsDestructionCertificateTemplatePath {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    $templatePath = Join-Path $repoRoot 'templates\CertificatDeDestruction.ods'

    if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
        throw 'Template CertificatDeDestruction.ods introuvable dans le dossier templates/'
    }

    return [System.IO.Path]::GetFullPath($templatePath)
}

function Get-CnsDestructionCertificateBasePlaceholders {
    param(
        [Parameter(Mandatory = $true)]
        $WorkOrderEntity,
        [AllowNull()]
        $SegmentMeta,
        [Parameter(Mandatory = $true)]
        [datetime]$VisitDate
    )
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    [string]$dateCollecte = $VisitDate.ToString('dd/MM/yyyy', $inv)

    [string]$clientId = ''
    [string]$clientNom = ''
    [string]$street = ''
    [string]$cp = ''
    [string]$ville = ''
    [string]$odmNum = ''
    try { $clientId = [string]$WorkOrderEntity.ClientID } catch { }
    try { $clientNom = [string]$WorkOrderEntity.ClientName } catch { }
    try { $odmNum = [string]$WorkOrderEntity.WorkOrder } catch { }
    if ([string]::IsNullOrWhiteSpace($odmNum)) {
        foreach ($svc in @($WorkOrderEntity.Services)) {
            if ($null -eq $svc) { continue }
            try {
                $od = [string]$svc.ODM
                if (-not [string]::IsNullOrWhiteSpace($od)) { $odmNum = $od.Trim(); break }
            }
            catch { }
        }
    }
    if ($null -ne $WorkOrderEntity.Address) {
        try { $street = [string]$WorkOrderEntity.Address.Street } catch { }
        try { $cp = [string]$WorkOrderEntity.Address.PostalCode } catch { }
        try { $ville = [string]$WorkOrderEntity.Address.City } catch { }
    }

    [string]$collecteurRaw = ''
    [string]$vehicule = ''
    if ($null -ne $SegmentMeta) {
        try { $collecteurRaw = [string]$SegmentMeta.Collecteur } catch { }
        try { $vehicule = [string]$SegmentMeta.Vehicule } catch { }
    }
    $collecteurResolved = Resolve-CnsCollecteurFieldsForCertificate -CollecteurExcelRaw $collecteurRaw

    return [ordered]@{
        Date_Collecte     = $dateCollecte
        Client_ID         = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $clientId)
        Client_Nom        = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $clientNom)
        Client_Adresse    = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $street)
        Client_CP         = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $cp)
        Client_Ville      = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $ville)
        Collecteur_Nom    = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value ([string]$collecteurResolved.Nom))
        Collecteur_Prenom = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value ([string]$collecteurResolved.Prenom))
        Vehicule_Immat    = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $vehicule)
        ODM_Numero        = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $odmNum)
    }
}

function Get-CnsDestructionCertificatePlaceholders {
    param(
        [Parameter(Mandatory = $true)]
        $WorkOrderEntity,
        [AllowNull()]
        $SegmentMeta,
        [Parameter(Mandatory = $true)]
        [datetime]$VisitDate
    )
    $base = Get-CnsDestructionCertificateBasePlaceholders -WorkOrderEntity $WorkOrderEntity -SegmentMeta $SegmentMeta -VisitDate $VisitDate
    $visitDt = $VisitDate
    try {
        $parsed = [datetime]::ParseExact([string]$base.Date_Collecte, 'dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
        $visitDt = $parsed
    }
    catch { }

    $dateFin = Add-2WorkingDaysWithFrenchHolidays -StartDate $visitDt
    [string]$dateFinStr = Format-CnsFrenchDate -Date $dateFin
    $trieur = Get-RandomTrieurFromDatabase

    $ph = [ordered]@{}
    foreach ($entry in $base.GetEnumerator()) {
        $ph[$entry.Key] = $entry.Value
    }
    $ph['Date_FinDestruction'] = $dateFinStr
    $ph['Trieur_Nom'] = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value ([string]$trieur.Nom))
    $ph['Trieur_Prenom'] = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value ([string]$trieur.Prenom))
    return $ph
}

function New-CnsDestructionCertificatePdfFromOdsTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$OutPdfPath,
        [Parameter(Mandatory = $true)][hashtable]$Placeholders,
        [string]$TemplatePath
    )
    if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
        $TemplatePath = Get-CnsDestructionCertificateTemplatePath
    }
    return (New-CnsFilledOdsPdfFromTemplate -TemplatePath $TemplatePath -OutPdfPath $OutPdfPath -Placeholders $Placeholders -TempFilePrefix 'cn_destr_cert' -KeepFilledOdsEnvVar 'CN_KEEP_DESTRUCTION_CERT_ODS')
}

function New-CnsDestructionCertificatePdfFromWordTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$OutPdfPath,
        [Parameter(Mandatory = $true)][hashtable]$Placeholders,
        [string]$TemplatePath
    )
    return (New-CnsDestructionCertificatePdfFromOdsTemplate -OutPdfPath $OutPdfPath -Placeholders $Placeholders -TemplatePath $TemplatePath)
}

function New-CnsDestructionCertificatePdfFromExcelTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$OutPdfPath,
        [Parameter(Mandatory = $true)][hashtable]$Placeholders,
        [string]$TemplatePath
    )
    return (New-CnsDestructionCertificatePdfFromOdsTemplate -OutPdfPath $OutPdfPath -Placeholders $Placeholders -TemplatePath $TemplatePath)
}

function Set-CnsOdsTemplatePlaceholders {
    param(
        [Parameter(Mandatory = $true)][string]$OdsPath,
        [Parameter(Mandatory = $true)][hashtable]$Placeholders,
        [string]$OutputPath
    )
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = $OdsPath
    }
    return (Set-OdsTemplatePlaceholders -OdsPath $OdsPath -Placeholders $Placeholders -OutputPath $OutputPath)
}

function Set-CnsDocxTemplatePlaceholders {
    param(
        [Parameter(Mandatory = $true)][string]$DocxPath,
        [Parameter(Mandatory = $true)][hashtable]$Placeholders
    )
    return (Set-OdsTemplatePlaceholders -OdsPath $DocxPath -Placeholders $Placeholders -OutputPath $DocxPath)
}

function Convert-DocxToPdfUsingLibreOffice {
    param(
        [Parameter(Mandatory = $true)][string]$DocxPath,
        [Parameter(Mandatory = $true)][string]$PdfPath
    )
    return (Convert-OdsToPdf -OdsPath $DocxPath -PdfPath $PdfPath)
}

function Test-CnsMicrosoftWordAvailable {
    return $false
}

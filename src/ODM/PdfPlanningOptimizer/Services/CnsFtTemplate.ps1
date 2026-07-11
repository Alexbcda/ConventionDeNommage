# France Travail — point de collecte : template XLSX -> PDF.

. (Join-Path $PSScriptRoot 'CnsDestructionCertificateExcel.ps1')

function ConvertTo-CnsFtPointCollecteDisplay {
    <#
    .SYNOPSIS
        Nettoie le libelle FT pour FT.xlsx : conserve uniquement le texte avant le premier [.
    #>
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$RawLabel
    )
    if (Get-Command ConvertTo-CnsFtBracketDisplayLabel -ErrorAction SilentlyContinue) {
        return ConvertTo-CnsFtBracketDisplayLabel -RawLabel $RawLabel
    }
    if ([string]::IsNullOrWhiteSpace($RawLabel)) { return '' }
    $t = [string]$RawLabel.Trim()
    if ($t -match '^(.*?)\s*[\[［].*$') {
        $t = $Matches[1].Trim()
    }
    return ([regex]::Replace($t, '\s+', ' ')).Trim()
}

function script:Write-CnsFtLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Level = 'INFO',
        $Data = $null
    )
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log ("[FT] " + $Message) $Level $Data
        return
    }
    Write-Host ("[FT] {0}" -f $Message) -ForegroundColor $(if ($Level -eq 'WARN') { 'Yellow' } elseif ($Level -eq 'ERROR') { 'Red' } else { 'DarkCyan' })
}

function Get-CnsFtTemplatePath {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    $templatePath = Join-Path $repoRoot 'templates\FT.xlsx'

    if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
        throw 'Template FT.xlsx introuvable dans le dossier templates/'
    }

    return [System.IO.Path]::GetFullPath($templatePath)
}

function Get-CnsFtPlaceholders {
    param(
        [AllowNull()]
        $WorkOrderEntity,
        [AllowNull()]
        $PageEntity,
        [AllowNull()]
        $SegmentMeta,
        [Parameter(Mandatory = $true)]
        [datetime]$VisitDate,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$PointCollecte
    )

    if (-not [string]::IsNullOrWhiteSpace($PointCollecte)) {
        $pointCollecteDisplay = ConvertTo-CnsFtPointCollecteDisplay -RawLabel $PointCollecte
    }
    elseif ($null -ne $WorkOrderEntity) {
        $clientName = [string]$WorkOrderEntity.ClientName
        $pointCollecteDisplay = ConvertTo-CnsFtPointCollecteDisplay -RawLabel $clientName
    }
    else {
        $pointCollecteDisplay = ''
    }

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
        # FT.xlsx affiche {{Client_Nom}} sous "Agence" — pas {{Point_Collecte}}
        if (-not [string]::IsNullOrWhiteSpace($pointCollecteDisplay)) {
            $clientNom = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $pointCollecteDisplay)
        }
        elseif ($clientNom -match '(?i)^FT\s+') {
            $clientNom = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value (ConvertTo-CnsFtPointCollecteDisplay -RawLabel $clientNom))
        }
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
            try {
                $dj = [string]$SegmentMeta.DisplayDateJM
                if (-not [string]::IsNullOrWhiteSpace($dj)) {
                    $dateCollecte = $dj.Trim()
                }
            }
            catch { }
            $collecteurResolved = Resolve-CnsCollecteurFieldsForCertificate -CollecteurExcelRaw ([string]$SegmentMeta.Collecteur)
            $collecteurNom = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value ([string]$collecteurResolved.Nom))
            $collecteurPrenom = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value ([string]$collecteurResolved.Prenom))
        }
    }

    return [ordered]@{
        Date_Collecte     = $dateCollecte
        Point_Collecte    = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $pointCollecteDisplay)
        Client_ID         = $clientId
        Client_Nom        = $clientNom
        Client_Adresse    = $street
        Client_CP         = $cp
        Client_Ville      = $ville
        ODM_Numero        = $odmNum
        Collecteur_Nom    = $collecteurNom
        Collecteur_Prenom = $collecteurPrenom
    }
}

function New-CnsFtPdfFromExcelTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$OutPdfPath,
        [Parameter(Mandatory = $true)][hashtable]$Placeholders,
        [string]$TemplatePath
    )
    if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
        $TemplatePath = Get-CnsFtTemplatePath
    }
    $pointLabel = if ($Placeholders.ContainsKey('Point_Collecte')) { [string]$Placeholders['Point_Collecte'] } else { '' }
    script:Write-CnsFtLog -Message ("Debut generation PDF FT pour : {0}" -f $pointLabel) -Level 'INFO'
    script:Write-CnsFtLog -Message ("Template : {0}" -f $TemplatePath) -Level 'DEBUG'
    $ftGenSw = [System.Diagnostics.Stopwatch]::StartNew()
    $result = New-CnsFilledXlsxPdfFromTemplate -TemplatePath $TemplatePath -OutPdfPath $OutPdfPath -Placeholders $Placeholders `
        -TempFilePrefix 'cn_ft_collecte' -KeepFilledXlsxEnvVar 'CN_KEEP_FT_XLSX'
    $ftGenSw.Stop()
    if ($null -ne $result) {
        script:Write-CnsFtLog -Message ("PDF genere : {0} ({1} ms)" -f (Split-Path -Leaf $result), $ftGenSw.ElapsedMilliseconds) -Level 'INFO'
        Write-Host ("[FT-POINTS] PDF genere dynamiquement : {0}" -f (Split-Path -Leaf $result)) -ForegroundColor Green
    }
    else {
        script:Write-CnsFtLog -Message ("Generation echouee apres {0} ms" -f $ftGenSw.ElapsedMilliseconds) -Level 'WARN'
    }
    return $result
}

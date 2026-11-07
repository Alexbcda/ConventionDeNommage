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
    $templatePath = Join-Path $repoRoot 'templates\FicheInventaireFranceTravail.xlsx'

    if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
        throw 'Template FicheInventaireFranceTravail.xlsx introuvable dans le dossier templates/'
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

function script:Get-CnsFtSiteForClientId {
    param(
        [Parameter(Mandatory = $true)]$Worksheet,
        [Parameter(Mandatory = $true)][int]$ClientId
    )
    $dim = $Worksheet.Dimension
    if ($null -eq $dim) { return $null }
    for ($r = 2; $r -le $dim.End.Row; $r++) {
        $raw = $Worksheet.Cells[$r, 1].Value
        $rowId = $null
        if ($raw -is [ValueType]) {
            try { $rowId = [int]$raw } catch { $rowId = $null }
        }
        else {
            $rowId = script:ConvertTo-CnsFtClientIdNumber -ClientId ([string]$raw)
        }
        if ($null -eq $rowId -or [int]$rowId -ne $ClientId) { continue }
        $site = [string]$Worksheet.Cells[$r, 6].Text
        if ([string]::IsNullOrWhiteSpace($site)) {
            $site = [string]$Worksheet.Cells[$r, 6].Value
        }
        return $site.Trim()
    }
    return $null
}

function script:ConvertTo-CnsFtClientIdNumber {
    param([AllowNull()][string]$ClientId)
    if ([string]::IsNullOrWhiteSpace($ClientId)) { return $null }
    $parsed = 0
    $ok = [int]::TryParse(
        $ClientId.Trim(),
        [System.Globalization.NumberStyles]::Integer,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$parsed
    )
    if (-not $ok -or $parsed -lt 0) { return $null }
    return $parsed
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
    $clientRaw = if ($Placeholders.ContainsKey('Client_ID')) { [string]$Placeholders['Client_ID'] } else { '' }
    $clientIdNum = script:ConvertTo-CnsFtClientIdNumber -ClientId $clientRaw
    if ($null -eq $clientIdNum) {
        script:Write-CnsFtLog -Message ("ID client FT non numerique, B4 non ecrit : [{0}]" -f $clientRaw) -Level 'WARN'
        return $null
    }

    script:Write-CnsFtLog -Message ("Debut generation PDF FT pour : {0} (ClientID={1})" -f $pointLabel, $clientIdNum) -Level 'INFO'
    script:Write-CnsFtLog -Message ("Template : {0}" -f $TemplatePath) -Level 'DEBUG'
    $ftGenSw = [System.Diagnostics.Stopwatch]::StartNew()

    $outAbs = [System.IO.Path]::GetFullPath($OutPdfPath)
    $outDir = Split-Path -Parent $outAbs
    if (-not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop
    }
    $runId = [Guid]::NewGuid().ToString('N')
    $workXlsx = Join-Path $env:TEMP ("cn_ft_collecte_{0}.xlsx" -f $runId)
    Copy-Item -LiteralPath $TemplatePath -Destination $workXlsx -Force

    $result = $null
    try {
        if (Get-Command script:Ensure-ImportExcelModule -ErrorAction SilentlyContinue) {
            script:Ensure-ImportExcelModule
        }
        else {
            Import-Module ImportExcel -ErrorAction Stop
        }

        $package = Open-ExcelPackage -Path $workXlsx
        try {
            $fiche = $package.Workbook.Worksheets['Fiche Inventaire']
            if ($null -eq $fiche) {
                throw 'Onglet Fiche Inventaire introuvable.'
            }
            $fiche.Cells[4, 2].Value = [int]$clientIdNum
            $fiche.Cells[4, 2].Style.Numberformat.Format = '0'

            $dateText = ''
            if ($Placeholders.ContainsKey('Date_Collecte')) {
                $dateText = ([string]$Placeholders['Date_Collecte']).Trim()
            }
            if ([string]::IsNullOrWhiteSpace($dateText)) {
                throw 'Date_Collecte absente : la date ODM ne peut pas etre ecrite en E1.'
            }
            $fiche.Cells[1, 5].Value = $dateText
            foreach ($addr in @('F1', 'E2', 'F2')) {
                $sibling = $fiche.Cells[$addr]
                if (-not [string]::IsNullOrWhiteSpace([string]$sibling.Formula)) {
                    $sibling.Formula = ''
                }
                $sibling.Value = $null
            }

            $fiche.PrinterSettings.PrintArea = $fiche.Cells['A1:F30']

            $liste = $package.Workbook.Worksheets['Liste des sites']
            if ($null -eq $liste) {
                throw 'Onglet Liste des sites introuvable.'
            }
            $expectedSite = script:Get-CnsFtSiteForClientId -Worksheet $liste -ClientId ([int]$clientIdNum)
            if ([string]::IsNullOrWhiteSpace($expectedSite)) {
                script:Write-CnsFtLog -Message ("ID client {0} absent de Liste des sites." -f $clientIdNum) -Level 'WARN'
            }
            $liste.Hidden = [OfficeOpenXml.eWorkSheetHidden]::Hidden

            Close-ExcelPackage $package
            $package = $null
        }
        finally {
            if ($null -ne $package) {
                Close-ExcelPackage $package -NoSave -ErrorAction SilentlyContinue
            }
        }

        $converted = Convert-XlsxToPdf -XlsxPath $workXlsx -PdfPath $outAbs -FullCalculation -VerifyCalculatedSite -CalculatedSiteMustEqual $expectedSite -AfterCalculation {
            param($Workbook)
            $ws = $Workbook.Worksheets.Item('Fiche Inventaire')
            $shown = ''
            try { $shown = [string]$ws.Range('B5').Text } catch { $shown = '' }
            if ([string]::IsNullOrWhiteSpace($shown)) {
                try { $shown = [string]$ws.Range('B5').Value2 } catch { $shown = '' }
            }
            $shown = $shown.Trim()
            $match = -not [string]::IsNullOrWhiteSpace($expectedSite) -and [string]::Equals($shown, $expectedSite, [System.StringComparison]::OrdinalIgnoreCase)
            if (-not $match) {
                script:Write-CnsFtLog -Message ("Recalcul FT non confirme : B4={0}, B5=[{1}], site attendu=[{2}]. La fiche est generee quand meme." -f $clientIdNum, $shown, $expectedSite) -Level 'WARN'
            }
            return $true
        }
        if ($converted) {
            $result = $outAbs
        }
    }
    catch {
        script:Write-CnsFtLog -Message ("Echec ecriture B4 / masquage Liste des sites : {0}" -f $_.Exception.Message) -Level 'WARN'
        $result = $null
    }
    finally {
        if (Test-Path -LiteralPath $workXlsx) {
            $keep = $false
            try { $keep = -not [string]::IsNullOrWhiteSpace((Get-Item Env:CN_KEEP_FT_XLSX -ErrorAction SilentlyContinue).Value) } catch { $keep = $false }
            if ($keep) {
                Write-Host ("[XLSX] Fichier conserve (CN_KEEP_FT_XLSX) : {0}" -f $workXlsx) -ForegroundColor DarkYellow
            }
            else {
                Remove-Item -LiteralPath $workXlsx -Force -ErrorAction SilentlyContinue
            }
        }
        $loSide = Join-Path $env:TEMP ([System.IO.Path]::GetFileNameWithoutExtension($workXlsx) + '.pdf')
        if ((Test-Path -LiteralPath $loSide) -and ($loSide -ne $outAbs)) {
            Remove-Item -LiteralPath $loSide -Force -ErrorAction SilentlyContinue
        }
    }

    $ftGenSw.Stop()
    if (-not [string]::IsNullOrWhiteSpace($result) -and (Test-Path -LiteralPath $result)) {
        script:Write-CnsFtLog -Message ("PDF genere : {0} ({1} ms)" -f (Split-Path -Leaf $result), $ftGenSw.ElapsedMilliseconds) -Level 'INFO'
        Write-Host ("[FT-POINTS] PDF genere dynamiquement : {0}" -f (Split-Path -Leaf $result)) -ForegroundColor Green
        return $result
    }
    script:Write-CnsFtLog -Message ("Generation echouee apres {0} ms" -f $ftGenSw.ElapsedMilliseconds) -Level 'WARN'
    return $null
}

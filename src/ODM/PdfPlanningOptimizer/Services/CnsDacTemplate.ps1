# DAC Bio-dechets : template XLSX (DAC.xlsx) -> N pages PDF (1 par bioseau theorique).

. (Join-Path $PSScriptRoot 'CnsDestructionCertificateExcel.ps1')

$script:CnsDacSheetDacName = 'DAC pour BIO'
$script:CnsDacSheetCentreName = 'Centre exploitations'
$script:CnsDacSheetExutoireName = 'Excutoires'

# Colonnes Excutoires (ligne 5 = libelle etablissement) — fiche DAC.xlsx uniquement.
# Le planning est la seule source de verite pour CHOISIR l'exutoire (pas de mapping centre).
$script:CnsDacExutoireColumnByKey = @{
    adfe       = 3   # C
    rovalterre = 6   # F
    savoie     = 9   # I
    murianette = 12  # L
}

function Get-CnsDacTemplatePath {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    $candidates = @(
        (Join-Path $repoRoot 'templates\planning\destruction\DAC.xlsx'),
        (Join-Path $repoRoot 'templates\DAC.xlsx')
    )
    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            return [System.IO.Path]::GetFullPath($p)
        }
    }
    throw 'Template DAC.xlsx introuvable (templates/planning/destruction/DAC.xlsx).'
}

function script:ConvertTo-CnsDacNormalizedMatchText {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { return '' }
    if (Get-Command ConvertTo-CnsMetierMatchNormalizedText -ErrorAction SilentlyContinue) {
        return (ConvertTo-CnsMetierMatchNormalizedText -Text $Text)
    }
    $t = ([string]$Text).Trim()
    if ($t.Length -lt 1) { return '' }
    $t = $t.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $t.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    return [regex]::Replace($sb.ToString().ToLowerInvariant(), '\s+', ' ').Trim()
}

function Get-CnsBioDechetsTheoreticalQuantityFromLines {
    <#
    .SYNOPSIS
        Extrait le nombre theorique de bioseaux/bacs depuis les lignes ODM (motif /Y).
    .NOTES
        Formes observees : Bioseau 20 L /2 kg | Bac 120L /1 kg | Bac marron + Biodechet/couvercle /Y | Vrac /Y.
        Ne matche que dans un contexte Bio (evite /Y d'autres prestations).
    #>
    param(
        [AllowEmptyCollection()]
        [string[]]$Lines = @()
    )
    if ($null -eq $Lines -or @($Lines).Count -lt 1) { return 0 }

    $rxQty = [regex]'(?i)(?:bioseau\s*\d*\s*l?|bac\s*\d*\s*l?(?:\s*marron)?|vrac|biod[eé]chets?|couvercle)\s*/\s*(\d+)\b'
    $rxBareSlash = [regex]'(?i)/\s*(\d+)\s*kg\b'
    $rxBioCtx = [regex]'(?i)bio[\s\-]*d[eé]chets?|bioseau|biod[eé]chet|en\s+bioseau|\bvrac\b'

    $arr = @($Lines | ForEach-Object { [string]$_ })
    for ($i = 0; $i -lt $arr.Count; $i++) {
        $ln = $arr[$i]
        if ([string]::IsNullOrWhiteSpace($ln)) { continue }
        $norm = script:ConvertTo-CnsDacNormalizedMatchText -Text $ln
        $isBioLine = ($norm -match 'collecte\s+de\s+bio') -or [bool]$rxBioCtx.IsMatch($norm)
        if (-not $isBioLine) {
            # Ligne suivante d'un bloc Bac marron (Biodechet /Y ou couvercle /Y)
            $prevNorm = if ($i -gt 0) { script:ConvertTo-CnsDacNormalizedMatchText -Text $arr[$i - 1] } else { '' }
            if ($prevNorm -notmatch 'bac\s*\d') { continue }
            if ($norm -notmatch 'biod|couvercle|/\s*\d+') { continue }
            $isBioLine = $true
        }
        if (-not $isBioLine) { continue }

        $window = $ln
        if ($i + 1 -lt $arr.Count) { $window = $window + ' ' + $arr[$i + 1] }
        if ($i + 2 -lt $arr.Count) { $window = $window + ' ' + $arr[$i + 2] }

        $m = $rxQty.Match($window)
        if ($m.Success) {
            $n = 0
            if ([int]::TryParse($m.Groups[1].Value, [ref]$n) -and $n -gt 0) { return $n }
        }
        $m2 = $rxBareSlash.Match($window)
        if ($m2.Success -and $rxBioCtx.IsMatch($window)) {
            $n2 = 0
            if ([int]::TryParse($m2.Groups[1].Value, [ref]$n2) -and $n2 -gt 0) { return $n2 }
        }
    }
    return 0
}

function script:Get-CnsDacActiveCentreObject {
    if (Get-Command Get-CurrentCentre -ErrorAction SilentlyContinue) {
        try {
            $c = Get-CurrentCentre
            if ($null -ne $c) { return $c }
        }
        catch { }
    }
    if ($null -ne $script:ActiveCentre) { return $script:ActiveCentre }
    if ($null -ne $script:CurrentCentre) { return $script:CurrentCentre }
    return $null
}

function script:Ensure-CnsDacImportExcel {
    # 1) Déjà chargé et sain ?
    $m = Get-Module -Name ImportExcel -ErrorAction SilentlyContinue
    if ($m -and (Get-Command Open-ExcelPackage -ErrorAction SilentlyContinue)) { return }

    # 2) Loader bundlé — SANS préfixe script: dans Get-Command
    if (Get-Command Ensure-ImportExcelModule -ErrorAction SilentlyContinue) {
        try { Ensure-ImportExcelModule } catch { }
        if (Get-Command Open-ExcelPackage -ErrorAction SilentlyContinue) { return }
    }

    # 3) Fallback chemins absolus
    $candidates = New-Object System.Collections.Generic.List[string]
    try {
        $root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..')).Path
        [void]$candidates.Add((Join-Path $root 'runtime\ImportExcel\ImportExcel.psd1'))
    } catch { }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        [void]$candidates.Add((Join-Path $env:LOCALAPPDATA 'ASSISTANT\runtime\ImportExcel\ImportExcel.psd1'))
    }

    foreach ($psd1 in $candidates) {
        if ([string]::IsNullOrWhiteSpace($psd1)) { continue }
        if (-not (Test-Path -LiteralPath $psd1 -PathType Leaf)) { continue }
        Import-Module -Name $psd1 -Force -ErrorAction Stop
        if (Get-Command Open-ExcelPackage -ErrorAction SilentlyContinue) { return }
    }

    throw "[DAC] ImportExcel introuvable ou invalide. Open-ExcelPackage indisponible. Chemins testés : $($candidates -join ' ; ')"
}

function script:Get-CnsDacWorksheetCellText {
    param($Worksheet, [int]$Row, [int]$Column)
    if ($null -eq $Worksheet) { return '' }
    try {
        $cell = $Worksheet.Cells[$Row, $Column]
        if ($null -eq $cell) { return '' }
        if ($null -ne $cell.Value) { return ([string]$cell.Value).Trim() }
        return ([string]$cell.Text).Trim()
    }
    catch {
        return ''
    }
}

function script:Set-CnsDacWorksheetCellValue {
    param($Worksheet, [string]$Address, [AllowNull()]$Value)
    if ($null -eq $Worksheet) { return }
    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    try {
        $Worksheet.Cells[$Address].Value = $text
    }
    catch {
        Write-Warning ("[DAC] Impossible d'ecrire {0} : {1}" -f $Address, $_.Exception.Message)
    }
}

function Get-CnsDacCentreExploitationInfoFromPackage {
    <#
    .SYNOPSIS
        Lit adresse / CP / SIRET / contact depuis l'onglet Centre exploitations (colonne du centre actif).
    #>
    param(
        [Parameter(Mandatory = $true)]$Package,
        [AllowNull()]$Centre = $null
    )
    $empty = [pscustomobject]@{
        CentreId   = ''
        CentreName = ''
        Adresse    = ''
        CpVille    = ''
        Siret      = ''
        Contact    = ''
        Column     = 0
    }
    if ($null -eq $Centre) { $Centre = script:Get-CnsDacActiveCentreObject }
    if ($null -eq $Centre) { return $empty }

    [string]$centreId = ''
    [string]$centreName = ''
    try { $centreId = [string]$Centre.id } catch { }
    try { $centreName = [string]$Centre.name } catch { }
    $empty.CentreId = $centreId
    $empty.CentreName = $centreName

    $ws = $Package.Workbook.Worksheets[$script:CnsDacSheetCentreName]
    if ($null -eq $ws) { return $empty }

    $needles = New-Object System.Collections.Generic.List[string]
    foreach ($cand in @($centreName, $centreId)) {
        $n = script:ConvertTo-CnsDacNormalizedMatchText -Text $cand
        if (-not [string]::IsNullOrWhiteSpace($n)) { [void]$needles.Add($n) }
    }
    # id -> tokens (bourg-en-bresse -> bourg)
    if ($centreId -match 'bourg') { [void]$needles.Add('bourg') }
    if ($needles.Count -lt 1) { return $empty }

    $matchedCol = 0
    foreach ($col in 4..7) {
        # D=4 .. G=7, ligne 3 = en-tete centre
        $header = script:Get-CnsDacWorksheetCellText -Worksheet $ws -Row 3 -Column $col
        $hNorm = script:ConvertTo-CnsDacNormalizedMatchText -Text $header
        if ([string]::IsNullOrWhiteSpace($hNorm)) { continue }
        foreach ($needle in $needles) {
            if ($hNorm.Contains($needle)) {
                $matchedCol = $col
                break
            }
        }
        if ($matchedCol -gt 0) { break }
    }
    if ($matchedCol -lt 1) {
        Write-Warning ("[DAC] Centre '{0}' introuvable dans '{1}' (ligne 3, colonnes D-G)." -f $centreName, $script:CnsDacSheetCentreName)
        return $empty
    }

    return [pscustomobject]@{
        CentreId   = $centreId
        CentreName = $centreName
        Adresse    = (script:Get-CnsDacWorksheetCellText -Worksheet $ws -Row 4 -Column $matchedCol)
        CpVille    = (script:Get-CnsDacWorksheetCellText -Worksheet $ws -Row 5 -Column $matchedCol)
        Siret      = (script:Get-CnsDacWorksheetCellText -Worksheet $ws -Row 6 -Column $matchedCol)
        Contact    = (script:Get-CnsDacWorksheetCellText -Worksheet $ws -Row 7 -Column $matchedCol)
        Column     = $matchedCol
    }
}

function script:Resolve-CnsDacExutoireKeyFromText {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $n = script:ConvertTo-CnsDacNormalizedMatchText -Text $Text
    if ([string]::IsNullOrWhiteSpace($n)) { return $null }
    if ($n -match 'adfe') { return 'adfe' }
    if ($n -match 'rovalterre|ro val terre') { return 'rovalterre' }
    if ($n -match 'savoie\s*dechets') { return 'savoie' }
    if ($n -match 'murianette') { return 'murianette' }
    return $null
}

function Get-CnsDacExutoireInfoFromPackage {
    <#
    .SYNOPSIS
        Lit etablissement / raison sociale / adresse / contacts (lignes 5-7 et 9-14) d'une colonne Excutoires.
    #>
    param(
        [Parameter(Mandatory = $true)]$Package,
        [Parameter(Mandatory = $true)][string]$ExutoireKey
    )
    $key = $ExutoireKey.Trim().ToLowerInvariant()
    $col = 0
    if ($script:CnsDacExutoireColumnByKey.ContainsKey($key)) {
        $col = [int]$script:CnsDacExutoireColumnByKey[$key]
    }
    $ws = $Package.Workbook.Worksheets[$script:CnsDacSheetExutoireName]
    $contacts = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt 6; $i++) { [void]$contacts.Add('') }

    if ($null -eq $ws -or $col -lt 1) {
        return [pscustomobject]@{
            Key           = $key
            Column        = $col
            Etablissement = ''
            RaisonSociale = ''
            Adresse       = ''
            Contacts      = @($contacts)
        }
    }

    for ($r = 9; $r -le 14; $r++) {
        $contacts[$r - 9] = script:Get-CnsDacWorksheetCellText -Worksheet $ws -Row $r -Column $col
    }

    return [pscustomobject]@{
        Key           = $key
        Column        = $col
        Etablissement = (script:Get-CnsDacWorksheetCellText -Worksheet $ws -Row 5 -Column $col)
        RaisonSociale = (script:Get-CnsDacWorksheetCellText -Worksheet $ws -Row 6 -Column $col)
        Adresse       = (script:Get-CnsDacWorksheetCellText -Worksheet $ws -Row 7 -Column $col)
        Contacts      = @($contacts)
    }
}

function script:Test-CnsDacServiceIsAfternoon {
    param([AllowNull()][AllowEmptyString()][string]$ServiceLabel)
    $n = script:ConvertTo-CnsDacNormalizedMatchText -Text $ServiceLabel
    if ([string]::IsNullOrWhiteSpace($n)) { return $false }
    return [bool]($n -match 'apres[\s\-]*midi|afternoon')
}

function Find-CnsDacExutoireDateInPlanning {
    <#
    .SYNOPSIS
        Scan chronologique du planning : date de collecte (J+0), puis J+1..J+MaxDaysAhead.
        Retourne le premier exutoire trouve (ADFE / ROVALTERRE / Savoie / Murianette), sinon $null.
    .NOTES
        Le planning est la seule source de verite — aucun mapping centre.
    #>
    param(
        [AllowNull()]$ExcelData,
        [Parameter(Mandatory = $true)][datetime]$FromDate,
        [int]$MaxDaysAhead = 14
    )
    if ($null -eq $ExcelData -or $null -eq $ExcelData.Sheets) {
        return $null
    }

    for ($offset = 0; $offset -le $MaxDaysAhead; $offset++) {
        $candidate = $FromDate.Date.AddDays($offset)
        # Les colonnes fixes du planning ciblent lun-ven.
        if ($candidate.DayOfWeek -eq [DayOfWeek]::Saturday -or $candidate.DayOfWeek -eq [DayOfWeek]::Sunday) {
            continue
        }

        $colInfo = $null
        try {
            if (Get-Command Find-ExcelColumnFromDate -ErrorAction SilentlyContinue) {
                $colInfo = Find-ExcelColumnFromDate -ExcelData $ExcelData -VisitDate $candidate -ErrorAction SilentlyContinue
            }
            elseif (Get-Command Find-ExcelColumnFromDateFixed -ErrorAction SilentlyContinue) {
                $colInfo = Find-ExcelColumnFromDateFixed -ExcelData $ExcelData -VisitDate $candidate
            }
        }
        catch {
            $colInfo = $null
        }
        if ($null -eq $colInfo) { continue }

        $sheet = @($ExcelData.Sheets | Where-Object { [string]$_.Name -eq [string]$colInfo.SheetName } | Select-Object -First 1)[0]
        if ($null -eq $sheet -or $null -eq $sheet.Grid) { continue }

        $colZero = ([int]$colInfo.ColumnIndex) - 1
        if ($colZero -lt 0) { continue }
        $rowCount = 0
        try { $rowCount = [int]$sheet.RowCount } catch { $rowCount = @($sheet.Grid).Count }
        for ($r = 0; $r -lt $rowCount; $r++) {
            try {
                $row = $sheet.Grid[$r]
                if ($null -eq $row -or $colZero -ge @($row).Count) { continue }
                $cellText = [string]$row[$colZero]
                $key = script:Resolve-CnsDacExutoireKeyFromText -Text $cellText
                if ($null -ne $key) {
                    return [pscustomobject]@{
                        Date         = $candidate
                        ExutoireKey  = $key
                        SheetName    = [string]$colInfo.SheetName
                        ColumnIndex  = [int]$colInfo.ColumnIndex
                        MatchedText  = $cellText.Trim()
                    }
                }
            }
            catch { }
        }
    }
    return $null
}

function Resolve-CnsDacExutoireDeposit {
    <#
    .SYNOPSIS
        Date de depot H35 + cle exutoire : premier hit planning a partir de la date de collecte.
        Sans hit : date ODM, cle vide (pas de mapping centre).
    #>
    param(
        [Parameter(Mandatory = $true)][datetime]$VisitDate,
        [AllowNull()][AllowEmptyString()][string]$ServiceLabel = $null,
        [AllowNull()]$ExcelData = $null
    )
    $isAfternoon = script:Test-CnsDacServiceIsAfternoon -ServiceLabel $ServiceLabel
    $hit = Find-CnsDacExutoireDateInPlanning -ExcelData $ExcelData -FromDate $VisitDate -MaxDaysAhead 14

    [datetime]$depositDate = $VisitDate.Date
    [string]$key = ''
    if ($null -ne $hit) {
        $depositDate = [datetime]$hit.Date
        $key = [string]$hit.ExutoireKey
    }
    else {
        Write-Warning ("[DAC] Aucun exutoire trouve dans le planning a partir du {0:dd/MM/yyyy} (fenetre 14 j)." -f $VisitDate)
    }

    return [pscustomobject]@{
        DepositDate  = $depositDate
        ExutoireKey  = $key
        IsAfternoon  = $isAfternoon
        PlanningHit  = $hit
    }
}

function script:Remove-CnsDacAuxiliaryWorksheets {
    param([Parameter(Mandatory = $true)]$Package)
    $names = @(
        $script:CnsDacSheetCentreName,
        $script:CnsDacSheetExutoireName,
        'Ecoles Montélimar',
        'Ecoles Montelimar'
    )
    foreach ($n in $names) {
        try {
            $ws = $Package.Workbook.Worksheets[$n]
            if ($null -ne $ws) {
                $Package.Workbook.Worksheets.Delete($n)
            }
        }
        catch { }
    }
}

function Set-CnsDacWorksheetFilledValues {
    param(
        [Parameter(Mandatory = $true)]$Worksheet,
        [Parameter(Mandatory = $true)][hashtable]$Values
    )
    $map = @{
        I2  = 'OdmNumero'
        H8  = 'Siret'
        H9  = 'CentreAdresse'
        H10 = 'CentreCpVille'
        H11 = 'DateOdm'
        H12 = 'OdmNumero'
        H17 = 'Quantite'
        H22 = 'PointCollecteNom'
        H23 = 'PointCollecteNom'
        H24 = 'PointCollecteAdresse'
        H25 = 'CentreContact'
        H32 = 'ExutoireEtablissement'
        H33 = 'ExutoireRaisonSociale'
        H34 = 'ExutoireAdresse'
        H35 = 'ExutoireDate'
        H36 = 'ExutoireContact0'
        H37 = 'ExutoireContact1'
        H38 = 'ExutoireContact2'
        H39 = 'ExutoireContact3'
        H40 = 'ExutoireContact4'
        H41 = 'ExutoireContact5'
    }
    foreach ($addr in $map.Keys) {
        $key = [string]$map[$addr]
        $val = if ($Values.ContainsKey($key)) { $Values[$key] } else { '' }
        script:Set-CnsDacWorksheetCellValue -Worksheet $Worksheet -Address $addr -Value $val
    }
}

function New-CnsDacPdfFromExcelTemplate {
    <#
    .SYNOPSIS
        Genere N PDF DAC (N = quantite theorique de bioseaux) a partir du template Excel.
    .OUTPUTS
        string[] chemins PDF generes (vide si echec).
    #>
    param(
        [string]$TemplatePath,
        [Parameter(Mandatory = $true)]$WorkOrderEntity,
        [Parameter(Mandatory = $true)][int]$TheoreticalQuantity,
        [AllowNull()]$ExcelData = $null,
        [Parameter(Mandatory = $true)][datetime]$VisitDate,
        [AllowNull()][AllowEmptyString()][string]$OutDirectory = $null,
        [AllowNull()][AllowEmptyString()][string]$ServiceLabel = $null,
        [AllowNull()]$SegmentMeta = $null,
        [AllowNull()]$PageEntity = $null
    )

    $result = New-Object System.Collections.Generic.List[string]
    if ($TheoreticalQuantity -lt 1) {
        Write-Warning '[DAC] Quantite theorique < 1 — aucune page generee.'
        return @()
    }

    if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
        try { $TemplatePath = Get-CnsDacTemplatePath }
        catch {
            Write-Warning ("[DAC] {0}" -f $_.Exception.Message)
            return @()
        }
    }
    if (-not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
        Write-Warning ("[DAC] Template introuvable : {0}" -f $TemplatePath)
        return @()
    }

    if ([string]::IsNullOrWhiteSpace($OutDirectory)) {
        $OutDirectory = Join-Path $env:TEMP ('cn_dac_' + [Guid]::NewGuid().ToString('N'))
    }
    if (-not (Test-Path -LiteralPath $OutDirectory)) {
        $null = New-Item -ItemType Directory -Path $OutDirectory -Force -ErrorAction Stop
    }

    if ([string]::IsNullOrWhiteSpace($ServiceLabel) -and $null -ne $SegmentMeta) {
        try {
            if ($null -ne $SegmentMeta.PSObject.Properties['ServiceLabel']) {
                $ServiceLabel = [string]$SegmentMeta.ServiceLabel
            }
        }
        catch { }
    }

    script:Ensure-CnsDacImportExcel

    $centre = script:Get-CnsDacActiveCentreObject
    $centreInfo = $null
    $exutoireInfo = $null
    $deposit = $null

    # Lecture metadonnees une fois depuis une copie de travail.
    $metaXlsx = Join-Path $env:TEMP ('cn_dac_meta_' + [Guid]::NewGuid().ToString('N') + '.xlsx')
    Copy-Item -LiteralPath $TemplatePath -Destination $metaXlsx -Force
    $metaPkg = $null
    try {
        $metaPkg = Open-ExcelPackage -Path $metaXlsx
        $centreInfo = Get-CnsDacCentreExploitationInfoFromPackage -Package $metaPkg -Centre $centre
        $deposit = Resolve-CnsDacExutoireDeposit -VisitDate $VisitDate -ServiceLabel $ServiceLabel -ExcelData $ExcelData
        if (-not [string]::IsNullOrWhiteSpace([string]$deposit.ExutoireKey)) {
            $exutoireInfo = Get-CnsDacExutoireInfoFromPackage -Package $metaPkg -ExutoireKey ([string]$deposit.ExutoireKey)
        }
        else {
            $emptyContacts = @('', '', '', '', '', '')
            $exutoireInfo = [pscustomobject]@{
                Key           = ''
                Column        = 0
                Etablissement = 'Non défini'
                RaisonSociale = ''
                Adresse       = ''
                Contacts      = $emptyContacts
            }
        }
    }
    catch {
        Write-Warning ("[DAC] Lecture metadonnees template echouee : {0}" -f $_.Exception.Message)
        return @()
    }
    finally {
        if ($null -ne $metaPkg) {
            try { Close-ExcelPackage $metaPkg -NoSave } catch { }
        }
        Remove-Item -LiteralPath $metaXlsx -Force -ErrorAction SilentlyContinue
    }

    $basePh = Get-CnsDestructionCertificateBasePlaceholders -WorkOrderEntity $WorkOrderEntity -SegmentMeta $SegmentMeta -VisitDate $VisitDate
    [string]$odmNum = [string]$basePh.ODM_Numero
    [string]$clientNom = [string]$basePh.Client_Nom
    if ([string]::IsNullOrWhiteSpace($clientNom) -and $null -ne $PageEntity) {
        try { $clientNom = ConvertTo-CnsDestructionCertificatePlaceholderValue -Value ([string]$PageEntity.ClientName) } catch { }
    }
    [string]$street = [string]$basePh.Client_Adresse
    [string]$cp = [string]$basePh.Client_CP
    [string]$ville = [string]$basePh.Client_Ville
    $adresseFull = $street
    $tail = (($cp, $ville | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' ').Trim()
    if (-not [string]::IsNullOrWhiteSpace($tail)) {
        $adresseFull = if ([string]::IsNullOrWhiteSpace($adresseFull)) { $tail } else { '{0}, {1}' -f $adresseFull, $tail }
    }

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $dateOdm = $VisitDate.ToString('dd/MM/yyyy', $inv)
    $dateExu = ([datetime]$deposit.DepositDate).ToString('dd/MM/yyyy', $inv)
    $contacts = @($exutoireInfo.Contacts)
    $exuKeyLabel = if ([string]::IsNullOrWhiteSpace([string]$deposit.ExutoireKey)) { '(aucun — Non défini)' } else { [string]$deposit.ExutoireKey }

    $values = @{
        OdmNumero               = $odmNum
        Siret                   = [string]$centreInfo.Siret
        CentreAdresse           = [string]$centreInfo.Adresse
        CentreCpVille           = [string]$centreInfo.CpVille
        DateOdm                 = $dateOdm
        Quantite                = [string]$TheoreticalQuantity
        PointCollecteNom        = $clientNom
        PointCollecteAdresse    = $adresseFull
        CentreContact           = [string]$centreInfo.Contact
        ExutoireEtablissement   = [string]$exutoireInfo.Etablissement
        ExutoireRaisonSociale   = [string]$exutoireInfo.RaisonSociale
        ExutoireAdresse         = [string]$exutoireInfo.Adresse
        ExutoireDate            = $dateExu
        ExutoireContact0        = $(if ($contacts.Count -gt 0) { [string]$contacts[0] } else { '' })
        ExutoireContact1        = $(if ($contacts.Count -gt 1) { [string]$contacts[1] } else { '' })
        ExutoireContact2        = $(if ($contacts.Count -gt 2) { [string]$contacts[2] } else { '' })
        ExutoireContact3        = $(if ($contacts.Count -gt 3) { [string]$contacts[3] } else { '' })
        ExutoireContact4        = $(if ($contacts.Count -gt 4) { [string]$contacts[4] } else { '' })
        ExutoireContact5        = $(if ($contacts.Count -gt 5) { [string]$contacts[5] } else { '' })
    }

    Write-Host ("[DAC] Centre={0} ({1}) | Exutoire={2} | Depot={3} | Qty={4} | Service={5}" -f `
            $centreInfo.CentreName, $centreInfo.CentreId, $exuKeyLabel, $dateExu, $TheoreticalQuantity, `
            $(if ([string]::IsNullOrWhiteSpace($ServiceLabel)) { '(n/a)' } else { $ServiceLabel })) -ForegroundColor Cyan

    for ($i = 1; $i -le $TheoreticalQuantity; $i++) {
        $runId = [Guid]::NewGuid().ToString('N')
        $workXlsx = Join-Path $env:TEMP ("cn_dac_fill_{0}_{1}.xlsx" -f $i, $runId)
        $outPdf = Join-Path $OutDirectory ('dac_{0:D2}_{1}.pdf' -f $i, $runId)
        Copy-Item -LiteralPath $TemplatePath -Destination $workXlsx -Force

        $pkg = $null
        try {
            $pkg = Open-ExcelPackage -Path $workXlsx
            $wsDac = $pkg.Workbook.Worksheets[$script:CnsDacSheetDacName]
            if ($null -eq $wsDac) {
                $wsDac = $pkg.Workbook.Worksheets[1]
            }
            if ($null -eq $wsDac) {
                Write-Warning '[DAC] Feuille DAC pour BIO introuvable.'
                continue
            }
            Set-CnsDacWorksheetFilledValues -Worksheet $wsDac -Values $values
            try { $pkg.Workbook.Worksheets[$script:CnsDacSheetDacName].Select() } catch { }
            script:Remove-CnsDacAuxiliaryWorksheets -Package $pkg
            Close-ExcelPackage $pkg
            $pkg = $null

            if (-not (Convert-XlsxToPdf -XlsxPath $workXlsx -PdfPath $outPdf)) {
                Write-Warning ("[DAC] Conversion PDF echouee pour exemplaire {0}/{1}." -f $i, $TheoreticalQuantity)
                continue
            }
            if (Test-Path -LiteralPath $outPdf -PathType Leaf) {
                [void]$result.Add([System.IO.Path]::GetFullPath($outPdf))
            }
        }
        catch {
            Write-Warning ("[DAC] Generation exemplaire {0}/{1} echouee : {2}" -f $i, $TheoreticalQuantity, $_.Exception.Message)
            if ($null -ne $pkg) {
                try { Close-ExcelPackage $pkg -NoSave } catch { }
                $pkg = $null
            }
        }
        finally {
            if (Test-Path -LiteralPath $workXlsx) {
                if ($env:CN_KEEP_DAC_XLSX -in @('1', 'true')) {
                    Write-Host ("[DAC] XLSX conserve : {0}" -f $workXlsx) -ForegroundColor DarkYellow
                }
                else {
                    Remove-Item -LiteralPath $workXlsx -Force -ErrorAction SilentlyContinue
                }
            }
            $loSide = Join-Path $env:TEMP ([System.IO.Path]::GetFileNameWithoutExtension($workXlsx) + '.pdf')
            if (Test-Path -LiteralPath $loSide) {
                Remove-Item -LiteralPath $loSide -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if ($result.Count -gt 0) {
        Write-Host ("[DAC] {0}/{1} PDF genere(s)." -f $result.Count, $TheoreticalQuantity) -ForegroundColor Green
    }
    return @($result)
}

# ============================================================
# EntityExtractor.ps1
# Rôle : Transformer du texte PDF déjà découpé en lignes en PageEntity.
# Aucune lecture PDF, Excel, matching ou décision métier.
# ============================================================

. (Join-Path $PSScriptRoot "PdfTextNormalizer.ps1")
. (Join-Path $PSScriptRoot "..\Models\PageEntity.ps1")

#region Regex (parsing uniquement — formats réels planning)
# Client : "N°8276" puis espaces + chiffres ; repli "N 8276" (PDF / OCR sans signe)
$script:RxClientIdNumbered = [regex]'(?i)N[°o]\s*(\d+)'
$script:RxClientIdNumberSpaced = [regex]'(?i)N\s+(\d+)\b'

# ODM service : 4638154-16585036 ; tolère espaces et tirets Unicode ; (?<!\d) si \b absent (lettre collée au 1er chiffre)
$script:RxOdmPair = [regex]'(?i)(?<![0-9])(\d{7}\s*\p{Pd}\s*\d+)\b'

# Work order : 7 chiffres, hors préfixe d’un ODM (même ligne ou texte global)
$script:RxWorkOrderDigits = [regex]'\b(\d{7})\b'

# Libellés optionnels : ordre de mission(s), N° ordre, référence, mission, bon de commande (pdftotext -layout)
$script:RxWorkOrderLabeled = [regex]'(?i)(?:ordre(?:\s+de\s+missions?)?|o\.?\s*t\.?|intervention|n[°o]?\s*ot|n[°o]?\s*ordre|r[ée]f(?:érence)?\.?|mission|bon\s+de\s+commande)\s*[.:]?\s*(\d{6,10})\b'

# Date de passage : 22/04/2026 ; repli : première date jj/mm/aaaa
$script:RxVisitDateLabeled = [regex]'(?i)date\s+de\s+passage\s*[:.]?\s*(\d{2}/\d{2}/\d{4})'
$script:RxVisitDateGeneric = [regex]'(?<!\d)(\d{2}/\d{2}/\d{4})(?!\d)'

$script:RxEmail = [regex]'(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'

# Code postal FR (ligne d’adresse)
$script:RxPostalLine = [regex]'\b(\d{5})\b'

# Quantités / contact (sans dépendre des accents : variantes explicites)
$script:RxQuantityLabeled = [regex]'(?i)(?:qt[ée]|qte|quantit[ée]|qty)\s*[.:]?\s*(\d+)\b'
$script:RxQuantityUnit = [regex]'(?i)\b(\d+)\s*(?:sac|sacs|kg|tonne|tonnes|colis|palette|palettes)\b'
$script:RxContactNameLabeled = [regex]'(?im)contact\s*(?:nom|name)?\s*[.:]\s*(.+)$'

# Secondaire client (hors format N° strict)
$script:RxClientIdLabeled = [regex]'(?i)\bclient\s*(?:ident(?:ifiant)?|n[°o]|id)?\s*[.:]?\s*(\d{4,10})\b'
#endregion

# --- Debug temporaire (desactiver : retirer la variable d'environnement) ---
# $env:PDF_ENTITY_EXTRACTOR_DEBUG = '1'
# Optionnel : PDF_ENTITY_EXTRACTOR_DEBUG_LINES=35 (entre 20 et 50), PDF_ENTITY_EXTRACTOR_DEBUG_RAW_PAGES=2 (premieres pages avec dump brut complet)

function script:Test-EntityExtractorDebugEnabled {
    $v = [string]$env:PDF_ENTITY_EXTRACTOR_DEBUG
    if ([string]::IsNullOrWhiteSpace($v)) { return $false }
    return $v.Trim() -inotmatch '^(0|false|no|off)$'
}

function script:Get-EntityExtractorDebugHeadLineCount {
    $n = 40
    $raw = [string]$env:PDF_ENTITY_EXTRACTOR_DEBUG_LINES
    if ($raw -match '^\d+$') {
        $n = [int]$raw
        if ($n -lt 20) { $n = 20 }
        if ($n -gt 50) { $n = 50 }
    }
    return $n
}

function script:Get-EntityExtractorDebugRawDumpMaxPage {
    $n = 2
    $raw = [string]$env:PDF_ENTITY_EXTRACTOR_DEBUG_RAW_PAGES
    if ($raw -match '^\d+$') {
        $n = [int]$raw
        if ($n -lt 1) { $n = 1 }
        if ($n -gt 20) { $n = 20 }
    }
    return $n
}

function script:Test-EntityExtractorInterestLine {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
    if ($Line -match '(?i)ordre|mission|intervention|\bot\b|reference|ref\.|client|date\s+de\s+passage|n[°o]\s*\d|\bodm\b') {
        return $true
    }
    if ($Line -match '\d{7}') { return $true }
    if ($Line -match '\d{3}\s+\d{4}\b') { return $true }
    if ($Line -match '\d{4}\s+\d{3}\b') { return $true }
    if ($Line -match '\d{2,8}\s*-\s*\d{2,12}') { return $true }
    return $false
}

function script:Write-EntityExtractorDebugReport {
    param(
        [int]$PageNumber,
        [string[]]$RawLines,
        [string[]]$SanitizedLines,
        [string[]]$NormalizedLines,
        [string]$Text,
        [PageEntity]$Entity
    )

    $headN = Get-EntityExtractorDebugHeadLineCount
    $rawMaxPage = Get-EntityExtractorDebugRawDumpMaxPage
    $cRaw = if ($RawLines) { $RawLines.Count } else { 0 }

    Write-Host ""
    Write-Host "[EntityExtractor DEBUG] ========== Page $PageNumber ==========" -ForegroundColor Cyan
    Write-Host "[EntityExtractor DEBUG] Lignes brutes (pdftotext) : $cRaw" -ForegroundColor Cyan

    if ($PageNumber -le $rawMaxPage -and $cRaw -gt 0) {
        Write-Host "[EntityExtractor DEBUG] Premiers $headN lignes brutes (indices 1-based) :" -ForegroundColor DarkCyan
        $lim = [Math]::Min($headN, $cRaw)
        for ($i = 0; $i -lt $lim; $i++) {
            $show = $RawLines[$i]
            if ($null -eq $show) { $show = '<null>' }
            $vis = ($show -replace "`t", '\t')
            Write-Host ("  {0,4}| {1}" -f ($i + 1), $vis)
        }
        if ($cRaw -gt $lim) {
            Write-Host ("  ... ({0} lignes supplementaires sur cette page)" -f ($cRaw - $lim)) -ForegroundColor DarkGray
        }
    }
    elseif ($PageNumber -gt $rawMaxPage) {
        Write-Host "[EntityExtractor DEBUG] (Dump brut desactive pour page > $rawMaxPage ; regler PDF_ENTITY_EXTRACTOR_DEBUG_RAW_PAGES)" -ForegroundColor DarkGray
    }

    $emitInterest = {
        param($Label, $Arr)
        Write-Host "[EntityExtractor DEBUG] $Label" -ForegroundColor Yellow
        $hits = 0
        $maxShow = 25
        if (-not $Arr) {
            Write-Host "  (aucune ligne)" -ForegroundColor DarkGray
            return
        }
        for ($j = 0; $j -lt $Arr.Count; $j++) {
            $ln = $Arr[$j]
            if (-not (Test-EntityExtractorInterestLine $ln)) { continue }
            $hits++
            if ($hits -le $maxShow) {
                Write-Host ("  L{0,4}| {1}" -f ($j + 1), $ln)
            }
        }
        if ($hits -eq 0) {
            Write-Host "  --> Aucune ligne ne matche (ordre|mission|7 chiffres|3+4 espaces|motif ODM-like tiret)." -ForegroundColor DarkYellow
        }
        elseif ($hits -gt $maxShow) {
            Write-Host ("  ... ({0} autres lignes d'interet non affichees)" -f ($hits - $maxShow)) -ForegroundColor DarkGray
        }
    }

    & $emitInterest -Label 'Lignes d''interet (texte BRUT tel que recu) :' -Arr $RawLines
    & $emitInterest -Label 'Lignes d''interet (apres normalisation NBSP / tirets / 3+4) :' -Arr $SanitizedLines

    $normCount = if ($NormalizedLines) { $NormalizedLines.Count } else { 0 }
    Write-Host "[EntityExtractor DEBUG] Lignes non vides apres collapse espaces : $normCount" -ForegroundColor Cyan

    if (-not [string]::IsNullOrWhiteSpace($Text)) {
        $odmMatches = $script:RxOdmPair.Matches($Text)
        $woLab = $script:RxWorkOrderLabeled.IsMatch($Text)
        $d7 = $script:RxWorkOrderDigits.Matches($Text).Count
        Write-Host "[EntityExtractor DEBUG] Sur texte page joint (newline) : RxOdmPair.Matches=$($odmMatches.Count) | rx_libelle_ordre=$woLab | candidats_7chiffres(count)=$d7" -ForegroundColor Magenta
        if ($odmMatches.Count -eq 0 -and $Text.Length -gt 0) {
            $sample = $Text.Substring(0, [Math]::Min(400, $Text.Length)) -replace "`n", ' | '
            Write-Host "[EntityExtractor DEBUG] Extrait texte (400 car. max) : $sample" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "[EntityExtractor DEBUG] Texte page vide apres filtrage : aucune regex ne peut matcher." -ForegroundColor Red
    }

    $svcN = if ($null -ne $Entity.Services) { @($Entity.Services).Count } else { 0 }
    Write-Host ("[EntityExtractor DEBUG] Resultat extraction : ClientID={0} | WorkOrder={1} | Services={2}" -f @(
        ($(if ($Entity.ClientID) { $Entity.ClientID } else { '<vide>' })),
        ($(if ($Entity.WorkOrder) { $Entity.WorkOrder } else { '<vide>' })),
        $svcN
    )) -ForegroundColor Green
    Write-Host "[EntityExtractor DEBUG] ========== fin page $PageNumber ==========" -ForegroundColor Cyan
    Write-Host ""
}

function script:Get-TrimmedOrNull {
    param([string]$Value)
    if ($null -eq $Value) { return $null }
    $t = $Value.Trim()
    if ($t.Length -eq 0) { return $null }
    return $t
}

function script:Normalize-OdmToken {
    <#
    Ramène une paire ODM extraite du PDF (tirets Unicode, espaces) au forme stricte 7chiffres-restechiffres.
    #>
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    $collapsed = [regex]::Replace([string]$Raw.Trim(), '\s+', '')
    $oneDash = [regex]::Replace($collapsed, '\p{Pd}+', '-')
    if ($oneDash -match '^(\d{7})-(\d+)$') {
        return ('{0}-{1}' -f $Matches[1], $Matches[2])
    }
    return (Get-TrimmedOrNull $Raw)
}

function script:Get-NormalizedNonEmptyLines {
    <#
    Ignore les lignes vides, trim, réduit les espaces multiples à une seule.
    #>
    param([string[]]$Lines)
    $out = [System.Collections.Generic.List[string]]::new()
    if (-not $Lines) {
        return @()
    }

    foreach ($l in $Lines) {
        if ($null -eq $l) { continue }
        $collapsed = [regex]::Replace([string]$l, '\s+', ' ', [System.Text.RegularExpressions.RegexOptions]::None)
        $t = $collapsed.Trim()
        if ($t.Length -eq 0) { continue }
        $out.Add($t)
    }

    return $out.ToArray()
}

function script:Find-ClientIdInText {
    param([string]$Text, [string[]]$Lines)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    $m = $script:RxClientIdNumbered.Match($Text)
    if ($m.Success) { return $m.Groups[1].Value }

    $m0 = $script:RxClientIdNumberSpaced.Match($Text)
    if ($m0.Success) { return $m0.Groups[1].Value }

    $m2 = $script:RxClientIdLabeled.Match($Text)
    if ($m2.Success) { return $m2.Groups[1].Value }

    return $null
}

function script:Find-ClientNameFromLines {
    param(
        [string[]]$Lines,
        [string]$ClientId
    )
    if (-not $Lines -or -not $ClientId) { return $null }

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -notmatch [regex]::Escape($ClientId)) { continue }

        if ($line -match '^\s*N(?:[°o]\s*|\s+)\d+\s*$' -and $i -gt 0) {
            return Get-TrimmedOrNull $Lines[$i - 1]
        }

        $beforeNumbered = [regex]::Match(
            $line,
            '(?i)^(.{0,300}?)\s+N(?:[°o]\s*|\s+)\d',
            [System.Text.RegularExpressions.RegexOptions]::None)
        if ($beforeNumbered.Success) {
            $name = Get-TrimmedOrNull $beforeNumbered.Groups[1].Value
            if ($name -and $name.Length -ge 2 -and $name -notmatch '^(?i)n\.?$') { return $name }
        }

        $beforeBare = [regex]::Match(
            $line,
            '^(.{0,300}?)\s+' + [regex]::Escape($ClientId) + '\b',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($beforeBare.Success) {
            $name = Get-TrimmedOrNull $beforeBare.Groups[1].Value
            if ($name) { return $name }
        }

        if ($i -gt 0) {
            $prev = Get-TrimmedOrNull $Lines[$i - 1]
            if ($prev -and $prev -notmatch '^\d{5}\b' -and $prev -notmatch '@') {
                return $prev
            }
        }

        return $null
    }
    return $null
}

function script:Build-AddressFromLines {
    <#
    Ligne contenant un code postal \b\d{5}\b ; la ligne précédente (non vide) = rue.
    Ville : texte restant sur la ligne du code postal après le CP, si présent.
    #>
    param([string[]]$Lines)
    $street = $null
    $postal = $null
    $city = $null
    if (-not $Lines) {
        return @{ Street = $null; PostalCode = $null; City = $null }
    }

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        $m = $script:RxPostalLine.Match($line)
        if (-not $m.Success) { continue }

        $postal = $m.Groups[1].Value
        $afterCp = $line.Substring($m.Index + $m.Length).Trim()
        if ($afterCp.Length -gt 0) {
            $city = Get-TrimmedOrNull $afterCp
        }

        if ($i -gt 0) {
            $street = Get-TrimmedOrNull $Lines[$i - 1]
        }
        break
    }

    return @{
        Street     = $street
        PostalCode = $postal
        City       = $city
    }
}

function script:Test-IsSevenDigitOdmPrefix {
    param(
        [string]$Text,
        [int]$Index,
        [int]$Length
    )
    if ($Index + $Length -ge $Text.Length) { return $false }
    $rest = $Text.Substring($Index + $Length)
    # Même logique que RxOdmPair : 7 chiffres suivis d’un séparateur tiret (Unicode ou ASCII) puis d’autres chiffres.
    return $rest -match '^\s*\p{Pd}\s*\d+\b'
}

function script:Find-WorkOrderInText {
    param([string]$Text, [string]$ClientId)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    $m = $script:RxWorkOrderLabeled.Match($Text)
    if ($m.Success) { return $m.Groups[1].Value }

    foreach ($m2 in $script:RxWorkOrderDigits.Matches($Text)) {
        $val = $m2.Groups[1].Value
        if ($ClientId -and $val -eq $ClientId) { continue }
        if (Test-IsSevenDigitOdmPrefix -Text $Text -Index $m2.Index -Length $m2.Length) {
            continue
        }
        return $val
    }
    return $null
}

function script:Find-VisitDateInText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    $m = $script:RxVisitDateLabeled.Match($Text)
    if (-not $m.Success) {
        $m = $script:RxVisitDateGeneric.Match($Text)
    }
    if (-not $m.Success) { return $null }

    $raw = $m.Groups[1].Value
    try {
        return [datetime]::ParseExact($raw, 'dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        return $null
    }
}

function script:Build-ContactFromLines {
    param([string[]]$Lines, [string]$FullText)
    $email = $null
    $name = $null
    if (-not [string]::IsNullOrWhiteSpace($FullText)) {
        $em0 = $script:RxEmail.Match($FullText)
        if ($em0.Success) { $email = $em0.Value }
    }

    if ($Lines) {
        foreach ($line in $Lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $nm = $script:RxContactNameLabeled.Match($line)
            if (-not $nm.Success) { continue }
            $candidate = Get-TrimmedOrNull $nm.Groups[1].Value
            if (-not $candidate) { continue }
            if ($script:RxEmail.IsMatch($candidate)) {
                $candidate = Get-TrimmedOrNull (($candidate -replace $script:RxEmail, '').Trim(' -;,'))
            }
            if ($candidate) {
                $name = $candidate
                break
            }
        }
    }

    return @{ Name = $name; Email = $email }
}

function script:Find-ServicesFromLines {
    param([string[]]$Lines)
    $list = [System.Collections.Generic.List[object]]::new()
    if (-not $Lines) { return $list.ToArray() }

    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $matches = $script:RxOdmPair.Matches($line)
        if ($matches.Count -eq 0) { continue }

        $lastIndex = 0
        for ($mi = 0; $mi -lt $matches.Count; $mi++) {
            $m = $matches[$mi]
            $odm = Normalize-OdmToken -Raw $m.Groups[1].Value
            $idx = $m.Index
            $len = $m.Length

            $typePart = $line.Substring($lastIndex, $idx - $lastIndex)
            $type = Get-TrimmedOrNull $typePart

            $nextIdx = if (($mi + 1) -lt $matches.Count) { $matches[$mi + 1].Index } else { $line.Length }
            $segment = $line.Substring($idx, $nextIdx - $idx)

            $qty = $null
            $qL = $script:RxQuantityLabeled.Match($segment)
            if ($qL.Success) { $qty = $qL.Groups[1].Value }
            else {
                $qU = $script:RxQuantityUnit.Match($segment)
                if ($qU.Success) { $qty = $qU.Groups[1].Value }
            }

            $list.Add(@{
                Type     = $type
                ODM      = $odm
                Quantity = $qty
            })

            $lastIndex = $idx + $len
        }
    }

    return $list.ToArray()
}

function ConvertTo-PageEntity {
    <#
    .SYNOPSIS
    Extrait les entités métier depuis les lignes de texte d'une page (sans lecture PDF).

    .PARAMETER PageNumber
    Numéro de page (entier).

    .PARAMETER Lines
    Tableau de lignes de texte brut pour cette page.

    .INPUTS
    Aucun pipeline requis ; utiliser les paramètres nommés.

    .OUTPUTS
    PageEntity
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$PageNumber,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Lines
    )

    $entity = [PageEntity]::new($PageNumber)
    if (-not $Lines -or $Lines.Count -eq 0) {
        if (Test-EntityExtractorDebugEnabled) {
            Write-Host "[EntityExtractor DEBUG] Page $PageNumber : pas de lignes (null ou Count=0)." -ForegroundColor Yellow
        }
        return $entity
    }

    $sanitizedLines = @(Normalize-PdfNoiseText -Lines $Lines)
    $normalized = @(Get-NormalizedNonEmptyLines -Lines $sanitizedLines)
    $text = if ($normalized.Count -gt 0) { $normalized -join "`n" } else { '' }

    if ($normalized.Count -eq 0) {
        if (Test-EntityExtractorDebugEnabled) {
            Write-EntityExtractorDebugReport -PageNumber $PageNumber -RawLines @($Lines) -SanitizedLines $sanitizedLines -NormalizedLines $normalized -Text $text -Entity $entity
        }
        return $entity
    }

    $clientId = Find-ClientIdInText -Text $text -Lines $normalized
    $entity.ClientID = $clientId
    $entity.ClientName = Find-ClientNameFromLines -Lines $normalized -ClientId $clientId

    $addr = Build-AddressFromLines $normalized
    $entity.Address['Street'] = $addr.Street
    $entity.Address['PostalCode'] = $addr.PostalCode
    $entity.Address['City'] = $addr.City

    $entity.WorkOrder = Find-WorkOrderInText -Text $text -ClientId $clientId
    $entity.VisitDate = Find-VisitDateInText $text

    $contact = Build-ContactFromLines -Lines $normalized -FullText $text
    $entity.Contact['Name'] = $contact.Name
    $entity.Contact['Email'] = $contact.Email

    $entity.Services = @(Find-ServicesFromLines $normalized)

    if ($VerbosePreference -ne 'SilentlyContinue') {
        $odmList = @($entity.Services | ForEach-Object { [string]$_.ODM }) -join ', '
        if (-not $odmList) { $odmList = '<aucun>' }

        $digitDiag = [System.Text.StringBuilder]::new()
        $dIdx = 0
        foreach ($m2 in $script:RxWorkOrderDigits.Matches($text)) {
            if ($dIdx -ge 6) {
                [void]$digitDiag.Append('...')
                break
            }
            $val = $m2.Groups[1].Value
            $skipOdm = Test-IsSevenDigitOdmPrefix -Text $text -Index $m2.Index -Length $m2.Length
            $skipClient = ($ClientId -and $val -eq $ClientId)
            [void]$digitDiag.AppendFormat('{0}(skipODM={1},skipClient={2});', $val, $skipOdm, $skipClient)
            $dIdx++
        }

        $preview = ($text -replace "`r?`n", ' | ')
        if ($preview.Length -gt 200) {
            $preview = $preview.Substring(0, 200) + '...'
        }

        $emptyMark = '<vide>'
        Write-Verbose (
            "[Extraction page {0}] ClientID={1} | WorkOrder={2} | nbServices={3} | ODM=[{4}] | rx_libelle_ordre={5} | candidats_7chiffres=[{6}] | apercu={7}" -f @(
                $PageNumber,
                ($(if ($entity.ClientID) { $entity.ClientID } else { $emptyMark })),
                ($(if ($entity.WorkOrder) { $entity.WorkOrder } else { $emptyMark })),
                @($entity.Services).Count,
                $odmList,
                $script:RxWorkOrderLabeled.IsMatch($text),
                $digitDiag.ToString().TrimEnd(';'),
                $preview
            )
        )
    }

    if (Test-EntityExtractorDebugEnabled) {
        Write-EntityExtractorDebugReport -PageNumber $PageNumber -RawLines @($Lines) -SanitizedLines $sanitizedLines -NormalizedLines $normalized -Text $text -Entity $entity
    }

    return $entity
}

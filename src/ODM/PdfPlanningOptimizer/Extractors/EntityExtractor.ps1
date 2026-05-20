# ============================================================
# EntityExtractor.ps1
# Rôle : Transformer du texte PDF déjà découpé en lignes en PageEntity.
# Aucune lecture PDF, Excel, matching ou décision métier.
# ============================================================

. (Join-Path $PSScriptRoot "PdfTextNormalizer.ps1")
. (Join-Path $PSScriptRoot "..\Models\PageEntity.ps1")

#region Regex (parsing uniquement — formats réels planning)
# U+00B0 / U+00BA / o|O : séquences \u (ASCII dans le source) pour éviter tout décalage d’encodage du fichier .ps1
$script:RxNumeroSignCore = '\u00B0|\u00BA|[oO]'
$script:RxNumeroSignToken = '(?:' + $script:RxNumeroSignCore + ')'
$script:RxNumeroSignTokenOpt = '(?:' + $script:RxNumeroSignCore + ')?'

# Client : "N°8276" puis espaces + chiffres ; repli "N 8276" (PDF / OCR sans signe)
$script:RxClientIdNumbered = [regex]('(?i)N' + $script:RxNumeroSignToken + '\s*(\d+)')
$script:RxClientIdNumberSpaced = [regex]'(?i)N\s+(\d+)\b'
$script:RxClientIdNumberedWithHyphen = [regex]('(?i)(?:^|[\s\p{P}])-\s*N' + $script:RxNumeroSignToken + '\s*(\d+)')

# ODM service : 4638154-16585036 ; tolère espaces et tirets Unicode ; (?<!\d) si \b absent (lettre collée au 1er chiffre)
$script:RxOdmPair = [regex]'(?i)(?<![0-9])(\d{7}\s*\p{Pd}\s*\d+)\b'

# Work order : 7 chiffres, hors préfixe d’un ODM (même ligne ou texte global)
$script:RxWorkOrderDigits = [regex]'\b(\d{7})\b'

# Libellés optionnels : ordre de mission(s), N° ordre, référence, mission, bon de commande (pdftotext -layout)
$script:RxWorkOrderLabeled = [regex]('(?i)(?:ordre(?:\s+de\s+missions?)?|o\.?\s*t\.?|intervention|n' + $script:RxNumeroSignTokenOpt + '\s*ot|n' + $script:RxNumeroSignTokenOpt + '\s*ordre|r[ée]f(?:érence)?\.?|mission|bon\s+de\s+commande)\s*[.:]?\s*(\d{6,10})\b')

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
$script:RxClientIdLabeled = [regex]('(?i)\bclient\s*(?:ident(?:ifiant)?|n' + $script:RxNumeroSignToken + '|id)?\s*[.:]?\s*(\d{4,10})\b')
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
    if ($Line -match ('(?i)ordre|mission|intervention|\bot\b|reference|ref\.|client|date\s+de\s+passage|n' + $script:RxNumeroSignToken + '\s*\d|\bodm\b')) {
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
    if ($Lines) {
        for ($i = 0; $i -lt $Lines.Count; $i++) {
            $ln = $Lines[$i]
            if ([string]::IsNullOrWhiteSpace($ln)) { continue }
            if ($ln -match ('(?i)^\s*client\s*(?:id|ident(?:ifiant)?|n' + $script:RxNumeroSignToken + ')\s*:\s*$')) {
                if (($i + 1) -lt $Lines.Count) {
                    $nx = Get-TrimmedOrNull $Lines[$i + 1]
                    if ($nx -match '^(\d{4,12})\s*$') { return $Matches[1] }
                }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    $m = $script:RxClientIdNumbered.Match($Text)
    if ($m.Success) { return $m.Groups[1].Value }

    $mHyphen = $script:RxClientIdNumberedWithHyphen.Match($Text)
    if ($mHyphen.Success) { return $mHyphen.Groups[1].Value }

    $m0 = $script:RxClientIdNumberSpaced.Match($Text)
    if ($m0.Success) { return $m0.Groups[1].Value }

    $m2 = $script:RxClientIdLabeled.Match($Text)
    if ($m2.Success) { return $m2.Groups[1].Value }

    return $null
}

function script:Test-IsLikelyFrenchPostalTokenInContext {
    <#
    Évite les faux positifs (ex. « BANQUE … 01800 SAINT ») : un bloc \d{5} n'est « code postal »
    que si le contexte ressemble à une ligne d'adresse (CP + ville, début de ligne, etc.).
    #>
    param(
        [string]$Line,
        [System.Text.RegularExpressions.Match]$Match
    )
    if (-not $Match.Success) { return $false }
    $d = $Match.Groups[1].Value
    if ($d.Length -ne 5) { return $false }
    if ($d -match '^0{4,}') { return $false }
    $idx = $Match.Index
    $before = if ($idx -gt 0) { $Line.Substring(0, $idx) } else { '' }
    $after = if ($idx + $Match.Length -lt $Line.Length) { $Line.Substring($idx + $Match.Length) } else { '' }
    # Suite immédiate d'un « N° » : 5 chiffres = identifiant client (ex. 24896), pas code postal
    if ($before -match ('(?i)N' + $script:RxNumeroSignTokenOpt + '\s*$')) { return $false }
    if ($Line -match '(?i)^\s*\d{5}\s+\S') { return $true }
    if ($Line -match '(?i),\s*\d{5}\b') { return $true }
    $bLen = $before.Trim().Length
    if ($bLen -ge 20 -and $after -match '^\s+[A-Za-zÀ-ÿ]') {
        return $false
    }
    if ($bLen -le 14 -and $after -match '^\s*[,\s]?\s*[A-Za-zÀ-ÿ]') {
        return $true
    }
    if ($after -match '^\s*,') { return $true }
    return $false
}

function script:IsAddressLine {
    <#
    Une ligne d'adresse (rue, numéro, code postal) ne doit jamais être traitée comme nom client.
    CP \d{5} : seulement si contexte adresse (Test-IsLikelyFrenchPostalTokenInContext) et pas suite de N° client.
    Ne pas traiter « D 906 », libellés type BANQUE, ni une ligne d'en-tête « … N° client » comme adresse seule.
    #>
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
    $l = $Line.Trim()
    if ($l -match ('(?i)N' + $script:RxNumeroSignToken + '\s*\d{4,12}')) { return $false }
    if ($l -match '(?i)\bRoute\s+nationale\s+D\s*\d') { return $false }
    if ($l -match '(?i)^D\s+\d{3,4}\b' -and $l -notmatch '(?i)\b(Rue|Avenue|Route|Chemin|Boulevard|All[ée]e|Place|Impasse)\b') {
        return $false
    }
    if ($l -match '(?i)\bBANQUE\s+DE\b') { return $false }
    if ($l -match '(?i)\bSR\s+CONSEIL\b') { return $false }
    foreach ($m in [regex]::Matches($l, '\b(\d{5})\b')) {
        if (Test-IsLikelyFrenchPostalTokenInContext -Line $l -Match $m) {
            return $true
        }
    }
    if ($l -match '^\d+\s') { return $true }
    if ($l -match '(?i)\b(Rue|Avenue|Route|Chemin|Boulevard|All[ée]e|Place|Impasse)\b') { return $true }
    if ($l -match '(?i),\s*\d{5}\b') { return $true }
    if ($l -match '(?i)^Les\s+') { return $true }
    if ($l -match '\b\d{7}\b') { return $true }
    return $false
}

function script:Extract-TrailingClientNameFromAddressHead {
    <#
    Sur une même ligne « rue … NOM CLIENT » (PDF layout), conserve le suffixe en mots majoritairement en majuscules.
    #>
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $m = [regex]::Match(
        $Text,
        '(?i)\s+((?:[A-ZÀÂÄÉÈÊËÏÎÔÙÛÜÇ]{2,})(?:\s+[A-ZÀÂÄÉÈÊËÏÎÔÙÛÜÇ0-9]{2,})*)\s*$'
    )
    if ($m.Success) {
        return Get-TrimmedOrNull $m.Groups[1].Value
    }
    return $null
}

function script:Test-PdfClientBlockDebugEnabled {
    $v = [string]$env:PDF_CLIENT_BLOCK_DEBUG
    if ([string]::IsNullOrWhiteSpace($v)) { return $false }
    return $v.Trim() -inotmatch '^(0|false|no|off)$'
}

$script:PdfExtractionScoringState = $null

function script:Get-ClientNumberedIdLineMatches {
    <#
    Première occurrence « N° + identifiant » par ligne (ordre document), pour aligner ClientId / ancre sans rescan global du texte joint.
    #>
    param([string[]]$Lines)
    $list = [System.Collections.Generic.List[object]]::new()
    if (-not $Lines) { return $list.ToArray() }
    $rx = [regex]('(?i)N' + $script:RxNumeroSignToken + '\s*(\d{4,12})(?=\D|$)')
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $ln = [string]$Lines[$i]
        if ([string]::IsNullOrWhiteSpace($ln)) { continue }
        $m = $rx.Match($ln)
        if ($m.Success) {
            $list.Add([pscustomobject]@{ LineIndex = $i; ClientId = $m.Groups[1].Value })
        }
    }
    return $list.ToArray()
}

function script:Find-FirstAddressBlockEndLineIndex {
    <#
    Indice de fin (inclus) du premier bloc « CP en contexte adresse + ville » entre $From et $To.
    #>
    param(
        [string[]]$Lines,
        [int]$From,
        [int]$To
    )
    if (-not $Lines -or $From -gt $To) { return -1 }
    $fromB = [Math]::Max(0, $From)
    $toB = [Math]::Min($Lines.Count - 1, $To)
    for ($j = $fromB; $j -le $toB; $j++) {
        $line = Get-TrimmedOrNull $Lines[$j]
        if (-not $line) { continue }
        $mCp = [regex]::Match($line, '\b(\d{5})\b')
        if (-not $mCp.Success) { continue }
        if (-not (Test-IsLikelyFrenchPostalTokenInContext -Line $line -Match $mCp)) { continue }
        $after = $line.Substring($mCp.Index + $mCp.Length).Trim(' ', '-', ',', ';')
        if (-not [string]::IsNullOrWhiteSpace($after)) {
            if ($after -match '[A-Za-zÀ-ÿ]') { return $j }
        }
        if (($j + 1) -le $toB) {
            $nx = Get-TrimmedOrNull $Lines[$j + 1]
            if ($nx -and $nx -notmatch '(?i)^date\s+de\s+passage\b' -and $nx -match '[A-Za-zÀ-ÿ]') {
                return $j + 1
            }
        }
        return $j
    }
    return -1
}

function script:Resolve-PageClientKeyFields {
    <#
    Détermine ClientId + index d’ancre en une passe sur les lignes + une résolution d’indices N°,
    pour éviter le décalage « premier N° dans le texte joint » vs « bonne ligne sur la page ».
    #>
    param(
        [string[]]$Lines,
        [string]$JoinedText
    )
    $numbered = @(Get-ClientNumberedIdLineMatches -Lines $Lines)
    $hint = Find-ClientIdInText -Text $JoinedText -Lines $Lines

    if ($numbered.Count -eq 0) {
        $anchor = if (-not [string]::IsNullOrWhiteSpace($hint)) {
            Find-ClientAnchorLineIndex -Lines $Lines -ClientId $hint
        }
        else { -1 }
        if ($anchor -lt 0 -and [string]::IsNullOrWhiteSpace($hint)) {
            for ($ai = 0; $ai -lt $Lines.Count; $ai++) {
                if ([string]$Lines[$ai] -match ('(?i)N\s*' + $script:RxNumeroSignToken + '\s*\d{4,12}')) {
                    $anchor = $ai
                    break
                }
            }
        }
        return [pscustomobject]@{
            ClientId    = $hint
            AnchorIndex = $anchor
            Source      = 'no-numbered-lines'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($hint)) {
        foreach ($c in $numbered) {
            if ($c.ClientId -eq $hint) {
                return [pscustomobject]@{
                    ClientId    = $hint
                    AnchorIndex = $c.LineIndex
                    Source      = 'hint-aligned-to-n-line'
                }
            }
        }
    }

    $distinct = @($numbered | ForEach-Object { $_.ClientId } | Sort-Object -Unique)
    if ($distinct.Count -eq 1) {
        $c0 = $numbered[0]
        return [pscustomobject]@{
            ClientId    = $c0.ClientId
            AnchorIndex = $c0.LineIndex
            Source      = 'unique-numbered-id'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($hint)) {
        $anchorLoose = Find-ClientAnchorLineIndex -Lines $Lines -ClientId $hint
        if ($anchorLoose -ge 0) {
            return [pscustomobject]@{
                ClientId    = $hint
                AnchorIndex = $anchorLoose
                Source      = 'hint-unique-fallback-anchor'
            }
        }
    }

    $first = $numbered[0]
    return [pscustomobject]@{
        ClientId    = $first.ClientId
        AnchorIndex = $first.LineIndex
        Source      = 'first-numbered-line-on-page'
    }
}

function Test-TextExistsInRaw {
    <#
    Décision « sous-chaîne contenue dans le texte des lignes brutes pdftotext » (joker -like, caractères * ? [ échappés en littéral).
    #>
    param(
        $text,
        [string[]]$RawLines
    )
    if ($null -eq $text) { return $false }
    $t = [string]$text
    if ($null -eq $RawLines) { $RawLines = @() }
    $hay = ($RawLines -join ' ')
    if ($hay.Length -eq 0) { return $false }
    if ([string]::IsNullOrWhiteSpace($t)) { return $false }
    $esc = [System.Management.Automation.WildcardPattern]::Escape($t)
    return $hay -like ('*' + $esc + '*')
}

function script:Test-ClientNamePartiallyInRawLines {
    param(
        [string]$Name,
        [string[]]$RawLines
    )
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    if (Test-TextExistsInRaw -text $Name -RawLines $RawLines) { return $true }
    foreach ($w in ($Name -split '\s+')) {
        if ($w.Length -ge 2 -and (Test-TextExistsInRaw -text $w -RawLines $RawLines)) { return $true }
    }
    return $false
}

function script:Register-PdfExtractionPageScoring {
    param(
        [int]$PageNumber,
        [int]$Score
    )
    if ($env:PDF_SCORING -ne '1') { return }
    if ($null -eq $script:PdfExtractionScoringState) {
        Reset-PdfExtractionScoringSession
    }
    $s = $script:PdfExtractionScoringState
    $s.TotalScore += $Score
    $s.NbPages += 1
    if ($Score -lt 70) { [void]$s.WeakPageNumbers.Add($PageNumber) }
}

function Write-PdfExtractionScoreReport {
    <#
    Compare les champs extraits PageEntity au texte brut pdftotext (lignes page). Diagnostic uniquement (mode PDF_SCORING=1 sur ConvertTo-PageEntity).
    Barème : 20+25+25+15+15 = 100.
    #>
    param(
        [string[]]$RawLines,
        $Entity
    )
    if ($env:PDF_SCORING -ne '1') { return }
    if ($null -eq $Entity) { return }

    $raw = if ($null -ne $RawLines) { $RawLines } else { @() }
    $pg = [int]$Entity.PageNumber
    $cid = $Entity.ClientID
    $name = $Entity.ClientName
    $st = $Entity.Address['Street']
    $cp = $Entity.Address['PostalCode']
    $city = $Entity.Address['City']

    $score = 0

    $cidInRaw = $false
    if (-not [string]::IsNullOrWhiteSpace($cid) -and (Test-TextExistsInRaw -text $cid -RawLines $raw)) { $cidInRaw = $true }
    if (-not [string]::IsNullOrWhiteSpace($cid) -and $cidInRaw) { $score += 20 }

    $nameInRaw = $false
    if (-not [string]::IsNullOrWhiteSpace($name)) { $nameInRaw = (Test-ClientNamePartiallyInRawLines -Name $name -RawLines $raw) }
    if (-not [string]::IsNullOrWhiteSpace($name) -and $nameInRaw) { $score += 25 }

    $stInRaw = (-not [string]::IsNullOrWhiteSpace($st)) -and (Test-TextExistsInRaw -text $st -RawLines $raw)
    if ($stInRaw) { $score += 25 }

    $cpInRaw = (-not [string]::IsNullOrWhiteSpace($cp)) -and (Test-TextExistsInRaw -text $cp -RawLines $raw)
    if ($cpInRaw) { $score += 15 }

    $cityInRaw = (-not [string]::IsNullOrWhiteSpace($city)) -and (Test-TextExistsInRaw -text $city -RawLines $raw)
    if ($cityInRaw) { $score += 15 }

    $ClientNameMatch = if (-not [string]::IsNullOrWhiteSpace($name) -and $nameInRaw) { 'True' } else { 'False' }
    $addrAllOk = $true
    if (-not [string]::IsNullOrWhiteSpace($st) -and -not $stInRaw) { $addrAllOk = $false }
    if (-not [string]::IsNullOrWhiteSpace($cp) -and -not $cpInRaw) { $addrAllOk = $false }
    if (-not [string]::IsNullOrWhiteSpace($city) -and -not $cityInRaw) { $addrAllOk = $false }
    if ([string]::IsNullOrWhiteSpace($st) -and [string]::IsNullOrWhiteSpace($cp) -and [string]::IsNullOrWhiteSpace($city)) { $addrAllOk = $false }
    $AddressMatch = if ($addrAllOk) { 'True' } else { 'False' }

    $missing = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($cid) -or -not $cidInRaw) { [void]$missing.Add('ClientID') }
    if ([string]::IsNullOrWhiteSpace($name) -or -not $nameInRaw) { [void]$missing.Add('ClientName') }
    if (-not [string]::IsNullOrWhiteSpace($st) -and -not $stInRaw) { [void]$missing.Add('Address.Street') }
    if (-not [string]::IsNullOrWhiteSpace($cp) -and -not $cpInRaw) { [void]$missing.Add('Address.PostalCode') }
    if (-not [string]::IsNullOrWhiteSpace($city) -and -not $cityInRaw) { [void]$missing.Add('Address.City') }
    $missingList = if ($missing.Count -gt 0) { $missing -join ', ' } else { '—' }

    [void](Register-PdfExtractionPageScoring -PageNumber $pg -Score $score)

    Write-Host ("SCORE PAGE {0} : {1} / 100" -f $pg, $score) -ForegroundColor Cyan
    Write-Host ("  ClientName OK: {0}" -f $ClientNameMatch) -ForegroundColor $(if ($ClientNameMatch -eq 'True') { 'Green' } else { 'Yellow' })
    Write-Host ("  Address OK    : {0}" -f $AddressMatch) -ForegroundColor $(if ($AddressMatch -eq 'True') { 'Green' } else { 'Yellow' })
    Write-Host ("  Missing fields: {0}" -f $missingList) -ForegroundColor DarkGray
}

function Reset-PdfExtractionScoringSession {
    <#
    Remet le cumul document (score global) à zéro. Appeler une fois par PDF avant d’enchaîner les ConvertTo-PageEntity avec PDF_SCORING=1.
    #>
    if ($env:PDF_SCORING -ne '1') { return }
    $script:PdfExtractionScoringState = [pscustomobject]@{
        TotalScore      = 0
        NbPages         = 0
        WeakPageNumbers = [System.Collections.Generic.List[int]]::new()
    }
}

function script:Test-IsPlanningScheduleLine {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
    $v = $Line.Trim()
    if ($v -match '(?i)Tourn[ée]e\s+Cr[ée]neau') { return $true }
    if ($v -match '(?i)\b(Jeudi|Mardi|Lundi|Mercredi|Vendredi|Samedi|Dimanche)\b') { return $true }
    if ($v -match '(?i)Heure\s+de\s+passage') { return $true }
    if ($v -match '\d{1,2}\s*h\s*\d{2}') { return $true }
    return $false
}

function script:Get-ClientBlock {
    <#
    Bloc métier unique autour de l'ancre N° : jusqu'à 10 lignes au-dessus,
    fin = première borne parmi : fenêtre max après ancre, « Date de passage », planning, ou fin du premier bloc adresse (CP + ville).
    #>
    param(
        [string[]]$Lines,
        [int]$AnchorIndex
    )
    if (-not $Lines -or $Lines.Count -eq 0 -or $AnchorIndex -lt 0 -or $AnchorIndex -ge $Lines.Count) {
        return [pscustomobject]@{
            StartIndex  = -1
            EndIndex    = -1
            AnchorIndex = $AnchorIndex
            BlockLines  = [string[]]@()
        }
    }

    $start = [Math]::Max(0, $AnchorIndex - 10)

    # « Date de passage » : première occurrence à partir de l’ancre (évite en-têtes / bruit au-dessus du bloc courant)
    $dateIdx = -1
    for ($d = $AnchorIndex; $d -lt $Lines.Count; $d++) {
        if ([string]$Lines[$d] -match '(?i)\bDate\s+de\s+passage\b') {
            $dateIdx = $d
            break
        }
    }

    $schedIdx = -1
    for ($s = $AnchorIndex + 1; $s -lt $Lines.Count; $s++) {
        if (Test-IsPlanningScheduleLine $Lines[$s]) {
            $schedIdx = $s
            break
        }
    }

    $hardCap = [Math]::Min($Lines.Count - 1, $AnchorIndex + 18)
    $dateCap = if ($dateIdx -ge 0) { [Math]::Min($dateIdx - 1, $hardCap) } else { $hardCap }
    if ($dateCap -lt $AnchorIndex) { $dateCap = $AnchorIndex }

    $addrEnd = Find-FirstAddressBlockEndLineIndex -Lines $Lines -From ($AnchorIndex + 1) -To $dateCap

    $maxByWindow = [Math]::Min($Lines.Count - 1, $AnchorIndex + 10)
    $candidates = @($maxByWindow, $hardCap, $dateCap)
    if ($dateIdx -ge 0) { $candidates += ($dateIdx - 1) }
    if ($schedIdx -ge 0) { $candidates += ($schedIdx - 1) }
    if ($addrEnd -ge $AnchorIndex) { $candidates += $addrEnd }

    $end = ($candidates | Where-Object { $_ -ge $AnchorIndex } | Measure-Object -Minimum).Minimum
    if ($null -eq $end) { $end = $AnchorIndex }
    if ($end -lt $AnchorIndex) { $end = $AnchorIndex }

    $blockLines = @([string[]]@($Lines[$start..$end]))
    return [pscustomobject]@{
        StartIndex  = $start
        EndIndex    = $end
        AnchorIndex = $AnchorIndex
        BlockLines  = $blockLines
    }
}

function script:Write-PdfClientBlockDebug {
    param(
        [int]$PageNumber,
        [object]$Block,
        [int]$AnchorIndex,
        [string[]]$Excluded,
        [string]$ClientNameFinal
    )
    Write-Host ""
    Write-Host "[PDF_CLIENT_BLOCK_DEBUG] Page $PageNumber  AncreIndex=$AnchorIndex  Bloc Start=$($Block.StartIndex) End=$($Block.EndIndex)" -ForegroundColor Cyan
    $relA = $AnchorIndex - $Block.StartIndex
    if ($relA -ge 0 -and $Block.BlockLines -and $relA -lt @($Block.BlockLines).Count) {
        Write-Host ("  Ancre (ligne): {0}" -f $Block.BlockLines[$relA]) -ForegroundColor White
    }
    Write-Host "  Lignes du bloc:" -ForegroundColor Gray
    $rel = 0
    foreach ($ln in @($Block.BlockLines)) {
        $abs = $Block.StartIndex + $rel
        Write-Host ("    [{0,3}] {1}" -f $abs, $ln)
        $rel++
    }
    if ($Excluded -and $Excluded.Count -gt 0) {
        Write-Host "  Exclues (adresse / date / planning / N°):" -ForegroundColor DarkYellow
        foreach ($e in $Excluded) {
            Write-Host "    - $e" -ForegroundColor DarkYellow
        }
    }
    Write-Host ("  ClientName final: {0}" -f ($(if ($ClientNameFinal) { $ClientNameFinal } else { '<vide>' }))) -ForegroundColor Green
    Write-Host ""
}

function script:Get-ClientNameFromBlock {
    <#
    Nom client = lignes du bloc hors adresse, hors date, hors planning, hors ligne N° seule ;
    ligne d'ancre : texte avant/après N° (collages pdftotext, ET, rue+nom sur même ligne).
    #>
    param(
        [string[]]$Lines,
        [object]$Block,
        [string]$ClientId,
        [int]$PageNumber = 0,
        [switch]$DebugClientBlocks
    )

    if (-not $Lines -or $Block.StartIndex -lt 0) { return $null }
    $anchorIdx = $Block.AnchorIndex
    $anchor = [string]$Lines[$anchorIdx]
    $excluded = [System.Collections.Generic.List[string]]::new()

    function script:MetaSkip {
        param([string]$v)
        if ([string]::IsNullOrWhiteSpace($v)) { return $true }
        if ($v -match '^\d{1,2}/\d{1,2}/\d{2,4}') { return $true }
        if ($v -match '^(?i)\d{1,2}:\d{2}\b') { return $true }
        return $false
    }

    function script:StopLine {
        param([string]$v)
        if ([string]::IsNullOrWhiteSpace($v)) { return $true }
        if ($v -match '(?i)\bDate\s+de\s+passage\b') { return $true }
        if ($v -match '@') { return $true }
        if ($v -match '^(?i)(Prestation|Contact|Heure|Remarque|Portable)\b') { return $true }
        return $false
    }

    function script:IsNOnlyClientLine {
        param([string]$v)
        if ([string]::IsNullOrWhiteSpace($v)) { return $false }
        return [bool]($v -match ('(?i)^\s*-?\s*N\s*' + $script:RxNumeroSignTokenOpt + '\s*\d{4,12}\s*$'))
    }

    if ([string]::IsNullOrWhiteSpace($ClientId)) { return $null }
    # Groupe 1 = identifiant (obligatoire pour fidEsc / sous-chaînes tête–queue)
    $idPat = '(?i)(?:ET\s*)?N\s*' + $script:RxNumeroSignTokenOpt + '\s*(' + [regex]::Escape($ClientId) + ')(?=\D|$)'
    $idMatch = [regex]::Match($anchor, $idPat)
    if (-not $idMatch.Success) { return $null }

    $fullMarker = $idMatch
    $fidEsc = [regex]::Escape($idMatch.Groups[1].Value)

    $headRaw = if ($fullMarker.Index -gt 0) { $anchor.Substring(0, $fullMarker.Index).Trim() } else { '' }
    $headRaw = $headRaw.Trim().TrimStart('-').Trim()
    $tailRaw = ''
    if ($fullMarker.Index + $fullMarker.Length -lt $anchor.Length) {
        $tailRaw = $anchor.Substring($fullMarker.Index + $fullMarker.Length).Trim().TrimEnd('-').Trim()
    }

    $baseFromHead = $headRaw
    $insertEtBetweenBlocks = $false
    if ($fullMarker.Success -and $fullMarker.Value -match '(?i)^ET') {
        $insertEtBetweenBlocks = $true
        $baseFromHead = Get-TrimmedOrNull ($headRaw -replace '(?i)-\s*$', '')
    }
    elseif ($headRaw -match '(?i)(.+?)(?:\s*-\s*)?ET(?=N)') {
        $baseFromHead = Get-TrimmedOrNull $Matches[1].Value
        $insertEtBetweenBlocks = $true
    }
    elseif ($headRaw -match '(?i)(.+?)(?:\s*-\s*)?ET\s*$') {
        $baseFromHead = Get-TrimmedOrNull $Matches[1].Value
        $insertEtBetweenBlocks = $true
    }

    if ($baseFromHead -and (IsAddressLine $baseFromHead)) {
        $stripped = Extract-TrailingClientNameFromAddressHead -Text $baseFromHead
        if ($stripped) { $baseFromHead = $stripped }
        else { $baseFromHead = $null }
    }

    $partsUp = [System.Collections.Generic.List[string]]::new()
    for ($i = $anchorIdx - 1; $i -ge $Block.StartIndex; $i--) {
        $l = Get-TrimmedOrNull $Lines[$i]
        if (-not $l) { break }
        if (MetaSkip $l) {
            [void]$excluded.Add("[meta] $l")
            continue
        }
        if (StopLine $l) { break }
        if (Test-IsPlanningScheduleLine $l) { break }
        if (IsAddressLine $l) {
            [void]$excluded.Add("[adresse] $l")
            continue
        }
        if (IsNOnlyClientLine $l) {
            [void]$excluded.Add("[n° seul] $l")
            continue
        }
        $partsUp.Insert(0, $l)
    }

    $partsDown = [System.Collections.Generic.List[string]]::new()
    for ($j = $anchorIdx + 1; $j -le $Block.EndIndex; $j++) {
        $l2 = Get-TrimmedOrNull $Lines[$j]
        if (-not $l2) { break }
        if ($l2 -match '(?i)\bDate\s+de\s+passage\b') { break }
        if (MetaSkip $l2) {
            [void]$excluded.Add("[meta] $l2")
            continue
        }
        if (StopLine $l2) { break }
        if (Test-IsPlanningScheduleLine $l2) { break }
        if (IsAddressLine $l2) {
            [void]$excluded.Add("[adresse] $l2")
            continue
        }
        if (IsNOnlyClientLine $l2) {
            [void]$excluded.Add("[n° seul] $l2")
            continue
        }
        $nextAddr = $false
        if (($j + 1) -le $Block.EndIndex) {
            $nxLn = Get-TrimmedOrNull $Lines[$j + 1]
            if ($nxLn -and (IsAddressLine $nxLn)) { $nextAddr = $true }
        }
        if ($nextAddr -and $l2 -notmatch '\d' -and $l2 -match '^(?i)[A-ZÀÂÄÉÈÊËÏÎÔÙÛÜÇ][A-ZÀÂÄÉÈÊËÏÎÔÙÛÜÇ\s\-]{1,40}$') {
            [void]$excluded.Add("[ville-seule] $l2")
            continue
        }
        $partsDown.Add($l2)
    }

    $chunks = [System.Collections.Generic.List[string]]::new()
    if ($partsUp.Count -gt 0) { [void]$chunks.Add(($partsUp -join ' ')) }
    if ($insertEtBetweenBlocks -and $partsUp.Count -gt 0 -and $partsDown.Count -gt 0) { [void]$chunks.Add('ET') }
    if ($partsDown.Count -gt 0) { [void]$chunks.Add(($partsDown -join ' ')) }
    if ($baseFromHead) { [void]$chunks.Add($baseFromHead) }
    if ($tailRaw) {
        $tailUse = $tailRaw
        if (IsAddressLine $tailUse) {
            $ts = Extract-TrailingClientNameFromAddressHead -Text $tailUse
            if ($ts) { $tailUse = $ts }
            else { $tailUse = $null }
        }
        if ($tailUse) { [void]$chunks.Add($tailUse) }
    }

    $name = $null
    if ($chunks.Count -gt 0) {
        $name = ($chunks -join ' ')
        $name = $name -replace '\s*-\s*', ' '
        $name = [regex]::Replace($name, '\s+', ' ').Trim().TrimEnd('-').Trim()
    }

    if ([string]::IsNullOrWhiteSpace($name)) {
        $cid = if ($idMatch.Groups[1].Success -and $idMatch.Groups[1].Value) { $idMatch.Groups[1].Value } else { $ClientId }
        $partsFb = [System.Collections.Generic.List[string]]::new()
        for ($k = $Block.StartIndex; $k -le $Block.EndIndex; $k++) {
            if ($k -eq $anchorIdx) {
                $an = [string]$Lines[$anchorIdx]
                $clean = [regex]::Replace($an, ('(?i)(?:ET\s*)?N\s*' + $script:RxNumeroSignTokenOpt + '\s*') + [regex]::Escape($cid), ' ')
                $clean = Get-TrimmedOrNull ([regex]::Replace($clean, '\s+', ' '))
                if ($clean -and -not (IsAddressLine $clean)) { [void]$partsFb.Add($clean) }
                continue
            }
            $ln = Get-TrimmedOrNull $Lines[$k]
            if (-not $ln) { continue }
            if (MetaSkip $ln) { continue }
            if (Test-IsPlanningScheduleLine $ln) { continue }
            if ($ln -match '(?i)\bDate\s+de\s+passage\b') { continue }
            if (IsAddressLine $ln) { continue }
            [void]$partsFb.Add($ln)
        }
        if ($partsFb.Count -gt 0) {
            $name = [regex]::Replace(($partsFb -join ' '), '\s+', ' ').Trim()
        }
    }

    if ($DebugClientBlocks -or (Test-PdfClientBlockDebugEnabled) -or ($env:PDF_ENTITY_DEBUG_CLIENT_BLOCKS -and $env:PDF_ENTITY_DEBUG_CLIENT_BLOCKS.Trim() -inotmatch '^(0|false|no|off)$')) {
        Write-PdfClientBlockDebug -PageNumber $PageNumber -Block $Block -AnchorIndex $anchorIdx -Excluded @($excluded.ToArray()) -ClientNameFinal $name
    }

    if ([string]::IsNullOrWhiteSpace($name)) { return $null }
    return $name
}

function script:Get-AddressFromBlock {
    param(
        [string[]]$Lines,
        [object]$Block
    )
    $result = @{
        Street      = $null
        PostalCode  = $null
        City        = $null
        FullAddress = $null
    }
    if (-not $Lines -or $Block.StartIndex -lt 0) { return $result }

    function script:NormStreet {
        param([string]$Value)
        $s = Get-TrimmedOrNull $Value
        if (-not $s) { return $null }
        if ($s -match '^\d{1,2}/\d{1,2}/\d{2,4},?\s+\d{1,2}:\d{2}\s*(?:AM|PM)?$') { return $null }
        $s = [regex]::Replace($s, '\s+\d{7}\s*$', '')
        $s = [regex]::Replace($s, '\s+', ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($s)) { return $null }
        return $s
    }

    $anchor = $Block.AnchorIndex
    $street = $null
    $postal = $null
    $city = $null
    $prevStreetLike = $null

    for ($idx = $anchor + 1; $idx -le $Block.EndIndex; $idx++) {
        $line = Get-TrimmedOrNull $Lines[$idx]
        if (-not $line) { continue }
        if ($line -match '(?i)\bDate\s+de\s+passage\b') { break }

        $mCp = [regex]::Match($line, '\b(\d{5})\b')
        if ($mCp.Success -and (Test-IsLikelyFrenchPostalTokenInContext -Line $line -Match $mCp)) {
            $postal = $mCp.Groups[1].Value
            $after = $line.Substring($mCp.Index + $mCp.Length).Trim(' ', '-', ',', ';')
            if (-not [string]::IsNullOrWhiteSpace($after)) {
                $city = [regex]::Replace($after, '\s+', ' ').Trim()
                $city = [regex]::Replace($city, '\s+\d{7}\s*$', '').Trim()
            }
            elseif (($idx + 1) -le $Block.EndIndex) {
                $next = Get-TrimmedOrNull $Lines[$idx + 1]
                if ($next -and $next -notmatch '(?i)^date\s+de\s+passage\b') {
                    $city = [regex]::Replace($next, '\s+', ' ').Trim()
                    $city = [regex]::Replace($city, '\s+\d{7}\s*$', '').Trim()
                }
            }
            if (-not $street -and $prevStreetLike) { $street = $prevStreetLike }
            elseif (-not $street) {
                $beforeCp = Get-TrimmedOrNull ($line.Substring(0, $mCp.Index).Trim())
                if ($beforeCp) { $street = NormStreet $beforeCp }
            }
            break
        }

        if ($line -match '(?i)\b(?:contact|heure|prestation|tournee|tourn[ée]e|odm|ordre|mission|client)\b') { continue }

        if (IsAddressLine $line) {
            $norm = NormStreet $line
            if ($norm) {
                $prevStreetLike = $norm
                if (-not $street) { $street = $norm }
            }
        }
    }

    $result.Street = NormStreet $street
    $result.PostalCode = $postal
    $result.City = $city
    $full = @($result.Street, $result.PostalCode, $result.City) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $result.FullAddress = if ($full.Count -gt 0) { $full -join ' ' } else { $null }
    return $result
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

function script:Find-ClientAnchorLineIndex {
    <#
    Ligne contenant l'identifiant client au format N° / N (OCR) : priorité stricte N° + id (collage pdftotext inclus).
    Aucun repli sur un autre N° de la page : fallbacks tolérés seulement si occurrence unique (id ou ligne libellée).
    #>
    param(
        [string[]]$Lines,
        [string]$ClientId
    )
    if (-not $Lines -or [string]::IsNullOrWhiteSpace($ClientId)) { return -1 }
    $esc = [regex]::Escape($ClientId)
    $tok = $script:RxNumeroSignToken
    $tokOpt = $script:RxNumeroSignTokenOpt
    $pA = '(?i)N\s*' + $tok + '\s*' + $esc + '(?=\D|$)'
    $pB = '(?i)N\s*' + $tok + '\s*' + $esc + '(?!\d)'
    $pC = '(?i)-\s*N\s*' + $tokOpt + '\s*' + $esc + '(?=\D|$)'
    $pD = '(?i)N\s+' + $esc + '\b'
    $strictPatterns = @($pA, $pB, $pC, $pD)

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = [string]$Lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        foreach ($pat in $strictPatterns) {
            if ($line -match $pat) { return $i }
        }
    }

    $rxLoose = [regex]('(?i)N\s*' + $tokOpt + '\s*' + $esc + '(?=\D|$)')
    $looseIdx = [System.Collections.Generic.List[int]]::new()
    for ($j = 0; $j -lt $Lines.Count; $j++) {
        $line2 = [string]$Lines[$j]
        if ([string]::IsNullOrWhiteSpace($line2)) { continue }
        if ($rxLoose.IsMatch($line2)) { [void]$looseIdx.Add($j) }
    }
    if ($looseIdx.Count -eq 1) { return $looseIdx[0] }

    $labeledIdx = [System.Collections.Generic.List[int]]::new()
    for ($k = 0; $k -lt $Lines.Count; $k++) {
        $line3 = [string]$Lines[$k]
        if ([string]::IsNullOrWhiteSpace($line3)) { continue }
        if ($line3 -match '(?i)\bclient\b' -and $line3 -match [regex]::Escape($ClientId)) {
            [void]$labeledIdx.Add($k)
        }
    }
    if ($labeledIdx.Count -eq 1) { return $labeledIdx[0] }

    return -1
}

function script:Find-AddressFromLines {
    param(
        [string[]]$Lines,
        [int]$ClientAnchorIndex = -1
    )
    $result = @{
        Street      = $null
        PostalCode  = $null
        City        = $null
        FullAddress = $null
    }
    if (-not $Lines -or $Lines.Count -eq 0) { return $result }

    $anchor = $ClientAnchorIndex
    if ($anchor -lt 0 -or $anchor -ge $Lines.Count) {
        for ($i = 0; $i -lt $Lines.Count; $i++) {
            if ([string]$Lines[$i] -match ('(?i)N\s*' + $script:RxNumeroSignToken + '\s*\d{4,12}')) {
                $anchor = $i
                break
            }
        }
    }
    if ($anchor -lt 0 -or $anchor -ge $Lines.Count) { return $result }

    function script:Normalize-StreetAddressCandidate {
        param([string]$Value)
        $s = Get-TrimmedOrNull $Value
        if (-not $s) { return $null }
        if ($s -match '^\d{1,2}/\d{1,2}/\d{2,4},?\s+\d{1,2}:\d{2}\s*(?:AM|PM)?$') { return $null }
        $s = [regex]::Replace($s, '\s+\d{7}\s*$', '')
        $s = [regex]::Replace($s, '\s+', ' ').Trim()
        if ([string]::IsNullOrWhiteSpace($s)) { return $null }
        return $s
    }

    $street = $null
    $postal = $null
    $city = $null
    $prevStreetLike = $null
    $end = [Math]::Min($Lines.Count - 1, $anchor + 28)
    for ($idx = $anchor + 1; $idx -le $end; $idx++) {
        $line = Get-TrimmedOrNull $Lines[$idx]
        if (-not $line) { continue }
        if ($line -match '(?i)\bDate\s+de\s+passage\b') { break }

        $mCp = [regex]::Match($line, '\b(\d{5})\b')
        if ($mCp.Success -and (Test-IsLikelyFrenchPostalTokenInContext -Line $line -Match $mCp)) {
            $postal = $mCp.Groups[1].Value
            $after = $line.Substring($mCp.Index + $mCp.Length).Trim(' ', '-', ',', ';')
            if (-not [string]::IsNullOrWhiteSpace($after)) {
                $city = [regex]::Replace($after, '\s+', ' ').Trim()
                $city = [regex]::Replace($city, '\s+\d{7}\s*$', '').Trim()
            }
            elseif (($idx + 1) -le $end) {
                $next = Get-TrimmedOrNull $Lines[$idx + 1]
                if ($next -and $next -notmatch '(?i)^date\s+de\s+passage\b') {
                    $city = [regex]::Replace($next, '\s+', ' ').Trim()
                    $city = [regex]::Replace($city, '\s+\d{7}\s*$', '').Trim()
                }
            }
            if (-not $street -and $prevStreetLike) {
                $street = $prevStreetLike
            }
            elseif (-not $street -and (IsAddressLine $line)) {
                $beforeCp = Get-TrimmedOrNull ($line.Substring(0, $mCp.Index).Trim())
                if ($beforeCp) {
                    $street = Normalize-StreetAddressCandidate $beforeCp
                }
            }
            break
        }

        if ($line -match '(?i)\b(?:contact|heure|prestation|tournee|tourn[ée]e|odm|ordre|mission|client)\b') {
            continue
        }

        if (IsAddressLine $line) {
            $norm = Normalize-StreetAddressCandidate $line
            if ($norm) {
                $prevStreetLike = $norm
                if (-not $street) {
                    $street = $norm
                }
            }
        }
    }

    $full = @($street, $postal, $city) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $result.Street = Normalize-StreetAddressCandidate $street
    $result.PostalCode = $postal
    $result.City = $city
    $result.FullAddress = if ($full.Count -gt 0) { $full -join ' ' } else { $null }
    return $result
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
    param(
        [string]$Text,
        [string]$ClientId,
        [string[]]$Lines = $null
    )
    if ($Lines) {
        for ($i = 0; $i -lt $Lines.Count; $i++) {
            $ln = $Lines[$i]
            if ([string]::IsNullOrWhiteSpace($ln)) { continue }
            if ($ln -match ('(?i)(?:ordre(?:\s+de\s+missions?)?|o\.?\s*t\.?|intervention|n' + $script:RxNumeroSignTokenOpt + '\s*ot|n' + $script:RxNumeroSignTokenOpt + '\s*ordre|r[ée]f(?:érence)?\.?|mission|bon\s+de\s+commande)\s*:\s*$')) {
                if (($i + 1) -lt $Lines.Count) {
                    $nx = Get-TrimmedOrNull $Lines[$i + 1]
                    if ($nx -match '^(\d{6,10})\s*$') { return $Matches[1] }
                }
            }
        }
    }

    if ($Lines) {
        foreach ($ln in $Lines) {
            if ([string]::IsNullOrWhiteSpace($ln)) { continue }
            if ($ln -match '^\s*(\d{7})\s*$') {
                $val = $Matches[1]
                if ($ClientId -and $val -eq $ClientId) { continue }
                return $val
            }
        }
    }

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
    param(
        [string]$Text,
        [string[]]$Lines = $null
    )
    if ($Lines) {
        for ($i = 0; $i -lt $Lines.Count; $i++) {
            $ln = $Lines[$i]
            if ([string]::IsNullOrWhiteSpace($ln)) { continue }
            if ($ln -match '(?i)date\s+de\s+passage\s*[:.]?\s*(\d{2}/\d{2}/\d{4})') {
                $rawInline = $Matches[1]
                try {
                    return [datetime]::ParseExact($rawInline, 'dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
                }
                catch { }
            }
            if ($ln -match '(?i)^\s*date\s+de\s+passage\s*:\s*$') {
                if (($i + 1) -lt $Lines.Count) {
                    $nx = Get-TrimmedOrNull $Lines[$i + 1]
                    if ($nx -match '^(\d{2}/\d{2}/\d{4})\s*$') {
                        $raw = $Matches[1]
                        try {
                            return [datetime]::ParseExact($raw, 'dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
                        }
                        catch { }
                    }
                }
            }
        }
    }

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

function script:Test-EntityExtractorLineOpensNewCarrierBlock {
    <#
    .SYNOPSIS
        Ligne sans code ODM : début d'un nouveau bloc prestation tel que PDF réel multi-ligne
        (nouveau bloc = rejette les lignes suivantes précédentes ex. Bac / consignes).
    #>
    param([AllowNull()][AllowEmptyString()][string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
    [string]$ln = $Line.Trim()
    # Accents usuels ADV + ASCII — début « mot » après espaces début ligne
    if ($ln -match '(?i)^(?:Collecte|Destruction|Ramassage|Enlèvement|Enlevement|Tri|Piles|Récupération|Recuperation|r[ée]cup[ée]ration)\b') {
        return $true
    }
    return $false
}

function script:Find-ServicesFromLines {
    param([string[]]$Lines)
    $list = [System.Collections.Generic.List[object]]::new()
    if (-not $Lines) { return $list.ToArray() }

    $pendingFragments = [System.Collections.Generic.List[string]]::new()

    foreach ($line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $matches = $script:RxOdmPair.Matches($line)
        if ($matches.Count -eq 0) {
            [string]$ln = $line.Trim()
            if ($ln.Length -eq 0) { continue }
            if (Test-EntityExtractorLineOpensNewCarrierBlock -Line $ln) {
                $pendingFragments.Clear()
                [void]$pendingFragments.Add($ln)
            }
            else {
                [void]$pendingFragments.Add($ln)
            }
            continue
        }

        [string]$joinedPending = (($pendingFragments.ToArray() | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' ').Trim()
        [string]$pref = ''
        if (-not [string]::IsNullOrWhiteSpace($joinedPending)) { $pref = $joinedPending }

        $lastIndex = 0
        for ($mi = 0; $mi -lt $matches.Count; $mi++) {
            $m = $matches[$mi]
            $odm = Normalize-OdmToken -Raw $m.Groups[1].Value
            $idx = $m.Index
            $len = $m.Length

            $typePart = $line.Substring($lastIndex, $idx - $lastIndex)
            $typeMid = Get-TrimmedOrNull $typePart

            [string]$typeUse = ''
            [string]$effectivePref = if ($mi -eq 0) { $pref } else { '' }
            if ([string]::IsNullOrWhiteSpace($effectivePref)) {
                $typeUse = $typeMid
            }
            elseif ($null -eq $typeMid) {
                $typeUse = Get-TrimmedOrNull $effectivePref
            }
            else {
                $typeUse = Get-TrimmedOrNull (($effectivePref.Trim() + ' ' + [string]$typeMid.Trim()).Trim())
            }

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
                Type     = $typeUse
                ODM      = $odm
                Quantity = $qty
            })

            $lastIndex = $idx + $len
        }

        $pendingFragments.Clear()
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

    .PARAMETER DebugClientBlocks
    Affiche le bloc client (ancre, bornes, lignes du bloc, exclusions, ClientName). Équivalent : PDF_CLIENT_BLOCK_DEBUG=1 ou PDF_ENTITY_DEBUG_CLIENT_BLOCKS=1.

    Diag observabilité : $env:PDF_SCORING = "1" → score page (vs lignes brutes) + cumul ; Reset-PdfExtractionScoringSession avant le PDF, Write-PdfExtractionScoringSessionGlobalReport en fin.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$PageNumber,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,

        [switch]$DebugClientBlocks
    )

    $entity = [PageEntity]::new($PageNumber)
    try {
    if (-not $Lines -or $Lines.Count -eq 0) {
        if (Test-EntityExtractorDebugEnabled) {
            Write-Host "[EntityExtractor DEBUG] Page $PageNumber : pas de lignes (null ou Count=0)." -ForegroundColor Yellow
        }
        return $entity
    }

    $inputLines = @(
        foreach ($ln in @($Lines)) {
            if ($null -eq $ln) { '' } else { [string]$ln }
        }
    )
    $processableLines = @($inputLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($processableLines.Count -eq 0) {
        if (Test-EntityExtractorDebugEnabled) {
            Write-EntityExtractorDebugReport -PageNumber $PageNumber -RawLines $inputLines -SanitizedLines @() -NormalizedLines @() -Text '' -Entity $entity
        }
        return $entity
    }

    $sanitizedLines = @(Normalize-PdfNoiseText -Lines $processableLines)
    $normalized = @(Get-NormalizedNonEmptyLines -Lines $sanitizedLines)
    $text = if ($normalized.Count -gt 0) { $normalized -join "`n" } else { '' }
    Write-Host ("[TRACE-PDF-RAW] Page={0} Text=""{1}""" -f $PageNumber, $text)

    if ($normalized.Count -eq 0) {
        if (Test-EntityExtractorDebugEnabled) {
            Write-EntityExtractorDebugReport -PageNumber $PageNumber -RawLines @($Lines) -SanitizedLines $sanitizedLines -NormalizedLines $normalized -Text $text -Entity $entity
        }
        return $entity
    }

    $keyFields = Resolve-PageClientKeyFields -Lines $normalized -JoinedText $text
    $clientId = $keyFields.ClientId
    $entity.ClientID = $clientId
    Write-Host ("[TRACE-PDF-ID] Page={0} ExtractedClientID=""{1}""" -f $PageNumber, $clientId)
    $clientAnchorIndex = $keyFields.AnchorIndex
    if ($clientAnchorIndex -lt 0 -and [string]::IsNullOrWhiteSpace($clientId)) {
        for ($ai = 0; $ai -lt $normalized.Count; $ai++) {
            if ([string]$normalized[$ai] -match ('(?i)N\s*' + $script:RxNumeroSignToken + '\s*\d{4,12}')) {
                $clientAnchorIndex = $ai
                break
            }
        }
    }

    $clientBlock = Get-ClientBlock -Lines $normalized -AnchorIndex $clientAnchorIndex
    $entity.ClientName = Get-ClientNameFromBlock -Lines $normalized -Block $clientBlock -ClientId $clientId -PageNumber $PageNumber -DebugClientBlocks:$DebugClientBlocks

    $addr = if ($clientBlock.StartIndex -ge 0) {
        Get-AddressFromBlock -Lines $normalized -Block $clientBlock
    }
    else {
        @{ Street = $null; PostalCode = $null; City = $null; FullAddress = $null }
    }
    if (-not $addr.PostalCode -and -not $addr.City -and -not $addr.Street) {
        $addr = Find-AddressFromLines -Lines $normalized -ClientAnchorIndex $clientAnchorIndex
    }
    if (-not $addr.PostalCode -and -not $addr.City -and -not $addr.Street) {
        $addr = Build-AddressFromLines $normalized
    }
    $entity.Address['Street'] = $addr.Street
    $entity.Address['PostalCode'] = $addr.PostalCode
    $entity.Address['City'] = $addr.City
    $entity.Address['Full'] = if ($addr.PSObject.Properties['FullAddress']) { $addr.FullAddress } else { @($addr.Street, $addr.PostalCode, $addr.City) -join ' ' }

    $entity.WorkOrder = Find-WorkOrderInText -Text $text -ClientId $clientId -Lines $normalized
    $entity.VisitDate = Find-VisitDateInText -Text $text -Lines $normalized

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
            $skipClient = ($clientId -and $val -eq $clientId)
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
    finally {
        if ($env:PDF_SCORING -eq '1') {
            Write-PdfExtractionScoreReport -RawLines $Lines -Entity $entity
        }
    }
}

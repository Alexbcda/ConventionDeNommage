# STEP 5 — Détection prestations métier depuis le texte ODM PDF (source de vérité unique).
# Ne pas utiliser MatchResult / ExcelOrder / SpecialFlags pour la logique métier.

. (Join-Path $PSScriptRoot 'PlanningExcelTourneeSegments.ps1')
$_cnsPlanningDatabase = Join-Path $PSScriptRoot '..\..\..\Database\Database.ps1'
if (Test-Path -LiteralPath $_cnsPlanningDatabase) {
    . $_cnsPlanningDatabase
}
$_cnsCertPlaceholderCommon = Join-Path $PSScriptRoot 'CnsCertificatePlaceholderCommon.ps1'
if (Test-Path -LiteralPath $_cnsCertPlaceholderCommon) {
    . $_cnsCertPlaceholderCommon
}

function ConvertTo-CnsMetierMatchNormalizedText {
    <#
    .SYNOPSIS
        Normalisation tolérante : casse, accents, espaces multiples.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { return '' }
    $t = ([string]$Text).Trim()
    if ($t.Length -lt 1) { return '' }
    if (Get-Command NormalizeText -ErrorAction SilentlyContinue) {
        $t = NormalizeText -TextIn $t
    }
    $t = $t.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $t.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -eq [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            continue
        }
        [void]$sb.Append($ch)
    }
    $t = $sb.ToString().ToLowerInvariant()
    $t = [regex]::Replace($t, '\s+', ' ')
    return $t.Trim()
}

function Get-CnsMetierLettersOnlyCompact {
    param([AllowNull()][AllowEmptyString()][string]$NormalizedText)
    if ([string]::IsNullOrWhiteSpace($NormalizedText)) { return '' }
    return [regex]::Replace([string]$NormalizedText, '[^a-z]', '')
}

function Test-CnsMetierNormalizedTextMatchesKeyword {
    param(
        [AllowNull()][AllowEmptyString()][string]$NormalizedText,
        [Parameter(Mandatory = $true)]
        [string[]]$KeywordPatterns
    )
    if ([string]::IsNullOrWhiteSpace($NormalizedText)) { return $false }
    foreach ($pat in @($KeywordPatterns)) {
        if ([string]::IsNullOrWhiteSpace($pat)) { continue }
        if ($NormalizedText -match $pat) { return $true }
    }
    return $false
}

function Get-CnsPdfOdmPageTextContent {
    param(
        [AllowNull()] $PageEntity,
        [AllowNull()] $WorkOrderEntity
    )
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($src in @($PageEntity, $WorkOrderEntity)) {
        if ($null -eq $src) { continue }
        try {
            $cn = [string]$src.ClientName
            if (-not [string]::IsNullOrWhiteSpace($cn)) { [void]$parts.Add($cn) }
        }
        catch { }
        try {
            $cid = [string]$src.ClientID
            if (-not [string]::IsNullOrWhiteSpace($cid)) { [void]$parts.Add($cid) }
        }
        catch { }
        try {
            $wk = [string]$src.WorkOrder
            if (-not [string]::IsNullOrWhiteSpace($wk)) { [void]$parts.Add($wk) }
        }
        catch { }
        foreach ($svc in @($src.Services)) {
            if ($null -eq $svc) { continue }
            try {
                $ty = [string]$svc.Type
                if (-not [string]::IsNullOrWhiteSpace($ty)) { [void]$parts.Add($ty) }
            }
            catch { }
            try {
                $od = [string]$svc.ODM
                if (-not [string]::IsNullOrWhiteSpace($od)) { [void]$parts.Add($od) }
            }
            catch { }
        }
        if ($null -ne $src.PSObject.Properties['Lines']) {
            foreach ($ln in @($src.Lines)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$ln)) { [void]$parts.Add([string]$ln) }
            }
        }
    }
    return (($parts.ToArray()) -join ' ')
}

function ConvertTo-CnsCeaDetectionNormalizedText {
    <#
    .SYNOPSIS
        Normalisation CEA (STEP 5 / frag) : lowercase, accents, N°/No/#, ponctuation, espaces.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { return '' }
    $t = ([string]$Text).Trim()
    if ($t.Length -lt 1) { return '' }
    $t = ($t -replace '[\r\n]+', ' ')
    $t = ConvertTo-CnsMetierMatchNormalizedText -Text $t
    $t = [regex]::Replace($t, '(?i)\b(n°|no|#)\b', ' n ')
    $t = [regex]::Replace($t, 'n\s*[°º#o]\s*', 'n ')
    $t = [regex]::Replace($t, '[^a-z0-9\s]', ' ')
    $t = [regex]::Replace($t, '\s+', ' ')
    return $t.Trim()
}

function Get-CnsCeaPageSignalsFromNormalizedText {
    <#
    .SYNOPSIS
        Signaux CEA independants sur texte page normalise (STEP 5 frag) — pas de phrase complete requise.
    #>
    param([AllowNull()][AllowEmptyString()][string]$NormalizedText)
    if ([string]::IsNullOrWhiteSpace($NormalizedText)) {
        return [pscustomobject]@{
            HasCEA  = $false
            HasID   = $false
            HasSLE  = $false
            IsCea   = $false
        }
    }

    $norm = [string]$NormalizedText
    $digitsOnly = [regex]::Replace($norm, '[^0-9]', '')

    $hasCEA = ($norm -match 'cea')
    $hasID = ($norm -match '24531') -or ($norm -match '24 531') -or ($digitsOnly -match '24531')
    $hasSLE = ($norm -match 'sle') -or
        ($norm -match 'service logistique et environnement') -or
        ($norm -match 'service logistique')

    return [pscustomobject]@{
        HasCEA = [bool]$hasCEA
        HasID  = [bool]$hasID
        HasSLE = [bool]$hasSLE
        IsCea  = ([bool]$hasCEA -and [bool]$hasID -and [bool]$hasSLE)
    }
}

function Test-CnsCeaNormalizedTextIsCeaPoint {
    <#
    .SYNOPSIS
        Point CEA : signal1 (cea) ET signal2 (24531) ET signal3 (sle / service logistique / service logistique et environnement).
    #>
    param([AllowNull()][AllowEmptyString()][string]$NormalizedText)
    $sig = Get-CnsCeaPageSignalsFromNormalizedText -NormalizedText $NormalizedText
    return [bool]$sig.IsCea
}

function Get-CnsStep5PdftotextExecutable {
    <#
    .SYNOPSIS
        Délègue à Get-ResolvedPdfToTextPath (PdfExtractor) — même binaire que STEP 1–4.
    #>
    if (-not (Get-Command Get-ResolvedPdfToTextPath -ErrorAction SilentlyContinue)) {
        $_cnsPdfExtractor = Join-Path $PSScriptRoot '..\Extractors\PdfExtractor.ps1'
        if (Test-Path -LiteralPath $_cnsPdfExtractor) {
            . $_cnsPdfExtractor
        }
    }
    try {
        $p = Get-ResolvedPdfToTextPath
        if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path -LiteralPath $p -PathType Leaf)) {
            return ([System.IO.Path]::GetFullPath($p))
        }
    }
    catch { }
    return $null
}

function Get-CnsStep5PdftotextLinesFromSinglePagePdf {
    <#
    .SYNOPSIS
        STEP 5 uniquement : texte brut d'une page ODM (slice PDF mono-page du frag).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SinglePagePdfPath
    )
    if ([string]::IsNullOrWhiteSpace($SinglePagePdfPath)) { return @() }
    if (-not (Test-Path -LiteralPath $SinglePagePdfPath -PathType Leaf)) { return @() }

    $exe = Get-CnsStep5PdftotextExecutable
    if ([string]::IsNullOrWhiteSpace($exe)) {
        Write-Warning '[STEP5-CEA] pdftotext introuvable — detection CEA frag impossible.'
        return @()
    }

    $pdfAbs = [System.IO.Path]::GetFullPath($SinglePagePdfPath)
    foreach ($extra in @(@('-layout'), @())) {
        $tempOut = [System.IO.Path]::GetTempFileName()
        try {
            $args = @('-f', '1', '-l', '1', '-enc', 'UTF-8', '-q') + $extra + @($pdfAbs, $tempOut)
            $null = & $exe @args 2>$null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tempOut)) { continue }
            $lines = @(Get-Content -LiteralPath $tempOut -Encoding UTF8 -ErrorAction SilentlyContinue)
            $out = @($lines | ForEach-Object { if ($null -eq $_) { '' } else { [string]$_ } })
            if ($out.Count -gt 0) { return $out }
        }
        catch { }
        finally {
            Remove-Item -LiteralPath $tempOut -Force -ErrorAction SilentlyContinue
        }
    }
    return @()
}

function Test-CnsPdfFragPageRequiresCeaDocument {
    <#
    .SYNOPSIS
        Detection CEA par signaux sur texte page concatene (lignes pdftotext du slice frag STEP 5).
    #>
    param(
        [AllowEmptyCollection()]
        [string[]]$RawLines
    )
    if ($null -eq $RawLines -or $RawLines.Count -lt 1) { return $false }
    $continuous = (($RawLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ' ')
    if ([string]::IsNullOrWhiteSpace($continuous)) { return $false }
    $norm = ConvertTo-CnsCeaDetectionNormalizedText -Text $continuous
    return (Test-CnsCeaNormalizedTextIsCeaPoint -NormalizedText $norm)
}

function Get-CnsStep5RawLinesForPhysicalPage {
    param(
        [int]$PageNumberOneBased,
        [hashtable]$PdfRawLinesByPage = $null
    )
    if ($PageNumberOneBased -lt 1) { return $null }
    if ($null -eq $PdfRawLinesByPage) { return $null }
    if ($PdfRawLinesByPage.ContainsKey($PageNumberOneBased)) {
        return @($PdfRawLinesByPage[$PageNumberOneBased])
    }
    return $null
}

function ConvertTo-CnsFtBracketDisplayLabel {
    <#
    .SYNOPSIS
        Nettoie le libelle FT : garde UNIQUEMENT le texte avant le premier [ (ASCII ou pleine chasse).
    .EXAMPLE
        "FT CHAMBERY GRAND VERGER [2953] - N°8785" -> "FT CHAMBERY GRAND VERGER"
    #>
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$RawLabel
    )

    if ([string]::IsNullOrWhiteSpace($RawLabel)) {
        return ''
    }

    $t = [string]$RawLabel.Trim()

    if ($t -match '^(.*?)\s*[\[［].*$') {
        $t = $Matches[1].Trim()
    }

    $t = [regex]::Replace($t, '\s+', ' ').Trim()

    if (Get-Command Repair-CnsClientNumeroSignText -ErrorAction SilentlyContinue) {
        $t = Repair-CnsClientNumeroSignText -Text $t
    }
    $t = $t -replace '(?i)&apos;', "'"

    return $t
}

function Test-CnsFtCollectionPointLabelEligible {
    <#
    .SYNOPSIS
        Vrai si le libelle point de collecte commence par FT (insensible a la casse).
    #>
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Label
    )
    if ([string]::IsNullOrWhiteSpace($Label)) { return $false }
    return ([string]$Label).Trim() -match '(?i)^FT\s+'
}

function Resolve-CnsFtCollectionPointLabelOrNull {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Label,
        [switch]$FtDebug
    )
    if (-not (Test-CnsFtCollectionPointLabelEligible -Label $Label)) {
        if ($FtDebug -and -not [string]::IsNullOrWhiteSpace($Label)) {
            Write-Host ("[FT] Label rejete (ne commence pas par FT) : {0}" -f $Label) -ForegroundColor DarkYellow
        }
        return $null
    }
    return ([string]$Label).Trim()
}

function Get-CnsFtCollectionPointLabelFromPageEntity {
    <#
    .SYNOPSIS
        Reconstruit le nom du point de collecte FT via ClientNameLines (bbox step 1)
        et Get-ClientNameFromLines (meme logique que le certificat de destruction).
    #>
    param(
        [Parameter(Mandatory = $true)]
        $PageEntity,

        [Parameter(Mandatory = $true)]
        $WorkOrderEntity,

        [switch]$FtDebug
    )

    $cnLines = @()
    if ($PageEntity.PSObject.Properties['ClientNameLines'] -and $null -ne $PageEntity.ClientNameLines) {
        $cnLines = @($PageEntity.ClientNameLines)
    }

    if ($FtDebug) {
        Write-Host ("[FT-DEBUG] ClientNameLines.Count = {0}" -f $cnLines.Count) -ForegroundColor Cyan
        foreach ($i in 0..($cnLines.Count - 1)) {
            Write-Host ("[FT-DEBUG] Ligne {0} : {1}" -f $i, $cnLines[$i]) -ForegroundColor Gray
        }
    }

    if ($cnLines.Count -lt 1) {
        if ($FtDebug) { Write-Host '[FT-DEBUG] Pas de ClientNameLines - fallback sur ClientName' -ForegroundColor Yellow }
        $fallback = [string]$PageEntity.ClientName
        if (-not [string]::IsNullOrWhiteSpace($fallback)) {
            return (Resolve-CnsFtCollectionPointLabelOrNull -Label (ConvertTo-CnsFtBracketDisplayLabel -RawLabel $fallback) -FtDebug:$FtDebug)
        }
        return $null
    }

    $hasFtSignal = $false
    foreach ($line in $cnLines) {
        if (-not [string]::IsNullOrWhiteSpace($line) -and ([string]$line).Trim() -match '(?i)^FT\s+') {
            $hasFtSignal = $true
            break
        }
    }
    if (-not $hasFtSignal) {
        $clientNameProbe = [string]$PageEntity.ClientName
        if (-not [string]::IsNullOrWhiteSpace($clientNameProbe) -and $clientNameProbe.Trim() -match '(?i)^FT\s+') {
            $hasFtSignal = $true
        }
    }
    if (-not $hasFtSignal) {
        if ($FtDebug) { Write-Host '[FT-DEBUG] Aucun signal FT dans ClientNameLines/ClientName' -ForegroundColor Yellow }
        return $null
    }

    $clientId = [string]$WorkOrderEntity.ClientID
    if ([string]::IsNullOrWhiteSpace($clientId)) {
        foreach ($line in $cnLines) {
            if ($line -match '(?i)N°?\s*(\d{4,8})') {
                $clientId = $Matches[1]
                if ($FtDebug) { Write-Host ("[FT-DEBUG] ClientID extrait des lignes : {0}" -f $clientId) -ForegroundColor Yellow }
                break
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($clientId)) {
        if ($FtDebug) { Write-Host '[FT-DEBUG] Pas de ClientID - fallback sur ClientName' -ForegroundColor Yellow }
        $fallback = [string]$PageEntity.ClientName
        if (-not [string]::IsNullOrWhiteSpace($fallback)) {
            return (Resolve-CnsFtCollectionPointLabelOrNull -Label (ConvertTo-CnsFtBracketDisplayLabel -RawLabel $fallback) -FtDebug:$FtDebug)
        }
        return $null
    }

    $reconstructedName = $null
    Initialize-CnsPdfMetierEntityExtractorAccess

    if (Get-Command Get-ClientNameFromLines -ErrorAction SilentlyContinue) {
        try {
            $reconstructedName = Get-ClientNameFromLines -Lines $cnLines -ClientId $clientId
            if ($FtDebug -and -not [string]::IsNullOrWhiteSpace($reconstructedName)) {
                Write-Host ("[FT-DEBUG] Reconstruction Get-ClientNameFromLines : {0}" -f $reconstructedName) -ForegroundColor Green
            }
        }
        catch {
            Write-Warning ("[FT] Erreur Get-ClientNameFromLines : {0}" -f $_.Exception.Message)
        }
    }

    if ([string]::IsNullOrWhiteSpace($reconstructedName)) {
        $reconstructedName = [string]$WorkOrderEntity.ClientName
        if ([string]::IsNullOrWhiteSpace($reconstructedName)) {
            $reconstructedName = [string]$PageEntity.ClientName
        }
        if ($FtDebug) { Write-Host ("[FT-DEBUG] Repli sur ClientName : {0}" -f $reconstructedName) -ForegroundColor Yellow }
    }

    $cleanedName = ConvertTo-CnsFtBracketDisplayLabel -RawLabel $reconstructedName

    if ($FtDebug) {
        Write-Host ("[FT-DEBUG] Avant nettoyage : {0}" -f $reconstructedName) -ForegroundColor Gray
        Write-Host ("[FT-DEBUG] Apres nettoyage : {0}" -f $cleanedName) -ForegroundColor Green
    }

    return (Resolve-CnsFtCollectionPointLabelOrNull -Label $cleanedName -FtDebug:$FtDebug)
}

function ConvertTo-CnsFtCollectionPointDisplayLabel {
    <#
    .SYNOPSIS
        Normalise le libelle FT : supprime crochets (ASCII ou pleine chasse), N°, suffixes apres tiret.
    #>
    param(
        [AllowEmptyString()]
        [string]$Value
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $t = ([string]$Value).Trim()
    if ($t -notmatch '^(?i)FT\b') { return $t }

    # Cas PDF mal decoupe : "FT - N°8785GRAND VERGER" -> "FT GRAND VERGER"
    if ($t -match '^(?i)FT\s+-\s*N[°ºoO]?\s*\d+(?<agency>[A-Za-z].*)$') {
        $agency = ([string]$matches.agency).Trim()
        if (-not [string]::IsNullOrWhiteSpace($agency)) {
            return ('FT {0}' -f $agency) -replace '\s{2,}', ' '
        }
    }

    $cleaned = $t -replace '(?i)\s*[\[［][^\]］]*[\]］]\s*.*$', ''
    if ([string]::IsNullOrWhiteSpace($cleaned)) { $cleaned = $t }

    $cleaned = $cleaned -replace '(?i)\s*-\s*N[°ºoO]?\s*\d.*$', ''
    $cleaned = $cleaned -replace '\s*-.*$', ''
    $cleaned = ($cleaned -replace '\s{2,}', ' ').Trim()

    if ($cleaned -match '^(?i)FT\s*$') { return $t.Trim() }
    $cleaned = $cleaned -replace '(?i)&apos;', "'"
    return $cleaned
}

function Get-CnsFtCollectionPointLabelFromRawLines {
    <#
    .SYNOPSIS
        Extrait le premier libelle « FT <agence> » (ligne commencant par FT + espace).
        Ne s'appuie pas sur l'ID client.
    #>
    param(
        [AllowEmptyCollection()]
        [string[]]$RawLines
    )
    if ($null -eq $RawLines -or $RawLines.Count -lt 1) { return $null }
    foreach ($ln in @($RawLines)) {
        if ([string]::IsNullOrWhiteSpace($ln)) { continue }
        $t = ([string]$ln).Trim()
        if ($t -match '^(?i)FT\s+') {
            $rawLabel = $t
            $cleaned = ConvertTo-CnsFtCollectionPointDisplayLabel -Value $rawLabel
            if (-not [string]::IsNullOrWhiteSpace($cleaned)) {
                if ($cleaned -ne $rawLabel -and (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
                    Write-Log '[FT] Libelle nettoye' 'INFO' @{ raw = $rawLabel; cleaned = $cleaned }
                }
                return $cleaned
            }
        }
    }
    return $null
}

function Get-CnsStep5FragSliceFtCollectionPointLabel {
    <#
    .SYNOPSIS
        Libelle point de collecte FT pour une page ODM.
        Priorite 1 : bbox (ClientNameLines) + Get-ClientNameFromLines (comme certificat)
        Priorite 2 : PageEntity.ClientName deja fusionne
        Priorite 3 : RawLines layout (fallback)
        Priorite 4 : pdftotext slice (dernier recours)
    #>
    param(
        [AllowNull()][AllowEmptyString()][string]$FragSlicePdfPath,
        [AllowEmptyCollection()]
        [string[]]$PrecomputedRawLines = $null,
        [AllowEmptyCollection()]
        [string[]]$PdfRawLines = $null,
        [hashtable]$PdfRawLinesByPage = $null,
        [int]$RawPageNumOneBased = 0,
        [AllowNull()]
        $PageEntity = $null,
        [AllowNull()]
        $WorkOrderEntity = $null,
        [switch]$FtDebug
    )

    if ($null -ne $PageEntity -and $null -ne $WorkOrderEntity) {
        $bboxLabel = Get-CnsFtCollectionPointLabelFromPageEntity -PageEntity $PageEntity -WorkOrderEntity $WorkOrderEntity -FtDebug:$FtDebug
        $bboxLabel = Resolve-CnsFtCollectionPointLabelOrNull -Label $bboxLabel -FtDebug:$FtDebug
        if (-not [string]::IsNullOrWhiteSpace($bboxLabel)) {
            if ($FtDebug) { Write-Host ("[FT] Label via bbox + Get-ClientNameFromLines : {0}" -f $bboxLabel) -ForegroundColor Green }
            return $bboxLabel
        }
    }

    if ($null -ne $PageEntity) {
        $clientName = [string]$PageEntity.ClientName
        if (-not [string]::IsNullOrWhiteSpace($clientName) -and $clientName -match '(?i)^FT\s+') {
            $cleaned = ConvertTo-CnsFtBracketDisplayLabel -RawLabel $clientName
            $cleaned = Resolve-CnsFtCollectionPointLabelOrNull -Label $cleaned -FtDebug:$FtDebug
            if (-not [string]::IsNullOrWhiteSpace($cleaned)) {
                if ($FtDebug) { Write-Host ("[FT] Label via PageEntity.ClientName : {0}" -f $cleaned) -ForegroundColor Cyan }
                return $cleaned
            }
        }
    }

    $rawLines = @()
    if ($null -ne $PdfRawLines -and @($PdfRawLines).Count -gt 0) {
        $rawLines = @($PdfRawLines)
    }
    elseif ($null -ne $PrecomputedRawLines -and @($PrecomputedRawLines).Count -gt 0) {
        $rawLines = @($PrecomputedRawLines)
    }
    elseif ($RawPageNumOneBased -gt 0) {
        $fromStep1 = Get-CnsStep5RawLinesForPhysicalPage -PageNumberOneBased $RawPageNumOneBased -PdfRawLinesByPage $PdfRawLinesByPage
        if ($null -ne $fromStep1 -and @($fromStep1).Count -gt 0) {
            $rawLines = @($fromStep1)
        }
    }

    if ($rawLines.Count -gt 0) {
        foreach ($ln in $rawLines) {
            if ([string]::IsNullOrWhiteSpace($ln)) { continue }
            $trimmed = ([string]$ln).Trim()
            if ($trimmed -match '(?i)^FT\s+') {
                $cleaned = ConvertTo-CnsFtBracketDisplayLabel -RawLabel $trimmed
                $cleaned = Resolve-CnsFtCollectionPointLabelOrNull -Label $cleaned -FtDebug:$FtDebug
                if (-not [string]::IsNullOrWhiteSpace($cleaned)) {
                    if ($FtDebug) { Write-Host ("[FT] Label via RawLines layout : {0}" -f $cleaned) -ForegroundColor Yellow }
                    return $cleaned
                }
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($FragSlicePdfPath) -and (Test-Path -LiteralPath $FragSlicePdfPath -PathType Leaf)) {
        $sliceLines = @(Get-CnsStep5PdftotextLinesFromSinglePagePdf -SinglePagePdfPath $FragSlicePdfPath)
        foreach ($ln in $sliceLines) {
            if ([string]::IsNullOrWhiteSpace($ln)) { continue }
            $trimmed = ([string]$ln).Trim()
            if ($trimmed -match '(?i)^FT\s+') {
                $cleaned = ConvertTo-CnsFtBracketDisplayLabel -RawLabel $trimmed
                $cleaned = Resolve-CnsFtCollectionPointLabelOrNull -Label $cleaned -FtDebug:$FtDebug
                if (-not [string]::IsNullOrWhiteSpace($cleaned)) {
                    if ($FtDebug) { Write-Host ("[FT] Label via fallback pdftotext : {0}" -f $cleaned) -ForegroundColor DarkYellow }
                    return $cleaned
                }
            }
        }
    }

    if ($FtDebug) { Write-Host '[FT] Aucun label FT trouve' -ForegroundColor Red }
    return $null
}

function Test-CnsStep5FragSliceRequiresFtDocument {
    param(
        [AllowNull()][AllowEmptyString()][string]$FragSlicePdfPath,
        [AllowEmptyCollection()]
        [string[]]$PrecomputedRawLines = $null,
        [hashtable]$PdfRawLinesByPage = $null,
        [int]$RawPageNumOneBased = 0,
        [AllowNull()]
        $PageEntity = $null,
        [AllowNull()]
        $WorkOrderEntity = $null,
        [switch]$FtDebug
    )
    $label = Get-CnsStep5FragSliceFtCollectionPointLabel -FragSlicePdfPath $FragSlicePdfPath `
        -PrecomputedRawLines $PrecomputedRawLines -PdfRawLinesByPage $PdfRawLinesByPage -RawPageNumOneBased $RawPageNumOneBased `
        -PageEntity $PageEntity -WorkOrderEntity $WorkOrderEntity -FtDebug:$FtDebug
    if (Test-CnsFtCollectionPointLabelEligible -Label $label) {
        Write-Host ("[STEP5-FT] Point de collecte FT detecte : {0} (page {1})" -f $label, $(if ($RawPageNumOneBased -gt 0) { $RawPageNumOneBased } else { '?' })) -ForegroundColor DarkCyan
        return $true
    }
    return $false
}

function Test-CnsStep5FragSliceRequiresCeaDocument {
    <#
    .SYNOPSIS
        Detection CEA STEP 5 par signaux sur le texte ODM.
        Priorite : lignes de l'etape 1 (pdftotext) ; repli pdftotext sur le slice PDF si absent.
    #>
    param(
        [AllowNull()][AllowEmptyString()][string]$FragSlicePdfPath,
        [AllowEmptyCollection()]
        [string[]]$PrecomputedRawLines = $null,
        [hashtable]$PdfRawLinesByPage = $null,
        [int]$RawPageNumOneBased = 0
    )
    $rawLines = @()
    if ($null -ne $PrecomputedRawLines -and @($PrecomputedRawLines).Count -gt 0) {
        $rawLines = @($PrecomputedRawLines)
    }
    elseif ($RawPageNumOneBased -gt 0) {
        $fromStep1 = Get-CnsStep5RawLinesForPhysicalPage -PageNumberOneBased $RawPageNumOneBased -PdfRawLinesByPage $PdfRawLinesByPage
        if ($null -ne $fromStep1 -and @($fromStep1).Count -gt 0) {
            $rawLines = @($fromStep1)
            if ($null -ne $script:PlanningStep5Perf) {
                $script:PlanningStep5Perf.CeaFromStep1++
            }
        }
    }
    if ($rawLines.Count -lt 1) {
        if ([string]::IsNullOrWhiteSpace($FragSlicePdfPath)) { return $false }
        if (-not (Test-Path -LiteralPath $FragSlicePdfPath -PathType Leaf)) { return $false }
        $rawLines = @(Get-CnsStep5PdftotextLinesFromSinglePagePdf -SinglePagePdfPath $FragSlicePdfPath)
        if ($null -ne $script:PlanningStep5Perf) {
            $script:PlanningStep5Perf.CeaPdftotextFallback++
        }
    }
    if ($rawLines.Count -lt 1) { return $false }
    $isCea = (Test-CnsPdfFragPageRequiresCeaDocument -RawLines $rawLines)
    if ($isCea) {
        Write-Host ("[STEP5-CEA] Signaux CEA valides (page physique {0})" -f $(if ($RawPageNumOneBased -gt 0) { $RawPageNumOneBased } else { (Split-Path -Leaf $FragSlicePdfPath) })) -ForegroundColor DarkCyan
    }
    return $isCea
}

function Initialize-CnsPdfMetierEntityExtractorAccess {
    if ($script:CnsMetierEntityExtractorLoadAttempted) { return }
    $script:CnsMetierEntityExtractorLoadAttempted = $true
    if (Get-Command Get-ClientNameFromLines -ErrorAction SilentlyContinue) { return }
    $entityScript = Join-Path $PSScriptRoot '..\Extractors\EntityExtractor.ps1'
    if (-not (Test-Path -LiteralPath $entityScript)) { return }
    try {
        . $entityScript
    }
    catch {
        Write-Warning ("[METIER-PDF] Chargement EntityExtractor.ps1 echoue : {0}" -f $_.Exception.Message)
    }
}

function Test-CnsGardeClientNameDebugEnabled {
    return ([string]$env:CN_DEBUG_GARDE).Trim().ToLowerInvariant() -in @('1', 'true', 'yes', 'on')
}

function Write-CnsGardeClientNameDebug {
    param([AllowNull()][AllowEmptyString()][string]$Message)
    if (-not (Test-CnsGardeClientNameDebugEnabled)) { return }
    if ([string]::IsNullOrWhiteSpace($Message)) { return }
    Write-Host ("[GARDE-CLIENT] {0}" -f $Message) -ForegroundColor DarkYellow
}

function Repair-CnsClientDisplayNameForCover {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    $t = ([string]$Text).Trim()
    if (Get-Command Repair-CnsClientNumeroSignText -ErrorAction SilentlyContinue) {
        $t = Repair-CnsClientNumeroSignText -Text $t
    }
    $t = $t -replace '&apos;', "'"
    return $t
}

function ConvertTo-CnsCoverClientDisplayLabel {
    <#
    .SYNOPSIS
        Nettoie le nom client pour la page de garde : texte avant le premier [ uniquement.
    #>
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Name
    )
    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    $t = ([string]$Name).Trim()
    if ($t -match '^(.*?)\s*\[.*$') {
        $t = $Matches[1].Trim()
    }
    $t = [regex]::Replace($t, '\s+', ' ').Trim()
    if (Get-Command Repair-CnsClientNumeroSignText -ErrorAction SilentlyContinue) {
        $t = Repair-CnsClientNumeroSignText -Text $t
    }
    $t = $t -replace '&apos;', "'"
    return $t
}

function Remove-CnsCoverPrestationVehiculeSuffix {
    <#
    .SYNOPSIS
        Retire le suffixe (véhicule …) d'un libellé ou d'une ligne mémo garde.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Detail)
    if ([string]::IsNullOrWhiteSpace($Detail)) { return $Detail }
    return ([regex]::Replace(([string]$Detail).Trim(), '(?i)\s*\(véhicule\s+[^)]+\)\s*$', '')).Trim()
}

function Format-CnsCoverGardePrestationMemoLine {
    param(
        [AllowNull()][AllowEmptyString()][string]$Detail,
        [AllowNull()][AllowEmptyString()][string]$Client
    )
    [string]$det = Remove-CnsCoverPrestationVehiculeSuffix -Detail ([string]$Detail)
    [string]$cl = ConvertTo-CnsCoverClientDisplayLabel -Name ([string]$Client)
    if ([string]::IsNullOrWhiteSpace($cl)) { $cl = 'Non specifie' }
    $line = ("{0} - {1}" -f $det, $cl)
    return (Remove-CnsCoverPrestationVehiculeSuffix -Detail $line)
}

function Test-CnsPdfClientDisplayNameLooksPolluted {
    <#
    .SYNOPSIS
        Nom client pollué : date et/ou ligne prestation DEEE/piles/cartouches dans le libellé affiché.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $true }
    $n = ([string]$Name).Trim()
    if ($n -match '\d{1,2}/\d{1,2}/\d{2,4}') { return $true }
    if ($n -match '(?i)\b(collecte|deee|piles?|cartouche(s)?|encre)\b') { return $true }
    return $false
}

function Resolve-CnsPdfClientDisplayNameFromEntity {
    param(
        [Parameter(Mandatory = $true)]
        $Entity,
        [switch]$StoredClientNameOnly,
        [string]$DebugContext = ''
    )
    if ($null -eq $Entity) { return $null }

    [string]$ctx = if ([string]::IsNullOrWhiteSpace($DebugContext)) { 'Entity' } else { $DebugContext }

    if (-not $StoredClientNameOnly) {
        $cnLines = @()
        if ($Entity.PSObject.Properties['ClientNameLines'] -and $null -ne $Entity.ClientNameLines) {
            $cnLines = @($Entity.ClientNameLines)
        }
        [string]$clientId = ''
        try { $clientId = [string]$Entity.ClientID } catch { }
        Write-CnsGardeClientNameDebug -Message ("{0}: ClientNameLines.Count={1} ClientID=[{2}]" -f $ctx, $cnLines.Count, $clientId)
        if ($cnLines.Count -gt 0) {
            Write-CnsGardeClientNameDebug -Message ("{0}: ClientNameLines=[{1}]" -f $ctx, (($cnLines | ForEach-Object { [string]$_ }) -join ' | '))
        }

        if ($cnLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($clientId)) {
            Initialize-CnsPdfMetierEntityExtractorAccess
            if (Get-Command Get-ClientNameFromLines -ErrorAction SilentlyContinue) {
                $rebuilt = Get-ClientNameFromLines -Lines $cnLines -ClientId $clientId
                Write-CnsGardeClientNameDebug -Message ("{0}: Get-ClientNameFromLines -> [{1}]" -f $ctx, $(if ($rebuilt) { $rebuilt } else { '<vide>' }))
                if (-not [string]::IsNullOrWhiteSpace($rebuilt)) {
                    Write-CnsGardeClientNameDebug -Message ("{0}: decision=reconstruction" -f $ctx)
                    return (Repair-CnsClientDisplayNameForCover -Text $rebuilt)
                }
            }
            else {
                Write-CnsGardeClientNameDebug -Message ("{0}: Get-ClientNameFromLines indisponible" -f $ctx)
            }
        }
    }

    try {
        $cn = [string]$Entity.ClientName
        if (-not [string]::IsNullOrWhiteSpace($cn)) {
            Write-CnsGardeClientNameDebug -Message ("{0}: decision=repli ClientName stocke [{1}]" -f $ctx, $cn.Trim())
            return (Repair-CnsClientDisplayNameForCover -Text $cn)
        }
    }
    catch { }

    Write-CnsGardeClientNameDebug -Message ("{0}: decision=aucun nom" -f $ctx)
    return $null
}

function Get-CnsPdfPageClientDisplayName {
    param(
        [AllowNull()] $PageEntity,
        [AllowNull()] $WorkOrderEntity
    )

    [string]$peResolved = $null
    if ($null -ne $PageEntity) {
        $peResolved = Resolve-CnsPdfClientDisplayNameFromEntity -Entity $PageEntity -DebugContext 'PageEntity'
    }

    if (-not [string]::IsNullOrWhiteSpace($peResolved) -and -not (Test-CnsPdfClientDisplayNameLooksPolluted -Name $peResolved)) {
        Write-CnsGardeClientNameDebug -Message ("final=PageEntity [{0}]" -f $peResolved)
        return $peResolved
    }

    if ($null -ne $WorkOrderEntity) {
        $woResolved = Resolve-CnsPdfClientDisplayNameFromEntity -Entity $WorkOrderEntity -StoredClientNameOnly -DebugContext 'WorkOrderEntity'
        if (-not [string]::IsNullOrWhiteSpace($woResolved)) {
            Write-CnsGardeClientNameDebug -Message ("final=WorkOrderEntity [{0}] (PageEntity pollué ou absent)" -f $woResolved)
            return $woResolved
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($peResolved)) {
        Write-CnsGardeClientNameDebug -Message ("final=PageEntity repli [{0}]" -f $peResolved)
        return $peResolved
    }

    Write-CnsGardeClientNameDebug -Message 'final=Non specifie'
    return 'Non specifie'
}

function Get-CnsPonctuellePrestationDisplayLabelFromServiceType {
    <#
    .SYNOPSIS
        Libellé affichable pour une prestation ponctuelle (Collecte / Depose / Livraison Ponctuel), ou $null si parasite.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Type)
    if ([string]::IsNullOrWhiteSpace($Type)) { return $null }
    $raw = ([string]$Type).Trim()
    $norm = ConvertTo-CnsMetierMatchNormalizedText -Text $raw
    if ([string]::IsNullOrWhiteSpace($norm)) { return $null }

    $m = [regex]::Match($raw, '(?i)\b(Collecte|D[eéè]pose|Livraison|Fourniture)\s+Ponctuel\b.*$')
    if (-not $m.Success) { return $null }

    if ($norm -match 'neon|néon|tube|alveole|vrac|cartouche|encre|deee') {
        return 'Collecte DEEE'
    }
    if ($norm -match 'pile') {
        return 'Collecte de piles'
    }

    $label = $m.Value.Trim()
    $label = [regex]::Replace($label, '(?i)\bSac\s+\d+L[^/]*(?=/\d|\s+(?:Bouteilles|Canettes|Essuie|Verre|Multi|Papier|Carton))', '')
    $label = [regex]::Replace($label, '(?i)\s*/\d+\s*kg\s*', ' ')
    $label = [regex]::Replace($label, '\s+', ' ').Trim()

    $labelNorm = ConvertTo-CnsMetierMatchNormalizedText -Text $label
    if (-not ($labelNorm -match '^(collecte|depose|livraison|fourniture)\s+ponctuel')) { return $null }
    if ($labelNorm -match 'traitement\s+filiere\s+de\s+valorisation') { return $null }
    if ($labelNorm -match '\d{1,2}/\d{1,2}/\d{2,4}') { return $null }
    if ($labelNorm -match '\b\d{5}\b') { return $null }

    return $label
}

function Test-CnsServiceTypeIsPonctuellePrestationLine {
    <#
    .SYNOPSIS
        Prestation ponctuelle : préfixe métier Collecte / Depose / Livraison + Ponctuel (texte normalisé).
    #>
    param([AllowNull()][AllowEmptyString()][string]$Type)
    return (-not [string]::IsNullOrWhiteSpace((Get-CnsPonctuellePrestationDisplayLabelFromServiceType -Type $Type)))
}

function Test-CnsPonctuellePrestationTypeIndicatesSpecificWaste {
    <#
    .SYNOPSIS
        True si la prestation ponctuelle concerne des déchets spécifiques (dédup track / ponctuelle sur la garde).
    #>
    param([AllowNull()][AllowEmptyString()][string]$Type)
    if ([string]::IsNullOrWhiteSpace($Type)) { return $false }
    $norm = ConvertTo-CnsMetierMatchNormalizedText -Text $Type
    if ([string]::IsNullOrWhiteSpace($norm)) { return $false }
    return ($norm -match 'pile|deee|batterie|ampoule|neon|tube')
}

function Get-CnsVehiculeImmatriculationByNumeroParc {
    param([AllowNull()][AllowEmptyString()][string]$NumeroParc)
    if ([string]::IsNullOrWhiteSpace($NumeroParc)) { return $null }
    [string]$parc = ([string]$NumeroParc).Trim()
    $parc = [regex]::Replace($parc, '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($parc)) { return $null }
    if (-not (Get-Command Get-VehiculeByNumeroParc -ErrorAction SilentlyContinue)) { return $null }
    try {
        $vehicule = Get-VehiculeByNumeroParc -NumeroParc $parc
        if ($null -ne $vehicule) {
            $immat = ''
            try { $immat = [string]$vehicule.immatriculation } catch { }
            if (-not [string]::IsNullOrWhiteSpace($immat)) {
                return $immat.Trim()
            }
        }
    }
    catch {
        Write-Warning ("[METIER-PDF] Get-VehiculeByNumeroParc echoue : {0}" -f $_.Exception.Message)
    }
    return $null
}

function Get-CnsNumeroParcForExcelOrderIndex {
    <#
    .SYNOPSIS
        Numéro de parc Excel pour un OrderIndex : propriété slot NumeroParc ou Vehicule du segment tournée.
    #>
    param(
        [int]$ExcelOrderIndex,
        [AllowEmptyCollection()]
        [object[]]$ExcelOrder = @(),
        [AllowEmptyCollection()]
        [object[]]$Segments = @(),
        [AllowNull()]
        [hashtable]$ExcelOrderIndexToSegmentIndex = $null
    )
    if ($ExcelOrderIndex -lt 1) { return $null }

    foreach ($slot in @($ExcelOrder)) {
        if ($null -eq $slot) { continue }
        try {
            if ([int]$slot.OrderIndex -ne $ExcelOrderIndex) { continue }
            if ($slot.PSObject.Properties['NumeroParc'] -and -not [string]::IsNullOrWhiteSpace([string]$slot.NumeroParc)) {
                return ([string]$slot.NumeroParc).Trim()
            }
            break
        }
        catch { }
    }

    if ($null -eq $ExcelOrderIndexToSegmentIndex) { return $null }
    $segNum = $ExcelOrderIndexToSegmentIndex[$ExcelOrderIndex]
    if ($null -eq $segNum) {
        $sk = ([string]$ExcelOrderIndex).Trim()
        if ($sk.Length -gt 0) { $segNum = $ExcelOrderIndexToSegmentIndex[$sk] }
    }
    if ($null -eq $segNum) { return $null }
    try { $sn = [int]$segNum } catch { return $null }
    if ($sn -lt 1) { return $null }

    foreach ($seg in @($Segments)) {
        if ($null -eq $seg) { continue }
        try {
            if ([int]$seg.SegmentIndex -ne $sn) { continue }
            $v = ([string]$seg.Vehicule).Trim()
            if ([string]::IsNullOrWhiteSpace($v)) { return $null }
            $plain = $v.ToUpperInvariant()
            foreach ($sent in @('NON SPECIFIE', 'NON SPECIFIEE', 'INCONNU', '-', 'N/A', 'NA', 'ND')) {
                if ($plain -eq $sent) { return $null }
            }
            return $v
        }
        catch { }
    }
    return $null
}

function Test-CnsPdfTextLineIsDestructionPrestation {
  param([AllowNull()][AllowEmptyString()][string]$Line)
  if (Test-CnsServiceTypeIsDestructionPrestationLine -Type $Line) { return $true }
  $norm = ConvertTo-CnsMetierMatchNormalizedText -Text $Line
  if ([string]::IsNullOrWhiteSpace($norm)) { return $false }
  return (Test-CnsMetierNormalizedTextMatchesKeyword -NormalizedText $norm -KeywordPatterns @(
      '(?<![a-z])destruction(\s+confidentielle)?(\s+de\b|\b)',
      '(?<![a-z])destruction\s+confidentielle\b'
  ))
}

function Test-CnsPdfPageRequiresDestructionCertificate {
    <#
    .SYNOPSIS
        Certificat : prestation destruction dans le texte ODM + lien WorkOrder-prestation (7 chiffres).
    #>
    param(
        [AllowNull()] $PageEntity,
        [AllowNull()] $WorkOrderEntity
    )
    $wo = $WorkOrderEntity
    if ($null -eq $wo -and $null -ne $PageEntity) {
        $wo = $PageEntity
    }
    if ($null -eq $wo) { return $false }

    [string]$baseId = Get-CnsWorkOrderBaseIdFromEntity -WorkOrderEntity $wo
    if ([string]::IsNullOrWhiteSpace($baseId)) {
        $textAll = Get-CnsPdfOdmPageTextContent -PageEntity $PageEntity -WorkOrderEntity $WorkOrderEntity
        $rxOdm = [regex]'(?i)(?<![0-9])(\d{7}\s*\p{Pd}\s*\d+)\b'
        $m = $rxOdm.Match($textAll)
        if ($m.Success) {
            $collapsed = [regex]::Replace([string]$m.Groups[1].Value, '\s+', '')
            $oneDash = [regex]::Replace($collapsed, '\p{Pd}+', '-')
            $baseId = Get-CnsWorkOrderBaseIdFromToken -Token $oneDash
        }
    }
    if ([string]::IsNullOrWhiteSpace($baseId)) { return $false }

    foreach ($svc in @($wo.Services)) {
        if ($null -eq $svc) { continue }
        [string]$type = ''
        [string]$odm = ''
        try { $type = [string]$svc.Type } catch { }
        try { $odm = [string]$svc.ODM } catch { }
        if (-not (Test-CnsPdfTextLineIsDestructionPrestation -Line $type)) { continue }
        [string]$odmBase = Get-CnsWorkOrderBaseIdFromToken -Token $odm
        if ($odmBase -eq $baseId) { return $true }
    }

    $fullText = Get-CnsPdfOdmPageTextContent -PageEntity $PageEntity -WorkOrderEntity $WorkOrderEntity
    $normFull = ConvertTo-CnsMetierMatchNormalizedText -Text $fullText
    if (-not (Test-CnsMetierNormalizedTextMatchesKeyword -NormalizedText $normFull -KeywordPatterns @(
            '(?<![a-z])destruction(\s+confidentielle)?(\s+de\b|\b)',
            '(?<![a-z])destruction\s+confidentielle\b'
        ))) {
        return $false
    }

    foreach ($line in @($fullText -split "`n")) {
        if (-not (Test-CnsPdfTextLineIsDestructionPrestation -Line $line)) { continue }
        [string]$odmBase2 = Get-CnsWorkOrderBaseIdFromToken -Token $line
        if ($odmBase2 -eq $baseId) { return $true }
    }
    return $false
}

function Get-CnsPdfPageTrackDechetEntries {
    param(
        [AllowNull()] $PageEntity,
        [AllowNull()] $WorkOrderEntity
    )
    $client = Get-CnsPdfPageClientDisplayName -PageEntity $PageEntity -WorkOrderEntity $WorkOrderEntity
    $text = Get-CnsPdfOdmPageTextContent -PageEntity $PageEntity -WorkOrderEntity $WorkOrderEntity
    $norm = ConvertTo-CnsMetierMatchNormalizedText -Text $text
    if ([string]::IsNullOrWhiteSpace($norm)) { return @() }

    $found = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    $candidates = New-Object System.Collections.Generic.List[string]
    if ($null -ne $WorkOrderEntity) {
        foreach ($svc in @($WorkOrderEntity.Services)) {
            if ($null -eq $svc) { continue }
            try {
                $ty = [string]$svc.Type
                if (-not [string]::IsNullOrWhiteSpace($ty)) { [void]$candidates.Add($ty) }
            }
            catch { }
        }
    }
    if ($null -ne $PageEntity) {
        foreach ($svc in @($PageEntity.Services)) {
            if ($null -eq $svc) { continue }
            try {
                $ty = [string]$svc.Type
                if (-not [string]::IsNullOrWhiteSpace($ty)) { [void]$candidates.Add($ty) }
            }
            catch { }
        }
    }
    if ($candidates.Count -lt 1) {
        foreach ($ln in @($text -split "`n")) {
            if (-not [string]::IsNullOrWhiteSpace($ln)) { [void]$candidates.Add([string]$ln) }
        }
    }

    foreach ($line in @($candidates)) {
        $ln = ConvertTo-CnsMetierMatchNormalizedText -Text $line
        if ([string]::IsNullOrWhiteSpace($ln)) { continue }
        $compact = Get-CnsMetierLettersOnlyCompact -NormalizedText $ln
        [string]$detail = $null

        if ($ln -match 'pile(s)?' -or $compact -match 'piles?') {
            $detail = 'Collecte de piles'
        }
        elseif (($ln -match 'cartouche' -and $ln -match 'encre') -or ($compact -match 'cartouche' -and $compact -match 'encre')) {
            $detail = 'Collecte cartouches encre'
        }
        elseif ($ln -match 'neon|néon|tube' -or $compact -match 'neon|néon|tube') {
            $detail = 'Collecte Néons / tubes'
        }
        elseif ($ln -match 'deee' -or $compact -match 'deee') {
            $detail = 'Collecte DEEE'
        }

        if ([string]::IsNullOrWhiteSpace($detail)) { continue }
        $key = ('{0}|{1}' -f $detail, $client)
        if ($seen.Add($key)) {
            [void]$found.Add([pscustomobject]@{ Detail = $detail; Client = $client; SourceLine = $line })
        }
    }

    if ($found.Count -lt 1) {
        $normCompact = Get-CnsMetierLettersOnlyCompact -NormalizedText $norm
        if ($norm -match 'pile(s)?' -or $normCompact -match 'piles?') {
            $detail = 'Collecte de piles'
        }
        elseif (($norm -match 'cartouche' -and $norm -match 'encre') -or ($normCompact -match 'cartouche' -and $normCompact -match 'encre')) {
            $detail = 'Collecte cartouches encre'
        }
        elseif ($norm -match 'neon|néon|tube' -or $normCompact -match 'neon|néon|tube') {
            $detail = 'Collecte Néons / tubes'
        }
        elseif ($norm -match 'deee' -or $normCompact -match 'deee') {
            $detail = 'Collecte DEEE'
        }
        if (-not [string]::IsNullOrWhiteSpace($detail)) {
            $key = ('{0}|{1}' -f $detail, $client)
            if ($seen.Add($key)) {
                [void]$found.Add([pscustomobject]@{ Detail = $detail; Client = $client; SourceLine = $text })
            }
        }
    }

    return @($found.ToArray())
}

function Get-CnsPdfPagePonctuellePrestationEntries {
    <#
    .SYNOPSIS
        Prestations ponctuelles (Collecte / Depose / Livraison ponctuel) depuis Services page ou WO.
    .OUTPUTS
        Objets Detail (libelle affiche), Client, ODM, HasWaste.
    #>
    param(
        [AllowNull()] $PageEntity,
        [AllowNull()] $WorkOrderEntity
    )
    $client = Get-CnsPdfPageClientDisplayName -PageEntity $PageEntity -WorkOrderEntity $WorkOrderEntity
    if ([string]::IsNullOrWhiteSpace($client)) { $client = 'Non specifie' }
    else { $client = Repair-CnsClientDisplayNameForCover -Text $client }

    $found = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $serviceList = New-Object System.Collections.Generic.List[object]

    foreach ($src in @($PageEntity, $WorkOrderEntity)) {
        if ($null -eq $src) { continue }
        foreach ($svc in @($src.Services)) {
            if ($null -ne $svc) { [void]$serviceList.Add($svc) }
        }
    }

    foreach ($svc in $serviceList) {
        if ($null -eq $svc) { continue }
        [string]$type = ''
        [string]$odm = ''
        if ($svc -is [hashtable]) {
            if ($svc.ContainsKey('Type')) { $type = ([string]$svc['Type']).Trim() }
            if ($svc.ContainsKey('ODM')) { $odm = ([string]$svc['ODM']).Trim() }
        }
        else {
            try { $type = ([string]$svc.Type).Trim() } catch { }
            try { $odm = ([string]$svc.ODM).Trim() } catch { }
        }
        if ([string]::IsNullOrWhiteSpace($odm)) { continue }
        if ([string]::IsNullOrWhiteSpace($type)) { continue }

        $displayLabel = Get-CnsPonctuellePrestationDisplayLabelFromServiceType -Type $type
        if ([string]::IsNullOrWhiteSpace($displayLabel)) { continue }

        $key = $odm
        if (-not $seen.Add($key)) { continue }

        $hasWaste = Test-CnsPonctuellePrestationTypeIndicatesSpecificWaste -Type $type

        [void]$found.Add([pscustomobject]@{
            Detail   = $displayLabel
            Client   = $client
            ODM      = $odm
            HasWaste = $hasWaste
        })
    }

    return @($found.ToArray())
}

function Get-CnsPdfPageMetierAnalysis {
    param(
        [AllowNull()] $PageEntity,
        [AllowNull()] $WorkOrderEntity
    )
    $client = Get-CnsPdfPageClientDisplayName -PageEntity $PageEntity -WorkOrderEntity $WorkOrderEntity
    $needsCert = Test-CnsPdfPageRequiresDestructionCertificate -PageEntity $PageEntity -WorkOrderEntity $WorkOrderEntity
    return [pscustomobject]@{
        RequiresDestructionCertificate = $needsCert
        RequiresCeaDocument            = $false
        TrackDechetEntries             = @(Get-CnsPdfPageTrackDechetEntries -PageEntity $PageEntity -WorkOrderEntity $WorkOrderEntity)
        PonctuellePrestationEntries    = @(Get-CnsPdfPagePonctuellePrestationEntries -PageEntity $PageEntity -WorkOrderEntity $WorkOrderEntity)
        DestructionMemoClient          = if ($needsCert) { $client } else { $null }
    }
}

function Resolve-CnsWorkOrderEntityFromPdfPage {
    param(
        [Parameter(Mandatory = $true)]
        [int]$RawPageNumOneBased,
        [AllowEmptyCollection()]
        [object[]]$WorkOrders = @(),
        [AllowEmptyCollection()]
        [object[]]$PdfEntities = @()
    )
    if ($RawPageNumOneBased -gt 0 -and @($WorkOrders).Count -gt 0) {
        foreach ($w in @($WorkOrders)) {
            if ($null -eq $w) { continue }
            foreach ($p in @($w.Pages)) {
                try {
                    if ([int]$p -eq $RawPageNumOneBased) { return $w }
                }
                catch { }
            }
        }
    }
    $pe = $null
    if ($RawPageNumOneBased -gt 0 -and @($PdfEntities).Count -gt 0) {
        foreach ($e in @($PdfEntities)) {
            if ($null -eq $e) { continue }
            try {
                if ([int]$e.PageNumber -eq $RawPageNumOneBased) { $pe = $e; break }
            }
            catch { }
        }
    }
    if ($null -eq $pe) { return $null }

    $addr = @{ Street = $null; PostalCode = $null; City = $null }
    if ($null -ne $pe.Address) {
        try { $addr.Street = $pe.Address.Street } catch { }
        try { $addr.PostalCode = $pe.Address.PostalCode } catch { }
        try { $addr.City = $pe.Address.City } catch { }
    }
    return [pscustomobject]@{
        WorkOrder  = $pe.WorkOrder
        ClientID   = $pe.ClientID
        ClientName = $pe.ClientName
        Address    = $addr
        VisitDate  = $pe.VisitDate
        Contact    = $pe.Contact
        Services   = @($pe.Services)
        Pages      = @([int]$pe.PageNumber)
        Lines      = if ($null -ne $pe.PSObject.Properties['Lines']) { @($pe.Lines) } else { @() }
    }
}

function Get-CnsPdfPageEntityByPhysicalPage {
    param(
        [Parameter(Mandatory = $true)]
        [int]$PageNumberOneBased,
        [AllowEmptyCollection()]
        [object[]]$PdfEntities = @()
    )
    foreach ($pe in @($PdfEntities)) {
        if ($null -eq $pe) { continue }
        try {
            if ([int]$pe.PageNumber -eq $PageNumberOneBased) { return $pe }
        }
        catch { }
    }
    return $null
}

function Get-CnsTourneeMetierMemoLinesForBlock {
    <#
    .SYNOPSIS
        Mémos garde tournée agrégés depuis les ODM PDF du bloc (hors PdfFallback / __PRE__).
        Inclut l'instruction texte « Inventaire FT … compter le nombre de bacs » si un point FT est detecte.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$MainFrom1,
        [Parameter(Mandatory = $true)]
        [int]$MainTo1,
        [Parameter(Mandatory = $true)]
        [object[]]$SortedGsPairs,
        [Parameter(Mandatory = $true)]
        [hashtable]$FinalOrderToLine,
        [AllowEmptyCollection()]
        [object[]]$WorkOrders = @(),
        [AllowEmptyCollection()]
        [object[]]$PdfEntities = @()
    )
    $destructionClients = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $trackSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $trackLines = New-Object System.Collections.Generic.List[object]
    $ponctuelleSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $ponctuelleLines = New-Object System.Collections.Generic.List[object]
    $ftLabels = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)

    $pairs = @($SortedGsPairs)
    for ($pn = [int]$MainFrom1; $pn -le [int]$MainTo1; $pn++) {
        $idx = $pn - 1
        if ($idx -lt 0 -or $idx -ge $pairs.Count) { continue }
        $gsPair = $pairs[$idx]
        try { $fo = [int]$gsPair.FinalOrder } catch { continue }
        $ln = $FinalOrderToLine[$fo]
        if ($null -ne $ln) {
            $src = [string]$ln.Source
            if ($src -eq 'PdfFallback') { continue }
        }

        [int]$rawPn = 0
        try { $rawPn = [int]$gsPair.RawPageNum } catch { $rawPn = 0 }
        if ($rawPn -lt 1) { continue }

        $wo = Resolve-CnsWorkOrderEntityFromPdfPage -RawPageNumOneBased $rawPn -WorkOrders $WorkOrders -PdfEntities $PdfEntities
        $pe = Get-CnsPdfPageEntityByPhysicalPage -PageNumberOneBased $rawPn -PdfEntities $PdfEntities

        $analysis = Get-CnsPdfPageMetierAnalysis -PageEntity $pe -WorkOrderEntity $wo

        if (-not [string]::IsNullOrWhiteSpace($analysis.DestructionMemoClient)) {
            [void]$destructionClients.Add($analysis.DestructionMemoClient.Trim())
        }
        foreach ($tr in @($analysis.TrackDechetEntries)) {
            if ($null -eq $tr) { continue }
            [string]$det = Remove-CnsCoverPrestationVehiculeSuffix -Detail ([string]$tr.Detail)
            [string]$cl = [string]$tr.Client
            if ([string]::IsNullOrWhiteSpace($det)) { continue }
            if ([string]::IsNullOrWhiteSpace($cl)) { $cl = 'Non specifie' }
            $key = ('{0}|{1}' -f $det, $cl)
            if ($trackSeen.Add($key)) {
                [void]$trackLines.Add([pscustomobject]@{ Detail = $det; Client = $cl })
            }
        }
        foreach ($pp in @($analysis.PonctuellePrestationEntries)) {
            if ($null -eq $pp) { continue }
            [string]$det = Remove-CnsCoverPrestationVehiculeSuffix -Detail ([string]$pp.Detail)
            [string]$cl = [string]$pp.Client
            [string]$odm = ''
            try { $odm = ([string]$pp.ODM).Trim() } catch { }
            if ([string]::IsNullOrWhiteSpace($det)) { continue }
            if ([string]::IsNullOrWhiteSpace($cl)) { $cl = 'Non specifie' }

            if ($pp.HasWaste) {
                $skipAsTrackDup = $false
                foreach ($tr in @($analysis.TrackDechetEntries)) {
                    if ($null -eq $tr) { continue }
                    [string]$trDet = [string]$tr.Detail
                    if ($trDet -eq 'Collecte DEEE' -and $det -eq 'Collecte DEEE') { $skipAsTrackDup = $true; break }
                    if ($trDet -eq 'Collecte de piles' -and $det -eq 'Collecte de piles') { $skipAsTrackDup = $true; break }
                }
                if ($skipAsTrackDup) { continue }
            }

            $key = $odm
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            if ($ponctuelleSeen.Add($key)) {
                [void]$ponctuelleLines.Add([pscustomobject]@{ Detail = $det; Client = $cl })
            }
        }

        # Instruction garde : Inventaire FT (texte pur, aucun comptage)
        if (Get-Command Get-CnsStep5FragSliceFtCollectionPointLabel -ErrorAction SilentlyContinue) {
            $peLines = @()
            if ($null -ne $pe -and $null -ne $pe.PSObject.Properties['Lines'] -and $null -ne $pe.Lines) {
                $peLines = @($pe.Lines)
            }
            $ftLabel = Get-CnsStep5FragSliceFtCollectionPointLabel `
                -FragSlicePdfPath $null `
                -PdfRawLines $peLines `
                -RawPageNumOneBased $rawPn `
                -PageEntity $pe `
                -WorkOrderEntity $wo
            if (Test-CnsFtCollectionPointLabelEligible -Label $ftLabel) {
                [void]$ftLabels.Add(([string]$ftLabel).Trim())
            }
        }
    }

    $dedupSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($tr in $trackLines) {
        if ($null -eq $tr) { continue }
        $line = Format-CnsCoverGardePrestationMemoLine -Detail ([string]$tr.Detail) -Client ([string]$tr.Client)
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $key = $line
        if ($dedupSeen.Add($key)) {
            [void]$out.Add($line)
        }
    }
    foreach ($pp in $ponctuelleLines) {
        if ($null -eq $pp) { continue }
        $line = Format-CnsCoverGardePrestationMemoLine -Detail ([string]$pp.Detail) -Client ([string]$pp.Client)
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $key = $line
        if ($dedupSeen.Add($key)) {
            [void]$out.Add($line)
        }
    }
    foreach ($dc in @($destructionClients)) {
        $cl = ConvertTo-CnsCoverClientDisplayLabel -Name $dc
        if (-not [string]::IsNullOrWhiteSpace($cl)) {
            [void]$out.Add(("Certificat de destruction : {0}" -f $cl))
        }
    }
    foreach ($ftLabel in @($ftLabels)) {
        if ([string]::IsNullOrWhiteSpace($ftLabel)) { continue }
        $ftClean = ($ftLabel.Trim() -replace '(?i)&apos;', "'")
        $ftInstruction = ("Inventaire {0} compter le nombre de bacs" -f $ftClean)
        if ($dedupSeen.Add($ftInstruction)) {
            [void]$out.Add($ftInstruction)
        }
    }
    return @($out.ToArray())
}

function Get-CnsMetierTemplatePdfPath {
    param([Parameter(Mandatory = $true)][string]$FileName)
    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:CN_METIER_TEMPLATE_DIR)) {
        [void]$candidates.Add((Join-Path $env:CN_METIER_TEMPLATE_DIR.Trim() $FileName))
    }
    try {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
        [void]$candidates.Add((Join-Path $repoRoot ('templates\' + $FileName)))
        [void]$candidates.Add((Join-Path $repoRoot ('templates\planning\' + $FileName)))
    }
    catch { }
    foreach ($p in @($candidates)) {
        if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path -LiteralPath $p -PathType Leaf)) {
            return ([System.IO.Path]::GetFullPath($p))
        }
    }
    return $null
}

function Copy-CnsMetierTemplatePdfToWorkDir {
    param(
        [Parameter(Mandatory = $true)][string]$TemplateFileName,
        [Parameter(Mandatory = $true)][string]$WorkDir,
        [Parameter(Mandatory = $true)][string]$DestLeafName
    )
    $src = Get-CnsMetierTemplatePdfPath -FileName $TemplateFileName
    if ([string]::IsNullOrWhiteSpace($src)) {
        Write-Warning ("[STEP5-METIER] Template PDF introuvable : {0}" -f $TemplateFileName)
        return $null
    }
    $dest = Join-Path $WorkDir $DestLeafName
    try {
        Copy-Item -LiteralPath $src -Destination $dest -Force -ErrorAction Stop
        return $dest
    }
    catch {
        Write-Warning ("[STEP5-METIER] Copie template {0} echouee : {1}" -f $TemplateFileName, $_.Exception.Message)
        return $null
    }
}

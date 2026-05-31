# Certificat de destruction : template PDF + couche dynamique (texte + Code 128) sans modifier le fichier modele.
# Composition : rendu modele (Ghostscript png16m RGB opaque, evite pngalpha / transparence -> fond noir) + GDI+ sur bitmap 24bpp + JPEG haute qualite + PDF (Ghostscript pdfwrite).

. (Join-Path $PSScriptRoot '..\..\..\Core\GhostscriptResolve.ps1')

function Convert-CdsGhostscriptPathLiteral {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (([System.IO.Path]::GetFullPath($Path)) -replace '\\', '/')
}

function Get-CdsGhostscriptPermitFileReadArgsFallback {
    <#
    .SYNOPSIS
        Equivalent Get-CnsGhostscriptPermitFileReadArgs si PdfTourneeCoverComposer n'est pas charge (tests isoles).
    #>
    param([string[]]$Paths)
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($raw in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        try { $full = [System.IO.Path]::GetFullPath($raw) } catch { continue }
        $dir = Split-Path -Parent $full
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        $lit = Convert-CdsGhostscriptPathLiteral -Path $dir
        if ($seen.Add($lit)) { [void]$out.Add("--permit-file-read=$lit") }
    }
    try {
        $tmpLit = Convert-CdsGhostscriptPathLiteral -Path $env:TEMP
        if ($seen.Add($tmpLit)) { [void]$out.Add("--permit-file-read=$tmpLit") }
    }
    catch { }
    return @( $out.ToArray() )
}

function Write-CdsCertNullCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Step,
        [Parameter(Mandatory = $true)][string]$ObjectName,
        $Ref
    )
    Write-Host '[CERTIF-NULL-CHECK]'
    Write-Host ('Step={0}' -f $Step)
    Write-Host ('Object={0}' -f $ObjectName)
    Write-Host ('IsNull={0}' -f ($null -eq $Ref))
}

function Get-CdsGhostscriptCombinedPermits {
    param([string[]]$Paths)
    if (Get-Command Get-CnsGhostscriptPermitFileReadArgs -ErrorAction SilentlyContinue) {
        return [string[]]@( Get-CnsGhostscriptPermitFileReadArgs -Paths $Paths )
    }
    return [string[]]@( Get-CdsGhostscriptPermitFileReadArgsFallback -Paths $Paths )
}

$script:CdsCode128W6 = @(
    '212222', '222122', '222221', '121223', '121322', '131222', '122213', '122312', '132212', '221213', '221312', '231212',
    '112232', '122132', '122231', '113222', '123122', '123221', '223211', '221132', '221231', '213212', '223112', '312131',
    '311222', '321122', '321221', '312212', '322112', '322211', '212123', '212321', '232121', '111323', '131123', '131321',
    '112313', '132113', '132311', '211313', '231113', '231311', '112133', '112331', '132131', '113123', '113321', '133121',
    '313121', '211331', '231131', '213113', '213311', '213131', '311123', '311321', '331121', '312113', '312311', '332111',
    '314111', '221411', '431111', '111224', '111422', '121124', '121421', '141122', '141221', '112214', '112412', '122114',
    '122411', '142112', '142211', '241211', '221114', '413111', '241112', '134111', '111242', '121142', '121241', '114212',
    '124112', '124211', '411212', '421112', '421211', '212141', '214121', '412121', '111143', '111341', '131141', '114113',
    '114311', '411113', '411311', '113141', '114131', '311141', '411131', '211412', '211214', '211232'
)

# DPI raster unique pour le certificat (spec metier) : px = mm * CdsCertRasterDpi / 25.4
# 192 : equilibre stabilite / nettete ; dimensions metier en mm inchangees.
$script:CdsCertRasterDpi = 192

function Convert-CdsCertMmToPxInt {
    <#
    .SYNOPSIS
        mm -> px : px = Round(mm * CdsCertRasterDpi / 25.4). Origine raster : HAUT-GAUCHE, Y vers le BAS.
    #>
    param([Parameter(Mandatory = $true)][double]$Mm)
    return [int][math]::Round($Mm * $script:CdsCertRasterDpi / 25.4, [MidpointRounding]::AwayFromZero)
}

function Write-CdsCertifDebugBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Element,
        [Parameter(Mandatory = $true)][double]$Xmm,
        [Parameter(Mandatory = $true)][double]$Ymm,
        [Parameter(Mandatory = $true)][int]$Xpx,
        [Parameter(Mandatory = $true)][int]$Ypx,
        [Parameter(Mandatory = $true)][ValidateSet('TEXT', 'IMAGE')][string]$Type
    )
    $ci = [System.Globalization.CultureInfo]::InvariantCulture
    Write-Host '[CERTIF-DEBUG]'
    Write-Host ('Element = {0}' -f $Element)
    Write-Host ('Xmm = {0}' -f $Xmm.ToString($ci))
    Write-Host ('Ymm = {0}' -f $Ymm.ToString($ci))
    Write-Host ('Xpx = {0}' -f $Xpx)
    Write-Host ('Ypx = {0}' -f $Ypx)
    Write-Host ('Type = {0}' -f $Type)
    Write-Host ('DPI = {0}' -f $script:CdsCertRasterDpi)
}

function Get-CdsCertFontAscentPx {
    <#
    .SYNOPSIS
        Hauteur (px) du cell ascent pour DrawString : aligne la baseline du layout (spec) sur le repere Y GDI+.
    #>
    param(
        [Parameter(Mandatory = $true)][System.Drawing.Font]$Font,
        [Parameter(Mandatory = $true)][System.Drawing.Graphics]$Graphics
    )
    $fam = $Font.FontFamily
    $st = $Font.Style
    $designAscent = [float]$fam.GetCellAscent($st)
    $em = [float]$fam.GetEmHeight($st)
    if ($em -lt 1.0) { $em = 1.0 }
    [double]$ratio = [double]$designAscent / [double]$em
    return [double]$Font.SizeInPoints * $ratio * ($Graphics.DpiY / 72.0)
}

function Get-CdsCertDrawStringTopPxFromBaselineLayoutMm {
    <#
    .SYNOPSIS
        Coordonnee Y (px, haut-gauche) pour DrawString lorsque Ymm du layout est la baseline du texte.
        Forme metier : Yfinal_mm = Ymm + baselineOffsetMm avec baselineOffsetMm = -(ascentPx * 25.4 / DPI).
    #>
    param(
        [Parameter(Mandatory = $true)][double]$BaselineLayoutYmm,
        [Parameter(Mandatory = $true)][System.Drawing.Font]$Font,
        [Parameter(Mandatory = $true)][System.Drawing.Graphics]$Graphics
    )
    [int]$yBaselinePx = Convert-CdsCertMmToPxInt -Mm $BaselineLayoutYmm
    [double]$ascentPx = Get-CdsCertFontAscentPx -Font $Font -Graphics $Graphics
    return [int][math]::Round([double]$yBaselinePx - $ascentPx, [MidpointRounding]::AwayFromZero)
}

function Write-CdsCertifLayoutLog {
    param(
        [Parameter(Mandatory = $true)][string]$Element,
        [Parameter(Mandatory = $true)][ValidateSet('TEXT', 'BARCODE')][string]$Type,
        [Parameter(Mandatory = $true)][double]$Xmm,
        [Parameter(Mandatory = $true)][double]$Ymm,
        [Parameter(Mandatory = $true)][int]$Xpx,
        [Parameter(Mandatory = $true)][int]$Ypx,
        [Parameter(Mandatory = $true)][ValidateSet('NONE', 'TOO_LOW', 'TOO_BIG')][string]$Issue
    )
    $ci = [System.Globalization.CultureInfo]::InvariantCulture
    Write-Host '[CERTIF-LAYOUT]'
    Write-Host ('Element = {0}' -f $Element)
    Write-Host ('Type = {0}' -f $Type)
    Write-Host ('Xmm = {0}' -f $Xmm.ToString($ci))
    Write-Host ('Ymm = {0}' -f $Ymm.ToString($ci))
    Write-Host ('Xpx = {0}' -f $Xpx)
    Write-Host ('Ypx = {0}' -f $Ypx)
    Write-Host ('Issue = {0}' -f $Issue)
}

function Test-CdsCertRectOverlap {
    param(
        [Parameter(Mandatory = $true)][hashtable]$A,
        [Parameter(Mandatory = $true)][hashtable]$B
    )
    [double]$ax1 = [double]$A['Xmm']
    [double]$ay1 = [double]$A['Ymm']
    [double]$ax2 = $ax1 + [double]$A['Wmm']
    [double]$ay2 = $ay1 + [double]$A['Hmm']
    [double]$bx1 = [double]$B['Xmm']
    [double]$by1 = [double]$B['Ymm']
    [double]$bx2 = $bx1 + [double]$B['Wmm']
    [double]$by2 = $by1 + [double]$B['Hmm']
    return (($ax1 -lt $bx2) -and ($ax2 -gt $bx1) -and ($ay1 -lt $by2) -and ($ay2 -gt $by1))
}

function Write-CdsCertTopZoneAudit {
    <#
    .SYNOPSIS
        Audit local de la zone haute : titre (zone reservee), code-barres, WorkOrder.
    #>
    param(
        [Parameter(Mandatory = $true)][hashtable]$BarcodeRectMm,
        [Parameter(Mandatory = $true)][hashtable]$WorkOrderRectMm,
        [double]$TitleReservedBottomMm = 10.5,
        [double]$MinVerticalGapMm = 2.0
    )
    $ci = [System.Globalization.CultureInfo]::InvariantCulture
    [double]$barcodeBottom = [double]$BarcodeRectMm['Ymm'] + [double]$BarcodeRectMm['Hmm']
    [double]$woTop = [double]$WorkOrderRectMm['Ymm']
    [double]$gapBarcodeToWo = $woTop - $barcodeBottom
    [double]$gapTitleToBarcode = [double]$BarcodeRectMm['Ymm'] - $TitleReservedBottomMm
    [bool]$overlapBarcodeWo = Test-CdsCertRectOverlap -A $BarcodeRectMm -B $WorkOrderRectMm
    [bool]$titlePressure = $gapTitleToBarcode -lt $MinVerticalGapMm

    Write-Host '[CERTIF-AUDIT-TOP-ZONE]'
    Write-Host ('TitleReservedBottomMm = {0}' -f $TitleReservedBottomMm.ToString($ci))
    Write-Host ('BarcodeTopMm = {0}' -f ([double]$BarcodeRectMm['Ymm']).ToString($ci))
    Write-Host ('BarcodeBottomMm = {0}' -f $barcodeBottom.ToString($ci))
    Write-Host ('WorkOrderTopMm = {0}' -f $woTop.ToString($ci))
    Write-Host ('GapTitleToBarcodeMm = {0}' -f $gapTitleToBarcode.ToString($ci))
    Write-Host ('GapBarcodeToWorkOrderMm = {0}' -f $gapBarcodeToWo.ToString($ci))
    Write-Host ('OverlapBarcodeWorkOrder = {0}' -f $overlapBarcodeWo)
    Write-Host ('TitleZoneTooClose = {0}' -f $titlePressure)

    if ($overlapBarcodeWo -or ($gapBarcodeToWo -lt $MinVerticalGapMm) -or $titlePressure) {
        Write-Warning '[DEST-CERT] Audit top-zone: espacement potentiellement insuffisant (titre / barcode / WorkOrder).'
    }
}

function Test-CdsCertSingleMmValue {
    param(
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)][double]$Mm
    )
    if ([double]::IsNaN($Mm) -or [double]::IsInfinity($Mm)) {
        throw "[DEST-CERT] $Context : valeur mm non finie."
    }
    $s = $Mm.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    if ($s.IndexOf(',') -ge 0) {
        throw "[DEST-CERT] $Context : separateur decimal interdit (virgule) dans la representation."
    }
}

function Test-CdsDestructionCertificateLayoutSpec {
    <#
    .SYNOPSIS
        Verifie cohérence des coordonnees metier avant rendu (mm, point decimal, valeurs finies).
    #>
    param([Parameter(Mandatory = $true)][hashtable]$Layout)
    foreach ($pair in $Layout.GetEnumerator()) {
        if ($pair.Key -isnot [string]) { continue }
        $hl = $pair.Value
        if ($hl -isnot [hashtable]) { continue }
        foreach ($axis in @('Xmm', 'Ymm', 'Wmm', 'Hmm')) {
            if (-not $hl.ContainsKey($axis)) { continue }
            [string]$lbl = '{0}.{1}' -f $pair.Key, $axis
            Test-CdsCertSingleMmValue -Context $lbl -Mm ([double]$hl[$axis])
        }
    }
    $allowedKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    [void]$allowedKeys.Add('Xmm'); [void]$allowedKeys.Add('Ymm'); [void]$allowedKeys.Add('Wmm'); [void]$allowedKeys.Add('Hmm')
    foreach ($pair in $Layout.GetEnumerator()) {
        $hl = $pair.Value
        if ($hl -isnot [hashtable]) { continue }
        foreach ($k in $hl.Keys) {
            if (-not $allowedKeys.Contains([string]$k)) {
                throw "[DEST-CERT] Cle layout inconnue '$k' (conversions multiples / spec suspecte)."
            }
        }
    }
}

function Get-CdsDestructionCertificateTemplatePath {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    return (Join-Path $repoRoot 'templates\CertificatDeDestruction.pdf')
}

function Get-CdsDestructionCertificateTemplateAcroFormDiag {
    <#
    .SYNOPSIS
        Inspection legere du PDF template (scan ASCII du fichier) : /AcroForm, annotations Widget, noms /T(...).
        Limites : flux compresse (filtre FlateDecode) => chaines absentes en clair -> faux negatif possible.
    #>
    param([Parameter(Mandatory = $true)][string]$LiteralPdfPath)
    $out = [ordered]@{
        HasAcroFormFields = $false
        FieldList         = ''
        HasAcroFormKey    = $false
        HasWidgetLike     = $false
        FieldNames        = [string[]]@()
    }
    try {
        if (-not (Test-Path -LiteralPath $LiteralPdfPath)) {
            $out.FieldList = '<fichier_introuvable>'
            return [pscustomobject]$out
        }
        $bytes = [System.IO.File]::ReadAllBytes($LiteralPdfPath)
        if ($bytes.Length -lt 32) {
            $out.FieldList = '<fichier_trop_petit>'
            return [pscustomobject]$out
        }
        $ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
        $latin = ''
        try { $latin = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes) } catch { $latin = $ascii }

        $out.HasAcroFormKey = (($ascii.IndexOf('/AcroForm', [System.StringComparison]::Ordinal) -ge 0) -or
            ($latin.IndexOf('/AcroForm', [System.StringComparison]::Ordinal) -ge 0))

        # Champs widgets : Subtype /Widget ou cle fonctionnelle courante /FT
        foreach ($hay in @($ascii, $latin)) {
            if ([string]::IsNullOrWhiteSpace($hay)) { continue }
            if (($hay.IndexOf('/Widget', [System.StringComparison]::Ordinal) -ge 0) -or
                ($hay.IndexOf('/FT', [System.StringComparison]::Ordinal) -ge 0)) {
                $out.HasWidgetLike = $true
                break
            }
        }

        $names = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
        $rx = [regex]::new('\x2F\s*T\s*\(([^\)\x00-\x08]{1,200})\)')
        foreach ($hay in @($ascii, $latin)) {
            if ([string]::IsNullOrWhiteSpace($hay)) { continue }
            foreach ($m in $rx.Matches($hay)) {
                try {
                    $raw = ([string]$m.Groups[1].Value).Trim()
                    $raw = $raw -replace '^\s*\xFE\xFF', '' # BOM UTF-16 rare
                    if ($raw.Length -gt 0 -and $names.Add($raw)) { }
                }
                catch { }
            }
        }
        $out.FieldNames = [string[]]@($names | Sort-Object)
        [string]$joined = (($out.FieldNames | Select-Object -First 40) -join ', ')
        if ([string]::IsNullOrWhiteSpace($joined)) {
            $joined = if (-not $out.HasAcroFormKey) {
                '(aucun_motif_plaintext;_flux_probablement_compresses)'
            }
            else { '(detecte_structure_forme;_noms_T_non_visibles_en_clair)' }
        }
        elseif ($joined.Length -gt 900) {
            $joined = $joined.Substring(0, 897) + '...'
        }
        $out.FieldList = $joined

        # AcroForm declare + (widget fonctionnel OU noms trouves par regex)
        $out.HasAcroFormFields = ($out.HasAcroFormKey -and ($out.HasWidgetLike -or (@($out.FieldNames).Count -gt 0)))

        # Si pas de cle /AcroForm mais des /T(, rester prudent : faux positifs annexes PDF
        if (-not $out.HasAcroFormKey -and @($out.FieldNames).Count -gt 0) {
            $out.HasAcroFormFields = $false
        }

        return [pscustomobject]$out
    }
    catch {
        $out.FieldList = ('<erreur_lecture> {0}' -f $_.Exception.Message)
        return [pscustomobject]$out
    }
}

function Build-CdsCode128BSequence {
    <#
    .SYNOPSIS
        Symboles Code 128 subset B : [Start B] + donnees + checksum (sans stop 13 modules).
        Checksum ISO : StartB + sum(poids[i] * valeur[i]), poids 1..n sur les caracteres donnees.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )
    if ($null -eq $Text) { $Text = '' }
    [string]$t = ([string]$Text).Trim()
    if ($t.Length -lt 1) { return @([int[]]@()) }

    [int]$startB = 104
    [int64]$sum = $startB
    $codes = New-Object System.Collections.Generic.List[int]
    [void]$codes.Add($startB)
    [int]$weight = 1
    foreach ($ch in $t.ToCharArray()) {
        [int]$oc = [int][char]$ch
        if ($oc -lt 32 -or $oc -gt 126) {
            $oc = 63
        }
        [int]$v = $oc - 32
        [void]$codes.Add($v)
        $sum += $weight * $v
        $weight++
    }
    [int]$chk = [int]($sum % 103)
    [void]$codes.Add($chk)
    return @($codes.ToArray())
}

function Get-CdsCode128PatternInts {
    param([Parameter(Mandatory = $true)][int]$Symbol)
    if ($Symbol -lt 0 -or $Symbol -gt 105) {
        throw ("Code128 : symbole {0} hors plage 0-105." -f $Symbol)
    }
    $s = [string]$script:CdsCode128W6[$Symbol]
    $out = New-Object int[] ($s.Length)
    for ($i = 0; $i -lt $s.Length; $i++) {
        $out[$i] = [int]::Parse($s.Substring($i, 1), [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return $out
}

function Measure-CdsCode128TotalModules {
    param([Parameter(Mandatory = $true)][int[]]$SequenceSansStop)
    $n = @($SequenceSansStop).Count
    if ($n -lt 1) { return 0 }
    return (11 * $n) + 13
}

function Draw-CdsCode128BlackOnBitmap {
    <#
    .SYNOPSIS
        Code 128 bandes : largeur totale = BarcodeBoxWidthPx (modules repartis, arrondi cumule), hauteur = HeightPx.
        Rendu direct dans la cible, sans bitmap intermediaire 1 module = 1 px.
    #>
    param(
        [Parameter(Mandatory = $true)]$Graphics,
        [Parameter(Mandatory = $true)][int]$LeftPx,
        [Parameter(Mandatory = $true)][int]$TopPx,
        [Parameter(Mandatory = $true)][int]$HeightPx,
        [Parameter(Mandatory = $true)][int]$BarcodeBoxWidthPx,
        [Parameter(Mandatory = $true)][string]$Data
    )
    $seq = Build-CdsCode128BSequence -Text $Data
    if ($seq.Count -lt 2) { return }
    $totalMods = Measure-CdsCode128TotalModules -SequenceSansStop $seq
    if ($totalMods -lt 1) { return }
    if ($BarcodeBoxWidthPx -lt 2) { return }

    $stripes = New-Object System.Collections.Generic.List[object]
    foreach ($sym in @($seq)) {
        [int]$s = [int]$sym
        $widths = Get-CdsCode128PatternInts -Symbol $s
        $barTurn = $true
        foreach ($w in @($widths)) {
            [void]$stripes.Add(@([int]$w, [bool]$barTurn))
            $barTurn = -not $barTurn
        }
    }
    $stopStripes = @(
        @(2, $true), @(3, $false), @(3, $true), @(1, $false), @(1, $true), @(1, $false), @(2, $true)
    )
    foreach ($st0 in @($stopStripes)) {
        [void]$stripes.Add(@([int]$st0[0], [bool]$st0[1]))
    }

    [double]$modulePx = [double]$BarcodeBoxWidthPx / [double]$totalMods
    if ($modulePx -lt 0.15) {
        Write-Warning ('[DEST-CERT] Code128 : largeur modules trop petite (modulePx={0:N4}).' -f $modulePx)
    }

    $Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor

    [double]$acc = 0.0
    [int]$x0 = $LeftPx
    [int]$maxR = $LeftPx + $BarcodeBoxWidthPx
    foreach ($st in $stripes) {
        [int]$w = [int]$st[0]
        $isBar = [bool]$st[1]
        $acc += [double]$w * $modulePx
        [int]$x1 = [int][math]::Round([double]$LeftPx + $acc, [MidpointRounding]::AwayFromZero)
        if ($x1 -gt $maxR) { $x1 = $maxR }
        if ($x1 -lt $x0) { $x1 = $x0 }
        [int]$wPx = $x1 - $x0
        if ($isBar -and $wPx -gt 0) {
            $Graphics.FillRectangle([System.Drawing.Brushes]::Black, [single]$x0, [float]$TopPx, [single]$wPx, [float]$HeightPx)
        }
        $x0 = $x1
    }
}

function Draw-CdsCode128ToDestinationRectangle {
    <#
    .SYNOPSIS
        Code 128 : trace direct dans le rectangle destination (largeur x hauteur en px = spec mm au DPI certificat).
        ResetTransform + PageUnit Pixel pour eviter toute mise a l'echelle implicite GDI+ sur le Graphics.
    #>
    param(
        [Parameter(Mandatory = $true)]$TargetGraphics,
        [Parameter(Mandatory = $true)][int]$DestLeftPx,
        [Parameter(Mandatory = $true)][int]$DestTopPx,
        [Parameter(Mandatory = $true)][int]$DestWidthPx,
        [Parameter(Mandatory = $true)][int]$DestHeightPx,
        [Parameter(Mandatory = $true)][string]$Data,
        [Parameter(Mandatory = $true)][double]$Xmm,
        [Parameter(Mandatory = $true)][double]$Ymm,
        [Parameter(Mandatory = $true)][double]$WidthMm,
        [Parameter(Mandatory = $true)][double]$HeightMm
    )
    $seq = Build-CdsCode128BSequence -Text $Data
    if ($seq.Count -lt 2) {
        Write-Warning '[DEST-CERT] Code128 : donnees insuffisantes pour le code-barres.'
        return
    }

    [int]$hPx = [math]::Max(1, $DestHeightPx)
    $gState = $TargetGraphics.Save()
    try {
        $TargetGraphics.ResetTransform()
        $TargetGraphics.PageUnit = [System.Drawing.GraphicsUnit]::Pixel
        $clipR = [System.Drawing.Rectangle]::new($DestLeftPx, $DestTopPx, $DestWidthPx, $hPx)
        $TargetGraphics.SetClip($clipR, [System.Drawing.Drawing2D.CombineMode]::Intersect)
        Draw-CdsCode128BlackOnBitmap -Graphics $TargetGraphics -LeftPx $DestLeftPx -TopPx $DestTopPx -HeightPx $hPx -BarcodeBoxWidthPx $DestWidthPx -Data $Data
    }
    finally {
        $TargetGraphics.Restore($gState)
    }

    $ci = [System.Globalization.CultureInfo]::InvariantCulture
    Write-Host '[CERTIF-BARCODE]'
    Write-Host 'RenderMode = DIRECT'
    Write-Host ('Xmm = {0}; Ymm = {1}' -f $Xmm.ToString($ci), $Ymm.ToString($ci))
    Write-Host ('WidthMm = {0}; HeightMm = {1}' -f $WidthMm.ToString($ci), $HeightMm.ToString($ci))
    Write-Host ('Xpx = {0}; Ypx = {1}' -f $DestLeftPx, $DestTopPx)
    Write-Host ('WidthPx = {0}; HeightPx = {1}' -f $DestWidthPx, $hPx)
}

function Resolve-CdsPoppinsOrFallbackFont {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Semibold','Regular')]
        [string]$Variant,
        [Parameter(Mandatory = $true)][float]$SizePt
    )
    $candidates = if ($Variant -eq 'Semibold') {
        @(
            @{ Path = Join-Path ${env:USERPROFILE} 'Downloads\Poppins-SemiBold.ttf'; Name = 'Poppins SemiBold' }
            @{ Path = "${env:LOCALAPPDATA}\Microsoft\Windows\Fonts\poppins-semibold.ttf"; Name = $null }
            @{ Path = Join-Path ${env:WINDIR} 'Fonts\poppins-semibold.ttf'; Name = $null }
        )
    }
    else {
        @(
            @{ Path = Join-Path ${env:USERPROFILE} 'Downloads\Poppins-Regular.ttf'; Name = 'Poppins Regular' }
            @{ Path = "${env:LOCALAPPDATA}\Microsoft\Windows\Fonts\poppins-regular.ttf"; Name = $null }
            @{ Path = Join-Path ${env:WINDIR} 'Fonts\poppins-regular.ttf'; Name = $null }
        )
    }

    foreach ($c in @($candidates)) {
        try {
            if (-not [string]::IsNullOrWhiteSpace($c.Path) -and (Test-Path -LiteralPath $c.Path)) {
                [void][System.Reflection.Assembly]::LoadWithPartialName('System.Drawing')
                $col = New-Object System.Drawing.Text.PrivateFontCollection
                $col.AddFontFile($c.Path)
                if ($null -eq $col.Families -or $col.Families.Length -lt 1) {
                    continue
                }
                $fam = $col.Families[0]
                $style = if ($Variant -eq 'Semibold') { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
                return [System.Drawing.Font]::new($fam, $SizePt, $style, [System.Drawing.GraphicsUnit]::Point)
            }
        }
        catch { }
    }

    $fallback = if ($Variant -eq 'Semibold') { 'Segoe UI' } else { 'Segoe UI' }
    $style2 = if ($Variant -eq 'Semibold') { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    return [System.Drawing.Font]::new([string]$fallback, $SizePt, $style2, [System.Drawing.GraphicsUnit]::Point)
}

function Format-CdsCertificateVisitDate {
    param(
        [AllowNull()] $VisitDate,
        [AllowNull()][AllowEmptyString()][string]$FallbackDdMmYyyy = ''
    )
    if ($null -ne $VisitDate -and $VisitDate -is [datetime]) {
        try {
            return ([datetime]$VisitDate).ToString('dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
        }
        catch { }
    }
    try {
        if ($null -ne $VisitDate) {
            $dt = [datetime]$VisitDate
            return $dt.ToString('dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
        }
    }
    catch { }
    [string]$f = if ($null -eq $FallbackDdMmYyyy) { '' } else { ([string]$FallbackDdMmYyyy).Trim() }
    return $f
}

function Format-CdsCertificateClientNameDisplay {
    <#
    .SYNOPSIS
        Reconstruit un nom client multi-ligne dans l'ordre naturel des lignes
        puis ajoute " - N° <ClientId>" si l'identifiant est present.
    #>
    param(
        [AllowNull()][AllowEmptyString()][string]$ClientName = '',
        [AllowNull()][AllowEmptyString()][string]$ClientId = ''
    )

    [string]$rawName = if ($null -eq $ClientName) { '' } else { [string]$ClientName }
    [string]$rawId = if ($null -eq $ClientId) { '' } else { ([string]$ClientId).Trim() }

    # Normalise ligne par ligne (ordre vertical conserve par la sequence des lignes),
    # et conserve l'ordre des morceaux dans chaque ligne.
    $normalizedLines = @(
        $rawName -split '\r?\n' |
            ForEach-Object { ([string]$_ -replace '\s+', ' ').Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    [string]$nameDisplay = ($normalizedLines -join ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($nameDisplay)) { return '' }
    if ([string]::IsNullOrWhiteSpace($rawId)) { return $nameDisplay }
    return ('{0} - N° {1}' -f $nameDisplay, $rawId)
}

function Invoke-CdsGhostscriptRasterizePdfFirstPageToPng {
    <#
    .NOTES
        png16m = PNG 24 bits RGB sans canal alpha (contrairement a pngalpha : transparence mal gerée -> fond noir / halos).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$PdfPath,
        [Parameter(Mandatory = $true)][string]$OutPngPath,
        [ValidateRange(72,600)][int]$Dpi = 200
    )
    $gs = Get-ResolvedGhostscriptPath
    if (-not $gs) {
        Write-Warning '[DEST-CERT] Ghostscript introuvable.'
        return $false
    }
    $pdfAbs = (Resolve-Path -LiteralPath $PdfPath).Path
    $pngAbs = [System.IO.Path]::GetFullPath($OutPngPath)
    try {
        $al = New-Object System.Collections.Generic.List[string]
        [void]$al.AddRange([string[]]@(
                '-dNOPAUSE', '-dBATCH', '-sDEVICE=png16m',
                '-dUseCropBox=false',
                '-dPrinted=true',
                '-dTextAlphaBits=4',
                '-dGraphicsAlphaBits=4',
                ("-r$Dpi"), '-dFirstPage=1', '-dLastPage=1', ("-sOutputFile=$pngAbs")
            ))
        [void]$al.AddRange([string[]](Get-CdsGhostscriptCombinedPermits -Paths @($pdfAbs, $pngAbs)))
        [void]$al.Add($pdfAbs)
        $null = & $gs @($al.ToArray()) 2>&1
        return (($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $pngAbs))
    }
    catch {
        return $false
    }
}

function Get-CdsGhostscriptInstallationLibDirectory {
    param([Parameter(Mandatory = $true)][string]$GhostscriptExePath)
    $binDir = Split-Path -Path $GhostscriptExePath -Parent
    return (Join-Path (Split-Path -Path $binDir -Parent) 'lib')
}

function Invoke-CdsGhostscriptRasterImageToSinglePagePdf {
    <#
    .SYNOPSIS
        JPEG -> une page PDF via lib/viewjpeg.ps (pdfwrite avec -f fichier image echoue avec PDF24 10.05).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$RasterImagePath,
        [Parameter(Mandatory = $true)][string]$OutPdfPath,
        [Parameter(Mandatory = $true)][double]$PageWidthPt,
        [Parameter(Mandatory = $true)][double]$PageHeightPt
    )
    $gs = Get-ResolvedGhostscriptPath
    if (-not $gs) { return $false }
    $imgAbs = [System.IO.Path]::GetFullPath($RasterImagePath)
    $pdfAbs = [System.IO.Path]::GetFullPath($OutPdfPath)
    if (-not (Test-Path -LiteralPath $imgAbs)) { return $false }
    $imgExt = [System.IO.Path]::GetExtension($imgAbs)
    if (-not ($imgExt -match '^\.(jpe?g)$')) {
        Write-Warning "[DEST-CERT] Seul le JPEG est pris en charge pour l'emission PDF (fichier=$imgAbs)."
        return $false
    }

    $wi = [int][math]::Round($PageWidthPt, [MidpointRounding]::AwayFromZero)
    $hi = [int][math]::Round($PageHeightPt, [MidpointRounding]::AwayFromZero)

    $libRoot = Get-CdsGhostscriptInstallationLibDirectory -GhostscriptExePath $gs
    $viewJpegPs = Join-Path $libRoot 'viewjpeg.ps'
    if (-not (Test-Path -LiteralPath $viewJpegPs)) {
        Write-Warning "[DEST-CERT] viewjpeg.ps introuvable : $viewJpegPs"
        return $false
    }

    $imgFwd = Convert-CdsGhostscriptPathLiteral -Path $imgAbs
    $cmd = ("<< /PageSize [{0} {1}] >> setpagedevice ({2}) viewJPEG showpage" -f $wi, $hi, $imgFwd)

    $arg = New-Object System.Collections.Generic.List[string]
    [void]$arg.AddRange([string[]]@(
            '-dNOPAUSE', '-dBATCH', '-sDEVICE=pdfwrite',
            '-dFIXEDMEDIA',
            '-dCompatibilityLevel=1.7',
            ("-sOutputFile=$pdfAbs")
        ))
    if (Get-Command Get-CnsCoverPdfwriteQualityArgs -ErrorAction SilentlyContinue) {
        [void]$arg.AddRange([string[]](Get-CnsCoverPdfwriteQualityArgs))
    }
    [void]$arg.AddRange([string[]](Get-CdsGhostscriptCombinedPermits -Paths @($imgAbs, $pdfAbs, $libRoot, $viewJpegPs)))
    [void]$arg.Add($viewJpegPs)
    [void]$arg.Add('-c')
    [void]$arg.Add($cmd)
    try {
        $null = & $gs @($arg.ToArray()) 2>&1
        return (($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $pdfAbs))
    }
    catch { return $false }
}

function New-DestructionCertificate {
    <#
    .SYNOPSIS
        Certificat de destruction : raster + overlay. Repere unique : HAUT-GAUCHE, X vers la droite, Y vers le BAS (mm).
        Conversion unique : px = Round(mm * CdsCertRasterDpi / 25.4). Pas d'inversion PDF, pas de centiemes de mm.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutPdfPath,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$WorkOrder,
        [AllowEmptyString()]
        [string]$ClientName = '',
        [AllowEmptyString()]
        [string]$ClientId = '',
        [AllowEmptyString()]
        [string]$Street = '',
        [AllowEmptyString()]
        [string]$PostalCode = '',
        [AllowEmptyString()]
        [string]$City = '',
        [AllowNull()]
        $VisitDate,
        [AllowEmptyString()]
        [string]$VisitDateFallbackDdMmYyyy = '',
        [AllowEmptyString()]
        [string]$Vehicle = '',
        [string]$TemplatePdfPath,
        [ValidateRange(72, 600)]
        [int]$RasterDpi = 192
    )

    Add-Type -AssemblyName System.Drawing -ErrorAction Stop

    [int]$rD = [int]$script:CdsCertRasterDpi
    if ($RasterDpi -ne $rD) {
        Write-Warning ('[DEST-CERT] RasterDpi={0} ignore — spec certificat : raster et mm->px imposent DPI={1}.' -f $RasterDpi, $rD)
    }
    $RasterDpi = $rD

    if ([string]::IsNullOrWhiteSpace($TemplatePdfPath)) {
        $TemplatePdfPath = Get-CdsDestructionCertificateTemplatePath
    }
    if (-not (Test-Path -LiteralPath $TemplatePdfPath)) {
        Write-Warning "[DEST-CERT] Template introuvable : $TemplatePdfPath"
        return $false
    }

    try {
        $tplDiag = Get-CdsDestructionCertificateTemplateAcroFormDiag -LiteralPdfPath ([System.IO.Path]::GetFullPath($TemplatePdfPath))
        Write-Host ('[TEMPLATE] HasAcroFormFields={0}' -f $tplDiag.HasAcroFormFields) -ForegroundColor DarkCyan
        Write-Host ('[TEMPLATE] FieldList={0}' -f $tplDiag.FieldList) -ForegroundColor DarkCyan
    }
    catch { }

    [string]$woRaw = if ($null -eq $WorkOrder) { '' } else { ([string]$WorkOrder).Trim() }
    if ($woRaw.Length -lt 1) {
        Write-Warning '[DEST-CERT] WorkOrder vide — certificat non genere.'
        return $false
    }

    [double]$barcodeOldYmm = 11.8
    [double]$barcodeNewYmm = 14.4
    [double]$workOrderOldYmm = 34.0
    # ~15 px supplementaires vers le bas (meme echelle que le raster courant)
    [double]$workOrderPixelDownMm = 15.0 * 25.4 / [double]$script:CdsCertRasterDpi
    [double]$workOrderNewYmm = $workOrderOldYmm + $workOrderPixelDownMm
    # Libelle fixe template ; valeur prestation (meme WO) sur la meme ligne visuelle, a droite.
    [double]$prestationBesideLabelYmm = 87.67
    [double]$prestationBesideLabelOldYmm = 87.67
    # Ajustement optique leger : libelle et valeur partagent la meme baseline (Y metier identique).
    [double]$prestationBesideLabelNewYmm = $prestationBesideLabelYmm + 0.55

    $certLayout = @{
        Barcode                       = @{ Xmm = 147.5; Ymm = $barcodeNewYmm; Wmm = 47.6; Hmm = 18.3 }
        # WO affiche sous le code-barres (Semibold 9) — seul ce bloc reçoit le decalage vertical demande.
        WorkOrder                     = @{ Xmm = 186.0; Ymm = $workOrderNewYmm }
        ClientName                    = @{ Xmm = 11.75; Ymm = 56.34 }
        Street                        = @{ Xmm = 11.75; Ymm = 62.15 }
        PostalCodeCity                = @{ Xmm = 11.75; Ymm = 66.15 }
        VisitDate                     = @{ Xmm = 43.81; Ymm = 80.77 }
        PapierConfidentiel            = @{ Xmm = 29.79; Ymm = 87.67 }
        Vehicle                       = @{ Xmm = 59.68; Ymm = 105.41 }
    }
    try {
        Test-CdsDestructionCertificateLayoutSpec -Layout $certLayout
    }
    catch {
        Write-Warning ('[DEST-CERT] Validation layout : {0}' -f $_.Exception.Message)
        return $false
    }
    Write-Host '[CERTIF-LAYOUT] Validation des coordonnees mm OK — un seul passage mm->px, separateur decimal point (Culture Invariant).'

    $runGu = [Guid]::NewGuid().ToString('N')
    $tmpPngTpl = Join-Path $env:TEMP ("cn_dest_tpl_{0}.png" -f $runGu)
    $tmpJpgFlat = Join-Path $env:TEMP ("cn_dest_flat_{0}.jpg" -f $runGu)
    $outAbs = [System.IO.Path]::GetFullPath($OutPdfPath)

    try {
        Write-CdsCertNullCheck -Step 'BeforeGhostscriptRasterizeTemplate' -ObjectName 'TemplatePdfPath' -Ref $TemplatePdfPath
        Write-CdsCertNullCheck -Step 'BeforeGhostscriptRasterizeTemplate' -ObjectName 'TmpPngPath' -Ref $tmpPngTpl
        if (-not (Invoke-CdsGhostscriptRasterizePdfFirstPageToPng -PdfPath $TemplatePdfPath -OutPngPath $tmpPngTpl -Dpi $RasterDpi)) {
            return $false
        }

        Write-CdsCertNullCheck -Step 'BeforeBitmapFromPng' -ObjectName 'TmpPngTplExists' -Ref (Test-Path -LiteralPath $tmpPngTpl)
        $srcTpl = [System.Drawing.Bitmap]::FromFile($tmpPngTpl)
        Write-CdsCertNullCheck -Step 'AfterBitmapFromPng' -ObjectName 'srcTpl' -Ref $srcTpl
        $bmpWork = $null
        try {
            [int]$imgW = $srcTpl.Width
            [int]$imgH = $srcTpl.Height
            [double]$pageWpt = $imgW * 72.0 / [double]$RasterDpi
            [double]$pageHpt = $imgH * 72.0 / [double]$RasterDpi
            Write-Host ('[CERTIF-COORD] PageRaster DPI={0} ImgW={1}px ImgH={2}px PageW={3:N2}pt PageH={4:N2}pt Repere=haut_gauche_Y_bas' -f $RasterDpi, $imgW, $imgH, $pageWpt, $pageHpt)
            Write-Host '[CERTIF-RASTER-AUDIT]'
            Write-Host ('PngIntermediateWidthPx={0}' -f $imgW)
            Write-Host ('PngIntermediateHeightPx={0}' -f $imgH)
            Write-Host ('PngIntermediateDpiX={0}' -f ([double]$srcTpl.HorizontalResolution).ToString([System.Globalization.CultureInfo]::InvariantCulture))
            Write-Host ('PngIntermediateDpiY={0}' -f ([double]$srcTpl.VerticalResolution).ToString([System.Globalization.CultureInfo]::InvariantCulture))
            Write-Host ('RasterDpiRequested={0}' -f $RasterDpi)

            $bmpWork = [System.Drawing.Bitmap]::new($imgW, $imgH, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
            Write-CdsCertNullCheck -Step 'AfterBitmapWorkCreate' -ObjectName 'bmpWork' -Ref $bmpWork
            $bmpWork.SetResolution([float]$RasterDpi, [float]$RasterDpi)
            Write-Host ('BitmapFinalWidthPx={0}' -f $bmpWork.Width)
            Write-Host ('BitmapFinalHeightPx={0}' -f $bmpWork.Height)
            Write-Host ('BitmapFinalDpiX={0}' -f ([double]$bmpWork.HorizontalResolution).ToString([System.Globalization.CultureInfo]::InvariantCulture))
            Write-Host ('BitmapFinalDpiY={0}' -f ([double]$bmpWork.VerticalResolution).ToString([System.Globalization.CultureInfo]::InvariantCulture))
            $gBase = [System.Drawing.Graphics]::FromImage($bmpWork)
            try {
                $gBase.Clear([System.Drawing.Color]::White)
                $gBase.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
                $gBase.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $gBase.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $gBase.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $gBase.DrawImage($srcTpl, 0, 0, $imgW, $imgH)
            }
            finally {
                $gBase.Dispose()
            }

            $g = [System.Drawing.Graphics]::FromImage($bmpWork)
            Write-CdsCertNullCheck -Step 'AfterGraphicsFromImage' -ObjectName 'g' -Ref $g
            $g.PageUnit = [System.Drawing.GraphicsUnit]::Pixel
            $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
            $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor

            $blk = [System.Drawing.Brushes]::Black
            $sf = [System.Drawing.StringFormat]::GenericTypographic
            $sf.FormatFlags = $sf.FormatFlags -bor [System.Drawing.StringFormatFlags]::MeasureTrailingSpaces

            $barcodeValue = $woRaw
            $bSpec = $certLayout['Barcode']
            [double]$barYmm = [double]$bSpec['Ymm']
            [double]$barWmm = [double]$bSpec['Wmm']
            [double]$barHmm = [double]$bSpec['Hmm']
            [double]$barXmm = [double]$bSpec['Xmm']
            $ciFix = [System.Globalization.CultureInfo]::InvariantCulture
            Write-Host '[CERTIF-BARCODE-FIX]'
            Write-Host ('Xmm = {0}' -f $barXmm.ToString($ciFix))
            Write-Host ('Ymm = {0}' -f $barYmm.ToString($ciFix))
            Write-Host ('WidthMm = {0}' -f $barWmm.ToString($ciFix))

            [int]$barLeftPx = Convert-CdsCertMmToPxInt -Mm $barXmm
            [int]$barTopPx = Convert-CdsCertMmToPxInt -Mm $barYmm
            [int]$barBoxWidthPx = Convert-CdsCertMmToPxInt -Mm $barWmm
            [int]$barHpx = Convert-CdsCertMmToPxInt -Mm $barHmm
            [int]$barEndXpx = $barLeftPx + $barBoxWidthPx
            [int]$barEndYpx = $barTopPx + $barHpx

            Draw-CdsCode128ToDestinationRectangle `
                -TargetGraphics $g `
                -DestLeftPx $barLeftPx `
                -DestTopPx $barTopPx `
                -DestWidthPx $barBoxWidthPx `
                -DestHeightPx $barHpx `
                -Data $barcodeValue `
                -Xmm $barXmm `
                -Ymm $barYmm `
                -WidthMm $barWmm `
                -HeightMm $barHmm

            $g.ResetTransform()
            $g.PageUnit = [System.Drawing.GraphicsUnit]::Pixel

            Write-CdsCertifLayoutLog -Element 'WorkOrderBarcode' -Type BARCODE -Xmm $barXmm -Ymm $barYmm -Xpx $barLeftPx -Ypx $barTopPx -Issue NONE

            Write-CdsCertifDebugBlock -Element 'WorkOrderBarcode' -Xmm $barXmm -Ymm $barYmm -Xpx $barLeftPx -Ypx $barTopPx -Type IMAGE
            Write-Host '[CERTIF-BARCODE-REAL]'
            Write-Host ('StartXpx={0}' -f $barLeftPx)
            Write-Host ('StartYpx={0}' -f $barTopPx)
            Write-Host ('EndXpx={0}' -f $barEndXpx)
            Write-Host ('EndYpx={0}' -f $barEndYpx)
            Write-Host ('WidthPx={0}' -f $barBoxWidthPx)
            Write-Host ('HeightPx={0}' -f $barHpx)

            $woSpec = $certLayout['WorkOrder']
            $fontWo = Resolve-CdsPoppinsOrFallbackFont -Variant Semibold -SizePt 9.0
            [int]$woXPx = Convert-CdsCertMmToPxInt -Mm ([double]$woSpec['Xmm'])
            [double]$woYmm = [double]$woSpec['Ymm']
            [int]$woBaselineYpx = Convert-CdsCertMmToPxInt -Mm $woYmm
            [int]$woYPx = Get-CdsCertDrawStringTopPxFromBaselineLayoutMm -BaselineLayoutYmm $woYmm -Font $fontWo -Graphics $g
            [int]$woYPxNaive = Convert-CdsCertMmToPxInt -Mm $woYmm
            [double]$woTextHeightPx = [double]$fontWo.GetHeight($g)
            [string]$woLayoutIssue = if ($woYPx -ne $woYPxNaive) { 'TOO_LOW' } else { 'NONE' }
            try {
                $g.DrawString($woRaw, $fontWo, $blk, [float]$woXPx, [float]$woYPx, $sf)
            }
            finally { $fontWo.Dispose() }
            Write-CdsCertifLayoutLog -Element 'WorkOrder' -Type TEXT -Xmm ([double]$woSpec['Xmm']) -Ymm $woYmm -Xpx $woXPx -Ypx $woYPx -Issue $woLayoutIssue
            Write-CdsCertifDebugBlock -Element 'WorkOrder' -Xmm ([double]$woSpec['Xmm']) -Ymm $woYmm -Xpx $woXPx -Ypx $woYPx -Type TEXT
            Write-Host '[CERTIF-WORKORDER-REAL]'
            Write-Host ('Xpx={0}' -f $woXPx)
            Write-Host ('Ypx={0}' -f $woYPx)
            Write-Host ('BaselineYpx={0}' -f $woBaselineYpx)
            Write-Host ('TopDrawYpx={0}' -f $woYPx)
            Write-Host ('TextHeightPx={0}' -f ([double]$woTextHeightPx).ToString([System.Globalization.CultureInfo]::InvariantCulture))

            # Audit visuel local : vérifie collisions potentielles en haut (titre template / code-barres / WorkOrder).
            [double]$woTopAuditMm = [double]$woYPx * 25.4 / [double]$script:CdsCertRasterDpi
            # Approximation suffisante pour audit collision (sans dépendre de l'objet Font libéré).
            [double]$woHeightAuditMm = 4.0
            $barcodeRectMm = @{
                Xmm = $barXmm
                Ymm = $barYmm
                Wmm = $barWmm
                Hmm = $barHmm
            }
            $workOrderRectMm = @{
                Xmm = [double]$woSpec['Xmm']
                Ymm = $woTopAuditMm
                Wmm = 40.0
                Hmm = $woHeightAuditMm
            }
            Write-CdsCertTopZoneAudit -BarcodeRectMm $barcodeRectMm -WorkOrderRectMm $workOrderRectMm -TitleReservedBottomMm 10.5 -MinVerticalGapMm 2.0

            $fontLine975 = Resolve-CdsPoppinsOrFallbackFont -Variant Regular -SizePt 9.75
            try {
                $cn = Format-CdsCertificateClientNameDisplay -ClientName $ClientName -ClientId $ClientId
                $st = if ($null -eq $Street) { '' } else { ([string]$Street).Trim() }
                $cp = if ($null -eq $PostalCode) { '' } else { ([string]$PostalCode).Trim() }
                $ci = if ($null -eq $City) { '' } else { ([string]$City).Trim() }
                [string]$cpCi = ('{0} {1}' -f $cp, $ci).Trim()

                foreach ($row in @(
                        @{ Element = 'ClientName'; SpecKey = 'ClientName'; Text = $cn }
                        @{ Element = 'Street'; SpecKey = 'Street'; Text = $st }
                        @{ Element = 'PostalCodeCity'; SpecKey = 'PostalCodeCity'; Text = $cpCi }
                    )) {
                    if ([string]::IsNullOrWhiteSpace($row.Text)) {
                        Write-Host ('[CERTIF-DEBUG] Element = {0} ; SKIP (valeur vide)' -f $row.Element)
                        continue
                    }
                    $sp = $certLayout[$row.SpecKey]
                    [int]$tx = Convert-CdsCertMmToPxInt -Mm ([double]$sp['Xmm'])
                    [double]$tymm = [double]$sp['Ymm']
                    [int]$ty = Get-CdsCertDrawStringTopPxFromBaselineLayoutMm -BaselineLayoutYmm $tymm -Font $fontLine975 -Graphics $g
                    [int]$tyNaive = Convert-CdsCertMmToPxInt -Mm $tymm
                    [string]$txtIssue = if ($ty -ne $tyNaive) { 'TOO_LOW' } else { 'NONE' }
                    $g.DrawString($row.Text, $fontLine975, $blk, [float]$tx, [float]$ty, $sf)
                    Write-CdsCertifLayoutLog -Element $row.Element -Type TEXT -Xmm ([double]$sp['Xmm']) -Ymm $tymm -Xpx $tx -Ypx $ty -Issue $txtIssue
                    Write-CdsCertifDebugBlock -Element $row.Element -Xmm ([double]$sp['Xmm']) -Ymm $tymm -Xpx $tx -Ypx $ty -Type TEXT
                }
            }
            finally { $fontLine975.Dispose() }

            $vdd = Format-CdsCertificateVisitDate -VisitDate $VisitDate -FallbackDdMmYyyy $VisitDateFallbackDdMmYyyy
            $fontDv = Resolve-CdsPoppinsOrFallbackFont -Variant Regular -SizePt 8.25
            try {
                $vdSpec = $certLayout['VisitDate']
                if (-not [string]::IsNullOrWhiteSpace($vdd)) {
                    [int]$vdX = Convert-CdsCertMmToPxInt -Mm ([double]$vdSpec['Xmm'])
                    [double]$vdYmm = [double]$vdSpec['Ymm']
                    [int]$vdY = Get-CdsCertDrawStringTopPxFromBaselineLayoutMm -BaselineLayoutYmm $vdYmm -Font $fontDv -Graphics $g
                    [int]$vdYNaive = Convert-CdsCertMmToPxInt -Mm $vdYmm
                    [string]$vdIssue = if ($vdY -ne $vdYNaive) { 'TOO_LOW' } else { 'NONE' }
                    $g.DrawString($vdd, $fontDv, $blk, [float]$vdX, [float]$vdY, $sf)
                    Write-CdsCertifLayoutLog -Element 'VisitDate' -Type TEXT -Xmm ([double]$vdSpec['Xmm']) -Ymm $vdYmm -Xpx $vdX -Ypx $vdY -Issue $vdIssue
                    Write-CdsCertifDebugBlock -Element 'VisitDate' -Xmm ([double]$vdSpec['Xmm']) -Ymm $vdYmm -Xpx $vdX -Ypx $vdY -Type TEXT
                }
                else {
                    Write-Host '[CERTIF-DEBUG] Element = VisitDate ; SKIP (valeur vide)'
                }
            }
            finally { $fontDv.Dispose() }

            $fontFx = Resolve-CdsPoppinsOrFallbackFont -Variant Regular -SizePt 8.25
            try {
                $fxSpec = $certLayout['PapierConfidentiel']
                $prestSpec = $certLayout['PrestationPapierConfidentiel']
                $fxText = 'Papier confidentiel'
                [int]$fxX = Convert-CdsCertMmToPxInt -Mm ([double]$fxSpec['Xmm'])
                [double]$fxYmm = [double]$fxSpec['Ymm']
                [int]$fxY = Get-CdsCertDrawStringTopPxFromBaselineLayoutMm -BaselineLayoutYmm $fxYmm -Font $fontFx -Graphics $g
                [int]$fxBaselineY = Convert-CdsCertMmToPxInt -Mm $fxYmm
                [int]$fxYNaive = Convert-CdsCertMmToPxInt -Mm $fxYmm
                [string]$fxIssue = if ($fxY -ne $fxYNaive) { 'TOO_LOW' } else { 'NONE' }
                $g.DrawString($fxText, $fontFx, $blk, [float]$fxX, [float]$fxY, $sf)
                Write-CdsCertifLayoutLog -Element 'ConfidentialLabel' -Type TEXT -Xmm ([double]$fxSpec['Xmm']) -Ymm $fxYmm -Xpx $fxX -Ypx $fxY -Issue $fxIssue
                Write-CdsCertifDebugBlock -Element 'ConfidentialLabel' -Xmm ([double]$fxSpec['Xmm']) -Ymm $fxYmm -Xpx $fxX -Ypx $fxY -Type TEXT
                Write-Host '[CERTIF-PRESTATION-REAL]'
                Write-Host 'FieldName=ConfidentialLabel'
                Write-Host 'SourceVariable=$fxText'
                Write-Host 'LayoutKey=PapierConfidentiel'
                Write-Host ('Xpx={0}' -f $fxX)
                Write-Host ('Ypx={0}' -f $fxY)
                Write-Host ('TopDrawYpx={0}' -f $fxY)
                Write-Host ('BaselineYpx={0}' -f $fxBaselineY)

                # Champ ARTICLE sur la meme ligne que le libelle : meme police / baseline que le libelle.
                [string]$articleText = 'Article'
                [int]$prestX = Convert-CdsCertMmToPxInt -Mm ([double]$prestSpec['Xmm'])
                [double]$prestYmm = [double]$prestSpec['Ymm']
                [int]$prestY = Get-CdsCertDrawStringTopPxFromBaselineLayoutMm -BaselineLayoutYmm $prestYmm -Font $fontFx -Graphics $g
                [int]$prestBaselineY = Convert-CdsCertMmToPxInt -Mm $prestYmm
                $g.DrawString($articleText, $fontFx, $blk, [float]$prestX, [float]$prestY, $sf)
                Write-CdsCertifLayoutLog -Element 'PrestationPapierConfidentiel' -Type TEXT -Xmm ([double]$prestSpec['Xmm']) -Ymm $prestYmm -Xpx $prestX -Ypx $prestY -Issue NONE
                Write-CdsCertifDebugBlock -Element 'PrestationPapierConfidentiel' -Xmm ([double]$prestSpec['Xmm']) -Ymm $prestYmm -Xpx $prestX -Ypx $prestY -Type TEXT
                Write-Host '[CERTIF-PRESTATION-TARGET]'
                Write-Host 'FieldName=PrestationPapierConfidentiel'
                Write-Host 'SourceVariable=$articleText'
                Write-Host 'LayoutKey=PrestationPapierConfidentiel'
                Write-Host ('TextValue={0}' -f $articleText)
                Write-Host ('Xpx={0}' -f $prestX)
                Write-Host ('Ypx={0}' -f $prestY)
                Write-Host ('TopDrawYpx={0}' -f $prestY)
                Write-Host ('BaselineYpx={0}' -f $prestBaselineY)
            }
            finally { $fontFx.Dispose() }

            $fontVeh = Resolve-CdsPoppinsOrFallbackFont -Variant Regular -SizePt 8.25
            try {
                $vh = if ($null -eq $Vehicle) { '' } else { ([string]$Vehicle).Trim() }
                $vSpec = $certLayout['Vehicle']
                if (-not [string]::IsNullOrWhiteSpace($vh)) {
                    [int]$vx = Convert-CdsCertMmToPxInt -Mm ([double]$vSpec['Xmm'])
                    [double]$vYmm = [double]$vSpec['Ymm']
                    [int]$vy = Get-CdsCertDrawStringTopPxFromBaselineLayoutMm -BaselineLayoutYmm $vYmm -Font $fontVeh -Graphics $g
                    [int]$vyNaive = Convert-CdsCertMmToPxInt -Mm $vYmm
                    [string]$vehIssue = if ($vy -ne $vyNaive) { 'TOO_LOW' } else { 'NONE' }
                    $g.DrawString($vh, $fontVeh, $blk, [float]$vx, [float]$vy, $sf)
                    Write-CdsCertifLayoutLog -Element 'Vehicle' -Type TEXT -Xmm ([double]$vSpec['Xmm']) -Ymm $vYmm -Xpx $vx -Ypx $vy -Issue $vehIssue
                    Write-CdsCertifDebugBlock -Element 'Vehicle' -Xmm ([double]$vSpec['Xmm']) -Ymm $vYmm -Xpx $vx -Ypx $vy -Type TEXT
                }
                else {
                    Write-Host '[CERTIF-DEBUG] Element = Vehicle ; SKIP (valeur vide)'
                }
            }
            finally { $fontVeh.Dispose() }

            [int]$expBarW = Convert-CdsCertMmToPxInt -Mm ([double]$bSpec['Wmm'])
            [int]$expBarH = Convert-CdsCertMmToPxInt -Mm ([double]$bSpec['Hmm'])
            [bool]$scalingDetected = ($barBoxWidthPx -ne $expBarW) -or ($barHpx -ne $expBarH)
            [double]$prestationYAfter = [double]$certLayout['PrestationPapierConfidentiel']['Ymm']
            [double]$prestationYBefore = $prestationBesideLabelOldYmm
            [double]$vehiculeYAfter = [double]$certLayout['Vehicle']['Ymm']
            [double]$vehiculeYBefore = $vehiculeYAfter + 1.0
            Write-Host '[CERTIF-FIX]'
            Write-Host ("BarcodeExpectedPx = {0}x{1}" -f $expBarW, $expBarH)
            Write-Host ("BarcodeActualPx = {0}x{1}" -f $barBoxWidthPx, $barHpx)
            Write-Host ("ScalingDetected = {0}" -f $scalingDetected)
            Write-Host ('PrestationYBefore = {0}' -f $prestationYBefore.ToString($ciFix))
            Write-Host ('PrestationYAfter = {0}' -f $prestationYAfter.ToString($ciFix))
            Write-Host ('VehiculeYBefore = {0}' -f $vehiculeYBefore.ToString($ciFix))
            Write-Host ('VehiculeYAfter = {0}' -f $vehiculeYAfter.ToString($ciFix))

            Write-Host '[CERTIF-FINAL-LAYOUT]'
            Write-Host ('BarcodeOldY={0}' -f $barcodeOldYmm.ToString($ciFix))
            Write-Host ('BarcodeNewY={0}' -f $barcodeNewYmm.ToString($ciFix))
            Write-Host ('WorkOrderOldY={0}' -f $workOrderOldYmm.ToString($ciFix))
            Write-Host ('WorkOrderNewY={0}' -f $workOrderNewYmm.ToString($ciFix))
            Write-Host ('PrestationOldY={0}' -f $prestationBesideLabelOldYmm.ToString($ciFix))
            Write-Host ('PrestationNewY={0}' -f $prestationBesideLabelNewYmm.ToString($ciFix))

            [string]$gInterpLog = $g.InterpolationMode.ToString()
            [string]$gSmoothLog = $g.SmoothingMode.ToString()
            [string]$gTextHintLog = $g.TextRenderingHint.ToString()
            $g.Dispose()
            $g = $null

            [long]$jpegQualityUsed = 98
            [string]$jpegQualityLog = ([string]$jpegQualityUsed)
            Write-CdsCertNullCheck -Step 'BeforeJpegEncode' -ObjectName 'bmpWork' -Ref $bmpWork
            $jpegCodec = @([System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' })[0]
            Write-CdsCertNullCheck -Step 'BeforeJpegEncode' -ObjectName 'jpegCodec' -Ref $jpegCodec
            if ($null -eq $jpegCodec) {
                Write-Host '[CERTIF-OUTPUT-AUDIT]'
                Write-Host 'JpegCodecFound=false'
                Write-Host 'JpegQualityUsed=<default-system>'
                $jpegQualityLog = '<default>'
                $bmpWork.Save($tmpJpgFlat, [System.Drawing.Imaging.ImageFormat]::Jpeg)
            }
            else {
                $encParams = New-Object System.Drawing.Imaging.EncoderParameters 1
                $qParam = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality, $jpegQualityUsed)
                try {
                    Write-Host '[CERTIF-OUTPUT-AUDIT]'
                    Write-Host 'JpegCodecFound=true'
                    Write-Host ('JpegQualityUsed={0}' -f $jpegQualityUsed)
                    $encParams.Param[0] = $qParam
                    $bmpWork.Save($tmpJpgFlat, $jpegCodec, $encParams)
                }
                finally {
                    $qParam.Dispose()
                    $encParams.Dispose()
                }
            }
            Write-Host '[CERTIF-QUALITY]'
            Write-Host ('RasterDpi={0}' -f $RasterDpi)
            Write-Host ('BitmapWidth={0}' -f $bmpWork.Width)
            Write-Host ('BitmapHeight={0}' -f $bmpWork.Height)
            Write-Host ('JpegQuality={0}' -f $jpegQualityLog)
            Write-Host ('PdfPageWidthPt={0}' -f ([double]$pageWpt).ToString([System.Globalization.CultureInfo]::InvariantCulture))
            Write-Host ('PdfPageHeightPt={0}' -f ([double]$pageHpt).ToString([System.Globalization.CultureInfo]::InvariantCulture))
            Write-Host '[CERTIF-QUALITY-FINAL]'
            Write-Host ('RasterDpi={0}' -f $RasterDpi)
            Write-Host ('BitmapWidth={0}' -f $bmpWork.Width)
            Write-Host ('BitmapHeight={0}' -f $bmpWork.Height)
            Write-Host 'ImageFormat=JPEG'
            Write-Host ('JpegQuality={0}' -f $jpegQualityLog)
            Write-Host ('InterpolationMode={0}' -f $gInterpLog)
            Write-Host ('SmoothingMode={0}' -f $gSmoothLog)
            Write-Host ('TextRenderingHint={0}' -f $gTextHintLog)
        }
        finally {
            if ($null -ne $bmpWork) {
                $bmpWork.Dispose()
            }
            $srcTpl.Dispose()
        }

        Write-CdsCertNullCheck -Step 'BeforePdfFromJpeg' -ObjectName 'tmpJpgFlat' -Ref $tmpJpgFlat
        Write-CdsCertNullCheck -Step 'BeforePdfFromJpeg' -ObjectName 'JpegExists' -Ref (Test-Path -LiteralPath $tmpJpgFlat)
        Write-CdsCertNullCheck -Step 'BeforePdfFromJpeg' -ObjectName 'pageWpt' -Ref $pageWpt
        Write-CdsCertNullCheck -Step 'BeforePdfFromJpeg' -ObjectName 'pageHpt' -Ref $pageHpt
        [bool]$pdfOk = Invoke-CdsGhostscriptRasterImageToSinglePagePdf -RasterImagePath $tmpJpgFlat -OutPdfPath $outAbs -PageWidthPt $pageWpt -PageHeightPt $pageHpt
        Write-Host '[CERTIF-PDF-REAL]'
        Write-Host ('PdfGenerated={0}' -f $pdfOk)
        Write-Host ('PdfExpectedPageWidthPt={0}' -f ([double]$pageWpt).ToString([System.Globalization.CultureInfo]::InvariantCulture))
        Write-Host ('PdfExpectedPageHeightPt={0}' -f ([double]$pageHpt).ToString([System.Globalization.CultureInfo]::InvariantCulture))
        if ($pdfOk -and (Test-Path -LiteralPath $outAbs)) {
            try {
                $pdfBytes = [System.IO.File]::ReadAllBytes($outAbs)
                $pdfAscii = [System.Text.Encoding]::ASCII.GetString($pdfBytes)
                $mMedia = [regex]::Match($pdfAscii, '/MediaBox\s*\[\s*([0-9\.\-]+)\s+([0-9\.\-]+)\s+([0-9\.\-]+)\s+([0-9\.\-]+)\s*\]')
                if ($mMedia.Success) {
                    Write-Host ('MediaBoxX0={0}' -f $mMedia.Groups[1].Value)
                    Write-Host ('MediaBoxY0={0}' -f $mMedia.Groups[2].Value)
                    Write-Host ('MediaBoxX1={0}' -f $mMedia.Groups[3].Value)
                    Write-Host ('MediaBoxY1={0}' -f $mMedia.Groups[4].Value)
                }
                else {
                    Write-Host 'MediaBox=<not_found_in_plaintext>'
                }
            }
            catch {
                Write-Host ('MediaBox=<read_error:{0}>' -f $_.Exception.Message)
            }
        }
        return $pdfOk
    }
    catch {
        Write-Warning ('[DEST-CERT] Erreur : {0}' -f $_.Exception.Message)
        return $false
    }
    finally {
        Remove-Item -LiteralPath $tmpPngTpl -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tmpJpgFlat -Force -ErrorAction SilentlyContinue
    }
}

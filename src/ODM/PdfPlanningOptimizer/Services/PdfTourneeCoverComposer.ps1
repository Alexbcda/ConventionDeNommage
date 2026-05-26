# Composition PDF : pages de garde globale + par tournée, puis concat avec le PDF principal
# (sans modifier Reorganiser-PDF ni le matching / reorder / sequence GS).

. (Join-Path $PSScriptRoot '..\..\..\Core\GhostscriptResolve.ps1')
. (Join-Path $PSScriptRoot 'PlanningExcelTourneeSegments.ps1')
. (Join-Path $PSScriptRoot 'CnsPdfMetierPrestation.ps1')
. (Join-Path $PSScriptRoot 'CnsPdfStructureMerge.ps1')
$_cnsDestructionWord = Join-Path $PSScriptRoot 'CnsDestructionCertificateWord.ps1'
if (Test-Path -LiteralPath $_cnsDestructionWord) {
    . $_cnsDestructionWord
}
$_cnsBilanCollecteWord = Join-Path $PSScriptRoot 'CnsBilanCollecteWord.ps1'
if (Test-Path -LiteralPath $_cnsBilanCollecteWord) {
    . $_cnsBilanCollecteWord
}
$_cnsCeaPointsWord = Join-Path $PSScriptRoot 'CnsCeaPointsCollecteWord.ps1'
if (Test-Path -LiteralPath $_cnsCeaPointsWord) {
    . $_cnsCeaPointsWord
}

function Sanitize-CnsCoverTextForGhostscript {
    <#
    .SYNOPSIS
        Apres NormalizeText : retire caracteres de contrôle et paires de substitution (stabilité pdfwrite).
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { return '' }
    $t = if (Get-Command NormalizeText -ErrorAction SilentlyContinue) {
        NormalizeText -TextIn $Text
    }
    else {
        ([string]$Text).Trim().Normalize([System.Text.NormalizationForm]::FormC)
    }
    $sb = [System.Text.StringBuilder]::new()
    $chars = $t.ToCharArray()
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $ch = $chars[$i]
        if ([char]::IsSurrogate($ch)) {
            if ($i + 1 -lt $chars.Length -and [char]::IsSurrogatePair($ch, $chars[$i + 1])) { $i++ }
            continue
        }
        [int]$oc = [int][char]$ch
        if ($oc -lt 32 -and $oc -notin @(9, 10, 13)) { continue }
        if ($oc -eq 0xFFFE -or $oc -eq 0xFFFF) { continue }
        [void]$sb.Append($ch)
    }
    return $sb.ToString().Trim()
}

function Convert-CnsFilesystemPathToGhostscriptPathLiteral {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (([System.IO.Path]::GetFullPath($Path)) -replace '\\', '/')
}

function ConvertTo-CnsPsHelveticaParenBody {
    <#
    .SYNOPSIS
        Corps d'une chaine PostScript entre parentheses pour Helvetica (WinAnsi/Latin-1 safe : ASCII + deaccentuation).
        Echappe \, (, ). Le signe ° (U+00B0) est emis en \260 (WinAnsi).
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $t = Sanitize-CnsCoverTextForGhostscript -Text $Text
    if (Get-Command Repair-CnsClientNumeroSignText -ErrorAction SilentlyContinue) {
        $t = Repair-CnsClientNumeroSignText -Text $t
    }
    if ([string]::IsNullOrEmpty($t)) { return '' }
    $d = $t.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $d.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -eq [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            continue
        }
        [int]$o = [int][char]$ch
        if ($o -lt 32) { continue }
        if ($o -eq 0x2019 -or $o -eq 0x2018) {
            [void]$sb.Append("'")
            continue
        }
        if ($o -eq 0x00B0 -or $o -eq 0x00BA) {
            [void]$sb.Append('\260')
            continue
        }
        if ($o -ge 32 -and $o -le 126) {
            if ($ch -eq '\' -or $ch -eq '(' -or $ch -eq ')') { [void]$sb.Append('\') }
            [void]$sb.Append($ch)
            continue
        }
        [void]$sb.Append('?')
    }
    return $sb.ToString()
}

function Get-CnsGhostscriptPermitFileReadArgs {
    <#
    .SYNOPSIS
        Repertoires parents des chemins (Ghostscript 10+ --permit-file-read, mode restreint).
    #>
    param([string[]]$Paths)
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($raw in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        try { $full = [System.IO.Path]::GetFullPath($raw) } catch { continue }
        $dir = Split-Path -Parent $full
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        $lit = Convert-CnsFilesystemPathToGhostscriptPathLiteral -Path $dir
        if ($seen.Add($lit)) { [void]$out.Add("--permit-file-read=$lit") }
    }
    try {
        $tmp = Convert-CnsFilesystemPathToGhostscriptPathLiteral -Path $env:TEMP
        if ($seen.Add($tmp)) { [void]$out.Add("--permit-file-read=$tmp") }
    }
    catch { }
    return @($out.ToArray())
}

function Get-CnsCoverPdfwriteQualityArgs {
    return @(
        '-dPDFSETTINGS=/prepress',
        '-dEmbedAllFonts=true',
        '-dSubsetFonts=false'
    )
}

function Write-CnsPostScriptPdfPage {
    <#
    .SYNOPSIS
        Ghostscript : .ps mono-page -> PDF A4 (595x842).
    .NOTES
        # Utilisation de Helvetica pour compatibilite maximale Ghostscript (polices base PDF, sans CIDFont / TTF / CIDFMAP).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PsBodySansShowpage,
        [Parameter(Mandatory = $true)]
        [string]$OutPdfPath,
        [switch]$SkipTrailingShowpage
    )
    $prolog = "<< /PageSize [595 842] >> setpagedevice`n"
    $runId = [Guid]::NewGuid().ToString('N')
    $psPath = Join-Path $env:TEMP ("cn_cover_{0}.ps1gen.ps" -f $runId)
    $footer = if ($SkipTrailingShowpage) { "`r`n" } else { "`r`nshowpage`r`n" }
    $psDoc = "%!PS-Adobe-3.0`r`n" + $prolog + $PsBodySansShowpage + $footer
    try {
        [System.IO.File]::WriteAllText($psPath, $psDoc, [System.Text.UTF8Encoding]::new($false))
    }
    catch {
        return $false
    }

    $gs = Get-ResolvedGhostscriptPath
    if (-not $gs) {
        Remove-Item -LiteralPath $psPath -Force -ErrorAction SilentlyContinue
        return $false
    }

    $outAbs = [System.IO.Path]::GetFullPath($OutPdfPath)
    $psArg = (Convert-CnsFilesystemPathToGhostscriptPathLiteral -Path $psPath)

    $gsArgs = [System.Collections.Generic.List[string]]::new()
    [void]$gsArgs.AddRange([string[]]@(
        '-dNOPAUSE', '-dBATCH', '-sDEVICE=pdfwrite'
    ))
    [void]$gsArgs.AddRange([string[]](Get-CnsCoverPdfwriteQualityArgs))
    [void]$gsArgs.AddRange([string[]]@(
        ("-sOutputFile=$outAbs")
    ))
    [void]$gsArgs.AddRange([string[]](Get-CnsGhostscriptPermitFileReadArgs -Paths @($outAbs, $psPath)))
    [void]$gsArgs.Add($psArg)

    try {
        $p = Start-Process -FilePath $gs -ArgumentList @($gsArgs.ToArray()) -Wait -PassThru -NoNewWindow
        if ($null -eq $p -or $p.ExitCode -ne 0) {
            Remove-Item -LiteralPath $psPath -Force -ErrorAction SilentlyContinue
            return $false
        }
    }
    catch {
        Remove-Item -LiteralPath $psPath -Force -ErrorAction SilentlyContinue
        return $false
    }
    Remove-Item -LiteralPath $psPath -Force -ErrorAction SilentlyContinue
    return (Test-Path -LiteralPath $outAbs)
}

function Split-CnsCoverTextToMaxWidth {
    param(
        [AllowNull()][AllowEmptyString()][string]$Text,
        [int]$MaxLen = 88
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $words = @(([string]$Text).Trim() -split '\s+')
    $lines = [System.Collections.Generic.List[string]]::new()
    $current = ''
    foreach ($w in @($words)) {
        if ([string]::IsNullOrWhiteSpace($w)) { continue }
        if ([string]::IsNullOrWhiteSpace($current)) {
            $current = $w
            continue
        }
        if (($current.Length + 1 + $w.Length) -le $MaxLen) {
            $current = "$current $w"
        }
        else {
            [void]$lines.Add($current)
            $current = $w
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($current)) {
        [void]$lines.Add($current)
    }
    return @($lines.ToArray())
}

function Get-CnsCoverGapVerticalCost {
    param([string]$Kind)
    switch ($Kind) {
        'G12' { return 12 }
        'G15' { return 15 }
        'G20' { return 20 }
        'G25' { return 25 }
        'S8'  { return 8 }
        'S15' { return 15 }
        'BLK' { return 8 }
        default { return 0 }
    }
}

function Get-CnsCoverElementVerticalCost {
    param(
        $Element,
        [int]$PageWidth = 612
    )
    if ($null -eq $Element) { return 0 }
    $kind = [string]$Element.Kind
    $txt = [string]$Element.Text
    $gap = Get-CnsCoverGapVerticalCost -Kind $kind
    if ($gap -gt 0) { return $gap }

    switch ($kind) {
        'TC12' {
            $n = @((Split-CnsCoverTextToMaxWidth -Text $txt -MaxLen 72)).Count
            if ($n -lt 1) { return 14 }
            return (14 * $n)
        }
        'T12' {
            $n = @((Split-CnsCoverTextToMaxWidth -Text $txt -MaxLen 85)).Count
            if ($n -lt 1) { return 11 }
            return (11 * $n)
        }
        'B11' {
            $n = @((Split-CnsCoverTextToMaxWidth -Text $txt -MaxLen 85)).Count
            if ($n -lt 1) { return 11 }
            return (11 * $n)
        }
        { $_ -in @('H10', 'VE', 'I10', 'N10') } {
            $n = @((Split-CnsCoverTextToMaxWidth -Text $txt -MaxLen 85)).Count
            if ($n -lt 1) { return 10 }
            return (10 * $n)
        }
        default {
            if ([string]::IsNullOrWhiteSpace($txt)) { return 0 }
            $n = @((Split-CnsCoverTextToMaxWidth -Text $txt -MaxLen 85)).Count
            if ($n -lt 1) { return 10 }
            return (10 * $n)
        }
    }
}

function Build-CnsMismatchCoverPostScriptFromElements {
    <#
    .SYNOPSIS
        Page(s) de garde non-matches : polices compactes, pagination, message de troncature si besoin.
    #>
    param(
        [AllowEmptyCollection()][object[]]$Elements,
        [Parameter(Mandatory = $true)][int]$StartY,
        [Parameter(Mandatory = $true)][int]$MinY,
        [int]$PageWidth = 612,
        [switch]$Multipage
    )
    if ($null -eq $Elements -or @($Elements).Count -lt 1) { return '' }

    $elList = @($Elements)
    $parts = New-Object System.Collections.Generic.List[string]
    [int]$xLeft = 50
    [int]$xIndent = 70
    [int]$idx = 0
    [int]$pageNum = 1
    $truncationDrawn = $false

    function script:Add-CnsCoverPsTextAtX {
        param(
            [string]$Text,
            [string]$FontName,
            [int]$FontSize,
            [int]$X,
            [int]$LineStep,
            $PartsList,
            [ref]$YRef,
            [int]$YMin
        )
        if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
        $textForPs = [string]$Text
        if (Get-Command Repair-CnsClientNumeroSignText -ErrorAction SilentlyContinue) {
            $textForPs = Repair-CnsClientNumeroSignText -Text $textForPs
        }
        $drew = $false
        $wrapped = @(Split-CnsCoverTextToMaxWidth -Text $textForPs -MaxLen 85)
        foreach ($wl in @($wrapped)) {
            if ($YRef.Value -lt $YMin) { return $drew }
            $lit = ConvertTo-CnsPsHelveticaParenBody -Text $wl
            [void]$PartsList.Add("/$FontName findfont $FontSize scalefont setfont`n$X $($YRef.Value) moveto`n($lit) show")
            $YRef.Value -= $LineStep
            $drew = $true
        }
        return $drew
    }

    function script:Add-CnsCoverPsTextCentered {
        param(
            [string]$Text,
            [string]$FontName,
            [int]$FontSize,
            [int]$LineStep,
            $PartsList,
            [ref]$YRef,
            [int]$YMin,
            [int]$PageW
        )
        if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
        $textForPs = [string]$Text
        if (Get-Command Repair-CnsClientNumeroSignText -ErrorAction SilentlyContinue) {
            $textForPs = Repair-CnsClientNumeroSignText -Text $textForPs
        }
        $drew = $false
        $wrapped = @(Split-CnsCoverTextToMaxWidth -Text $textForPs -MaxLen 72)
        foreach ($wl in @($wrapped)) {
            if ($YRef.Value -lt $YMin) { return $drew }
            $lit = ConvertTo-CnsPsHelveticaParenBody -Text $wl
            [void]$PartsList.Add(@"
/$FontName findfont $FontSize scalefont setfont
($lit) dup stringwidth pop $PageW exch sub 2 div $($YRef.Value) moveto show
"@)
            $YRef.Value -= $LineStep
            $drew = $true
        }
        return $drew
    }

    function script:Render-CnsCoverElement {
        param(
            $Element,
            $PartsList,
            [ref]$YRef,
            [int]$YMin,
            [int]$PageW,
            [int]$XLeft,
            [int]$XIndent
        )
        if ($null -eq $Element) { return $true }
        $kind = [string]$Element.Kind
        $txt = [string]$Element.Text
        switch ($kind) {
            'TC12' {
                return (script:Add-CnsCoverPsTextCentered -Text $txt -FontName 'Helvetica-Bold' -FontSize 14 -LineStep 14 `
                    -PartsList $PartsList -YRef $YRef -YMin $YMin -PageW $PageW)
            }
            'T12' {
                return (script:Add-CnsCoverPsTextAtX -Text $txt -FontName 'Helvetica-Bold' -FontSize 10 -X $XLeft -LineStep 11 `
                    -PartsList $PartsList -YRef $YRef -YMin $YMin)
            }
            'H10' {
                return (script:Add-CnsCoverPsTextAtX -Text $txt -FontName 'Helvetica' -FontSize 9 -X $XLeft -LineStep 10 `
                    -PartsList $PartsList -YRef $YRef -YMin $YMin)
            }
            'VE' {
                return (script:Add-CnsCoverPsTextAtX -Text $txt -FontName 'Helvetica' -FontSize 9 -X $XLeft -LineStep 10 `
                    -PartsList $PartsList -YRef $YRef -YMin $YMin)
            }
            'B11' {
                return (script:Add-CnsCoverPsTextAtX -Text $txt -FontName 'Helvetica-Bold' -FontSize 10 -X $XLeft -LineStep 11 `
                    -PartsList $PartsList -YRef $YRef -YMin $YMin)
            }
            'I10' {
                return (script:Add-CnsCoverPsTextAtX -Text $txt -FontName 'Helvetica' -FontSize 9 -X $XIndent -LineStep 10 `
                    -PartsList $PartsList -YRef $YRef -YMin $YMin)
            }
            'N10' {
                return (script:Add-CnsCoverPsTextAtX -Text $txt -FontName 'Helvetica' -FontSize 9 -X $XLeft -LineStep 10 `
                    -PartsList $PartsList -YRef $YRef -YMin $YMin)
            }
            { $_ -in @('S8', 'S15', 'G12', 'G15', 'G20', 'G25', 'BLK') } {
                $YRef.Value -= (Get-CnsCoverGapVerticalCost -Kind $kind)
                return $true
            }
            default {
                if ([string]::IsNullOrWhiteSpace($txt)) { return $true }
                return (script:Add-CnsCoverPsTextAtX -Text $txt -FontName 'Helvetica' -FontSize 9 -X $XLeft -LineStep 10 `
                    -PartsList $PartsList -YRef $YRef -YMin $YMin)
            }
        }
    }

    function script:Add-CnsCoverTruncationNotice {
        param(
            [int]$RemainingCount,
            $PartsList,
            [int]$YMin
        )
        if ($RemainingCount -lt 1) { return }
        $truncMsg = "... et $RemainingCount autre(s) ODM non affiche(s) (voir fichier diagnostic)"
        $lit = ConvertTo-CnsPsHelveticaParenBody -Text $truncMsg
        $yMsg = $YMin + 10
        [void]$PartsList.Add("/Helvetica findfont 9 scalefont setfont`n$xLeft $yMsg moveto`n($lit) show")
    }

    while ($idx -lt $elList.Count) {
        if ($pageNum -gt 1) {
            [void]$parts.Add('showpage')
            $contTitle = '=== SYNTHESE DES ODM NON MATCHES (suite) ==='
            $litCont = ConvertTo-CnsPsHelveticaParenBody -Text $contTitle
            [void]$parts.Add("/Helvetica-Bold findfont 14 scalefont setfont`n50 780 moveto`n($litCont) show")
        }

        [int]$y = $StartY
        [int]$startIdx = $idx
        while ($idx -lt $elList.Count) {
            $el = $elList[$idx]
            $cost = Get-CnsCoverElementVerticalCost -Element $el -PageWidth $PageWidth
            if (($y - $cost) -lt $MinY) {
                break
            }
            $null = script:Render-CnsCoverElement -Element $el -PartsList $parts -YRef ([ref]$y) -YMin $MinY `
                -PageW $PageWidth -XLeft $xLeft -XIndent $xIndent
            $idx++
        }

        if ($idx -eq $startIdx) {
            if (-not $truncationDrawn) {
                $remaining = $elList.Count - $idx
                script:Add-CnsCoverTruncationNotice -RemainingCount $remaining -PartsList $parts -YMin $MinY
                $truncationDrawn = $true
            }
            break
        }

        if ($idx -lt $elList.Count) {
            $pageNum++
            if (-not $Multipage) {
                if (-not $truncationDrawn) {
                    $remaining = $elList.Count - $idx
                    script:Add-CnsCoverTruncationNotice -RemainingCount $remaining -PartsList $parts -YMin $MinY
                    $truncationDrawn = $true
                }
                break
            }
        }
    }

    if ($idx -lt $elList.Count -and -not $truncationDrawn) {
        $remaining = $elList.Count - $idx
        script:Add-CnsCoverTruncationNotice -RemainingCount $remaining -PartsList $parts -YMin $MinY
    }

    if ($parts.Count -lt 1) { return '' }
    $body = ($parts.ToArray()) -join "`n"
    if ($pageNum -gt 1 -or ($body -match '(?m)^showpage\s*$')) {
        return ($body + "`nshowpage")
    }
    return $body
}

function Expand-CnsCoverDiagnosticLinesForPostScript {
    param(
        [AllowEmptyCollection()][string[]]$Lines,
        [int]$MaxLen = 88
    )
    $expanded = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @($Lines)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $wrapped = @(Split-CnsCoverTextToMaxWidth -Text $line -MaxLen $MaxLen)
        if ($wrapped.Count -lt 1) { continue }
        [void]$expanded.Add($wrapped[0])
        for ($wi = 1; $wi -lt $wrapped.Count; $wi++) {
            [void]$expanded.Add(('    {0}' -f $wrapped[$wi]))
        }
    }
    return @($expanded.ToArray())
}

function New-CnsGlobalMismatchCoverPdf {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutPdfPath,
        [Parameter(Mandatory = $true)]
        [int]$TotalOdmCount,
        [Parameter(Mandatory = $true)]
        [int]$UnmatchedOdmCount,
        [AllowEmptyCollection()]
        [string[]]$DetailLines = @(),
        [AllowEmptyCollection()]
        [object[]]$CoverElements = @(),
        [int]$Section1Count = -1,
        [int]$Section2Count = -1,
        [int]$Section3Count = -1,
        [switch]$AllMatched
    )
    $mainTitle = '=== SYNTHESE DES ODM NON MATCHES ==='
    $lTotal = "Nombre total d'ODM (groupes extraits du PDF) : $TotalOdmCount"
    $tMain = ConvertTo-CnsPsHelveticaParenBody -Text $mainTitle
    $tTotal = ConvertTo-CnsPsHelveticaParenBody -Text $lTotal
    $bodyParts = [System.Collections.Generic.List[string]]::new()
    $pageW = 595
    $hasSectionCounts = ($Section1Count -ge 0 -or $Section2Count -ge 0 -or $Section3Count -ge 0)
    if ($hasSectionCounts) {
        $s1 = [Math]::Max(0, $Section1Count)
        $s2 = [Math]::Max(0, $Section2Count)
        $s3 = [Math]::Max(0, $Section3Count)
        $lSec1 = "Section 1 : $s1 EXCEL SANS ODM"
        $lSec2 = "Section 2 : $s2 ODM DIFFERENTS D'EXCEL"
        $lSec3 = "Section 3 : $s3 ODM ABSENTS D'EXCEL"
        $tSec1 = ConvertTo-CnsPsHelveticaParenBody -Text $lSec1
        $tSec2 = ConvertTo-CnsPsHelveticaParenBody -Text $lSec2
        $tSec3 = ConvertTo-CnsPsHelveticaParenBody -Text $lSec3
        [void]$bodyParts.Add(@"
/Helvetica-Bold findfont 14 scalefont setfont
($tMain) dup stringwidth pop $pageW exch sub 2 div 780 moveto show
/Helvetica findfont 10 scalefont setfont
50 745 moveto
($tTotal) show
50 720 moveto
($tSec1) show
50 695 moveto
($tSec2) show
50 670 moveto
($tSec3) show
"@)
    }
    else {
        $lLegacy = "Nombre d'ODM PDF sans correspondance Excel : $UnmatchedOdmCount"
        $tLegacy = ConvertTo-CnsPsHelveticaParenBody -Text $lLegacy
        [void]$bodyParts.Add(@"
/Helvetica-Bold findfont 14 scalefont setfont
($tMain) dup stringwidth pop $pageW exch sub 2 div 780 moveto show
/Helvetica findfont 10 scalefont setfont
50 745 moveto
($tTotal) show
50 720 moveto
($tLegacy) show
"@)
    }

    $detailStartY = 650
    $detailMinY = 35
    $detailPs = ''
    if (@($CoverElements).Count -gt 0) {
        $detailPs = Build-CnsMismatchCoverPostScriptFromElements -Elements @($CoverElements) `
            -StartY $detailStartY -MinY $detailMinY -Multipage
    }
    elseif (@($DetailLines).Count -gt 0) {
        $flatDetail = @(Expand-CnsCoverDiagnosticLinesForPostScript -Lines @($DetailLines))
        if ($flatDetail.Count -gt 0) {
            $detailPs = Build-CnsCoverTextLinesPostScriptAppend -Lines $flatDetail -StartY $detailStartY -LineStep 10 -MinY $detailMinY -FontName 'Helvetica' -FontSize 9
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($detailPs)) {
        [void]$bodyParts.Add($detailPs)
    }
    elseif ($AllMatched) {
        $okMsg = 'Tous les ODM ont ete matches avec succes.'
        $tOk = ConvertTo-CnsPsHelveticaParenBody -Text $okMsg
        [void]$bodyParts.Add("/Helvetica findfont 9 scalefont setfont`n50 $detailStartY moveto`n($tOk) show")
    }

    $body = ($bodyParts.ToArray()) -join "`n"
    $skipTrailingShow = ($detailPs -match '(?m)showpage\s*$')
    Write-CnsPostScriptPdfPage -PsBodySansShowpage $body -OutPdfPath $OutPdfPath -SkipTrailingShowpage:$skipTrailingShow
}

function Format-CnsTourneeCoverDateFrLong {
    <#
    .SYNOPSIS
        Date affichee type "Mardi 24 mars 2026" (culture fr-FR) depuis JJ/MM/AAAA ou parse libre.
    #>
    param([AllowNull()][AllowEmptyString()][string]$DateJJMMAAAA)
    if ([string]::IsNullOrWhiteSpace($DateJJMMAAAA)) { return '' }
    $raw = $DateJJMMAAAA.Trim()
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $fr = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    [datetime]$dt = [datetime]::Today
    $parsed = $false
    foreach ($pat in @('dd/MM/yyyy', 'd/M/yyyy', 'dd/MM/yy')) {
        try {
            [datetime]$tmp = $dt
            if ([datetime]::TryParseExact($raw, $pat, $inv, [System.Globalization.DateTimeStyles]::None, [ref]$tmp)) {
                $dt = $tmp
                $parsed = $true
                break
            }
        }
        catch { }
    }
    if (-not $parsed) {
        [datetime]$tmp2 = $dt
        if (-not [datetime]::TryParse($raw, $fr, [System.Globalization.DateTimeStyles]::None, [ref]$tmp2)) {
            if (-not [datetime]::TryParse($raw, $inv, [System.Globalization.DateTimeStyles]::None, [ref]$tmp2)) {
                return $raw
            }
        }
        $dt = $tmp2
    }
    $formatted = $dt.ToString('dddd dd MMMM yyyy', $fr)
    if ($formatted.Length -lt 2) { return $formatted }
    return ($formatted.Substring(0, 1).ToUpper() + $formatted.Substring(1))
}

function Format-CnsFrenchLongDateForCoverLabels {
    param([AllowNull()][AllowEmptyString()][string]$LongFr)
    if ([string]::IsNullOrWhiteSpace($LongFr)) { return $LongFr }
    $repl = [ordered]@{
        'janvier' = 'Janvier'; 'février' = 'Fevrier'; 'fevrier' = 'Fevrier'; 'mars' = 'Mars'; 'avril' = 'Avril'
        'mai' = 'Mai'; 'juin' = 'Juin'; 'juillet' = 'Juillet'; 'août' = 'Aout'; 'aout' = 'Aout'
        'septembre' = 'Septembre'; 'octobre' = 'Octobre'; 'novembre' = 'Novembre'; 'décembre' = 'Decembre'; 'decembre' = 'Decembre'
    }
    $s = [string]$LongFr
    foreach ($entry in $repl.GetEnumerator()) {
        $s = $s -replace ('(?i)\b' + [regex]::Escape([string]$entry.Key) + '\b'), [string]$entry.Value
    }
    if ($s.Length -ge 2) {
        $s = $s.Substring(0, 1).ToUpper() + $s.Substring(1)
    }
    return $s
}

function Format-CnsTourneeCoverGardeDateTitle {
    <#
    .SYNOPSIS
        Titre date garde tournée : "Lundi 23 Avril 2026" (fr-FR, sans prefixe ODM/Date).
    #>
    param([AllowNull()][AllowEmptyString()][string]$DateJJMMAAAA)
    $title = Format-CnsTourneeCoverDateFrLong -DateJJMMAAAA $DateJJMMAAAA
    if ([string]::IsNullOrWhiteSpace($title)) {
        $fr = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
        $today = [datetime]::Today
        $title = $today.ToString('dddd dd MMMM yyyy', $fr)
        if ($title.Length -ge 2) {
            $title = $title.Substring(0, 1).ToUpper() + $title.Substring(1)
        }
    }
    return (Format-CnsFrenchLongDateForCoverLabels -LongFr $title)
}

function Get-CnsCoverPostScriptFontBlackName {
    <#
    .NOTES
        Arial-Black non disponible en PostScript Ghostscript standard — Helvetica-Bold equivalent visuel.
    #>
    return 'Helvetica-Bold'
}

function Get-CnsCoverPostScriptFontRegularName {
    return 'Helvetica'
}

function New-CnsPostScriptRightAlignedTextShowBlock {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$FontName,
        [Parameter(Mandatory = $true)][int]$FontSize,
        [Parameter(Mandatory = $true)][int]$RightX,
        [Parameter(Mandatory = $true)][int]$Y
    )
    $lit = ConvertTo-CnsPsHelveticaParenBody -Text $Text
    return @"
/$FontName findfont $FontSize scalefont setfont
($lit) dup stringwidth pop $RightX exch sub $Y moveto show
"@
}

function Build-CnsCoverTextLinesPostScriptAppend {
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Lines,
        [Parameter(Mandatory = $true)]
        [int]$StartY,
        [Parameter(Mandatory = $true)]
        [int]$LineStep,
        [Parameter(Mandatory = $true)]
        [int]$MinY,
        [string]$FontName = 'Helvetica',
        [int]$FontSize = 11
    )
    $parts = New-Object System.Collections.Generic.List[string]
    [int]$y = $StartY
    foreach ($line in @($Lines)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $lit = ConvertTo-CnsPsHelveticaParenBody -Text $line
        [void]$parts.Add("/$FontName findfont $FontSize scalefont setfont`n50 $y moveto`n($lit) show")
        $y -= $LineStep
        if ($y -lt $MinY) { break }
    }
    if ($parts.Count -lt 1) { return '' }
    return (($parts.ToArray()) -join "`n")
}

function Get-CnsTourneeCoverCollecteurPrenomDisplay {
    <#
    .SYNOPSIS
        Prenom seul pour la garde tournée ("Jean DUPONT" -> "Jean"). Vide si absent ou sentinelle Excel.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Collecteur)
    if ([string]::IsNullOrWhiteSpace($Collecteur)) { return '' }
    $value = ([string]$Collecteur).Trim()
    $plain = $value.ToUpperInvariant()
    foreach ($s in @('INCONNU', 'NON SPECIFIE', 'NON SPECIFIEE', '-', 'N/A', 'NA', 'ND')) {
        if ($plain -eq $s) { return '' }
    }
    $parts = @(
        ($value -split '\s+') |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($parts.Count -lt 1) { return '' }
    return [string]$parts[0]
}

function Build-CnsTourneeHeaderCoverPostScriptBody {
    param(
        [Parameter(Mandatory = $true)][string]$DateTitle,
        [Parameter(Mandatory = $true)][string]$Collecteur,
        [Parameter(Mandatory = $true)][string]$Vehicule,
        [AllowEmptyCollection()][string[]]$MetierMemoLines = @(),
        [AllowNull()][AllowEmptyString()][string]$IncompleteBanner = $null
    )
    $fontBlack = Get-CnsCoverPostScriptFontBlackName
    $fontReg = Get-CnsCoverPostScriptFontRegularName
    $litDate = ConvertTo-CnsPsHelveticaParenBody -Text $DateTitle
    [string]$prenom = Get-CnsTourneeCoverCollecteurPrenomDisplay -Collecteur $Collecteur
    [string]$vehText = if ([string]::IsNullOrWhiteSpace($Vehicule)) { '' } else { ([string]$Vehicule).Trim() }

    $headerFontSize = 18

    if (-not [string]::IsNullOrWhiteSpace($IncompleteBanner)) {
        $line1Y = 770
        $vehY = 740
        $memoY = 700
        $rightX = 550
        $litBanner = ConvertTo-CnsPsHelveticaParenBody -Text $IncompleteBanner
        $bannerPs = @"
/$fontBlack findfont 14 scalefont setfont
50 835 moveto
($litBanner) show
"@
    }
    else {
        $line1Y = 800
        $vehY = 770
        $memoY = 730
        $rightX = 550
        $bannerPs = ''
    }

    $prenomPs = ''
    if (-not [string]::IsNullOrWhiteSpace($prenom)) {
        $prenomPs = New-CnsPostScriptRightAlignedTextShowBlock -Text $prenom -FontName $fontBlack -FontSize $headerFontSize -RightX $rightX -Y $line1Y
    }

    $vehPs = ''
    if (-not [string]::IsNullOrWhiteSpace($vehText)) {
        $vehPs = New-CnsPostScriptRightAlignedTextShowBlock -Text $vehText -FontName $fontBlack -FontSize $headerFontSize -RightX $rightX -Y $vehY
    }

    $memoPs = Build-CnsCoverTextLinesPostScriptAppend -Lines @($MetierMemoLines) -StartY $memoY -LineStep 14 -MinY 72 -FontName $fontReg -FontSize 12

    return @"
$bannerPs
/$fontBlack findfont $headerFontSize scalefont setfont
50 $line1Y moveto
($litDate) show
$prenomPs
$vehPs
$memoPs
"@
}

function Get-CnsPlanningWorkOrderCacheKey {
    param([AllowNull()] $WorkOrderEntity)
    if ($null -eq $WorkOrderEntity) { return $null }
    try {
        $wk = [string]$WorkOrderEntity.WorkOrder
        if (-not [string]::IsNullOrWhiteSpace($wk)) { return $wk.Trim() }
    }
    catch { }
    try {
        $pages = @($WorkOrderEntity.Pages | ForEach-Object { [string]$_ }) -join ','
        if ($pages.Length -gt 0) { return ('PAGES:' + $pages) }
    }
    catch { }
    return $null
}

function Get-CnsDestructionCertificateWorkOrderKey {
    param([AllowNull()] $WorkOrderEntity)
    [string]$base = Get-CnsWorkOrderBaseIdFromEntity -WorkOrderEntity $WorkOrderEntity
    if (-not [string]::IsNullOrWhiteSpace($base)) { return ('WO:{0}' -f $base) }
    return (Get-CnsPlanningWorkOrderCacheKey -WorkOrderEntity $WorkOrderEntity)
}

function Get-CnsWorkOrderEntityForPlanningGsPair {
    <#
    .SYNOPSIS
        WorkOrder pour une page du PDF reorder : FinalOrder -> ligne Reordered -> ExcelOrder -> MatchResult (orderToWorkOrder).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [object]$GsPair,
        [Parameter(Mandatory = $true)]
        [hashtable]$FinalOrderToLine,
        [Parameter(Mandatory = $true)]
        [hashtable]$OrderToWorkOrder
    )
    if ($null -eq $OrderToWorkOrder -or $OrderToWorkOrder.Count -lt 1) { return $null }
    try { $fo = [int]$GsPair.FinalOrder } catch { return $null }
    if ($fo -lt 0) { return $null }
    $ln = $FinalOrderToLine[$fo]
    if ($null -eq $ln) { return $null }
    $ex = $ln.ExcelSourceOrder
    if ($null -eq $ex) { return $null }
    try {
        return $OrderToWorkOrder[[int]$ex]
    }
    catch { return $null }
}

function Get-CnsPageEntityByPhysicalPage {
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

function New-CnsWorkOrderEntityFromPageEntityForCert {
    param([AllowNull()] $PageEntity)
    if ($null -eq $PageEntity) { return $null }
    $addr = @{ Street = $null; PostalCode = $null; City = $null }
    if ($null -ne $PageEntity.Address) {
        try { $addr.Street = $PageEntity.Address.Street } catch { }
        try { $addr.PostalCode = $PageEntity.Address.PostalCode } catch { }
        try { $addr.City = $PageEntity.Address.City } catch { }
    }
    $wo = [pscustomobject]@{
        WorkOrder  = $PageEntity.WorkOrder
        ClientID   = $PageEntity.ClientID
        ClientName = $PageEntity.ClientName
        Address    = $addr
        VisitDate  = $PageEntity.VisitDate
        Contact    = $PageEntity.Contact
        Services   = @($PageEntity.Services)
        Pages      = @([int]$PageEntity.PageNumber)
    }
    if (Test-CnsPdfPageRequiresDestructionCertificate -PageEntity $PageEntity -WorkOrderEntity $wo) {
        return $wo
    }
    return $null
}

function New-CnsWorkOrderEntityFromPageTextFallback {
    <#
    .SYNOPSIS
        Dernier recours : ODM 7 chiffres + mention Destruction dans le texte page (PdfEntities.Lines).
    #>
    param([AllowNull()] $PageEntity)
    if ($null -eq $PageEntity) { return $null }

    $lines = @()
    try {
        if ($null -ne $PageEntity.PSObject.Properties['Lines']) {
            $lines = @($PageEntity.Lines)
        }
    }
    catch { $lines = @() }
    if ($lines.Count -lt 1) {
        foreach ($svc in @($PageEntity.Services)) {
            if ($null -eq $svc) { continue }
            try {
                $t = [string]$svc.Type
                if (-not [string]::IsNullOrWhiteSpace($t)) { [void]$lines.Add($t) }
            }
            catch { }
            try {
                $o = [string]$svc.ODM
                if (-not [string]::IsNullOrWhiteSpace($o)) { [void]$lines.Add($o) }
            }
            catch { }
        }
    }

    $text = (($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n")
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $hasDest = $false
    foreach ($svc in @($PageEntity.Services)) {
        if ($null -eq $svc) { continue }
        try {
            if (Test-CnsServiceTypeIsDestructionPrestationLine -Type ([string]$svc.Type)) {
                $hasDest = $true
                break
            }
        }
        catch { }
    }
    if (-not $hasDest) {
        if ($text -notmatch '(?i)Destruction(\s+confidentielle)?\s+de\b' -and
            $text -notmatch '(?i)Destruction\s+confidentielle') {
            return $null
        }
        $hasDest = $true
    }

    $rxOdm = [regex]'(?i)(?<![0-9])(\d{7}\s*\p{Pd}\s*\d+)\b'
    $odmNorm = $null
    $m = $rxOdm.Match($text)
    if ($m.Success) {
        $collapsed = [regex]::Replace([string]$m.Groups[1].Value, '\s+', '')
        $oneDash = [regex]::Replace($collapsed, '\p{Pd}+', '-')
        if ($oneDash -match '^(\d{7})-(\d+)$') {
            $odmNorm = ('{0}-{1}' -f $Matches[1], $Matches[2])
        }
        else {
            $odmNorm = $oneDash
        }
    }
    if ([string]::IsNullOrWhiteSpace($odmNorm)) { return $null }

    [string]$baseId = Get-CnsWorkOrderBaseIdFromToken -Token $odmNorm
    if ([string]::IsNullOrWhiteSpace($baseId)) { return $null }

    [string]$typeUse = 'Destruction'
    foreach ($line in @($lines)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if (Test-CnsServiceTypeIsDestructionPrestationLine -Type $line) {
            $typeUse = $line.Trim()
            break
        }
    }

    $svcArr = @($PageEntity.Services)
    if ($svcArr.Count -lt 1) {
        $svcArr = @([pscustomobject]@{ Type = $typeUse; ODM = $odmNorm })
    }

    $addrFb = @{ Street = $null; PostalCode = $null; City = $null }
    if ($null -ne $PageEntity.Address) {
        try { $addrFb.Street = $PageEntity.Address.Street } catch { }
        try { $addrFb.PostalCode = $PageEntity.Address.PostalCode } catch { }
        try { $addrFb.City = $PageEntity.Address.City } catch { }
    }

    $wo = [pscustomobject]@{
        WorkOrder  = if ([string]::IsNullOrWhiteSpace([string]$PageEntity.WorkOrder)) { $baseId } else { [string]$PageEntity.WorkOrder }
        ClientID   = $PageEntity.ClientID
        ClientName = $PageEntity.ClientName
        Address    = $addrFb
        VisitDate  = $PageEntity.VisitDate
        Contact    = $PageEntity.Contact
        Services   = $svcArr
        Pages      = @([int]$PageEntity.PageNumber)
    }
    if (-not (Test-CnsPdfPageRequiresDestructionCertificate -PageEntity $PageEntity -WorkOrderEntity $wo)) { return $null }
    return $wo
}

function Resolve-CnsWorkOrderEntityForStep5 {
    <#
    .SYNOPSIS
        Resolution WorkOrder STEP 5 depuis PDF uniquement (WorkOrders / PdfEntities / texte page).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [object]$GsPair,
        [Parameter(Mandatory = $true)]
        [hashtable]$FinalOrderToLine,
        [hashtable]$OrderToWorkOrder = @{},
        [AllowEmptyCollection()]
        [object[]]$WorkOrders = @(),
        [AllowEmptyCollection()]
        [object[]]$PdfEntities = @()
    )
    [int]$fo = -1
    [int]$rawPn = 0
    try { $fo = [int]$GsPair.FinalOrder } catch { $fo = -1 }
    try { $rawPn = [int]$GsPair.RawPageNum } catch { $rawPn = 0 }

    if ($rawPn -gt 0) {
        $woPdf = Resolve-CnsWorkOrderEntityFromPdfPage -RawPageNumOneBased $rawPn -WorkOrders $WorkOrders -PdfEntities $PdfEntities
        if ($null -ne $woPdf) {
            Write-Host ("[STEP5-PDF] WorkOrder resolu depuis ODM PDF (FinalOrder={0}, RawPage={1})." -f $fo, $rawPn) -ForegroundColor Cyan
            return $woPdf
        }
        $pe = Get-CnsPageEntityByPhysicalPage -PageNumberOneBased $rawPn -PdfEntities $PdfEntities
        if ($null -ne $pe) {
            $woPe = New-CnsWorkOrderEntityFromPageEntityForCert -PageEntity $pe
            if ($null -ne $woPe) {
                Write-Host ("[STEP5-PDF] WorkOrder construit depuis PdfEntities page {0}." -f $rawPn) -ForegroundColor Cyan
                return $woPe
            }
            $woRx = New-CnsWorkOrderEntityFromPageTextFallback -PageEntity $pe
            if ($null -ne $woRx) {
                Write-Host ("[STEP5-PDF] WorkOrder construit depuis texte PDF page {0}." -f $rawPn) -ForegroundColor Cyan
                return $woRx
            }
        }
    }

    Write-Host ("[STEP5-FAILED] No WorkOrder found (FinalOrder={0}, RawPage={1})." -f $fo, $rawPn) -ForegroundColor Yellow
    return $null
}

function New-CnsTourneeHeaderCoverPdf {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutPdfPath,
        [Parameter(Mandatory = $true)]
        [string]$DateJJMMAAAA,
        [Parameter(Mandatory = $true)]
        [string]$Collecteur,
        [Parameter(Mandatory = $true)]
        [string]$Vehicule,
        [Parameter()]
        [bool]$TourneeIncomplete = $false,
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$MetierMemoLines = @()
    )
    if ([string]::IsNullOrWhiteSpace($DateJJMMAAAA)) {
        $DateJJMMAAAA = (Get-Date).ToString('dd/MM/yyyy')
        Write-Verbose '[COVER] Date manquante, utilisation de la date du jour'
    }
    if ([string]::IsNullOrWhiteSpace($Collecteur)) {
        $Collecteur = 'INCONNU'
    }
    if ([string]::IsNullOrWhiteSpace($Vehicule)) {
        $Vehicule = 'NON SPECIFIE'
    }
    $dateTitle = Format-CnsTourneeCoverGardeDateTitle -DateJJMMAAAA $DateJJMMAAAA
    $banner = if ($TourneeIncomplete) { 'TOURNEE NON MATCHEE' } else { $null }
    $body = Build-CnsTourneeHeaderCoverPostScriptBody -DateTitle $dateTitle -Collecteur $Collecteur -Vehicule $Vehicule -MetierMemoLines @($MetierMemoLines) -IncompleteBanner $banner
    return (Write-CnsPostScriptPdfPage -PsBodySansShowpage $body -OutPdfPath $OutPdfPath)
}

function New-CnsPrefaceSectionCoverPdf {
    param(
        [Parameter(Mandatory = $true)][string]$OutPdfPath,
        [Parameter(Mandatory = $true)][int]$TotalOdmCount,
        [Parameter(Mandatory = $true)][int]$UnmatchedOdmCount
    )
    $l0 = 'ODM non matché dans les tournées du date de la tournée depuis le PDF importé'
    $l1 = "Nombre total d'ODM (groupes extraits du PDF) : $TotalOdmCount"
    $l2 = "Nombre d'ODM sans correspondance : $UnmatchedOdmCount"
    $t0 = ConvertTo-CnsPsHelveticaParenBody -Text $l0
    $t1 = ConvertTo-CnsPsHelveticaParenBody -Text $l1
    $t2 = ConvertTo-CnsPsHelveticaParenBody -Text $l2
    $body = @"
/Helvetica-Bold findfont 11 scalefont setfont
50 800 moveto
($t0) show
/Helvetica findfont 11 scalefont setfont
50 760 moveto
($t1) show
50 730 moveto
($t2) show
"@
    Write-CnsPostScriptPdfPage -PsBodySansShowpage $body -OutPdfPath $OutPdfPath
}

function Get-CnsWorkOrderEntityForRawPageNum {
    param(
        [Parameter(Mandatory = $true)]
        [int]$RawPageNumOneBased,
        [AllowEmptyCollection()]
        [object[]]$WorkOrders = @()
    )
    foreach ($w in @($WorkOrders)) {
        if ($null -eq $w) { continue }
        foreach ($p in @($w.Pages)) {
            try {
                if ([int]$p -eq $RawPageNumOneBased) { return $w }
            }
            catch { }
        }
    }
    return $null
}

function Get-CnsTourneeCoverSegmentMetaForPair {
    param(
        [Parameter(Mandatory = $true)]
        [object]$GsPair,
        [Parameter(Mandatory = $true)]
        [hashtable]$FinalOrderToLine,
        [AllowEmptyCollection()]
        [object[]]$Segments = @(),
        [Parameter(Mandatory = $true)]
        [hashtable]$ExcelOrderIndexToSegmentIndex,
        [Parameter(Mandatory = $true)]
        [datetime]$VisitDate
    )
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $defJj = $VisitDate.ToString('dd/MM/yyyy', $inv)
    $out = [pscustomobject]@{
        DateJJMMAAAA = $defJj
        Collecteur   = '-'
        Vehicule     = '-'
    }
    try { $fo = [int]$GsPair.FinalOrder } catch { return $out }
    if ($fo -lt 1) { return $out }
    $ln = $FinalOrderToLine[$fo]
    if ($null -eq $ln) { return $out }
    $ex = $ln.ExcelSourceOrder
    if ($null -eq $ex) { return $out }
    try { $exI = [int]$ex } catch { return $out }
    $segNum = $ExcelOrderIndexToSegmentIndex[$exI]
    if ($null -eq $segNum) {
        $sk = ([string]$ex).Trim()
        if ($sk.Length -gt 0) { $segNum = $ExcelOrderIndexToSegmentIndex[$sk] }
    }
    if ($null -eq $segNum) { return $out }
    try { $sn = [int]$segNum } catch { return $out }
    if ($sn -lt 1) { return $out }
    $seg = $null
    foreach ($s in @($Segments)) {
        if ($null -eq $s) { continue }
        try {
            if ([int]$s.SegmentIndex -eq $sn) { $seg = $s; break }
        }
        catch { }
    }
    if ($null -eq $seg) { return $out }
    $jj = ''
    try { $jj = [string]$seg.DisplayDateJM } catch { $jj = '' }
    if ([string]::IsNullOrWhiteSpace($jj)) {
        try { $jj = ($seg.TourDate).ToString('dd/MM/yyyy', $inv) } catch { $jj = $defJj }
    }
    if ([string]::IsNullOrWhiteSpace($jj)) { $jj = $defJj }
    $c = ''; $v = ''
    try { $c = [string]$seg.Collecteur } catch { }
    try { $v = [string]$seg.Vehicule } catch { }
    $out.DateJJMMAAAA = $jj
    $out.Collecteur = if ([string]::IsNullOrWhiteSpace($c)) { '-' } else { $c }
    $out.Vehicule = if ([string]::IsNullOrWhiteSpace($v)) { '-' } else { $v }
    return $out
}

function Invoke-CnsGhostscriptExtractOnePage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePdf,
        [Parameter(Mandatory = $true)]
        [int]$FirstPageOneBased,
        [Parameter(Mandatory = $true)]
        [string]$OutPdfPath
    )
    $gs = Get-ResolvedGhostscriptPath
    if (-not $gs) { return $false }
    $srcAbs = (Resolve-Path -LiteralPath $SourcePdf).Path
    $outAbs = [System.IO.Path]::GetFullPath($OutPdfPath)
    $arg = [System.Collections.Generic.List[string]]::new()
    [void]$arg.AddRange([string[]]@('-dNOPAUSE', '-dBATCH', '-sDEVICE=pdfwrite'))
    [void]$arg.AddRange([string[]](Get-CnsCoverPdfwriteQualityArgs))
    [void]$arg.AddRange([string[]]@(
        ("-sOutputFile=$outAbs"),
        ("-dFirstPage=$FirstPageOneBased"), ("-dLastPage=$FirstPageOneBased")
    ))
    [void]$arg.AddRange([string[]](Get-CnsGhostscriptPermitFileReadArgs -Paths @($srcAbs, $outAbs)))
    [void]$arg.Add($srcAbs)
    try {
        $p = Start-Process -FilePath $gs -ArgumentList @($arg.ToArray()) -Wait -PassThru -NoNewWindow
        return ($null -ne $p -and $p.ExitCode -eq 0 -and (Test-Path -LiteralPath $outAbs))
    }
    catch { return $false }
}

function Merge-CnsPdfFilesGhostscriptOrdered {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$InputPdfsOrdered,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPdfPath
    )
    $gs = Get-ResolvedGhostscriptPath
    if (-not $gs) { return $false }
    $outAbs = [System.IO.Path]::GetFullPath($DestinationPdfPath)
    $paths = @( $InputPdfsOrdered | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) } )
    if ($paths.Count -lt 1) { return $false }

    $argLenEst = 0
    foreach ($tp in @($paths)) { $argLenEst += ($tp.Length + 6) }

    $runGuid = [Guid]::NewGuid().ToString('N')
    try {
        if ($argLenEst -gt 28000 -or $paths.Count -gt 50) {
            $rspPath = Join-Path $env:TEMP ("cn_cover_merge_{0}.rsp" -f $runGuid)
            $lines = New-Object System.Collections.Generic.List[string]
            foreach ($tp in $paths) {
                [void]$lines.Add('-f')
                [void]$lines.Add("`"$tp`"")
            }
            [System.IO.File]::WriteAllLines($rspPath, $lines.ToArray(), [System.Text.UTF8Encoding]::new($false))
            $atArg = "@$rspPath"
            $mergeArgsRsp = [System.Collections.Generic.List[string]]::new()
            [void]$mergeArgsRsp.AddRange([string[]]@('-dNOPAUSE', '-dBATCH', '-sDEVICE=pdfwrite'))
            [void]$mergeArgsRsp.AddRange([string[]](Get-CnsCoverPdfwriteQualityArgs))
            [void]$mergeArgsRsp.AddRange([string[]]@(("-sOutputFile=$outAbs")))
            [void]$mergeArgsRsp.AddRange([string[]](Get-CnsGhostscriptPermitFileReadArgs -Paths (@($paths) + @($outAbs))))
            [void]$mergeArgsRsp.Add($atArg)
            $p = Start-Process -FilePath $gs -ArgumentList @($mergeArgsRsp.ToArray()) -Wait -PassThru -NoNewWindow
            if (Test-Path -LiteralPath $rspPath) { Remove-Item -LiteralPath $rspPath -Force -ErrorAction SilentlyContinue }
            return ($null -ne $p -and $p.ExitCode -eq 0 -and (Test-Path -LiteralPath $outAbs))
        }

        $mergeArgs = New-Object System.Collections.Generic.List[string]
        [void]$mergeArgs.AddRange([string[]]@('-dNOPAUSE', '-dBATCH', '-sDEVICE=pdfwrite'))
        [void]$mergeArgs.AddRange([string[]](Get-CnsCoverPdfwriteQualityArgs))
        [void]$mergeArgs.Add("-sOutputFile=$outAbs")
        [void]$mergeArgs.AddRange([string[]](Get-CnsGhostscriptPermitFileReadArgs -Paths (@($paths) + @($outAbs))))
        foreach ($tp in $paths) {
            [void]$mergeArgs.Add('-f')
            [void]$mergeArgs.Add($tp)
        }
        $p = Start-Process -FilePath $gs -ArgumentList @($mergeArgs.ToArray()) -Wait -PassThru -NoNewWindow
        return ($null -ne $p -and $p.ExitCode -eq 0 -and (Test-Path -LiteralPath $outAbs))
    }
    finally { }
}

function Get-CnsTourneeCoverGroupingKeyFromPair {
    param(
        [object]$GsPair,
        [hashtable]$FinalOrderToLine,
        [hashtable]$ExcelOrderIndexToSegmentIndex
    )
    try { $fo = [int]$GsPair.FinalOrder } catch { return '__PRE__' }
    if ($fo -lt 0) { return '__PRE__' }
    $ln = $FinalOrderToLine[$fo]
    if ($null -eq $ln) { return '__PRE__' }
    $src = [string]$ln.Source
    if ($src -eq 'PdfFallback') { return '__PRE__' }
    $ex = $ln.ExcelSourceOrder
    if ($null -eq $ex) { return '__TUNK__' }
    try { $exI = [int]$ex } catch { return '__TUNK__' }
    $seg = $ExcelOrderIndexToSegmentIndex[$exI]
    if ($null -eq $seg) {
        $exKey = ([string]$ex).Trim()
        if ($exKey.Length -gt 0 -and $null -ne $ExcelOrderIndexToSegmentIndex[$exKey]) {
            $seg = $ExcelOrderIndexToSegmentIndex[$exKey]
        }
    }
    if ($null -eq $seg) { return '__TUNK__' }
    try { $si = [int]$seg } catch { return '__TUNK__' }
    if ($si -lt 1) { return '__TUNK__' }
    return ('SEG{0}' -f $si)
}

function Build-PlanningTourneeCoverBlocks {
    <#
    .SYNOPSIS
        Blocs contigus (cle de regroupement) -> plages d'index 1..N dans le PDF principal (post-GS).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$SortedGsPairs,
        [Parameter(Mandatory = $true)]
        [hashtable]$FinalOrderToLine,
        [Parameter(Mandatory = $true)]
        [hashtable]$ExcelOrderIndexToSegmentIndex
    )
    $arr = @($SortedGsPairs)
    if ($arr.Count -lt 1) { return @() }
    $keys = New-Object object[] $arr.Count
    for ($i = 0; $i -lt $arr.Count; $i++) {
        $keys[$i] = Get-CnsTourneeCoverGroupingKeyFromPair -GsPair $arr[$i] -FinalOrderToLine $FinalOrderToLine -ExcelOrderIndexToSegmentIndex $ExcelOrderIndexToSegmentIndex
    }

    $blocks = [System.Collections.Generic.List[object]]::new()
    $runStart = 0
    for ($j = 1; $j -le $keys.Count; $j++) {
        $atEnd = ($j -eq $keys.Count)
        $split = (-not $atEnd) -and ($keys[$j] -ne $keys[$j - 1])
        if ($split -or $atEnd) {
            $from1 = $runStart + 1
            $to1 = $j
            [void]$blocks.Add([pscustomobject]@{
                GroupKey     = $keys[$runStart]
                MainFrom1    = $from1
                MainTo1      = $to1
            })
            $runStart = $j
        }
    }
    return @($blocks.ToArray())
}

function Get-CnsOdmPagePrestationDetectionLabel {
    param(
        $PageEntity,
        $WorkOrderEntity,
        [bool]$RequiresCea = $false
    )
    $parts = [System.Collections.Generic.List[string]]::new()
    $metierPage = Get-CnsPdfPageMetierAnalysis -PageEntity $PageEntity -WorkOrderEntity $WorkOrderEntity
    if ($metierPage.RequiresDestructionCertificate) { [void]$parts.Add('Destruction confidentielle detectee') }
    if ($RequiresCea) { [void]$parts.Add('CEA detecte') }
    foreach ($entry in @($metierPage.TrackDechetEntries)) {
        if ($null -eq $entry) { continue }
        $det = [string]$entry.Detail
        if ($det -match '(?i)pile') { [void]$parts.Add('Piles detectees') }
        if ($det -match '(?i)deee') { [void]$parts.Add('DEEE detecte') }
    }
    if ($parts.Count -lt 1) { return 'Aucune prestation metier specifique detectee' }
    return ($parts -join ', ')
}

function Write-TourneeCompositionTourStart {
    param(
        [AllowNull()][scriptblock]$ProgressCallback,
        [Parameter(Mandatory = $true)][string]$Detail,
        [int]$StepIndex = 5,
        [int]$StepCount = 5
    )
    if ($null -eq $ProgressCallback) { return }
    try {
        & $ProgressCallback @{
            StepIndex  = $StepIndex
            StepCount  = $StepCount
            Label      = 'Composition pages de garde'
            Status     = 'TourneeStart'
            Detail     = $Detail
        }
    }
    catch {
        Write-Warning ("[TOURNEE-UI] ProgressCallback echoue (Status=TourneeStart) : {0}" -f $_.Exception.Message)
    }
}

function Write-TourneeCompositionTourProgress {
    param(
        [AllowNull()][scriptblock]$ProgressCallback,
        [Parameter(Mandatory = $true)][string]$Detail,
        [int]$StepIndex = 5,
        [int]$StepCount = 5
    )
    if ($null -eq $ProgressCallback -or [string]::IsNullOrWhiteSpace($Detail)) { return }
    try {
        & $ProgressCallback @{
            StepIndex  = $StepIndex
            StepCount  = $StepCount
            Label      = 'Composition pages de garde'
            Status     = 'TourneeProgress'
            Detail     = $Detail
        }
    }
    catch {
        Write-Warning ("[TOURNEE-UI] ProgressCallback echoue (Status=TourneeProgress) : {0}" -f $_.Exception.Message)
    }
}

function Write-TourneeCompositionTourEnd {
    param(
        [AllowNull()][scriptblock]$ProgressCallback,
        [int]$StepIndex = 5,
        [int]$StepCount = 5
    )
    if ($null -eq $ProgressCallback) { return }
    try {
        & $ProgressCallback @{
            StepIndex  = $StepIndex
            StepCount  = $StepCount
            Label      = 'Composition pages de garde'
            Status     = 'TourneeEnd'
            Detail     = $null
        }
    }
    catch {
        Write-Warning ("[TOURNEE-UI] ProgressCallback echoue (Status=TourneeEnd) : {0}" -f $_.Exception.Message)
    }
}

function Write-TourneeCompositionTreeLine {
    param(
        [AllowNull()][scriptblock]$ProgressCallback,
        [string]$TreePrefix,
        [string]$Text = '',
        [int]$StepIndex = 5,
        [int]$StepCount = 5
    )
    if ([string]::IsNullOrWhiteSpace($Text)) {
        Write-Verbose '[TREE] Ignored empty line'
        return
    }
    $pfx = if ($null -ne $TreePrefix) { [string]$TreePrefix } else { '' }
    Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback -Detail ($pfx + $Text) -StepIndex $StepIndex -StepCount $StepCount
}

function Add-TourneeCompositionGeneratedDocCount {
    param([int]$Delta = 1)
    if ($null -eq $script:PlanningTourneeGeneratedDocCount) { $script:PlanningTourneeGeneratedDocCount = 0 }
    $script:PlanningTourneeGeneratedDocCount += $Delta
}

function Get-CnsTourneeBlockPrestationDetectionLabel {
    param(
        [Parameter(Mandatory = $true)] $Block,
        [Parameter(Mandatory = $true)][object[]]$SortedGsPairs,
        [AllowEmptyCollection()][object[]]$WorkOrders = @(),
        [AllowEmptyCollection()][object[]]$PdfEntities = @()
    )
    $hasDestruction = $false
    $hasCea = $false
    $hasPiles = $false
    $hasDeee = $false
    $sortedPairsArr = @($SortedGsPairs)
    for ($pn = [int]$Block.MainFrom1; $pn -le [int]$Block.MainTo1; $pn++) {
        $pairIdx = $pn - 1
        if ($pairIdx -lt 0 -or $pairIdx -ge $sortedPairsArr.Count) { continue }
        $gsPair = $sortedPairsArr[$pairIdx]
        [int]$rawPnPage = 0
        try { $rawPnPage = [int]$gsPair.RawPageNum } catch { $rawPnPage = 0 }
        $woPage = Resolve-CnsWorkOrderEntityForStep5 -GsPair $gsPair -FinalOrderToLine @{} -OrderToWorkOrder @{} -WorkOrders $WorkOrders -PdfEntities @($PdfEntities)
        $pePage = $null
        if ($rawPnPage -gt 0) {
            $pePage = Get-CnsPageEntityByPhysicalPage -PageNumberOneBased $rawPnPage -PdfEntities @($PdfEntities)
        }
        $metierPage = Get-CnsPdfPageMetierAnalysis -PageEntity $pePage -WorkOrderEntity $woPage
        if ($metierPage.RequiresDestructionCertificate) { $hasDestruction = $true }
        foreach ($entry in @($metierPage.TrackDechetEntries)) {
            if ($null -eq $entry) { continue }
            $det = [string]$entry.Detail
            if ($det -match '(?i)pile') { $hasPiles = $true }
            if ($det -match '(?i)deee') { $hasDeee = $true }
        }
        if ($null -ne $pePage) {
            $txt = Get-CnsPdfOdmPageTextContent -PageEntity $pePage -WorkOrderEntity $woPage
            $norm = ConvertTo-CnsMetierMatchNormalizedText -Text $txt
            if ($norm -match '(?i)\bcea\b') { $hasCea = $true }
        }
    }
    $parts = [System.Collections.Generic.List[string]]::new()
    if ($hasDestruction) { [void]$parts.Add('Destruction confidentielle detectee') }
    if ($hasCea) { [void]$parts.Add('CEA detecte') }
    if ($hasPiles) { [void]$parts.Add('Piles detectees') }
    if ($hasDeee) { [void]$parts.Add('DEEE detecte') }
    if ($parts.Count -lt 1) { return 'Aucune prestation metier specifique detectee' }
    return ($parts -join ', ')
}

function Invoke-PlanningTourneePdfCoverComposition {
    <#
    .SYNOPSIS
        Recoit le PDF principal deja genere (Reorganiser-PDF), insere page de garde globale + couvertures tournée
        et re-extrait les pages du main dans l'ordre pour produire le PDF final au meme chemin.
    .NOTES
        Desactiver : $env:CN_SKIP_TOURNEE_COVERS = '1'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MainPdfPath,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$SortedGsPairs,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Reordered,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$ExcelOrder,
        [Parameter(Mandatory = $true)]
        $ExcelData,
        $ColumnInfo,
        [Parameter(Mandatory = $true)]
        [datetime]$VisitDate,
        [Parameter(Mandatory = $true)]
        [int]$DeclaredPdfPageCount,
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$WorkOrders = @(),
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$PdfEntities = @(),
        $MatchResult = $null,
        [scriptblock]$ProgressCallback = $null
    )

    if ($env:CN_SKIP_TOURNEE_COVERS -in @('1', 'true')) {
        Write-Host '[TOURNEE] Composition couvertures desactivee (CN_SKIP_TOURNEE_COVERS).' -ForegroundColor DarkGray
        return $true
    }

    if (-not (Test-Path -LiteralPath $MainPdfPath)) {
        Write-Warning '[TOURNEE] Main PDF introuvable — composition abandonnee.'
        return $false
    }

    $gs = Get-ResolvedGhostscriptPath
    if (-not $gs) {
        Write-Warning '[TOURNEE] Ghostscript introuvable — composition couvertures abandonnee (PDF principal conserve).'
        return $false
    }

    $mainAbs = (Resolve-Path -LiteralPath $MainPdfPath).Path
    $mainPageCount = @($SortedGsPairs).Count
    if ($mainPageCount -lt 1) {
        Write-Warning '[TOURNEE] Sequence principale vide — pas de composition.'
        return $false
    }

    # Synthèse ODM (WorkOrderEntity) vs lignes de match Excel (OrderIndex -> entité pour prestations).
    [int]$totalODM = @($WorkOrders).Count
    $matchedWoKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $orderToWorkOrder = @{}
    if ($null -ne $MatchResult) {
        $woByNum = @{}
        foreach ($w in @($WorkOrders)) {
            if ($null -eq $w) { continue }
            try {
                $wk = [string]$w.WorkOrder
                if ([string]::IsNullOrWhiteSpace($wk)) { continue }
                $woByNum[$wk.Trim()] = $w
            }
            catch { }
        }
        foreach ($m in @($MatchResult.Matches)) {
            if ($null -eq $m) { continue }
            $key = Get-CnsPlanningWorkOrderKeyFromMatchWorkOrderField -WorkOrderField $m.WorkOrder
            if (-not [string]::IsNullOrWhiteSpace($key)) { [void]$matchedWoKeys.Add($key) }
            $ent = $null
            if ($null -ne $m.WorkOrder) {
                if ($m.WorkOrder -is [string]) {
                    $sk = ([string]$m.WorkOrder).Trim()
                    if ($woByNum.ContainsKey($sk)) { $ent = $woByNum[$sk] }
                }
                else {
                    $ent = $m.WorkOrder
                }
            }
            if ($null -eq $ent) { continue }
            try {
                $eo = [int]$m.ExcelOrder
                $orderToWorkOrder[$eo] = $ent
            }
            catch { }
        }
    }
    [int]$unmatchedCount = @(
        foreach ($w in @($WorkOrders)) {
            if ($null -eq $w) { continue }
            [string]$wk2 = ''
            try { $wk2 = [string]$w.WorkOrder } catch { $wk2 = '' }
            if ([string]::IsNullOrWhiteSpace($wk2)) {
                $w
                continue
            }
            if (-not $matchedWoKeys.Contains($wk2.Trim())) { $w }
        }
    ).Count

    $segments = @()
    if ($null -ne $ColumnInfo -and $null -ne $ExcelData) {
        try {
            $segments = @(Get-PlanningExcelTourneeCoverSegments -ExcelData $ExcelData -ColumnInfo $ColumnInfo -FallbackVisitDate $VisitDate -ExcelOrder $ExcelOrder -OrderToWorkOrder $orderToWorkOrder)
        }
        catch {
            Write-Warning ("[TOURNEE] Segments Excel non disponibles : {0}" -f $_.Exception.Message)
            $segments = @()
        }
    }

    $orderToSeg = @{}
    $segIx = 0
    foreach ($seg in @($segments)) {
        $segIx++
        [int]$segNum = $segIx
        try { $segNum = [int]$seg.SegmentIndex } catch { $segNum = $segIx }
        $oiList = @()
        if ($null -ne $seg.PSObject.Properties['OrderIndices']) { $oiList = @($seg.OrderIndices) }
        if ($oiList.Count -eq 0) {
            Write-Warning ("[TOURNEE] Segment {0} sans OrderIndices — cle PDF SEG{0} absente pour les lignes concernees." -f $segNum)
        }
        foreach ($oi in $oiList) {
            try {
                $k = [int]$oi
                $orderToSeg[$k] = [int]$segIx
                $orderToSeg["$k"] = [int]$segIx
            }
            catch { }
        }
    }

    $foToLine = @{}
    foreach ($ln in @($Reordered)) {
        if ($null -eq $ln) { continue }
        try {
            $foToLine[[int]$ln.FinalOrder] = $ln
        }
        catch { }
    }

    $blocks = @(Build-PlanningTourneeCoverBlocks -SortedGsPairs $SortedGsPairs -FinalOrderToLine $foToLine -ExcelOrderIndexToSegmentIndex $orderToSeg)
    $blockTotal = @($blocks).Count
    $script:PlanningTourneeBlockTotal = $blockTotal
    $script:PlanningTourneeGeneratedDocCount = 0

    $frag = [System.Collections.Generic.List[string]]::new()
    $runId = [Guid]::NewGuid().ToString('N')
    $tmpDir = $null
    $tmpDir = Join-Path $env:TEMP ('cn_coverwork_' + $runId)

    try {
        $null = New-Item -ItemType Directory -Path $tmpDir -Force -ErrorAction Stop

        $globalCov = Join-Path $tmpDir 'cover_global.pdf'

        Write-Host '[TOURNEE] Creation page de garde globale (premiere page du PDF final).' -ForegroundColor Cyan
        $coverElements = @()
        $coverAllMatched = $false
        $coverS1 = -1
        $coverS2 = -1
        $coverS3 = -1
        if (Get-Command Build-PlanningOdmMismatchThreeSectionCoverLines -ErrorAction SilentlyContinue) {
            try {
                $missingList = @()
                if ($null -ne $MatchResult -and $null -ne $MatchResult.Missing) {
                    $missingList = @($MatchResult.Missing)
                }
                $coverReport = Build-PlanningOdmMismatchThreeSectionCoverLines `
                    -Missing $missingList `
                    -WorkOrders @($WorkOrders) `
                    -ExcelOrder @($ExcelOrder) `
                    -MatchResult $MatchResult `
                    -TourSegments @($segments) `
                    -MaxEntriesPerSection 20
                $coverAllMatched = [bool]$coverReport.AllMatched
                $coverS1 = [int]$coverReport.Section1Count
                $coverS2 = [int]$coverReport.Section2Count
                $coverS3 = [int]$coverReport.Section3Count
                if (-not $coverAllMatched -and $null -ne $coverReport.Elements) {
                    $coverElements = @($coverReport.Elements)
                }
            }
            catch {
                Write-Warning ("[TOURNEE] Diagnostic ODM non matches indisponible : {0}" -f $_.Exception.Message)
            }
        }
        $gcOk = (New-CnsGlobalMismatchCoverPdf -OutPdfPath $globalCov `
                -TotalOdmCount $totalODM `
                -UnmatchedOdmCount $unmatchedCount `
                -CoverElements $coverElements `
                -Section1Count $coverS1 `
                -Section2Count $coverS2 `
                -Section3Count $coverS3 `
                -AllMatched:$coverAllMatched)
        if (-not $gcOk) {
            throw 'Ghostscript global cover echouee'
        }
        [void]$frag.Add($globalCov)

        $seenSegments = @{}
        $prefaceAlreadyAdded = $false
        $certInjectedForWo = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $ceaInjectedForPage = New-Object 'System.Collections.Generic.HashSet[int]'
        $bilanInjectedForSeg = @{}
        $sortedPairsArr = @($SortedGsPairs)
        $fi = 0
        foreach ($blk in @($blocks)) {
            $fi++
            $isLastTour = ($fi -eq $blockTotal)
            $tBranchCore = if ($isLastTour) { '└── ' } else { '├── ' }
            $tChildCore = if ($isLastTour) { '    ' } else { '│   ' }

            $segmentName = [string]$blk.GroupKey
            $tourHeaderDetail = $segmentName
            $segUi = $null
            if ([string]$blk.GroupKey -match '^SEG(\d+)$') {
                $segNumUi = [int]$Matches[1]
                $segUi = ($segments | Where-Object { [int]$_.SegmentIndex -eq $segNumUi } | Select-Object -First 1)
                if ($null -ne $segUi) {
                    $segLabel = [string]$segUi.Collecteur
                    if ([string]::IsNullOrWhiteSpace($segLabel)) { $segLabel = [string]$segUi.Vehicule }
                    if (-not [string]::IsNullOrWhiteSpace($segLabel)) { $segmentName = $segLabel }
                    $jjUi = [string]$segUi.DisplayDateJM
                    if ([string]::IsNullOrWhiteSpace($jjUi)) {
                        try { $jjUi = ($segUi.TourDate).ToString('dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture) } catch { $jjUi = $VisitDate.ToString('dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture) }
                    }
                    $dateTitleUi = Format-CnsTourneeCoverGardeDateTitle -DateJJMMAAAA $jjUi
                    $tourHeaderDetail = ('{0} - Collecteur : {1}' -f $dateTitleUi, $segLabel)
                }
            }
            if ([string]::IsNullOrWhiteSpace($tourHeaderDetail)) { $tourHeaderDetail = 'Operation en cours' }
            Write-TourneeCompositionTourStart -ProgressCallback $ProgressCallback -Detail ("{0}/{1}" -f $fi, $blockTotal)
            Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback `
                -Detail ("{0}Tournee {1}/{2} : {3}" -f $tBranchCore, $fi, $blockTotal, $tourHeaderDetail)

            $odmTotal = ([int]$blk.MainTo1 - [int]$blk.MainFrom1 + 1)
            if ($odmTotal -lt 1) { $odmTotal = 0 }
            $hasSegBilan = [string]$blk.GroupKey -match '^SEG(\d+)$'
            $coverBranch = if ($odmTotal -gt 0 -or $hasSegBilan) { '├── ' } else { '└── ' }

            $coverPath = Join-Path $tmpDir ('cover_blk_{0}.pdf' -f $fi)
            $coverCreated = $false

            switch -Regex ([string]$blk.GroupKey) {
                '^SEG(\d+)$' {
                    $n = [int]$Matches[1]
                    if ($seenSegments.ContainsKey($n)) {
                        Write-Host ("[TOURNEE] Garde tournée segment {0} deja inseree — pas de doublon pour ce bloc." -f $n) -ForegroundColor DarkGray
                    }
                    else {
                        $seenSegments[$n] = $true
                        Write-Host "[TOURNEE] Creating cover page for segment $n" -ForegroundColor Cyan
                        $seg = ($segments | Where-Object { [int]$_.SegmentIndex -eq $n } | Select-Object -First 1)
                        if ($null -eq $seg) {
                            Write-Host '[TOURNEE] Segment metadata introuvable — garde minimale (TOURNEE NON MATCHEE).' -ForegroundColor Yellow
                            $minimal = Join-Path $tmpDir ('cover_blk_min_{0}.pdf' -f $fi)
                            $fdMin = $VisitDate.ToString('dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
                            Write-Host ("[TOURNEE-COVER] Segment={0} Incomplete=True (metadata absente) Date={1}" -f $n, $fdMin) -ForegroundColor Cyan
                            if (New-CnsTourneeHeaderCoverPdf -OutPdfPath $minimal -DateJJMMAAAA $fdMin -Collecteur 'INCONNU' -Vehicule 'NON SPECIFIE' -TourneeIncomplete:$true -MetierMemoLines @()) {
                                [void]$frag.Add($minimal)
                                $coverCreated = $true
                            }
                            else {
                                Write-Warning '[TOURNEE] Garde minimale segment GS echouee'
                                [void]$seenSegments.Remove($n)
                            }
                        }
                        else {
                            $jj = [string]$seg.DisplayDateJM
                            if ([string]::IsNullOrWhiteSpace($jj)) {
                                try { $jj = ($seg.TourDate).ToString('dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture) } catch { $jj = $VisitDate.ToString('dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture) }
                            }
                            $inc = $true
                            try { $inc = -not [bool]$seg.TourneeComplete } catch { $inc = $true }
                            Write-Host ("[TOURNEE-COVER] Segment={0} Incomplete={1} Date={2} Collecteur={3} Vehicule={4} PagesBloc={5}" -f $n, $inc, $jj, ([string]$seg.Collecteur), ([string]$seg.Vehicule), (1 + $blk.MainTo1 - $blk.MainFrom1)) -ForegroundColor Cyan
                            $metierMemos = @(Get-CnsTourneeMetierMemoLinesForBlock -MainFrom1 ([int]$blk.MainFrom1) -MainTo1 ([int]$blk.MainTo1) `
                                -SortedGsPairs $sortedPairsArr -FinalOrderToLine $foToLine -WorkOrders $WorkOrders -PdfEntities @($PdfEntities))
                            Write-Host ("[STEP5-METIER] Segment {0} : {1} memo(s) garde tournée (source PDF ODM)." -f $n, $metierMemos.Count) -ForegroundColor DarkCyan
                            if (New-CnsTourneeHeaderCoverPdf -OutPdfPath $coverPath -DateJJMMAAAA $jj -Collecteur ([string]$seg.Collecteur) -Vehicule ([string]$seg.Vehicule) -TourneeIncomplete:$inc -MetierMemoLines $metierMemos) {
                                [void]$frag.Add($coverPath)
                                $coverCreated = $true
                            }
                            else {
                                Write-Warning "[TOURNEE] Cover segment $n GS failure"
                                [void]$seenSegments.Remove($n)
                            }
                        }
                    }
                }
                default {
                    Write-Host ('[TOURNEE] Creating cover page for preface / hors segment Excel (cle=' + ([string]$blk.GroupKey) + ')') -ForegroundColor Cyan
                    Write-Host ("[TOURNEE] Pages count (bloque principal) = {0}" -f (1 + $blk.MainTo1 - $blk.MainFrom1)) -ForegroundColor DarkCyan
                    if (-not $prefaceAlreadyAdded) {
                        if (New-CnsPrefaceSectionCoverPdf -OutPdfPath $coverPath -TotalOdmCount $totalODM -UnmatchedOdmCount $unmatchedCount) {
                            [void]$frag.Add($coverPath)
                            $prefaceAlreadyAdded = $true
                            $coverCreated = $true
                        }
                        else {
                            Write-Warning '[TOURNEE] Cover prefixe echouee'
                        }
                    }
                }
            }

            if ($coverCreated) {
                Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback `
                    -Detail ("{0}Creation page de garde tournee... [OK]" -f ($tChildCore + $coverBranch))
            }

            $sliceIx = 0
            $odmIdx = 0
            for ($pn = [int]$blk.MainFrom1; $pn -le [int]$blk.MainTo1; $pn++) {
                $sliceIx++
                $odmIdx++
                $slicePath = Join-Path $tmpDir ('main_slice_{0:D3}_{1:D5}.pdf' -f $fi, $sliceIx)
                if (-not (Invoke-CnsGhostscriptExtractOnePage -SourcePdf $mainAbs -FirstPageOneBased $pn -OutPdfPath $slicePath)) {
                    throw ("[TOURNEE] Extraction page principale #{0} echouee." -f $pn)
                }
                [void]$frag.Add($slicePath)

                $pairIdx = $pn - 1
                if ($pairIdx -ge 0 -and $pairIdx -lt $sortedPairsArr.Count) {
                    $gsPair = $sortedPairsArr[$pairIdx]
                    [int]$rawPnPage = 0
                    try { $rawPnPage = [int]$gsPair.RawPageNum } catch { $rawPnPage = 0 }

                    $woPage = Resolve-CnsWorkOrderEntityForStep5 -GsPair $gsPair -FinalOrderToLine $foToLine -OrderToWorkOrder @{} -WorkOrders $WorkOrders -PdfEntities @($PdfEntities)
                    $pePage = $null
                    if ($rawPnPage -gt 0) {
                        $pePage = Get-CnsPageEntityByPhysicalPage -PageNumberOneBased $rawPnPage -PdfEntities @($PdfEntities)
                    }
                    $metierPage = Get-CnsPdfPageMetierAnalysis -PageEntity $pePage -WorkOrderEntity $woPage
                    $requiresCeaPage = Test-CnsStep5FragSliceRequiresCeaDocument -FragSlicePdfPath $slicePath
                    $odmLabel = Get-CnsOdmPagePrestationDetectionLabel -PageEntity $pePage -WorkOrderEntity $woPage -RequiresCea:$requiresCeaPage
                    if ([string]::IsNullOrWhiteSpace($odmLabel)) { $odmLabel = 'Operation en cours' }

                    $willCert = $false
                    $willCea = $false
                    if ($metierPage.RequiresDestructionCertificate -and $null -ne $woPage) {
                        $woKeyProbe = Get-CnsDestructionCertificateWorkOrderKey -WorkOrderEntity $woPage
                        if (-not [string]::IsNullOrWhiteSpace($woKeyProbe) -and -not $certInjectedForWo.Contains($woKeyProbe)) {
                            $willCert = $true
                        }
                    }
                    if ($requiresCeaPage -and $rawPnPage -gt 0 -and -not $ceaInjectedForPage.Contains($rawPnPage)) {
                        $willCea = $true
                    }

                    $analyseIsLast = ($odmIdx -eq $odmTotal) -and -not $willCert -and -not $willCea -and -not $hasSegBilan
                    $analyseBranch = if ($analyseIsLast) { '└── ' } else { '├── ' }
                    Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback `
                        -Detail ("{0}Analyse ODM {1}/{2} : {3}" -f ($tChildCore + $analyseBranch), $odmIdx, $odmTotal, $odmLabel)

                    if ($metierPage.RequiresDestructionCertificate -and $null -ne $woPage) {
                        $woCacheKey = Get-CnsDestructionCertificateWorkOrderKey -WorkOrderEntity $woPage
                        if (-not [string]::IsNullOrWhiteSpace($woCacheKey) -and $certInjectedForWo.Add($woCacheKey)) {
                            if (Get-Command New-CnsDestructionCertificatePdfFromWordTemplate -ErrorAction SilentlyContinue) {
                                $segMeta = Get-CnsTourneeCoverSegmentMetaForPair -GsPair $gsPair -FinalOrderToLine $foToLine -Segments $segments -ExcelOrderIndexToSegmentIndex $orderToSeg -VisitDate $VisitDate
                                $phTable = @{}
                                foreach ($entry in (Get-CnsDestructionCertificatePlaceholders -WorkOrderEntity $woPage -SegmentMeta $segMeta -VisitDate $VisitDate).GetEnumerator()) {
                                    $phTable[[string]$entry.Key] = [string]$entry.Value
                                }
                                $certOut = Join-Path $tmpDir ('cert_dest_{0:D3}_{1:D5}.pdf' -f $fi, $sliceIx)
                                $certPdf = New-CnsDestructionCertificatePdfFromWordTemplate -OutPdfPath $certOut -Placeholders $phTable
                                if (-not [string]::IsNullOrWhiteSpace($certPdf) -and (Test-Path -LiteralPath $certPdf)) {
                                    if (Get-Command Write-CnsDestructionCertificatePdfMergeAudit -ErrorAction SilentlyContinue) {
                                        Write-CnsDestructionCertificatePdfMergeAudit -Phase 'GENERATED' -PdfPath $certPdf
                                    }
                                    [void]$frag.Add($certPdf)
                                    Add-TourneeCompositionGeneratedDocCount
                                    Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback `
                                        -Detail ("{0}Generation certificat destruction... [OK]" -f ($tChildCore + '│   └── '))
                                    Write-Host ("[DESTRUCTION-CERT] Certificat injecte apres page reorder #{0} (WO={1}, PDF ODM, fichier={2})." -f $pn, $woCacheKey, (Split-Path -Leaf $certPdf)) -ForegroundColor Green
                                }
                                else {
                                    [void]$certInjectedForWo.Remove($woCacheKey)
                                    Write-Warning ("[DESTRUCTION-CERT] Generation certificat echouee pour WO={0} — page ODM conservee." -f $woCacheKey)
                                }
                            }
                            else {
                                [void]$certInjectedForWo.Remove($woCacheKey)
                                Write-Warning '[DESTRUCTION-CERT] Module Word certificat non charge — injection ignoree.'
                            }
                        }
                    }

                    if ($requiresCeaPage -and $rawPnPage -gt 0 -and $ceaInjectedForPage.Add($rawPnPage)) {
                        $ceaOut = Join-Path $tmpDir ('cea_{0:D3}_{1:D5}.pdf' -f $fi, $sliceIx)
                        $ceaPdf = $null
                        if (Get-Command New-CnsCeaPointsDeCollectesPdfFromWordTemplate -ErrorAction SilentlyContinue) {
                            $segMetaCea = Get-CnsTourneeCoverSegmentMetaForPair -GsPair $gsPair -FinalOrderToLine $foToLine -Segments $segments -ExcelOrderIndexToSegmentIndex $orderToSeg -VisitDate $VisitDate
                            $phCea = @{}
                            foreach ($entry in (Get-CnsCeaPointsDeCollectePlaceholders -WorkOrderEntity $woPage -PageEntity $pePage -SegmentMeta $segMetaCea -VisitDate $VisitDate -FragSlicePdfPath $slicePath).GetEnumerator()) {
                                $phCea[[string]$entry.Key] = [string]$entry.Value
                            }
                            $ceaPdf = New-CnsCeaPointsDeCollectesPdfFromWordTemplate -OutPdfPath $ceaOut -Placeholders $phCea
                        }
                        else {
                            Write-Warning '[CEA-POINTS] Module Word CEA non charge — fallback PDF statique legacy.'
                            $ceaPdf = Copy-CnsMetierTemplatePdfToWorkDir -TemplateFileName 'CeaPointsDeCollectes.pdf' -WorkDir $tmpDir -DestLeafName ('cea_{0:D3}_{1:D5}.pdf' -f $fi, $sliceIx)
                        }
                        if (-not [string]::IsNullOrWhiteSpace($ceaPdf) -and (Test-Path -LiteralPath $ceaPdf)) {
                            Write-Host ("[CEA-POINTS] PDF injecte dans frag (source DOCX dynamique) : {0}" -f (Split-Path -Leaf $ceaPdf)) -ForegroundColor Green
                            [void]$frag.Add($ceaPdf)
                            Add-TourneeCompositionGeneratedDocCount
                            Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback `
                                -Detail ("{0}Generation document CEA... [OK]" -f ($tChildCore + '│   └── '))
                            Write-Host ("[STEP5-METIER] Document CEA injecte apres page reorder #{0} (RawPage={1}, fichier={2})." -f $pn, $rawPnPage, (Split-Path -Leaf $ceaPdf)) -ForegroundColor Green
                        }
                        else {
                            [void]$ceaInjectedForPage.Remove($rawPnPage)
                            Write-Warning ("[CEA-POINTS] Generation CEA echouee pour RawPage={0} — page non injectee." -f $rawPnPage)
                        }
                    }
                }
            }

            if ([string]$blk.GroupKey -match '^SEG(\d+)$') {
                $segNumBilan = [int]$Matches[1]
                if (-not $bilanInjectedForSeg.ContainsKey($segNumBilan)) {
                    $bilanInjectedForSeg[$segNumBilan] = $true
                    if (Get-Command New-CnsBilanCollectePdfFromWordTemplate -ErrorAction SilentlyContinue) {
                        $segBilan = ($segments | Where-Object { [int]$_.SegmentIndex -eq $segNumBilan } | Select-Object -First 1)
                        $phBilan = @{}
                        foreach ($entry in (Get-CnsBilanCollectePlaceholders -SegmentMeta $segBilan -VisitDate $VisitDate).GetEnumerator()) {
                            $phBilan[[string]$entry.Key] = [string]$entry.Value
                        }
                        $bilanOut = Join-Path $tmpDir ('bilan_seg_{0:D3}.pdf' -f $fi)
                        $bilanPdf = New-CnsBilanCollectePdfFromWordTemplate -OutPdfPath $bilanOut -Placeholders $phBilan
                        if (-not [string]::IsNullOrWhiteSpace($bilanPdf) -and (Test-Path -LiteralPath $bilanPdf)) {
                            if (Get-Command Write-CnsLibreOfficePdfMergeAudit -ErrorAction SilentlyContinue) {
                                Write-CnsLibreOfficePdfMergeAudit -Phase 'GENERATED' -PdfPath $bilanPdf -DocumentKind 'BILAN-COLLECTE'
                            }
                            [void]$frag.Add($bilanPdf)
                            Add-TourneeCompositionGeneratedDocCount
                            Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback `
                                -Detail ("{0}Generation bilan collecte... [OK]" -f ($tChildCore + '└── '))
                            Write-Host ("[STEP5-METIER] Bilan de collecte dynamique injecte en fin de tournée segment {0} (fichier={1})." -f $segNumBilan, (Split-Path -Leaf $bilanPdf)) -ForegroundColor Green
                        }
                        else {
                            Write-Warning ("[BILAN-COLLECTE] Generation bilan echouee pour segment {0} — page non injectee." -f $segNumBilan)
                        }
                    }
                    else {
                        Write-Warning '[BILAN-COLLECTE] Module Word bilan non charge — injection ignoree.'
                    }
                }
            }
            Write-TourneeCompositionTourEnd -ProgressCallback $ProgressCallback
        }

        Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback -Detail 'Phase 3 : Assemblage final'
        $fragCount = @($frag).Count
        $mergeMsg = "Fusion des {0} elements PDF... [OK]" -f $fragCount
        if ([string]::IsNullOrWhiteSpace($mergeMsg)) { $mergeMsg = 'Operation en cours' }
        $outFinal = Join-Path $tmpDir 'composed_final.pdf'
        $merged = Merge-CnsPdfFilesForStep5TourneeComposition -InputPdfsOrdered @($frag.ToArray()) -DestinationPdfPath $outFinal
        if (-not $merged) {
            throw '[TOURNEE] Fusion Ghostscript (couvertures + corps) echouee.'
        }
        Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback -Detail ("├── {0}" -f $mergeMsg)

        Copy-Item -LiteralPath $outFinal -Destination $mainAbs -Force
        $nCoverSheets = 1 + @($blocks).Count
        $tourneeMsg = "[TOURNEE] PDF final compose : {0} garde(s) + {1} page(s) corps reorder (Ghostscript reorder inchange)." -f $nCoverSheets, $mainPageCount
        Write-Host $tourneeMsg -ForegroundColor Green
        if (Get-Command Write-PlanningRebuildUiLog -ErrorAction SilentlyContinue) {
            Write-PlanningRebuildUiLog $tourneeMsg
        }
        return $true
    }
    catch {
        Write-Warning ("[TOURNEE] Composition abandonnee : {0}" -f $_.Exception.Message)
        return $false
    }
    finally {
        if ([string]::IsNullOrWhiteSpace($tmpDir) -eq $false -and (Test-Path -LiteralPath $tmpDir)) {
            Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback `
                -Detail '└── Nettoyage des fichiers temporaires... [OK]'
            Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
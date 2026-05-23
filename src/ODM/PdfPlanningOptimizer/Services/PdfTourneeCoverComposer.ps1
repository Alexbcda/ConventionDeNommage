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
        Echappe \, (, ).
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $t = Sanitize-CnsCoverTextForGhostscript -Text $Text
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
        [string]$OutPdfPath
    )
    $prolog = "<< /PageSize [595 842] >> setpagedevice`n"
    $runId = [Guid]::NewGuid().ToString('N')
    $psPath = Join-Path $env:TEMP ("cn_cover_{0}.ps1gen.ps" -f $runId)
    $psDoc = "%!PS-Adobe-3.0`r`n" + $prolog + $PsBodySansShowpage + "`r`nshowpage`r`n"
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

function New-CnsGlobalMismatchCoverPdf {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutPdfPath,
        [Parameter(Mandatory = $true)]
        [int]$TotalOdmCount,
        [Parameter(Mandatory = $true)]
        [int]$UnmatchedOdmCount
    )
    $title = 'Synthese ODM / matching planning'
    $l1 = "Nombre total d'ODM (groupes extraits du PDF) : $TotalOdmCount"
    $l2 = "Nombre d'ODM sans correspondance : $UnmatchedOdmCount"
    $t0 = ConvertTo-CnsPsHelveticaParenBody -Text $title
    $t1 = ConvertTo-CnsPsHelveticaParenBody -Text $l1
    $t2 = ConvertTo-CnsPsHelveticaParenBody -Text $l2
    $body = @"
/Helvetica-Bold findfont 18 scalefont setfont
50 780 moveto
($t0) show
/Helvetica findfont 12 scalefont setfont
50 730 moveto
($t1) show
50 700 moveto
($t2) show
"@
    Write-CnsPostScriptPdfPage -PsBodySansShowpage $body -OutPdfPath $OutPdfPath
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
        'janvier' = 'Janvier'; 'février' = 'Février'; 'fevrier' = 'Février'; 'mars' = 'Mars'; 'avril' = 'Avril'
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
        [int]$MinY
    )
    $parts = New-Object System.Collections.Generic.List[string]
    [int]$y = $StartY
    foreach ($line in @($Lines)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $lit = ConvertTo-CnsPsHelveticaParenBody -Text $line
        [void]$parts.Add("/Helvetica findfont 11 scalefont setfont`n50 $y moveto`n($lit) show")
        $y -= $LineStep
        if ($y -lt $MinY) { break }
    }
    if ($parts.Count -lt 1) { return '' }
    return (($parts.ToArray()) -join "`n")
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
    if ($TourneeIncomplete) {
        $litBanner = ConvertTo-CnsPsHelveticaParenBody -Text 'TOURNEE NON MATCHEE'
        $dateShown = Format-CnsFrenchLongDateForCoverLabels -LongFr (Format-CnsTourneeCoverDateFrLong -DateJJMMAAAA $DateJJMMAAAA)
        $litL1 = ConvertTo-CnsPsHelveticaParenBody -Text ("Date : {0}" -f $dateShown)
        $litL2 = ConvertTo-CnsPsHelveticaParenBody -Text ("Collecteur : {0}" -f $Collecteur)
        $litL3 = ConvertTo-CnsPsHelveticaParenBody -Text ("Vehicule   : {0}" -f $Vehicule)
        $memoPsInc = (Build-CnsCoverTextLinesPostScriptAppend -Lines @($MetierMemoLines) -StartY 655 -LineStep 15 -MinY 72)
        $body = @"
/Helvetica-Bold findfont 14 scalefont setfont
50 800 moveto
($litBanner) show
/Helvetica findfont 12 scalefont setfont
50 760 moveto
($litL1) show
50 725 moveto
($litL2) show
50 690 moveto
($litL3) show
$memoPsInc
"@
        return (Write-CnsPostScriptPdfPage -PsBodySansShowpage $body -OutPdfPath $OutPdfPath)
    }

    $culture = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    $invCc = [System.Globalization.CultureInfo]::InvariantCulture
    [datetime]$dateObj = [datetime]::Today
    $dj = if ($null -eq $DateJJMMAAAA) { '' } else { ([string]$DateJJMMAAAA).Trim() }
    $dateParsedOk = $false
    foreach ($patDj in @('dd/MM/yyyy', 'd/M/yyyy', 'dd/MM/yy')) {
        if ([datetime]::TryParseExact($dj, $patDj, $invCc, [System.Globalization.DateTimeStyles]::None, [ref]$dateObj)) {
            $dateParsedOk = $true
            break
        }
    }
    if (-not $dateParsedOk) {
        [datetime]$tmpDj = $dateObj
        if ([datetime]::TryParse($dj, $culture, [System.Globalization.DateTimeStyles]::None, [ref]$tmpDj)) {
            $dateObj = $tmpDj
            $dateParsedOk = $true
        }
        elseif ([datetime]::TryParse($dj, $invCc, [System.Globalization.DateTimeStyles]::None, [ref]$tmpDj)) {
            $dateObj = $tmpDj
            $dateParsedOk = $true
        }
    }
    $dateFormatted = if ($dateParsedOk) {
        $sFr = $dateObj.ToString('dddd dd MMMM yyyy', $culture)
        if ($sFr.Length -ge 2) { $sFr.Substring(0, 1).ToUpper() + $sFr.Substring(1) } else { $sFr }
    }
    else {
        Format-CnsTourneeCoverDateFrLong -DateJJMMAAAA $DateJJMMAAAA
    }
    $dateFormatted = Format-CnsFrenchLongDateForCoverLabels -LongFr $dateFormatted
    $litL1 = ConvertTo-CnsPsHelveticaParenBody -Text ("Date : {0}" -f $dateFormatted)
    $litL2 = ConvertTo-CnsPsHelveticaParenBody -Text ("Collecteur : {0}" -f $Collecteur)
    $litL3 = ConvertTo-CnsPsHelveticaParenBody -Text ("Vehicule   : {0}" -f $Vehicule)
    $memoPs = (Build-CnsCoverTextLinesPostScriptAppend -Lines @($MetierMemoLines) -StartY 675 -LineStep 15 -MinY 72)

    $body = @"
/Helvetica findfont 12 scalefont setfont
50 780 moveto
($litL1) show
50 745 moveto
($litL2) show
50 710 moveto
($litL3) show
$memoPs
"@
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
        $MatchResult = $null
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

    $frag = [System.Collections.Generic.List[string]]::new()
    $runId = [Guid]::NewGuid().ToString('N')
    $tmpDir = $null
    $tmpDir = Join-Path $env:TEMP ('cn_coverwork_' + $runId)

    try {
        $null = New-Item -ItemType Directory -Path $tmpDir -Force -ErrorAction Stop

        $globalCov = Join-Path $tmpDir 'cover_global.pdf'

        Write-Host '[TOURNEE] Creation page de garde globale (premiere page du PDF final).' -ForegroundColor Cyan
        $gcOk = (New-CnsGlobalMismatchCoverPdf -OutPdfPath $globalCov `
                -TotalOdmCount $totalODM `
                -UnmatchedOdmCount $unmatchedCount )
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

            $coverPath = Join-Path $tmpDir ('cover_blk_{0}.pdf' -f $fi)

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
                        }
                        else {
                            Write-Warning '[TOURNEE] Cover prefixe echouee'
                        }
                    }
                }
            }

            $sliceIx = 0
            for ($pn = [int]$blk.MainFrom1; $pn -le [int]$blk.MainTo1; $pn++) {
                $sliceIx++
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
                        $ceaPdf = Copy-CnsMetierTemplatePdfToWorkDir -TemplateFileName 'CeaPointsDeCollectes.pdf' -WorkDir $tmpDir -DestLeafName ('cea_{0:D3}_{1:D5}.pdf' -f $fi, $sliceIx)
                        if (-not [string]::IsNullOrWhiteSpace($ceaPdf)) {
                            [void]$frag.Add($ceaPdf)
                            Write-Host ("[STEP5-METIER] Document CEA injecte apres page reorder #{0} (RawPage={1})." -f $pn, $rawPnPage) -ForegroundColor Green
                        }
                        else {
                            [void]$ceaInjectedForPage.Remove($rawPnPage)
                        }
                    }
                }
            }

            if ([string]$blk.GroupKey -match '^SEG(\d+)$') {
                $segNumBilan = [int]$Matches[1]
                if (-not $bilanInjectedForSeg.ContainsKey($segNumBilan)) {
                    $bilanInjectedForSeg[$segNumBilan] = $true
                    $bilanPdf = Copy-CnsMetierTemplatePdfToWorkDir -TemplateFileName 'BilanDeCollecte.pdf' -WorkDir $tmpDir -DestLeafName ('bilan_seg_{0:D3}.pdf' -f $fi)
                    if (-not [string]::IsNullOrWhiteSpace($bilanPdf)) {
                        [void]$frag.Add($bilanPdf)
                        Write-Host ("[STEP5-METIER] Bilan de collecte injecte en fin de tournée segment {0} (hors bloc __PRE__)." -f $segNumBilan) -ForegroundColor Green
                    }
                }
            }
        }

        $outFinal = Join-Path $tmpDir 'composed_final.pdf'
        $merged = Merge-CnsPdfFilesForStep5TourneeComposition -InputPdfsOrdered @($frag.ToArray()) -DestinationPdfPath $outFinal
        if (-not $merged) {
            throw '[TOURNEE] Fusion Ghostscript (couvertures + corps) echouee.'
        }

        Copy-Item -LiteralPath $outFinal -Destination $mainAbs -Force
        $nCoverSheets = 1 + @($blocks).Count
        Write-Host ("[TOURNEE] PDF final compose : {0} garde(s) + {1} page(s) corps reorder (Ghostscript reorder inchange)." -f $nCoverSheets, $mainPageCount) -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning ("[TOURNEE] Composition abandonnee : {0}" -f $_.Exception.Message)
        return $false
    }
    finally {
        if ([string]::IsNullOrWhiteSpace($tmpDir) -eq $false -and (Test-Path -LiteralPath $tmpDir)) {
            Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
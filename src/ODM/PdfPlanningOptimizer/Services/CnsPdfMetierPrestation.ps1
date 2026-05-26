# STEP 5 — Détection prestations métier depuis le texte ODM PDF (source de vérité unique).
# Ne pas utiliser MatchResult / ExcelOrder / SpecialFlags pour la logique métier.

. (Join-Path $PSScriptRoot 'PlanningExcelTourneeSegments.ps1')
$_cnsCertWordForMetier = Join-Path $PSScriptRoot 'CnsDestructionCertificateWord.ps1'
if (Test-Path -LiteralPath $_cnsCertWordForMetier) {
    . $_cnsCertWordForMetier
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

function Test-CnsStep5FragSliceRequiresCeaDocument {
    <#
    .SYNOPSIS
        Detection CEA STEP 5 par signaux : pdftotext du slice ODM dans frag (seule source autorisee).
    #>
    param(
        [AllowNull()][AllowEmptyString()][string]$FragSlicePdfPath
    )
    if ([string]::IsNullOrWhiteSpace($FragSlicePdfPath)) { return $false }
    if (-not (Test-Path -LiteralPath $FragSlicePdfPath -PathType Leaf)) { return $false }
    $rawLines = @(Get-CnsStep5PdftotextLinesFromSinglePagePdf -SinglePagePdfPath $FragSlicePdfPath)
    $isCea = (Test-CnsPdfFragPageRequiresCeaDocument -RawLines $rawLines)
    if ($isCea) {
        Write-Host ("[STEP5-CEA] Signaux CEA valides sur slice frag : {0}" -f (Split-Path -Leaf $FragSlicePdfPath)) -ForegroundColor DarkCyan
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
    return $t
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
        elseif ($ln -match 'deee' -or $compact -match 'deee') {
            $detail = 'Collecte DEEE'
        }
        elseif (($ln -match 'cartouche' -and $ln -match 'encre') -or ($compact -match 'cartouche' -and $compact -match 'encre')) {
            $detail = 'Collecte cartouches encre'
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
        elseif ($norm -match 'deee' -or $normCompact -match 'deee') {
            $detail = 'Collecte DEEE'
        }
        elseif (($norm -match 'cartouche' -and $norm -match 'encre') -or ($normCompact -match 'cartouche' -and $normCompact -match 'encre')) {
            $detail = 'Collecte cartouches encre'
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
    $trackLines = New-Object System.Collections.Generic.List[string]

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
            [string]$det = [string]$tr.Detail
            [string]$cl = Repair-CnsClientDisplayNameForCover -Text ([string]$tr.Client)
            if ([string]::IsNullOrWhiteSpace($det)) { continue }
            if ([string]::IsNullOrWhiteSpace($cl)) { $cl = 'Non specifie' }
            $key = ('{0}|{1}' -f $det, $cl)
            if ($trackSeen.Add($key)) {
                [void]$trackLines.Add(("{0} - {1}" -f $det, $cl))
            }
        }
    }

    $out = New-Object System.Collections.Generic.List[string]
    foreach ($dc in @($destructionClients)) {
        [void]$out.Add(("Certificat de destruction : {0}" -f $dc))
    }
    foreach ($tl in @($trackLines)) {
        [void]$out.Add($tl)
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

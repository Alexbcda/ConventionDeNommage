# ============================================================
# PdfExtractor.ps1
# Rôle : Extraire le texte brut d'un PDF, découpé en lignes par page.
$script:_cnGhostResolve = Join-Path $PSScriptRoot '..\..\..\Core\GhostscriptResolve.ps1'
if (Test-Path -LiteralPath $script:_cnGhostResolve) { . $script:_cnGhostResolve }
# Pipeline unique : pdftotext (-enc UTF-8) → lecture UTF-8 (Get-Content -Encoding UTF8) ;
# si validation UTF-8 stricte échoue ou caractères de remplacement : correction unique
# UTF8.GetString( CP1252.GetBytes( CP1252.GetString(octets) ) ) sur les octets du fichier temporaire.
# Diagnostic hors flux : Debug\PdfRawEncodingInspector.ps1
# Découpage : une page = un tableau de lignes (pdftotext -layout) ; l’alignement sémantique client/adresse
# relève d’EntityExtractor (parsing par blocs), pas du moteur ligne à ligne ici.
#
# Observabilité (diagnostic) : $env:PDF_SCORING = "1" sur EntityExtractor\ConvertTo-PageEntity
# (score par page vs RawLines) + cumul. Avant de parcourir un PDF : Reset-PdfExtractionScoringSession ;
# après toutes les pages : Write-PdfExtractionScoringSessionGlobalReport (fichier EntityExtractor.ps1).
#
# Performance : cache mémoire par session Invoke-PdfExtraction uniquement ($script:PdftotextIntraRunLineCache ;
# clé = chemin résolu + n° page + args pdftotext). Évite notamment la 7ᵉ invocation pdftotext page 1
# (après Select-Best sur les mêmes arguments). Réinitialisation en entrée/sortie d'Invoke-PdfExtraction.
# ============================================================

# pdftotext : -enc UTF-8 ; lecture + reparation CP1252 ci-dessous. Normalisation UI (Convert-ToUiText) en sortie.
$_pdfUiText = Join-Path $PSScriptRoot '..\..\..\Common\UiText.ps1'
if (Test-Path -LiteralPath $_pdfUiText) {
    if (-not (Get-Command Convert-ToUiText -ErrorAction SilentlyContinue)) {
        . $_pdfUiText
    }
}

function script:Convert-PdfLineTextForUiIfAvailable {
    param([string[]]$Lines)
    if ($null -eq $Lines) {
        return @()
    }
    if (-not (Get-Command Convert-ToUiText -ErrorAction SilentlyContinue)) {
        return $Lines
    }
    return @(
        foreach ($ln in @($Lines)) {
            if ($null -eq $ln) {
                ''
            }
            else {
                Convert-ToUiText -Text ([string]$ln)
            }
        }
    )
}

function script:Remove-Utf8BomFromByteArray {
    param([byte[]]$Bytes)
    if ($null -eq $Bytes -or $Bytes.Length -lt 3) {
        return $Bytes
    }
    if ($Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        if ($Bytes.Length -eq 3) {
            return [byte[]]@()
        }
        $n = $Bytes.Length - 3
        $out = [byte[]]::new($n)
        [Array]::Copy($Bytes, 3, $out, 0, $n)
        return $out
    }
    return $Bytes
}

function script:Test-PdfFileBytesAreStrictUtf8 {
    param([byte[]]$Bytes)
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) {
        return $true
    }
    $enc = [System.Text.UTF8Encoding]::new($false, $true)
    try {
        $null = $enc.GetString($Bytes)
        return $true
    }
    catch {
        return $false
    }
}

function script:Test-PdfUtf8DecodedTextHasReplacementChar {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) {
        return $false
    }
    return ($Text.IndexOf([char]0xFFFD) -ge 0)
}

function script:Repair-PdfTextUtf8ViaCp1252BytesRoundtrip {
    <#
    Interprète les octets comme Windows-1252 puis ré-encode en octets CP1252 et décode en UTF-8.
    Corrige le cas « UTF-8 lu comme CP1252 » (double interprétation).
    #>
    param([byte[]]$Bytes)
    $cp1252 = [System.Text.Encoding]::GetEncoding(1252)
    $utf8 = [System.Text.Encoding]::UTF8
    $payload = Remove-Utf8BomFromByteArray -Bytes $Bytes
    if ($null -eq $payload -or $payload.Length -eq 0) {
        return @()
    }
    $misread = $cp1252.GetString($payload)
    $roundBytes = $cp1252.GetBytes($misread)
    $text = $utf8.GetString($roundBytes)
    return @($text -split "`r?`n", [System.StringSplitOptions]::None)
}

function script:Read-PdftotextOutputFileAsUtf8Lines {
    <#
    Lit le fichier texte produit par pdftotext : d'abord Get-Content -Encoding UTF8 ;
    si UTF-8 strict invalide ou U+FFFD dans le texte lu, applique la réparation CP1252→UTF-8 unique.
    #>
    param([string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        return @(Convert-PdfLineTextForUiIfAvailable -Lines @())
    }

    $bytes = [System.IO.File]::ReadAllBytes($LiteralPath)
    $bytesNoBom = Remove-Utf8BomFromByteArray -Bytes $bytes

    $primaryLines = @()
    try {
        $primaryLines = @(Get-Content -LiteralPath $LiteralPath -Encoding UTF8)
    }
    catch {
        return @(Convert-PdfLineTextForUiIfAvailable -Lines @(Repair-PdfTextUtf8ViaCp1252BytesRoundtrip -Bytes $bytes))
    }

    $joined = if ($primaryLines.Count -eq 0) { '' } else { ($primaryLines -join "`n") }
    $strictOk = Test-PdfFileBytesAreStrictUtf8 -Bytes $bytesNoBom
    $hasRepl = Test-PdfUtf8DecodedTextHasReplacementChar -Text $joined

    if ($strictOk -and -not $hasRepl) {
        return @(Convert-PdfLineTextForUiIfAvailable -Lines $primaryLines)
    }

    return @(Convert-PdfLineTextForUiIfAvailable -Lines @(Repair-PdfTextUtf8ViaCp1252BytesRoundtrip -Bytes $bytes))
}

function Get-PdfExtractedUtf8LinesFromFile {
    <#
    .SYNOPSIS
    Applique la même lecture UTF-8 (+ réparation unique si besoin) que pour la sortie pdftotext.
    Exposé pour les tests (Test-Aggregation.ps1).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    return @(Read-PdftotextOutputFileAsUtf8Lines -LiteralPath $resolved)
}

function script:Test-PdfPageCountDebug {
    return ($env:PDF_PAGECOUNT_DEBUG -in @('1', 'true'))
}

function script:Write-PdfPageCountDebug {
    param([string]$Message)
    if (script:Test-PdfPageCountDebug) {
        Write-Host ("[PDF-PAGECOUNT] {0}" -f $Message) -ForegroundColor DarkCyan
    }
}

function script:Parse-GhostscriptPdfPageCountStrict {
    <#
    N'accepte pas le premier nombre arbitraire dans toute la sortie : lignes pertinentes uniquement,
    valeurs strictement positives et < seuil GS (sécurité bruit banners / IDS).
    #>
    param(
        [string]$JoinedText,
        [int]$GsMaxInclusive = 4999
    )
    if ([string]::IsNullOrWhiteSpace($JoinedText)) { return $null }

    $lines = $JoinedText -split "`r?`n"

    foreach ($ln in @($lines)) {
        $ll = "$ln".Trim()
        if ($ll.Length -eq 0) { continue }
        if (-not ($ll -match '(?i)page\s*count|pdf\s*pages?|pdfpagecount')) {
            continue
        }
        foreach ($mm in [regex]::Matches($ll, '(?<!\d)(\d{1,9})(?!\d)')) {
            $v = 0
            if (-not [int]::TryParse($mm.Value, [ref]$v)) { continue }
            if ($v -ge 1 -and $v -le $GsMaxInclusive) {
                return $v
            }
        }
    }

    $solitaryInts = foreach ($ln in @($lines)) {
        $t = "$ln".Trim()
        if ($t.Length -eq 0 -or "$t".Length -gt 14) { continue }
        if ($t -match '^\d{1,9}$') {
            [int]$t
        }
    }
    $solitaryInts = @($solitaryInts)
    if ($solitaryInts.Count -eq 1) {
        $v = $solitaryInts[0]
        if ($v -ge 1 -and $v -le $GsMaxInclusive) { return $v }
    }

    for ($idx = ($lines.Length - 1); $idx -ge 0; $idx--) {
        $t = "$($lines[$idx])".Trim()
        if ($t.Length -eq 0 -or "$t".Length -gt 14) { continue }
        if ($t -match '^\d{1,9}$') {
            $v = [int]$t
            if ($v -ge 1 -and $v -le $GsMaxInclusive) {
                return $v
            }
            break
        }
    }

    return $null
}

function script:Get-PdfPageCountInternal {
    param([string]$FichierPDF)

    if (-not (Test-Path -LiteralPath $FichierPDF)) {
        return 0
    }

    $maxTrustedPagesPdfinfoScan = 50000
    $gsMaxInclusive = 4999
    script:Write-PdfPageCountDebug -Message "--- Get-PdfPageCountInternal start ---"

    $pdfinfo = Get-Command pdfinfo.exe -ErrorAction SilentlyContinue
    if ($pdfinfo -and $pdfinfo.Source) {
        try {
            $info = & $pdfinfo.Source $FichierPDF 2>&1
            $text = if ($info -is [array]) { $info -join "`n" } else { [string]$info }
            $infoClip = if ($text.Length -le 1200) { $text } else { $text.Substring(0, 1200) }
            script:Write-PdfPageCountDebug -Message ('pdfinfo raw (truncate 1200)="{0}"' -f ($infoClip -replace "[\r\n]+", ' '))

            $m = [regex]::Match($text, '(?im)^Pages:\s*(\d+)\s*$')
            if (-not $m.Success) {
                $m = [regex]::Match($text, '(?im)Pages\s*[:=]\s*(\d+)')
            }
            if ($m.Success) {
                $pv = [int]$m.Groups[1].Value
                script:Write-PdfPageCountDebug -Message ('pdfinfo candidate={0}' -f $pv)
                if ($pv -ge 1 -and $pv -le $maxTrustedPagesPdfinfoScan) {
                    script:Write-PdfPageCountDebug -Message ('METHOD=pdfinfo FINAL={0}' -f $pv)
                    return $pv
                }
                script:Write-PdfPageCountDebug -Message 'pdfinfo reject: out of trusted range'
            }
        }
        catch {
            script:Write-PdfPageCountDebug -Message ('pdfinfo exception: {0}' -f $_.Exception.Message)
        }
    }
    else {
        script:Write-PdfPageCountDebug -Message 'pdfinfo: not on PATH / not found'
    }

    $gsCandidate = $null
    if (Get-Command Get-ResolvedGhostscriptPath -ErrorAction SilentlyContinue) {
        $gsPath = Get-ResolvedGhostscriptPath
        if ($gsPath) {
            try {
                $psPath = $FichierPDF -replace '\\', '/'
                $output = & $gsPath -dNODISPLAY -q -c "($psPath) (r) file runpdfbegin pdfpagecount = quit" 2>&1
                $joined = if ($output -is [array]) { $output -join "`n" } else { [string]$output }
                $clip = $joined
                if ($clip.Length -gt 2000) { $clip = $clip.Substring(0, 2000) + '...' }
                script:Write-PdfPageCountDebug -Message ('GS raw (trunc)="{0}"' -f ($clip -replace "[\r\n]+", ' | '))

                $gsCandidate = script:Parse-GhostscriptPdfPageCountStrict -JoinedText $joined -GsMaxInclusive $gsMaxInclusive
                if ($null -ne $gsCandidate) {
                    script:Write-PdfPageCountDebug -Message ('GS candidate (strict)={0}' -f $gsCandidate)
                    script:Write-PdfPageCountDebug -Message ('METHOD=ghostscript FINAL={0}' -f $gsCandidate)
                    return [int]$gsCandidate
                }
                script:Write-PdfPageCountDebug -Message 'GS: no strict match - fallback next'
            }
            catch {
                script:Write-PdfPageCountDebug -Message ('GS exception: {0}' -f $_.Exception.Message)
            }
        }
        else {
            script:Write-PdfPageCountDebug -Message 'Ghostscript path not resolved'
        }
    }

    $scanVal = Get-PdfPageCountFromRawScan -FichierPDF $FichierPDF
    script:Write-PdfPageCountDebug -Message ('scan /Count MAX candidate={0}' -f $scanVal)
    if ($scanVal -ge 1 -and $scanVal -le $maxTrustedPagesPdfinfoScan) {
        script:Write-PdfPageCountDebug -Message ('METHOD=rawscan FINAL={0}' -f $scanVal)
    }
    else {
        script:Write-PdfPageCountDebug -Message 'METHOD=rawscan rejected or zero'
    }
    return $scanVal
}

function script:Get-PdfPageCountFromRawScan {
    param([string]$FichierPDF)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($FichierPDF)
        if ($bytes.Length -lt 16) { return 0 }

        $enc = [System.Text.Encoding]::GetEncoding(28591)
        $chunks = [System.Collections.Generic.List[byte[]]]::new()
        $headLen = [Math]::Min($bytes.Length, 524288)
        $chunks.Add($bytes[0..($headLen - 1)])
        if ($bytes.Length -gt $headLen) {
            $tailLen = [Math]::Min($bytes.Length, 524288)
            $chunks.Add($bytes[($bytes.Length - $tailLen)..($bytes.Length - 1)])
        }
        if ($bytes.Length -gt ($headLen + $tailLen + 4096)) {
            $midSpan = [Math]::Min(262144, $bytes.Length)
            $midStart = [Math]::Max(0, [int][Math]::Floor($bytes.Length / 2.0) - [int][Math]::Floor($midSpan / 2.0))
            $midEnd = [Math]::Min($bytes.Length - 1, $midStart + $midSpan - 1)
            if ($midEnd -ge $midStart) {
                $chunks.Add($bytes[$midStart..$midEnd])
            }
        }

        $best = 0
        foreach ($chunk in $chunks) {
            $raw = $enc.GetString($chunk)
            foreach ($m in [regex]::Matches($raw, '/Count\s+(\d+)')) {
                $n = 0
                if (-not [int]::TryParse($m.Groups[1].Value, [ref]$n)) { continue }
                if ($n -gt 0 -and $n -le 50000 -and $n -gt $best) {
                    $best = $n
                }
            }
        }
        return $best
    }
    catch {
        return 0
    }
}

function script:Get-ResolvedPdfToTextPath {
    <#
    Résout pdftotext.exe selon un ordre strict :
      1) PDFTOTEXT_PATH
      2) PATH machine (si PDFTOTEXT_ALLOW_PATH actif)
      3) chemins standards repo / Program Files / WinGet
    #>
    [CmdletBinding()]
    param(
        [ref]$TraceOut = ([ref]$null)
    )

    $trace = [System.Collections.Generic.List[string]]::new()
    $debugResolve = ($env:CN_DEBUG_PIPELINE -in @('1', 'true'))
    $repoRoot = $PSScriptRoot
    for ($i = 0; $i -lt 4; $i++) {
        $repoRoot = Split-Path -Parent $repoRoot
    }

    $allowPathRaw = [string]$env:PDFTOTEXT_ALLOW_PATH
    $allowPath = -not [string]::IsNullOrWhiteSpace($allowPathRaw) -and ($allowPathRaw.Trim().ToLowerInvariant() -in @('1', 'true', 'yes', 'on'))

    [void]$trace.Add(("PDFTOTEXT_PATH={0}" -f [string]$env:PDFTOTEXT_PATH))
    [void]$trace.Add(("PDFTOTEXT_ALLOW_PATH={0} (enabled={1})" -f $allowPathRaw, $allowPath))
    if ($debugResolve) {
        Write-Host "[PDF] Checking Poppler explicit path..." -ForegroundColor Cyan
    }

    $popplerExplicit = 'C:\Users\alexa\Downloads\Release-25.12.0-0\poppler-25.12.0\Library\bin\pdftotext.exe'
    if (Test-Path -LiteralPath $popplerExplicit -PathType Leaf) {
        $resolvedExplicit = (Resolve-Path -LiteralPath $popplerExplicit).Path
        [void]$trace.Add(("EXPLICIT hit: {0}" -f $resolvedExplicit))
        if ($TraceOut) { $TraceOut.Value = @($trace.ToArray()) }
        return $resolvedExplicit
    }
    [void]$trace.Add(("EXPLICIT miss: {0}" -f $popplerExplicit))

    $fromEnv = [string]$env:PDFTOTEXT_PATH
    if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
        $envPath = $fromEnv.Trim().Trim('"')
        if (Test-Path -LiteralPath $envPath -PathType Container) {
            $envPath = Join-Path $envPath 'pdftotext.exe'
            [void]$trace.Add(("ENV dir -> {0}" -f $envPath))
        }
        if (-not (Test-Path -LiteralPath $envPath -PathType Leaf)) {
            [void]$trace.Add(("ENV missing: {0}" -f $envPath))
            throw "PDFTOTEXT_PATH invalide (fichier introuvable)."
        }
        if ((Split-Path -Leaf $envPath).ToLowerInvariant() -cne 'pdftotext.exe') {
            [void]$trace.Add(("ENV bad name: {0}" -f $envPath))
            throw "PDFTOTEXT_PATH doit pointer vers pdftotext.exe uniquement."
        }
        if ([System.IO.Path]::GetExtension($envPath).ToLowerInvariant() -cne '.exe') {
            [void]$trace.Add(("ENV bad extension: {0}" -f $envPath))
            throw "Fichier non exécutable interdit."
        }
        $resolvedEnv = (Resolve-Path -LiteralPath $envPath).Path
        [void]$trace.Add(("ENV hit: {0}" -f $resolvedEnv))
        if ($TraceOut) { $TraceOut.Value = @($trace.ToArray()) }
        return $resolvedEnv
    }

    if ($allowPath) {
        if ($debugResolve) {
            Write-Host "[PDF] Checking PATH..." -ForegroundColor Cyan
        }
        $cmd = Get-Command pdftotext.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $cmd -and -not [string]::IsNullOrWhiteSpace($cmd.Source) -and (Test-Path -LiteralPath $cmd.Source -PathType Leaf)) {
            [void]$trace.Add(("PATH hit: {0}" -f $cmd.Source))
            if ($TraceOut) { $TraceOut.Value = @($trace.ToArray()) }
            return [string]$cmd.Source
        }
        [void]$trace.Add("PATH miss: Get-Command pdftotext.exe")
    }
    else {
        [void]$trace.Add("PATH check skipped (PDFTOTEXT_ALLOW_PATH disabled)")
    }

    if ($debugResolve) {
        Write-Host "[PDF] Checking fallback directories..." -ForegroundColor Cyan
    }
    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @(
            (Join-Path $repoRoot 'tools\Poppler\Library\bin\pdftotext.exe'),
            (Join-Path $repoRoot 'tools\pdftotext.exe'),
            (Join-Path $repoRoot 'vendor\poppler\Library\bin\pdftotext.exe'),
            "${env:LOCALAPPDATA}\Microsoft\WinGet\Links\pdftotext.exe",
            'C:\Program Files\Xpdf\pdftotext.exe'
        )) {
        if (-not [string]::IsNullOrWhiteSpace($p)) { [void]$candidates.Add($p) }
    }
    foreach ($base in @($env:ProgramFiles, $env:ProgramFilesx86, ${env:ProgramFiles(x86)})) {
        if ([string]::IsNullOrWhiteSpace([string]$base)) { continue }
        $popplerRoot = Join-Path $base 'poppler'
        if (-not (Test-Path -LiteralPath $popplerRoot -PathType Container)) {
            [void]$trace.Add(("STD miss root: {0}" -f $popplerRoot))
            continue
        }
        $direct = Join-Path $popplerRoot 'Library\bin\pdftotext.exe'
        [void]$candidates.Add($direct)
        foreach ($d in @(Get-ChildItem -LiteralPath $popplerRoot -Directory -ErrorAction SilentlyContinue)) {
            [void]$candidates.Add((Join-Path $d.FullName 'Library\bin\pdftotext.exe'))
        }
    }

    $seen = @{}
    foreach ($cand in $candidates) {
        if ([string]::IsNullOrWhiteSpace($cand)) { continue }
        $k = $cand.ToLowerInvariant()
        if ($seen.ContainsKey($k)) { continue }
        $seen[$k] = $true
        if (Test-Path -LiteralPath $cand -PathType Leaf) {
            $resolved = (Resolve-Path -LiteralPath $cand).Path
            [void]$trace.Add(("STD hit: {0}" -f $resolved))
            if ($TraceOut) { $TraceOut.Value = @($trace.ToArray()) }
            return $resolved
        }
        [void]$trace.Add(("STD miss: {0}" -f $cand))
    }

    if ($TraceOut) { $TraceOut.Value = @($trace.ToArray()) }
    return $null
}

function script:Resolve-PdfTotextPath {
    try {
        return Get-ResolvedPdfToTextPath
    }
    catch {
        if ($_.Exception.Message -like 'PDFTOTEXT_PATH*') {
            throw
        }
        return $null
    }
}

# --- Diagnostic extraction PDF (liste partagée + PDF_DEBUG / -PdfDebug sur Invoke-PdfExtraction) ---
$script:PdfExtractionDiagList = $null
$script:PdfExtractDebugSession = $false

function script:Test-PdfExtractDebugEnabled {
    if ($true -eq $script:PdfExtractDebugSession) {
        return $true
    }
    $v = [string]$env:PDF_DEBUG
    if ([string]::IsNullOrWhiteSpace($v)) {
        return $false
    }
    return $v.Trim() -notmatch '^(0|false|no|off)$'
}

function script:Add-PdfExtractionDiagLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [switch]$DebugOnly
    )
    if ($DebugOnly -and -not (Test-PdfExtractDebugEnabled)) {
        return
    }
    if ($null -ne $script:PdfExtractionDiagList) {
        [void]$script:PdfExtractionDiagList.Add($Message)
    }
    if (Test-PdfExtractDebugEnabled) {
        Write-Verbose $Message
    }
}

function script:Format-PdftotextArgsForLog {
    param([string[]]$ArgList)
    $parts = foreach ($a in $ArgList) {
        if ($null -eq $a) { continue }
        $s = [string]$a
        if ($s -match '[\s"]') { '"{0}"' -f ($s -replace '"', '\"') } else { $s }
    }
    return ($parts -join ' ')
}

function script:Read-PdfPdftotextStderrFileText {
    <#
    PowerShell peut rediriger stderr natif en UTF-16 LE ; lecture tolérante (UTF-16 BOM / UTF-8 / UTF-8 sans BOM).
    #>
    param([string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        return ''
    }
    $bytes = [System.IO.File]::ReadAllBytes($LiteralPath)
    if ($null -eq $bytes -or $bytes.Length -eq 0) {
        return ''
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes)
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    }
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function script:Join-PdfLinesToText {
    param([string[]]$Lines)
    if (-not $Lines -or $Lines.Count -eq 0) { return '' }
    $arr = foreach ($x in @($Lines)) {
        if ($null -eq $x) { '' } else { [string]$x }
    }
    return [string]::Join([Environment]::NewLine, [string[]]@($arr))
}

function script:Measure-PdfLinesExtractionScore {
    param([string[]]$Lines)
    if (-not $Lines -or $Lines.Count -eq 0) { return 0 }
    $join = Join-PdfLinesToText -Lines $Lines
    if ($join.Length -eq 0) { return 0 }
    $nonEmpty = @($Lines | Where-Object { $_ -and $_.Trim().Length -gt 1 })
    $letterDigit = ([regex]::Matches($join, '[\p{L}0-9]')).Count
    $substantial = @($nonEmpty | Where-Object { $_.Trim().Length -ge 6 }).Count
    return [int]([Math]::Min(50000, $join.Length) + 2 * $letterDigit + 15 * $substantial)
}

function script:Get-PdftotextIntraRunCacheKey {
    param(
        [string]$PdfPath,
        [int]$PageNumber,
        [AllowEmptyCollection()]
        [string[]]$ExtraArgs
    )
    $normPath = ''
    try {
        $normPath = [System.IO.Path]::GetFullPath($PdfPath)
    }
    catch {
        $normPath = [string]$PdfPath
    }
    $keyExtraSep = "`u{001E}"
    $frag = [System.Collections.Generic.List[string]]::new()
    if ($ExtraArgs) {
        foreach ($a in $ExtraArgs) {
            if (-not [string]::IsNullOrWhiteSpace($a)) {
                [void]$frag.Add(($a.Trim()))
            }
        }
    }
    $argsKey = ''
    if ($frag.Count -gt 0) {
        $argsKey = [string]::Join($keyExtraSep, $frag.ToArray())
    }
    return ($normPath + "`t" + "$PageNumber" + "`t" + $argsKey)
}

function script:Parse-PdftotextBboxHtmlWords {
    param([string]$Html)
    $words = [System.Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrWhiteSpace($Html)) { return $words.ToArray() }
    $rx = [regex]'<word\s+xMin="([^"]+)"\s+yMin="([^"]+)"\s+xMax="([^"]+)"\s+yMax="([^"]+)">([^<]*)</word>'
    foreach ($m in $rx.Matches($Html)) {
        $t = [string]$m.Groups[5].Value
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        [void]$words.Add([pscustomobject]@{
            XMin = [double]$m.Groups[1].Value
            YMin = [double]$m.Groups[2].Value
            Text = $t
        })
    }
    return $words.ToArray()
}

function script:Build-LinesFromPdfBboxWords {
    <#
    Regroupe les mots par Y (arrondi 5 pt), trie X croissant, concatene avec espace.
    #>
    param(
        [object[]]$Words,
        [double]$YTolerance = 5.0
    )
    if (-not $Words -or $Words.Count -eq 0) { return @() }
    $groups = @{}
    foreach ($w in @($Words)) {
        if ($null -eq $w) { continue }
        $yKey = [Math]::Round([double]$w.YMin / $YTolerance) * $YTolerance
        if (-not $groups.ContainsKey($yKey)) {
            $groups[$yKey] = [System.Collections.Generic.List[object]]::new()
        }
        [void]$groups[$yKey].Add($w)
    }
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($yKey in @($groups.Keys | Sort-Object)) {
        $rowWords = @($groups[$yKey] | Sort-Object { [double]$_.XMin })
        $parts = [System.Collections.Generic.List[string]]::new()
        foreach ($rw in $rowWords) {
            $t = Get-TrimmedOrNull ([string]$rw.Text)
            if (-not [string]::IsNullOrWhiteSpace($t)) { [void]$parts.Add($t) }
        }
        if ($parts.Count -gt 0) {
            [void]$lines.Add(($parts.ToArray() -join ' '))
        }
    }
    return @([string[]]@($lines.ToArray()))
}

function script:Get-TrimmedOrNull {
    param([string]$Value)
    if ($null -eq $Value) { return $null }
    $t = $Value.Trim()
    if ($t.Length -eq 0) { return $null }
    return $t
}

function script:Get-PdfPageBboxHtmlWithPdftotext {
    param(
        [string]$PdfPath,
        [string]$PdftotextExe,
        [int]$PageNumber,
        [string]$LogContext = ''
    )
    $ctx = if ([string]::IsNullOrWhiteSpace($LogContext)) { 'pdftotext-bbox' } else { $LogContext }
    if ([string]::IsNullOrWhiteSpace($PdftotextExe) -or -not (Test-Path -LiteralPath $PdftotextExe -PathType Leaf)) {
        return $null
    }
    $tempOut = [System.IO.Path]::GetTempFileName()
    try {
        $arguments = @(
            '-f', "$PageNumber",
            '-l', "$PageNumber",
            '-bbox',
            '-enc', 'UTF-8',
            '-q',
            $PdfPath,
            $tempOut
        )
        $null = & $PdftotextExe $arguments 2>$null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tempOut)) { return $null }
        $bytes = [System.IO.File]::ReadAllBytes($tempOut)
        if ($null -eq $bytes -or $bytes.Length -eq 0) { return $null }
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    }
    finally {
        if (Test-Path -LiteralPath $tempOut) {
            Remove-Item -LiteralPath $tempOut -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-PdfPageClientNameLinesFromBbox {
    <#
    .SYNOPSIS
        Lignes logiques reconstruites depuis pdftotext -bbox (ordre Y, mots tries par X).
        Retourne @() si bbox indisponible (pas de repli layout ici).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PdfPath,
        [Parameter(Mandatory = $true)]
        [string]$PdftotextExe,
        [Parameter(Mandatory = $true)]
        [int]$PageNumber
    )
    $html = Get-PdfPageBboxHtmlWithPdftotext -PdfPath $PdfPath -PdftotextExe $PdftotextExe -PageNumber $PageNumber `
        -LogContext ('ClientName bbox page=' + $PageNumber)
    if ([string]::IsNullOrWhiteSpace($html)) { return @() }
    $words = @(Parse-PdftotextBboxHtmlWords -Html $html)
    if ($words.Count -lt 1) { return @() }
    $lines = @(Build-LinesFromPdfBboxWords -Words $words)
    return @(Convert-PdfLineTextForUiIfAvailable -Lines $lines)
}

function Split-PdfMonolithicClientNameLayoutLines {
    <#
    .SYNOPSIS
        Scinde une ligne layout fusionnee (prestation + date + nom N°) en lignes logiques pour traversal.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$LayoutLines
    )
    if (-not $LayoutLines -or $LayoutLines.Count -lt 1) { return @() }

    $prestationPat = '(?i)\b(collecte|deee|piles?|cartouche(s)?|encre)\b'
    $datePat = '\d{1,2}/\d{1,2}/\d{2,4}(?:\s*,\s*\d{1,2}:\d{2}\s*(?:AM|PM)?)?'
    $numeroPat = '(?i)N\s*(?:[°\u00B0\u00BA?]|┬░|\uFFFD)?\s*\d{4,12}'

    $out = New-Object System.Collections.Generic.List[string]
    foreach ($raw in @($LayoutLines)) {
        if ($null -eq $raw) { continue }
        $line = ([string]$raw).Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $canSplit = ($line -match $prestationPat) -and ($line -match $datePat) -and ($line -match $numeroPat)
        if (-not $canSplit) {
            [void]$out.Add($line)
            continue
        }

        $dm = [regex]::Match($line, $datePat)
        if (-not $dm.Success) {
            [void]$out.Add($line)
            continue
        }

        $beforeDate = $line.Substring(0, $dm.Index).Trim()
        $afterDate = $line.Substring($dm.Index + $dm.Length).Trim()
        $prestationLine = $beforeDate.TrimEnd(' ', '-', '–', '—', ',', ';')
        $nameLine = $afterDate.TrimStart(' ', '-', '–', '—', ',', ';').Trim()

        if ([string]::IsNullOrWhiteSpace($prestationLine) -or [string]::IsNullOrWhiteSpace($nameLine)) {
            [void]$out.Add($line)
            continue
        }
        if ($nameLine -notmatch $numeroPat) {
            [void]$out.Add($line)
            continue
        }

        [void]$out.Add($prestationLine)
        [void]$out.Add($nameLine)
    }

    if ($out.Count -lt 1) { return @() }
    return @($out.ToArray())
}

function script:Get-PdfPageLinesWithPdftotextArgs {
    param(
        [string]$PdfPath,
        [string]$PdftotextExe,
        [int]$PageNumber,
        [string[]]$ExtraArgs,

        [string]$LogContext = ''
    )

    $ctx = if ([string]::IsNullOrWhiteSpace($LogContext)) { 'pdftotext' } else { $LogContext }

    $lineCache = $script:PdftotextIntraRunLineCache
    $cacheKey = $null
    if ($null -ne $lineCache -and ($lineCache -is [hashtable])) {
        $cacheKey = (Get-PdftotextIntraRunCacheKey -PdfPath $PdfPath -PageNumber $PageNumber -ExtraArgs $ExtraArgs)
        $cachedHit = $lineCache[$cacheKey]
        if ($null -ne $cachedHit -and ($cachedHit -is [System.Array])) {
            return [string[]]@($cachedHit)
        }
    }

    $tempOut = [System.IO.Path]::GetTempFileName()
    $stderrPath = "$tempOut.stderr.txt"

    try {
        if ([string]::IsNullOrWhiteSpace($PdftotextExe)) {
            Add-PdfExtractionDiagLine -Message ("[{0}] ECHEC: PdftotextExe vide." -f $ctx)
            return @()
        }
        if (-not (Test-Path -LiteralPath $PdftotextExe -PathType Leaf)) {
            Add-PdfExtractionDiagLine -Message ("[{0}] ECHEC: PdftotextExe introuvable ou non fichier: {1}" -f $ctx, $PdftotextExe)
            return @()
        }

        $arguments = @(
            '-f', "$PageNumber",
            '-l', "$PageNumber",
            '-enc', 'UTF-8',
            '-q'
        )
        if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
            foreach ($a in $ExtraArgs) {
                if (-not [string]::IsNullOrWhiteSpace($a)) {
                    $arguments += $a.Trim()
                }
            }
        }
        $arguments += $PdfPath
        $arguments += $tempOut

        $argLine = Format-PdftotextArgsForLog -ArgList $arguments
        Add-PdfExtractionDiagLine -Message ("[{0}] pdftotext.exe={1}" -f $ctx, $PdftotextExe) -DebugOnly
        Add-PdfExtractionDiagLine -Message ("[{0}] args: {1}" -f $ctx, $argLine) -DebugOnly
        Add-PdfExtractionDiagLine -Message ("[{0}] tempOut={1}" -f $ctx, $tempOut) -DebugOnly

        if (Test-Path -LiteralPath $stderrPath) {
            Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
        }

        $null = & $PdftotextExe $arguments 2>$stderrPath
        $exitCode = $LASTEXITCODE

        $stderrText = ''
        if (Test-Path -LiteralPath $stderrPath) {
            try {
                $stderrText = Read-PdfPdftotextStderrFileText -LiteralPath $stderrPath
            }
            catch {
                $stderrText = '(lecture stderr impossible)'
            }
        }

        if ($stderrText.Length -gt 4000) {
            $stderrText = $stderrText.Substring(0, 4000) + '...'
        }
        $stderrOneLine = ($stderrText -replace "`r?`n", ' | ').Trim()
        if ($stderrOneLine.Length -gt 0) {
            Add-PdfExtractionDiagLine -Message ("[{0}] stderr: {1}" -f $ctx, $stderrOneLine)
        }

        Add-PdfExtractionDiagLine -Message ("[{0}] LASTEXITCODE={1}" -f $ctx, $exitCode)

        if (-not (Test-Path -LiteralPath $tempOut)) {
            Add-PdfExtractionDiagLine -Message ("[{0}] ECHEC: fichier sortie temp introuvable apres pdftotext." -f $ctx)
            return @()
        }

        $outLen = (Get-Item -LiteralPath $tempOut).Length
        Add-PdfExtractionDiagLine -Message ("[{0}] tempOut taille_octets={1}" -f $ctx, $outLen)
        if ($outLen -eq 0) {
            Add-PdfExtractionDiagLine -Message ("[{0}] AVERTISSEMENT: sortie pdftotext vide (0 octet) — PDF image ou erreur silencieuse cote moteur." -f $ctx)
        }

        if ($exitCode -ne 0) {
            Add-PdfExtractionDiagLine -Message ("[{0}] ECHEC pdftotext: code retour {1}. Sortie texte ignoree (0 ligne)." -f $ctx, $exitCode)
            return @()
        }

        $lines = @(Read-PdftotextOutputFileAsUtf8Lines -LiteralPath $tempOut)
        Add-PdfExtractionDiagLine -Message ("[{0}] lecture UTF-8: {1} ligne(s)" -f $ctx, $lines.Count)

        if ((Test-PdfExtractDebugEnabled) -and $lines.Count -gt 0) {
            $maxPreview = [Math]::Min(3, $lines.Count)
            $preview = @()
            for ($pi = 0; $pi -lt $maxPreview; $pi++) {
                $one = [string]$lines[$pi]
                if ($one.Length -gt 200) { $one = $one.Substring(0, 200) + '...' }
                $preview += ('L{0}: {1}' -f ($pi + 1), $one)
            }
            Add-PdfExtractionDiagLine -Message ("[{0}] apercu_lignes: {1}" -f $ctx, ($preview -join ' || ')) -DebugOnly
        }

        if ($null -ne $lineCache -and ($lineCache -is [hashtable]) -and ($null -ne $cacheKey) -and $exitCode -eq 0) {
            [string[]]$toStore = @(
                foreach ($lnItem in @($lines)) {
                    if ($null -eq $lnItem) { '' } else { [string]$lnItem }
                }
            )
            $lineCache[$cacheKey] = $toStore
        }

        return $lines
    }
    finally {
        if (Test-Path -LiteralPath $stderrPath) {
            Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $tempOut) {
            Remove-Item -LiteralPath $tempOut -Force -ErrorAction SilentlyContinue
        }
    }
}

function script:Get-PdfPdftotextModeCandidates {
    return @(
        @{ Label = 'layout'; Args = @('-layout') },
        @{ Label = 'raw'; Args = @('-raw') },
        @{ Label = 'default'; Args = @() },
        @{ Label = 'layout+nopgbrk'; Args = @('-layout', '-nopgbrk') },
        @{ Label = 'raw+nopgbrk'; Args = @('-raw', '-nopgbrk') },
        @{ Label = 'nopgbrk'; Args = @('-nopgbrk') }
    )
}

function script:Select-BestPdftotextModeForPdf {
    param(
        [string]$PdfPath,
        [string]$PdftotextExe
    )
    $bestScore = -1
    $bestLabel = 'layout'
    $bestLines = @()
    $detail = [ordered]@{}
    foreach ($cand in @(Get-PdfPdftotextModeCandidates)) {
        $lines = @(Get-PdfPageLinesWithPdftotextArgs -PdfPath $PdfPath -PdftotextExe $PdftotextExe -PageNumber 1 -ExtraArgs $cand.Args -LogContext ('SelectBest page=1 mode=' + $cand.Label))
        $sc = Measure-PdfLinesExtractionScore -Lines $lines
        $joined = Join-PdfLinesToText -Lines $lines
        $detail[[string]$cand.Label] = [pscustomobject]@{
            ExtractedLength = $joined.Length
            LineCount       = $lines.Count
            Score           = $sc
        }
        if ($sc -gt $bestScore) {
            $bestScore = $sc
            $bestLabel = [string]$cand.Label
            $bestLines = $lines
        }
    }
    return [pscustomobject]@{
        Mode            = $bestLabel
        Score           = $bestScore
        Lines           = $bestLines
        Page1ByMode     = [pscustomobject]$detail
    }
}

function script:Get-PdfPageLinesViaPdftotext {
    param(
        [string]$PdfPath,
        [string]$PdftotextExe,
        [int]$PageNumber,
        [string[]]$PdftotextExtraArgs,

        [string]$LogContext = ''
    )

    if ($null -eq $PdftotextExtraArgs) {
        $PdftotextExtraArgs = @('-layout')
    }

    $lc = if ([string]::IsNullOrWhiteSpace($LogContext)) {
        ('Extract page=' + $PageNumber)
    }
    else {
        $LogContext
    }

    return @(Get-PdfPageLinesWithPdftotextArgs -PdfPath $PdfPath -PdftotextExe $PdftotextExe -PageNumber $PageNumber -ExtraArgs $PdftotextExtraArgs -LogContext $lc)
}

function script:Get-PdftotextArgsFromModeLabel {
    param([string]$Label)
    foreach ($cand in @(Get-PdfPdftotextModeCandidates)) {
        if ($cand.Label -ceq $Label) {
            return [string[]]@($cand.Args)
        }
    }
    return @('-layout')
}

function Test-PdfExtractQuality {
    <#
    .SYNOPSIS
    Qualité du texte extrait : longueur, présence de contenu utile, heuristique « PDF scanné » (peu ou pas de texte).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$Lines = @(),

        [Parameter(Mandatory = $false)]
        [int]$PageCount = 1,

        [Parameter(Mandatory = $false)]
        [string]$Mode = ''
    )

    $text = if ($Lines -and $Lines.Count -gt 0) {
        Join-PdfLinesToText -Lines $Lines
    }
    else {
        ''
    }

    $extractedLength = $text.Length
    $nonWs = if ($extractedLength -eq 0) {
        0
    }
    else {
        ([regex]::Replace($text, '\s', '')).Length
    }

    $pc = [Math]::Max(1, $PageCount)
    $letterDigit = ([regex]::Matches($text, '[\p{L}0-9]')).Count
    $perPageNonWs = $nonWs / $pc
    $perPageLd = $letterDigit / $pc

    $minNonWs = [Math]::Max(28, 12 * $pc)
    $minLd = [Math]::Max(12, 5 * $pc)
    $hasText = ($nonWs -ge $minNonWs) -and ($letterDigit -ge $minLd)
    $isLikelyScanned = ($extractedLength -lt 20) -or ($nonWs -lt 18) -or ($letterDigit -lt 10) -or (($perPageNonWs -lt 10) -and ($perPageLd -lt 6))

    if ($hasText) {
        $isLikelyScanned = $false
    }

    return [pscustomobject]@{
        HasText             = $hasText
        ExtractedLength     = $extractedLength
        NonWhitespaceLength = $nonWs
        LetterDigitCount    = $letterDigit
        IsLikelyScanned     = $isLikelyScanned
        Mode                = $Mode
        PageCount           = $pc
    }
}

function Compare-PdftotextExtractionModes {
    <#
    .SYNOPSIS
    Pour diagnostic / tests : compare pdftotext -layout, -raw, défaut, -nopgbrk (longueurs et scores page 1).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PdfPath,

        [Parameter(Mandatory = $true)]
        [string]$PdftotextExe,

        [Parameter(Mandatory = $false)]
        [int]$PageNumber = 1
    )

    $resolved = (Resolve-Path -LiteralPath $PdfPath -ErrorAction Stop).ProviderPath
    $modes = [ordered]@{}
    foreach ($cand in @(Get-PdfPdftotextModeCandidates)) {
        $lines = @(Get-PdfPageLinesWithPdftotextArgs -PdfPath $resolved -PdftotextExe $PdftotextExe -PageNumber $PageNumber -ExtraArgs $cand.Args -LogContext ('Compare page=' + $PageNumber + ' mode=' + $cand.Label))
        $joined = Join-PdfLinesToText -Lines $lines
        $modes[[string]$cand.Label] = [pscustomobject]@{
            ExtractedLength = $joined.Length
            LineCount       = $lines.Count
            Score           = (Measure-PdfLinesExtractionScore -Lines $lines)
        }
    }

    return [pscustomobject]@{
        PdfPath = $resolved
        Page    = $PageNumber
        Modes   = [pscustomobject]$modes
    }
}

function Invoke-PdfExtraction {
    <#
    .SYNOPSIS
    Extrait le texte d'un PDF, découpé en lignes par page.

    .PARAMETER PdfPath
    Chemin absolu ou relatif du fichier PDF source.

    .PARAMETER PdfDebug
    Active des journaux détaillés (pdftotext : exe complet, arguments, chemin fichier temporaire, aperçu des lignes).
    Équivalent pratique : variable d'environnement PDF_DEBUG=1 (hors valeur 0/false/no/off).

    .OUTPUTS
    PSCustomObject
    Propriétés : PdfPath, PageCount, Pages, ExtractionNote, PdftotextModeUsed, ExtractQuality,
    PdfTextUnusable, UserAbortMessage, DiagnosticsMessages
    Chaque entrée de Pages : PageNumber, Lines (filtré / pipeline), RawLines (toujours après pdftotext),
    FilteredLines (après contrôle qualité ; vide si PdfTextUnusable).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PdfPath,

        [switch]$PdfDebug,

        [scriptblock]$ProgressCallback = $null
    )

    $prevDiagList = $script:PdfExtractionDiagList
    $prevDebugSession = $script:PdfExtractDebugSession
    $diag = [System.Collections.Generic.List[string]]::new()
    $script:PdfExtractionDiagList = $diag
    if ($PdfDebug) {
        $script:PdfExtractDebugSession = $true
    }

    try {
        try {
            $resolved = (Resolve-Path -LiteralPath $PdfPath -ErrorAction Stop).ProviderPath
        }
        catch {
            throw "PDF introuvable : $PdfPath"
        }

        $pageCount = Get-PdfPageCountInternal -FichierPDF $resolved
        if ($pageCount -lt 1) {
            throw "Impossible de déterminer le nombre de pages pour : $resolved"
        }

        $resolveTrace = @()
        $pdftotext = Get-ResolvedPdfToTextPath -TraceOut ([ref]$resolveTrace)
        $pages = [System.Collections.Generic.List[object]]::new()
        $note = $null
        $winningMode = 'none'
        $extraArgs = @('-layout')

        if (-not $pdftotext) {
            [void]$diag.Add('[PDF] FATAL: pdftotext introuvable')
            Write-Host "[PDF] Recherche pdftotext..." -ForegroundColor Cyan
            Write-Host (" - PDFTOTEXT_PATH = {0}" -f [string]$env:PDFTOTEXT_PATH) -ForegroundColor DarkGray
            Write-Host (" - PDFTOTEXT_ALLOW_PATH = {0}" -f [string]$env:PDFTOTEXT_ALLOW_PATH) -ForegroundColor DarkGray
            foreach ($ln in @($resolveTrace)) {
                Write-Host (" - PATH test = {0}" -f $ln) -ForegroundColor DarkGray
                [void]$diag.Add("[PDF][Resolve] $ln")
            }

            $allowEmpty = ([string]$env:CN_ALLOW_EMPTY_PDF).Trim().ToLowerInvariant() -in @('1', 'true', 'yes', 'on')
            if ($allowEmpty) {
                $note = '[WARN] Extraction desactivee — mode fallback CN_ALLOW_EMPTY_PDF=1 (pages vides).'
                Write-Host $note -ForegroundColor Yellow
                for ($i = 1; $i -le $pageCount; $i++) {
                    $empty = [string[]]@()
                    $pages.Add([pscustomobject]@{
                        PageNumber      = $i
                        Lines           = $empty
                        RawLines        = $empty
                        FilteredLines   = $empty
                        ClientNameLines = @($empty)
                    })
                    if ($null -ne $ProgressCallback) {
                        try { & $ProgressCallback $i $pageCount ("pages extraites : {0}/{1}" -f $i, $pageCount) } catch { }
                    }
                }
            }
            else {
                throw @"
[FATAL] pdftotext introuvable

Solutions :
1. Installer Poppler (recommandé)
2. Définir PDFTOTEXT_PATH
3. Mettre pdftotext.exe dans le PATH + PDFTOTEXT_ALLOW_PATH=1
4. Déployer tools\Poppler\Library\bin\pdftotext.exe

Debug :
- PATH = $env:PATH
- PDFTOTEXT_PATH = $env:PDFTOTEXT_PATH
- PDFTOTEXT_ALLOW_PATH = $env:PDFTOTEXT_ALLOW_PATH
"@
            }
        }
        else {
            $script:PdftotextIntraRunLineCache = @{}
            $pick = Select-BestPdftotextModeForPdf -PdfPath $resolved -PdftotextExe $pdftotext
            $winningMode = [string]$pick.Mode
            $extraArgs = Get-PdftotextArgsFromModeLabel -Label $winningMode

            $pm = $pick.Page1ByMode
            $layoutLen = $pm.layout.ExtractedLength
            $defaultLen = $pm.default.ExtractedLength
            $rawLen = $pm.raw.ExtractedLength
            [void]$diag.Add("[PDF] Compare page1: layoutLen=$layoutLen defaultLen=$defaultLen rawLen=$rawLen picked=$winningMode score=$($pick.Score)")

            for ($i = 1; $i -le $pageCount; $i++) {
                $lines = @(Get-PdfPageLinesViaPdftotext -PdfPath $resolved -PdftotextExe $pdftotext -PageNumber $i -PdftotextExtraArgs $extraArgs -LogContext ('Extract page=' + $i + ' mode=' + $winningMode))
                $rawCopy = @(
                    foreach ($ln in @($lines)) {
                        if ($null -eq $ln) { '' } else { [string]$ln }
                    }
                )
                $clientNameLines = @(Get-PdfPageClientNameLinesFromBbox -PdfPath $resolved -PdftotextExe $pdftotext -PageNumber $i)
                if ($clientNameLines.Count -lt 1) {
                    $clientNameLines = @(Split-PdfMonolithicClientNameLayoutLines -LayoutLines $rawCopy)
                }
                $pages.Add([pscustomobject]@{
                    PageNumber      = $i
                    Lines           = $rawCopy
                    RawLines        = $rawCopy
                    FilteredLines   = $rawCopy
                    ClientNameLines = @($clientNameLines)
                })
                if ($null -ne $ProgressCallback) {
                    try { & $ProgressCallback $i $pageCount ("pages extraites : {0}/{1}" -f $i, $pageCount) } catch { }
                }
            }
        }

        if (@($pages).Count -lt 1) {
            throw "[FATAL] Extraction PDF vide ou invalide (aucune page collectee)"
        }

        $allLines = [System.Collections.Generic.List[string]]::new()
        foreach ($pg in $pages) {
            foreach ($ln in @($pg.Lines)) {
                [void]$allLines.Add([string]$ln)
            }
        }

        $quality = Test-PdfExtractQuality -Lines @($allLines.ToArray()) -PageCount $pageCount -Mode $winningMode
        $pdfTextUnusable = $false
        $userAbort = $null
        if ($pdftotext -and ($quality.IsLikelyScanned -or -not $quality.HasText)) {
            $pdfTextUnusable = $true
            $userAbort = 'Le PDF ne contient pas de texte exploitable (document scanné).'
            $note = $userAbort

            $rawLineTotal = 0
            foreach ($pg0 in $pages) {
                $rawLineTotal += @($pg0.RawLines).Count
            }
            [void]$diag.Add("[PDF] Qualite: texte non exploitable (HasText=$($quality.HasText) LikelyScanned=$($quality.IsLikelyScanned)). Document traite comme scanne / sans couche texte. RawLines conservees (total lignes brutes=$rawLineTotal) ; Lines et FilteredLines vides pour le pipeline.")
            Add-PdfExtractionDiagLine -Message '[PDF] Gate qualite : sortie filtree videe ; consulter RawLines par page pour le texte brut extrait.'

            for ($j = 0; $j -lt $pages.Count; $j++) {
                $cur = $pages[$j]
                $rawKeep = @(
                    foreach ($r in @($cur.RawLines)) {
                        if ($null -eq $r) { '' } else { [string]$r }
                    }
                )
                if ($rawKeep.Count -eq 0) {
                    $rawKeep = @(
                        foreach ($r in @($cur.Lines)) {
                            if ($null -eq $r) { '' } else { [string]$r }
                        }
                    )
                }
                $emptyOut = [string[]]@()
                $pages[$j] = [pscustomobject]@{
                    PageNumber    = $cur.PageNumber
                    Lines         = $emptyOut
                    RawLines      = $rawKeep
                    FilteredLines = $emptyOut
                }
            }
        }

        $logLine = "[PDF] ExtractLength=$($quality.ExtractedLength) | HasText=$($quality.HasText) | Mode=$winningMode | LikelyScanned=$($quality.IsLikelyScanned)"
        [void]$diag.Add($logLine)
        Write-Verbose $logLine

        return [pscustomobject]@{
            PdfPath             = $resolved
            PageCount           = $pageCount
            Pages               = $pages.ToArray()
            ExtractionNote      = $note
            PdftotextModeUsed   = $winningMode
            ExtractQuality      = $quality
            PdfTextUnusable     = $pdfTextUnusable
            UserAbortMessage    = $userAbort
            DiagnosticsMessages = @($diag.ToArray())
        }
    }
    finally {
        $script:PdftotextIntraRunLineCache = $null
        $script:PdfExtractionDiagList = $prevDiagList
        $script:PdfExtractDebugSession = $prevDebugSession
    }
}

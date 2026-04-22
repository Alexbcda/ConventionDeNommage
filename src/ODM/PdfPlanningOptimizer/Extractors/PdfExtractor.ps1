# ============================================================
# PdfExtractor.ps1
# Rôle : Extraire le texte brut d'un PDF, découpé en lignes par page.
# Pipeline unique : pdftotext (-enc UTF-8) → lecture UTF-8 (Get-Content -Encoding UTF8) ;
# si validation UTF-8 stricte échoue ou caractères de remplacement : correction unique
# UTF8.GetString( CP1252.GetBytes( CP1252.GetString(octets) ) ) sur les octets du fichier temporaire.
# Diagnostic hors flux : Debug\PdfRawEncodingInspector.ps1
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
        $out = New-Object byte[] $n
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
    $enc = New-Object System.Text.UTF8Encoding @($false, $true)
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

function script:Get-PdfPageCountInternal {
    param([string]$FichierPDF)

    if (-not (Test-Path -LiteralPath $FichierPDF)) {
        return 0
    }

    $gsPaths = [System.Collections.Generic.List[string]]::new()
    $gsRoot = Join-Path $env:ProgramFiles 'gs'
    if (Test-Path -LiteralPath $gsRoot) {
        foreach ($dir in (Get-ChildItem -LiteralPath $gsRoot -Directory -ErrorAction SilentlyContinue)) {
            foreach ($name in @('gswin64c.exe', 'gswin32c.exe')) {
                $candidate = Join-Path $dir.FullName "bin\$name"
                if (Test-Path -LiteralPath $candidate) {
                    $gsPaths.Add($candidate)
                }
            }
        }
    }
    foreach ($extra in @(
            "${env:ProgramFiles}\Ghostscript\bin\gswin64c.exe",
            "${env:ProgramFiles}\Ghostscript\bin\gswin32c.exe"
        )) {
        if (Test-Path -LiteralPath $extra) {
            $gsPaths.Add($extra)
        }
    }

    foreach ($gsPath in $gsPaths) {
        if (-not (Test-Path -LiteralPath $gsPath)) { continue }
        try {
            $psPath = $FichierPDF -replace '\\', '/'
            $output = & $gsPath -dNODISPLAY -q -c "($psPath) (r) file runpdfbegin pdfpagecount = quit" 2>&1
            $joined = if ($output -is [array]) { $output -join "`n" } else { [string]$output }
            if ($joined -match '(\d+)') {
                return [int]$Matches[1]
            }
        }
        catch {
            continue
        }
    }

    $pdfinfo = Get-Command pdfinfo.exe -ErrorAction SilentlyContinue
    if ($pdfinfo -and $pdfinfo.Source) {
        try {
            $info = & $pdfinfo.Source $FichierPDF 2>&1
            $text = if ($info -is [array]) { $info -join "`n" } else { [string]$info }
            $m = [regex]::Match($text, '(?im)^Pages:\s*(\d+)\s*$')
            if ($m.Success) {
                return [int]$m.Groups[1].Value
            }
        }
        catch {
            # ignore
        }
    }

    return Get-PdfPageCountFromRawScan -FichierPDF $FichierPDF
}

function script:Get-PdfPageCountFromRawScan {
    param([string]$FichierPDF)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($FichierPDF)
        if ($bytes.Length -lt 16) { return 0 }

        $enc = [System.Text.Encoding]::GetEncoding(28591)
        $chunks = [System.Collections.Generic.List[byte[]]]::new()
        $headLen = [Math]::Min($bytes.Length, 262144)
        $chunks.Add($bytes[0..($headLen - 1)])
        if ($bytes.Length -gt $headLen) {
            $tailLen = [Math]::Min($bytes.Length, 524288)
            $chunks.Add($bytes[($bytes.Length - $tailLen)..($bytes.Length - 1)])
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

function script:Resolve-PdfToTextPathSafe {
    <#
    Résout pdftotext.exe : PDFTOTEXT_PATH (fichier validé strictement) ou emplacements contrôlés sous le dépôt / Xpdf.
    Ne suit pas le PATH machine ; n’accepte pas un dossier dans PDFTOTEXT_PATH (évite exécution non validée).
    #>
    param()

    $repoRoot = $PSScriptRoot
    for ($i = 0; $i -lt 4; $i++) {
        $repoRoot = Split-Path -Parent $repoRoot
    }

    $defaultPaths = @(
        (Join-Path $repoRoot 'tools\pdftotext.exe'),
        (Join-Path $repoRoot 'tools\Poppler\Library\bin\pdftotext.exe'),
        'C:\Program Files\Xpdf\pdftotext.exe'
    )

    $fromEnv = [string]$env:PDFTOTEXT_PATH

    if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
        $path = $fromEnv.Trim()

        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "PDFTOTEXT_PATH invalide (fichier introuvable)."
        }

        if ((Split-Path -Leaf $path).ToLower() -cne 'pdftotext.exe') {
            throw "PDFTOTEXT_PATH doit pointer vers pdftotext.exe uniquement."
        }

        if ([System.IO.Path]::GetExtension($path).ToLower() -cne '.exe') {
            throw "Fichier non exécutable interdit."
        }

        $resolvedExe = (Resolve-Path -LiteralPath $path).Path

        try {
            $sig = Get-AuthenticodeSignature -LiteralPath $resolvedExe
            if ($sig.Status -ne 'Valid') {
                Write-Warning "pdftotext.exe non signé"
            }
        }
        catch { }

        return $resolvedExe
    }

    foreach ($p in $defaultPaths) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }

        $resolvedExe = (Resolve-Path -LiteralPath $p).Path

        try {
            $sig = Get-AuthenticodeSignature -LiteralPath $resolvedExe
            if ($sig.Status -ne 'Valid') {
                Write-Warning "pdftotext.exe non signé"
            }
        }
        catch { }

        return $resolvedExe
    }

    return $null
}

function script:Resolve-PdfTotextPath {
    try {
        return Resolve-PdfToTextPathSafe
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
    param([System.Collections.Generic.List[string]]$ArgList)
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

function script:Get-PdfPageLinesWithPdftotextArgs {
    param(
        [string]$PdfPath,
        [string]$PdftotextExe,
        [int]$PageNumber,
        [string[]]$ExtraArgs,

        [string]$LogContext = ''
    )

    $tempOut = [System.IO.Path]::GetTempFileName()
    $stderrPath = "$tempOut.stderr.txt"
    $ctx = if ([string]::IsNullOrWhiteSpace($LogContext)) { 'pdftotext' } else { $LogContext }

    try {
        $argList = [System.Collections.Generic.List[string]]::new()
        [void]$argList.AddRange(@(
                '-f', "$PageNumber",
                '-l', "$PageNumber",
                '-enc', 'UTF-8',
                '-q'
            ))
        if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
            foreach ($a in $ExtraArgs) {
                if (-not [string]::IsNullOrWhiteSpace($a)) { [void]$argList.Add($a.Trim()) }
            }
        }
        [void]$argList.Add($PdfPath)
        [void]$argList.Add($tempOut)

        $argLine = Format-PdftotextArgsForLog -ArgList $argList
        Add-PdfExtractionDiagLine -Message ("[{0}] pdftotext.exe={1}" -f $ctx, $PdftotextExe) -DebugOnly
        Add-PdfExtractionDiagLine -Message ("[{0}] args: {1}" -f $ctx, $argLine) -DebugOnly
        Add-PdfExtractionDiagLine -Message ("[{0}] tempOut={1}" -f $ctx, $tempOut) -DebugOnly

        if (Test-Path -LiteralPath $stderrPath) {
            Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
        }

        $null = & $PdftotextExe $argList.ToArray() 2>$stderrPath
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

        [switch]$PdfDebug
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

        $pdftotext = Resolve-PdfTotextPath
        $pages = [System.Collections.Generic.List[object]]::new()
        $note = $null
        $winningMode = 'none'
        $extraArgs = @('-layout')

        if ($pdftotext) {
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
                $pages.Add([pscustomobject]@{
                    PageNumber    = $i
                    Lines         = $rawCopy
                    RawLines      = $rawCopy
                    FilteredLines = $rawCopy
                })
            }
        }
        else {
            $note = 'pdftotext (Poppler) introuvable : pages créées avec lignes vides. Installez Poppler pour extraire le texte.'
            for ($i = 1; $i -le $pageCount; $i++) {
                $empty = [string[]]@()
                $pages.Add([pscustomobject]@{
                    PageNumber    = $i
                    Lines         = $empty
                    RawLines      = $empty
                    FilteredLines = $empty
                })
            }
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
        $script:PdfExtractionDiagList = $prevDiagList
        $script:PdfExtractDebugSession = $prevDebugSession
    }
}

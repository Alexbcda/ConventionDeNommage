# ============================================================
# PdfRawEncodingInspector.ps1 (hors flux normal — dossier Debug/)
# Diagnostic encodage : octets bruts du fichier produit par pdftotext (-enc UTF-8),
# sans lecture texte pour la couche d'analyse. Aucune logique métier (ODM, client, date).
# ============================================================

function script:Get-PdfPageCountFromRawScanInspector {
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

function script:Get-PdfPageCountInternalInspector {
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

    return Get-PdfPageCountFromRawScanInspector -FichierPDF $FichierPDF
}

function script:Resolve-PdfTotextPathInspector {
    $fromEnv = [string]$env:PDFTOTEXT_PATH
    if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
        $t = $fromEnv.Trim()
        if (Test-Path -LiteralPath $t -PathType Container) {
            $t = Join-Path $t 'pdftotext.exe'
        }
        if (Test-Path -LiteralPath $t -PathType Leaf) {
            return (Resolve-Path -LiteralPath $t).ProviderPath
        }
    }

    $cmd = Get-Command pdftotext.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    $candidates = @(
        "${env:ProgramFiles}\poppler\Library\bin\pdftotext.exe",
        "${env:ProgramFiles(x86)}\poppler\Library\bin\pdftotext.exe",
        "${env:LOCALAPPDATA}\Microsoft\WinGet\Links\pdftotext.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function script:Read-FileAsRawByteArrayInspector {
    <#
    Couche octets uniquement : jamais Get-Content en mode texte.
    Windows PowerShell 5.x : Get-Content -Encoding Byte.
    PowerShell 6+ : Get-Content -AsByteStream -Raw (equivalent lecture octets bruts).
    #>
    param([string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        return [byte[]]@()
    }

    if ($PSVersionTable.PSVersion.Major -ge 6) {
        return Get-Content -LiteralPath $LiteralPath -AsByteStream -Raw
    }

    return [byte[]](, @(Get-Content -LiteralPath $LiteralPath -Encoding Byte -ReadCount 0))
}

function script:Split-ByteArrayIntoLinesInspector {
    param([byte[]]$AllBytes)

    $lines = [System.Collections.Generic.List[byte[]]]::new()
    if ($null -eq $AllBytes -or $AllBytes.Length -eq 0) {
        return @([byte[]]@())
    }

    $start = 0
    for ($i = 0; $i -lt $AllBytes.Length; $i++) {
        if ($AllBytes[$i] -ne 10) {
            continue
        }

        $len = $i - $start
        if ($len -lt 0) { $len = 0 }

        if ($len -eq 0) {
            $lines.Add([byte[]]@())
        }
        else {
            $buf = [byte[]]::new($len)
            [Array]::Copy($AllBytes, $start, $buf, 0, $len)
            if ($buf[$len - 1] -eq 13) {
                $nl = $len - 1
                $buf2 = [byte[]]::new($nl)
                [Array]::Copy($buf, 0, $buf2, 0, $nl)
                $lines.Add($buf2)
            }
            else {
                $lines.Add($buf)
            }
        }

        $start = $i + 1
    }

    if ($start -lt $AllBytes.Length) {
        $len = $AllBytes.Length - $start
        $buf = [byte[]]::new($len)
        [Array]::Copy($AllBytes, $start, $buf, 0, $len)
        if ($len -ge 1 -and $buf[$len - 1] -eq 13) {
            $nl = $len - 1
            $buf2 = [byte[]]::new($nl)
            [Array]::Copy($buf, 0, $buf2, 0, $nl)
            $lines.Add($buf2)
        }
        else {
            $lines.Add($buf)
        }
    }

    return @($lines.ToArray())
}

function script:Format-ByteSignatureHexInspector {
    param(
        [byte[]]$Bytes,
        [int]$MaxBytes = 256
    )

    if ($null -eq $Bytes -or $Bytes.Length -eq 0) {
        return '<empty>'
    }

    $take = [Math]::Min($Bytes.Length, $MaxBytes)
    $parts = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $take; $i++) {
        $parts.Add('{0:X2}' -f $Bytes[$i])
    }
    $hex = $parts -join ' '
    if ($Bytes.Length -gt $MaxBytes) {
        $hex += (' ... (+{0} octets)' -f ($Bytes.Length - $MaxBytes))
    }
    return $hex
}

function script:Test-StrictUtf8LineBytesInspector {
    param([byte[]]$LineBytes)
    if ($null -eq $LineBytes -or $LineBytes.Length -eq 0) {
        return $true
    }
    $strict = [System.Text.UTF8Encoding]::new($false, $true)
    try {
        $null = $strict.GetString($LineBytes)
        return $true
    }
    catch {
        return $false
    }
}

function script:Get-VisualDiffSummaryInspector {
    param(
        [string]$Left,
        [string]$Right,
        [int]$MaxReport = 24
    )

    if ($null -eq $Left) { $Left = '' }
    if ($null -eq $Right) { $Right = '' }

    if ($Left -ceq $Right) {
        return 'aucune difference'
    }

    $a = $Left.ToCharArray()
    $b = $Right.ToCharArray()
    $max = [Math]::Max($a.Length, $b.Length)
    $reports = [System.Collections.Generic.List[string]]::new()
    $n = 0
    for ($i = 0; $i -lt $max; $i++) {
        $ca = if ($i -lt $a.Length) { [int][char]$a[$i] } else { -1 }
        $cb = if ($i -lt $b.Length) { [int][char]$b[$i] } else { -1 }
        if ($ca -ne $cb) {
            $sa = if ($ca -ge 0) { 'U+{0:X4}' -f $ca } else { '<fin>' }
            $sb = if ($cb -ge 0) { 'U+{0:X4}' -f $cb } else { '<fin>' }
            $reports.Add(("idx {0}: {1} vs {2}" -f $i, $sa, $sb))
            $n++
            if ($n -ge $MaxReport) {
                $reports.Add('...')
                break
            }
        }
    }
    return ($reports -join ' | ')
}

function script:Build-LineConclusionPhraseInspector {
    param(
        [bool]$StrictUtf8Valid,
        [string]$Utf8String,
        [string]$Cp1252String
    )

    if (-not $StrictUtf8Valid) {
        return 'Cette ligne : octets non conformes UTF-8 strict ; le fichier pdftotext peut contenir du non-UTF8 ou du binaire sur cette ligne (pas seulement une erreur de canonicalizer).'
    }

    if ($Utf8String -ceq $Cp1252String) {
        return 'Cette ligne : UTF-8 strict valide ; interpretations UTF-8 et CP1252 identiques (contenu principallement ASCII sur les octets presents).'
    }

    return 'Cette ligne : UTF-8 strict valide ; UTF-8 et CP1252 different : si vous observez des caracteres type Atilde ou Acirc en aval, une couche a probablement relu du UTF-8 valide comme Windows-1252 (double interpretation), pas une erreur de pdftotext sur ces octets.'
}

function script:Build-DocumentSummaryPhraseInspector {
    param(
        [object[]]$PageResults
    )

    if ($null -eq $PageResults -or $PageResults.Count -eq 0) {
        return 'Aucune page inspectee.'
    }

    $invalid = 0
    $linesTotal = 0
    foreach ($p in $PageResults) {
        foreach ($ln in @($p.Lines)) {
            $linesTotal++
            if (-not $ln.Utf8StrictValid) {
                $invalid++
            }
        }
    }

    if ($invalid -gt 0) {
        return ('Document : {0} ligne(s) sur {1} avec octets invalides en UTF-8 strict — le probleme vient en priorite du contenu/emis par pdftotext (ou -enc UTF-8 ne produit pas du UTF-8 pur), pas d''une simple relecture CP1252 sur tout le fichier.' -f $invalid, $linesTotal)
    }

    return ('Document : toutes les lignes ({0}) sont des sequences UTF-8 strictes valides — si l''interface montre encore Atilde/Acirc/bullet casse, le probleme vient probablement d''une interpretation Windows-1252 (ou ISO-8859-1) du texte UTF-8 en aval (double decodage ou mauvais encodage affiche), pas des octets emis par pdftotext sur cet echantillon.' -f $linesTotal)
}

function Invoke-PdfRawEncodingInspection {
    <#
    .SYNOPSIS
    Inspecte l'encodage reel des fichiers texte produits par pdftotext : lecture exclusive en octets bruts,
    puis decodage UTF-8 / CP1252 / UTF-8 avec remplacements pour comparaison.

    .PARAMETER PdfPath
    Chemin du PDF source.

    .PARAMETER MaxHexBytesPerLine
    Nombre maximal d'octets affiches dans ByteSignatureHex par ligne (defaut 256).

    .OUTPUTS
    PSCustomObject avec Pages (lignes : signatures octets + chaines A/B/C + conclusions).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PdfPath,

        [Parameter(Mandatory = $false)]
        [ValidateRange(8, 8192)]
        [int]$MaxHexBytesPerLine = 256
    )

    try {
        $resolved = (Resolve-Path -LiteralPath $PdfPath -ErrorAction Stop).ProviderPath
    }
    catch {
        throw "PDF introuvable : $PdfPath"
    }

    $pdftotext = Resolve-PdfTotextPathInspector
    if (-not $pdftotext) {
        return [pscustomobject]@{
            PdfPath               = $resolved
            PdftotextPath         = $null
            DocumentSummaryPhrase = 'pdftotext introuvable : inspection impossible (definir PDFTOTEXT_PATH ou installer Poppler).'
            Pages                 = @()
        }
    }

    $pageCount = Get-PdfPageCountInternalInspector -FichierPDF $resolved
    if ($pageCount -lt 1) {
        return [pscustomobject]@{
            PdfPath               = $resolved
            PdftotextPath         = $pdftotext
            DocumentSummaryPhrase = 'Nombre de pages du PDF non determine : inspection impossible.'
            Pages                 = @()
        }
    }

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false, $false)
    $cp1252 = [System.Text.Encoding]::GetEncoding(1252)
    $encFb = [System.Text.EncoderReplacementFallback]::new([string][char]0xFFFD)
    $decFb = [System.Text.DecoderReplacementFallback]::new([string][char]0xFFFD)
    $utf8Replacement = [System.Text.Encoding]::GetEncoding(65001, $encFb, $decFb)

    $pageList = [System.Collections.Generic.List[object]]::new()

    for ($pageNum = 1; $pageNum -le $pageCount; $pageNum++) {
        $tempOut = [System.IO.Path]::GetTempFileName()
        try {
            $argList = @(
                '-f', "$pageNum",
                '-l', "$pageNum",
                '-layout',
                '-enc', 'UTF-8',
                $resolved,
                $tempOut
            )
            $proc = Start-Process -FilePath $pdftotext -ArgumentList $argList -Wait -PassThru -NoNewWindow
            if ($proc.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $tempOut)) {
                $pageList.Add([pscustomobject]@{
                    PageNumber         = $pageNum
                    Lines              = @()
                    PageSummaryPhrase  = ('pdftotext a echoue pour la page {0} (code {1}).' -f $pageNum, $proc.ExitCode)
                })
                continue
            }

            $allBytes = Read-FileAsRawByteArrayInspector -LiteralPath $tempOut
            $lineArrays = @(Split-ByteArrayIntoLinesInspector -AllBytes $allBytes)

            $lineObjs = [System.Collections.Generic.List[object]]::new()
            $idx = 0
            foreach ($lineBytes in $lineArrays) {
                $strictOk = Test-StrictUtf8LineBytesInspector -LineBytes $lineBytes
                $strA = if ($null -eq $lineBytes -or $lineBytes.Length -eq 0) {
                    ''
                }
                else {
                    $utf8NoBom.GetString($lineBytes)
                }
                $strB = if ($null -eq $lineBytes -or $lineBytes.Length -eq 0) {
                    ''
                }
                else {
                    $cp1252.GetString($lineBytes)
                }
                $strC = if ($null -eq $lineBytes -or $lineBytes.Length -eq 0) {
                    ''
                }
                else {
                    $utf8Replacement.GetString($lineBytes)
                }

                $diffAC = Get-VisualDiffSummaryInspector -Left $strA -Right $strC
                $diffAB = Get-VisualDiffSummaryInspector -Left $strA -Right $strB

                $ffA = 0
                $ffC = 0
                foreach ($ch in $strA.ToCharArray()) {
                    if ([int][char]$ch -eq 0xFFFD) { $ffA++ }
                }
                foreach ($ch in $strC.ToCharArray()) {
                    if ([int][char]$ch -eq 0xFFFD) { $ffC++ }
                }

                $lineObjs.Add([pscustomobject]@{
                    LineIndex                          = $idx
                    ByteCount                          = if ($null -eq $lineBytes) { 0 } else { $lineBytes.Length }
                    ByteSignatureHex                   = (Format-ByteSignatureHexInspector -Bytes $lineBytes -MaxBytes $MaxHexBytesPerLine)
                    Utf8NoBomString                    = $strA
                    Windows1252String                  = $strB
                    Utf8ReplacementFallbackString      = $strC
                    Utf8StrictValid                    = $strictOk
                    ReplacementCharCountUtf8Lenient    = $ffA
                    ReplacementCharCountUtf8Explicit = $ffC
                    DiffVisibleUtf8LenientVsReplacement = $diffAC
                    DiffVisibleUtf8VsCp1252            = $diffAB
                    ConclusionPhrase                   = (Build-LineConclusionPhraseInspector -StrictUtf8Valid $strictOk -Utf8String $strA -Cp1252String $strB)
                })
                $idx++
            }

            $pageList.Add([pscustomobject]@{
                PageNumber        = $pageNum
                Lines             = @($lineObjs.ToArray())
                PageSummaryPhrase = ('Page {0} : {1} ligne(s) analysees en octets bruts.' -f $pageNum, $lineObjs.Count)
            })
        }
        finally {
            if (Test-Path -LiteralPath $tempOut) {
                Remove-Item -LiteralPath $tempOut -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $pagesArr = @($pageList.ToArray())
    return [pscustomobject]@{
        PdfPath               = $resolved
        PdftotextPath         = $pdftotext
        DocumentSummaryPhrase = (Build-DocumentSummaryPhraseInspector -PageResults $pagesArr)
        Pages                 = $pagesArr
    }
}

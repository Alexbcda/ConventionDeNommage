# ============================================================
# PdfExtractor.ps1
# Rôle : Extraire le texte brut d'un PDF, découpé en lignes par page.
# Pipeline unique : pdftotext (-enc UTF-8) → lecture UTF-8 (Get-Content -Encoding UTF8) ;
# si validation UTF-8 stricte échoue ou caractères de remplacement : correction unique
# UTF8.GetString( CP1252.GetBytes( CP1252.GetString(octets) ) ) sur les octets du fichier temporaire.
# Diagnostic hors flux : Debug\PdfRawEncodingInspector.ps1
# ============================================================

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
        return @()
    }

    $bytes = [System.IO.File]::ReadAllBytes($LiteralPath)
    $bytesNoBom = Remove-Utf8BomFromByteArray -Bytes $bytes

    $primaryLines = @()
    try {
        $primaryLines = @(Get-Content -LiteralPath $LiteralPath -Encoding UTF8)
    }
    catch {
        return @(Repair-PdfTextUtf8ViaCp1252BytesRoundtrip -Bytes $bytes)
    }

    $joined = if ($primaryLines.Count -eq 0) { '' } else { ($primaryLines -join "`n") }
    $strictOk = Test-PdfFileBytesAreStrictUtf8 -Bytes $bytesNoBom
    $hasRepl = Test-PdfUtf8DecodedTextHasReplacementChar -Text $joined

    if ($strictOk -and -not $hasRepl) {
        return $primaryLines
    }

    return @(Repair-PdfTextUtf8ViaCp1252BytesRoundtrip -Bytes $bytes)
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

function script:Resolve-PdfTotextPath {
    $fromEnv = [string]$env:PDFTOTEXT_PATH
    if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
        $t = $fromEnv.Trim()
        if (Test-Path -LiteralPath $t -PathType Container) {
            $t = Join-Path $t 'pdftotext.exe'
        }
        if (Test-Path -LiteralPath $t -PathType Leaf) {
            $resolved = Resolve-Path -LiteralPath $t -ErrorAction SilentlyContinue
            if ($resolved) { return $resolved.ProviderPath }
            return $t
        }
    }

    $cmd = Get-Command pdftotext.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    $candidates = @(
        "C:\Users\alexa\Downloads\Release-25.12.0-0\poppler-25.12.0\Library\bin\pdftotext.exe",
        "${env:ProgramFiles}\poppler\Library\bin\pdftotext.exe",
        "${env:ProgramFiles(x86)}\poppler\Library\bin\pdftotext.exe",
        "${env:LOCALAPPDATA}\Microsoft\WinGet\Links\pdftotext.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function script:Get-PdfPageLinesViaPdftotext {
    param(
        [string]$PdfPath,
        [string]$PdftotextExe,
        [int]$PageNumber
    )

    $tempOut = [System.IO.Path]::GetTempFileName()
    try {
        # Appel natif avec & : évite les pièges de Start-Process -ArgumentList ; -q supprime les messages Poppler ;
        # stderr ignoré pour ne pas polluer la console (copyright / erreurs).
        $null = & $PdftotextExe `
            '-f', "$PageNumber", `
            '-l', "$PageNumber", `
            '-layout', `
            '-enc', 'UTF-8', `
            '-q', `
            $PdfPath, `
            $tempOut 2>$null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tempOut)) {
            return @()
        }
        return @(Read-PdftotextOutputFileAsUtf8Lines -LiteralPath $tempOut)
    }
    finally {
        if (Test-Path -LiteralPath $tempOut) {
            Remove-Item -LiteralPath $tempOut -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-PdfExtraction {
    <#
    .SYNOPSIS
    Extrait le texte d'un PDF, découpé en lignes par page.

    .PARAMETER PdfPath
    Chemin absolu ou relatif du fichier PDF source.

    .OUTPUTS
    PSCustomObject
    Propriétés : PdfPath, PageCount, Pages (tableau @{ PageNumber; Lines } ), ExtractionNote (optionnel).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PdfPath
    )

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

    if ($pdftotext) {
        for ($i = 1; $i -le $pageCount; $i++) {
            $lines = @(Get-PdfPageLinesViaPdftotext -PdfPath $resolved -PdftotextExe $pdftotext -PageNumber $i)
            $pages.Add([pscustomobject]@{
                PageNumber = $i
                Lines      = $lines
            })
        }
    }
    else {
        $note = 'pdftotext (Poppler) introuvable : pages créées avec lignes vides. Installez Poppler pour extraire le texte.'
        for ($i = 1; $i -le $pageCount; $i++) {
            $pages.Add([pscustomobject]@{
                PageNumber = $i
                Lines      = [string[]]@()
            })
        }
    }

    return [pscustomobject]@{
        PdfPath      = $resolved
        PageCount    = $pageCount
        Pages        = $pages.ToArray()
        ExtractionNote = $note
    }
}

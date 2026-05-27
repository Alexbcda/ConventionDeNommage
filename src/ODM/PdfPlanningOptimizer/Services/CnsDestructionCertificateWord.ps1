# Certificat de destruction : template DOCX -> PDF (LibreOffice headless ou Microsoft Word COM en secours).

function Get-CnsDestructionCertificateTemplatePath {
    $candidates = New-Object System.Collections.Generic.List[string]
    try {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
        [void]$candidates.Add((Join-Path $repoRoot 'templates\planning\destruction\CertificatDeDestruction.docx'))
        [void]$candidates.Add((Join-Path $repoRoot 'templates\CertificatDeDestruction.docx'))
    }
    catch { }
    if (-not [string]::IsNullOrWhiteSpace($env:CN_DESTRUCTION_CERT_TEMPLATE)) {
        [void]$candidates.Insert(0, $env:CN_DESTRUCTION_CERT_TEMPLATE.Trim())
    }
    foreach ($p in @($candidates)) {
        if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path -LiteralPath $p -PathType Leaf)) {
            return ([System.IO.Path]::GetFullPath($p))
        }
    }
    return $null
}

function Get-CnsLibreOfficeSofficePath {
    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:CN_LIBREOFFICE_SOFFICE)) {
        [void]$candidates.Add($env:CN_LIBREOFFICE_SOFFICE.Trim())
    }
    [void]$candidates.Add('C:\Program Files\LibreOffice\program\soffice.exe')
    [void]$candidates.Add('C:\Program Files (x86)\LibreOffice\program\soffice.exe')
    foreach ($p in @($candidates)) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            return ([System.IO.Path]::GetFullPath($p))
        }
    }
    return $null
}

function Convert-DocxToPdfUsingLibreOffice {
    <#
    .SYNOPSIS
        Convertit un DOCX en PDF via soffice.exe (LibreOffice headless).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DocxPath,
        [Parameter(Mandatory = $true)]
        [string]$PdfPath
    )
    $soffice = Get-CnsLibreOfficeSofficePath
    if ([string]::IsNullOrWhiteSpace($soffice)) {
        Write-Warning '[DESTRUCTION-CERT] LibreOffice introuvable (soffice.exe). Installez LibreOffice ou definissez CN_LIBREOFFICE_SOFFICE.'
        return $false
    }

    if (-not (Test-Path -LiteralPath $DocxPath -PathType Leaf)) {
        Write-Warning ("[DESTRUCTION-CERT] DOCX source introuvable : {0}" -f $DocxPath)
        return $false
    }

    $docxAbs = [System.IO.Path]::GetFullPath($DocxPath)
    $pdfAbs = [System.IO.Path]::GetFullPath($PdfPath)
    $outDir = [System.IO.Path]::GetDirectoryName($pdfAbs)
    if (-not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop
    }

    $loArgs = @(
        '--headless',
        '--nologo',
        '--nofirststartwizard',
        '--convert-to', 'pdf',
        '--outdir', $outDir,
        $docxAbs
    )

    try {
        $proc = Start-Process -FilePath $soffice -ArgumentList $loArgs -Wait -PassThru -NoNewWindow -ErrorAction Stop
        if ($null -eq $proc -or $proc.ExitCode -ne 0) {
            Write-Warning ("[DESTRUCTION-CERT] LibreOffice a retourne le code {0}." -f $(if ($null -eq $proc) { 'null' } else { $proc.ExitCode }))
            return $false
        }
    }
    catch {
        Write-Warning ("[DESTRUCTION-CERT] LibreOffice echoue : {0}" -f $_.Exception.Message)
        return $false
    }

    $produced = Join-Path $outDir ([System.IO.Path]::GetFileNameWithoutExtension($docxAbs) + '.pdf')
    if (-not (Test-Path -LiteralPath $produced)) {
        Write-Warning '[DESTRUCTION-CERT] PDF non produit apres conversion LibreOffice.'
        return $false
    }

    if (-not ($produced.Equals($pdfAbs, [System.StringComparison]::OrdinalIgnoreCase))) {
        if (Test-Path -LiteralPath $pdfAbs) {
            Remove-Item -LiteralPath $pdfAbs -Force -ErrorAction SilentlyContinue
        }
        Move-Item -LiteralPath $produced -Destination $pdfAbs -Force
    }

    return (Test-Path -LiteralPath $pdfAbs)
}

$script:CnsMicrosoftWordAvailableCache = $null

function Get-CnsMicrosoftWordExecutablePath {
  <#
  .SYNOPSIS
      Chemin vers WINWORD.EXE : CN_WORD_APP, puis registre App Paths.
  #>
    if (-not [string]::IsNullOrWhiteSpace($env:CN_WORD_APP)) {
        $p = $env:CN_WORD_APP.Trim().Trim('"')
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            return ([System.IO.Path]::GetFullPath($p))
        }
    }
    foreach ($regPath in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\WINWORD.EXE',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\WINWORD.EXE'
        )) {
        try {
            $item = Get-ItemProperty -LiteralPath $regPath -ErrorAction Stop
            $exe = [string]$item.'(default)'
            if (-not [string]::IsNullOrWhiteSpace($exe)) {
                $exe = $exe.Trim().Trim('"')
                if (Test-Path -LiteralPath $exe -PathType Leaf) {
                    return ([System.IO.Path]::GetFullPath($exe))
                }
            }
        }
        catch { }
    }
    return $null
}

function Test-CnsMicrosoftWordAvailable {
  <#
  .SYNOPSIS
      Indique si Microsoft Word est utilisable (executable ou probe COM leger, resultat cache).
  #>
    if ($null -ne $script:CnsMicrosoftWordAvailableCache) {
        return [bool]$script:CnsMicrosoftWordAvailableCache
    }
    if ($null -ne (Get-CnsMicrosoftWordExecutablePath)) {
        $script:CnsMicrosoftWordAvailableCache = $true
        return $true
    }
    $word = $null
    try {
        $word = New-Object -ComObject Word.Application -ErrorAction Stop
        $script:CnsMicrosoftWordAvailableCache = ($null -ne $word)
    }
    catch {
        $script:CnsMicrosoftWordAvailableCache = $false
    }
    finally {
        if ($null -ne $word) {
            try { $word.DisplayAlerts = 0 } catch { }
            try { $word.Quit() } catch { }
            try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) } catch { }
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
        }
    }
    return [bool]$script:CnsMicrosoftWordAvailableCache
}

function script:Release-CnsWordComObject {
    param([object]$ComObject)
    if ($null -eq $ComObject) { return }
    try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($ComObject) } catch { }
}

function Get-CnsDocxToPdfConverterMode {
    $raw = [string]$env:CN_PDF_CONVERTER
    if ([string]::IsNullOrWhiteSpace($raw)) { return 'AUTO' }
    $m = $raw.Trim().ToUpperInvariant()
    switch ($m) {
        'AUTO' { return 'AUTO' }
        'LIBREOFFICE' { return 'LIBREOFFICE' }
        'WORD' { return 'WORD' }
        'NONE' { return 'NONE' }
        default {
            Write-Warning ("[DOCX-PDF] CN_PDF_CONVERTER valeur inconnue « {0} » — mode AUTO applique." -f $raw.Trim())
            return 'AUTO'
        }
    }
}

function Resolve-CnsDocxToPdfEngine {
    param([Parameter(Mandatory = $true)][string]$Mode)
    if ($Mode -eq 'NONE') {
        Write-Warning '[DOCX-PDF] Conversion desactivee (CN_PDF_CONVERTER=NONE).'
        return $null
    }
    $loOk = -not [string]::IsNullOrWhiteSpace((Get-CnsLibreOfficeSofficePath))
    $wordOk = Test-CnsMicrosoftWordAvailable
    switch ($Mode) {
        'LIBREOFFICE' {
            if ($loOk) { return 'LibreOffice' }
            Write-Warning '[DOCX-PDF] CN_PDF_CONVERTER=LIBREOFFICE mais soffice.exe introuvable. Definissez CN_LIBREOFFICE_SOFFICE ou installez LibreOffice.'
            return $null
        }
        'WORD' {
            if ($wordOk) { return 'Word' }
            Write-Warning '[DOCX-PDF] CN_PDF_CONVERTER=WORD mais Microsoft Word est indisponible. Installez Office ou definissez CN_WORD_APP.'
            return $null
        }
        default {
            if ($loOk) { return 'LibreOffice' }
            if ($wordOk) { return 'Word' }
            Write-Warning @'
[DOCX-PDF] Aucun convertisseur DOCX vers PDF disponible. Installez LibreOffice (recommande) ou Microsoft Word, ou definissez CN_LIBREOFFICE_SOFFICE / CN_WORD_APP. Variable CN_PDF_CONVERTER : AUTO, LIBREOFFICE, WORD, NONE.
'@
            return $null
        }
    }
}

function script:Write-CnsDocxToPdfLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Level = 'INFO',
        $Data = $null
    )
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log ("[DOCX-PDF] " + $Message) $Level $Data
        return
    }
    $color = switch ($Level) {
        'WARN' { 'Yellow' }
        'ERROR' { 'Red' }
        default { 'DarkGray' }
    }
    Write-Host ("[DOCX-PDF] {0}" -f $Message) -ForegroundColor $color
}

function Convert-DocxToPdfUsingWord {
  <#
  .SYNOPSIS
      Convertit un DOCX en PDF via Microsoft Word COM (ExportAsFixedFormat, wdFormatPDF = 17).
  #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DocxPath,
        [Parameter(Mandatory = $true)]
        [string]$PdfPath
    )
    if (-not (Test-CnsMicrosoftWordAvailable)) {
        Write-Warning '[DOCX-PDF] Microsoft Word indisponible pour la conversion.'
        return $false
    }
    if (-not (Test-Path -LiteralPath $DocxPath -PathType Leaf)) {
        Write-Warning ("[DOCX-PDF] DOCX source introuvable : {0}" -f $DocxPath)
        return $false
    }

    $docxAbs = [System.IO.Path]::GetFullPath($DocxPath)
    $pdfAbs = [System.IO.Path]::GetFullPath($PdfPath)
    $outDir = [System.IO.Path]::GetDirectoryName($pdfAbs)
    if (-not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop
    }

    $word = $null
    $doc = $null
    $wdFormatPDF = 17
    try {
        $word = New-Object -ComObject Word.Application -ErrorAction Stop
        $word.Visible = $false
        $word.DisplayAlerts = 0
        $doc = $word.Documents.Open($docxAbs, $false, $true)
        if ($null -eq $doc) {
            Write-Warning '[DOCX-PDF] Word n''a pas ouvert le document source.'
            return $false
        }
        $doc.ExportAsFixedFormat($pdfAbs, $wdFormatPDF)
    }
    catch {
        Write-Warning ("[DOCX-PDF] Conversion Word echouee : {0}" -f $_.Exception.Message)
        return $false
    }
    finally {
        if ($null -ne $doc) {
            try { $doc.Close($false) } catch { }
            script:Release-CnsWordComObject -ComObject $doc
            $doc = $null
        }
        if ($null -ne $word) {
            try { $word.Quit() } catch { }
            script:Release-CnsWordComObject -ComObject $word
            $word = $null
        }
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }

    if (-not (Test-Path -LiteralPath $pdfAbs)) {
        Write-Warning '[DOCX-PDF] PDF non produit apres conversion Word.'
        return $false
    }
    return $true
}

function Convert-DocxToPdf {
  <#
  .SYNOPSIS
      Convertit DOCX en PDF via le moteur choisi (CN_PDF_CONVERTER : AUTO, LIBREOFFICE, WORD, NONE).
  #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DocxPath,
        [Parameter(Mandatory = $true)]
        [string]$PdfPath
    )
    $mode = Get-CnsDocxToPdfConverterMode
    $engine = Resolve-CnsDocxToPdfEngine -Mode $mode
    if ([string]::IsNullOrWhiteSpace($engine)) {
        return $false
    }

    script:Write-CnsDocxToPdfLog -Message ("Moteur selectionne : {0} (mode={1})" -f $engine, $mode) -Level 'INFO' -Data @{
        Engine = $engine
        Mode   = $mode
        Docx   = $DocxPath
        Pdf    = $PdfPath
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = $false
    if ($engine -eq 'LibreOffice') {
        $ok = Convert-DocxToPdfUsingLibreOffice -DocxPath $DocxPath -PdfPath $PdfPath
    }
    else {
        $ok = Convert-DocxToPdfUsingWord -DocxPath $DocxPath -PdfPath $PdfPath
    }
    $sw.Stop()

    if ($ok) {
        script:Write-CnsDocxToPdfLog -Message ("Conversion reussie via {0} en {1} ms" -f $engine, $sw.ElapsedMilliseconds) -Level 'INFO'
    }
    else {
        script:Write-CnsDocxToPdfLog -Message ("Conversion echouee via {0} apres {1} ms (pas de bascule vers un autre moteur)" -f $engine, $sw.ElapsedMilliseconds) -Level 'WARN'
    }
    return $ok
}

$script:CnsWordMlNamespaceUri = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
$script:CnsWordMlXPathParagraph = '//*[local-name()="p" and namespace-uri()="http://schemas.openxmlformats.org/wordprocessingml/2006/main"]'
$script:CnsWordMlXPathTextInSubtree = './/*[local-name()="t" and namespace-uri()="http://schemas.openxmlformats.org/wordprocessingml/2006/main"]'

function Select-CnsWordMlNodes {
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlNode]$ContextNode,
        [Parameter(Mandatory = $true)][ValidateSet('Paragraph', 'Text')]
        [string]$NodeKind
    )
    $xpath = if ($NodeKind -eq 'Paragraph') { $script:CnsWordMlXPathParagraph } else { $script:CnsWordMlXPathTextInSubtree }
    return $ContextNode.SelectNodes($xpath)
}

function Get-CnsDocxWordContentXmlPaths {
    param([Parameter(Mandatory = $true)][string]$ExtractDir)
    $wordDir = Join-Path $ExtractDir 'word'
    if (-not (Test-Path -LiteralPath $wordDir)) { return @() }
    $names = @(
        'document.xml', 'footnotes.xml', 'endnotes.xml'
    )
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($n in $names) {
        $p = Join-Path $wordDir $n
        if (Test-Path -LiteralPath $p) { [void]$paths.Add($p) }
    }
    Get-ChildItem -LiteralPath $wordDir -File -Filter 'header*.xml' -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$paths.Add($_.FullName) }
    Get-ChildItem -LiteralPath $wordDir -File -Filter 'footer*.xml' -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$paths.Add($_.FullName) }
    return @($paths)
}

function Set-CnsWordMlWtElementText {
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlElement]$WtElement,
        [AllowNull()][string]$Text
    )
    $text = if ($null -eq $Text) { '' } else { [string]$Text }
    $doc = $WtElement.OwnerDocument
    $xmlNs = 'http://www.w3.org/XML/1998/namespace'
    while ($WtElement.HasChildNodes) {
        $WtElement.RemoveChild($WtElement.FirstChild) | Out-Null
    }
    if ($text -match '^\s|\s\s|\s$') {
        $null = $WtElement.SetAttribute('space', $xmlNs, 'preserve')
    }
    else {
        if ($WtElement.HasAttribute('space', $xmlNs)) {
            $WtElement.RemoveAttribute('space', $xmlNs)
        }
    }
    if ($text.Length -gt 0) {
        [void]$WtElement.AppendChild($doc.CreateTextNode($text))
    }
}

function Get-CnsPlaceholderReplacementSpansInText {
    param(
        [Parameter(Mandatory = $true)][string]$FullText,
        [Parameter(Mandatory = $true)][hashtable]$Placeholders
    )
    $spans = New-Object System.Collections.Generic.List[object]
    $keys = @(
        $Placeholders.Keys |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object { $_.Length } -Descending
    )
    foreach ($key in $keys) {
        $needle = ('{' + '{' + $key + '}' + '}')
        $val = ConvertTo-CnsDestructionCertificatePlaceholderValue -Value ([string]$Placeholders[$key])
        $idx = 0
        while (($idx = $FullText.IndexOf($needle, $idx, [System.StringComparison]::Ordinal)) -ge 0) {
            [void]$spans.Add([PSCustomObject]@{
                    Start = $idx
                    End   = $idx + $needle.Length
                    Key   = $key
                    Value = $val
                })
            $idx += $needle.Length
        }
    }
    $used = New-Object System.Collections.Generic.List[object]
    $final = New-Object System.Collections.Generic.List[object]
    foreach ($s in ($spans | Sort-Object Start)) {
        $conflict = $false
        foreach ($u in $used) {
            if ($s.Start -lt $u.End -and $s.End -gt $u.Start) {
                $conflict = $true
                break
            }
        }
        if (-not $conflict) {
            [void]$final.Add($s)
            [void]$used.Add([PSCustomObject]@{ Start = $s.Start; End = $s.End })
        }
    }
    return @($final | Sort-Object Start)
}

function Update-CnsWordParagraphWtNodesFromReplacements {
    <#
    .SYNOPSIS
        Ne modifie que les noeuds w:t couverts par une balise {{KEY}} ; le reste du paragraphe est laisse intact.
    #>
    param(
        [Parameter(Mandatory = $true)][array]$WtParts,
        [Parameter(Mandatory = $true)][array]$Replacements
    )
    if ($WtParts.Count -lt 1) { return }

    foreach ($repl in @($Replacements)) {
        $overlapping = @(
            $WtParts | Where-Object {
                $_.Start -lt $repl.End -and ($_.Start + $_.Length) -gt $repl.Start
            } | Sort-Object Start
        )
        if ($overlapping.Count -lt 1) { continue }
        $first = $true
        foreach ($part in $overlapping) {
            if ($first) {
                Set-CnsWordMlWtElementText -WtElement $part.Node -Text ([string]$repl.Value)
                $first = $false
            }
            else {
                Set-CnsWordMlWtElementText -WtElement $part.Node -Text ''
            }
        }
    }
}

function Get-CnsWordMlXmlDeclarationLine {
    param([Parameter(Mandatory = $true)][string]$XmlPath)
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    foreach ($line in [System.IO.File]::ReadLines($XmlPath, $utf8NoBom)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.TrimStart().StartsWith('<?xml', [System.StringComparison]::Ordinal)) {
            return $line.TrimEnd()
        }
        break
    }
    return $null
}

function Save-CnsWordMlXmlDocument {
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlDocument]$XmlDoc,
        [Parameter(Mandatory = $true)][string]$XmlPath,
        [AllowNull()][string]$DeclarationLine
    )
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $tempPath = $XmlPath + '.cnssave'
    $writerSettings = New-Object System.Xml.XmlWriterSettings
    $writerSettings.Encoding = $utf8NoBom
    $writerSettings.Indent = $false
    $writerSettings.OmitXmlDeclaration = [string]::IsNullOrWhiteSpace($DeclarationLine)
    $writerSettings.NewLineHandling = [System.Xml.NewLineHandling]::None
    $writer = [System.Xml.XmlWriter]::Create($tempPath, $writerSettings)
    try {
        $XmlDoc.Save($writer)
    }
    finally {
        $writer.Close()
    }

    $body = [System.IO.File]::ReadAllText($tempPath, $utf8NoBom)
    if (-not [string]::IsNullOrWhiteSpace($DeclarationLine)) {
        $body = [regex]::Replace($body, '^\uFEFF?\s*<\?xml[^>]*\?>\s*', '', 1)
        $body = $DeclarationLine + $body
    }
    [System.IO.File]::WriteAllText($XmlPath, $body, $utf8NoBom)
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
}

function Invoke-CnsDocxSafePlaceholderReplaceInXmlFile {
    param(
        [Parameter(Mandatory = $true)][string]$XmlPath,
        [Parameter(Mandatory = $true)][hashtable]$Placeholders
    )
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $origDecl = Get-CnsWordMlXmlDeclarationLine -XmlPath $XmlPath
    $readerSettings = New-Object System.Xml.XmlReaderSettings
    $readerSettings.IgnoreWhitespace = $false
    $reader = [System.Xml.XmlReader]::Create($XmlPath, $readerSettings)
    $xmlDoc = New-Object System.Xml.XmlDocument
    $xmlDoc.PreserveWhitespace = $true
    $xmlDoc.Load($reader)
    $reader.Close()

    $fileReplaced = 0
    $paragraphs = Select-CnsWordMlNodes -ContextNode $xmlDoc -NodeKind 'Paragraph'
    if ($null -eq $paragraphs -or $paragraphs.Count -lt 1) { return 0 }

    foreach ($paragraph in @($paragraphs)) {
        $wtNodes = Select-CnsWordMlNodes -ContextNode $paragraph -NodeKind 'Text'
        if ($null -eq $wtNodes -or $wtNodes.Count -lt 1) { continue }

        $wtParts = New-Object System.Collections.Generic.List[object]
        $sb = [System.Text.StringBuilder]::new()
        foreach ($wt in @($wtNodes)) {
            $txt = $wt.InnerText
            if ($null -eq $txt) { $txt = '' }
            $start = $sb.Length
            [void]$sb.Append($txt)
            [void]$wtParts.Add([PSCustomObject]@{
                    Node   = $wt
                    Start  = $start
                    Length = $txt.Length
                })
        }

        $oldFull = $sb.ToString()
        if ($oldFull.IndexOf('{{', [System.StringComparison]::Ordinal) -lt 0) { continue }

        $replacements = @(Get-CnsPlaceholderReplacementSpansInText -FullText $oldFull -Placeholders $Placeholders)
        if ($replacements.Count -lt 1) { continue }

        Update-CnsWordParagraphWtNodesFromReplacements -WtParts $wtParts.ToArray() -Replacements @($replacements)
        $fileReplaced += $replacements.Count
        foreach ($r in $replacements) {
            Write-Host ("[DESTRUCTION-CERT] {0} -> `"{1}`" (w:t safe)" -f $r.Key, $r.Value) -ForegroundColor DarkCyan
        }
    }

    $layoutChanged = $false
    if ($XmlPath -match '(?i)[\\/]document\.xml$') {
        $layoutChanged = Invoke-CnsDocxRepairCertificateTitleCenteringInXmlDocument -XmlDoc $xmlDoc
    }

    if ($fileReplaced -gt 0 -or $layoutChanged) {
        Save-CnsWordMlXmlDocument -XmlDoc $xmlDoc -XmlPath $XmlPath -DeclarationLine $origDecl
    }

    if ($fileReplaced -lt 1 -and $layoutChanged) { return 1 }
    return $fileReplaced
}

function Get-CnsDocxEntryRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$ExtractDir,
        [Parameter(Mandatory = $true)][string]$FullPath
    )
    $root = [System.IO.Path]::GetFullPath($ExtractDir)
    if (-not $root.EndsWith('\')) { $root += '\' }
    $full = [System.IO.Path]::GetFullPath($FullPath)
    if (-not $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return [System.IO.Path]::GetFileName($full)
    }
    return $full.Substring($root.Length).Replace('\', '/')
}

function Publish-CnsDocxModifiedPartsToArchive {
    <#
    .SYNOPSIS
        Met a jour uniquement les entrees modifiees dans le ZIP DOCX (preserve media, Content_Types, relations).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$DocxPath,
        [Parameter(Mandatory = $true)][string]$ExtractDir,
        [Parameter(Mandatory = $true)][string[]]$ModifiedRelativePaths
    )
    if ($ModifiedRelativePaths.Count -lt 1) { return }

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $docxAbs = [System.IO.Path]::GetFullPath($DocxPath)
    $archive = [System.IO.Compression.ZipFile]::Open($docxAbs, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        foreach ($rel in @($ModifiedRelativePaths)) {
            if ([string]::IsNullOrWhiteSpace($rel)) { continue }
            $relNorm = ([string]$rel).Replace('\', '/')
            $diskPath = Join-Path $ExtractDir ($relNorm.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
            if (-not (Test-Path -LiteralPath $diskPath)) {
                throw ("[DESTRUCTION-CERT] Fichier extrait introuvable pour entree ZIP : {0}" -f $relNorm)
            }
            $existing = $archive.GetEntry($relNorm)
            if ($null -ne $existing) { $existing.Delete() }
            $entry = $archive.CreateEntry($relNorm, [System.IO.Compression.CompressionLevel]::Optimal)
            $input = [System.IO.File]::OpenRead($diskPath)
            try {
                $output = $entry.Open()
                try {
                    $input.CopyTo($output)
                }
                finally {
                    $output.Dispose()
                }
            }
            finally {
                $input.Dispose()
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Set-CnsDocxTemplatePlaceholders {
    <#
    .SYNOPSIS
        Remplace {{KEY}} dans les noeuds w:t uniquement (WordML structure preservee). Repackage ZIP par entrees, sans CreateFromDirectory.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DocxPath,
        [Parameter(Mandatory = $true)]
        [hashtable]$Placeholders
    )
    if (-not (Test-Path -LiteralPath $DocxPath)) { return $false }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $docxAbs = [System.IO.Path]::GetFullPath($DocxPath)
    $workDir = Join-Path $env:TEMP ('cn_docx_unzip_' + [Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $workDir -Force
    $totalReplaced = 0
    $modifiedRelPaths = New-Object System.Collections.Generic.List[string]

    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($docxAbs, $workDir)

        foreach ($xmlPath in @(Get-CnsDocxWordContentXmlPaths -ExtractDir $workDir)) {
            $n = [int](Invoke-CnsDocxSafePlaceholderReplaceInXmlFile -XmlPath $xmlPath -Placeholders $Placeholders)
            if ($n -gt 0) {
                $totalReplaced += $n
                [void]$modifiedRelPaths.Add((Get-CnsDocxEntryRelativePath -ExtractDir $workDir -FullPath $xmlPath))
            }
        }

        if ($totalReplaced -lt 1 -and $Placeholders.Count -gt 0) {
            Write-Warning '[DESTRUCTION-CERT] Aucun placeholder remplace (verifier template DOCX / balises {{KEY}}).'
            return $false
        }

        Publish-CnsDocxModifiedPartsToArchive -DocxPath $docxAbs -ExtractDir $workDir -ModifiedRelativePaths @($modifiedRelPaths)
        return $true
    }
    catch {
        Write-Warning ("[DESTRUCTION-CERT] Remplacement placeholders DOCX echoue : {0}" -f $_.Exception.Message)
        return $false
    }
    finally {
        if (Test-Path -LiteralPath $workDir) {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Repair-CnsClientNumeroSignText {
    <#
    .SYNOPSIS
        Corrige N? / N (U+FFFD) / mojibake en N° avant affichage certificat ou page de garde.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { return '' }
    $t = [string]$Text
    if ($t.Length -lt 1) { return $t }
    $t = $t.Replace('N┬░', 'N°')
    $t = [regex]::Replace($t, '(?i)N\s*\?\s*(?=\d)', 'N°')
    $t = [regex]::Replace($t, 'N\s*\uFFFD\s*(?=\d)', 'N°')
    return $t
}

function Get-CnsWordMlParagraphPlainText {
    param([Parameter(Mandatory = $true)][System.Xml.XmlElement]$Paragraph)
    $wtNodes = Select-CnsWordMlNodes -ContextNode $Paragraph -NodeKind 'Text'
    if ($null -eq $wtNodes -or $wtNodes.Count -lt 1) { return '' }
    $sb = [System.Text.StringBuilder]::new()
    foreach ($wt in @($wtNodes)) {
        $txt = $wt.InnerText
        if ($null -eq $txt) { $txt = '' }
        [void]$sb.Append($txt)
    }
    return $sb.ToString()
}

function Set-CnsWordMlParagraphJc {
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlElement]$Paragraph,
        [ValidateSet('center', 'left', 'right', 'both')]
        [string]$Alignment = 'center'
    )
    $doc = $Paragraph.OwnerDocument
    $ns = $script:CnsWordMlNamespaceUri
    $pPr = $Paragraph.SelectSingleNode('./*[local-name()="pPr" and namespace-uri()="' + $ns + '"]')
    if ($null -eq $pPr) {
        $pPr = $doc.CreateElement('pPr', $ns)
        if ($Paragraph.FirstChild) {
            $null = $Paragraph.InsertBefore($pPr, $Paragraph.FirstChild)
        }
        else {
            [void]$Paragraph.AppendChild($pPr)
        }
    }
    $jc = $pPr.SelectSingleNode('./*[local-name()="jc" and namespace-uri()="' + $ns + '"]')
    if ($null -eq $jc) {
        $jc = $doc.CreateElement('jc', $ns)
        [void]$pPr.AppendChild($jc)
    }
    $null = $jc.SetAttribute('val', $ns, $Alignment)
}

function Invoke-CnsDocxRepairCertificateTitleCenteringInXmlDocument {
    <#
    .SYNOPSIS
        Titre « Certificat de destruction » : cellule pleine largeur + paragraphe centré (le template a logo + titre côte à côte).
    #>
    param([Parameter(Mandatory = $true)][System.Xml.XmlDocument]$XmlDoc)

    # Annulation : le centrage du titre a provoque un decalage et la disparition du logo.
    # On no-op volontairement pour revenir a la mise en page d'origine du template.
    return $false

    $ns = $script:CnsWordMlNamespaceUri
    $changed = $false
    $paragraphs = Select-CnsWordMlNodes -ContextNode $XmlDoc -NodeKind 'Paragraph'
    if ($null -eq $paragraphs -or $paragraphs.Count -lt 1) { return $false }

    foreach ($paragraph in @($paragraphs)) {
        $plain = Get-CnsWordMlParagraphPlainText -Paragraph $paragraph
        if ($plain -notmatch '(?i)Certificat\s+de\s+destructio') { continue }

        Set-CnsWordMlParagraphJc -Paragraph $paragraph -Alignment 'center'
        $changed = $true

        $row = $paragraph.SelectSingleNode('ancestor::*[local-name()="tr" and namespace-uri()="' + $ns + '"][1]')
        if ($null -eq $row) { continue }

        $cells = @($row.SelectNodes('./*[local-name()="tc" and namespace-uri()="' + $ns + '"]'))
        if ($cells.Count -lt 2) { continue }

        $titleCell = $paragraph.SelectSingleNode('ancestor::*[local-name()="tc" and namespace-uri()="' + $ns + '"][1]')
        if ($null -eq $titleCell) { continue }

        if ($cells[0] -ne $titleCell) {
            $null = $row.RemoveChild($cells[0])
            $changed = $true
        }

        $tcPr = $titleCell.SelectSingleNode('./*[local-name()="tcPr" and namespace-uri()="' + $ns + '"]')
        if ($null -eq $tcPr) {
            $tcPr = $XmlDoc.CreateElement('tcPr', $ns)
            if ($titleCell.FirstChild) {
                $null = $titleCell.InsertBefore($tcPr, $titleCell.FirstChild)
            }
            else {
                [void]$titleCell.AppendChild($tcPr)
            }
            $changed = $true
        }

        $gridSpan = $tcPr.SelectSingleNode('./*[local-name()="gridSpan" and namespace-uri()="' + $ns + '"]')
        if ($null -eq $gridSpan) {
            $gridSpan = $XmlDoc.CreateElement('gridSpan', $ns)
            [void]$tcPr.AppendChild($gridSpan)
            $changed = $true
        }
        if ($gridSpan.GetAttribute('val', $ns) -ne '5') {
            $null = $gridSpan.SetAttribute('val', $ns, '5')
            $changed = $true
        }

        $tcW = $tcPr.SelectSingleNode('./*[local-name()="tcW" and namespace-uri()="' + $ns + '"]')
        if ($null -eq $tcW) {
            $tcW = $XmlDoc.CreateElement('tcW', $ns)
            [void]$tcPr.AppendChild($tcW)
            $changed = $true
        }
        if ($tcW.GetAttribute('type', $ns) -ne 'dxa') {
            $null = $tcW.SetAttribute('type', $ns, 'dxa')
            $changed = $true
        }
        if ($tcW.GetAttribute('w', $ns) -ne '10939') {
            $null = $tcW.SetAttribute('w', $ns, '10939')
            $changed = $true
        }

        $tbl = $row.SelectSingleNode('ancestor::*[local-name()="tbl" and namespace-uri()="' + $ns + '"][1]')
        if ($null -ne $tbl) {
            $tblInd = $tbl.SelectSingleNode('./*[local-name()="tblPr" and namespace-uri()="' + $ns + '"]/*[local-name()="tblInd" and namespace-uri()="' + $ns + '"]')
            if ($null -ne $tblInd -and $tblInd.GetAttribute('w', $ns) -ne '0') {
                $null = $tblInd.SetAttribute('w', $ns, '0')
                $changed = $true
            }
        }
        break
    }

    return $changed
}

function Invoke-CnsDocxRepairCertificateTitleCenteringInXmlFile {
    param([Parameter(Mandatory = $true)][string]$XmlPath)
    if (-not (Test-Path -LiteralPath $XmlPath)) { return $false }

    $origDecl = Get-CnsWordMlXmlDeclarationLine -XmlPath $XmlPath
    $readerSettings = New-Object System.Xml.XmlReaderSettings
    $readerSettings.IgnoreWhitespace = $false
    $reader = [System.Xml.XmlReader]::Create($XmlPath, $readerSettings)
    $xmlDoc = New-Object System.Xml.XmlDocument
    $xmlDoc.PreserveWhitespace = $true
    $xmlDoc.Load($reader)
    $reader.Close()

    $changed = Invoke-CnsDocxRepairCertificateTitleCenteringInXmlDocument -XmlDoc $xmlDoc
    if ($changed) {
        Save-CnsWordMlXmlDocument -XmlDoc $xmlDoc -XmlPath $XmlPath -DeclarationLine $origDecl
    }
    return $changed
}

function ConvertTo-CnsDestructionCertificatePlaceholderValue {
    <#
    .SYNOPSIS
        Valeur pour le DOCX : donnée réelle ou chaîne vide (jamais de texte de remplacement type "À compléter").
    #>
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '' }
    $t = Repair-CnsClientNumeroSignText -Text (([string]$Value).Trim())
    if ([string]::IsNullOrWhiteSpace($t)) { return '' }
    $norm = $t.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $norm.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    $plain = $sb.ToString().ToUpperInvariant()
    $sentinels = @(
        '-', '--', '—', '?', 'N/A', 'NA', 'ND', 'INCONNU', 'NON SPECIFIE', 'NON SPECIFIE',
        'A COMPLETER', 'A RENSEIGNER', 'NON RENSEIGNE', 'NON RENSEIGNEE', 'VIDE', 'TBD'
    )
    foreach ($s in $sentinels) {
        if ($plain -eq $s) { return '' }
    }
    if ($plain -match '^(A|A)\s*COMPL') { return '' }
    if ($plain -match 'COMPLETER') { return '' }
    return $t
}

function Split-CnsCollecteurNomPrenom {
    param([AllowNull()][AllowEmptyString()][string]$CollecteurText)
    $t = ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $CollecteurText
    if ([string]::IsNullOrWhiteSpace($t)) {
        return @{ Nom = ''; Prenom = '' }
    }
    $parts = @(
        ($t -split '\s+') |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($parts.Count -lt 2) {
        return @{ Nom = $parts[0]; Prenom = '' }
    }
    return @{
        Prenom = $parts[0]
        Nom    = (($parts | Select-Object -Skip 1) -join ' ')
    }
}

function Normalize-CnsCertificateAgentLookupKey {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    $t = ([string]$Text).Trim()
    if ([string]::IsNullOrWhiteSpace($t)) { return '' }
    $norm = $t.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $norm.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString().ToUpperInvariant()
}

function Initialize-CnsCertificateAgentDbAccess {
    if ($script:CnsCertAgentDbLoadAttempted) { return }
    $script:CnsCertAgentDbLoadAttempted = $true
    $dbScript = Join-Path $PSScriptRoot '..\..\..\Database\Database.ps1'
    if (-not (Test-Path -LiteralPath $dbScript)) {
        Write-Warning ("[DESTRUCTION-CERT] Database.ps1 introuvable : {0}" -f $dbScript)
        return
    }
    try {
        . $dbScript
    }
    catch {
        Write-Warning ("[DESTRUCTION-CERT] Chargement Database.ps1 echoue : {0}" -f $_.Exception.Message)
    }
}

function Get-CnsCertificateAgentCatalog {
    if ($null -ne $script:CnsCertAgentCatalog) {
        return @($script:CnsCertAgentCatalog)
    }
    $script:CnsCertAgentCatalog = @()
    Initialize-CnsCertificateAgentDbAccess
    if (-not (Get-Command Get-Agents -ErrorAction SilentlyContinue)) {
        return @()
    }
    try {
        $script:CnsCertAgentCatalog = @(Get-Agents)
        Write-Host ("[DESTRUCTION-CERT] Catalogue Agent charge ({0} actifs)." -f $script:CnsCertAgentCatalog.Count) -ForegroundColor DarkGray
    }
    catch {
        Write-Warning ("[DESTRUCTION-CERT] Get-Agents echoue : {0}" -f $_.Exception.Message)
        $script:CnsCertAgentCatalog = @()
    }
    return @($script:CnsCertAgentCatalog)
}

function Find-CnsAgentNomByPrenomForCertificate {
    <#
    .SYNOPSIS
        Recherche Agent.nom par prenom (match exact normalise). Retourne $null si absent.
    #>
    param([AllowNull()][string]$PrenomSearch)
    $key = Normalize-CnsCertificateAgentLookupKey -Text $PrenomSearch
    if ([string]::IsNullOrWhiteSpace($key)) { return $null }

    $agentHits = New-Object System.Collections.Generic.List[object]
    foreach ($agent in @(Get-CnsCertificateAgentCatalog)) {
        if ($null -eq $agent) { continue }
        try {
            $ap = Normalize-CnsCertificateAgentLookupKey -Text ([string]$agent.prenom)
            if ($ap -eq $key) { [void]$agentHits.Add($agent) }
        }
        catch { }
    }
    if ($agentHits.Count -lt 1) { return $null }

    $chosen = $agentHits[0]
    for ($i = 0; $i -lt $agentHits.Count; $i++) {
        $agent = $agentHits[$i]
        try {
            $poste = Normalize-CnsCertificateAgentLookupKey -Text ([string]$agent.poste)
            if ($poste -match 'COLLECTEUR') { $chosen = $agent; break }
        }
        catch { }
    }

    try {
        $nom = [string]$chosen.nom
        if ([string]::IsNullOrWhiteSpace($nom)) { return $null }
        return $nom.Trim()
    }
    catch {
        return $null
    }
}

function Resolve-CnsCollecteurFieldsForCertificate {
    <#
    .SYNOPSIS
        Prenom depuis Excel (segment) ; Nom depuis BDD Agent (match prenom) sinon fallback split Excel.
    #>
    param([AllowNull()][string]$CollecteurExcelRaw)
    $npExcel = Split-CnsCollecteurNomPrenom -CollecteurText $CollecteurExcelRaw
    [string]$prenomOut = [string]$npExcel.Prenom
    if ([string]::IsNullOrWhiteSpace($prenomOut)) {
        $t = ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $CollecteurExcelRaw
        if (-not [string]::IsNullOrWhiteSpace($t)) {
            $prenomOut = (($t -split '\s+') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
        }
    }

    [string]$nomOut = [string]$npExcel.Nom
    $nomBdd = Find-CnsAgentNomByPrenomForCertificate -PrenomSearch $prenomOut
    if (-not [string]::IsNullOrWhiteSpace($nomBdd)) {
        $nomOut = $nomBdd
        Write-Host ("[DESTRUCTION-CERT] Collecteur_Nom depuis BDD Agent (prenom={0}, nom={1})." -f $prenomOut, $nomOut) -ForegroundColor DarkCyan
    }
    elseif (-not [string]::IsNullOrWhiteSpace($nomOut)) {
        Write-Host ("[DESTRUCTION-CERT] Collecteur_Nom depuis Excel (fallback split, prenom={0})." -f $prenomOut) -ForegroundColor DarkGray
    }

    return @{
        Prenom = $prenomOut
        Nom    = $nomOut
    }
}

function Get-CnsDestructionCertificatePlaceholders {
    param(
        [Parameter(Mandatory = $true)]
        $WorkOrderEntity,
        [AllowNull()]
        $SegmentMeta,
        [Parameter(Mandatory = $true)]
        [datetime]$VisitDate
    )
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    [string]$dateCollecte = $VisitDate.ToString('dd/MM/yyyy', $inv)

    [string]$clientId = ''
    [string]$clientNom = ''
    [string]$street = ''
    [string]$cp = ''
    [string]$ville = ''
    [string]$odmNum = ''
    try { $clientId = [string]$WorkOrderEntity.ClientID } catch { }
    try { $clientNom = [string]$WorkOrderEntity.ClientName } catch { }
    try { $odmNum = [string]$WorkOrderEntity.WorkOrder } catch { }
    if ([string]::IsNullOrWhiteSpace($odmNum)) {
        foreach ($svc in @($WorkOrderEntity.Services)) {
            if ($null -eq $svc) { continue }
            try {
                $od = [string]$svc.ODM
                if (-not [string]::IsNullOrWhiteSpace($od)) { $odmNum = $od.Trim(); break }
            }
            catch { }
        }
    }
    if ($null -ne $WorkOrderEntity.Address) {
        try { $street = [string]$WorkOrderEntity.Address.Street } catch { }
        try { $cp = [string]$WorkOrderEntity.Address.PostalCode } catch { }
        try { $ville = [string]$WorkOrderEntity.Address.City } catch { }
    }

    [string]$collecteurRaw = ''
    [string]$vehicule = ''
    if ($null -ne $SegmentMeta) {
        try { $collecteurRaw = [string]$SegmentMeta.Collecteur } catch { }
        try { $vehicule = [string]$SegmentMeta.Vehicule } catch { }
    }
    $collecteurResolved = Resolve-CnsCollecteurFieldsForCertificate -CollecteurExcelRaw $collecteurRaw

    return [ordered]@{
        Date_Collecte     = $dateCollecte
        Client_ID         = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $clientId)
        Client_Nom        = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $clientNom)
        Client_Adresse    = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $street)
        Client_CP         = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $cp)
        Client_Ville      = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $ville)
        Collecteur_Nom    = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value ([string]$collecteurResolved.Nom))
        Collecteur_Prenom = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value ([string]$collecteurResolved.Prenom))
        Vehicule_Immat    = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $vehicule)
        ODM_Numero        = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $odmNum)
    }
}

function New-CnsDestructionCertificatePdfFromWordTemplate {
    <#
    .SYNOPSIS
        Remplit le template DOCX (placeholders) et exporte un PDF (LibreOffice ou Word). Retourne le chemin PDF ou $null.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutPdfPath,
        [Parameter(Mandatory = $true)]
        [hashtable]$Placeholders,
        [string]$TemplatePath
    )
    if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
        $TemplatePath = Get-CnsDestructionCertificateTemplatePath
    }
    if ([string]::IsNullOrWhiteSpace($TemplatePath) -or -not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
        Write-Warning '[DESTRUCTION-CERT] Template DOCX introuvable (templates\CertificatDeDestruction.docx ou CN_DESTRUCTION_CERT_TEMPLATE).'
        return $null
    }

    $outAbs = [System.IO.Path]::GetFullPath($OutPdfPath)
    $outDir = Split-Path -Parent $outAbs
    if (-not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop
    }

    $runId = [Guid]::NewGuid().ToString('N')
    $workDocx = Join-Path $env:TEMP ("cn_destr_cert_{0}.docx" -f $runId)
    Copy-Item -LiteralPath $TemplatePath -Destination $workDocx -Force

    try {
        if (-not (Set-CnsDocxTemplatePlaceholders -DocxPath $workDocx -Placeholders $Placeholders)) {
            return $null
        }
        if (-not (Convert-DocxToPdf -DocxPath $workDocx -PdfPath $outAbs)) {
            return $null
        }
    }
    finally {
        if (Test-Path -LiteralPath $workDocx) {
            if (-not [string]::IsNullOrWhiteSpace($env:CN_KEEP_DESTRUCTION_CERT_DOCX)) {
                Write-Host ("[DESTRUCTION-CERT] DOCX conserve (CN_KEEP_DESTRUCTION_CERT_DOCX) : {0}" -f $workDocx) -ForegroundColor DarkYellow
            }
            else {
                Remove-Item -LiteralPath $workDocx -Force -ErrorAction SilentlyContinue
            }
        }
        $loPdfSide = Join-Path $env:TEMP ([System.IO.Path]::GetFileNameWithoutExtension($workDocx) + '.pdf')
        if (Test-Path -LiteralPath $loPdfSide) {
            Remove-Item -LiteralPath $loPdfSide -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not (Test-Path -LiteralPath $outAbs)) {
        Write-Warning '[DESTRUCTION-CERT] PDF non produit apres conversion DOCX vers PDF.'
        return $null
    }
    return $outAbs
}

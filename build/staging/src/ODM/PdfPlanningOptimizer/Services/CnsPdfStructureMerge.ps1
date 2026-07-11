# Fusion PDF structure-preserving (qpdf / pdftk) — sans pdfwrite Ghostscript.
# Objectif : ne jamais réinterpréter les PDF LibreOffice (certificat destruction).

function Get-CnsQpdfExecutablePath {
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($envName in @('CN_QPDF_EXE', 'QPDF_EXE')) {
        $raw = [Environment]::GetEnvironmentVariable($envName, 'Process')
        if ([string]::IsNullOrWhiteSpace($raw)) { $raw = [Environment]::GetEnvironmentVariable($envName, 'User') }
        if ([string]::IsNullOrWhiteSpace($raw)) { $raw = [Environment]::GetEnvironmentVariable($envName, 'Machine') }
        if (-not [string]::IsNullOrWhiteSpace($raw)) { [void]$candidates.Add($raw.Trim().Trim('"')) }
    }
    $c = Get-Command qpdf -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $c -and (Test-Path -LiteralPath $c.Source)) { [void]$candidates.Add($c.Source) }
    try {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
        [void]$candidates.Add((Join-Path $repoRoot 'lib\qpdf\bin\qpdf.exe'))
    }
    catch { }
    foreach ($p in @(
            "${env:ProgramFiles}\qpdf\bin\qpdf.exe",
            "${env:ProgramFiles(x86)}\qpdf\bin\qpdf.exe",
            'C:\Program Files\qpdf\bin\qpdf.exe'
        )) {
        if (-not [string]::IsNullOrWhiteSpace($p)) { [void]$candidates.Add($p) }
    }
    foreach ($p in @($candidates)) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            return ([System.IO.Path]::GetFullPath($p))
        }
    }
    return $null
}

function Get-CnsPdftkExecutablePath {
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($envName in @('CN_PDFTK_EXE', 'PDFTK_EXE')) {
        $raw = [Environment]::GetEnvironmentVariable($envName, 'Process')
        if ([string]::IsNullOrWhiteSpace($raw)) { $raw = [Environment]::GetEnvironmentVariable($envName, 'User') }
        if ([string]::IsNullOrWhiteSpace($raw)) { $raw = [Environment]::GetEnvironmentVariable($envName, 'Machine') }
        if (-not [string]::IsNullOrWhiteSpace($raw)) { [void]$candidates.Add($raw.Trim().Trim('"')) }
    }
    $c = Get-Command pdftk -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $c -and (Test-Path -LiteralPath $c.Source)) { [void]$candidates.Add($c.Source) }
    foreach ($p in @(
            "${env:ProgramFiles}\PDF24\pdftk.exe",
            "${env:ProgramFiles(x86)}\PDF24\pdftk.exe",
            "${env:ProgramFiles}\PDFtk Server\bin\pdftk.exe"
        )) {
        if (-not [string]::IsNullOrWhiteSpace($p)) { [void]$candidates.Add($p) }
    }
    foreach ($p in @($candidates)) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            return ([System.IO.Path]::GetFullPath($p))
        }
    }
    return $null
}

function Get-CnsPdfFontStructureMarkers {
    <#
    .SYNOPSIS
        Indicateurs binaires rapides : ToUnicode, FontFile2, TrueType, Type0, taille, pages (via /Type /Page).
    #>
    param([Parameter(Mandatory = $true)][string]$PdfPath)
    if (-not (Test-Path -LiteralPath $PdfPath)) { return $null }
    $bytes = [System.IO.File]::ReadAllBytes($PdfPath)
    $ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
    $pageCount = ([regex]::Matches($ascii, '/Type\s*/Page\b')).Count
    if ($pageCount -lt 1) { $pageCount = 1 }
    return [PSCustomObject]@{
        Path           = ([System.IO.Path]::GetFullPath($PdfPath))
        FileName       = [System.IO.Path]::GetFileName($PdfPath)
        ByteLength     = $bytes.Length
        PageCountGuess = $pageCount
        ToUnicode      = ([regex]::Matches($ascii, '/ToUnicode')).Count
        FontFile2      = ([regex]::Matches($ascii, '/FontFile2')).Count
        FontFile3      = ([regex]::Matches($ascii, '/FontFile3')).Count
        TrueType       = ([regex]::Matches($ascii, '/Subtype\s*/TrueType')).Count
        Type0          = ([regex]::Matches($ascii, '/Subtype\s*/Type0')).Count
    }
}

function Test-CnsPdfFontStructureDegradedAfterMerge {
    param(
        [Parameter(Mandatory = $true)][PSCustomObject]$Before,
        [Parameter(Mandatory = $true)][PSCustomObject]$After
    )
    $issues = New-Object System.Collections.Generic.List[string]
    if ($Before.ToUnicode -gt 0 -and $After.ToUnicode -lt $Before.ToUnicode) {
        [void]$issues.Add(('ToUnicode {0} -> {1}' -f $Before.ToUnicode, $After.ToUnicode))
    }
    if ($Before.FontFile2 -gt 0 -and $After.FontFile2 -lt $Before.FontFile2) {
        [void]$issues.Add(('FontFile2 {0} -> {1}' -f $Before.FontFile2, $After.FontFile2))
    }
    if ($Before.TrueType -gt 0 -and $After.TrueType -lt $Before.TrueType) {
        [void]$issues.Add(('TrueType {0} -> {1}' -f $Before.TrueType, $After.TrueType))
    }
    if ($Before.ByteLength -gt 4096 -and $After.ByteLength -lt [int]($Before.ByteLength * 0.55)) {
        [void]$issues.Add(('ByteLength chute {0} -> {1}' -f $Before.ByteLength, $After.ByteLength))
    }
    return @{
        Degraded = ($issues.Count -gt 0)
        Issues   = @($issues)
    }
}

function Write-CnsDestructionCertificatePdfMergeAudit {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('BEFORE_MERGE', 'AFTER_MERGE', 'GENERATED')]
        [string]$Phase,
        [Parameter(Mandatory = $true)][string]$PdfPath
    )
    return (Write-CnsLibreOfficePdfMergeAudit -Phase $Phase -PdfPath $PdfPath -DocumentKind 'DESTRUCTION-CERT')
}

function Test-CnsPdfPathIsDestructionCertificateFragment {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $leaf = [System.IO.Path]::GetFileName($Path)
    return ($leaf -match '(?i)^cert_dest_.*\.pdf$')
}

function Test-CnsPdfPathIsBilanCollecteFragment {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $leaf = [System.IO.Path]::GetFileName($Path)
    return ($leaf -match '(?i)^bilan_seg_.*\.pdf$')
}

function Test-CnsPdfPathIsLibreOfficeStep5Fragment {
    <#
    .SYNOPSIS
        PDF produits par LibreOffice (certificat, bilan) — ne jamais repasser dans pdfwrite.
    #>
    param([AllowNull()][string]$Path)
    if (Test-CnsPdfPathIsDestructionCertificateFragment -Path $Path) { return $true }
    if (Test-CnsPdfPathIsBilanCollecteFragment -Path $Path) { return $true }
    return $false
}

function Write-CnsLibreOfficePdfMergeAudit {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('BEFORE_MERGE', 'AFTER_MERGE', 'GENERATED')]
        [string]$Phase,
        [Parameter(Mandatory = $true)][string]$PdfPath,
        [Parameter(Mandatory = $true)][ValidateSet('DESTRUCTION-CERT', 'BILAN-COLLECTE', 'PDF-FINAL')]
        [string]$DocumentKind
    )
    $m = Get-CnsPdfFontStructureMarkers -PdfPath $PdfPath
    if ($null -eq $m) {
        Write-Host ("[{0}] LIBREOFFICE PDF {1} : {2} (introuvable)" -f $DocumentKind, $Phase, $PdfPath) -ForegroundColor Yellow
        return $null
    }
    $color = if ($Phase -eq 'AFTER_MERGE') { 'Cyan' } elseif ($Phase -eq 'BEFORE_MERGE') { 'DarkCyan' } else { 'Green' }
    Write-Host (
        "[{0}] LIBREOFFICE PDF {1} : {2} | {3} bytes | pages~{4} | ToUnicode={5} FontFile2={6} TrueType={7} Type0={8}" -f
        $DocumentKind,
        $Phase,
        $m.FileName,
        $m.ByteLength,
        $m.PageCountGuess,
        $m.ToUnicode,
        $m.FontFile2,
        $m.TrueType,
        $m.Type0
    ) -ForegroundColor $color
    return $m
}

function Merge-CnsPdfFilesQpdfOrdered {
    param(
        [Parameter(Mandatory = $true)][string[]]$InputPdfsOrdered,
        [Parameter(Mandatory = $true)][string]$DestinationPdfPath
    )
    $qpdf = Get-CnsQpdfExecutablePath
    if ([string]::IsNullOrWhiteSpace($qpdf)) { return $false }

    $paths = @(
        $InputPdfsOrdered |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) } |
            ForEach-Object { [System.IO.Path]::GetFullPath($_) }
    )
    if ($paths.Count -lt 1) { return $false }

    $outAbs = [System.IO.Path]::GetFullPath($DestinationPdfPath)
    $outDir = [System.IO.Path]::GetDirectoryName($outAbs)
    if (-not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Path $outDir -Force
    }

    $args = New-Object System.Collections.Generic.List[string]
    [void]$args.Add('--warning-exit-0')
    [void]$args.Add('--empty')
    [void]$args.Add('--pages')
    foreach ($p in $paths) {
        [void]$args.Add($p)
        [void]$args.Add('1-z')
    }
    [void]$args.Add('--')
    [void]$args.Add($outAbs)

    try {
        $proc = Start-Process -FilePath $qpdf -ArgumentList @($args.ToArray()) -Wait -PassThru -NoNewWindow -ErrorAction Stop
        return ($null -ne $proc -and $proc.ExitCode -eq 0 -and (Test-Path -LiteralPath $outAbs))
    }
    catch {
        Write-Warning ("[PDF-MERGE] qpdf echoue : {0}" -f $_.Exception.Message)
        return $false
    }
}

function Merge-CnsPdfFilesPdftkOrdered {
    param(
        [Parameter(Mandatory = $true)][string[]]$InputPdfsOrdered,
        [Parameter(Mandatory = $true)][string]$DestinationPdfPath
    )
    $pdftk = Get-CnsPdftkExecutablePath
    if ([string]::IsNullOrWhiteSpace($pdftk)) { return $false }

    $paths = @(
        $InputPdfsOrdered |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_) } |
            ForEach-Object { [System.IO.Path]::GetFullPath($_) }
    )
    if ($paths.Count -lt 1) { return $false }

    $outAbs = [System.IO.Path]::GetFullPath($DestinationPdfPath)
    $argList = New-Object System.Collections.Generic.List[string]
    foreach ($p in $paths) { [void]$argList.Add($p) }
    [void]$argList.Add('cat')
    [void]$argList.Add('output')
    [void]$argList.Add($outAbs)

    try {
        $proc = Start-Process -FilePath $pdftk -ArgumentList @($argList.ToArray()) -Wait -PassThru -NoNewWindow -ErrorAction Stop
        return ($null -ne $proc -and $proc.ExitCode -eq 0 -and (Test-Path -LiteralPath $outAbs))
    }
    catch {
        Write-Warning ("[PDF-MERGE] pdftk echoue : {0}" -f $_.Exception.Message)
        return $false
    }
}

function Merge-CnsPdfFilesStructurePreservingOrdered {
    <#
    .SYNOPSIS
        Concatène des PDF sans pdfwrite (qpdf puis pdftk). Préserve polices / ToUnicode des entrées.
    #>
    param(
        [Parameter(Mandatory = $true)][string[]]$InputPdfsOrdered,
        [Parameter(Mandatory = $true)][string]$DestinationPdfPath
    )
    if (Merge-CnsPdfFilesQpdfOrdered -InputPdfsOrdered $InputPdfsOrdered -DestinationPdfPath $DestinationPdfPath) {
        Write-Host '[PDF-MERGE] Fusion structure-preserving via qpdf (pas de pdfwrite).' -ForegroundColor Green
        return $true
    }
    if (Merge-CnsPdfFilesPdftkOrdered -InputPdfsOrdered $InputPdfsOrdered -DestinationPdfPath $DestinationPdfPath) {
        Write-Host '[PDF-MERGE] Fusion structure-preserving via pdftk (pas de pdfwrite).' -ForegroundColor Green
        return $true
    }
    return $false
}

function Merge-CnsPdfFilesForStep5TourneeComposition {
    <#
    .SYNOPSIS
        Fusion finale STEP 5 : qpdf/pdftk si PDF LibreOffice presents (certificat, bilan) ; sinon Ghostscript historique.
        Les PDF cert_dest_*.pdf et bilan_seg_*.pdf ne doivent jamais passer dans pdfwrite.
    #>
    param(
        [Parameter(Mandatory = $true)][string[]]$InputPdfsOrdered,
        [Parameter(Mandatory = $true)][string]$DestinationPdfPath
    )

    $loPaths = @(
        $InputPdfsOrdered | Where-Object { Test-CnsPdfPathIsLibreOfficeStep5Fragment -Path $_ }
    )
    $hasLoDocs = ($loPaths.Count -gt 0)

    foreach ($lp in @($loPaths)) {
        if (-not (Test-Path -LiteralPath $lp)) { continue }
        $kind = if (Test-CnsPdfPathIsDestructionCertificateFragment -Path $lp) { 'DESTRUCTION-CERT' } else { 'BILAN-COLLECTE' }
        Write-CnsLibreOfficePdfMergeAudit -Phase 'BEFORE_MERGE' -PdfPath $lp -DocumentKind $kind
    }

    if ($hasLoDocs) {
        $beforeMarkers = @{}
        foreach ($lp in @($loPaths)) {
            if (Test-Path -LiteralPath $lp) {
                $beforeMarkers[$lp] = Get-CnsPdfFontStructureMarkers -PdfPath $lp
            }
        }

        $merged = Merge-CnsPdfFilesStructurePreservingOrdered -InputPdfsOrdered $InputPdfsOrdered -DestinationPdfPath $DestinationPdfPath
        if (-not $merged) {
            Write-Warning @'
[PDF-MERGE] Fusion impossible sans qpdf/pdftk : les PDF LibreOffice (certificat, bilan) ne peuvent pas passer dans Ghostscript pdfwrite.
Installez qpdf (https://github.com/qpdf/qpdf/releases) et definissez CN_QPDF_EXE, ou installez pdftk / PDFtk Server.
'@
            return $false
        }

        if (-not (Test-Path -LiteralPath $DestinationPdfPath)) { return $false }

        $afterFinal = Get-CnsPdfFontStructureMarkers -PdfPath $DestinationPdfPath
        Write-CnsLibreOfficePdfMergeAudit -Phase 'AFTER_MERGE' -PdfPath $DestinationPdfPath -DocumentKind 'PDF-FINAL'

        if ($null -ne $afterFinal) {
            $minTu = 0
            $minFf2 = 0
            foreach ($bm in @($beforeMarkers.Values)) {
                if ($null -eq $bm) { continue }
                if ([int]$bm.ToUnicode -gt $minTu) { $minTu = [int]$bm.ToUnicode }
                if ([int]$bm.FontFile2 -gt $minFf2) { $minFf2 = [int]$bm.FontFile2 }
            }
            $issues = New-Object System.Collections.Generic.List[string]
            if ($minTu -gt 0 -and [int]$afterFinal.ToUnicode -lt $minTu) {
                [void]$issues.Add(('ToUnicode final {0} < LibreOffice min {1}' -f $afterFinal.ToUnicode, $minTu))
            }
            if ($minFf2 -gt 0 -and [int]$afterFinal.FontFile2 -lt $minFf2) {
                [void]$issues.Add(('FontFile2 final {0} < LibreOffice min {1}' -f $afterFinal.FontFile2, $minFf2))
            }
            if ($issues.Count -gt 0) {
                Write-Warning ("[PDF-MERGE] Validation structure degradee apres merge LibreOffice : {0}" -f ($issues -join '; '))
            }
            else {
                Write-Host '[PDF-MERGE] Validation structure OK (ToUnicode/FontFile2 preserves dans le PDF final).' -ForegroundColor Green
            }
        }
        return $true
    }

    if (-not (Get-Command Merge-CnsPdfFilesGhostscriptOrdered -ErrorAction SilentlyContinue)) {
        Write-Warning '[PDF-MERGE] Merge-CnsPdfFilesGhostscriptOrdered indisponible.'
        return $false
    }
    Write-Host '[PDF-MERGE] Fusion Ghostscript pdfwrite (aucun PDF LibreOffice certificat/bilan dans la liste).' -ForegroundColor DarkGray
    return (Merge-CnsPdfFilesGhostscriptOrdered -InputPdfsOrdered $InputPdfsOrdered -DestinationPdfPath $DestinationPdfPath)
}

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
        [void]$candidates.Add((Join-Path $repoRoot 'lib\qpdf\qpdf.exe'))
        [void]$candidates.Add((Join-Path $repoRoot 'package\lib\qpdf\bin\qpdf.exe'))
        [void]$candidates.Add((Join-Path $repoRoot 'package\runtime\qpdf\qpdf.exe'))
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
    return ($leaf -match '(?i)^bilan_(seg|sb)_.*\.pdf$')
}

function Test-CnsPdfPathIsFtCollecteFragment {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $leaf = [System.IO.Path]::GetFileName($Path)
    return ($leaf -match '(?i)^ft_\d+_.*\.pdf$')
}

function Test-CnsPdfPathIsLibreOfficeStep5Fragment {
    <#
    .SYNOPSIS
        PDF produits par LibreOffice (certificat, bilan, FT) — ne jamais repasser dans pdfwrite.
    #>
    param([AllowNull()][string]$Path)
    if (Test-CnsPdfPathIsDestructionCertificateFragment -Path $Path) { return $true }
    if (Test-CnsPdfPathIsBilanCollecteFragment -Path $Path) { return $true }
    if (Test-CnsPdfPathIsFtCollecteFragment -Path $Path) { return $true }
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

    # Fusion par lots si ligne de commande trop longue (limite Windows ~32k).
    $argLenEst = 0
    foreach ($tp in @($paths)) { $argLenEst += ($tp.Length + 8) }
    $needChunk = ($argLenEst -gt 28000 -or $paths.Count -gt 80)

    if ($needChunk -and $paths.Count -gt 2) {
        $chunkSize = 40
        $partials = New-Object System.Collections.Generic.List[string]
        $runId = [Guid]::NewGuid().ToString('N')
        try {
            for ($i = 0; $i -lt $paths.Count; $i += $chunkSize) {
                $take = [Math]::Min($chunkSize, $paths.Count - $i)
                $chunk = @($paths[$i..($i + $take - 1)])
                $partOut = Join-Path $outDir ("cn_qpdf_chunk_{0}_{1:D3}.pdf" -f $runId, ($partials.Count + 1))
                if (-not (Merge-CnsPdfFilesQpdfOrdered -InputPdfsOrdered $chunk -DestinationPdfPath $partOut)) {
                    return $false
                }
                [void]$partials.Add($partOut)
            }
            if ($partials.Count -eq 1) {
                Copy-Item -LiteralPath $partials[0] -Destination $outAbs -Force
                return (Test-Path -LiteralPath $outAbs)
            }
            return (Merge-CnsPdfFilesQpdfOrdered -InputPdfsOrdered @($partials.ToArray()) -DestinationPdfPath $outAbs)
        }
        finally {
            foreach ($pp in @($partials)) {
                if (-not [string]::IsNullOrWhiteSpace($pp) -and (Test-Path -LiteralPath $pp)) {
                    Remove-Item -LiteralPath $pp -Force -ErrorAction SilentlyContinue
                }
            }
        }
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
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $proc = Start-Process -FilePath $qpdf -ArgumentList @($args.ToArray()) -Wait -PassThru -NoNewWindow -ErrorAction Stop
        $sw.Stop()
        $ok = ($null -ne $proc -and $proc.ExitCode -eq 0 -and (Test-Path -LiteralPath $outAbs))
        if ($ok) {
            Write-Host ("[PDF-MERGE] qpdf OK : {0} fichier(s) -> {1} en {2} ms" -f $paths.Count, (Split-Path -Leaf $outAbs), $sw.ElapsedMilliseconds) -ForegroundColor Green
        }
        return $ok
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
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $proc = Start-Process -FilePath $pdftk -ArgumentList @($argList.ToArray()) -Wait -PassThru -NoNewWindow -ErrorAction Stop
        $sw.Stop()
        $ok = ($null -ne $proc -and $proc.ExitCode -eq 0 -and (Test-Path -LiteralPath $outAbs))
        if ($ok) {
            Write-Host ("[PDF-MERGE] pdftk OK : {0} fichier(s) en {1} ms" -f $paths.Count, $sw.ElapsedMilliseconds) -ForegroundColor Yellow
        }
        return $ok
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
        Write-Host '[PDF-MERGE] Fusion via qpdf (structure-preserving)' -ForegroundColor Green
        return $true
    }
    if (Merge-CnsPdfFilesPdftkOrdered -InputPdfsOrdered $InputPdfsOrdered -DestinationPdfPath $DestinationPdfPath) {
        Write-Host '[PDF-MERGE] Fusion via pdftk' -ForegroundColor Yellow
        return $true
    }
    return $false
}

function Merge-CnsPdfFilesForStep5TourneeComposition {
    <#
    .SYNOPSIS
        Fusion PDF Step 5 : qpdf en priorite (structure-preserving), puis pdftk, puis Ghostscript en dernier recours.
        Les PDF LibreOffice (certificat / bilan / FT) ne passent jamais dans pdfwrite si qpdf/pdftk echouent.
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
        $kind = if (Test-CnsPdfPathIsDestructionCertificateFragment -Path $lp) {
            'DESTRUCTION-CERT'
        }
        elseif (Test-CnsPdfPathIsFtCollecteFragment -Path $lp) {
            'BILAN-COLLECTE'
        }
        else {
            'BILAN-COLLECTE'
        }
        Write-CnsLibreOfficePdfMergeAudit -Phase 'BEFORE_MERGE' -PdfPath $lp -DocumentKind $kind
    }

    $beforeMarkers = @{}
    if ($hasLoDocs) {
        foreach ($lp in @($loPaths)) {
            if (Test-Path -LiteralPath $lp) {
                $beforeMarkers[$lp] = Get-CnsPdfFontStructureMarkers -PdfPath $lp
            }
        }
    }

    # 1) qpdf — toujours en priorite (avec ou sans fragments LibreOffice)
    if (Merge-CnsPdfFilesQpdfOrdered -InputPdfsOrdered $InputPdfsOrdered -DestinationPdfPath $DestinationPdfPath) {
        Write-Host '[PDF-MERGE] Fusion via qpdf (structure-preserving)' -ForegroundColor Green
        if ($hasLoDocs -and (Test-Path -LiteralPath $DestinationPdfPath)) {
            Write-CnsLibreOfficePdfMergeAudit -Phase 'AFTER_MERGE' -PdfPath $DestinationPdfPath -DocumentKind 'PDF-FINAL'
            $afterFinal = Get-CnsPdfFontStructureMarkers -PdfPath $DestinationPdfPath
            if ($null -ne $afterFinal -and $beforeMarkers.Count -gt 0) {
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
        }
        return $true
    }

    # 2) pdftk
    if (Merge-CnsPdfFilesPdftkOrdered -InputPdfsOrdered $InputPdfsOrdered -DestinationPdfPath $DestinationPdfPath) {
        Write-Host '[PDF-MERGE] Fusion via pdftk' -ForegroundColor Yellow
        if ($hasLoDocs -and (Test-Path -LiteralPath $DestinationPdfPath)) {
            Write-CnsLibreOfficePdfMergeAudit -Phase 'AFTER_MERGE' -PdfPath $DestinationPdfPath -DocumentKind 'PDF-FINAL'
        }
        return $true
    }

    # 3) Ghostscript — interdit si fragments LibreOffice (re-encodage destructeur)
    if ($hasLoDocs) {
        Write-Warning @'
[PDF-MERGE] qpdf et pdftk indisponibles : les PDF LibreOffice (certificat, bilan, FT) ne peuvent pas passer dans Ghostscript pdfwrite.
Installez qpdf (lib\qpdf\bin\qpdf.exe) ou definissez CN_QPDF_EXE, ou installez pdftk.
'@
        return $false
    }

    if (-not (Get-Command Merge-CnsPdfFilesGhostscriptOrdered -ErrorAction SilentlyContinue)) {
        Write-Warning '[PDF-MERGE] Merge-CnsPdfFilesGhostscriptOrdered indisponible.'
        return $false
    }
    Write-Warning '[PDF-MERGE] qpdf et pdftk indisponibles - fallback Ghostscript'
    return (Merge-CnsPdfFilesGhostscriptOrdered -InputPdfsOrdered $InputPdfsOrdered -DestinationPdfPath $DestinationPdfPath)
}

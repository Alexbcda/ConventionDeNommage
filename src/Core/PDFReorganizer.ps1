# PDFReorganizer.ps1 - Réorganisation de PDF
. (Join-Path $PSScriptRoot 'GhostscriptResolve.ps1')
$_scalarGuard = Join-Path $PSScriptRoot '..\Common\ScalarGuard.ps1'
if (Test-Path -LiteralPath $_scalarGuard) { . $_scalarGuard }
$_sortSafe = Join-Path $PSScriptRoot '..\Common\SortSafe.ps1'
if (Test-Path -LiteralPath $_sortSafe) { . $_sortSafe }

function script:Write-PdfReorgLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Level = 'INFO'
    )
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log $Message $Level
    }
}

function Test-PlausibleGeneratedPdf {
    <#
    .SYNOPSIS
        Vérifie qu'un chemin pointe vers un PDF probablement valide (en-tête %PDF- et taille minimale).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [int]$MinBytes = 200
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $i = Get-Item -LiteralPath $Path
    if ($i.Length -lt $MinBytes) { return $false }
    $fs = $null
    try {
        $fs = [System.IO.File]::OpenRead($i.FullName)
        $b = [byte[]]::new(5)
        $n = $fs.Read($b, 0, 5)
        if ($n -lt 5) { return $false }
        $s = [System.Text.Encoding]::ASCII.GetString($b)
        return ($s -eq '%PDF-')
    }
    finally { if ($null -ne $fs) { $fs.Dispose() } }
}

function Convert-PdfReorganiserPathToGhostscriptLiteral {
    param([AllowEmptyString()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    try { return ([System.IO.Path]::GetFullPath($Path) -replace '\\', '/') }
    catch { return '' }
}

function Get-PdfReorganiserGhostscriptPermitArgs {
    <#
    .SYNOPSIS
        Ghostscript 10 + default SAFER : autoriser lecture (source, slices @f, fichier @rsp, TEMP)
        et ecriture (repertoire de sortie, TEMP) sans elargir hors repertoires pipeline.
    .NOTES
        Sans ces options, erreur typique : "Could not open the file …" sur -sOutputFile ou sur entree merge.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResolvedSourcePdf,
        [Parameter(Mandatory = $true)]
        [string]$OutputPdfAbsPath,
        [AllowEmptyCollection()]
        [string[]]$AdditionalReadCandidates = @()
    )
    $readLit = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $writeLit = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $emit = New-Object System.Collections.Generic.List[string]

    $addReadDir = {
        param([string]$Dir)
        if ([string]::IsNullOrWhiteSpace($Dir)) { return }
        $lit = Convert-PdfReorganiserPathToGhostscriptLiteral -Path $Dir
        if ([string]::IsNullOrWhiteSpace($lit)) { return }
        if ($readLit.Add($lit)) { [void]$emit.Add("--permit-file-read=$lit") }
    }
    $addWriteDir = {
        param([string]$Dir)
        if ([string]::IsNullOrWhiteSpace($Dir)) { return }
        $lit = Convert-PdfReorganiserPathToGhostscriptLiteral -Path $Dir
        if ([string]::IsNullOrWhiteSpace($lit)) { return }
        if ($writeLit.Add($lit)) { [void]$emit.Add("--permit-file-write=$lit") }
    }

    try {
        $srcAbs = [System.IO.Path]::GetFullPath($ResolvedSourcePdf)
        $sd = Split-Path -Path $srcAbs -Parent
        if (-not [string]::IsNullOrWhiteSpace($sd)) { & $addReadDir $sd }
    }
    catch { }

    try {
        $outAbs = [System.IO.Path]::GetFullPath($OutputPdfAbsPath)
        $od = Split-Path -Path $outAbs -Parent
        if (-not [string]::IsNullOrWhiteSpace($od)) { & $addWriteDir $od }
    }
    catch { }

    foreach ($cand in @($AdditionalReadCandidates)) {
        if ([string]::IsNullOrWhiteSpace($cand)) { continue }
        try {
            $full = [System.IO.Path]::GetFullPath($cand)
            $pd = Split-Path -Path $full -Parent
            if (-not [string]::IsNullOrWhiteSpace($pd)) { & $addReadDir $pd }
        }
        catch { }
    }

    try {
        & $addReadDir $env:TEMP
        & $addWriteDir $env:TEMP
    }
    catch { }

    return @($emit.ToArray())
}

function Write-PdfReorganiserGhostscriptResponseFileUtf8NoBom {
    param([Parameter(Mandatory = $true)][string]$RspPath, [Parameter(Mandatory = $true)][string[]]$BodyLines)
    $utf = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllLines($RspPath, $BodyLines, $utf)
}

function Write-PdfReorganiserGhostscriptInputDiagnosticsIfEnabled {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedSourcePdf,
        [Parameter(Mandatory = $true)][string]$OutputPdfAbsPath,
        [AllowEmptyString()][string]$RspPath = ''
    )
    if ($null -eq $env:CN_DEBUG_GHOSTSCRIPT_INPUT -or $env:CN_DEBUG_GHOSTSCRIPT_INPUT -notin @('1', 'true')) {
        return
    }

    Write-Host '[GS-DEBUG] CN_DEBUG_GHOSTSCRIPT_INPUT active' -ForegroundColor Magenta

    foreach ($lbl in @( @{ L = 'source'; P = $ResolvedSourcePdf }, @{ L = 'sortie '; P = $OutputPdfAbsPath } )) {
        $p = [string]$lbl.P
        $ln = [string]$lbl.L
        try {
            $tp = Test-Path -LiteralPath $p -PathType Leaf
            $it = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
            $sz = if ($null -eq $it) { 'n/a' } else { [string]$it.Length }
            Write-Host ("[GS-DEBUG] Test-Path Leaf {0} ({1}) = {2} ; Length={3}" -f $ln, $p, $tp, $sz) -ForegroundColor Magenta
            if (-not [string]::IsNullOrWhiteSpace($p)) {
                $dir = Split-Path -Path ([System.IO.Path]::GetFullPath($p)) -Parent
                if (-not [string]::IsNullOrWhiteSpace($dir)) {
                    $td = Test-Path -LiteralPath $dir
                    Write-Host ("[GS-DEBUG] Repertoire parent existe : {0} = {1}" -f $dir, $td) -ForegroundColor Magenta
                }
            }
        }
        catch {
            Write-Host ("[GS-DEBUG] Erreur diagnostic {0} : {1}" -f $ln, $_.Exception.Message) -ForegroundColor Magenta
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($RspPath)) {
        Write-Host "[GS-DEBUG] Fichier reponse Ghostscript @$RspPath :" -ForegroundColor Magenta
        if (Test-Path -LiteralPath $RspPath -PathType Leaf) {
            $raw = Get-Content -LiteralPath $RspPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            $lines = @(Get-Content -LiteralPath $RspPath -ErrorAction SilentlyContinue)
            $max = [Math]::Min([int]$lines.Count, [int]40)
            for ($li = 0; $li -lt $max; $li++) {
                Write-Host ("[GS-DEBUG]   rsp[{0:D4}]={1}" -f $li, $lines[$li]) -ForegroundColor DarkMagenta
            }
            Write-Host ("[GS-DEBUG]   octets bruts (Raw.Length) ~= {0}" -f $(if ($raw) { $raw.Length } else { 0 })) -ForegroundColor DarkMagenta
        }
        else {
            Write-Host '[GS-DEBUG]   rsp introuvable' -ForegroundColor Magenta
        }
    }

    $leafHint = Split-Path $OutputPdfAbsPath -Leaf
    try {
        $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { $null -ne $_.CommandLine -and $leafHint.Length -gt 2 -and $_.CommandLine -like ('*' + $leafHint + '*') }
        foreach ($xp in @($procs)) {
            Write-Host ("[GS-DEBUG] Processus dont la ligne de commande mentionne `{0}` : PID={1} Name={2}" -f `
                    $leafHint, $xp.ProcessId, $xp.Name) -ForegroundColor Yellow
        }
    }
    catch { }
}

function Get-PdfReorganiserPageNumberBatches {
    <#
    .SYNOPSIS
        Regroupe une sequence de numeros de pages source en lots pour Ghostscript sans changer l'ordre final.
        - Plages contigues ascendante stricte (p, p+1, p+2, ...) → un lot FirstPage..LastPage.
        - Suites de meme page consecutives (p, p, ...) → une extraction puis N references dans le merge.
        Autres motifs (pas de +1 entre voisins) tombent en lots mono-page comme avant (ex. [10],[12]).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$PageNumbers
    )

    $batches = [System.Collections.Generic.List[object]]::new()
    $n = @($PageNumbers).Count
    $i = 0
    while ($i -lt $n) {
        $pn = [int]$PageNumbers[$i]

        # Suite de meme page physique consecutives (doublons contigus)
        if (($i + 1) -lt $n -and [int]$PageNumbers[$i + 1] -eq $pn) {
            $rep = 1
            $j = $i
            while (($j + 1) -lt $n -and [int]$PageNumbers[$j + 1] -eq $pn) {
                $rep++
                $j++
            }
            [void]$batches.Add([PSCustomObject]@{
                    Kind        = 'SamePageRun'
                    FirstPage   = $pn
                    LastPage    = $pn
                    MergeRepeat = $rep
                })
            $i = $j + 1
            continue
        }

        # Suite contigue dans le fichier source (delta +1 entre occurrences consecutives)
        $first = $pn
        $last = $pn
        $j = $i
        while (($j + 1) -lt $n -and ([int]$PageNumbers[$j + 1] -eq ([int]$PageNumbers[$j] + 1))) {
            $j++
            $last = [int]$PageNumbers[$j]
        }
        [void]$batches.Add([PSCustomObject]@{
                Kind        = 'RangePages'
                FirstPage   = $first
                LastPage    = $last
                MergeRepeat = 1
            })
        $i = $j + 1
    }

    return @($batches.ToArray())
}

function Reorganiser-PDF {
    param(
        [string]$SourcePDF, 
        [string]$OutputPDF, 
        [hashtable]$Mapping,
        [int[]]$OrderedPhysicalPages = @(),
        [int]$SourcePdfPageCountHint = 0,
        [scriptblock]$ProgressCallback = $null
    )
    
    script:Write-PdfReorgLog -Message "`n[PDF] === DEBUT REORGANISATION ===" -Level 'INFO'
    script:Write-PdfReorgLog -Message "[PDF] Source : $(Split-Path $SourcePDF -Leaf)" -Level 'INFO'
    script:Write-PdfReorgLog -Message "[PDF] Destination : $(Split-Path $OutputPDF -Leaf)" -Level 'INFO'
    
    $useOrderedSequence = @($OrderedPhysicalPages).Count -gt 0
    if ($useOrderedSequence) {
        script:Write-PdfReorgLog -Message ("[PDF] Ordre explicite (OrderedPhysicalPages) : {0} occurrence(s)" -f @($OrderedPhysicalPages).Count) -Level 'INFO'
    }
    else {
        script:Write-PdfReorgLog -Message "[PDF] Pages configurées (mapping clé par page) : $($Mapping.Count)" -Level 'INFO'
    }
    
    # Ordre des pages : séquence explicite (doublons autorisés) OU tri depuis le mapping (une entrée par numéro de page)
    $pageNumbers = @()
    if ($useOrderedSequence) {
        $pageNumbers = @($OrderedPhysicalPages | ForEach-Object { [int]$_ })
    }
    else {
        $pagesOrder = @()
        foreach ($key in $Mapping.Keys) {
            $row = $Mapping[$key]
            $tRaw = if ($null -ne $row) { $row.Tournee } else { 0 }
            $rRaw = if ($null -ne $row) { $row.Rang } else { 0 }
            if (Get-Command ConvertTo-SafeInt -ErrorAction SilentlyContinue) {
                $tNum = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $tRaw -Name "pdf.Tournee") -Name "pdf.Tournee")
                $rNum = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $rRaw -Name "pdf.Rang") -Name "pdf.Rang")
            } else {
                $tNum = [int]($tRaw)
                $rNum = [int]($rRaw)
            }
            $pagesOrder += [PSCustomObject]@{
                PageNum = [int]$key
                Tournee = $tNum
                Rang    = $rNum
            }
        }
        $pagesOrder = Sort-SafeTripleInt -InputObject $pagesOrder -P1 Tournee -P2 Rang -P3 PageNum
        $pageNumbers = @($pagesOrder | ForEach-Object { [int]$_.PageNum })
    }
    $pageRange = $pageNumbers -join ','

    script:Write-PdfReorgLog -Message ("[GS-PREP] pageList.Count={0}" -f $pageNumbers.Count) -Level 'INFO'
    if ($pageNumbers.Count -le 200) {
        script:Write-PdfReorgLog -Message ("[GS-PREP] pageList.Full={0}" -f $pageRange) -Level 'INFO'
    }
    else {
        $headCh = (($pageNumbers[0..199] | ForEach-Object { "$_" }) -join ',')
        script:Write-PdfReorgLog -Message ("[GS-PREP] pageList.preview(200premiers)={0},..." -f $headCh) -Level 'INFO'
    }

    script:Write-PdfReorgLog -Message "[PDF] Ordre des pages : $pageRange" -Level 'INFO'

    if (-not (Test-Path -LiteralPath $SourcePDF -PathType Leaf)) {
        Write-Warning "PDFReorganizer: source introuvable : $SourcePDF"
        return $false
    }
    if (-not $useOrderedSequence -and ($null -eq $Mapping -or $Mapping.Count -eq 0)) {
        Write-Warning "PDFReorganizer: mapping vide."
        return $false
    }
    $outDir = Split-Path -Parent -Path $OutputPDF
    if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -LiteralPath $outDir)) {
        try {
            $null = New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop
        } catch {
            Write-Warning "PDFReorganizer: impossible de créer le dossier cible : $outDir"
            return $false
        }
    }

    $gsPath = Get-ResolvedGhostscriptPath
    if ($gsPath) {
        # GS 10 SAFER (defaut) : sans --permit-file-read|--permit-file-write, echec frequent
        # "Could not open the file ..." sur sortie (ex. Downloads) ou sur entrees merge / @rsp.
        # Opt. : $env:CN_DEBUG_GHOSTSCRIPT_INPUT = '1' | CN_GS_PREMERGE_DELAY_MS avant merge @rsp | CN_GS_BATCH_SLICES=0 pour desactiver le lotissement.
        script:Write-PdfReorgLog -Message "[PDF] Ghostscript (exécution) : $gsPath" -Level 'INFO'
        if (-not (Test-Path -LiteralPath $gsPath -PathType Leaf)) {
            Write-Warning "PDFReorganizer: binaire GS résolu introuvable : $gsPath"
            return $false
        }

        $resolvedSource = (Resolve-Path -LiteralPath $SourcePDF).Path
        $outAbs = [System.IO.Path]::GetFullPath($OutputPDF)

        if ($pageNumbers.Count -lt 1) {
            script:Write-PdfReorgLog -Message "[ERROR] Ghostscript : liste des pages vide (aucune page à écrire)." -Level 'ERROR'
            return $false
        }

        if ($SourcePdfPageCountHint -gt 1 -and $pageNumbers.Count -eq 1) {
            script:Write-PdfReorgLog -Message ("[ERROR] Troncature suspecte du pipeline : hint pages source={0} mais sequence GS={1}. Verifier sanitize / mapping Hashtable (cles dupliquées)." -f $SourcePdfPageCountHint, $pageNumbers.Count) -Level 'ERROR'
            return $false
        }

        # Une seule paire -dFirstPage/-dLastPage est prise en compte par invocation : plusieurs paires écrase la précédente
        # → une ou plusieurs extractions (lots : plages contigues +1 et doublons consecutifs) puis fusion multi -f.
        # CN_GS_BATCH_SLICES=0 : desactive le lotissement (1 processus par occurrence de page, comme avant).
        $errFile = Join-Path $env:TEMP ("cn_gs_err_{0}.txt" -f [Guid]::NewGuid().ToString('N'))
        if (Test-Path -LiteralPath $errFile) { Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue }

        $runGuid = [Guid]::NewGuid().ToString('N')
        $tempSingles = [System.Collections.Generic.List[string]]::new()
        $process = $null
        $stderr = ''
        try {
            if ($pageNumbers.Count -eq 1) {
                $only = [int]$pageNumbers[0]
                script:Write-PdfReorgLog -Message "[GS-PREP] single-page shortcut FirstPage=$only" -Level 'INFO'
                $permSingle = @(Get-PdfReorganiserGhostscriptPermitArgs -ResolvedSourcePdf $resolvedSource -OutputPdfAbsPath $outAbs)
                $gsArgsSingle = @(
                    '-dNOPAUSE', '-dBATCH'
                ) + $permSingle + @(
                    '-sDEVICE=pdfwrite',
                    ("-sOutputFile=$outAbs"),
                    ("-dFirstPage=$only"), ("-dLastPage=$only"),
                    $resolvedSource
                )
                $cmdChars = 0
                foreach ($_a in $gsArgsSingle) { $cmdChars += $_a.Length + 1 }
                script:Write-PdfReorgLog -Message "[GS-PREP] singlePass approxArgChars=$cmdChars" -Level 'INFO'
                $process = Start-Process -FilePath $gsPath -ArgumentList $gsArgsSingle -NoNewWindow -Wait -PassThru -RedirectStandardError $errFile
                if ($null -ne $ProgressCallback) {
                    try { & $ProgressCallback 1 1 $only } catch { }
                }
            }
            else {
                $disableBatchSlices = ([string]::Equals(([string]$env:CN_GS_BATCH_SLICES).Trim(), '0', [System.StringComparison]::OrdinalIgnoreCase))
                $pageArray = [int[]]@($pageNumbers)

                if (-not $disableBatchSlices) {
                    $sliceBatches = @(Get-PdfReorganiserPageNumberBatches -PageNumbers $pageArray)
                    $nb = @($sliceBatches).Length
                    $savedProcsApprox = [int]$pageNumbers.Count - $nb
                    Write-Host (
                        "[GS-PREP] batch slices lots={0}, pages_logiques={1}, approx_extractions_gs_evitees_vs_page_a_page={2}" -f $nb, @($pageNumbers).Count, [Math]::Max(0, $savedProcsApprox)
                    ) -ForegroundColor Cyan

                    $bi = 0
                    foreach ($sb in @($sliceBatches)) {
                        $fP = [int]$sb.FirstPage
                        $lP = [int]$sb.LastPage
                        $mRep = 1
                        if ($null -ne $sb.MergeRepeat) { try { $mRep = [int]$sb.MergeRepeat } catch { $mRep = 1 } }
                        if ($mRep -lt 1) { $mRep = 1 }

                        $sliceOut = Join-Path $env:TEMP ("cn_gs_slice_{0}_{1:D5}.pdf" -f $runGuid, $bi)
                        $bi++
                        $permSlice = @(Get-PdfReorganiserGhostscriptPermitArgs -ResolvedSourcePdf $resolvedSource -OutputPdfAbsPath $sliceOut)
                        $argSlice = @(
                            '-dNOPAUSE', '-dBATCH'
                        ) + $permSlice + @(
                            '-sDEVICE=pdfwrite',
                            ("-sOutputFile=$sliceOut"),
                            ("-dFirstPage=$fP"), ("-dLastPage=$lP"),
                            $resolvedSource
                        )
                        if ($bi -eq 1 -or ($bi % 25 -eq 0) -or ($bi -eq $nb)) {
                            Write-Host (
                                "[PDF] Ghostscript extraction lot {0}/{1} FirstPage={2} LastPage={3} mergeRefs={4}" -f $bi, $nb, $fP, $lP, $mRep
                            ) -ForegroundColor Gray
                        }

                        $prSlice = Start-Process -FilePath $gsPath -ArgumentList $argSlice -NoNewWindow -Wait -PassThru -RedirectStandardError $errFile
                        if ($null -eq $prSlice -or $prSlice.ExitCode -ne 0) {
                            $ec = if ($null -eq $prSlice) { '(null)' } else { "$($prSlice.ExitCode)" }
                            script:Write-PdfReorgLog -Message ("[ERROR] Ghostscript extraction echouee lot : First=$fP Last=$lP ExitCode=$ec") -Level 'ERROR'
                            if (Test-Path -LiteralPath $errFile) {
                                script:Write-PdfReorgLog -Message ([string](Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue)) -Level 'ERROR'
                            }
                            return $false
                        }
                        if (-not (Test-Path -LiteralPath $sliceOut)) {
                            script:Write-PdfReorgLog -Message "[ERROR] Fichier lot extrait absent : $sliceOut" -Level 'ERROR'
                            return $false
                        }
                        for ($ri = 0; $ri -lt $mRep; $ri++) {
                            [void]$tempSingles.Add($sliceOut)
                        }
                        if ($null -ne $ProgressCallback) {
                            try { & $ProgressCallback $bi $nb $fP } catch { }
                        }
                    }
                }
                else {
                    script:Write-PdfReorgLog -Message '[GS-PREP] CN_GS_BATCH_SLICES=0 : extraction page par page (comportement historique)' -Level 'WARN'
                    $pi = 0
                    foreach ($pageNum in @($pageNumbers)) {
                        $pnI = [int]$pageNum
                        $sliceOut = Join-Path $env:TEMP ("cn_gs_slice_{0}_{1:D5}.pdf" -f $runGuid, $pi)
                        $pi++
                        $permSlice = @(Get-PdfReorganiserGhostscriptPermitArgs -ResolvedSourcePdf $resolvedSource -OutputPdfAbsPath $sliceOut)
                        $argSlice = @(
                            '-dNOPAUSE', '-dBATCH'
                        ) + $permSlice + @(
                            '-sDEVICE=pdfwrite',
                            ("-sOutputFile=$sliceOut"),
                            ("-dFirstPage=$pnI"), ("-dLastPage=$pnI"),
                            $resolvedSource
                        )
                        if ($pi -eq 1 -or ($pi % 50 -eq 0)) {
                            Write-Host ("[PDF] Ghostscript extraction page {0}/{1}" -f $pi, $pageNumbers.Count) -ForegroundColor Gray
                        }
                        $prSlice = Start-Process -FilePath $gsPath -ArgumentList $argSlice -NoNewWindow -Wait -PassThru -RedirectStandardError $errFile
                        if ($null -eq $prSlice -or $prSlice.ExitCode -ne 0) {
                            $ec = if ($null -eq $prSlice) { '(null)' } else { "$($prSlice.ExitCode)" }
                            script:Write-PdfReorgLog -Message "[ERROR] Ghostscript extraction echouee : page=$pnI ExitCode=$ec" -Level 'ERROR'
                            if (Test-Path -LiteralPath $errFile) {
                                script:Write-PdfReorgLog -Message ([string](Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue)) -Level 'ERROR'
                            }
                            return $false
                        }
                        if (-not (Test-Path -LiteralPath $sliceOut)) {
                            script:Write-PdfReorgLog -Message "[ERROR] Fichier page extrait absent : $sliceOut" -Level 'ERROR'
                            return $false
                        }
                        [void]$tempSingles.Add($sliceOut)
                        if ($null -ne $ProgressCallback) {
                            try { & $ProgressCallback $pi $pageNumbers.Count $pnI } catch { }
                        }
                    }
                }

                $mergeReadCandidates = @($tempSingles.ToArray())
                $permMerge = @(Get-PdfReorganiserGhostscriptPermitArgs -ResolvedSourcePdf $resolvedSource -OutputPdfAbsPath $outAbs -AdditionalReadCandidates $mergeReadCandidates)
                $mergeArgs = [System.Collections.Generic.List[string]]::new()
                [void]$mergeArgs.AddRange([string[]]@('-dNOPAUSE', '-dBATCH'))
                [void]$mergeArgs.AddRange([string[]]$permMerge)
                [void]$mergeArgs.AddRange([string[]]@('-sDEVICE=pdfwrite', ("-sOutputFile=$outAbs")))
                foreach ($tp in $tempSingles) {
                    [void]$mergeArgs.Add('-f')
                    [void]$mergeArgs.Add($tp)
                }
                $argLenEst = 0
                foreach ($part in @($mergeArgs)) { $argLenEst += ($part.Length + 1) }
                script:Write-PdfReorgLog -Message ("[GS-PREP] merge pass partCount=$($mergeArgs.Count) approxArgChars=$argLenEst") -Level 'INFO'
                $useRsp = ($argLenEst -gt 28000 -or $tempSingles.Count -gt 50)
                if ($useRsp) {
                    $rspPath = Join-Path $env:TEMP ("cn_gs_merge_{0}.rsp" -f $runGuid)
                    $rspBody = New-Object System.Collections.Generic.List[string]
                    foreach ($tp in @($tempSingles)) {
                        $tpNorm = [System.IO.Path]::GetFullPath($tp)
                        [void]$rspBody.Add('-f')
                        [void]$rspBody.Add(('"' + $tpNorm + '"').Trim())
                    }
                    Write-PdfReorganiserGhostscriptResponseFileUtf8NoBom -RspPath $rspPath -BodyLines @($rspBody.ToArray())
                    script:Write-PdfReorgLog -Message "[GS-PREP] merge utilise fichier arguments (liste longue ou >50 fichiers)" -Level 'WARN'

                    $permRsp = @(Get-PdfReorganiserGhostscriptPermitArgs -ResolvedSourcePdf $resolvedSource -OutputPdfAbsPath $outAbs -AdditionalReadCandidates (@($tempSingles.ToArray()) + @($rspPath)))

                    [int]$preMs = 0
                    try {
                        if (-not [string]::IsNullOrWhiteSpace($env:CN_GS_PREMERGE_DELAY_MS)) {
                            $parsed = [int]0
                            if ([int]::TryParse(([string]$env:CN_GS_PREMERGE_DELAY_MS).Trim(), [ref]$parsed)) {
                                $preMs = [Math]::Max(0, [Math]::Min(10000, $parsed))
                            }
                        }
                    }
                    catch { $preMs = 0 }

                    Write-PdfReorganiserGhostscriptInputDiagnosticsIfEnabled -ResolvedSourcePdf $resolvedSource -OutputPdfAbsPath $outAbs -RspPath $rspPath

                    if ($preMs -gt 0) {
                        script:Write-PdfReorgLog -Message ("[GS-PREP] Pause pre-merge CN_GS_PREMERGE_DELAY_MS={0}ms (flush FS / fermeture fichier)" -f $preMs) -Level 'INFO'
                        Start-Sleep -Milliseconds $preMs
                    }

                    $rspResolved = [System.IO.Path]::GetFullPath($rspPath)
                    $atMerge = if ($rspResolved.Contains(' ')) {
                        ('"' + '@' + $rspResolved + '"')
                    }
                    else {
                        ('@' + $rspResolved)
                    }

                    $mergeArgsRsp = @('-dNOPAUSE', '-dBATCH') + @($permRsp) + @('-sDEVICE=pdfwrite', ("-sOutputFile=$outAbs"), $atMerge )
                    $process = Start-Process -FilePath $gsPath -ArgumentList $mergeArgsRsp -NoNewWindow -Wait -PassThru -RedirectStandardError $errFile
                    if (Test-Path -LiteralPath $rspPath) {
                        Remove-Item -LiteralPath $rspPath -Force -ErrorAction SilentlyContinue
                    }
                }
                else {
                    $process = Start-Process -FilePath $gsPath -ArgumentList @($mergeArgs.ToArray()) -NoNewWindow -Wait -PassThru -RedirectStandardError $errFile
                }
            }
        } catch {
            script:Write-PdfReorgLog -Message "[ERROR] Ghostscript pipeline : $_" -Level 'ERROR'
            return $false
        } finally {
            foreach ($ts in @($tempSingles)) {
                if (Test-Path -LiteralPath $ts) {
                    Remove-Item -LiteralPath $ts -Force -ErrorAction SilentlyContinue
                }
            }
            if (Test-Path -LiteralPath $errFile) {
                $stderr = [string](Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue)
                Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
            }
        }

        script:Write-PdfReorgLog -Message "[PDF] Fusion / ecriture Ghostscript terminee (stderr agrégée si erreur)." -Level 'INFO'

        if ($null -eq $process) {
            script:Write-PdfReorgLog -Message "[ERROR] Processus Ghostscript non démarré." -Level 'ERROR'
            if (-not [string]::IsNullOrWhiteSpace($stderr)) { script:Write-PdfReorgLog -Message $stderr -Level 'ERROR' }
            return $false
        }

        if ($process.ExitCode -ne 0) {
            script:Write-PdfReorgLog -Message "[ERROR] Ghostscript a échoué (code: $($process.ExitCode))" -Level 'ERROR'
            if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                script:Write-PdfReorgLog -Message "[ERROR] Sortie d'erreur Ghostscript (stderr) :" -Level 'ERROR'
                script:Write-PdfReorgLog -Message $stderr -Level 'ERROR'
            } else { script:Write-PdfReorgLog -Message "[ERROR] (stderr vide ; vérifier chemins, droits, argument -sOutputFile.)" -Level 'ERROR' }
            return $false
        }

        if (-not (Test-PlausibleGeneratedPdf -Path $outAbs)) {
            script:Write-PdfReorgLog -Message "[ERROR] Fichier de sortie absent ou n'est pas un PDF valide (en-tête %PDF- / taille minimale)." -Level 'ERROR'
            if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                script:Write-PdfReorgLog -Message "[ERROR] Sortie stderr Ghostscript (aide diagnostic) :" -Level 'ERROR'
                script:Write-PdfReorgLog -Message $stderr -Level 'ERROR'
            }
            if (Test-Path -LiteralPath $outAbs) {
                $len = (Get-Item -LiteralPath $outAbs).Length
                script:Write-PdfReorgLog -Message ("[ERROR] Fichier trouvé : {0} octet(s)" -f $len) -Level 'ERROR'
            }
            return $false
        }

        if (-not [string]::IsNullOrWhiteSpace($stderr) -and $stderr -match '(?i)error|fatal|invalid|cannot|failed') {
            script:Write-PdfReorgLog -Message "[WARN] Ghostscript (code 0) mais message suspect sur stderr : voir ci-dessous" -Level 'WARN'
            script:Write-PdfReorgLog -Message $stderr -Level 'WARN'
        }

        $sz = (Get-Item -LiteralPath $outAbs).Length
        $pdfOkMsg = "[PDF] OK — sortie vérifiée (en-tête %PDF- + {0} octet(s))" -f $sz
        script:Write-PdfReorgLog -Message $pdfOkMsg -Level 'INFO'
        if (Get-Command Write-PlanningRebuildUiLog -ErrorAction SilentlyContinue) {
            Write-PlanningRebuildUiLog $pdfOkMsg
        }
        return $true
    } else {
        Write-Warning "Ghostscript (gswin64c) introuvable : pas de génération PDF automatique. Définir GHOSTSCRIPT_EXE vers l'exécutable, ou ajouter gswin64c au PATH, ou installer Ghostscript (ex. https://ghostscript.com/releases/gsdnld.html) — le binaire PDF24 est souvent sous Program Files\PDF24\gs\bin\."
        script:Write-PdfReorgLog -Message "[PDF] Ghostscript non détecté (voir avertissement ci-dessus)" -Level 'WARN'

        # Alternative : Utiliser l'impression Windows
        Add-Type -AssemblyName System.Windows.Forms

        $message = @"
Aucun exécutable Ghostscript détecté (hors emplacements connus, PATH, GHOSTSCRIPT_EXE).

1. Téléchargez Ghostscript : https://ghostscript.com/releases/gsdnld.html
   (ou indiquez le chemin complet dans la variable d'environnement GHOSTSCRIPT_EXE)
2. Installez-le
3. Réessayez

OU procédez manuellement imprimable :

1. Le PDF source va s'ouvrir
2. Ctrl+P
3. « Microsoft Print to PDF »
4. Pages : $pageRange
5. Enregistrez vers : $OutputPDF
"@
        
        $result = [System.Windows.Forms.MessageBox]::Show(
            $message,
            "Réorganisation PDF",
            [System.Windows.Forms.MessageBoxButtons]::OKCancel,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            Start-Process $SourcePDF
        }
        Write-Warning "Aucun PDF n'a été généré automatiquement (Ghostscript manquant) ; pas de succès allégé côté application."
        return $false
    }
}


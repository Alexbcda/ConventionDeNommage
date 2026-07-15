# Composition PDF : pages de garde globale + par tournée, puis concat avec le PDF principal
# (sans modifier Reorganiser-PDF ni le matching / reorder / sequence GS).

. (Join-Path $PSScriptRoot '..\..\..\Core\GhostscriptResolve.ps1')
. (Join-Path $PSScriptRoot 'PlanningExcelTourneeSegments.ps1')
. (Join-Path $PSScriptRoot 'CnsPdfMetierPrestation.ps1')
. (Join-Path $PSScriptRoot 'CnsPdfStructureMerge.ps1')

function script:Write-CnsTourneeLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Level = 'INFO'
    )
    $pf = $env:CN_PLANNING_JOB_PROGRESS_FILE
    if ($Level -eq 'INFO' -and -not [string]::IsNullOrWhiteSpace($pf)) {
        try {
            Add-Content -LiteralPath $pf -Value ('{0} - {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message) -Encoding UTF8 -ErrorAction SilentlyContinue
        }
        catch { }
    }
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log $Message $Level
    }
    if ($Level -in @('ERROR', 'WARN')) {
        Write-Warning $Message
    }
}

function Write-CnsStep5ConsoleProgress {
    <#
    .SYNOPSIS
        Messages [PROGRESS] STEP 5 sur la console (hors job GUI pour ne pas polluer Receive-Job).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::Gray
    )
    if ($env:CN_PLANNING_REBUILD_JOB -in @('1', 'true')) { return }
    Write-Host $Message -ForegroundColor $ForegroundColor
}

function Write-PlanningTourneeStep5UiLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    if (Get-Command Write-PlanningRebuildUiLog -ErrorAction SilentlyContinue) {
        Write-PlanningRebuildUiLog $Message
    }
}

$_cnsDestructionExcel = Join-Path $PSScriptRoot 'CnsDestructionCertificateExcel.ps1'
if (Test-Path -LiteralPath $_cnsDestructionExcel) {
    . $_cnsDestructionExcel
}
$_cnsBilanCollecteExcel = Join-Path $PSScriptRoot 'CnsBilanCollecteExcel.ps1'
if (Test-Path -LiteralPath $_cnsBilanCollecteExcel) {
    . $_cnsBilanCollecteExcel
}
$_cnsCeaPointsExcel = Join-Path $PSScriptRoot 'CnsCeaPointsCollecteExcel.ps1'
if (Test-Path -LiteralPath $_cnsCeaPointsExcel) {
    . $_cnsCeaPointsExcel
}
$_cnsFtTemplate = Join-Path $PSScriptRoot 'CnsFtTemplate.ps1'
if (Test-Path -LiteralPath $_cnsFtTemplate) {
    . $_cnsFtTemplate
}

function Invoke-CnsAppendFtDocumentToFrag {
    <#
    .SYNOPSIS
        Genere et insere le document FT apres une page ODM (etape 5).
    .OUTPUTS
        $true si le PDF FT a ete ajoute au fragment.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[string]]$Frag,
        [Parameter(Mandatory = $true)]
        [string]$TmpDir,
        [Parameter(Mandatory = $true)]
        [int]$BlockIndex,
        [Parameter(Mandatory = $true)]
        [int]$SliceIndex,
        [Parameter(Mandatory = $true)]
        [int]$ReorderPage,
        [Parameter(Mandatory = $true)]
        [int]$RawPageNum,
        [Parameter(Mandatory = $true)]
        [string]$PointCollecteLabel,
        [AllowNull()]
        $WorkOrderEntity,
        [AllowNull()]
        $PageEntity,
        [AllowNull()]
        $GsPair,
        [Parameter(Mandatory = $true)]
        [hashtable]$FinalOrderToLine,
        [Parameter(Mandatory = $true)]
        [array]$Segments,
        [Parameter(Mandatory = $true)]
        [hashtable]$OrderToSeg,
        [Parameter(Mandatory = $true)]
        [datetime]$VisitDate,
        [AllowNull()][scriptblock]$ProgressCallback,
        [Parameter(Mandatory = $true)]
        [string]$TChildCore
    )
    if ([string]::IsNullOrWhiteSpace($PointCollecteLabel)) { return $false }
    if (-not (Test-CnsFtCollectionPointLabelEligible -Label $PointCollecteLabel)) {
        Write-Warning ("[FT-POINTS] Injection ignoree — le point de collecte ne commence pas par FT : {0}" -f $PointCollecteLabel)
        return $false
    }
    if (-not (Get-Command New-CnsFtPdfFromExcelTemplate -ErrorAction SilentlyContinue)) {
        Write-Warning '[FT-POINTS] Module FT non charge — document non injecte.'
        return $false
    }

    $ftOut = Join-Path $TmpDir ('ft_{0:D3}_{1:D5}.pdf' -f $BlockIndex, $SliceIndex)
    $segMetaFt = Get-CnsTourneeCoverSegmentMetaForPair -GsPair $GsPair -FinalOrderToLine $FinalOrderToLine `
        -Segments $Segments -ExcelOrderIndexToSegmentIndex $OrderToSeg -VisitDate $VisitDate
    $phFt = @{}
    foreach ($entry in (Get-CnsFtPlaceholders -WorkOrderEntity $WorkOrderEntity -PageEntity $PageEntity `
            -SegmentMeta $segMetaFt -VisitDate $VisitDate -PointCollecte $PointCollecteLabel).GetEnumerator()) {
        $phFt[[string]$entry.Key] = [string]$entry.Value
    }
    $ftPdf = New-CnsFtPdfFromExcelTemplate -OutPdfPath $ftOut -Placeholders $phFt
    if (-not [string]::IsNullOrWhiteSpace($ftPdf) -and (Test-Path -LiteralPath $ftPdf)) {
        [void]$Frag.Add($ftPdf)
        Add-TourneeCompositionGeneratedDocCount
        Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback `
            -Detail ("{0}Generation document FT... [OK]" -f ($TChildCore + '│   └── '))
        Write-Host ("[STEP5-METIER] Document FT injecte apres page reorder #{0} (RawPage={1}, point={2}, fichier={3})." -f `
                $ReorderPage, $RawPageNum, $PointCollecteLabel, (Split-Path -Leaf $ftPdf)) -ForegroundColor Green
        return $true
    }
    Write-Warning ("[FT-POINTS] Generation FT echouee pour RawPage={0} — point={1}." -f $RawPageNum, $PointCollecteLabel)
    return $false
}

function Invoke-CnsGhostscriptDirect {
    <#
    .SYNOPSIS
        Lance Ghostscript via appel direct (&), comme le test manuel fiable sur poste cible.
        Evite Start-Process + redirection qui peut empecher la creation du PDF (exit 0 sans fichier).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$GsPath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [string]$StdOutFile = $null,
        [string]$StdErrFile = $null
    )
    $mergedOutput = & $GsPath @ArgumentList 2>&1
    $exitCode = $LASTEXITCODE
    if ($null -ne $mergedOutput) {
        $lines = @($mergedOutput | ForEach-Object { [string]$_ })
        $logFile = if (-not [string]::IsNullOrWhiteSpace($StdErrFile)) { $StdErrFile }
        elseif (-not [string]::IsNullOrWhiteSpace($StdOutFile)) { $StdOutFile }
        else { $null }
        if (-not [string]::IsNullOrWhiteSpace($logFile)) {
            [System.IO.File]::WriteAllLines($logFile, $lines, [System.Text.UTF8Encoding]::new($false))
        }
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        TimedOut = $false
    }
}

function Invoke-CnsProcessWithTimeout {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [int]$TimeoutSeconds = 120,
        [string]$RedirectStandardOutput = $null,
        [string]$RedirectStandardError = $null
    )
    if ($TimeoutSeconds -lt 1) { $TimeoutSeconds = 120 }
    $startParams = @{
        FilePath     = $FilePath
        ArgumentList = $ArgumentList
        PassThru     = $true
        NoNewWindow  = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($RedirectStandardOutput)) {
        $startParams.RedirectStandardOutput = $RedirectStandardOutput
    }
    if (-not [string]::IsNullOrWhiteSpace($RedirectStandardError)) {
        $startParams.RedirectStandardError = $RedirectStandardError
    }
    $proc = Start-Process @startParams
    if ($proc.WaitForExit($TimeoutSeconds * 1000)) {
        return $proc
    }
    try {
        if (-not $proc.HasExited) { $proc.Kill() }
    }
    catch { }
    Write-Warning ("[PROCESS] Timeout apres {0}s : {1}" -f $TimeoutSeconds, (Split-Path -Leaf $FilePath))
    return $null
}

function Invoke-CnsGhostscriptProcess {
    <#
    .SYNOPSIS
        Lance Ghostscript via appel direct (&) en priorite (fiable sur poste cible).
        Start-Process n'est utilise qu'en repli (timeout longs, fusion PDF).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$GsPath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [switch]$RedirectStreamsForJob,
        [int]$TimeoutSeconds = 0
    )

    if ($TimeoutSeconds -lt 1) {
        $envTs = $env:CN_GS_TIMEOUT_SEC
        if (-not [string]::IsNullOrWhiteSpace($envTs)) {
            try { $TimeoutSeconds = [int]$envTs } catch { $TimeoutSeconds = 120 }
        }
        else {
            $TimeoutSeconds = if ($RedirectStreamsForJob.IsPresent) { 300 } else { 60 }
        }
    }

    $argList = @($ArgumentList)
    try {
        $direct = Invoke-CnsGhostscriptDirect -GsPath $GsPath -ArgumentList $argList
        return [pscustomobject]@{
            ExitCode  = [int]$direct.ExitCode
            HasExited = $true
            TimedOut  = [bool]$direct.TimedOut
        }
    }
    catch {
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] Appel direct echoue, repli Start-Process : {0}" -f $_.Exception.Message) -Level 'WARN'
    }

    $p = Invoke-CnsProcessWithTimeout -FilePath $GsPath -ArgumentList $argList -TimeoutSeconds $TimeoutSeconds
    if ($null -eq $p) { return $null }
    return [pscustomobject]@{
        ExitCode  = $p.ExitCode
        HasExited = $p.HasExited
        TimedOut  = $false
    }
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

function Ensure-CnsGhostscriptOutputDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [string]$LogContext = 'cover'
    )
    $outAbs = [System.IO.Path]::GetFullPath($OutputPath)
    $outDir = Split-Path -Parent $outAbs
    if ([string]::IsNullOrWhiteSpace($outDir)) { return $true }
    if (Test-Path -LiteralPath $outDir -PathType Container) { return $true }
    try {
        $null = New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] Dossier de sortie cree : {0} ({1})" -f $outDir, $LogContext) -Level 'INFO'
    }
    catch {
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] Impossible de creer le dossier de sortie ({0}) : {1} — {2}" -f $LogContext, $outDir, $_.Exception.Message) -Level 'ERROR'
        return $false
    }
    if (-not (Test-Path -LiteralPath $outDir -PathType Container)) {
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] Dossier de sortie introuvable apres creation ({0}) : {1}" -f $LogContext, $outDir) -Level 'ERROR'
        return $false
    }
    return $true
}

function ConvertTo-CnsPsHelveticaParenBody {
    <#
    .SYNOPSIS
        Corps d'une chaine PostScript entre parentheses pour Helvetica (WinAnsi/Latin-1 safe : ASCII + deaccentuation).
        Echappe \, (, ). Le signe ° (U+00B0) est emis en \260 (WinAnsi).
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $t = Sanitize-CnsCoverTextForGhostscript -Text $Text
    if (Get-Command Repair-CnsClientNumeroSignText -ErrorAction SilentlyContinue) {
        $t = Repair-CnsClientNumeroSignText -Text $t
    }
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
        if ($o -eq 0x00B0 -or $o -eq 0x00BA) {
            [void]$sb.Append('\260')
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

function Get-CnsGhostscriptPermitFileArgs {
    <#
    .SYNOPSIS
        Ghostscript 10+ SAFER : repertoires parents en lecture ; sorties PDF + TEMP en ecriture.
    .NOTES
        Sans --permit-file-write, echec typique sur -sOutputFile (Could not open the file / invalidfileaccess).
    #>
    param(
        [string[]]$Paths = @(),
        [string[]]$WritePaths = @()
    )
    $readLit = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $writeLit = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $out = New-Object System.Collections.Generic.List[string]

    $addReadDir = {
        param([string]$Dir)
        if ([string]::IsNullOrWhiteSpace($Dir)) { return }
        $lit = Convert-CnsFilesystemPathToGhostscriptPathLiteral -Path $Dir
        if ([string]::IsNullOrWhiteSpace($lit)) { return }
        if ($readLit.Add($lit)) { [void]$out.Add("--permit-file-read=$lit") }
    }
    $addWriteDir = {
        param([string]$Dir)
        if ([string]::IsNullOrWhiteSpace($Dir)) { return }
        $lit = Convert-CnsFilesystemPathToGhostscriptPathLiteral -Path $Dir
        if ([string]::IsNullOrWhiteSpace($lit)) { return }
        if ($writeLit.Add($lit)) { [void]$out.Add("--permit-file-write=$lit") }
    }

    foreach ($raw in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        try {
            $full = [System.IO.Path]::GetFullPath($raw)
            $dir = Split-Path -Parent $full
            if (-not [string]::IsNullOrWhiteSpace($dir)) { & $addReadDir $dir }
            $fileLit = Convert-CnsFilesystemPathToGhostscriptPathLiteral -Path $full
            if (-not [string]::IsNullOrWhiteSpace($fileLit) -and $readLit.Add($fileLit)) {
                [void]$out.Add("--permit-file-read=$fileLit")
            }
        }
        catch { }
    }
    foreach ($raw in @($WritePaths)) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        try {
            $full = [System.IO.Path]::GetFullPath($raw)
            $dir = Split-Path -Parent $full
            if (-not [string]::IsNullOrWhiteSpace($dir)) { & $addWriteDir $dir }
            $fileLit = Convert-CnsFilesystemPathToGhostscriptPathLiteral -Path $full
            if (-not [string]::IsNullOrWhiteSpace($fileLit) -and $writeLit.Add($fileLit)) {
                [void]$out.Add("--permit-file-write=$fileLit")
            }
        }
        catch { }
    }
    try {
        & $addReadDir $env:TEMP
        & $addWriteDir $env:TEMP
    }
    catch { }
    return @($out.ToArray())
}

function Get-CnsGhostscriptPermitFileReadArgs {
    param([string[]]$Paths)
    return @(Get-CnsGhostscriptPermitFileArgs -Paths @($Paths) -WritePaths @($Paths))
}

function Get-CnsCoverPdfwriteQualityArgs {
    return @(
        '-dPDFSETTINGS=/prepress',
        '-dEmbedAllFonts=true',
        '-dSubsetFonts=false'
    )
}

function Write-CnsGhostscriptFailureDiagnostics {
    param(
        [Parameter(Mandatory = $true)][string]$LogContext,
        [int]$ExitCode = -1,
        [bool]$TimedOut = $false,
        [string]$GsPath = '',
        [string[]]$GsArgs = @(),
        [string]$OutPdfPath = '',
        [string]$StdOutFile = '',
        [string]$StdErrFile = '',
        [string]$FailedPsPath = '',
        [string]$CommandLine = ''
    )
    $stderr = ''
    $stdout = ''
    if (-not [string]::IsNullOrWhiteSpace($StdErrFile) -and (Test-Path -LiteralPath $StdErrFile)) {
        $stderr = [string](Get-Content -LiteralPath $StdErrFile -Raw -ErrorAction SilentlyContinue)
    }
    if (-not [string]::IsNullOrWhiteSpace($StdOutFile) -and (Test-Path -LiteralPath $StdOutFile)) {
        $stdout = [string](Get-Content -LiteralPath $StdOutFile -Raw -ErrorAction SilentlyContinue)
    }
    $reason = if ($TimedOut) { 'timeout' } elseif ($ExitCode -ne 0) { "exit=$ExitCode" } else { 'exit=0 sans fichier PDF' }
    script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] Echec {0} ({1})" -f $LogContext, $reason) -Level 'ERROR'
    script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] ExitCode: {0}" -f $ExitCode) -Level 'ERROR'
    if (-not [string]::IsNullOrWhiteSpace($GsPath)) {
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] Executable : {0}" -f $GsPath) -Level 'ERROR'
    }
    if ($GsArgs.Count -gt 0) {
        $argPreview = ($GsArgs -join ' ')
        if ($argPreview.Length -gt 900) { $argPreview = $argPreview.Substring(0, 900) + '...' }
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] Arguments : {0}" -f $argPreview) -Level 'ERROR'
    }
    if (-not [string]::IsNullOrWhiteSpace($CommandLine)) {
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] Commande exacte : {0}" -f $CommandLine) -Level 'ERROR'
    }
    if (-not [string]::IsNullOrWhiteSpace($OutPdfPath)) {
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] Sortie attendue : {0}" -f $OutPdfPath) -Level 'ERROR'
        $outDir = Split-Path -Parent $OutPdfPath
        if (-not [string]::IsNullOrWhiteSpace($outDir)) {
            $dirExists = Test-Path -LiteralPath $outDir -PathType Container
            script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] Dossier de sortie existe : {0} ({1})" -f $dirExists, $outDir) -Level 'ERROR'
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        $stderrLog = $stderr
        if ($stderrLog.Length -gt 4000) { $stderrLog = $stderrLog.Substring(0, 4000) + '...' }
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] stderr : {0}" -f $stderrLog.Trim()) -Level 'ERROR'
    }
    if (-not [string]::IsNullOrWhiteSpace($stdout) -and [string]::IsNullOrWhiteSpace($stderr)) {
        $stdoutLog = $stdout
        if ($stdoutLog.Length -gt 4000) { $stdoutLog = $stdoutLog.Substring(0, 4000) + '...' }
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] stdout : {0}" -f $stdoutLog.Trim()) -Level 'ERROR'
    }
    if (-not [string]::IsNullOrWhiteSpace($StdErrFile) -and (Test-Path -LiteralPath $StdErrFile)) {
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] stderr fichier : {0}" -f $StdErrFile) -Level 'ERROR'
    }
    if (-not [string]::IsNullOrWhiteSpace($StdOutFile) -and (Test-Path -LiteralPath $StdOutFile)) {
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] stdout fichier : {0}" -f $StdOutFile) -Level 'ERROR'
    }
    if (-not [string]::IsNullOrWhiteSpace($FailedPsPath) -and (Test-Path -LiteralPath $FailedPsPath)) {
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] PS echoue sauvegarde : {0}" -f $FailedPsPath) -Level 'ERROR'
    }
}

function Format-CnsGhostscriptCommandLine {
    param(
        [Parameter(Mandatory = $true)][string]$ExecutablePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList
    )
    $parts = [System.Collections.Generic.List[string]]::new()
    [void]$parts.Add(('"{0}"' -f $ExecutablePath))
    foreach ($arg in @($ArgumentList)) {
        if ([string]::IsNullOrWhiteSpace($arg)) { continue }
        if ($arg -match '[\s"]') {
            [void]$parts.Add(('"{0}"' -f ($arg -replace '"', '\"')))
        }
        else {
            [void]$parts.Add($arg)
        }
    }
    return ($parts -join ' ')
}

function Get-CnsGhostscriptPdfwriteArgumentList {
    param(
        [Parameter(Mandatory = $true)][string]$PsPath,
        [Parameter(Mandatory = $true)][string]$OutPdfPath,
        [switch]$MinimalQuality
    )
    $outAbs = [System.IO.Path]::GetFullPath($OutPdfPath)
    $psAbs = [System.IO.Path]::GetFullPath($PsPath)
    $outLit = Convert-CnsFilesystemPathToGhostscriptPathLiteral -Path $outAbs
    $psLit = Convert-CnsFilesystemPathToGhostscriptPathLiteral -Path $psAbs
    $tempDir = [System.IO.Path]::GetFullPath($env:TEMP)
    $tempLit = Convert-CnsFilesystemPathToGhostscriptPathLiteral -Path $tempDir

    $gsArgs = [System.Collections.Generic.List[string]]::new()
    [void]$gsArgs.AddRange([string[]]@('-dNOPAUSE', '-dBATCH', '-sDEVICE=pdfwrite'))
    [void]$gsArgs.Add("--permit-file-read=$tempLit")
    [void]$gsArgs.Add("--permit-file-write=$tempLit")
    if (-not $MinimalQuality.IsPresent) {
        [void]$gsArgs.AddRange([string[]](Get-CnsCoverPdfwriteQualityArgs))
    }
    [void]$gsArgs.Add("-sOutputFile=$outLit")
    [void]$gsArgs.Add('-f')
    [void]$gsArgs.Add($psLit)
    return @($gsArgs.ToArray())
}

function Invoke-CnsGhostscriptPdfwriteFromPsFile {
    param(
        [Parameter(Mandatory = $true)][string]$GsPath,
        [Parameter(Mandatory = $true)][string]$PsPath,
        [Parameter(Mandatory = $true)][string]$OutPdfPath,
        [switch]$MinimalQuality,
        [string]$LogContext = 'cover',
        [string]$StdOutFile = $null,
        [string]$StdErrFile = $null
    )
    $outAbs = [System.IO.Path]::GetFullPath($OutPdfPath)
    $psAbs = [System.IO.Path]::GetFullPath($PsPath)
    if (-not (Ensure-CnsGhostscriptOutputDirectory -OutputPath $outAbs -LogContext $LogContext)) {
        return [pscustomobject]@{
            Ok                 = $false
            ExitCode           = -1
            TimedOut           = $false
            OutPath            = $outAbs
            OutSize            = 0
            GsArgs             = @()
            CommandLine        = ''
            UsedDirectFallback = $false
        }
    }
    $gsArgs = @(Get-CnsGhostscriptPdfwriteArgumentList -PsPath $psAbs -OutPdfPath $outAbs -MinimalQuality:$MinimalQuality.IsPresent)
    $cmdLine = Format-CnsGhostscriptCommandLine -ExecutablePath $GsPath -ArgumentList $gsArgs
    script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] Commande {0} : {1}" -f $LogContext, $cmdLine) -Level 'INFO'

    $usedDirectInvocation = $true
    $exitCode = -1
    $timedOut = $false
    try {
        $runDirect = Invoke-CnsGhostscriptDirect -GsPath $GsPath -ArgumentList $gsArgs `
            -StdOutFile $StdOutFile -StdErrFile $StdErrFile
        $exitCode = [int]$runDirect.ExitCode
        $timedOut = [bool]$runDirect.TimedOut
    }
    catch {
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] Appel direct {0} exception : {1}" -f $LogContext, $_.Exception.Message) -Level 'ERROR'
    }

    $outOk = $false
    $outSize = 0
    if (Test-Path -LiteralPath $outAbs -PathType Leaf) {
        try {
            $outSize = [long](Get-Item -LiteralPath $outAbs).Length
            $outOk = ($outSize -gt 0)
        }
        catch { }
    }

    if ((-not $timedOut) -and ($exitCode -eq 0) -and $outOk) {
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] PDF cree ({0}) : {1} ({2} octets)" -f $LogContext, $outAbs, $outSize) -Level 'INFO'
        return [pscustomobject]@{
            Ok                 = $true
            ExitCode           = $exitCode
            TimedOut           = $false
            OutPath            = $outAbs
            OutSize            = $outSize
            GsArgs             = $gsArgs
            CommandLine        = $cmdLine
            UsedDirectFallback = $usedDirectInvocation
        }
    }

    if (-not $outOk) {
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] Repli {0} via Start-Process apres appel direct" -f $LogContext) -Level 'WARN'
        $usedDirectInvocation = $false
        $p = Invoke-CnsProcessWithTimeout -FilePath $GsPath -ArgumentList $gsArgs -TimeoutSeconds 90
        $exitCode = if ($null -eq $p) { -1 } else { $p.ExitCode }
        $timedOut = ($null -eq $p)
        if (Test-Path -LiteralPath $outAbs -PathType Leaf) {
            try {
                $outSize = [long](Get-Item -LiteralPath $outAbs).Length
                $outOk = ($outSize -gt 0)
            }
            catch { }
        }
    }

    $ok = (-not $timedOut) -and ($exitCode -eq 0) -and $outOk
    return [pscustomobject]@{
        Ok                 = $ok
        ExitCode           = $exitCode
        TimedOut           = $timedOut
        OutPath            = $outAbs
        OutSize            = $outSize
        GsArgs             = $gsArgs
        CommandLine        = $cmdLine
        UsedDirectFallback = $usedDirectInvocation
    }
}

function Write-CnsPostScriptPdfPage {
    <#
    .SYNOPSIS
        Ghostscript : .ps mono-page -> PDF A4 (595x842).
    .NOTES
        # Utilisation de Helvetica pour compatibilite maximale Ghostscript (polices base PDF, sans CIDFont / TTF / CIDFMAP).
        # Execution via appel direct (&) — Start-Process + redirection peut bloquer la creation du PDF sur certains postes.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PsBodySansShowpage,
        [Parameter(Mandatory = $true)]
        [string]$OutPdfPath,
        [switch]$SkipTrailingShowpage,
        [string]$LogContext = 'cover'
    )
    $prolog = "<< /PageSize [595 842] >> setpagedevice`n"
    $runId = [Guid]::NewGuid().ToString('N')
    $psPath = [System.IO.Path]::GetFullPath((Join-Path $env:TEMP ("cn_cover_{0}.ps" -f $runId)))
    $footer = if ($SkipTrailingShowpage.IsPresent) { "`r`n" } else { "`r`nshowpage`r`n" }
    $psDoc = "%!PS-Adobe-3.0`r`n" + $prolog + $PsBodySansShowpage + $footer
    try {
        [System.IO.File]::WriteAllText($psPath, $psDoc, [System.Text.UTF8Encoding]::new($false))
    }
    catch {
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] Ecriture PS impossible ({0}) : {1}" -f $LogContext, $_.Exception.Message) -Level 'ERROR'
        return $false
    }

    $gs = Get-ResolvedGhostscriptPath
    if (-not $gs) {
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] gswin64c introuvable ({0})" -f $LogContext) -Level 'ERROR'
        Remove-Item -LiteralPath $psPath -Force -ErrorAction SilentlyContinue
        return $false
    }

    $outAbs = [System.IO.Path]::GetFullPath($OutPdfPath)
    if (-not (Ensure-CnsGhostscriptOutputDirectory -OutputPath $outAbs -LogContext $LogContext)) {
        Remove-Item -LiteralPath $psPath -Force -ErrorAction SilentlyContinue
        return $false
    }

    if ($env:CN_DEBUG_PIPELINE -in @('1', 'true')) {
        $preview = $PsBodySansShowpage
        if ($preview.Length -gt 240) { $preview = $preview.Substring(0, 240) + '...' }
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] {0} PS preview : {1}" -f $LogContext, $preview) -Level 'DEBUG'
    }

    $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
    $gsOutFile = Join-Path $env:TEMP ("gs_stdout_{0}_{1}.log" -f $ts, $runId)
    $gsErrFile = Join-Path $env:TEMP ("gs_stderr_{0}_{1}.log" -f $ts, $runId)
    $keepDiagnosticFiles = $false
    try {
        $run = Invoke-CnsGhostscriptPdfwriteFromPsFile -GsPath $gs -PsPath $psPath -OutPdfPath $outAbs `
            -LogContext $LogContext -StdOutFile $gsOutFile -StdErrFile $gsErrFile
        if (-not $run.Ok) {
            script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] Repli {0} sans options prepress" -f $LogContext) -Level 'WARN'
            $run = Invoke-CnsGhostscriptPdfwriteFromPsFile -GsPath $gs -PsPath $psPath -OutPdfPath $outAbs `
                -MinimalQuality -LogContext ($LogContext + '-minimal') -StdOutFile $gsOutFile -StdErrFile $gsErrFile
        }
        if ($run.Ok) {
            Remove-Item -LiteralPath $psPath -Force -ErrorAction SilentlyContinue
            return $true
        }

        $keepDiagnosticFiles = $true
        $failedPs = Join-Path $env:TEMP ("cn_cover_failed_{0}_{1}.ps" -f $ts, $runId)
        try {
            Copy-Item -LiteralPath $psPath -Destination $failedPs -Force -ErrorAction Stop
        }
        catch {
            $failedPs = $psPath
        }
        Write-CnsGhostscriptFailureDiagnostics -LogContext $LogContext -ExitCode $run.ExitCode -TimedOut:$run.TimedOut `
            -GsPath $gs -GsArgs $run.GsArgs -OutPdfPath $outAbs -StdOutFile $gsOutFile -StdErrFile $gsErrFile `
            -FailedPsPath $failedPs -CommandLine $run.CommandLine
        Remove-Item -LiteralPath $psPath -Force -ErrorAction SilentlyContinue
        return $false
    }
    catch {
        $keepDiagnosticFiles = $true
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] Exception {0} : {1}" -f $LogContext, $_.Exception.Message) -Level 'ERROR'
        $failedPs = Join-Path $env:TEMP ("cn_cover_failed_{0}_{1}.ps" -f $ts, $runId)
        try {
            Copy-Item -LiteralPath $psPath -Destination $failedPs -Force -ErrorAction Stop
            script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] PS echoue sauvegarde : {0}" -f $failedPs) -Level 'ERROR'
        }
        catch { }
        Remove-Item -LiteralPath $psPath -Force -ErrorAction SilentlyContinue
        return $false
    }
    finally {
        if (-not $keepDiagnosticFiles) {
            Remove-Item -LiteralPath $gsOutFile -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $gsErrFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function Split-CnsCoverTextToMaxWidth {
    param(
        [AllowNull()][AllowEmptyString()][string]$Text,
        [int]$MaxLen = 88
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $words = @(([string]$Text).Trim() -split '\s+')
    $lines = [System.Collections.Generic.List[string]]::new()
    $current = ''
    foreach ($w in @($words)) {
        if ([string]::IsNullOrWhiteSpace($w)) { continue }
        if ([string]::IsNullOrWhiteSpace($current)) {
            $current = $w
            continue
        }
        if (($current.Length + 1 + $w.Length) -le $MaxLen) {
            $current = "$current $w"
        }
        else {
            [void]$lines.Add($current)
            $current = $w
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($current)) {
        [void]$lines.Add($current)
    }
    return @($lines.ToArray())
}

function Get-CnsCoverGapVerticalCost {
    param([string]$Kind)
    switch ($Kind) {
        'G12' { return 12 }
        'G15' { return 15 }
        'G20' { return 20 }
        'G25' { return 25 }
        'S8'  { return 8 }
        'S15' { return 15 }
        'BLK' { return 8 }
        default { return 0 }
    }
}

function Get-CnsCoverElementVerticalCost {
    param(
        $Element,
        [int]$PageWidth = 612
    )
    if ($null -eq $Element) { return 0 }
    $kind = [string]$Element.Kind
    $txt = [string]$Element.Text
    $gap = Get-CnsCoverGapVerticalCost -Kind $kind
    if ($gap -gt 0) { return $gap }

    switch ($kind) {
        'TC12' {
            $n = @((Split-CnsCoverTextToMaxWidth -Text $txt -MaxLen 72)).Count
            if ($n -lt 1) { return 14 }
            return (14 * $n)
        }
        'T12' {
            $n = @((Split-CnsCoverTextToMaxWidth -Text $txt -MaxLen 85)).Count
            if ($n -lt 1) { return 11 }
            return (11 * $n)
        }
        'B11' {
            $n = @((Split-CnsCoverTextToMaxWidth -Text $txt -MaxLen 85)).Count
            if ($n -lt 1) { return 11 }
            return (11 * $n)
        }
        { $_ -in @('H10', 'VE', 'I10', 'N10') } {
            $n = @((Split-CnsCoverTextToMaxWidth -Text $txt -MaxLen 85)).Count
            if ($n -lt 1) { return 10 }
            return (10 * $n)
        }
        default {
            if ([string]::IsNullOrWhiteSpace($txt)) { return 0 }
            $n = @((Split-CnsCoverTextToMaxWidth -Text $txt -MaxLen 85)).Count
            if ($n -lt 1) { return 10 }
            return (10 * $n)
        }
    }
}

function Build-CnsMismatchCoverPostScriptFromElements {
    <#
    .SYNOPSIS
        Page(s) de garde non-matches : polices compactes, pagination, message de troncature si besoin.
    #>
    param(
        [AllowEmptyCollection()][object[]]$Elements,
        [Parameter(Mandatory = $true)][int]$StartY,
        [Parameter(Mandatory = $true)][int]$MinY,
        [int]$PageWidth = 612,
        [switch]$Multipage
    )
    if ($null -eq $Elements -or @($Elements).Count -lt 1) { return '' }

    $elList = @($Elements)
    $parts = New-Object System.Collections.Generic.List[string]
    [int]$xLeft = 50
    [int]$xIndent = 70
    [int]$idx = 0
    [int]$pageNum = 1
    $truncationDrawn = $false

    function script:Add-CnsCoverPsTextAtX {
        param(
            [string]$Text,
            [string]$FontName,
            [int]$FontSize,
            [int]$X,
            [int]$LineStep,
            $PartsList,
            [ref]$YRef,
            [int]$YMin
        )
        if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
        $textForPs = [string]$Text
        if (Get-Command Repair-CnsClientNumeroSignText -ErrorAction SilentlyContinue) {
            $textForPs = Repair-CnsClientNumeroSignText -Text $textForPs
        }
        $drew = $false
        $wrapped = @(Split-CnsCoverTextToMaxWidth -Text $textForPs -MaxLen 85)
        foreach ($wl in @($wrapped)) {
            if ($YRef.Value -lt $YMin) { return $drew }
            $lit = ConvertTo-CnsPsHelveticaParenBody -Text $wl
            [void]$PartsList.Add("/$FontName findfont $FontSize scalefont setfont`n$X $($YRef.Value) moveto`n($lit) show")
            $YRef.Value -= $LineStep
            $drew = $true
        }
        return $drew
    }

    function script:Add-CnsCoverPsTextCentered {
        param(
            [string]$Text,
            [string]$FontName,
            [int]$FontSize,
            [int]$LineStep,
            $PartsList,
            [ref]$YRef,
            [int]$YMin,
            [int]$PageW
        )
        if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
        $textForPs = [string]$Text
        if (Get-Command Repair-CnsClientNumeroSignText -ErrorAction SilentlyContinue) {
            $textForPs = Repair-CnsClientNumeroSignText -Text $textForPs
        }
        $drew = $false
        $wrapped = @(Split-CnsCoverTextToMaxWidth -Text $textForPs -MaxLen 72)
        foreach ($wl in @($wrapped)) {
            if ($YRef.Value -lt $YMin) { return $drew }
            $lit = ConvertTo-CnsPsHelveticaParenBody -Text $wl
            [void]$PartsList.Add(@"
/$FontName findfont $FontSize scalefont setfont
($lit) dup stringwidth pop $PageW exch sub 2 div $($YRef.Value) moveto show
"@)
            $YRef.Value -= $LineStep
            $drew = $true
        }
        return $drew
    }

    function script:Render-CnsCoverElement {
        param(
            $Element,
            $PartsList,
            [ref]$YRef,
            [int]$YMin,
            [int]$PageW,
            [int]$XLeft,
            [int]$XIndent
        )
        if ($null -eq $Element) { return $true }
        $kind = [string]$Element.Kind
        $txt = [string]$Element.Text
        switch ($kind) {
            'TC12' {
                return (script:Add-CnsCoverPsTextCentered -Text $txt -FontName 'Helvetica-Bold' -FontSize 14 -LineStep 14 `
                    -PartsList $PartsList -YRef $YRef -YMin $YMin -PageW $PageW)
            }
            'T12' {
                return (script:Add-CnsCoverPsTextAtX -Text $txt -FontName 'Helvetica-Bold' -FontSize 10 -X $XLeft -LineStep 11 `
                    -PartsList $PartsList -YRef $YRef -YMin $YMin)
            }
            'H10' {
                return (script:Add-CnsCoverPsTextAtX -Text $txt -FontName 'Helvetica' -FontSize 9 -X $XLeft -LineStep 10 `
                    -PartsList $PartsList -YRef $YRef -YMin $YMin)
            }
            'VE' {
                return (script:Add-CnsCoverPsTextAtX -Text $txt -FontName 'Helvetica' -FontSize 9 -X $XLeft -LineStep 10 `
                    -PartsList $PartsList -YRef $YRef -YMin $YMin)
            }
            'B11' {
                return (script:Add-CnsCoverPsTextAtX -Text $txt -FontName 'Helvetica-Bold' -FontSize 10 -X $XLeft -LineStep 11 `
                    -PartsList $PartsList -YRef $YRef -YMin $YMin)
            }
            'I10' {
                return (script:Add-CnsCoverPsTextAtX -Text $txt -FontName 'Helvetica' -FontSize 9 -X $XIndent -LineStep 10 `
                    -PartsList $PartsList -YRef $YRef -YMin $YMin)
            }
            'N10' {
                return (script:Add-CnsCoverPsTextAtX -Text $txt -FontName 'Helvetica' -FontSize 9 -X $XLeft -LineStep 10 `
                    -PartsList $PartsList -YRef $YRef -YMin $YMin)
            }
            { $_ -in @('S8', 'S15', 'G12', 'G15', 'G20', 'G25', 'BLK') } {
                $YRef.Value -= (Get-CnsCoverGapVerticalCost -Kind $kind)
                return $true
            }
            default {
                if ([string]::IsNullOrWhiteSpace($txt)) { return $true }
                return (script:Add-CnsCoverPsTextAtX -Text $txt -FontName 'Helvetica' -FontSize 9 -X $XLeft -LineStep 10 `
                    -PartsList $PartsList -YRef $YRef -YMin $YMin)
            }
        }
    }

    function script:Add-CnsCoverTruncationNotice {
        param(
            [int]$RemainingCount,
            $PartsList,
            [int]$YMin
        )
        if ($RemainingCount -lt 1) { return }
        $truncMsg = "... et $RemainingCount autre(s) ODM non affiche(s) (voir fichier diagnostic)"
        $lit = ConvertTo-CnsPsHelveticaParenBody -Text $truncMsg
        $yMsg = $YMin + 10
        [void]$PartsList.Add("/Helvetica findfont 9 scalefont setfont`n$xLeft $yMsg moveto`n($lit) show")
    }

    while ($idx -lt $elList.Count) {
        if ($pageNum -gt 1) {
            [void]$parts.Add('showpage')
            $contTitle = '=== SYNTHESE DES ODM NON MATCHES (suite) ==='
            $litCont = ConvertTo-CnsPsHelveticaParenBody -Text $contTitle
            [void]$parts.Add("/Helvetica-Bold findfont 14 scalefont setfont`n50 780 moveto`n($litCont) show")
        }

        [int]$y = $StartY
        [int]$startIdx = $idx
        while ($idx -lt $elList.Count) {
            $el = $elList[$idx]
            $cost = Get-CnsCoverElementVerticalCost -Element $el -PageWidth $PageWidth
            if (($y - $cost) -lt $MinY) {
                break
            }
            $null = script:Render-CnsCoverElement -Element $el -PartsList $parts -YRef ([ref]$y) -YMin $MinY `
                -PageW $PageWidth -XLeft $xLeft -XIndent $xIndent
            $idx++
        }

        if ($idx -eq $startIdx) {
            if (-not $truncationDrawn) {
                $remaining = $elList.Count - $idx
                script:Add-CnsCoverTruncationNotice -RemainingCount $remaining -PartsList $parts -YMin $MinY
                $truncationDrawn = $true
            }
            break
        }

        if ($idx -lt $elList.Count) {
            $pageNum++
            if (-not $Multipage) {
                if (-not $truncationDrawn) {
                    $remaining = $elList.Count - $idx
                    script:Add-CnsCoverTruncationNotice -RemainingCount $remaining -PartsList $parts -YMin $MinY
                    $truncationDrawn = $true
                }
                break
            }
        }
    }

    if ($idx -lt $elList.Count -and -not $truncationDrawn) {
        $remaining = $elList.Count - $idx
        script:Add-CnsCoverTruncationNotice -RemainingCount $remaining -PartsList $parts -YMin $MinY
    }

    if ($parts.Count -lt 1) { return '' }
    $body = ($parts.ToArray()) -join "`n"
    if ($pageNum -gt 1 -or ($body -match '(?m)^showpage\s*$')) {
        return ($body + "`nshowpage")
    }
    return $body
}

function Expand-CnsCoverDiagnosticLinesForPostScript {
    param(
        [AllowEmptyCollection()][string[]]$Lines,
        [int]$MaxLen = 88
    )
    $expanded = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @($Lines)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $wrapped = @(Split-CnsCoverTextToMaxWidth -Text $line -MaxLen $MaxLen)
        if ($wrapped.Count -lt 1) { continue }
        [void]$expanded.Add($wrapped[0])
        for ($wi = 1; $wi -lt $wrapped.Count; $wi++) {
            [void]$expanded.Add(('    {0}' -f $wrapped[$wi]))
        }
    }
    return @($expanded.ToArray())
}

function Build-CnsGlobalMismatchCoverSimplePostScript {
    param(
        [Parameter(Mandatory = $true)][int]$TotalOdmCount,
        [Parameter(Mandatory = $true)][int]$UnmatchedOdmCount,
        [int]$Section1Count = -1,
        [int]$Section2Count = -1,
        [int]$Section3Count = -1,
        [switch]$AllMatched
    )
    $parts = [System.Collections.Generic.List[string]]::new()
    [void]$parts.Add('/Helvetica-Bold findfont 14 scalefont setfont')
    [void]$parts.Add('50 780 moveto')
    [void]$parts.Add(('({0}) show' -f (ConvertTo-CnsPsHelveticaParenBody -Text 'ASSISTANT - Synthese des ODM')))
    [void]$parts.Add('/Helvetica findfont 10 scalefont setfont')
    [int]$y = 750
    foreach ($lineText in @(
            ("Nombre total d'ODM : $TotalOdmCount")
        )) {
        $lit = ConvertTo-CnsPsHelveticaParenBody -Text $lineText
        if (-not [string]::IsNullOrWhiteSpace($lit)) {
            [void]$parts.Add("50 $y moveto")
            [void]$parts.Add(("($lit) show"))
            $y -= 22
        }
    }
    $hasSectionCounts = ($Section1Count -ge 0 -or $Section2Count -ge 0 -or $Section3Count -ge 0)
    if ($hasSectionCounts) {
        foreach ($lineText in @(
                ("Section 1 : $([Math]::Max(0, $Section1Count)) EXCEL SANS ODM")
                ("Section 2 : $([Math]::Max(0, $Section2Count)) ODM DIFFERENTS D'EXCEL")
                ("Section 3 : $([Math]::Max(0, $Section3Count)) ODM ABSENTS D'EXCEL")
            )) {
            $lit = ConvertTo-CnsPsHelveticaParenBody -Text $lineText
            if (-not [string]::IsNullOrWhiteSpace($lit)) {
                [void]$parts.Add("50 $y moveto")
                [void]$parts.Add(("($lit) show"))
                $y -= 22
            }
        }
    }
    else {
        $lit = ConvertTo-CnsPsHelveticaParenBody -Text ("ODM PDF sans correspondance Excel : $UnmatchedOdmCount")
        if (-not [string]::IsNullOrWhiteSpace($lit)) {
            [void]$parts.Add("50 $y moveto")
            [void]$parts.Add(("($lit) show"))
            $y -= 22
        }
    }
    if ($AllMatched) {
        $lit = ConvertTo-CnsPsHelveticaParenBody -Text 'Tous les ODM ont ete matches avec succes.'
        if (-not [string]::IsNullOrWhiteSpace($lit)) {
            [void]$parts.Add("50 $y moveto")
            [void]$parts.Add(("($lit) show"))
        }
    }
    return ($parts.ToArray() -join "`n")
}

function New-CnsGlobalMismatchCoverPdf {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutPdfPath,
        [Parameter(Mandatory = $true)]
        [int]$TotalOdmCount,
        [Parameter(Mandatory = $true)]
        [int]$UnmatchedOdmCount,
        [AllowEmptyCollection()]
        [string[]]$DetailLines = @(),
        [AllowEmptyCollection()]
        [object[]]$CoverElements = @(),
        [int]$Section1Count = -1,
        [int]$Section2Count = -1,
        [int]$Section3Count = -1,
        [switch]$AllMatched
    )
    $mainTitle = '=== SYNTHESE DES ODM NON MATCHES ==='
    $lTotal = "Nombre total d'ODM (groupes extraits du PDF) : $TotalOdmCount"
    $tMain = ConvertTo-CnsPsHelveticaParenBody -Text $mainTitle
    $tTotal = ConvertTo-CnsPsHelveticaParenBody -Text $lTotal
    $bodyParts = [System.Collections.Generic.List[string]]::new()
    $pageW = 595
    $hasSectionCounts = ($Section1Count -ge 0 -or $Section2Count -ge 0 -or $Section3Count -ge 0)
    if ($hasSectionCounts) {
        $s1 = [Math]::Max(0, $Section1Count)
        $s2 = [Math]::Max(0, $Section2Count)
        $s3 = [Math]::Max(0, $Section3Count)
        $lSec1 = "Section 1 : $s1 EXCEL SANS ODM"
        $lSec2 = "Section 2 : $s2 ODM DIFFERENTS D'EXCEL"
        $lSec3 = "Section 3 : $s3 ODM ABSENTS D'EXCEL"
        $tSec1 = ConvertTo-CnsPsHelveticaParenBody -Text $lSec1
        $tSec2 = ConvertTo-CnsPsHelveticaParenBody -Text $lSec2
        $tSec3 = ConvertTo-CnsPsHelveticaParenBody -Text $lSec3
        [void]$bodyParts.Add(@"
/Helvetica-Bold findfont 14 scalefont setfont
($tMain) dup stringwidth pop $pageW exch sub 2 div 780 moveto show
/Helvetica findfont 10 scalefont setfont
50 745 moveto
($tTotal) show
50 720 moveto
($tSec1) show
50 695 moveto
($tSec2) show
50 670 moveto
($tSec3) show
"@)
    }
    else {
        $lLegacy = "Nombre d'ODM PDF sans correspondance Excel : $UnmatchedOdmCount"
        $tLegacy = ConvertTo-CnsPsHelveticaParenBody -Text $lLegacy
        [void]$bodyParts.Add(@"
/Helvetica-Bold findfont 14 scalefont setfont
($tMain) dup stringwidth pop $pageW exch sub 2 div 780 moveto show
/Helvetica findfont 10 scalefont setfont
50 745 moveto
($tTotal) show
50 720 moveto
($tLegacy) show
"@)
    }

    $detailStartY = 650
    $detailMinY = 35
    $detailPs = ''
    if (@($CoverElements).Count -gt 0) {
        $detailPs = Build-CnsMismatchCoverPostScriptFromElements -Elements @($CoverElements) `
            -StartY $detailStartY -MinY $detailMinY -Multipage
    }
    elseif (@($DetailLines).Count -gt 0) {
        $flatDetail = @(Expand-CnsCoverDiagnosticLinesForPostScript -Lines @($DetailLines))
        if ($flatDetail.Count -gt 0) {
            $detailPs = Build-CnsCoverTextLinesPostScriptAppend -Lines $flatDetail -StartY $detailStartY -LineStep 10 -MinY $detailMinY -FontName 'Helvetica' -FontSize 9
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($detailPs)) {
        [void]$bodyParts.Add($detailPs)
    }
    elseif ($AllMatched) {
        $okMsg = 'Tous les ODM ont ete matches avec succes.'
        $tOk = ConvertTo-CnsPsHelveticaParenBody -Text $okMsg
        [void]$bodyParts.Add("/Helvetica findfont 9 scalefont setfont`n50 $detailStartY moveto`n($tOk) show")
    }

    $body = ($bodyParts.ToArray()) -join "`n"
    $skipTrailingShow = ($detailPs -match '(?m)showpage\s*$')
    if ($env:CN_DEBUG_PIPELINE -in @('1', 'true')) {
        $preview = $body
        if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) + '...' }
        script:Write-CnsTourneeLog -Message ("[GHOSTSCRIPT] global-cover body preview : {0}" -f $preview) -Level 'DEBUG'
    }

    $forceSimple = $env:CN_COVER_PS_SIMPLE -in @('1', 'true', 'yes', 'on')
    if (-not $forceSimple) {
        $ok = Write-CnsPostScriptPdfPage -PsBodySansShowpage $body -OutPdfPath $OutPdfPath `
            -SkipTrailingShowpage:$skipTrailingShow -LogContext 'global-cover'
        if ($ok) { return $true }
        script:Write-CnsTourneeLog -Message '[GHOSTSCRIPT] global-cover : syntaxe detaillee en echec — repli PS simplifie' -Level 'WARN'
    }

    $simpleBody = Build-CnsGlobalMismatchCoverSimplePostScript -TotalOdmCount $TotalOdmCount `
        -UnmatchedOdmCount $UnmatchedOdmCount -Section1Count $Section1Count `
        -Section2Count $Section2Count -Section3Count $Section3Count -AllMatched:$AllMatched
    return (Write-CnsPostScriptPdfPage -PsBodySansShowpage $simpleBody -OutPdfPath $OutPdfPath `
        -LogContext 'global-cover-simple')
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
        'janvier' = 'Janvier'; 'février' = 'Fevrier'; 'fevrier' = 'Fevrier'; 'mars' = 'Mars'; 'avril' = 'Avril'
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

function Format-CnsTourneeCoverGardeDateTitle {
    <#
    .SYNOPSIS
        Titre date garde tournée : "Lundi 23 Avril 2026" (fr-FR, sans prefixe ODM/Date).
    #>
    param([AllowNull()][AllowEmptyString()][string]$DateJJMMAAAA)
    $title = Format-CnsTourneeCoverDateFrLong -DateJJMMAAAA $DateJJMMAAAA
    if ([string]::IsNullOrWhiteSpace($title)) {
        $fr = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
        $today = [datetime]::Today
        $title = $today.ToString('dddd dd MMMM yyyy', $fr)
        if ($title.Length -ge 2) {
            $title = $title.Substring(0, 1).ToUpper() + $title.Substring(1)
        }
    }
    return (Format-CnsFrenchLongDateForCoverLabels -LongFr $title)
}

function Get-CnsCoverPostScriptFontBlackName {
    <#
    .NOTES
        Arial-Black non disponible en PostScript Ghostscript standard — Helvetica-Bold equivalent visuel.
    #>
    return 'Helvetica-Bold'
}

function Get-CnsCoverPostScriptFontRegularName {
    return 'Helvetica'
}

function New-CnsPostScriptRightAlignedTextShowBlock {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$FontName,
        [Parameter(Mandatory = $true)][int]$FontSize,
        [Parameter(Mandatory = $true)][int]$RightX,
        [Parameter(Mandatory = $true)][int]$Y
    )
    $lit = ConvertTo-CnsPsHelveticaParenBody -Text $Text
    return @"
/$FontName findfont $FontSize scalefont setfont
($lit) dup stringwidth pop $RightX exch sub $Y moveto show
"@
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
        [int]$MinY,
        [string]$FontName = 'Helvetica',
        [int]$FontSize = 11
    )
    $parts = New-Object System.Collections.Generic.List[string]
    [int]$y = $StartY
    foreach ($line in @($Lines)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $lit = ConvertTo-CnsPsHelveticaParenBody -Text $line
        [void]$parts.Add("/$FontName findfont $FontSize scalefont setfont`n50 $y moveto`n($lit) show")
        $y -= $LineStep
        if ($y -lt $MinY) { break }
    }
    if ($parts.Count -lt 1) { return '' }
    return (($parts.ToArray()) -join "`n")
}

function Get-CnsTourneeCoverCollecteurPrenomDisplay {
    <#
    .SYNOPSIS
        Prenom seul pour la garde tournée ("Jean DUPONT" -> "Jean"). Vide si absent ou sentinelle Excel.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Collecteur)
    if ([string]::IsNullOrWhiteSpace($Collecteur)) { return '' }
    $value = ([string]$Collecteur).Trim()
    $plain = $value.ToUpperInvariant()
    foreach ($s in @('INCONNU', 'NON SPECIFIE', 'NON SPECIFIEE', '-', 'N/A', 'NA', 'ND')) {
        if ($plain -eq $s) { return '' }
    }
    $parts = @(
        ($value -split '\s+') |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($parts.Count -lt 1) { return '' }
    return [string]$parts[0]
}

function Build-CnsTourneeHeaderCoverPostScriptBody {
    param(
        [Parameter(Mandatory = $true)][string]$DateTitle,
        [Parameter(Mandatory = $true)][string]$Collecteur,
        [Parameter(Mandatory = $true)][string]$Vehicule,
        [AllowNull()][AllowEmptyString()][string]$VehiculeImmatriculation = $null,
        [AllowEmptyCollection()][string[]]$MetierMemoLines = @(),
        [AllowNull()][AllowEmptyString()][string]$IncompleteBanner = $null
    )
    $fontBlack = Get-CnsCoverPostScriptFontBlackName
    $fontReg = Get-CnsCoverPostScriptFontRegularName
    $litDate = ConvertTo-CnsPsHelveticaParenBody -Text $DateTitle
    [string]$prenom = Get-CnsTourneeCoverCollecteurPrenomDisplay -Collecteur $Collecteur
    [string]$parcText = if ([string]::IsNullOrWhiteSpace($Vehicule)) { '' } else { ([string]$Vehicule).Trim() }
    [string]$immatText = if ([string]::IsNullOrWhiteSpace($VehiculeImmatriculation)) { '' } else { ([string]$VehiculeImmatriculation).Trim() }

    $headerFontSize = 18
    [int]$immatFontSize = 12
    [int]$vehImmatLineStep = 14
    [int]$immatRightIndent = 30

    if (-not [string]::IsNullOrWhiteSpace($IncompleteBanner)) {
        $line1Y = 770
        $vehY = 740
        $memoY = 700
        $rightX = 550
        $litBanner = ConvertTo-CnsPsHelveticaParenBody -Text $IncompleteBanner
        $bannerPs = @"
/$fontBlack findfont 14 scalefont setfont
50 835 moveto
($litBanner) show
"@
    }
    else {
        $line1Y = 800
        $vehY = 770
        $memoY = 730
        $rightX = 550
        $bannerPs = ''
    }

    $prenomPs = ''
    if (-not [string]::IsNullOrWhiteSpace($prenom)) {
        $prenomPs = New-CnsPostScriptRightAlignedTextShowBlock -Text $prenom -FontName $fontBlack -FontSize $headerFontSize -RightX $rightX -Y $line1Y
    }

    $parcPs = ''
    if (-not [string]::IsNullOrWhiteSpace($parcText)) {
        if ($parcText -notmatch '^(?i)camion\b') {
            $parcLineText = ('Camion {0}' -f $parcText)
        }
        else {
            $parcLineText = $parcText
        }
        $parcPs = New-CnsPostScriptRightAlignedTextShowBlock -Text $parcLineText -FontName $fontBlack -FontSize $headerFontSize -RightX $rightX -Y $vehY
    }

    $immatPs = ''
    if (-not [string]::IsNullOrWhiteSpace($immatText)) {
        [int]$immatY = $vehY - $vehImmatLineStep
        [int]$immatRightX = $rightX - $immatRightIndent
        if ($immatRightX -lt 50) { $immatRightX = 50 }
        $immatPs = New-CnsPostScriptRightAlignedTextShowBlock -Text $immatText -FontName $fontReg -FontSize $immatFontSize -RightX $immatRightX -Y $immatY
    }

    $memoPs = Build-CnsCoverTextLinesPostScriptAppend -Lines @($MetierMemoLines) -StartY $memoY -LineStep 14 -MinY 72 -FontName $fontReg -FontSize 12

    return @"
$bannerPs
/$fontBlack findfont $headerFontSize scalefont setfont
50 $line1Y moveto
($litDate) show
$prenomPs
$parcPs
$immatPs
$memoPs
"@
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
        [AllowNull()][AllowEmptyString()][string]$VehiculeImmatriculation = $null,
        [Parameter()]
        [bool]$TourneeIncomplete = $false,
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$MetierMemoLines = @()
    )
    if ([string]::IsNullOrWhiteSpace($DateJJMMAAAA)) {
        $DateJJMMAAAA = (Get-Date).ToString('dd/MM/yyyy')
        Write-Verbose '[COVER] Date manquante, utilisation de la date du jour'
    }
    if ([string]::IsNullOrWhiteSpace($Collecteur)) {
        $Collecteur = 'INCONNU'
    }
    if ([string]::IsNullOrWhiteSpace($Vehicule)) {
        $Vehicule = 'NON SPECIFIE'
    }
    $dateTitle = Format-CnsTourneeCoverGardeDateTitle -DateJJMMAAAA $DateJJMMAAAA
    $banner = if ($TourneeIncomplete) { 'TOURNEE NON MATCHEE' } else { $null }
    $body = Build-CnsTourneeHeaderCoverPostScriptBody -DateTitle $dateTitle -Collecteur $Collecteur -Vehicule $Vehicule `
        -VehiculeImmatriculation $VehiculeImmatriculation -MetierMemoLines @($MetierMemoLines) -IncompleteBanner $banner
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

function Invoke-CnsGhostscriptExtractPages {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePdf,
        [Parameter(Mandatory = $true)][int]$FirstPageOneBased,
        [Parameter(Mandatory = $true)][int]$LastPageOneBased,
        [Parameter(Mandatory = $true)][string]$OutPdfPath,
        [switch]$SkipPrepress,
        [switch]$CountAsBatchExtract
    )
    if ($FirstPageOneBased -gt $LastPageOneBased) { return $false }
    $gs = Get-ResolvedGhostscriptPath
    if (-not $gs) { return $false }
    $srcAbs = (Resolve-Path -LiteralPath $SourcePdf).Path
    $outAbs = [System.IO.Path]::GetFullPath($OutPdfPath)
    if (-not (Ensure-CnsGhostscriptOutputDirectory -OutputPath $outAbs -LogContext 'extract-pages')) {
        return $false
    }
    $outLit = Convert-CnsFilesystemPathToGhostscriptPathLiteral -Path $outAbs
    $arg = [System.Collections.Generic.List[string]]::new()
    [void]$arg.AddRange([string[]]@('-dNOPAUSE', '-dBATCH', '-sDEVICE=pdfwrite'))
    if (-not $SkipPrepress.IsPresent) {
        [void]$arg.AddRange([string[]](Get-CnsCoverPdfwriteQualityArgs))
    }
    [void]$arg.AddRange([string[]]@(
        ("-sOutputFile=$outLit"),
        ("-dFirstPage=$FirstPageOneBased"), ("-dLastPage=$LastPageOneBased")
    ))
    [void]$arg.AddRange([string[]](Get-CnsGhostscriptPermitFileReadArgs -Paths @($srcAbs, $outAbs)))
    [void]$arg.Add($srcAbs)
    try {
        $p = Invoke-CnsGhostscriptProcess -GsPath $gs -ArgumentList @($arg.ToArray()) -TimeoutSeconds 60
        $ok = ($null -ne $p -and $p.ExitCode -eq 0 -and (Test-Path -LiteralPath $outAbs))
        if ($ok -and $null -ne $script:PlanningStep5Perf) {
            if ($CountAsBatchExtract.IsPresent) {
                $script:PlanningStep5Perf.GsBatchExtracts++
            }
            else {
                $script:PlanningStep5Perf.GsPageExtracts++
            }
        }
        return $ok
    }
    catch { return $false }
}

function Invoke-CnsGhostscriptExtractOnePage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePdf,
        [Parameter(Mandatory = $true)]
        [int]$FirstPageOneBased,
        [Parameter(Mandatory = $true)]
        [string]$OutPdfPath,
        [switch]$SkipPrepress
    )
    return (Invoke-CnsGhostscriptExtractPages -SourcePdf $SourcePdf -FirstPageOneBased $FirstPageOneBased `
        -LastPageOneBased $FirstPageOneBased -OutPdfPath $OutPdfPath -SkipPrepress:$SkipPrepress.IsPresent)
}

function Invoke-CnsGhostscriptExtractPageRange {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePdf,
        [Parameter(Mandatory = $true)][int]$FirstPageOneBased,
        [Parameter(Mandatory = $true)][int]$LastPageOneBased,
        [Parameter(Mandatory = $true)][string]$OutPdfPath,
        [switch]$SkipPrepress
    )
    return (Invoke-CnsGhostscriptExtractPages -SourcePdf $SourcePdf -FirstPageOneBased $FirstPageOneBased `
        -LastPageOneBased $LastPageOneBased -OutPdfPath $OutPdfPath -SkipPrepress:$SkipPrepress.IsPresent -CountAsBatchExtract)
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
    if (-not (Ensure-CnsGhostscriptOutputDirectory -OutputPath $outAbs -LogContext 'merge')) {
        return $false
    }
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
            $p = Invoke-CnsGhostscriptProcess -GsPath $gs -ArgumentList @($mergeArgsRsp.ToArray()) -RedirectStreamsForJob -TimeoutSeconds 600
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
        $p = Invoke-CnsGhostscriptProcess -GsPath $gs -ArgumentList @($mergeArgs.ToArray()) -RedirectStreamsForJob -TimeoutSeconds 600
        return ($null -ne $p -and $p.ExitCode -eq 0 -and (Test-Path -LiteralPath $outAbs))
    }
    finally { }
}

function Build-CnsTourneeOrderToSegmentMap {
    param(
        [array]$Segments,
        [object[]]$ExcelOrder,
        [hashtable]$ReorderedByFinalOrder
    )
    $orderToSeg = @{}
    foreach ($seg in @($Segments)) {
        if ($null -eq $seg) { continue }
        [int]$segNum = 1
        try { $segNum = [int]$seg.SegmentIndex } catch { }
        if ($segNum -lt 1) { continue }
        $oiList = @()
        if ($null -ne $seg.PSObject.Properties['OrderIndices']) { $oiList = @($seg.OrderIndices) }
        foreach ($oi in $oiList) {
            try {
                $k = [int]$oi
                $orderToSeg[$k] = $segNum
                $orderToSeg["$k"] = $segNum
            }
            catch { }
        }
    }

    if ($orderToSeg.Count -eq 0 -and @($Segments).Count -eq 1 -and @($ExcelOrder).Count -gt 0) {
        [int]$segNum = 1
        try { $segNum = [int]$Segments[0].SegmentIndex } catch { }
        foreach ($ex in @($ExcelOrder)) {
            if ($null -eq $ex) { continue }
            try {
                $k = [int]$ex.OrderIndex
                $orderToSeg[$k] = $segNum
                $orderToSeg["$k"] = $segNum
            }
            catch { }
        }
        script:Write-CnsTourneeLog -Message ("[TOURNEE] OrderToSeg reconstruit depuis ExcelOrder (1 segment, {0} indices)." -f $orderToSeg.Count) -Level 'WARN'
    }

    if ($orderToSeg.Count -eq 0 -and $null -ne $ReorderedByFinalOrder -and $ReorderedByFinalOrder.Count -gt 0) {
        [int]$defaultSeg = 1
        if (@($Segments).Count -ge 1) {
            try { $defaultSeg = [int]$Segments[0].SegmentIndex } catch { }
        }
        foreach ($ln in $ReorderedByFinalOrder.Values) {
            if ($null -eq $ln) { continue }
            try {
                $ex = $ln.ExcelSourceOrder
                if ($null -eq $ex) { continue }
                $k = [int]$ex
                if (-not $orderToSeg.ContainsKey($k)) {
                    $orderToSeg[$k] = $defaultSeg
                    $orderToSeg["$k"] = $defaultSeg
                }
            }
            catch { }
        }
        if ($orderToSeg.Count -gt 0) {
            script:Write-CnsTourneeLog -Message ("[TOURNEE] OrderToSeg reconstruit depuis Reordered ({0} indices, segment {1})." -f $orderToSeg.Count, $defaultSeg) -Level 'WARN'
        }
    }

    return $orderToSeg
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

function Get-CnsOdmPagePrestationDetectionLabel {
    param(
        $PageEntity,
        $WorkOrderEntity,
        [bool]$RequiresCea = $false,
        [bool]$RequiresFt = $false
    )
    $parts = [System.Collections.Generic.List[string]]::new()
    $metierPage = Get-CnsPdfPageMetierAnalysis -PageEntity $PageEntity -WorkOrderEntity $WorkOrderEntity
    if ($metierPage.RequiresDestructionCertificate) { [void]$parts.Add('Destruction confidentielle detectee') }
    if ($RequiresCea) { [void]$parts.Add('CEA detecte') }
    if ($RequiresFt) { [void]$parts.Add('FT detecte') }
    foreach ($entry in @($metierPage.TrackDechetEntries)) {
        if ($null -eq $entry) { continue }
        $det = [string]$entry.Detail
        if ($det -match '(?i)pile') { [void]$parts.Add('Piles detectees') }
        if ($det -match '(?i)deee') { [void]$parts.Add('DEEE detecte') }
    }
    if ($parts.Count -lt 1) { return 'Aucune prestation metier specifique detectee' }
    return ($parts -join ', ')
}

function Get-PlanningTourneeStep5Percent {
    param([double]$SubRatio = 0)
    $ratio = [Math]::Max(0.0, [Math]::Min(1.0, $SubRatio))
    if (Get-Command Get-PlanningRebuildStepPercent -ErrorAction SilentlyContinue) {
        return (Get-PlanningRebuildStepPercent -StepIndex 5 -StepCount 5 -SubRatio $ratio)
    }
    return [int][Math]::Min(100, [Math]::Max(0, [Math]::Round(65.0 + ($ratio * 35.0))))
}

function Update-PlanningTourneeStep5Progress {
    param(
        [double]$SubRatio = 0,
        [string]$Detail = $null,
        [ValidateSet('Running', 'OK')]
        [string]$Status = 'Running'
    )
    if (Get-Command Update-PlanningRebuildStepProgress -ErrorAction SilentlyContinue) {
        Update-PlanningRebuildStepProgress -StepIndex 5 -StepCount 5 -Label 'Composition pages de garde' `
            -Status $Status -Detail $Detail -SubRatio $SubRatio
        return
    }
    $cb = $script:PlanningRebuildProgressCallback
    if ($null -eq $cb) { return }
    try {
        & $cb @{
            StepIndex = 5
            StepCount = 5
            Label     = 'Composition pages de garde'
            Status    = 'Running'
            Detail    = $Detail
            Percent   = (Get-PlanningTourneeStep5Percent -SubRatio $SubRatio)
        }
    }
    catch {
        Write-Warning ("[TOURNEE-UI] ProgressCallback echoue : {0}" -f $_.Exception.Message)
    }
}

function Update-PlanningTourneeStep5OdmSearchProgress {
    param(
        [int]$WoIndex,
        [int]$TotalWos
    )
    if ($TotalWos -lt 1) { $TotalWos = 1 }
    $safeIndex = [Math]::Max(0, [Math]::Min($WoIndex, $TotalWos))
    $percent = if ($safeIndex -lt 1) { 0 } else { [math]::Floor(($safeIndex / $TotalWos) * 100) }
    $detail = "Recherche des ODM sans correspondance... ($safeIndex/$TotalWos - $percent%)"
    $subRatio = 0.10 + (($safeIndex / $TotalWos) * 0.05)
    Update-PlanningTourneeStep5Progress -SubRatio $subRatio -Detail $detail
}

function Write-TourneeCompositionTourStart {
    param(
        [AllowNull()][scriptblock]$ProgressCallback,
        [Parameter(Mandatory = $true)][string]$Detail,
        [int]$StepIndex = 5,
        [int]$StepCount = 5,
        [double]$SubRatio = -1
    )
    if ($null -eq $ProgressCallback) { return }
    $evt = @{
        StepIndex = $StepIndex
        StepCount = $StepCount
        Label     = 'Composition pages de garde'
        Status    = 'TourneeStart'
        Detail    = $Detail
    }
    if ($SubRatio -ge 0) { $evt['Percent'] = (Get-PlanningTourneeStep5Percent -SubRatio $SubRatio) }
    try { & $ProgressCallback $evt }
    catch {
        Write-Warning ("[TOURNEE-UI] ProgressCallback echoue (Status=TourneeStart) : {0}" -f $_.Exception.Message)
    }
}

function Write-TourneeCompositionTourProgress {
    param(
        [AllowNull()][scriptblock]$ProgressCallback,
        [Parameter(Mandatory = $true)][string]$Detail,
        [int]$StepIndex = 5,
        [int]$StepCount = 5,
        [double]$SubRatio = -1
    )
    if ($null -eq $ProgressCallback -or [string]::IsNullOrWhiteSpace($Detail)) { return }
    $evt = @{
        StepIndex = $StepIndex
        StepCount = $StepCount
        Label     = 'Composition pages de garde'
        Status    = 'TourneeProgress'
        Detail    = $Detail
    }
    if ($SubRatio -ge 0) { $evt['Percent'] = (Get-PlanningTourneeStep5Percent -SubRatio $SubRatio) }
    try { & $ProgressCallback $evt }
    catch {
        Write-Warning ("[TOURNEE-UI] ProgressCallback echoue (Status=TourneeProgress) : {0}" -f $_.Exception.Message)
    }
}

function Write-TourneeCompositionTourEnd {
    param(
        [AllowNull()][scriptblock]$ProgressCallback,
        [int]$StepIndex = 5,
        [int]$StepCount = 5
    )
    if ($null -eq $ProgressCallback) { return }
    try {
        & $ProgressCallback @{
            StepIndex  = $StepIndex
            StepCount  = $StepCount
            Label      = 'Composition pages de garde'
            Status     = 'TourneeEnd'
            Detail     = $null
        }
    }
    catch {
        Write-Warning ("[TOURNEE-UI] ProgressCallback echoue (Status=TourneeEnd) : {0}" -f $_.Exception.Message)
    }
}

function Write-TourneeCompositionTreeLine {
    param(
        [AllowNull()][scriptblock]$ProgressCallback,
        [string]$TreePrefix,
        [string]$Text = '',
        [int]$StepIndex = 5,
        [int]$StepCount = 5
    )
    if ([string]::IsNullOrWhiteSpace($Text)) {
        Write-Verbose '[TREE] Ignored empty line'
        return
    }
    $pfx = if ($null -ne $TreePrefix) { [string]$TreePrefix } else { '' }
    Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback -Detail ($pfx + $Text) -StepIndex $StepIndex -StepCount $StepCount
}

function Add-TourneeCompositionGeneratedDocCount {
    param([int]$Delta = 1)
    if ($null -eq $script:PlanningTourneeGeneratedDocCount) { $script:PlanningTourneeGeneratedDocCount = 0 }
    $script:PlanningTourneeGeneratedDocCount += $Delta
}

function Get-CnsTourneeBlockPrestationDetectionLabel {
    param(
        [Parameter(Mandatory = $true)] $Block,
        [Parameter(Mandatory = $true)][object[]]$SortedGsPairs,
        [AllowEmptyCollection()][object[]]$WorkOrders = @(),
        [AllowEmptyCollection()][object[]]$PdfEntities = @()
    )
    $hasDestruction = $false
    $hasCea = $false
    $hasPiles = $false
    $hasDeee = $false
    $sortedPairsArr = @($SortedGsPairs)
    for ($pn = [int]$Block.MainFrom1; $pn -le [int]$Block.MainTo1; $pn++) {
        $pairIdx = $pn - 1
        if ($pairIdx -lt 0 -or $pairIdx -ge $sortedPairsArr.Count) { continue }
        $gsPair = $sortedPairsArr[$pairIdx]
        [int]$rawPnPage = 0
        try { $rawPnPage = [int]$gsPair.RawPageNum } catch { $rawPnPage = 0 }
        $woPage = Resolve-CnsWorkOrderEntityForStep5 -GsPair $gsPair -FinalOrderToLine @{} -OrderToWorkOrder @{} -WorkOrders $WorkOrders -PdfEntities @($PdfEntities)
        $pePage = $null
        if ($rawPnPage -gt 0) {
            $pePage = Get-CnsPageEntityByPhysicalPage -PageNumberOneBased $rawPnPage -PdfEntities @($PdfEntities)
        }
        $metierPage = Get-CnsPdfPageMetierAnalysis -PageEntity $pePage -WorkOrderEntity $woPage
        if ($metierPage.RequiresDestructionCertificate) { $hasDestruction = $true }
        foreach ($entry in @($metierPage.TrackDechetEntries)) {
            if ($null -eq $entry) { continue }
            $det = [string]$entry.Detail
            if ($det -match '(?i)pile') { $hasPiles = $true }
            if ($det -match '(?i)deee') { $hasDeee = $true }
        }
        if ($null -ne $pePage) {
            $txt = Get-CnsPdfOdmPageTextContent -PageEntity $pePage -WorkOrderEntity $woPage
            $norm = ConvertTo-CnsMetierMatchNormalizedText -Text $txt
            if ($norm -match '(?i)\bcea\b') { $hasCea = $true }
        }
    }
    $parts = [System.Collections.Generic.List[string]]::new()
    if ($hasDestruction) { [void]$parts.Add('Destruction confidentielle detectee') }
    if ($hasCea) { [void]$parts.Add('CEA detecte') }
    if ($hasPiles) { [void]$parts.Add('Piles detectees') }
    if ($hasDeee) { [void]$parts.Add('DEEE detecte') }
    if ($parts.Count -lt 1) { return 'Aucune prestation metier specifique detectee' }
    return ($parts -join ', ')
}

function Test-CnsOdmDuplicationTargetClient {
    param(
        [AllowNull()] $WorkOrderEntity,
        [AllowNull()] $PageEntity
    )
    $targetIds = New-Object System.Collections.Generic.List[string]
    [void]$targetIds.Add('25263')   # LABORATOIRES AGUETTANT
    [void]$targetIds.Add('61742')   # AIR LIQUIDE INDUSTRIE VOREPPE
    if (-not [string]::IsNullOrWhiteSpace($env:CN_ODM_DUPLICATE_CLIENT_IDS)) {
        foreach ($part in @($env:CN_ODM_DUPLICATE_CLIENT_IDS -split '[,;]')) {
            $t = $part.Trim()
            if (-not [string]::IsNullOrWhiteSpace($t)) { [void]$targetIds.Add($t) }
        }
    }

    [string]$cid = ''
    [string]$cname = ''
    if ($null -ne $WorkOrderEntity) {
        try { $cid = ([string]$WorkOrderEntity.ClientID).Trim() } catch { $cid = '' }
        try { $cname = ([string]$WorkOrderEntity.ClientName).Trim() } catch { $cname = '' }
    }
    if ($null -ne $PageEntity) {
        if ([string]::IsNullOrWhiteSpace($cid)) {
            try { $cid = ([string]$PageEntity.ClientID).Trim() } catch { $cid = '' }
        }
        if ([string]::IsNullOrWhiteSpace($cname)) {
            try { $cname = ([string]$PageEntity.ClientName).Trim() } catch { $cname = '' }
        }
    }

    foreach ($id in @($targetIds)) {
        if (-not [string]::IsNullOrWhiteSpace($cid) -and $cid -eq $id) { return $true }
    }

    if (-not [string]::IsNullOrWhiteSpace($cname)) {
        if ($cname -match '(?i)LABORATOIRES\s+AGUETTANT') { return $true }
        if ($cname -match '(?i)AIR\s+LIQUIDE\s+INDUSTRIE\s+VOREPPE') { return $true }
    }

    return $false
}

function Get-CnsOdmDuplicationRunKey {
    param(
        [AllowNull()] $WorkOrderEntity,
        [AllowNull()] $PageEntity
    )
    if ($null -ne $WorkOrderEntity) {
        if (Get-Command Get-CnsDestructionCertificateWorkOrderKey -ErrorAction SilentlyContinue) {
            $wk = Get-CnsDestructionCertificateWorkOrderKey -WorkOrderEntity $WorkOrderEntity
            if (-not [string]::IsNullOrWhiteSpace($wk)) { return ('WO:' + $wk.Trim()) }
        }
        [string]$cid = ''
        try { $cid = ([string]$WorkOrderEntity.ClientID).Trim() } catch { $cid = '' }
        if (-not [string]::IsNullOrWhiteSpace($cid)) { return ('CID:' + $cid) }
    }
    if ($null -ne $PageEntity) {
        [string]$cid2 = ''
        try { $cid2 = ([string]$PageEntity.ClientID).Trim() } catch { $cid2 = '' }
        if (-not [string]::IsNullOrWhiteSpace($cid2)) { return ('CID:' + $cid2) }
        try { return ('PE:' + [int]$PageEntity.PageNumber) } catch { return 'PE:0' }
    }
    return $null
}

function Add-CnsOdmDuplicateSliceAfterOriginal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SlicePath,
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[string]]$Frag,
        [Parameter(Mandatory = $true)]
        [string]$RunKeyLabel
    )
    if ([string]::IsNullOrWhiteSpace($SlicePath) -or -not (Test-Path -LiteralPath $SlicePath)) { return }
    $dupPath = Join-Path ([System.IO.Path]::GetDirectoryName($SlicePath)) (
        ([System.IO.Path]::GetFileNameWithoutExtension($SlicePath) + '_dup.pdf')
    )
    Copy-Item -LiteralPath $SlicePath -Destination $dupPath -Force
    [void]$Frag.Add($dupPath)
    Write-Host ("[DUPLICATION-ODM] 1 page(s) copiee(s) pour {0} (immediatement apres original)." -f $RunKeyLabel) -ForegroundColor Green
}

function Invoke-CnsFlushOdmDuplicationRun {
    <#
    .SYNOPSIS
        Insere les copies ODM du tampon (legacy) ou uniquement certificats/CEA différés du run de duplication.
        Les copies sont normalement ajoutées via Add-CnsOdmDuplicateSliceAfterOriginal dans la boucle STEP 5.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[string]]$Frag,
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[string]]$SlicePaths,
        [AllowNull()]
        [hashtable]$PendingCert,
        [AllowNull()]
        [System.Collections.Generic.List[object]]$PendingCea,
        [AllowNull()]
        [System.Collections.Generic.List[object]]$PendingFt,
        [Parameter(Mandatory = $true)]
        [string]$RunKeyLabel,
        [Parameter(Mandatory = $true)]
        [string]$TmpDir,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [System.Collections.Generic.HashSet[string]]$CertInjectedForWo,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [System.Collections.Generic.HashSet[int]]$CeaInjectedForPage,
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [System.Collections.Generic.HashSet[int]]$FtInjectedForPage,
        [AllowNull()][scriptblock]$ProgressCallback,
        [Parameter(Mandatory = $true)]
        [string]$TChildCore,
        [Parameter(Mandatory = $true)]
        [hashtable]$FinalOrderToLine,
        [Parameter(Mandatory = $true)]
        [array]$Segments,
        [Parameter(Mandatory = $true)]
        [hashtable]$OrderToSeg,
        [Parameter(Mandatory = $true)]
        [datetime]$VisitDate
    )

    if ($null -eq $CertInjectedForWo -or -not ($CertInjectedForWo -is [System.Collections.Generic.HashSet[string]])) {
        $CertInjectedForWo = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    }
    if ($null -eq $CeaInjectedForPage -or -not ($CeaInjectedForPage -is [System.Collections.Generic.HashSet[int]])) {
        $CeaInjectedForPage = [System.Collections.Generic.HashSet[int]]::new()
    }
    if ($null -eq $FtInjectedForPage -or -not ($FtInjectedForPage -is [System.Collections.Generic.HashSet[int]])) {
        $FtInjectedForPage = [System.Collections.Generic.HashSet[int]]::new()
    }
    if ($null -eq $PendingCea) {
        $PendingCea = [System.Collections.Generic.List[object]]::new()
    }
    if ($null -eq $PendingFt) {
        $PendingFt = [System.Collections.Generic.List[object]]::new()
    }

    $hasPendingCopies = ($SlicePaths.Count -ge 1)
    $hasPendingCert = ($null -ne $PendingCert)
    $hasPendingCea = ($PendingCea.Count -gt 0)
    $hasPendingFt = ($PendingFt.Count -gt 0)
    if (-not $hasPendingCopies -and -not $hasPendingCert -and -not $hasPendingCea -and -not $hasPendingFt) { return }

    $dupCount = 0
    foreach ($origPath in @($SlicePaths)) {
        if ([string]::IsNullOrWhiteSpace($origPath) -or -not (Test-Path -LiteralPath $origPath)) { continue }
        $dupPath = Join-Path ([System.IO.Path]::GetDirectoryName($origPath)) (
            ([System.IO.Path]::GetFileNameWithoutExtension($origPath) + '_dup.pdf')
        )
        Copy-Item -LiteralPath $origPath -Destination $dupPath -Force
        [void]$Frag.Add($dupPath)
        $dupCount++
    }
    if ($dupCount -gt 0) {
        Write-Host ("[DUPLICATION-ODM] {0} page(s) copiee(s) pour {1} (apres originaux, avant certificat/CEA)." -f $dupCount, $RunKeyLabel) -ForegroundColor Green
    }

    if ($null -ne $PendingCert) {
        $woPage = $PendingCert.WorkOrderEntity
        $gsPair = $PendingCert.GsPair
        $fi = [int]$PendingCert.BlockIndex
        $sliceIx = [int]$PendingCert.SliceIndex
        $pn = [int]$PendingCert.ReorderPage
        $woCacheKey = [string]$PendingCert.WorkOrderCacheKey
        if (-not [string]::IsNullOrWhiteSpace($woCacheKey) -and $certInjectedForWo.Add($woCacheKey)) {
            if (Get-Command New-CnsDestructionCertificatePdfFromExcelTemplate -ErrorAction SilentlyContinue) {
                $segMeta = Get-CnsTourneeCoverSegmentMetaForPair -GsPair $gsPair -FinalOrderToLine $FinalOrderToLine -Segments $Segments -ExcelOrderIndexToSegmentIndex $OrderToSeg -VisitDate $VisitDate
                $phTable = @{}
                foreach ($entry in (Get-CnsDestructionCertificatePlaceholders -WorkOrderEntity $woPage -SegmentMeta $segMeta -VisitDate $VisitDate).GetEnumerator()) {
                    $phTable[[string]$entry.Key] = [string]$entry.Value
                }
                $certOut = Join-Path $TmpDir ('cert_dest_{0:D3}_{1:D5}.pdf' -f $fi, $sliceIx)
                $certPdf = New-CnsDestructionCertificatePdfFromExcelTemplate -OutPdfPath $certOut -Placeholders $phTable
                if (-not [string]::IsNullOrWhiteSpace($certPdf) -and (Test-Path -LiteralPath $certPdf)) {
                    if (Get-Command Write-CnsDestructionCertificatePdfMergeAudit -ErrorAction SilentlyContinue) {
                        Write-CnsDestructionCertificatePdfMergeAudit -Phase 'GENERATED' -PdfPath $certPdf
                    }
                    [void]$Frag.Add($certPdf)
                    Add-TourneeCompositionGeneratedDocCount
                    Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback `
                        -Detail ("{0}Generation certificat destruction... [OK]" -f ($TChildCore + '│   └── '))
                    Write-Host ("[DESTRUCTION-CERT] Certificat injecte apres duplication ODM (WO={0}, reorder #{1}, fichier={2})." -f $woCacheKey, $pn, (Split-Path -Leaf $certPdf)) -ForegroundColor Green
                }
                else {
                    [void]$CertInjectedForWo.Remove($woCacheKey)
                    Write-Warning ("[DESTRUCTION-CERT] Generation certificat echouee pour WO={0} — page ODM conservee." -f $woCacheKey)
                }
            }
            else {
                [void]$CertInjectedForWo.Remove($woCacheKey)
                Write-Warning '[DESTRUCTION-CERT] Module Word certificat non charge — injection ignoree.'
            }
        }
    }

    foreach ($ceaItem in @($PendingCea)) {
        if ($null -eq $ceaItem) { continue }
        [int]$rawPnPage = [int]$ceaItem.RawPageNum
        if ($rawPnPage -lt 1) { continue }
        if (-not $CeaInjectedForPage.Add($rawPnPage)) { continue }
        $fi = [int]$ceaItem.BlockIndex
        $sliceIx = [int]$ceaItem.SliceIndex
        $pn = [int]$ceaItem.ReorderPage
        $slicePath = [string]$ceaItem.SlicePath
        $woPage = $ceaItem.WorkOrderEntity
        $pePage = $ceaItem.PageEntity
        $gsPair = $ceaItem.GsPair
        $ceaOut = Join-Path $TmpDir ('cea_{0:D3}_{1:D5}.pdf' -f $fi, $sliceIx)
        $ceaPdf = $null
        if (Get-Command New-CnsCeaPointsDeCollectesPdfFromExcelTemplate -ErrorAction SilentlyContinue) {
            $segMetaCea = Get-CnsTourneeCoverSegmentMetaForPair -GsPair $gsPair -FinalOrderToLine $FinalOrderToLine -Segments $Segments -ExcelOrderIndexToSegmentIndex $OrderToSeg -VisitDate $VisitDate
            $phCea = @{}
            foreach ($entry in (Get-CnsCeaPointsDeCollectePlaceholders -WorkOrderEntity $woPage -PageEntity $pePage -SegmentMeta $segMetaCea -VisitDate $VisitDate -FragSlicePdfPath $slicePath).GetEnumerator()) {
                $phCea[[string]$entry.Key] = [string]$entry.Value
            }
            $ceaPdf = New-CnsCeaPointsDeCollectesPdfFromExcelTemplate -OutPdfPath $ceaOut -Placeholders $phCea
        }
        else {
            Write-Warning '[CEA-POINTS] Module Word CEA non charge — fallback PDF statique legacy.'
            $ceaPdf = Copy-CnsMetierTemplatePdfToWorkDir -TemplateFileName 'CeaPointsDeCollectes.pdf' -WorkDir $TmpDir -DestLeafName ('cea_{0:D3}_{1:D5}.pdf' -f $fi, $sliceIx)
        }
        if (-not [string]::IsNullOrWhiteSpace($ceaPdf) -and (Test-Path -LiteralPath $ceaPdf)) {
            Write-Host ("[CEA-POINTS] PDF injecte apres duplication ODM : {0}" -f (Split-Path -Leaf $ceaPdf)) -ForegroundColor Green
            [void]$Frag.Add($ceaPdf)
            Add-TourneeCompositionGeneratedDocCount
            Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback `
                -Detail ("{0}Generation document CEA... [OK]" -f ($TChildCore + '│   └── '))
            Write-Host ("[STEP5-METIER] Document CEA injecte apres duplication ODM (reorder #{0}, RawPage={1}, fichier={2})." -f $pn, $rawPnPage, (Split-Path -Leaf $ceaPdf)) -ForegroundColor Green
        }
        else {
            [void]$CeaInjectedForPage.Remove($rawPnPage)
            Write-Warning ("[CEA-POINTS] Generation CEA echouee pour RawPage={0} — page non injectee." -f $rawPnPage)
        }
    }

    foreach ($ftItem in @($PendingFt)) {
        if ($null -eq $ftItem) { continue }
        [int]$rawPnFt = [int]$ftItem.RawPageNum
        if ($rawPnFt -lt 1) { continue }
        if (-not $FtInjectedForPage.Add($rawPnFt)) { continue }
        $okFt = Invoke-CnsAppendFtDocumentToFrag -Frag $Frag -TmpDir $TmpDir `
            -BlockIndex ([int]$ftItem.BlockIndex) -SliceIndex ([int]$ftItem.SliceIndex) `
            -ReorderPage ([int]$ftItem.ReorderPage) -RawPageNum $rawPnFt `
            -PointCollecteLabel ([string]$ftItem.PointCollecteLabel) `
            -WorkOrderEntity $ftItem.WorkOrderEntity -PageEntity $ftItem.PageEntity -GsPair $ftItem.GsPair `
            -FinalOrderToLine $FinalOrderToLine -Segments $Segments -OrderToSeg $OrderToSeg -VisitDate $VisitDate `
            -ProgressCallback $ProgressCallback -TChildCore $TChildCore
        if (-not $okFt) {
            [void]$FtInjectedForPage.Remove($rawPnFt)
        }
    }

    $SlicePaths.Clear()
    if ($null -ne $PendingCea) { $PendingCea.Clear() }
    if ($null -ne $PendingFt) { $PendingFt.Clear() }
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
        $MatchResult = $null,
        [scriptblock]$ProgressCallback = $null,
        [hashtable]$PdfRawLinesByPage = $null
    )

    $script:PlanningStep5Perf = @{
        GsBatchExtracts      = 0
        GsPageExtracts       = 0
        CeaFromStep1         = 0
        CeaPdftotextFallback = 0
    }
    $step5CompositionSw = [System.Diagnostics.Stopwatch]::StartNew()

    if ($env:CN_SKIP_TOURNEE_COVERS -in @('1', 'true')) {
        script:Write-CnsTourneeLog -Message '[TOURNEE] Composition couvertures desactivee (CN_SKIP_TOURNEE_COVERS).' -Level 'INFO'
        return $true
    }

    if (-not (Test-Path -LiteralPath $MainPdfPath)) {
        Write-Warning '[TOURNEE] Main PDF introuvable — composition abandonnee.'
        return $false
    }

    if (Get-Command Test-PlanningStep5Environment -ErrorAction SilentlyContinue) {
        $envCheck = Test-PlanningStep5Environment
        if (-not $envCheck.Ok) {
            foreach ($issue in @($envCheck.Issues)) {
                Write-Warning ("[TOURNEE] {0}" -f $issue)
                script:Write-CnsTourneeLog -Message ("[TOURNEE] Prerequis : {0}" -f $issue) -Level 'ERROR'
            }
            return $false
        }
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
    if ($null -eq $ColumnInfo) {
        script:Write-CnsTourneeLog -Message '[TOURNEE] ColumnInfo absent — detection segments Excel impossible.' -Level 'WARN'
    }
    elseif ($null -ne $ExcelData) {
        try {
            $segments = @(Get-PlanningExcelTourneeCoverSegments -ExcelData $ExcelData -ColumnInfo $ColumnInfo -FallbackVisitDate $VisitDate -ExcelOrder $ExcelOrder -OrderToWorkOrder $orderToWorkOrder)
        }
        catch {
            Write-Warning ("[TOURNEE] Segments Excel non disponibles : {0}" -f $_.Exception.Message)
            $segments = @()
        }
    }
    Write-PlanningTourneeStep5UiLog '📊 Analyse du planning Excel...'
    Write-PlanningTourneeStep5UiLog ("📄 Organisation des tournées... ({0} tournée(s) détectée(s))" -f @($segments).Count)

    $foToLine = @{}
    foreach ($ln in @($Reordered)) {
        if ($null -eq $ln) { continue }
        try {
            $foToLine[[int]$ln.FinalOrder] = $ln
        }
        catch { }
    }

    $orderToSeg = Build-CnsTourneeOrderToSegmentMap -Segments @($segments) -ExcelOrder @($ExcelOrder) -ReorderedByFinalOrder $foToLine
    script:Write-CnsTourneeLog -Message ("[TOURNEE] Segments Excel={0}, OrderToSeg={1}, pages PDF={2}." -f @($segments).Count, $orderToSeg.Count, $mainPageCount) -Level 'INFO'
    Write-PlanningTourneeStep5UiLog '🔄 Indexation des ODM...'

    $blocks = @(Build-PlanningTourneeCoverBlocks -SortedGsPairs $SortedGsPairs -FinalOrderToLine $foToLine -ExcelOrderIndexToSegmentIndex $orderToSeg)
    $blockTotal = @($blocks).Count
    if ($blockTotal -lt 1 -and $mainPageCount -ge 1) {
        script:Write-CnsTourneeLog -Message '[TOURNEE] Aucun bloc detecte — bloc unique SEG1 sur tout le PDF.' -Level 'WARN'
        $blocks = @([pscustomobject]@{
            GroupKey  = 'SEG1'
            MainFrom1 = 1
            MainTo1   = $mainPageCount
        })
        $blockTotal = 1
        if ($orderToSeg.Count -lt 1) {
            $orderToSeg[1] = 1
            $orderToSeg['1'] = 1
        }
    }
    script:Write-CnsTourneeLog -Message ("[TOURNEE] Blocs composition : {0} ({1})." -f $blockTotal, (($blocks | ForEach-Object { '{0}:{1}-{2}' -f $_.GroupKey, $_.MainFrom1, $_.MainTo1 }) -join ', ')) -Level 'INFO'
    $script:PlanningTourneeBlockTotal = $blockTotal
    $script:PlanningTourneeGeneratedDocCount = 0
    $totalTournees = [Math]::Max(1, $blockTotal)
    $tourneeIndex = 0
    Update-PlanningTourneeStep5Progress -SubRatio 0 -Detail 'Analyse des segments...'
    Update-PlanningTourneeStep5Progress -SubRatio 0.05 -Detail ("Segments detectes : {0} tournee(s)" -f $totalTournees)

    $frag = [System.Collections.Generic.List[string]]::new()
    $runId = [Guid]::NewGuid().ToString('N')
    $tmpDir = $null
    $tmpDir = Join-Path $env:TEMP ('cn_coverwork_' + $runId)

    try {
        $null = New-Item -ItemType Directory -Path $tmpDir -Force -ErrorAction Stop

        Write-CnsStep5ConsoleProgress -Message "`n[PROGRESS] STEP 5 : Composition des pages de garde..." -ForegroundColor Cyan
        Write-CnsStep5ConsoleProgress -Message '[PROGRESS]   - Creation des pages de garde globales...' -ForegroundColor Gray
        Update-PlanningTourneeStep5Progress -SubRatio 0.10 -Detail 'Page de garde globale...'

        $globalCov = Join-Path $tmpDir 'cover_global.pdf'

        script:Write-CnsTourneeLog -Message '[TOURNEE] Creation page de garde globale (premiere page du PDF final).' -Level 'INFO'
        $coverElements = @()
        $coverAllMatched = $false
        $coverS1 = -1
        $coverS2 = -1
        $coverS3 = -1
        $odmSearchTotalWos = @($WorkOrders).Count
        if ($odmSearchTotalWos -lt 1) { $odmSearchTotalWos = 1 }
        Update-PlanningTourneeStep5OdmSearchProgress -WoIndex 0 -TotalWos $odmSearchTotalWos
        if (Get-Command Build-PlanningOdmMismatchThreeSectionCoverLines -ErrorAction SilentlyContinue) {
            try {
                $missingList = @()
                if ($null -ne $MatchResult -and $null -ne $MatchResult.Missing) {
                    $missingList = @($MatchResult.Missing)
                }
                $orphanWorkOrders = @()
                if (Get-Command Get-PlanningUnmatchedPdfWorkOrders -ErrorAction SilentlyContinue) {
                    $orphanWorkOrders = @(Get-PlanningUnmatchedPdfWorkOrders -WorkOrders $WorkOrders -MatchResult $MatchResult)
                }
                $hasMissingOrphans = ($missingList.Count -gt 0) -or ($orphanWorkOrders.Count -gt 0)

                if (-not $hasMissingOrphans) {
                    Write-PlanningTourneeStep5UiLog '🔍 Tous les ODM sont matchés - synthèse simplifiée'
                    $coverReport = [pscustomobject]@{
                        Elements       = @()
                        Lines          = @()
                        Section1Count  = 0
                        Section2Count  = 0
                        Section3Count  = 0
                        AllMatched     = $true
                    }
                }
                else {
                    Write-PlanningTourneeStep5UiLog ("🔍 Analyse des ODM sans correspondance ($($missingList.Count) Excel sans ODM, $($orphanWorkOrders.Count) ODM sans Excel)")
                    $coverReport = Build-PlanningOdmMismatchThreeSectionCoverLines `
                        -Missing $missingList `
                        -WorkOrders @($orphanWorkOrders) `
                        -ExcelOrder @($ExcelOrder) `
                        -MatchResult $MatchResult `
                        -TourSegments @($segments) `
                        -MaxEntriesPerSection 20
                }
                $coverAllMatched = [bool]$coverReport.AllMatched
                $coverS1 = [int]$coverReport.Section1Count
                $coverS2 = [int]$coverReport.Section2Count
                $coverS3 = [int]$coverReport.Section3Count
                if (-not $coverAllMatched -and $null -ne $coverReport.Elements) {
                    $coverElements = @($coverReport.Elements)
                }
                if ($coverAllMatched) {
                    Update-PlanningTourneeStep5Progress -SubRatio 0.15 -Detail '🔍 Recherche des ODM sans correspondance... — ✅ Tous les ODM ont été matchés'
                }
                else {
                    Update-PlanningTourneeStep5Progress -SubRatio 0.15 -Detail ("🔍 Recherche des ODM sans correspondance... — ✅ Analyse terminée - Section1:$coverS1 Section2:$coverS2 Section3:$coverS3")
                }
            }
            catch {
                Write-Warning ("[TOURNEE] Diagnostic ODM non matches indisponible : {0}" -f $_.Exception.Message)
            }
        }
        Write-CnsStep5ConsoleProgress -Message '[PROGRESS]   - Page de garde globale...' -ForegroundColor Gray
        Write-PlanningTourneeStep5UiLog '🎨 Création de la page de synthèse (Ghostscript)...'
        $gcOk = (New-CnsGlobalMismatchCoverPdf -OutPdfPath $globalCov `
                -TotalOdmCount $totalODM `
                -UnmatchedOdmCount $unmatchedCount `
                -CoverElements $coverElements `
                -Section1Count $coverS1 `
                -Section2Count $coverS2 `
                -Section3Count $coverS3 `
                -AllMatched:$coverAllMatched)
        if (-not $gcOk) {
            throw 'Ghostscript global cover echouee'
        }
        [void]$frag.Add($globalCov)
        script:Write-CnsTourneeLog -Message '[TOURNEE] Page de garde globale OK.' -Level 'INFO'
        Write-PlanningTourneeStep5UiLog '💾 Sauvegarde de la page de garde...'

        $seenSegments = @{}
        $prefaceAlreadyAdded = $false
        $certInjectedForWo = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $ceaInjectedForPage = New-Object 'System.Collections.Generic.HashSet[int]'
        $ftInjectedForPage = New-Object 'System.Collections.Generic.HashSet[int]'
        $bilanInjectedForSeg = @{}
        $sortedPairsArr = @($SortedGsPairs)
        $fi = 0
        foreach ($blk in @($blocks)) {
            $fi++
            script:Write-CnsTourneeLog -Message ("[TOURNEE] Bloc {0}/{1} : {2} (pages {3}-{4})." -f $fi, $blockTotal, [string]$blk.GroupKey, $blk.MainFrom1, $blk.MainTo1) -Level 'INFO'
            $isLastTour = ($fi -eq $blockTotal)
            $tBranchCore = if ($isLastTour) { '└── ' } else { '├── ' }
            $tChildCore = if ($isLastTour) { '    ' } else { '│   ' }

            $segmentName = [string]$blk.GroupKey
            $tourHeaderDetail = $segmentName
            $segUi = $null
            if ([string]$blk.GroupKey -match '^SEG(\d+)$') {
                $segNumUi = [int]$Matches[1]
                $segUi = ($segments | Where-Object { [int]$_.SegmentIndex -eq $segNumUi } | Select-Object -First 1)
                if ($null -ne $segUi) {
                    $segLabel = [string]$segUi.Collecteur
                    if ([string]::IsNullOrWhiteSpace($segLabel)) { $segLabel = [string]$segUi.Vehicule }
                    if (-not [string]::IsNullOrWhiteSpace($segLabel)) { $segmentName = $segLabel }
                    $jjUi = [string]$segUi.DisplayDateJM
                    if ([string]::IsNullOrWhiteSpace($jjUi)) {
                        try { $jjUi = ($segUi.TourDate).ToString('dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture) } catch { $jjUi = $VisitDate.ToString('dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture) }
                    }
                    $dateTitleUi = Format-CnsTourneeCoverGardeDateTitle -DateJJMMAAAA $jjUi
                    $tourHeaderDetail = ('{0} - Collecteur : {1}' -f $dateTitleUi, $segLabel)
                }
            }
            if ([string]::IsNullOrWhiteSpace($tourHeaderDetail)) { $tourHeaderDetail = 'Operation en cours' }
            $tourneeIndex = $fi
            Write-PlanningTourneeStep5UiLog ("🚩 Tournée {0}/{1} - Préparation..." -f $tourneeIndex, $totalTournees)
            Write-CnsStep5ConsoleProgress -Message ("`n[PROGRESS]   - Tournee {0}/{1} : {2}" -f $fi, $blockTotal, $tourHeaderDetail) -ForegroundColor Yellow
            $tourRatioStart = 0.15 + (($tourneeIndex - 1) * (0.80 / $totalTournees))
            $tourRatioEnd = 0.15 + ($tourneeIndex * (0.80 / $totalTournees))
            Update-PlanningTourneeStep5Progress -SubRatio $tourRatioStart `
                -Detail ("Tournée {0}/{1} - Debut" -f $tourneeIndex, $totalTournees)
            Write-TourneeCompositionTourStart -ProgressCallback $ProgressCallback -Detail ("{0}/{1}" -f $fi, $blockTotal) -SubRatio $tourRatioStart
            Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback `
                -Detail ("{0}Tournee {1}/{2} : {3}" -f $tBranchCore, $fi, $blockTotal, $tourHeaderDetail)

            $odmTotal = ([int]$blk.MainTo1 - [int]$blk.MainFrom1 + 1)
            if ($odmTotal -lt 1) { $odmTotal = 0 }
            $hasSegBilan = [string]$blk.GroupKey -match '^SEG(\d+)$'
            $coverBranch = if ($odmTotal -gt 0 -or $hasSegBilan) { '├── ' } else { '└── ' }

            $coverPath = Join-Path $tmpDir ('cover_blk_{0}.pdf' -f $fi)
            $coverCreated = $false
            Write-CnsStep5ConsoleProgress -Message '[PROGRESS]       -> Creation page de garde...' -ForegroundColor Gray

            switch -Regex ([string]$blk.GroupKey) {
                '^SEG(\d+)$' {
                    $n = [int]$Matches[1]
                    if ($seenSegments.ContainsKey($n)) {
                        Write-Host ("[TOURNEE] Garde tournée segment {0} deja inseree — pas de doublon pour ce bloc." -f $n) -ForegroundColor DarkGray
                    }
                    else {
                        $seenSegments[$n] = $true
                        script:Write-CnsTourneeLog -Message ("[TOURNEE] Creating cover page for segment {0}" -f $n) -Level 'INFO'
                        Write-Host "[TOURNEE] Creating cover page for segment $n" -ForegroundColor Cyan
                        $seg = ($segments | Where-Object { [int]$_.SegmentIndex -eq $n } | Select-Object -First 1)
                        if ($null -eq $seg) {
                            Write-Host '[TOURNEE] Segment metadata introuvable — garde minimale (TOURNEE NON MATCHEE).' -ForegroundColor Yellow
                            $minimal = Join-Path $tmpDir ('cover_blk_min_{0}.pdf' -f $fi)
                            $fdMin = $VisitDate.ToString('dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
                            Write-Host ("[TOURNEE-COVER] Segment={0} Incomplete=True (metadata absente) Date={1}" -f $n, $fdMin) -ForegroundColor Cyan
                            if (New-CnsTourneeHeaderCoverPdf -OutPdfPath $minimal -DateJJMMAAAA $fdMin -Collecteur 'INCONNU' -Vehicule 'NON SPECIFIE' -TourneeIncomplete:$true -MetierMemoLines @()) {
                                [void]$frag.Add($minimal)
                                $coverCreated = $true
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
                            Write-PlanningTourneeStep5UiLog ("🔎 Tournée {0}/{1} - Analyse des prestations..." -f $tourneeIndex, $totalTournees)
                            $metierMemos = @(Get-CnsTourneeMetierMemoLinesForBlock -MainFrom1 ([int]$blk.MainFrom1) -MainTo1 ([int]$blk.MainTo1) `
                                -SortedGsPairs $sortedPairsArr -FinalOrderToLine $foToLine -WorkOrders $WorkOrders -PdfEntities @($PdfEntities))
                            Write-Host ("[STEP5-METIER] Segment {0} : {1} memo(s) garde tournée (source PDF ODM)." -f $n, $metierMemos.Count) -ForegroundColor DarkCyan
                            Write-PlanningTourneeStep5UiLog ("🎨 Tournée {0}/{1} - Création page de garde..." -f $tourneeIndex, $totalTournees)
                            $vehiculeImmat = $null
                            $vehiculeNumeroParc = [string]$seg.Vehicule
                            if (-not [string]::IsNullOrWhiteSpace($vehiculeNumeroParc)) {
                                $vehiculeImmat = Get-CnsVehiculeImmatriculationByNumeroParc -NumeroParc $vehiculeNumeroParc
                                if ([string]::IsNullOrWhiteSpace($vehiculeImmat)) {
                                    Write-Host ("[GARDE] Immatriculation introuvable pour le parc: {0}" -f $vehiculeNumeroParc) -ForegroundColor Yellow
                                    $normalizedParc = ([string]$vehiculeNumeroParc).Trim()
                                    $normalizedParc = [regex]::Replace($normalizedParc, '\s+', ' ').Trim()
                                    if ($normalizedParc -ne $vehiculeNumeroParc.Trim()) {
                                        $vehiculeImmat = Get-CnsVehiculeImmatriculationByNumeroParc -NumeroParc $normalizedParc
                                        if (-not [string]::IsNullOrWhiteSpace($vehiculeImmat)) {
                                            Write-Host ("[GARDE] Immatriculation trouvée après normalisation: {0}" -f $vehiculeImmat) -ForegroundColor Green
                                        }
                                    }
                                }
                                else {
                                    Write-Host ("[GARDE] Immatriculation trouvée: {0}" -f $vehiculeImmat) -ForegroundColor Green
                                }
                            }
                            if (New-CnsTourneeHeaderCoverPdf -OutPdfPath $coverPath -DateJJMMAAAA $jj -Collecteur ([string]$seg.Collecteur) `
                                -Vehicule $vehiculeNumeroParc -VehiculeImmatriculation $vehiculeImmat -TourneeIncomplete:$inc -MetierMemoLines $metierMemos) {
                                [void]$frag.Add($coverPath)
                                $coverCreated = $true
                            }
                            else {
                                Write-Warning "[TOURNEE] Cover segment $n GS failure"
                                [void]$seenSegments.Remove($n)
                            }
                        }
                    }
                }
                default {
                    script:Write-CnsTourneeLog -Message ("[TOURNEE] Creating cover page for preface / hors segment (cle={0})" -f [string]$blk.GroupKey) -Level 'INFO'
                    Write-Host ('[TOURNEE] Creating cover page for preface / hors segment Excel (cle=' + ([string]$blk.GroupKey) + ')') -ForegroundColor Cyan
                    Write-Host ("[TOURNEE] Pages count (bloque principal) = {0}" -f (1 + $blk.MainTo1 - $blk.MainFrom1)) -ForegroundColor DarkCyan
                    if (-not $prefaceAlreadyAdded) {
                        if (New-CnsPrefaceSectionCoverPdf -OutPdfPath $coverPath -TotalOdmCount $totalODM -UnmatchedOdmCount $unmatchedCount) {
                            [void]$frag.Add($coverPath)
                            $prefaceAlreadyAdded = $true
                            $coverCreated = $true
                        }
                        else {
                            Write-Warning '[TOURNEE] Cover prefixe echouee'
                        }
                    }
                }
            }

            if ($coverCreated) {
                Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback `
                    -Detail ("{0}Creation page de garde tournee... [OK]" -f ($tChildCore + $coverBranch))
            }

            $sliceIx = 0
            $odmIdx = 0
            $dupRunKey = $null
            $dupPendingCert = $null
            $dupPendingCea = [System.Collections.Generic.List[object]]::new()
            $dupPendingFt = [System.Collections.Generic.List[object]]::new()
            $emptyDupSliceList = [System.Collections.Generic.List[string]]::new()

            $batchFirst = [int]$blk.MainFrom1
            $batchLast = [int]$blk.MainTo1
            $blockBatchPath = $null
            $sliceSourcePdf = $mainAbs
            if ($batchLast -gt $batchFirst) {
                $blockBatchPath = Join-Path $tmpDir ("block_batch_{0:D3}.pdf" -f $fi)
                if (-not (Invoke-CnsGhostscriptExtractPageRange -SourcePdf $mainAbs -FirstPageOneBased $batchFirst `
                        -LastPageOneBased $batchLast -OutPdfPath $blockBatchPath -SkipPrepress)) {
                    throw ("[TOURNEE] Extraction lot pages {0}-{1} echouee." -f $batchFirst, $batchLast)
                }
                $sliceSourcePdf = $blockBatchPath
                script:Write-CnsTourneeLog -Message ("[TOURNEE] Lot GS bloc {0} : pages {1}-{2} extraites en un appel." -f $fi, $batchFirst, $batchLast) -Level 'INFO'
            }

            for ($pn = $batchFirst; $pn -le $batchLast; $pn++) {
                $sliceIx++
                $odmIdx++
                if ($odmTotal -gt 0 -and ($odmIdx % 5 -eq 0 -or $odmIdx -eq $odmTotal)) {
                    Write-PlanningTourneeStep5UiLog ("📄 Tournée {0}/{1} - Extraction des pages ({2}/{3})..." -f $tourneeIndex, $totalTournees, $odmIdx, $odmTotal)
                }
                if ($odmTotal -gt 0 -and $odmIdx % 10 -eq 0) {
                    Write-CnsStep5ConsoleProgress -Message ("[PROGRESS]       -> Traitement ODM {0}/{1}..." -f $odmIdx, $odmTotal) -ForegroundColor Gray
                }
                $slicePath = Join-Path $tmpDir ('main_slice_{0:D3}_{1:D5}.pdf' -f $fi, $sliceIx)
                $localPage = if ($null -ne $blockBatchPath) { ($pn - $batchFirst + 1) } else { $pn }
                $useSkipPrepress = ($null -ne $blockBatchPath) -or ($batchLast -gt $batchFirst)
                if (-not (Invoke-CnsGhostscriptExtractOnePage -SourcePdf $sliceSourcePdf -FirstPageOneBased $localPage `
                        -OutPdfPath $slicePath -SkipPrepress:$useSkipPrepress)) {
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

                    $runKey = Get-CnsOdmDuplicationRunKey -WorkOrderEntity $woPage -PageEntity $pePage
                    $isDupTarget = Test-CnsOdmDuplicationTargetClient -WorkOrderEntity $woPage -PageEntity $pePage
                    $hasDupMetierPending = ($null -ne $dupPendingCert) -or ($dupPendingCea.Count -gt 0) -or ($dupPendingFt.Count -gt 0)
                    if ($hasDupMetierPending -and (
                            -not $isDupTarget -or
                            [string]::IsNullOrWhiteSpace($runKey) -or
                            ($null -ne $dupRunKey -and $runKey -ne $dupRunKey)
                        )) {
                        Invoke-CnsFlushOdmDuplicationRun -Frag $frag -SlicePaths $emptyDupSliceList `
                            -PendingCert $dupPendingCert -PendingCea $dupPendingCea -PendingFt $dupPendingFt `
                            -RunKeyLabel $(if ([string]::IsNullOrWhiteSpace($dupRunKey)) { 'client cible' } else { $dupRunKey }) -TmpDir $tmpDir `
                            -CertInjectedForWo $certInjectedForWo -CeaInjectedForPage $ceaInjectedForPage -FtInjectedForPage $ftInjectedForPage `
                            -ProgressCallback $ProgressCallback -TChildCore $tChildCore `
                            -FinalOrderToLine $foToLine -Segments @($segments) -OrderToSeg $orderToSeg -VisitDate $VisitDate
                        $dupRunKey = $null
                        $dupPendingCert = $null
                    }

                    if ($isDupTarget) {
                        if ([string]::IsNullOrWhiteSpace($dupRunKey)) { $dupRunKey = $runKey }
                        $dupLabel = if ([string]::IsNullOrWhiteSpace($runKey)) { 'client cible' } else { $runKey }
                        Add-CnsOdmDuplicateSliceAfterOriginal -SlicePath $slicePath -Frag $frag -RunKeyLabel $dupLabel
                    }

                    $metierPage = Get-CnsPdfPageMetierAnalysis -PageEntity $pePage -WorkOrderEntity $woPage
                    $requiresCeaPage = Test-CnsStep5FragSliceRequiresCeaDocument -FragSlicePdfPath $slicePath `
                        -PdfRawLinesByPage $PdfRawLinesByPage -RawPageNumOneBased $rawPnPage
                    $ftPointLabel = Get-CnsStep5FragSliceFtCollectionPointLabel -FragSlicePdfPath $slicePath `
                        -PdfRawLines @($pePage.Lines) -PdfRawLinesByPage $PdfRawLinesByPage -RawPageNumOneBased $rawPnPage `
                        -PageEntity $pePage -WorkOrderEntity $woPage -FtDebug:($env:CN_DEBUG_FT -eq '1')
                    if (-not (Test-CnsFtCollectionPointLabelEligible -Label $ftPointLabel)) {
                        $ftPointLabel = $null
                    }
                    $requiresFtPage = Test-CnsFtCollectionPointLabelEligible -Label $ftPointLabel
                    $odmLabel = Get-CnsOdmPagePrestationDetectionLabel -PageEntity $pePage -WorkOrderEntity $woPage `
                        -RequiresCea:$requiresCeaPage -RequiresFt:$requiresFtPage
                    if ([string]::IsNullOrWhiteSpace($odmLabel)) { $odmLabel = 'Operation en cours' }

                    $willCert = $false
                    $willCea = $false
                    $willFt = $false
                    if ($metierPage.RequiresDestructionCertificate -and $null -ne $woPage) {
                        $woKeyProbe = Get-CnsDestructionCertificateWorkOrderKey -WorkOrderEntity $woPage
                        if (-not [string]::IsNullOrWhiteSpace($woKeyProbe) -and -not $certInjectedForWo.Contains($woKeyProbe)) {
                            $willCert = $true
                            Write-PlanningTourneeStep5UiLog ("📜 Tournée {0}/{1} - Génération certificat..." -f $tourneeIndex, $totalTournees)
                        }
                    }
                    if ($requiresCeaPage -and $rawPnPage -gt 0 -and -not $ceaInjectedForPage.Contains($rawPnPage)) {
                        $willCea = $true
                        Write-PlanningTourneeStep5UiLog ("🔬 Tournée {0}/{1} - Génération document CEA..." -f $tourneeIndex, $totalTournees)
                    }
                    if ($requiresFtPage -and $rawPnPage -gt 0 -and -not $ftInjectedForPage.Contains($rawPnPage)) {
                        $willFt = $true
                        Write-PlanningTourneeStep5UiLog ("🏢 Tournée {0}/{1} - Génération document FT..." -f $tourneeIndex, $totalTournees)
                    }

                    if ($isDupTarget) {
                        if ($willCert -and $null -eq $dupPendingCert) {
                            $dupPendingCert = @{
                                WorkOrderEntity   = $woPage
                                GsPair            = $gsPair
                                BlockIndex        = $fi
                                SliceIndex        = $sliceIx
                                ReorderPage       = $pn
                                WorkOrderCacheKey = (Get-CnsDestructionCertificateWorkOrderKey -WorkOrderEntity $woPage)
                            }
                            $willCert = $false
                        }
                        if ($willCea) {
                            [void]$dupPendingCea.Add([pscustomobject]@{
                                    WorkOrderEntity = $woPage
                                    PageEntity      = $pePage
                                    GsPair          = $gsPair
                                    BlockIndex      = $fi
                                    SliceIndex      = $sliceIx
                                    ReorderPage     = $pn
                                    RawPageNum      = $rawPnPage
                                    SlicePath       = $slicePath
                                })
                            $willCea = $false
                        }
                        if ($willFt) {
                            [void]$dupPendingFt.Add([pscustomobject]@{
                                    WorkOrderEntity    = $woPage
                                    PageEntity         = $pePage
                                    GsPair             = $gsPair
                                    BlockIndex         = $fi
                                    SliceIndex         = $sliceIx
                                    ReorderPage        = $pn
                                    RawPageNum         = $rawPnPage
                                    PointCollecteLabel = $ftPointLabel
                                })
                            $willFt = $false
                        }
                    }

                    $analyseIsLast = ($odmIdx -eq $odmTotal) -and -not $willCert -and -not $willCea -and -not $willFt -and -not $hasSegBilan `
                        -and (-not $isDupTarget -or $dupPendingCert -eq $null) -and ($dupPendingCea.Count -eq 0) -and ($dupPendingFt.Count -eq 0)
                    $analyseBranch = if ($analyseIsLast) { '└── ' } else { '├── ' }
                    Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback `
                        -Detail ("{0}Analyse ODM {1}/{2} : {3}" -f ($tChildCore + $analyseBranch), $odmIdx, $odmTotal, $odmLabel)

                    if (-not $isDupTarget -and $metierPage.RequiresDestructionCertificate -and $null -ne $woPage) {
                        $woCacheKey = Get-CnsDestructionCertificateWorkOrderKey -WorkOrderEntity $woPage
                        if (-not [string]::IsNullOrWhiteSpace($woCacheKey) -and $certInjectedForWo.Add($woCacheKey)) {
                            if (Get-Command New-CnsDestructionCertificatePdfFromExcelTemplate -ErrorAction SilentlyContinue) {
                                $segMeta = Get-CnsTourneeCoverSegmentMetaForPair -GsPair $gsPair -FinalOrderToLine $foToLine -Segments $segments -ExcelOrderIndexToSegmentIndex $orderToSeg -VisitDate $VisitDate
                                $phTable = @{}
                                foreach ($entry in (Get-CnsDestructionCertificatePlaceholders -WorkOrderEntity $woPage -SegmentMeta $segMeta -VisitDate $VisitDate).GetEnumerator()) {
                                    $phTable[[string]$entry.Key] = [string]$entry.Value
                                }
                                $certOut = Join-Path $tmpDir ('cert_dest_{0:D3}_{1:D5}.pdf' -f $fi, $sliceIx)
                                Write-CnsStep5ConsoleProgress -Message '[PROGRESS]       -> Generation certificat destruction...' -ForegroundColor Gray
                                $certPdf = New-CnsDestructionCertificatePdfFromExcelTemplate -OutPdfPath $certOut -Placeholders $phTable
                                if (-not [string]::IsNullOrWhiteSpace($certPdf) -and (Test-Path -LiteralPath $certPdf)) {
                                    if (Get-Command Write-CnsDestructionCertificatePdfMergeAudit -ErrorAction SilentlyContinue) {
                                        Write-CnsDestructionCertificatePdfMergeAudit -Phase 'GENERATED' -PdfPath $certPdf
                                    }
                                    [void]$frag.Add($certPdf)
                                    Add-TourneeCompositionGeneratedDocCount
                                    Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback `
                                        -Detail ("{0}Generation certificat destruction... [OK]" -f ($tChildCore + '│   └── '))
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

                    if (-not $isDupTarget -and $requiresCeaPage -and $rawPnPage -gt 0 -and $ceaInjectedForPage.Add($rawPnPage)) {
                        $ceaOut = Join-Path $tmpDir ('cea_{0:D3}_{1:D5}.pdf' -f $fi, $sliceIx)
                        Write-CnsStep5ConsoleProgress -Message '[PROGRESS]       -> Generation document CEA...' -ForegroundColor Gray
                        $ceaPdf = $null
                        if (Get-Command New-CnsCeaPointsDeCollectesPdfFromExcelTemplate -ErrorAction SilentlyContinue) {
                            $segMetaCea = Get-CnsTourneeCoverSegmentMetaForPair -GsPair $gsPair -FinalOrderToLine $foToLine -Segments $segments -ExcelOrderIndexToSegmentIndex $orderToSeg -VisitDate $VisitDate
                            $phCea = @{}
                            foreach ($entry in (Get-CnsCeaPointsDeCollectePlaceholders -WorkOrderEntity $woPage -PageEntity $pePage -SegmentMeta $segMetaCea -VisitDate $VisitDate -FragSlicePdfPath $slicePath).GetEnumerator()) {
                                $phCea[[string]$entry.Key] = [string]$entry.Value
                            }
                            $ceaPdf = New-CnsCeaPointsDeCollectesPdfFromExcelTemplate -OutPdfPath $ceaOut -Placeholders $phCea
                        }
                        else {
                            Write-Warning '[CEA-POINTS] Module Word CEA non charge — fallback PDF statique legacy.'
                            $ceaPdf = Copy-CnsMetierTemplatePdfToWorkDir -TemplateFileName 'CeaPointsDeCollectes.pdf' -WorkDir $tmpDir -DestLeafName ('cea_{0:D3}_{1:D5}.pdf' -f $fi, $sliceIx)
                        }
                        if (-not [string]::IsNullOrWhiteSpace($ceaPdf) -and (Test-Path -LiteralPath $ceaPdf)) {
                            Write-Host ("[CEA-POINTS] PDF injecte dans frag (source DOCX dynamique) : {0}" -f (Split-Path -Leaf $ceaPdf)) -ForegroundColor Green
                            [void]$frag.Add($ceaPdf)
                            Add-TourneeCompositionGeneratedDocCount
                            Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback `
                                -Detail ("{0}Generation document CEA... [OK]" -f ($tChildCore + '│   └── '))
                            Write-Host ("[STEP5-METIER] Document CEA injecte apres page reorder #{0} (RawPage={1}, fichier={2})." -f $pn, $rawPnPage, (Split-Path -Leaf $ceaPdf)) -ForegroundColor Green
                        }
                        else {
                            [void]$ceaInjectedForPage.Remove($rawPnPage)
                            Write-Warning ("[CEA-POINTS] Generation CEA echouee pour RawPage={0} — page non injectee." -f $rawPnPage)
                        }
                    }

                    if (-not $isDupTarget -and $requiresFtPage -and $rawPnPage -gt 0 -and $ftInjectedForPage.Add($rawPnPage)) {
                        Write-CnsStep5ConsoleProgress -Message '[PROGRESS]       -> Generation document FT...' -ForegroundColor Gray
                        $okFt = Invoke-CnsAppendFtDocumentToFrag -Frag $frag -TmpDir $tmpDir `
                            -BlockIndex $fi -SliceIndex $sliceIx -ReorderPage $pn -RawPageNum $rawPnPage `
                            -PointCollecteLabel $ftPointLabel -WorkOrderEntity $woPage -PageEntity $pePage -GsPair $gsPair `
                            -FinalOrderToLine $foToLine -Segments @($segments) -OrderToSeg $orderToSeg -VisitDate $VisitDate `
                            -ProgressCallback $ProgressCallback -TChildCore $tChildCore
                        if (-not $okFt) {
                            [void]$ftInjectedForPage.Remove($rawPnPage)
                        }
                    }
                }
            }

            if (($null -ne $dupPendingCert) -or ($dupPendingCea.Count -gt 0) -or ($dupPendingFt.Count -gt 0)) {
                Invoke-CnsFlushOdmDuplicationRun -Frag $frag -SlicePaths $emptyDupSliceList `
                    -PendingCert $dupPendingCert -PendingCea $dupPendingCea -PendingFt $dupPendingFt `
                    -RunKeyLabel $(if ([string]::IsNullOrWhiteSpace($dupRunKey)) { 'client cible' } else { $dupRunKey }) `
                    -TmpDir $tmpDir -CertInjectedForWo $certInjectedForWo -CeaInjectedForPage $ceaInjectedForPage -FtInjectedForPage $ftInjectedForPage `
                    -ProgressCallback $ProgressCallback -TChildCore $tChildCore `
                    -FinalOrderToLine $foToLine -Segments @($segments) -OrderToSeg $orderToSeg -VisitDate $VisitDate
                $dupRunKey = $null
                $dupPendingCert = $null
            }

            if ([string]$blk.GroupKey -match '^SEG(\d+)$') {
                $segNumBilan = [int]$Matches[1]
                if (-not $bilanInjectedForSeg.ContainsKey($segNumBilan)) {
                    $bilanInjectedForSeg[$segNumBilan] = $true
                    if (Get-Command New-CnsBilanCollectePdfFromExcelTemplate -ErrorAction SilentlyContinue) {
                        Write-PlanningTourneeStep5UiLog ("📊 Tournée {0}/{1} - Génération bilan collecte..." -f $tourneeIndex, $totalTournees)
                        $segBilan = ($segments | Where-Object { [int]$_.SegmentIndex -eq $segNumBilan } | Select-Object -First 1)
                        $phBilan = @{}
                        foreach ($entry in (Get-CnsBilanCollectePlaceholders -SegmentMeta $segBilan -VisitDate $VisitDate).GetEnumerator()) {
                            $phBilan[[string]$entry.Key] = [string]$entry.Value
                        }
                        $bilanOut = Join-Path $tmpDir ('bilan_seg_{0:D3}.pdf' -f $fi)
                        Write-CnsStep5ConsoleProgress -Message '[PROGRESS]       -> Generation bilan collecte...' -ForegroundColor Gray
                        $bilanPdf = New-CnsBilanCollectePdfFromExcelTemplate -OutPdfPath $bilanOut -Placeholders $phBilan
                        if (-not [string]::IsNullOrWhiteSpace($bilanPdf) -and (Test-Path -LiteralPath $bilanPdf)) {
                            if (Get-Command Write-CnsLibreOfficePdfMergeAudit -ErrorAction SilentlyContinue) {
                                Write-CnsLibreOfficePdfMergeAudit -Phase 'GENERATED' -PdfPath $bilanPdf -DocumentKind 'BILAN-COLLECTE'
                            }
                            [void]$frag.Add($bilanPdf)
                            Add-TourneeCompositionGeneratedDocCount
                            Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback `
                                -Detail ("{0}Generation bilan collecte... [OK]" -f ($tChildCore + '└── '))
                            Write-Host ("[STEP5-METIER] Bilan de collecte dynamique injecte en fin de tournée segment {0} (fichier={1})." -f $segNumBilan, (Split-Path -Leaf $bilanPdf)) -ForegroundColor Green
                        }
                        else {
                            Write-Warning ("[BILAN-COLLECTE] Generation bilan echouee pour segment {0} — page non injectee." -f $segNumBilan)
                        }
                    }
                    else {
                        Write-Warning '[BILAN-COLLECTE] Module Word bilan non charge — injection ignoree.'
                    }
                }
            }
            Update-PlanningTourneeStep5Progress -SubRatio $tourRatioEnd `
                -Detail ("Tournée {0}/{1} - Terminee" -f $tourneeIndex, $totalTournees)
            Write-PlanningTourneeStep5UiLog ("✅ Tournée {0}/{1} - Terminée" -f $tourneeIndex, $totalTournees)
            Write-TourneeCompositionTourEnd -ProgressCallback $ProgressCallback
        }

        $totalFragments = @($frag).Count
        Write-PlanningTourneeStep5UiLog ("🔗 Fusion des {0} documents..." -f $totalFragments)
        Update-PlanningTourneeStep5Progress -SubRatio 0.95 -Detail 'Fusion finale des documents...'
        Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback -SubRatio 0.95 -Detail 'Phase 3 : Assemblage final'
        Write-CnsStep5ConsoleProgress -Message '[PROGRESS]   - Fusion des documents...' -ForegroundColor Gray
        $fragCount = @($frag).Count
        $mergeMsg = "Fusion des {0} elements PDF... [OK]" -f $fragCount
        if ([string]::IsNullOrWhiteSpace($mergeMsg)) { $mergeMsg = 'Operation en cours' }
        $outFinal = Join-Path $tmpDir 'composed_final.pdf'
        $merged = Merge-CnsPdfFilesForStep5TourneeComposition -InputPdfsOrdered @($frag.ToArray()) -DestinationPdfPath $outFinal
        if (-not $merged) {
            throw '[TOURNEE] Fusion Ghostscript (couvertures + corps) echouee.'
        }
        Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback -Detail ("├── {0}" -f $mergeMsg)
        Update-PlanningTourneeStep5Progress -SubRatio 1.0 -Status 'OK' -Detail 'Traitement termine'

        Copy-Item -LiteralPath $outFinal -Destination $mainAbs -Force
        Write-PlanningTourneeStep5UiLog '💾 Sauvegarde du PDF final...'
        $nCoverSheets = 1 + @($blocks).Count
        $tourneeMsg = "[TOURNEE] PDF final compose : {0} garde(s) + {1} page(s) corps reorder (Ghostscript reorder inchange)." -f $nCoverSheets, $mainPageCount
        script:Write-CnsTourneeLog -Message $tourneeMsg -Level 'INFO'
        Write-CnsStep5ConsoleProgress -Message '[PROGRESS] STEP 5 : Termine !' -ForegroundColor Green
        Write-CnsStep5ConsoleProgress -Message ("[PROGRESS] PDF final : {0}" -f $mainAbs) -ForegroundColor Cyan
        $step5CompositionMs = $step5CompositionSw.ElapsedMilliseconds
        script:Write-CnsTourneeLog -Message ("[TOURNEE] Perf step5 : {0}ms | gs_batch={1} gs_page={2} cea_step1={3} cea_pdftotext={4}" -f `
            $step5CompositionMs, $script:PlanningStep5Perf.GsBatchExtracts, $script:PlanningStep5Perf.GsPageExtracts, `
            $script:PlanningStep5Perf.CeaFromStep1, $script:PlanningStep5Perf.CeaPdftotextFallback) -Level 'INFO'
        if (Get-Command Write-PlanningRebuildUiLog -ErrorAction SilentlyContinue) {
            Write-PlanningRebuildUiLog $tourneeMsg
        }
        return $true
    }
    catch {
        $errDetail = $_.Exception.Message
        try {
            if ($null -ne $_.ScriptStackTrace) {
                $errDetail = '{0} | {1}' -f $errDetail, ($_.ScriptStackTrace -replace '\r?\n', ' ')
            }
        }
        catch { }
        script:Write-CnsTourneeLog -Message ("[TOURNEE] Composition abandonnee : {0}" -f $errDetail) -Level 'ERROR'
        Write-Warning ("[TOURNEE] Composition abandonnee : {0}" -f $_.Exception.Message)
        return $false
    }
    finally {
        if ([string]::IsNullOrWhiteSpace($tmpDir) -eq $false -and (Test-Path -LiteralPath $tmpDir)) {
            Write-PlanningTourneeStep5UiLog '🧹 Nettoyage des fichiers temporaires...'
            Write-TourneeCompositionTourProgress -ProgressCallback $ProgressCallback `
                -Detail '└── Nettoyage des fichiers temporaires... [OK]'
            Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
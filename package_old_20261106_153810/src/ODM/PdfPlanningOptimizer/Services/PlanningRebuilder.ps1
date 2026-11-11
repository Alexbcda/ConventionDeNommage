. (Join-Path $PSScriptRoot '..\Extractors\PdfExtractor.ps1')
. (Join-Path $PSScriptRoot '..\Extractors\EntityExtractor.ps1')
. (Join-Path $PSScriptRoot '..\Extractors\ExcelLoader.ps1')
. (Join-Path $PSScriptRoot 'PageEntityAggregator.ps1')
$_qualityMonitor = Join-Path $PSScriptRoot '..\Monitoring\QualityMonitor.ps1'
if (Test-Path -LiteralPath $_qualityMonitor) {
    . $_qualityMonitor
}
$_rootCauseEngine = Join-Path $PSScriptRoot '..\Monitoring\RootCauseEngine.ps1'
if (Test-Path -LiteralPath $_rootCauseEngine) {
    . $_rootCauseEngine
}

$_scalarGuard = Join-Path $PSScriptRoot '..\..\..\Common\ScalarGuard.ps1'
if (Test-Path -LiteralPath $_scalarGuard) {
    . $_scalarGuard
}
$_sortSafe = Join-Path $PSScriptRoot '..\..\..\Common\SortSafe.ps1'
if (Test-Path -LiteralPath $_sortSafe) {
    . $_sortSafe
}
$_planningLogger = Join-Path $PSScriptRoot '..\..\..\Core\Logger.ps1'
$_pdfReorganizer  = Join-Path $PSScriptRoot '..\..\..\Core\PDFReorganizer.ps1'
if (Test-Path -LiteralPath $_pdfReorganizer) {
    . $_pdfReorganizer
}
$_tourneeCovers = Join-Path $PSScriptRoot 'PdfTourneeCoverComposer.ps1'
if (Test-Path -LiteralPath $_tourneeCovers) {
    . $_tourneeCovers
}
$_step5Prereq = Join-Path $PSScriptRoot 'PlanningStep5Prerequisites.ps1'
if (Test-Path -LiteralPath $_step5Prereq) {
    . $_step5Prereq
}
if (Test-Path -LiteralPath $_planningLogger) {
    . $_planningLogger
}

$_planningDatabase = Join-Path $PSScriptRoot '..\..\..\Database\Database.ps1'
if (Test-Path -LiteralPath $_planningDatabase) {
    . $_planningDatabase
}

function script:Write-PlanningDebugLog {
    param(
        [string]$Message,
        [string]$Level = 'DEBUG',
        $Data = $null
    )
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log ("[PlanningRebuilder] " + $Message) $Level $Data
    }
}

# Journalisation pipeline (hors boucles) : STEP / ERROR / SUCCESS uniquement — pas d'appel dans les boucles matching/ODM.
function script:Write-PlanningJobProgressFile {
    param([Parameter(Mandatory = $true)][string]$Message)
    $pf = $env:CN_PLANNING_JOB_PROGRESS_FILE
    if ([string]::IsNullOrWhiteSpace($pf)) { return }
    try {
        $line = '{0} - {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
        Add-Content -LiteralPath $pf -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    catch { }
}

function script:Write-PlanningLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Level = 'INFO'
    )
    if ($Level -eq 'INFO') {
        script:Write-PlanningJobProgressFile -Message $Message
    }
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log $Message $Level
    }
}

function Write-PlanningPipelineStepTiming {
    param(
        [Parameter(Mandatory = $true)][int]$StepIndex,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][long]$DurationMs,
        [string]$Detail = $null
    )
    $sec = [math]::Round($DurationMs / 1000.0, 1)
    $detailSuffix = if ([string]::IsNullOrWhiteSpace($Detail)) { '' } else { " — $Detail" }
    script:Write-PlanningLog -Message ("[PIPELINE] TIMING step{0}={1}ms ({2}s){3} — {4}" -f $StepIndex, $DurationMs, $sec, $detailSuffix, $Label) -Level 'INFO'
}

function Write-PlanningPipelineTimingSummary {
    param(
        [Parameter(Mandatory = $true)][long]$TotalMs,
        [hashtable]$StepMs,
        [string]$Step5Detail = $null
    )
    $sec = [math]::Round($TotalMs / 1000.0, 1)
    $s1 = if ($StepMs.ContainsKey(1)) { [long]$StepMs[1] } else { 0 }
    $s2 = if ($StepMs.ContainsKey(2)) { [long]$StepMs[2] } else { 0 }
    $s3 = if ($StepMs.ContainsKey(3)) { [long]$StepMs[3] } else { 0 }
    $s4 = if ($StepMs.ContainsKey(4)) { [long]$StepMs[4] } else { 0 }
    $s5 = if ($StepMs.ContainsKey(5)) { [long]$StepMs[5] } else { 0 }
    $extra = if ([string]::IsNullOrWhiteSpace($Step5Detail)) { '' } else { " | $Step5Detail" }
    script:Write-PlanningLog -Message ("[PIPELINE] TIMING total={0}ms ({1}s) | step1={2} step2={3} step3={4} step4={5} step5={6}{7}" -f $TotalMs, $sec, $s1, $s2, $s3, $s4, $s5, $extra) -Level 'INFO'
}

# $env:CN_CHIRURGICAL_TRACE=1 : UNE seule trace [CHIRURGICAL-LEAK] par run — 1ʳᵉ appearance réelle de System.Object[] (pas de throw; pipeline continue)
# Réinitialisé en entrée de Start-PlanningRebuild
$script:ChirurgicalLeakLogged = $false
$script:ObjectArrayLeakLogged = $false
$script:SortExprLeakLogged = $false
$script:SortPropLeakLogged = $false
$script:ArithLeakLogged = $false
$script:TypeLeakLogged = $false
$script:DeepLeakLogged = $false
$script:ArithHardLeakLogged = $false

function script:Test-CnChirurgicalTrace {
    return ($env:CN_CHIRURGICAL_TRACE -in @('1', 'true'))
}

function script:Test-CnObjectTrace {
    return ($env:CN_OBJECT_TRACE -in @('1', 'true'))
}

function Trace-TypeLeak {
    param(
        $Value,
        [string]$Name,
        [string]$Location
    )
    if (-not (script:Test-CnObjectTrace)) { return $Value }
    if ($script:TypeLeakLogged) { return $Value }
    if ($Value -is [System.Object[]]) {
        $script:TypeLeakLogged = $true
        $count = [int]@($Value).Count
        $first = if ($count -gt 0) { $Value[0] } else { $null }
        $stack = (Get-PSCallStack | Select-Object -First 20 | Out-String)
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log ("[TYPE-LEAK] Name={0} Location={1} Type={2} Count={3} First={4} Stack={5}" -f $Name, $Location, $Value.GetType().FullName, $count, $first, $stack) "ERROR" $null
        }
    }
    return $Value
}

function Trace-DeepObjectLeak {
    param($Value, $Name, $Location)
    if ($env:CN_DEEP_OBJECT_TRACE -notin @('1', 'true')) { return }
    if ($script:DeepLeakLogged) { return }
    if ($Value -is [System.Object[]]) {
        $script:DeepLeakLogged = $true
        $count = [int]@($Value).Count
        $first = if ($count -gt 0) { $Value[0] } else { $null }
        Write-Log "[DEEP-OBJECT-LEAK]" "ERROR" @{
            Name = $Name
            Location = $Location
            Type = $Value.GetType().FullName
            Count = $count
            First = $first
            Stack = (Get-PSCallStack | Select-Object -First 25 | Out-String)
        }
    }
}

function Trace-ArithmeticLeak {
    param(
        $Left,
        $Right,
        [string]$Operation,
        [string]$Location
    )

    if ($env:CN_ARITH_TRACE -notin @('1', 'true')) { return }
    if ($script:ArithLeakLogged) { return }

    if ($Left -is [System.Object[]] -or $Right -is [System.Object[]]) {
        $script:ArithLeakLogged = $true

        $leftType = if ($null -eq $Left) { $null } else { $Left.GetType().FullName }
        $rightType = if ($null -eq $Right) { $null } else { $Right.GetType().FullName }
        $leftCount = if ($Left -is [array]) { $Left.Count } else { $null }
        $rightCount = if ($Right -is [array]) { $Right.Count } else { $null }
        $leftFirst = if ($Left -is [array] -and $Left.Count -gt 0) { $Left[0] } else { $Left }
        $rightFirst = if ($Right -is [array] -and $Right.Count -gt 0) { $Right[0] } else { $Right }
        $stack = (Get-PSCallStack | Select-Object -First 15 | Out-String)

        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log "[ARITH-LEAK] $Operation @ $Location" "ERROR" @{
                LeftType   = $leftType
                RightType  = $rightType
                LeftCount  = $leftCount
                RightCount = $rightCount
                LeftFirst  = $leftFirst
                RightFirst = $rightFirst
                Stack      = $stack
            }
        } else {
            Write-Error ("[ARITH-LEAK] {0} @ {1} | LT={2} RT={3}" -f $Operation, $Location, $leftType, $rightType)
        }
    }
}

function script:Trace-ArithHardLeak {
    param(
        $Left,
        $Right,
        [string]$Op,
        [string]$Location
    )
    if ($env:CN_ARITH_HARD_TRACE -notin @('1', 'true')) { return }
    if ($script:ArithHardLeakLogged) { return }
    if ($Left -is [System.Object[]] -or $Right -is [System.Object[]]) {
        $script:ArithHardLeakLogged = $true
        $leftType = if ($null -eq $Left) { $null } else { $Left.GetType().FullName }
        $rightType = if ($null -eq $Right) { $null } else { $Right.GetType().FullName }
        $leftCount = if ($Left -is [array]) { $Left.Count } else { $null }
        $rightCount = if ($Right -is [array]) { $Right.Count } else { $null }
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log "[ARITH-HARD-LEAK]" "ERROR" @{
                Op = $Op
                Location = $Location
                LeftType = $leftType
                RightType = $rightType
                LeftCount = $leftCount
                RightCount = $rightCount
                Stack = (Get-PSCallStack | Select-Object -First 30 | Out-String)
            }
        }
    }
}

function script:Trace-CastHardLeak {
    param(
        $Value,
        [string]$CastType,
        [string]$Location
    )
    if ($env:CN_ARITH_HARD_TRACE -notin @('1', 'true')) { return }
    if ($script:ArithHardLeakLogged) { return }
    if ($Value -is [System.Object[]]) {
        $script:ArithHardLeakLogged = $true
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log "[ARITH-HARD-LEAK]" "ERROR" @{
                Op = "cast:$CastType"
                Location = $Location
                LeftType = $Value.GetType().FullName
                RightType = $null
                LeftCount = $Value.Count
                RightCount = $null
                Stack = (Get-PSCallStack | Select-Object -First 30 | Out-String)
            }
        }
    }
}

function Invoke-SafeOp {
    param($Left, $Right, $Op, $Location)

    if ($env:CN_RUNTIME_OP_TRACE -in @('1', 'true')) {
        if ($Left -is [System.Object[]] -or $Right -is [System.Object[]]) {
            $leftType = if ($null -eq $Left) { $null } else { $Left.GetType().FullName }
            $rightType = if ($null -eq $Right) { $null } else { $Right.GetType().FullName }
            $leftCount = if ($Left -is [array]) { $Left.Count } else { $null }
            $rightCount = if ($Right -is [array]) { $Right.Count } else { $null }
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log "[RUNTIME-OP-LEAK]" "ERROR" @{
                    Op = $Op
                    Location = $Location
                    LeftType = $leftType
                    RightType = $rightType
                    LeftCount = $leftCount
                    RightCount = $rightCount
                    Stack = (Get-PSCallStack | Select-Object -First 30 | Out-String)
                }
            }
        }
    }

    switch ($Op) {
        "sub" { return ($Left - $Right) }
        "add" { return ($Left + $Right) }
        "mul" { return ($Left * $Right) }
        "div" { return ($Left / $Right) }
    }
}

function script:Trace-SortExprLeak {
    param(
        $Value,
        [string]$Name,
        [string]$Location
    )
    if (-not (script:Test-CnObjectTrace)) { return $Value }
    if ($script:SortExprLeakLogged) { return $Value }
    if ($Value -is [System.Object[]]) {
        $script:SortExprLeakLogged = $true
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log ("[SORT-EXPR-LEAK] " + $Name) "ERROR" @{
                Name = $Name
                Location = $Location
                Type = $Value.GetType().FullName
                Count = $Value.Count
                First = $(if ($Value.Count -gt 0) { $Value[0] } else { $null })
                Stack = (Get-PSCallStack | Select-Object -First 10 | Out-String)
            }
        }
    }
    return $Value
}

function script:Trace-SortPropLeak {
    param(
        $Value,
        [string]$Name
    )
    if (-not (script:Test-CnObjectTrace)) { return $Value }
    if ($script:SortPropLeakLogged) { return $Value }
    if ($Value -is [System.Object[]]) {
        $script:SortPropLeakLogged = $true
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log ("[SORT-PROP-LEAK] " + $Name) "ERROR" @{
                Type = $Value.GetType().FullName
                Count = $Value.Count
                First = $(if ($Value.Count -gt 0) { $Value[0] } else { $null })
                Stack = (Get-PSCallStack | Select-Object -First 10 | Out-String)
            }
        }
    }
    return $Value
}

function Trace-ObjectArrayLeak {
    param(
        $Value,
        [string]$Name,
        [string]$Location
    )

    if (-not (script:Test-CnObjectTrace)) { return $Value }
    if ($script:ObjectArrayLeakLogged) { return $Value }
    if ($Value -is [System.Object[]]) {
        $script:ObjectArrayLeakLogged = $true
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log "[OBJECT-ARRAY-LEAK]" "ERROR" @{
                Name = $Name
                Location = $Location
                Type = $Value.GetType().FullName
                Count = $Value.Count
                First = $(if ($Value.Count -gt 0) { $Value[0] } else { $null })
                Stack = (Get-PSCallStack | Select-Object -First 15 | Out-String)
            }
        }
    }

    return $Value
}

function script:Trace-ChirurgicalType {
    [OutputType([bool])]
    param(
        $Value,
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [string] $Location
    )
    if (-not (script:Test-CnChirurgicalTrace)) { return $false }
    if ($null -eq $Value) { return $false }
    if (-not ($Value -is [System.Object[]])) { return $false }
    if ($true -eq $script:ChirurgicalLeakLogged) { return $false }
    $script:ChirurgicalLeakLogged = $true
    $stackStr = (Get-PSCallStack | Select-Object -First 25 | ForEach-Object { $_.ToString() }) -join ' | '
    $first = $null
    try { if (0 -lt [int]@($Value).Count) { $first = $Value[0] } } catch { $first = 'n/a' }
    $data = @{
        Name     = $Name
        Location = $Location
        Type     = $Value.GetType().FullName
        Count    = [int]@($Value).Count
        First    = $first
        Stack    = $stackStr
    }
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log "[CHIRURGICAL-LEAK] premiere mutation System.Object[] (trace unique / run)" "ERROR" $data
    } else {
        Write-Error ("[CHIRURGICAL-LEAK] {0} @ {1} : {2}" -f $Name, $Location, (ConvertTo-Json $data -Depth 5 -Compress))
    }
    return $true
}

function script:Test-CnPipelineDebug {
    return ($env:CN_DEBUG_PIPELINE -in @('1', 'true'))
}

function script:Test-CnPlanningFlowLog {
    return ($env:CN_DEBUG_PLANNING_FLOW -in @('1', 'true'))
}

function script:Test-CnExcelExtractionDebug {
    return ($env:CN_DEBUG_EXCEL_EXTRACTION -in @('1', 'true') -or $env:CN_DEBUG_PLANNING -in @('1', 'true'))
}

function script:Write-PlanningFlowLog {
    param(
        [string]$Message,
        $Data = $null
    )
    $m = "[FLOW] " + $Message
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log $m "INFO" $Data
    } else {
        Write-Host $m
    }
    if (Test-CnPlanningFlowLog) {
        if ($null -ne $Data) {
            try { Write-Host ("[FLOW][DEBUG] " + (ConvertTo-Json $Data -Compress -Depth 4)) } catch { }
        }
    }
}

# Anti reentrance (UI double clic, rappels concurrents) — un seul pipeline actif
$script:PlanningPipelineRunning = $false
$script:PlanningRebuildLastError = $null
$script:PlanningStopRequested = $false

function Reset-PlanningRebuildStop {
    $script:PlanningStopRequested = $false
}

function Request-PlanningRebuildStop {
    $script:PlanningStopRequested = $true
}

function Test-PlanningRebuildStopRequested {
    if ($true -eq $script:PlanningStopRequested) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log 'Traitement annule par l''utilisateur' 'WARN'
        }
        return $true
    }
    return $false
}

# CN_PLANNING_ARITH_DEBUG=1 : log DEBUG avant chaque opération d’arithmetic probe (types des opérandes)
# Détection System.Object[] (ou tableau non scalaire) vers opérateur binaire - / + : log ERROR + stack 30
# ne modifie pas ScalarGuard (appels uniquement)
function script:Test-PlanningArithDebug {
    return ($env:CN_PLANNING_ARITH_DEBUG -in @('1', 'true'))
}

function script:Test-IsLeakyValueForArith {
    param($V)
    if ($null -eq $V) { return $false }
    if ($V -is [string]) { return $false }
    try {
        if ($V.GetType().IsValueType) { return $false }
    } catch { }
    if ($V -is [Object[]]) { return $true }
    return $false
}

function script:Get-ProbeSummary {
    param($V)
    if ($null -eq $V) { return 'null' }
    $t = $V.GetType().FullName
    if ($V -is [Object[]] -or $V -is [Array]) {
        $c = [int]@($V).Count
        $f = if ($c -gt 0) { try { [string]($V[0]) } catch { $V[0].GetType().Name } } else { 'n/a' }
        return "type=$t Count=$c First=$f"
    }
    $vs = '?'
    try { $vs = [string]$V } catch { $vs = '?' }
    return "type=$t ValueToString=$vs"
}

function script:Write-PlanningArithOpProbe {
    <#
    .SYNOPSIS
        Breakpoint logique : avant - + min/max / offset, détecte System.Object[] (tableaux) en opérande d’arithmetic.
    .NOTES
        Analyse statique (candidats op_Subtraction dans ce fichier) :
        - Get-LevenshteinDistance L829–L832 : $i-1, $j-1 — si $i ou $j jamais Object[] (boucle for int), risque nul
        - Find-ExcelColumnFromDate L779 : $m1L + $m2L — si ConvertTo-SafeLong retourne mal (hors module)
        - Start-PlanningRebuild : Get-SafeMin/Max, Safe-Subtract, $pNum + $pOff — si $pages ou PageNumber = Object[] avant normalisation
        - Build-PlanningCalendarIndex L600-601 : ($c+1) — $c for-int, fuite rare
        - Origine type « premier Object[] » souvent : propriété d’objet (SQLite/Excel) = colonne lue 2+ valeurs, ou DTO non aplati
        - Correction 1 ligne typique (sans toucher ScalarGuard.ps1 / Database) : appliquer Normalize-Scalar sur la propriété fautive au moment de l’assignation PlanningRebuilder (ex. ColumnIndex / header_row depuis $rowOut).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Location,
        [Parameter(Mandatory = $true)]
        [string] $Operation,
        $Left = $null,
        $Right = $null
    )
    $leakL = (script:Test-IsLeakyValueForArith -V $Left)
    $leakR = (script:Test-IsLeakyValueForArith -V $Right)
    if ($leakL -or $leakR) {
        $stack = (Get-PSCallStack | Select-Object -First 30 | ForEach-Object { $_.ToString() }) -join ' | '
        $msg = "[PLANNING-ARITH-LEAK] op=$Operation loc=$Location | Left=$( & script:Get-ProbeSummary -V $Left) | Right=$( & script:Get-ProbeSummary -V $Right) | STACK: $stack"
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log $msg "ERROR" $null
        } else {
            Write-Error $msg
        }
    }
    if (Test-PlanningArithDebug) {
        $lN = if ($null -eq $Left) { 'null' } else { $Left.GetType().Name }
        $rN = if ($null -eq $Right) { 'n/a' } else { $Right.GetType().Name }
        script:Write-PlanningDebugLog -Message "ARITH-PROBE" -Level "DEBUG" -Data @{
            Loc = $Location; Op = $Operation; LeftT = $lN; RightT = $rN
        }
    }
}

# Garde : détection Object[] avant chemins d’arithmetic (Sort-Object, etc.). Throw si CN_PLANNING_SCALAR_ASSERT=1
function script:Assert-PlanningScalar {
    param($Value, [string]$Name = 'value')
    if ($null -eq $Value) { return }
    if ($Value -is [System.Object[]]) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log ("[TYPE-LEAK] name={0} type={1} count={2} first={3}`n{4}" -f $Name, $Value.GetType().FullName, $Value.Count, $(try { $Value[0] } catch { '?' }), (Get-PSCallStack | Out-String)) "ERROR" $null
        } else {
            Write-Host ("[TYPE-LEAK] $Name Object[] see console") -ForegroundColor Red; Get-PSCallStack | Out-Host
        }
        if ($env:CN_PLANNING_SCALAR_ASSERT -in @('1', 'true')) {
            throw "[SCALAR-FAIL] $Name is Object[]"
        }
    }
}

# Clé de tri int scalaire (évite op_Subtraction interne de Sort-Object sur clés non scalaires)
function script:Get-PlanningIntSortKey {
    param(
        $Object,
        [string]$PropertyName,
        [string]$Context = 'sort'
    )
    try {
        [void](Trace-ObjectArrayLeak -Value $Object.$PropertyName -Name $PropertyName -Location "Get-PlanningIntSortKey")
        if ($null -eq $Object) { return 0 }
        $v = $Object.$PropertyName
        if ($null -eq $v) { return 0 }
        script:Assert-PlanningScalar -Value $v -Name ($Context + '.' + $PropertyName)
        return (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $v -Name ($Context + '.' + $PropertyName)) -Name ($Context + '.' + $PropertyName + '.int'))
    }
    catch {
        Write-Log "[PLANNING-INNER-FAIL]" "ERROR" @{
            Context  = "Key"
            Message  = $_.Exception.Message
            Stack    = $_.ScriptStackTrace
            Position = $_.InvocationInfo.PositionMessage
        }
        throw
    }
}

function script:Write-PlanningRebuildPdfDebug {
    param(
        $PageMapping = $null,
        [object[]]$Reordered = $null
    )
    Write-Host "[PDF][DEBUG] --- Anomalie : ordre + mapping (ne pas ignorer) ---" -ForegroundColor DarkYellow
    if ($null -ne $Reordered) {
        $Reordered | Format-Table -AutoSize PageNumber, FinalOrder, ClientName, MatchScore
    }
    if ($null -ne $PageMapping -and $PageMapping -is [hashtable] -and $PageMapping.Count -gt 0) {
        try {
            $keyList = @(
                $PageMapping.Keys |
                    ForEach-Object {
                        $val = [int]$_
                        [void](script:Trace-SortExprLeak -Value $val -Name "PageMapping.Key" -Location "Write-PlanningRebuildPdfDebug.Sort")
                        $val
                    } |
                    Sort-Object
            )
        }
        catch {
            Write-Log "[PLANNING-INNER-FAIL]" "ERROR" @{
                Context  = "Sort"
                Message  = $_.Exception.Message
                Stack    = $_.ScriptStackTrace
                Position = $_.InvocationInfo.PositionMessage
            }
            throw
        }
        $parts = @(
            foreach ($k in $keyList) {
                $v = $PageMapping[$k]
                if ($v) { "p{0}=T{1}R{2}" -f $k, $v.Tournee, $v.Rang } else { "p$k=?" }
            }
        )
        Write-Host ("[PDF][DEBUG] " + ($parts -join ' | ')) -ForegroundColor DarkYellow
    }
    else {
        Write-Host "[PDF][DEBUG] (aucune entrée de mapping exploitable)" -ForegroundColor DarkYellow
    }
}

function Normalize-Date {
    <#
    .SYNOPSIS
        Normalise une date (string ou datetime) vers yyyy-MM-dd (date civile).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputValue
    )

    $raw = $null
    if ($null -eq $InputValue) { return $null }
    $debugDate = ($env:CN_DEBUG_DATE -in @('1', 'true'))
    if ($InputValue -is [datetime]) {
        $dt = [datetime]$InputValue
        $out = $dt.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        Write-PlanningDebugLog -Message "Date normalized" -Level "DEBUG" -Data @{ Input = $InputValue.ToString('o'); Output = $out }
        return $out
    }

    $raw = ([string]$InputValue).Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

    $cultures = @(
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.CultureInfo]::GetCultureInfo('en-US'),
        [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    )

    foreach ($c in $cultures) {
        try {
            $dt = [datetime]::Parse($raw, $c, [System.Globalization.DateTimeStyles]::AllowWhiteSpaces)
            $out = $dt.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
            Write-PlanningDebugLog -Message "Date normalized" -Level "DEBUG" -Data @{ Input = $raw; Output = $out; Culture = $c.Name }
            return $out
        }
        catch { }
    }

    $m = [regex]::Match($raw, '(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)')
    if ($m.Success) {
        try {
            $dt = [datetime]::new([int]$m.Groups[1].Value, [int]$m.Groups[2].Value, [int]$m.Groups[3].Value)
            $out = $dt.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
            Write-PlanningDebugLog -Message "Date normalized" -Level "DEBUG" -Data @{ Input = $raw; Output = $out; Rule = 'ISO-regex' }
            return $out
        }
        catch { }
    }

    $m2 = [regex]::Match($raw, '(?<!\d)(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})(?!\d)')
    if ($m2.Success) {
        $a = [int]$m2.Groups[1].Value
        $b = [int]$m2.Groups[2].Value
        $yRaw = [int]$m2.Groups[3].Value
        $yy = $yRaw
        if ($yy -lt 100) { $yy += 2000 }

        $candidates = [System.Collections.Generic.List[hashtable]]::new()
        if ($a -gt 12 -and $b -le 12) {
            [void]$candidates.Add(@{ dd = $a; mm = $b; yy = $yy; Rule = 'dd/MM/yyyy (a>12)' })
        }
        elseif ($b -gt 12 -and $a -le 12) {
            [void]$candidates.Add(@{ dd = $b; mm = $a; yy = $yy; Rule = 'MM/dd/yyyy (b>12)' })
        }
        else {
            [void]$candidates.Add(@{ dd = $a; mm = $b; yy = $yy; Rule = 'dd/MM/yyyy-first' })
            [void]$candidates.Add(@{ dd = $b; mm = $a; yy = $yy; Rule = 'MM/dd/yyyy-first' })
        }

        foreach ($cand in $candidates) {
            try {
                $dt = [datetime]::new($cand.yy, $cand.mm, $cand.dd)
                $out = $dt.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
                Write-PlanningDebugLog -Message "Date normalized" -Level "DEBUG" -Data @{ Input = $raw; Output = $out; Rule = $cand.Rule }
                return $out
            }
            catch { }
        }
    }

    if ($debugDate) {
        Write-PlanningDebugLog -Message "Date normalized" -Level "DEBUG" -Data @{ Input = $raw; Output = $null; Rule = 'FAILED' }
    }
    return $null
}

function script:Test-IsLikelyDate {
    param($Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [datetime]) { return $true }
    $raw = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) { return $false }

    # ISO date / datetime
    if ($raw -match '^\d{4}-\d{2}-\d{2}(?:[Tt ]\d{2}:\d{2}(?::\d{2})?)?$') { return $true }
    # dd/MM/yyyy ou dd-MM-yyyy (année 2 ou 4 chiffres)
    if ($raw -match '^\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}$') { return $true }
    # dd/MM ou dd-MM (souvent en en-têtes planning)
    if ($raw -match '^\d{1,2}[\/\-]\d{1,2}$') { return $true }

    # Evite les chaînes métier non-date (nombres isolés, adresses sans séparateurs date)
    if ($raw -notmatch '[\/\-Tt]') { return $false }
    if ($raw -match '^\d+$') { return $false }

    $tmp = [datetime]::MinValue
    return [datetime]::TryParse(
        $raw,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AllowWhiteSpaces,
        [ref]$tmp
    )
}

function script:Get-NormalizedDateCached {
    param(
        $Value,
        [hashtable]$Cache
    )

    if ($null -eq $Cache) {
        if ($Value -is [datetime]) { return (Normalize-Date -InputValue $Value) }
        if (-not (Test-IsLikelyDate -Value $Value)) { return $null }
        return (Normalize-Date -InputValue $Value)
    }

    $key = if ($null -eq $Value) {
        '__NULL__'
    }
    elseif ($Value -is [datetime]) {
        'DT:' + ([datetime]$Value).ToString('o')
    }
    else {
        'S:' + ([string]$Value).Trim()
    }

    if ($Cache.ContainsKey($key)) {
        return $Cache[$key]
    }

    $norm = $null
    if ($Value -is [datetime]) {
        $norm = Normalize-Date -InputValue $Value
    }
    elseif (Test-IsLikelyDate -Value $Value) {
        $norm = Normalize-Date -InputValue $Value
    }
    $Cache[$key] = $norm
    return $norm
}

function script:Normalize-PlanningText {
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }
    $norm = $s.ToLowerInvariant().Trim()
    $norm = [regex]::Replace($norm, '\s+', ' ')
    return $norm
}

function script:Remove-Diacritics {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $normalized.ToCharArray()) {
        $cat = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($cat -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString().Normalize([Text.NormalizationForm]::FormC)
}

function Normalize-ClientKey {
    [CmdletBinding()]
    param($entity)

    $raw = ''
    if ($entity -is [string]) {
        $raw = [string]$entity
    }
    elseif ($null -ne $entity) {
        $parts = @(
            [string]$entity.ClientID
            [string]$entity.ClientName
            [string](Get-EntityAddressText -Entity $entity)
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $raw = ($parts -join ' ')
    }

    $k = Remove-Diacritics -Text $raw
    $k = $k.ToUpperInvariant()
    $k = [regex]::Replace($k, '\b(DE|DU|LA|LE|ET)\b', ' ')
    $k = [regex]::Replace($k, '[^A-Z0-9\s]', ' ')
    $k = [regex]::Replace($k, '\s+', '')
    return $k
}

function script:Get-EntityAddressText {
    param([object]$Entity)
    if ($null -eq $Entity) { return '' }
    if ($Entity.Address -is [hashtable]) {
        $parts = @($Entity.Address.Street, $Entity.Address.PostalCode, $Entity.Address.City) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        return ($parts -join ' ').Trim()
    }
    return ([string]$Entity.Address).Trim()
}

function script:Get-VisitDateFromEntities {
    param([object[]]$PdfEntities)
    foreach ($entity in @($PdfEntities)) {
        if ($null -eq $entity) { continue }
        if ($null -ne $entity.VisitDate) { return [datetime]$entity.VisitDate }
        if ($null -ne $entity.Date) {
            try { return [datetime]$entity.Date } catch { }
        }
    }
    return $null
}

function script:Get-FrenchDayName {
    param([datetime]$Date)
    switch ($Date.DayOfWeek) {
        'Monday' { return 'Lundi' }
        'Tuesday' { return 'Mardi' }
        'Wednesday' { return 'Mercredi' }
        'Thursday' { return 'Jeudi' }
        'Friday' { return 'Vendredi' }
        'Saturday' { return 'Samedi' }
        'Sunday' { return 'Dimanche' }
        default { return '' }
    }
}

function script:Try-ParseDateFlexible {
    param(
        [string]$Text,
        [datetime]$VisitDate,
        [string]$TargetVisitNorm = $null,
        [hashtable]$DateNormCache = $null
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $t = Remove-Diacritics -Text $Text
    $t = $t.Trim()
    $day = Get-FrenchDayName -Date $VisitDate
    $targetNorm = if ([string]::IsNullOrWhiteSpace($TargetVisitNorm)) {
        Get-NormalizedDateCached -Value $VisitDate -Cache $DateNormCache
    }
    else {
        $TargetVisitNorm
    }

    $patterns = @(
        '(?i)\b' + [regex]::Escape($day) + '\s+(\d{1,2})[\/\-](\d{1,2})(?:[\/\-](\d{2,4}))?\b',
        '(?<!\d)(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})(?!\d)',
        '(?<!\d)(\d{1,2})[\/\-](\d{1,2})(?!\d)'
    )

    foreach ($pat in $patterns) {
        $m = [regex]::Match($t, $pat)
        if (-not $m.Success) { continue }
        $dd = [int]$m.Groups[1].Value
        $mm = [int]$m.Groups[2].Value
        $yy = $VisitDate.Year
        if ($m.Groups.Count -ge 4 -and $m.Groups[3].Success -and -not [string]::IsNullOrWhiteSpace($m.Groups[3].Value)) {
            $yy = [int]$m.Groups[3].Value
            if ($yy -lt 100) { $yy += 2000 }
        }
        try {
            $dt = [datetime]::new($yy, $mm, $dd)
            $norm = Get-NormalizedDateCached -Value $dt -Cache $DateNormCache
            if ($null -ne $norm -and $null -ne $targetNorm -and $norm -eq $targetNorm) {
                return $dt
            }
        }
        catch { }
    }

    if (-not (Test-IsLikelyDate -Value $t)) { return $null }
    $normAny = Get-NormalizedDateCached -Value $t -Cache $DateNormCache
    if ($null -ne $normAny -and $null -ne $targetNorm -and $normAny -eq $targetNorm) {
        try { return [datetime]::ParseExact($normAny, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) } catch { }
    }
    return $null
}

# Import-PlanningExcel : voir Extractors\ExcelLoader.ps1 (ImportExcel, sans Microsoft Excel installe)

function script:Test-CnCalendarIndexDebug {
    return ($env:CN_DEBUG_EXCEL_INDEX -in @('1', 'true'))
}

function script:Write-SqlitePlanningLog {
    param(
        [string]$Message,
        $Data = $null
    )
    $m = "[SQLite] " + $Message
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log $m "INFO" $Data
    } else {
        Write-Host $m
    }
}

function Get-PlanningCalendarFileId {
    <#
    .SYNOPSIS
        Identifiant stable pour calendar_index, dérivé de la clé d’import (chemin, mtime, forme des feuilles).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$IndexKey
    )
    $IndexKey = [string](Normalize-Scalar -Value $IndexKey -Name "Get-PlanningCalendarFileId.IndexKey")
    if ([string]::IsNullOrWhiteSpace($IndexKey)) { throw "Get-PlanningCalendarFileId: IndexKey requis" }
    $b = [System.Text.Encoding]::UTF8.GetBytes($IndexKey)
    $h = [System.Security.Cryptography.SHA256]::Create().ComputeHash($b)
    return -join (0..15 | ForEach-Object { "{0:x2}" -f $h[$_] })
}

function script:Get-Iso8601WeekOfYear {
    <#
    .SYNOPSIS
        Semaine ISO 8601 (algorithme recommandé par Microsoft / CultureInfo) pour n’importe quelle année.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$Date
    )
    $cal = [System.Globalization.CultureInfo]::InvariantCulture.Calendar
    $d = $Date.Date
    $day = $cal.GetDayOfWeek($d)
    if ($day -ge [DayOfWeek]::Monday -and $day -le [DayOfWeek]::Wednesday) {
        $d = $d.AddDays(3)
    }
    return $cal.GetWeekOfYear($d, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [DayOfWeek]::Monday)
}

function Get-WeekFromDate {
    <#
    .SYNOPSIS
        Clé de semaine style « S17 » (numéro de semaine ISO, 2 chiffres).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$Date
    )
    $w = Get-Iso8601WeekOfYear -Date $Date
    return 'S' + ('{0:00}' -f $w)
}

function script:Get-WeekKeyForPlanningIndex {
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$Date
    )
    $w = Get-Iso8601WeekOfYear -Date $Date
    return ('{0}S{1:00}' -f $Date.Year, $w)
}

function script:Get-PlanningCalendarIndexKey {
    param(
        [object]$ExcelData,
        [string]$ExcelPath
    )
    $p = $null
    if (-not [string]::IsNullOrWhiteSpace($ExcelPath)) {
        if (Test-Path -LiteralPath $ExcelPath) {
            $p = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ExcelPath)
        }
    }
    if ($null -eq $p -and $null -ne $ExcelData -and -not [string]::IsNullOrWhiteSpace($ExcelData.Path)) {
        $rp = $ExcelData.Path
        if (Test-Path -LiteralPath $rp) {
            $p = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($rp)
        }
    }
    if ($null -eq $p) { return $null }
    $lwt = 0L
    $fi = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
    if ($null -ne $fi) { $lwt = $fi.LastWriteTimeUtc.Ticks }
    $shape = @(
        foreach ($s in @($ExcelData.Sheets)) {
            ('{0}|{1}|{2}' -f $s.Name, [int]$s.RowCount, [int]$s.ColCount)
        }
    ) -join ';;'
    return ('{0}|{1}|{2}' -f $p, $lwt, $shape)
}

function script:Try-ExtractDateFromHeaderForIndex {
    <#
    .SYNOPSIS
        Extrait une date d’en-tête planning sans cible (PDF) — index une seule fois, année douteuse = ReferenceDate.Year
    #>
    param(
        [string]$Text,
        [datetime]$ReferenceDate,
        [hashtable]$DateNormCache
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $raw = $Text.Trim()
    if ($raw.Length -le 1) { return $null }
    if ($raw -in @('0', 'H', 'A', '-', '—')) { return $null }
    if (Test-IsLikelyDate $raw) {
        $n = Get-NormalizedDateCached -Value $raw -Cache $DateNormCache
        if ($null -ne $n) {
            try { return [datetime]::ParseExact($n, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) } catch { return $null }
        }
    }
    $t = Remove-Diacritics -Text $raw
    $t = $t.Trim()
    $refY = $ReferenceDate.Year
    $dayRx = [regex]'(?i)(?:lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)\s+(\d{1,2})[\/\-](\d{1,2})(?:[\/\-](\d{2,4}))?'
    $m0 = $dayRx.Match($t)
    if ($m0.Success) {
        $dd = [int]$m0.Groups[1].Value
        $mm = [int]$m0.Groups[2].Value
        $yy = $refY
        if ($m0.Groups[3].Success -and -not [string]::IsNullOrWhiteSpace($m0.Groups[3].Value)) {
            $yy = [int]$m0.Groups[3].Value
            if ($yy -lt 100) { $yy += 2000 }
        }
        try { return [datetime]::new($yy, $mm, $dd) } catch { }
    }
    $m1 = [regex]::Match($t, '(?<!\d)(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})(?!\d)')
    if ($m1.Success) {
        $a = [int]$m1.Groups[1].Value
        $b = [int]$m1.Groups[2].Value
        $yRaw = [int]$m1.Groups[3].Value
        $yy = $yRaw; if ($yy -lt 100) { $yy += 2000 }
        $cands = [System.Collections.Generic.List[hashtable]]::new()
        if ($a -gt 12 -and $b -le 12) { [void]$cands.Add(@{ dd = $a; mm = $b; yy = $yy }) }
        elseif ($b -gt 12 -and $a -le 12) { [void]$cands.Add(@{ dd = $b; mm = $a; yy = $yy }) }
        else {
            [void]$cands.Add(@{ dd = $a; mm = $b; yy = $yy })
            [void]$cands.Add(@{ dd = $b; mm = $a; yy = $yy })
        }
        foreach ($c in $cands) {
            try { return [datetime]::new($c.yy, $c.mm, $c.dd) } catch { }
        }
    }
    $m2 = [regex]::Match($t, '(?<!\d)(\d{1,2})[\/\-](\d{1,2})(?![\/\-\d])')
    if ($m2.Success) {
        $a = [int]$m2.Groups[1].Value
        $b = [int]$m2.Groups[2].Value
        if ($a -le 12 -and $b -le 12) {
            try { return [datetime]::new($refY, $a, $b) } catch { }
            try { return [datetime]::new($refY, $b, $a) } catch { }
        }
    }
    return $null
}

function Build-PlanningCalendarIndex {
    <#
    .SYNOPSIS
        Parcourt chaque feuille une seule fois (import Excel) et enregistre l’index dans SQLite (Data/gestion.db).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ExcelData,
        [Parameter(Mandatory = $true)]
        [datetime]$ReferenceDate,
        [Parameter(Mandatory = $true)]
        [string]$ExcelPath
    )
    if (-not (Get-Command Save-CalendarIndexForFile -ErrorAction SilentlyContinue)) {
        throw 'Build-PlanningCalendarIndex: module Database requis (Save-CalendarIndexForFile).'
    }
    $ExcelPath = [string](Normalize-Scalar -Value $ExcelPath -Name "Build-PlanningCalendarIndex.ExcelPath")
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $key = Get-PlanningCalendarIndexKey -ExcelData $ExcelData -ExcelPath $ExcelPath
    if ($null -eq $key) { throw 'Build-PlanningCalendarIndex: chemin Excel non résolu.' }
    $key = [string](Normalize-Scalar -Value $key -Name "Build.IndexKey")
    $fileId = Get-PlanningCalendarFileId -IndexKey $key
    $fileId = [string](Normalize-Scalar -Value $fileId -Name "Build.fileId")
    $dateCache = @{}
    $byWeek = @{}
    $byDate = @{}
    $totalCells = 0
    $parsedDates = 0
    $dupDate = 0
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    foreach ($sheet in @($ExcelData.Sheets)) {
        if (Get-Command Trace-IfArrayLeak -ErrorAction SilentlyContinue) {
            [void](Trace-IfArrayLeak -Value $sheet.RowCount -Label "Build-Index.RowCount")
            [void](Trace-IfArrayLeak -Value $sheet.ColCount -Label "Build-Index.ColCount")
        }
        $rowMax = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $sheet.RowCount -Name "index.sheet.RowCount") -Name "index.sheet.RowCount")
        $colMax = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $sheet.ColCount -Name "index.sheet.ColCount") -Name "index.sheet.ColCount")
        for ($r = 0; $r -lt $rowMax; $r++) {
            for ($c = 0; $c -lt $colMax; $c++) {
                if ($r -eq 0 -and $c -eq 0) {
                    script:Write-PlanningArithOpProbe -Location 'Build-PlanningCalendarIndex:cell-col' -Op 'add' -Left $c -Right 1
                    script:Write-PlanningArithOpProbe -Location 'Build-PlanningCalendarIndex:cell-row' -Op 'add' -Left $r -Right 1
                }
                $totalCells++
                $cell = [string]$sheet.Grid[$r][$c]
                if ([string]::IsNullOrWhiteSpace($cell)) { continue }
                $dtCell = script:Try-ExtractDateFromHeaderForIndex -Text $cell -ReferenceDate $ReferenceDate -DateNormCache $dateCache
                if ($null -eq $dtCell) { continue }
                $norm = Get-NormalizedDateCached -Value $dtCell -Cache $dateCache
                if ($null -eq $norm) { continue }
                $wk = Get-WeekKeyForPlanningIndex -Date $dtCell
                if (-not $byWeek.ContainsKey($wk)) { $byWeek[$wk] = @{} }
                $info = [pscustomobject]@{
                    SheetName   = $sheet.Name
                    ColumnIndex = ($c + 1)
                    HeaderRow   = ($r + 1)
                    HeaderText  = $cell
                }
                if (-not $byWeek[$wk].ContainsKey($norm)) {
                    $byWeek[$wk][$norm] = $info
                }
                elseif (Test-CnCalendarIndexDebug) {
                    $dupDate++
                }
                if ($byDate.ContainsKey($norm)) {
                    if (Test-CnCalendarIndexDebug) { $dupDate++ }
                }
                else {
                    $byDate[$norm] = $info
                }
                $parsedDates++
            }
        }
    }
    $sw.Stop()
    $rows = [System.Collections.Generic.List[object]]::new()
    Trace-DeepObjectLeak -Value $rows -Name "rows" -Location "Build-PlanningCalendarIndex.assign"
    foreach ($k in $byDate.Keys) {
        $info = $byDate[$k]
        $dtK = $null
        try { $dtK = [datetime]::ParseExact($k, 'yyyy-MM-dd', $inv) } catch { continue }
        $sem = Get-WeekKeyForPlanningIndex -Date $dtK
        [void]$rows.Add([pscustomobject]@{
            sheet         = $info.SheetName
            semaine       = $sem
            date          = $k
            column_index  = $info.ColumnIndex
            header_row    = $info.HeaderRow
            header_text   = $info.HeaderText
        })
    }
    Save-CalendarIndexForFile -FileId $fileId -Rows @($rows.ToArray())
    $buildMsVal = (ConvertTo-SafeLong -Value $sw.ElapsedMilliseconds -Name "CalendarBuild.Elapsed")
    script:Write-SqlitePlanningLog -Message "calendar index saved to gestion.db" -Data @{
        fileId   = $fileId
        rowCount = $rows.Count
        buildMs  = $buildMsVal
    }
    Write-PlanningDebugLog -Message "Calendar index built (Excel import → SQLite)" -Level "INFO" -Data @{
        Cells   = $totalCells
        UniqueDates = $byDate.Count
        DateLikeHeaderCells = $parsedDates
        DurationMs = $buildMsVal
        FileId  = $fileId
    }
    Write-PlanningDebugLog -Message "STEP TIMING" -Level "DEBUG" -Data @{
        Step       = "CalendarIndexExcelBuild"
        DurationMs = $buildMsVal
    }
    if (Test-CnCalendarIndexDebug) {
        Write-PlanningDebugLog -Message "CN_DEBUG_EXCEL_INDEX" -Level "DEBUG" -Data @{
            DuplicateHints = $dupDate
        }
    }
}

function script:Normalize-PlanningIndexRow {
    param($Row)
    if ($null -eq $Row) { return $null }
    if ($Row -is [Array] -and @($Row).Count -gt 0) {
        return (Normalize-Scalar -Value $Row[0] -Name "PlanningIndexRow[0]")
    }
    return $Row
}

function script:Get-WorkOrderSortKeyMinPage {
    param($WorkOrder)
    if ($null -eq $WorkOrder -or $null -eq $WorkOrder.Pages) { return 0 }
    return (Get-SafeMin -Values $WorkOrder.Pages -Name "wo.Pages.Get-SafeMin")
}

function script:Sort-PlanningMatchResultRows {
    param($InputObject)
    $list = @($InputObject)
    if ($list.Count -eq 0) { return @() }
    return @(
        $list | Sort-Object `
            @{ Expression = { (Get-SortSafeKeyInt $_.ExcelOrder) } }, `
            @{ Expression = {
                $pm = 0
                if ($null -ne $_.PSObject.Properties['PageMin'] -and $null -ne $_.PageMin) {
                    $pm = $_.PageMin
                }
                elseif ($null -ne $_.WorkOrder) {
                    $pm = script:Get-WorkOrderSortKeyMinPage -WorkOrder $_.WorkOrder
                }
                (Get-SortSafeKeyInt $pm)
            } }
    )
}

function script:Test-PlanningExcelFixedHeaderMatchesDate {
    param(
        [string]$HeaderCell,
        [datetime]$VisitDate
    )
    if ([string]::IsNullOrWhiteSpace($HeaderCell)) { return $false }
    $d = $VisitDate.Day
    $m = $VisitDate.Month
    $patterns = @(
        ('{0:00}/{1:00}' -f $d, $m),
        ('{0}/{1:00}' -f $d, $m),
        ('{0:00}/{1}' -f $d, $m),
        ('{0}/{1}' -f $d, $m)
    )
    foreach ($p in $patterns) {
        if ($HeaderCell -match [regex]::Escape($p)) { return $true }
    }
    return $false
}

function script:Test-PlanningExcelSheetNameMatchesIsoWeek {
    param(
        [string]$SheetName,
        [int]$Week
    )
    if ([string]::IsNullOrWhiteSpace($SheetName)) { return $false }
    $weekToken = [regex]::Escape([string]$Week)
    # Ex. S24, S024, "Planning S24 modifié" — pas de sous-chaîne ambiguë type S124 pour la semaine 24.
    return ($SheetName -match ("(?i)S0?{0}(?:\D|$)" -f $weekToken))
}

function Get-PlanningExcelSheetNameForIsoWeek {
    <#
    .SYNOPSIS
        Résout le nom d’onglet pour une semaine ISO à partir de la liste des feuilles (sans charger les grilles).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SheetNames,
        [Parameter(Mandatory = $true)]
        [int]$Week
    )
    foreach ($name in @($SheetNames)) {
        if (script:Test-PlanningExcelSheetNameMatchesIsoWeek -SheetName $name -Week $Week) {
            Write-Host ("[EXCEL] Onglet cible (recherche flexible) : '{0}' (semaine {1})" -f $name, $Week) -ForegroundColor Green
            return $name
        }
    }
    $weekStrPadded = '{0:D2}' -f $Week
    $candidates = @(
        ("S$weekStrPadded (à faire)"),
        ("S$Week (à faire)"),
        ("S$weekStrPadded"),
        ("S$Week")
    )
    foreach ($cand in $candidates) {
        if ($cand -in @($SheetNames)) {
            Write-Host ("[EXCEL] Onglet cible (recherche exacte) : '{0}'" -f $cand) -ForegroundColor Green
            return $cand
        }
    }
    return $null
}

function script:Get-PlanningExcelSheetForIsoWeek {
    param(
        [object]$ExcelData,
        [int]$Week
    )
    if ($null -eq $ExcelData -or $null -eq $ExcelData.Sheets) { return $null }

    $sheetName = Get-PlanningExcelSheetNameForIsoWeek -SheetNames @($ExcelData.Sheets | ForEach-Object { [string]$_.Name }) -Week $Week
    if ([string]::IsNullOrWhiteSpace($sheetName)) { return $null }
    return @($ExcelData.Sheets | Where-Object { [string]$_.Name -eq $sheetName } | Select-Object -First 1)[0]
}

function script:Get-PlanningExcelFixedColumnFromVisitDate {
    param([datetime]$VisitDate)
    $dayColMap = @{
        'Monday'    = 2
        'Tuesday'   = 25
        'Wednesday' = 48
        'Thursday'  = 71
        'Friday'    = 94
    }
    $dayOfWeek = $VisitDate.DayOfWeek
    if (-not $dayColMap.ContainsKey([string]$dayOfWeek)) { return $null }
    return $dayColMap[[string]$dayOfWeek]
}

function script:Find-ExcelColumnOnSheetForVisitDateFixed {
    param(
        [Parameter(Mandatory = $true)][object]$Sheet,
        [Parameter(Mandatory = $true)][datetime]$VisitDate,
        [Parameter(Mandatory = $true)][int]$Column,
        [string]$Source = 'Fixed'
    )
    $headerRowIndex = 4
    $rowCount = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $Sheet.RowCount -Name 'Fixed.sheet.RowCount') -Name 'Fixed.sheet.RowCount')
    if ($rowCount -le $headerRowIndex) { return $null }

    $colCount = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $Sheet.ColCount -Name 'Fixed.sheet.ColCount') -Name 'Fixed.sheet.ColCount')
    if ($Column -gt $colCount) { return $null }

    $colZero = $Column - 1
    if ($null -eq $Sheet.Grid -or $null -eq $Sheet.Grid[$headerRowIndex]) { return $null }
    if ($colZero -ge @($Sheet.Grid[$headerRowIndex]).Count) { return $null }

    $headerCell = [string]$Sheet.Grid[$headerRowIndex][$colZero]
    if ([string]::IsNullOrWhiteSpace($headerCell)) { return $null }
    if (-not (Test-PlanningExcelFixedHeaderMatchesDate -HeaderCell $headerCell -VisitDate $VisitDate)) { return $null }

    $dayName = Get-FrenchDayName -Date $VisitDate
    $dateShort = $VisitDate.ToString('dd/MM')

    return [pscustomobject]@{
        SheetName   = $Sheet.Name
        ColumnIndex = $Column
        HeaderRow   = 5
        HeaderText  = $headerCell
        TargetDay   = $dayName
        TargetDate  = $dateShort
        Source      = $Source
    }
}

function script:Write-PlanningExcelNonStandardColumnWarning {
    param(
        [datetime]$VisitDate,
        [string]$SheetName,
        [int]$ColumnIndex
    )
    $fixedColumns = @(2, 25, 48, 71, 94)
    if ($ColumnIndex -notin $fixedColumns) {
        Write-Warning "[EXCEL] Date $VisitDate trouvée dans $SheetName, colonne $ColumnIndex (non standard). Vérifier la colonne fixe correspondante."
    }
}

function Find-ExcelColumnFromDateFixed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ExcelData,
        [Parameter(Mandatory = $true)]
        [datetime]$VisitDate,
        [string]$ExcelPath = $null
    )

    $column = script:Get-PlanningExcelFixedColumnFromVisitDate -VisitDate $VisitDate
    if ($null -eq $column) { return $null }
    if ($null -eq $ExcelData -or $null -eq $ExcelData.Sheets -or @($ExcelData.Sheets).Count -lt 1) { return $null }

    $sheet = @($ExcelData.Sheets)[0]
    $result = script:Find-ExcelColumnOnSheetForVisitDateFixed -Sheet $sheet -VisitDate $VisitDate -Column $column -Source 'Fixed'
    if ($null -ne $result) {
        Write-Host ("[EXCEL] Date trouvee dans l'onglet '{0}' colonne {1}" -f $result.SheetName, $column) -ForegroundColor Green
    }
    return $result
}

function Find-ExcelColumnFromDateLegacy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ExcelData,
        [Parameter(Mandatory = $true)]
        [datetime]$VisitDate,
        [string]$ExcelPath = $null
    )
    if (-not (Get-Command Get-CalendarIndexPlanningRow -ErrorAction SilentlyContinue)) {
        throw 'Find-ExcelColumnFromDate: module Database requis (Get-CalendarIndexPlanningRow).'
    }
    if (Get-Command Trace-DeepType -ErrorAction SilentlyContinue) {
        Trace-DeepType -Value $ExcelData -Label "Find-ExcelColumnFromDate.ExcelData"
    }
    if (Test-CnPlanningFlowLog) {
        try {
            $stk = @(Get-PSCallStack | Select-Object -First 8 | ForEach-Object { $_.Command + ':' + $_.ScriptLineNumber }) -join ' <- '
        } catch { $stk = 'n/a' }
        script:Write-PlanningFlowLog -Message "Find-ExcelColumnFromDate entry" -Data @{ stack = $stk }
    }

    $dayName = Get-FrenchDayName -Date $VisitDate
    $dateShort = $VisitDate.ToString('dd/MM')
    $dateNormCache = @{}
    $targetVisitNorm = Get-NormalizedDateCached -Value $VisitDate -Cache $dateNormCache
    $semaine = Get-WeekKeyForPlanningIndex -Date $VisitDate
    $pathParam = if (-not [string]::IsNullOrWhiteSpace($ExcelPath)) { $ExcelPath } else { $null }
    $k = Get-PlanningCalendarIndexKey -ExcelData $ExcelData -ExcelPath $pathParam
    if ($null -eq $k) { throw "Find-ExcelColumnFromDate: chemin / ExcelData invalide pour l’index (cle introuvable)." }
    $k = [string](Normalize-Scalar -Value $k -Name "IndexKey")
    $targetVisitNorm = [string](Normalize-Scalar -Value $targetVisitNorm -Name "targetVisitNorm")
    $semaine = [string](Normalize-Scalar -Value $semaine -Name "semaine")
    $fileId = Get-PlanningCalendarFileId -IndexKey $k
    $fileId = [string](Normalize-Scalar -Value $fileId -Name "fileId")
    $pathForBuild = $pathParam
    if ([string]::IsNullOrWhiteSpace($pathForBuild) -and $null -ne $ExcelData.Path -and (Test-Path -LiteralPath $ExcelData.Path)) {
        $pathForBuild = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ExcelData.Path)
    }
    if ([string]::IsNullOrWhiteSpace($pathForBuild)) { throw "Find-ExcelColumnFromDate: chemin Excel requis pour rebuilder l’index." }

    $swQ1 = [System.Diagnostics.Stopwatch]::StartNew()
    $rowOut = Get-CalendarIndexPlanningRow -FileId $fileId -DateNorm $targetVisitNorm -Semaine $semaine
    $rowOut = (script:Normalize-PlanningIndexRow -Row $rowOut)
    $swQ1.Stop()
    $ms1 = (ConvertTo-SafeLong -Value $swQ1.ElapsedMilliseconds -Name "swQ1.ElapsedMilliseconds")

    if ($null -ne $rowOut) {
        script:Trace-ChirurgicalType -Value $rowOut.column_index -Name 'rowOut.column_index' -Location 'Find-ExcelColumnFromDate:SQLite:primary'
        script:Trace-ChirurgicalType -Value $rowOut.header_row -Name 'rowOut.header_row' -Location 'Find-ExcelColumnFromDate:SQLite:primary'
        script:Trace-ChirurgicalType -Value $rowOut.sheet -Name 'rowOut.sheet' -Location 'Find-ExcelColumnFromDate:SQLite:primary'
        script:Trace-ChirurgicalType -Value $rowOut.header_text -Name 'rowOut.header_text' -Location 'Find-ExcelColumnFromDate:SQLite:primary'
        script:Write-SqlitePlanningLog -Message "index hit" -Data @{ fileId = $fileId; date = $targetVisitNorm; ms = $ms1 }
        script:Write-SqlitePlanningLog -Message "query time" -Data @{ ms = $ms1; fileId = $fileId; phase = "primary" }
        script:Write-PlanningFlowLog -Message "SQLite HIT" -Data @{ fileId = $fileId; date = $targetVisitNorm; next = "RETURN column (no Excel scan)" }
        if (Test-CnPipelineDebug) {
            Write-PlanningDebugLog -Message "Excel column (SQLite cache)" -Level "DEBUG" -Data @{
                ColumnFound = $rowOut.column_index
                ColumnName  = $rowOut.header_text
                SheetName   = $rowOut.sheet
            }
        }
        Write-PlanningDebugLog -Message "STEP TIMING" -Level "DEBUG" -Data @{
            Step       = "SqliteColumnLookup"
            DurationMs = $ms1
        }
        script:Write-PlanningArithOpProbe -Location 'Find-ExcelColumnFromDateLegacy:HIT:sqlite-row' -Op 'dto-field-check' -Left $rowOut.column_index -Right $rowOut.header_row
        $colIdx = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $rowOut.column_index -Name "legacy.column_index") -Name "legacy.column_index")
        Write-PlanningExcelNonStandardColumnWarning -VisitDate $VisitDate -SheetName $rowOut.sheet -ColumnIndex $colIdx
        $out = [pscustomobject]@{
            SheetName   = $rowOut.sheet
            ColumnIndex = $rowOut.column_index
            HeaderRow   = $rowOut.header_row
            HeaderText  = $rowOut.header_text
            TargetDay   = $dayName
            TargetDate  = $dateShort
            Source      = 'Legacy'
        }
        script:Write-PlanningFlowLog -Message "RETURN EXECUTED" -Data @{ from = "SQLite HIT"; step = "SqliteColumnLookup"; column = $out.ColumnIndex }
        return $out
    }
    script:Write-SqlitePlanningLog -Message "index miss" -Data @{ fileId = $fileId; date = $targetVisitNorm }
    script:Write-SqlitePlanningLog -Message "query time" -Data @{ ms = $ms1; fileId = $fileId; phase = "primary" }
    script:Write-PlanningFlowLog -Message "SQLite MISS" -Data @{ fileId = $fileId; date = $targetVisitNorm; next = "check empty then optional single Excel build" }

    $swTotalMs = $ms1
    $cnt = 0L
    if (Get-Command Get-CalendarIndexFileRowCount -ErrorAction SilentlyContinue) {
        $cnt = Get-CalendarIndexFileRowCount -FileId $fileId
        $cnt = (ConvertTo-SafeLong -Value $cnt -Name "rowCount")
    }
    if ($cnt -gt 0) {
        script:Write-PlanningFlowLog -Message "Excel fallback NOT triggered" -Data @{
            reason = "SQLite a des lignes pour ce file_id mais date absente (pas de second scan ni header scan)"
        }
    }
    if ($cnt -eq 0) {
        script:Write-PlanningFlowLog -Message "Excel fallback triggered" -Data @{ reason = "calendar_index vide pour ce file_id"; fileId = $fileId; step = "Build-PlanningCalendarIndex (scan unique)" }
        script:Write-SqlitePlanningLog -Message "index empty for file; single Excel import rebuild" -Data @{ fileId = $fileId }
        Build-PlanningCalendarIndex -ExcelData $ExcelData -ReferenceDate $VisitDate -ExcelPath $pathForBuild
        $swQ2 = [System.Diagnostics.Stopwatch]::StartNew()
        $rowOut = Get-CalendarIndexPlanningRow -FileId $fileId -DateNorm $targetVisitNorm -Semaine $semaine
        $rowOut = (script:Normalize-PlanningIndexRow -Row $rowOut)
        $swQ2.Stop()
        $ms2 = (ConvertTo-SafeLong -Value $swQ2.ElapsedMilliseconds -Name "swQ2.ElapsedMilliseconds")
        if ($null -ne $rowOut) {
            script:Write-SqlitePlanningLog -Message "index hit" -Data @{ fileId = $fileId; afterRebuild = $true; ms = $ms2 }
        } else { script:Write-SqlitePlanningLog -Message "index miss" -Data @{ fileId = $fileId; afterRebuild = $true; ms = $ms2 } }
        script:Write-SqlitePlanningLog -Message "query time" -Data @{ ms = $ms2; fileId = $fileId; afterRebuild = $true; phase = "post_rebuild" }
        $m1L = (ConvertTo-SafeLong -Value $ms1 -Name "ms1.coerce")
        $m2L = (ConvertTo-SafeLong -Value $ms2 -Name "ms2.coerce")
        script:Write-PlanningArithOpProbe -Location 'Find-ExcelColumnFromDate:postRebuild' -Op 'add' -Left $m1L -Right $m2L
        Trace-ArithmeticLeak -Left $m1L -Right $m2L -Operation "add" -Location "Find-ExcelColumnFromDate.postRebuild.totalMs"
        [void](Trace-TypeLeak -Value $m1L -Name "m1L" -Location "Find-ExcelColumnFromDate")
        [void](Trace-TypeLeak -Value $m2L -Name "m2L" -Location "Find-ExcelColumnFromDate")
        script:Trace-ArithHardLeak -Left $m1L -Right $m2L -Op "add" -Location "Find-ExcelColumnFromDate.swTotalMs"
        $swTotalMs = (Invoke-SafeOp -Left $m1L -Right $m2L -Op "add" -Location "Find-ExcelColumnFromDate.swTotalMs")
    }
    if ($null -ne $rowOut) {
        if (Test-CnPipelineDebug) {
            Write-PlanningDebugLog -Message "Excel column (SQLite après import)" -Level "DEBUG" -Data @{
                ColumnFound = $rowOut.column_index
                ColumnName  = $rowOut.header_text
                SheetName   = $rowOut.sheet
            }
        }
        Write-PlanningDebugLog -Message "STEP TIMING" -Level "DEBUG" -Data @{
            Step       = "SqliteColumnLookup"
            DurationMs = $swTotalMs
        }
        script:Trace-ChirurgicalType -Value $rowOut.column_index -Name 'rowOut.column_index' -Location 'Find-ExcelColumnFromDate:SQLite:postRebuild'
        script:Trace-ChirurgicalType -Value $rowOut.header_row -Name 'rowOut.header_row' -Location 'Find-ExcelColumnFromDate:SQLite:postRebuild'
        script:Trace-ChirurgicalType -Value $rowOut.sheet -Name 'rowOut.sheet' -Location 'Find-ExcelColumnFromDate:SQLite:postRebuild'
        script:Trace-ChirurgicalType -Value $rowOut.header_text -Name 'rowOut.header_text' -Location 'Find-ExcelColumnFromDate:SQLite:postRebuild'
        script:Write-PlanningArithOpProbe -Location 'Find-ExcelColumnFromDateLegacy:postRebuild:assign-out' -Op 'dto-field-check' -Left $rowOut.column_index -Right $rowOut.header_row
        $colIdx2 = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $rowOut.column_index -Name "legacy.column_index2") -Name "legacy.column_index2")
        Write-PlanningExcelNonStandardColumnWarning -VisitDate $VisitDate -SheetName $rowOut.sheet -ColumnIndex $colIdx2
        $out2 = [pscustomobject]@{
            SheetName   = $rowOut.sheet
            ColumnIndex = $rowOut.column_index
            HeaderRow   = $rowOut.header_row
            HeaderText  = $rowOut.header_text
            TargetDay   = $dayName
            TargetDate  = $dateShort
            Source      = 'Legacy'
        }
        script:Write-PlanningFlowLog -Message "RETURN EXECUTED" -Data @{ from = "MISS puis rebuild + SQLite HIT"; step = "SqliteColumnLookup" }
        return $out2
    }
    Write-PlanningDebugLog -Message "STEP TIMING" -Level "DEBUG" -Data @{
        Step       = "SqliteColumnLookup"
        DurationMs = $swTotalMs
    }
    script:Write-PlanningFlowLog -Message "RETURN NOT EXECUTED (throw)" -Data @{ from = "SQLite; pas de colonne" }
    Write-Warning "Planning calendar index: pas d’en-tête pour la date $targetVisitNorm (semaine $semaine). Colonne non résolue (SQLite sans entrée, pas de second scan Excel)."
    throw "Find-ExcelColumnFromDateLegacy: colonne introuvable pour '$dayName $dateShort'."
}

function Find-ExcelColumnFromDate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ExcelData,
        [Parameter(Mandatory = $true)]
        [datetime]$VisitDate,
        [string]$ExcelPath = $null
    )

    $result = Find-ExcelColumnFromDateFixed -ExcelData $ExcelData -VisitDate $VisitDate -ExcelPath $ExcelPath
    if ($result) {
        Write-Host "[EXCEL] Date trouvée par colonnes fixes : $($result.SheetName) col. $($result.ColumnIndex)"
        return $result
    }

    Write-Host "[EXCEL] Fallback : recherche lente (scan + BDD)"
    return Find-ExcelColumnFromDateLegacy -ExcelData $ExcelData -VisitDate $VisitDate -ExcelPath $ExcelPath
}

function script:Get-LevenshteinDistance {
    param(
        [string]$A,
        [string]$B
    )
    if ($null -eq $A) { $A = '' }
    if ($null -eq $B) { $B = '' }

    $normalizeScalar = {
        param($v, [string]$name)
        if ($v -is [System.Array] -and -not ($v -is [string])) {
            if ($env:CN_TYPE_GUARD -in @('1', 'true')) {
                $first = if (@($v).Count -gt 0) { $v[0] } else { $null }
                if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                    Write-Log "[TYPE-FIX]" "DEBUG" @{
                        Name = $name
                        Type = $v.GetType().FullName
                        Count = @($v).Count
                        First = $first
                    }
                }
            }
            if (@($v).Count -gt 0) { return $v[0] }
            return 0
        }
        return $v
    }

    $n = [int](& $normalizeScalar $A.Length 'n')
    $m = [int](& $normalizeScalar $B.Length 'm')
    if ($n -eq 0) { return $m }
    if ($m -eq 0) { return $n }

    $d = [int[,]]::new($n + 1, $m + 1)
    for ($i = 0; $i -le $n; $i++) { $d[$i, 0] = $i }
    for ($j = 0; $j -le $m; $j++) { $d[0, $j] = $j }
    for ($i = 1; $i -le $n; $i++) {
        for ($j = 1; $j -le $m; $j++) {
            $iScalar = [int](& $normalizeScalar $i 'i')
            $jScalar = [int](& $normalizeScalar $j 'j')
            $im1 = $iScalar - 1
            $jm1 = $jScalar - 1

            $cost = if ($A[$im1] -eq $B[$jm1]) { 0 } else { 1 }
            $cost = [int](& $normalizeScalar $cost 'cost')

            $del = [int](& $normalizeScalar $d[$im1, $jScalar] 'del.left') + 1
            $ins = [int](& $normalizeScalar $d[$iScalar, $jm1] 'ins.left') + 1
            $sub = [int](& $normalizeScalar $d[$im1, $jm1] 'sub.left') + $cost

            $d[$iScalar, $jScalar] = [Math]::Min([Math]::Min($del, $ins), $sub)
        }
    }
    return $d[$n, $m]
}

function script:Get-SimilarityPercent {
    param(
        [string]$A,
        [string]$B
    )
    if ($A -is [System.Array] -and -not ($A -is [string])) { $A = (@($A) -join ' ') }
    if ($B -is [System.Array] -and -not ($B -is [string])) { $B = (@($B) -join ' ') }
    if ($null -eq $A) { $A = '' } else { $A = [string]$A }
    if ($null -eq $B) { $B = '' } else { $B = [string]$B }

    $a0 = Normalize-ClientKey $A
    $b0 = Normalize-ClientKey $B
    if ([string]::IsNullOrWhiteSpace($a0) -or [string]::IsNullOrWhiteSpace($b0)) { return 0 }

    $ml = (ConvertTo-SafeInt -Value ([Math]::Max($a0.Length, $b0.Length)) -Name "Similarity.maxLen")
    if ($ml -le 0) { return 100 }

    $dist = (ConvertTo-SafeInt -Value (Get-LevenshteinDistance -A $a0 -B $b0) -Name "Similarity.lev")
    $distD = [double]$dist
    $maxLenD = [double][Math]::Max(1, $ml)
    if ($maxLenD -eq 0.0) { return 0 }

    $ratio = ($distD / $maxLenD)
    $invRatio = (1.0 - $ratio)
    $pct = ($invRatio * 100.0)
    return [int][Math]::Round($pct)
}

function script:Test-PlanningExcelSlotHasValidOrderIndex {
    param([AllowNull()] $Slot)
    if ($null -eq $Slot) { return $false }
    if (script:Is-ExcelLabelKeyless -Label ([string]$Slot.Label)) { return $false }
    if (-not $Slot.PSObject.Properties['OrderIndex']) { return $false }
    if ($null -eq $Slot.OrderIndex) { return $false }
    try { return ([int]$Slot.OrderIndex -ge 1) } catch { return $false }
}

function script:Is-ExcelLabelKeyless {
    param([string]$Label)
    if ([string]::IsNullOrWhiteSpace($Label)) { return $true }
    $norm = Normalize-ClientKey $Label
    if ([string]::IsNullOrWhiteSpace($norm)) { return $true }
    if ($norm -match '^(BASE|COLL|JEUDI|LUNDI|MARDI|MERCREDI|VENDREDI|SAMEDI|DIMANCHE|\d)+$') { return $true }
    if ($norm -match '^BASE\d+.*COLL\d+$') { return $true }
    return $false
}

function script:Test-WorkOrderPagesUnused {
    param(
        [object]$WorkOrder,
        [System.Collections.Generic.HashSet[int]]$UsedPages
    )
    if ($null -eq $WorkOrder -or $null -eq $WorkOrder.Pages) { return $false }
    foreach ($p in @($WorkOrder.Pages)) {
        if ($UsedPages.Contains([int]$p)) { return $false }
    }
    return $true
}

function Invoke-ClientIdMatchAudit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$WorkOrders,
        [Parameter(Mandatory = $true)]
        [object[]]$ExcelOrder
    )

    $pdfClientIds = @(
        $WorkOrders |
            Where-Object { $null -ne $_ } |
            ForEach-Object { [string]$_.ClientID } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() } |
            Sort-Object -Unique
    )
    $excelClientIds = @(
        $ExcelOrder |
            Where-Object { $null -ne $_ } |
            ForEach-Object { [string]$_.ClientId } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() } |
            Sort-Object -Unique
    )

    $pdfSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $excelSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($id in $pdfClientIds) { [void]$pdfSet.Add($id) }
    foreach ($id in $excelClientIds) { [void]$excelSet.Add($id) }

    $excelExtractionStatus = if ($excelClientIds.Count -eq 0) { 'FAIL' } else { 'PASS' }
    if ($excelClientIds.Count -eq 0) {
        Write-Host "[CHECK] EXCEL_EXTRACTION = FAIL (no ClientID)"
    }
    else {
        Write-Host "[CHECK] EXCEL_EXTRACTION = PASS"
    }

    $pdfExtractionStatus = if ($pdfClientIds.Count -eq 0) { 'FAIL' } else { 'PASS' }
    if ($pdfClientIds.Count -eq 0) {
        Write-Host "[CHECK] PDF_EXTRACTION = FAIL (no ClientID)"
    }
    else {
        Write-Host "[CHECK] PDF_EXTRACTION = PASS"
    }

    $intersect = [System.Collections.Generic.List[string]]::new()
    foreach ($id in $pdfClientIds) {
        if ($excelSet.Contains($id)) { [void]$intersect.Add($id) }
    }

    $missingExcel = [System.Collections.Generic.List[string]]::new()
    foreach ($id in $pdfClientIds) {
        if (-not $excelSet.Contains($id)) { [void]$missingExcel.Add($id) }
    }

    $missingPdf = [System.Collections.Generic.List[string]]::new()
    foreach ($id in $excelClientIds) {
        if (-not $pdfSet.Contains($id)) { [void]$missingPdf.Add($id) }
    }

    $MatchStrictNormalized = 0
    $MissingNormalized = 0
    $formatStatus = 'FAIL'
    foreach ($excelId in $excelClientIds) {
        $rawMatched = $false
        $normMatched = $false
        foreach ($pdfId in $pdfClientIds) {
            $rawMatch = ($excelId -eq $pdfId)
            $excelIdNorm = ($excelId -as [string]) -replace '[^\d]', ''
            $pdfIdNorm = ($pdfId -as [string]) -replace '[^\d]', ''
            $normMatch = ($excelIdNorm -eq $pdfIdNorm)
            Write-Host "[CLIENTID-FORMAT] ExcelRaw='$excelId' PDFRaw='$pdfId'"
            Write-Host "[CLIENTID-NORMALIZED] Excel='$excelIdNorm' PDF='$pdfIdNorm'"
            if ($rawMatch) {
                Write-Host "[CHECK] FORMAT_RAW_MATCH = PASS"
                $formatStatus = 'PASS'
            }
            elseif ($normMatch) {
                Write-Host "[CHECK] FORMAT_NORMALIZED_MATCH = WARNING"
                if ($formatStatus -ne 'PASS') { $formatStatus = 'WARNING' }
            }
            else {
                Write-Host "[CHECK] FORMAT_MATCH = FAIL"
            }

            if (-not $rawMatched -and $rawMatch) {
                $rawMatched = $true
            }
            if (-not $normMatched -and -not [string]::IsNullOrWhiteSpace($excelIdNorm) -and $normMatch) {
                $normMatched = $true
            }
        }
        if ($normMatched) {
            $MatchStrictNormalized++
        }
        else {
            $MissingNormalized++
        }
    }

    $pdfCount = $pdfSet.Count
    $excelCount = $excelSet.Count
    $matchCount = $intersect.Count
    $matchRateRatio = ([double]$matchCount / [double][Math]::Max(1, $excelClientIds.Count))
    $coverageStatus = 'FAIL'
    if ($matchRateRatio -gt 0.8) {
        $coverageStatus = 'PASS'
        Write-Host ("[CHECK] MATCH_COVERAGE = PASS ({0})" -f ([Math]::Round($matchRateRatio, 4)))
    }
    elseif ($matchRateRatio -gt 0.3) {
        $coverageStatus = 'WARNING'
        Write-Host ("[CHECK] MATCH_COVERAGE = WARNING ({0})" -f ([Math]::Round($matchRateRatio, 4)))
    }
    else {
        Write-Host ("[CHECK] MATCH_COVERAGE = FAIL ({0})" -f ([Math]::Round($matchRateRatio, 4)))
    }
    $den = [Math]::Max(1, [Math]::Max($pdfCount, $excelCount))
    $matchRate = [int][Math]::Round(([double]$matchCount / [double]$den) * 100.0)

    Write-Host "[CLIENTID-AUDIT] PDF_Count=$pdfCount Excel_Count=$excelCount MatchCount=$matchCount MatchRate=$matchRate%"
    foreach ($id in @($missingExcel.ToArray())) {
        Write-Host "[CLIENTID-AUDIT-MISSING-EXCEL] ID=$id"
    }
    foreach ($id in @($missingPdf.ToArray())) {
        Write-Host "[CLIENTID-AUDIT-MISSING-PDF] ID=$id"
    }
    Write-Host "[CLIENTID-DEBUG-SUMMARY] RawMatchCount=$matchCount NormalizedMatchCount=$MatchStrictNormalized ExcelCount=$excelCount PDFCount=$pdfCount MissingNormalized=$MissingNormalized"
    Write-Host ("[CLIENTID-DIAG-SUMMARY] Format={0} Extraction={1} Coverage={2} Pipeline=PENDING Matcher=PENDING" -f $formatStatus, $(if ($excelExtractionStatus -eq 'PASS' -and $pdfExtractionStatus -eq 'PASS') { 'PASS' } else { 'FAIL' }), $coverageStatus)

    return [pscustomobject]@{
        PdfClientIds    = @($pdfClientIds)
        ExcelClientIds  = @($excelClientIds)
        IntersectIds    = @($intersect.ToArray())
        MissingExcelIds = @($missingExcel.ToArray())
        MissingPdfIds   = @($missingPdf.ToArray())
        MatchRate       = $matchRate
        MatchRateRatio  = $matchRateRatio
        RawMatchCount   = $matchCount
        NormalizedMatchCount = $MatchStrictNormalized
        MissingNormalized = $MissingNormalized
        FormatStatus = $formatStatus
        ExcelExtractionStatus = $excelExtractionStatus
        PdfExtractionStatus = $pdfExtractionStatus
        CoverageStatus = $coverageStatus
    }
}

function script:Get-WorkOrderQualityStatusForMatching {
    param([object]$WorkOrder)
    if ($null -eq $WorkOrder) { return 'OK' }
    $prop = $WorkOrder.PSObject.Properties['QualityStatus']
    if ($null -eq $prop) { return 'OK' }
    $status = [string]$prop.Value
    if ([string]::IsNullOrWhiteSpace($status)) { return 'OK' }
    $up = $status.Trim().ToUpperInvariant()
    if ($up -in @('OK', 'WARN', 'ERROR')) { return $up }
    return 'OK'
}

function script:Get-QualityMultiplierForMatching {
    param([string]$QualityStatus)
    $status = if ([string]::IsNullOrWhiteSpace($QualityStatus)) { 'OK' } else { $QualityStatus }
    switch ($status.ToUpperInvariant()) {
        'WARN' { return 0.75 }
        'ERROR' { return 0.25 }
        default { return 1.0 }
    }
}

function script:Get-QualityRankForMatching {
    param([string]$QualityStatus)
    $status = if ([string]::IsNullOrWhiteSpace($QualityStatus)) { 'OK' } else { $QualityStatus }
    switch ($status.ToUpperInvariant()) {
        'OK' { return 3 }
        'WARN' { return 2 }
        'ERROR' { return 1 }
        default { return 0 }
    }
}

function script:Normalize-ClientIdForJoin {
    param($Value)
    if ($null -eq $Value) { return '' }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }
    return ($s.Trim() -replace '[^\d]', '')
}

function script:ExcelContextTextForJoin {
    param($Slot)
    if ($null -eq $Slot) { return '' }
    if ($Slot.PSObject.Properties['RawLines'] -and $null -ne $Slot.RawLines -and @($Slot.RawLines).Count -gt 0) {
        return ([string](@($Slot.RawLines) -join ' ')).Trim()
    }
    return ([string]$Slot.Label).Trim()
}

function script:Normalize-ContextKey {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $v = Remove-Diacritics -Text $Text
    $v = $v.ToUpperInvariant()
    $v = [regex]::Replace($v, '[^A-Z0-9\s]', ' ')
    $v = [regex]::Replace($v, '\s+', ' ').Trim()
    return $v
}

function script:Test-ContainsNormalizedToken {
    param(
        [string]$HaystackNorm,
        [string]$Token
    )
    $tok = Normalize-ContextKey -Text $Token
    if ([string]::IsNullOrWhiteSpace($HaystackNorm) -or [string]::IsNullOrWhiteSpace($tok)) { return $false }
    return $HaystackNorm -like "*$tok*"
}

function script:Try-FallbackWorkOrderJoin {
    param(
        $Slot,
        [object[]]$UnusedWorkOrders,
        [bool]$HadClientIdMismatch
    )
    $excelLabel = ([string]$Slot.Label).Trim()
    $excelContext = ExcelContextTextForJoin -Slot $Slot
    $excelContextNorm = Normalize-PlanningText $excelContext

    $bestCand = $null
    $bestScore = -1
    $bestSim = 0

    foreach ($wo in @($UnusedWorkOrders)) {
        if ($null -eq $wo) { continue }

        $nameSim = Get-SimilarityPercent -A $excelLabel -B ([string]$wo.ClientName)
        if ($nameSim -lt 85) { continue }

        $addrText = Get-EntityAddressText -Entity $wo
        $street = if ($null -ne $wo.Address) { ([string]$wo.Address.Street).Trim() } else { '' }
        $city = if ($null -ne $wo.Address) { ([string]$wo.Address.City).Trim() } else { '' }
        $postal = if ($null -ne $wo.Address) { ([string]$wo.Address.PostalCode).Trim() } else { '' }

        $addrNorm = Normalize-PlanningText $addrText
        $excelNormJoin = Normalize-PlanningText $excelContext
        $cityNorm = Normalize-PlanningText $city

        $addrHit = (-not [string]::IsNullOrWhiteSpace($addrNorm)) -and (
            ($excelNormJoin -like "*$addrNorm*") -or ($excelContextNorm -like "*$street*")
        )

        $cityHit = (-not [string]::IsNullOrWhiteSpace($cityNorm)) -and (
            ($excelNormJoin -like "*$cityNorm*") -or ($excelContextNorm -like "*$city*")
        )

        $postalBoost = (-not [string]::IsNullOrWhiteSpace($postal)) -and ($excelNormJoin -like "*$postal*")

        if ((-not ($addrHit -or $cityHit)) -and -not $postalBoost) { continue }

        $score = [int]$nameSim + $(if ($postalBoost) { 10 } elseif ($addrHit -and $cityHit) { 8 } elseif ($addrHit -or $cityHit) { 6 } else { 0 })

        $pdfDigits = Normalize-ClientIdForJoin $wo.ClientID

        if ($score -gt $bestScore) {
            $bestScore = $score
            $bestCand = $wo
            $bestSim = $nameSim
        }
    }

    if ($null -eq $bestCand) { return $null }

    $fbReasonTag = if ($HadClientIdMismatch) { 'ClientID_MISMATCH' } else { 'ClientID_MISSING' }
    Write-Host "[FALLBACK-MATCH] reason=$fbReasonTag → using NAME/ADDRESS Client=$([string]$Slot.ClientId) WO=$([string]$bestCand.WorkOrder)"

    return [pscustomobject]@{
        WorkOrder   = $bestCand
        Score       = $bestScore
        Similarity  = $bestSim
        MatchReason = 'FALLBACK_NAME_ADDRESS'
    }
}

function script:Get-PlanningGraphStableWorkOrderRef {
    param([object]$WorkOrder)
    if ($null -eq $WorkOrder) { return '<null>' }
    $wid = ([string]$WorkOrder.WorkOrder).Trim()
    if (-not [string]::IsNullOrWhiteSpace($wid)) { return $wid }
    $mp = script:Get-WorkOrderSortKeyMinPage -WorkOrder $WorkOrder
    $cid = Normalize-PlanningText ([string]$WorkOrder.ClientID)
    $snippet = if ($cid.Length -le 24) { $cid } else { $cid.Substring(0, 24) }
    return "[WO:{0}:{1}]" -f $mp, $snippet
}

function script:Get-PlanningGraphSoftEdgeCandidate {
    param($Slot, $WorkOrder)
    if ($null -eq $Slot -or $null -eq $WorkOrder) { return $null }

    $excelLabel = ([string]$Slot.Label).Trim()
    $excelContext = ExcelContextTextForJoin -Slot $Slot
    $excelContextNorm = Normalize-PlanningText $excelContext

    $nameSim = Get-SimilarityPercent -A $excelLabel -B ([string]$WorkOrder.ClientName)
    if ($nameSim -lt 85) { return $null }

    $addrText = Get-EntityAddressText -Entity $WorkOrder
    $street = if ($null -ne $WorkOrder.Address) { ([string]$WorkOrder.Address.Street).Trim() } else { '' }
    $city = if ($null -ne $WorkOrder.Address) { ([string]$WorkOrder.Address.City).Trim() } else { '' }
    $postal = if ($null -ne $WorkOrder.Address) { ([string]$WorkOrder.Address.PostalCode).Trim() } else { '' }

    $addrNorm = Normalize-PlanningText $addrText
    $excelNormJoin = Normalize-PlanningText $excelContext
    $cityNorm = Normalize-PlanningText $city

    $addrHit = (-not [string]::IsNullOrWhiteSpace($addrNorm)) -and (
        ($excelNormJoin -like "*$addrNorm*") -or ($excelContextNorm -like "*$street*")
    )

    $cityHit = (-not [string]::IsNullOrWhiteSpace($cityNorm)) -and (
        ($excelNormJoin -like "*$cityNorm*") -or ($excelContextNorm -like "*$city*")
    )

    $postalBoost = (-not [string]::IsNullOrWhiteSpace($postal)) -and ($excelNormJoin -like "*$postal*")

    if ((-not ($addrHit -or $cityHit)) -and -not $postalBoost) { return $null }

    $score = [int]$nameSim + $(if ($postalBoost) { 10 } elseif ($addrHit -and $cityHit) { 8 } elseif ($addrHit -or $cityHit) { 6 } else { 0 })

    return [pscustomobject]@{
        Score           = $score
        Similarity      = [int]$nameSim
        MatchReason     = 'FALLBACK_NAME_ADDRESS_SOFT'
        WeightTier      = 70
    }
}

function script:Get-PlanningGraphSlotWorkOrderEdge {
    param($Slot, $WorkOrder)
    if ($null -eq $Slot -or $null -eq $WorkOrder) { return $null }

    $excelRawId = ([string]$Slot.ClientId).Trim()
    $excelDigits = Normalize-ClientIdForJoin $Slot.ClientId
    $pdfRaw = ([string]$WorkOrder.ClientID).Trim()
    $excelId = $excelRawId
    $pdfId = $pdfRaw
    if (-not [string]::IsNullOrWhiteSpace($excelRawId) -and -not [string]::IsNullOrWhiteSpace($pdfRaw) -and ($excelRawId -eq $pdfRaw)) {
        $script:ClientIdMatcherStatus = 'PASS'
        Write-Host "[CHECK] EDGE_CLIENTID_MATCH = PASS"
        return [pscustomobject]@{
            WeightTier          = 100
            MatchScore          = 100
            Similarity          = 100
            MatchReason         = 'CLIENTID_EXACT_JOIN'
            EdgeWeightDisplay   = [decimal]'1.0'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($excelDigits)) {
        $pdfDigits = Normalize-ClientIdForJoin $WorkOrder.ClientID
        if ((-not [string]::IsNullOrWhiteSpace($pdfDigits)) -and ($pdfDigits -eq $excelDigits)) {
            $script:ClientIdMatcherStatus = 'PASS'
            Write-Host "[CHECK] EDGE_CLIENTID_MATCH = PASS"
            return [pscustomobject]@{
                WeightTier        = 100
                MatchScore        = 100
                Similarity        = 100
                MatchReason       = 'CLIENTID_NORMALIZED_JOIN'
                EdgeWeightDisplay = [decimal]'1.0'
            }
        }
    }
    Write-Host "[CHECK] EDGE_CLIENTID_MATCH = FAIL"

    $soft = Get-PlanningGraphSoftEdgeCandidate -Slot $Slot -WorkOrder $WorkOrder
    if ($null -eq $soft) { return $null }

    $tierCap = [Math]::Min(70, [int]$soft.Score)
    return [pscustomobject]@{
        WeightTier        = 70
        MatchScore        = $tierCap
        Similarity        = $soft.Similarity
        MatchReason       = 'FALLBACK_NAME_ADDRESS_SOFT'
        EdgeWeightDisplay = [decimal]'0.7'
    }
}

function script:Test-PlanningGraphEdgeBBeatsA {
    param(
        [object]$EdgeA,
        [object]$WoA,
        [object]$EdgeB,
        [object]$WoB
    )
    if ($null -eq $EdgeB) { return $false }
    if ($null -eq $EdgeA -or $null -eq $WoA) { return $true }

    $wtA = [int]$EdgeA.WeightTier
    $wtB = [int]$EdgeB.WeightTier
    if ($wtB -ne $wtA) { return $wtB -gt $wtA }

    $msA = [int]$EdgeA.MatchScore
    $msB = [int]$EdgeB.MatchScore
    if ($msB -ne $msA) { return $msB -gt $msA }

    $pgA = [int](script:Get-WorkOrderSortKeyMinPage -WorkOrder $WoA)
    $pgB = [int](script:Get-WorkOrderSortKeyMinPage -WorkOrder $WoB)
    if ($pgB -ne $pgA) { return $pgB -lt $pgA }

    $refA = script:Get-PlanningGraphStableWorkOrderRef -WorkOrder $WoA
    $refB = script:Get-PlanningGraphStableWorkOrderRef -WorkOrder $WoB
    $cRef = [System.String]::CompareOrdinal($refB, $refA)
    if ($cRef -ne 0) { return ($cRef -lt 0) }
    return $false
}

function Invoke-PlanningGraphMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$WorkOrders,
        [Parameter(Mandatory = $true)]
        [object[]]$ExcelOrder
    )
    Write-Warning "[MATCHER-GRAPH-DISABLED] Fallback to canonical matcher Match-WorkOrderToExcelOrderSmart."
    return (Match-WorkOrderToExcelOrderSmart -WorkOrders $WorkOrders -ExcelOrder $ExcelOrder)
}

function Match-WorkOrderToExcelOrderSmart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$WorkOrders,
        [Parameter(Mandatory = $true)]
        [object[]]$ExcelOrder
    )

    $wos = @(
        $WorkOrders |
            Where-Object { $null -ne $_ } |
            ForEach-Object {
                $_ | Add-Member -NotePropertyName '__SortWorkOrderMinPage' -NotePropertyValue (
                    script:Get-WorkOrderSortKeyMinPage -WorkOrder $_
                ) -Force
                $_
            } |
            Sort-Safe -Property '__SortWorkOrderMinPage' -KeyType Int
    )
    $slots = @(
        $ExcelOrder |
            Where-Object { $null -ne $_ } |
            Sort-Safe -Property 'OrderIndex' -KeyType Int
    )

    if ($wos.Count -eq 0) {
        $missingAll = [System.Collections.Generic.List[object]]::new()
        foreach ($s in @($slots)) {
            if ($null -eq $s) {
                Write-Warning '[MATCH-MISSING] slot null (aucun WorkOrder PDF), ignore'
                continue
            }
            if (-not (script:Test-PlanningExcelSlotHasValidOrderIndex -Slot $s)) { continue }
            $orderIdxNone = [int]$s.OrderIndex
            [void]$missingAll.Add([pscustomobject]@{
                ExcelOrder = $orderIdxNone
                Label      = $s.Label
                Score      = 0
            })
            Write-Host ("[MATCH-RESULT] Type=NONE ExcelClientID={0} PDFClientID=" -f (Normalize-ClientIdForJoin $s.ClientId))
        }
        return [pscustomobject]@{
            Matches    = @()
            Missing    = @($missingAll.ToArray())
            Duplicates = @()
            Strategy   = 'CLIENTID_FIRST_CONTEXT'
        }
    }

    $workOrdersByClientId = @{}
    foreach ($wo in @($wos)) {
        $k = Normalize-ClientIdForJoin $wo.ClientID
        if ([string]::IsNullOrWhiteSpace($k)) { continue }
        if (-not $workOrdersByClientId.ContainsKey($k)) {
            $workOrdersByClientId[$k] = [System.Collections.Generic.List[object]]::new()
        }
        [void]$workOrdersByClientId[$k].Add($wo)
    }

    $usedWoKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $matches = [System.Collections.Generic.List[object]]::new()
    $missing = [System.Collections.Generic.List[object]]::new()
    $slotTotal = @($slots).Count
    $slotIdx = 0

    if ($null -eq $script:PlanningMatchExactCount) { $script:PlanningMatchExactCount = 0 }
    if ($null -eq $script:PlanningMatchFuzzyCount) { $script:PlanningMatchFuzzyCount = 0 }
    $script:PlanningMatchExactCount = 0
    $script:PlanningMatchFuzzyCount = 0
    Write-PlanningExcelSubStep -SubStepIndex 6 -Title 'Matching ClientID exact' -Status 'SubStepStart' -SubRatio 0.55

    $pendingFuzzy = [System.Collections.Generic.List[object]]::new()
    foreach ($slot in @($slots)) {
        if ($null -eq $slot) {
            Write-Warning '[MATCH-MISSING] slot null dans passe ClientID exact, ignore'
            continue
        }
        $slotIdx++
        Write-PlanningExcelSubStep -SubStepIndex 6 -Status 'SubStepProgress' `
            -Detail ("client {0}/{1}" -f $slotIdx, $slotTotal) `
            -SubRatio (0.55 + 0.07 * ($slotIdx / [Math]::Max(1, $slotTotal)))

        $excelIdNorm = Normalize-ClientIdForJoin $slot.ClientId
        $exactMatchedAny = $false

        if (-not [string]::IsNullOrWhiteSpace($excelIdNorm) -and $workOrdersByClientId.ContainsKey($excelIdNorm)) {
            $candidates = @(
                $workOrdersByClientId[$excelIdNorm].ToArray() |
                    Where-Object {
                        $null -ne $_ -and -not $usedWoKeys.Contains((script:Get-PlanningGraphStableWorkOrderRef -WorkOrder $_))
                    }
            )
            if ($candidates.Count -gt 0) {
                $candidates = @(
                    $candidates | Sort-Object { script:Get-WorkOrderSortKeyMinPage -WorkOrder $_ }
                )
                $maxPerSlot = 50
                if (-not [string]::IsNullOrWhiteSpace($env:CN_MAX_MATCHES_PER_EXCEL_SLOT)) {
                    try {
                        $parsedMax = [int]$env:CN_MAX_MATCHES_PER_EXCEL_SLOT
                        if ($parsedMax -gt 0) { $maxPerSlot = $parsedMax }
                    }
                    catch { }
                }
                $isMultiSlot = ($candidates.Count -gt 1)
                $slotMatchCount = 0
                foreach ($cand in @($candidates)) {
                    if ($slotMatchCount -ge $maxPerSlot) {
                        Write-Warning ("[MATCH] CN_MAX_MATCHES_PER_EXCEL_SLOT={0} atteint pour ExcelClientID={1}" -f $maxPerSlot, $excelIdNorm)
                        break
                    }
                    $woKey = script:Get-PlanningGraphStableWorkOrderRef -WorkOrder $cand
                    if ($usedWoKeys.Contains($woKey)) { continue }
                    [void]$usedWoKeys.Add($woKey)
                    $script:PlanningMatchExactCount++
                    $slotMatchCount++
                    $exactMatchedAny = $true
                    $pdfIdNorm = Normalize-ClientIdForJoin $cand.ClientID
                    $pageMin = script:Get-WorkOrderSortKeyMinPage -WorkOrder $cand
                    $matchReason = if ($isMultiSlot) { 'CLIENTID_EXACT_MULTI' } else { 'CLIENTID_EXACT' }
                    $matchTypeLabel = if ($isMultiSlot) { 'ID_MULTI' } else { 'ID' }
                    Write-Host ("[MATCH] TYPE={0} SCORE=100 ExcelClientID={1} PdfClientID={2}" -f $matchTypeLabel, $excelIdNorm, $pdfIdNorm)
                    Write-Host ("[MATCH-RESULT] Type={0} ExcelClientID={1} PDFClientID={2}" -f $matchTypeLabel, $excelIdNorm, $pdfIdNorm)
                    [void]$matches.Add([pscustomobject]@{
                        ExcelOrder  = $slot.OrderIndex
                        ExcelLabel  = $slot.Label
                        MatchScore  = 100
                        Similarity  = 100
                        MatchReason = $matchReason
                        WorkOrder   = $cand
                        Entity      = $null
                        PageMin     = $pageMin
                    })
                }
            }
        }

        if ($exactMatchedAny) {
            $script:ClientIdMatcherStatus = 'PASS'
        }
        elseif (script:Test-PlanningExcelSlotHasValidOrderIndex -Slot $slot) {
            [void]$pendingFuzzy.Add($slot)
        }
    }

    Write-PlanningExcelSubStep -SubStepIndex 6 -Title 'Matching ClientID exact' -Status 'SubStepEnd' `
        -Detail ("({0} correspondances)" -f $script:PlanningMatchExactCount) -SubRatio 0.62

    Write-PlanningExcelSubStep -SubStepIndex 7 -Title 'Matching flou (nom/adresse)' -Status 'SubStepStart' -SubRatio 0.65

    $fuzzyTotal = @($pendingFuzzy).Count
    $fuzzyIdx = 0
    foreach ($slot in @($pendingFuzzy)) {
        if ($null -eq $slot) {
            Write-Warning '[MATCH-MISSING] slot null dans pendingFuzzy, ignore'
            continue
        }
        $fuzzyIdx++
        Write-PlanningExcelSubStep -SubStepIndex 7 -Status 'SubStepProgress' `
            -Detail ("client {0}/{1}" -f $fuzzyIdx, $fuzzyTotal) `
            -SubRatio (0.65 + 0.13 * ($fuzzyIdx / [Math]::Max(1, $fuzzyTotal)))

        if ($env:CN_DEBUG_MATCHING -in @('1', 'true')) {
            Write-Host ("[DEBUG-MATCH] slot OrderIndex={0} Label={1}" -f $slot.OrderIndex, $slot.Label) -ForegroundColor DarkGray
        }

        $excelIdNorm = Normalize-ClientIdForJoin $slot.ClientId
        $matchedWo = $null
        $matchType = 'NONE'
        $matchReason = 'NO_MATCH'
        $matchScore = 0
        $similarity = 0

        $excelContext = ExcelContextTextForJoin -Slot $slot
            $excelContextNorm = Normalize-ContextKey -Text $excelContext

            $excelName = ''
            $propNom = $slot.PSObject.Properties['NomClient']
            if ($null -ne $propNom -and -not [string]::IsNullOrWhiteSpace(([string]$propNom.Value).Trim())) {
                $excelName = ([string]$propNom.Value).Trim()
            }
            if ([string]::IsNullOrWhiteSpace($excelName)) {
                $propCn = $slot.PSObject.Properties['ClientName']
                if ($null -ne $propCn -and -not [string]::IsNullOrWhiteSpace(([string]$propCn.Value).Trim())) {
                    $excelName = ([string]$propCn.Value).Trim()
                }
            }
            if ([string]::IsNullOrWhiteSpace($excelName)) {
                $excelName = ([string]$slot.Label).Trim()
            }

            $bestNameWo = $null
            $bestNameSim = -1
            foreach ($wo in @($wos)) {
                $woKey = script:Get-PlanningGraphStableWorkOrderRef -WorkOrder $wo
                if ($usedWoKeys.Contains($woKey)) { continue }

                $nameSimRaw = Get-SimilarityPercent -A $excelName -B ([string]$wo.ClientName)
                $aN = Normalize-ClientKey $excelName
                $bN = Normalize-ClientKey ([string]$wo.ClientName)
                $nameSim = $nameSimRaw
                if (
                    -not [string]::IsNullOrWhiteSpace($aN) -and
                    -not [string]::IsNullOrWhiteSpace($bN) -and
                    ($aN -cne $bN)
                ) {
                    $sKey = if ($aN.Length -lt $bN.Length) { $aN } else { $bN }
                    $lKey = if ($aN.Length -lt $bN.Length) { $bN } else { $aN }
                    if ($sKey.Length -ge 3 -and $lKey.Contains($sKey)) {
                        $nameSim = [Math]::Max($nameSimRaw, 100)
                    }
                }
                if ($nameSim -lt 80) { continue }

                if ($nameSim -gt $bestNameSim) {
                    $bestNameSim = $nameSim
                    $bestNameWo = $wo
                }
                elseif ($nameSim -eq $bestNameSim -and $null -ne $bestNameWo) {
                    $pgNew = [int](script:Get-WorkOrderSortKeyMinPage -WorkOrder $wo)
                    $pgOld = [int](script:Get-WorkOrderSortKeyMinPage -WorkOrder $bestNameWo)
                    if ($pgNew -lt $pgOld) {
                        $bestNameWo = $wo
                    }
                    elseif ($pgNew -eq $pgOld) {
                        $r = [string]::CompareOrdinal(
                            (script:Get-PlanningGraphStableWorkOrderRef -WorkOrder $wo),
                            (script:Get-PlanningGraphStableWorkOrderRef -WorkOrder $bestNameWo)
                        )
                        if ($r -lt 0) { $bestNameWo = $wo }
                    }
                }
            }

            if ($null -ne $bestNameWo) {
                $matchedWo = $bestNameWo
                $pdfIdNorm = Normalize-ClientIdForJoin $bestNameWo.ClientID
                $excelDisp = (($excelName -replace '"', "'") -replace '[\r\n]+', ' ')
                $pdfDisp = (([string]$bestNameWo.ClientName -replace '"', "'") -replace '[\r\n]+', ' ')
                if ($excelDisp.Length -gt 80) { $excelDisp = $excelDisp.Substring(0, 77) + '...' }
                if ($pdfDisp.Length -gt 80) { $pdfDisp = $pdfDisp.Substring(0, 77) + '...' }
                Write-Host ("[MATCH] TYPE=NAME SCORE={0} ExcelClientID={1} PdfClientID={2} Excel=`"{3}`" PDF=`"{4}`"" -f $bestNameSim, $excelIdNorm, $pdfIdNorm, $excelDisp, $pdfDisp)
                $script:ClientIdMatcherStatus = 'PASS'
                $matchType = 'NAME'
                $matchReason = 'NAME_SIMILARITY'
                $matchScore = 85
                $similarity = $bestNameSim
            }
            else {
                $bestWo = $null
                $bestAddressSim = -1.0
                $bestAddrRank = [int]::MaxValue
                $bestCityOk = $false
                $bestPostalOk = $false

                foreach ($wo in @($wos)) {
                    $woKey = script:Get-PlanningGraphStableWorkOrderRef -WorkOrder $wo
                    if ($usedWoKeys.Contains($woKey)) { continue }

                    $city = if ($null -ne $wo.Address) { [string]$wo.Address.City } else { '' }
                    $postal = if ($null -ne $wo.Address) { [string]$wo.Address.PostalCode } else { '' }
                    $street = if ($null -ne $wo.Address) { ([string]$wo.Address.Street).Trim() } else { '' }
                    $addressText = Get-EntityAddressText -Entity $wo

                    $cityOk = Test-ContainsNormalizedToken -HaystackNorm $excelContextNorm -Token $city
                    $postalOk = Test-ContainsNormalizedToken -HaystackNorm $excelContextNorm -Token $postal
                    if (-not ($cityOk -and $postalOk)) { continue }

                    $streetOk = (-not [string]::IsNullOrWhiteSpace($street)) -and (
                        Test-ContainsNormalizedToken -HaystackNorm $excelContextNorm -Token $street
                    )
                    $addrRank = if ($streetOk) { 0 } else { 1 }

                    $addressSimilarity = ([double](Get-SimilarityPercent -A $excelContext -B $addressText)) / 100.0

                    $replace = $false
                    if ($null -eq $bestWo) {
                        $replace = $true
                    }
                    elseif ($addrRank -lt $bestAddrRank) {
                        $replace = $true
                    }
                    elseif ($addrRank -gt $bestAddrRank) {
                        $replace = $false
                    }
                    else {
                        if ($addressSimilarity -gt $bestAddressSim) {
                            $replace = $true
                        }
                        elseif ($addressSimilarity -lt $bestAddressSim) {
                            $replace = $false
                        }
                        else {
                            $pgNew = [int](script:Get-WorkOrderSortKeyMinPage -WorkOrder $wo)
                            $pgOld = [int](script:Get-WorkOrderSortKeyMinPage -WorkOrder $bestWo)
                            if ($pgNew -lt $pgOld) {
                                $replace = $true
                            }
                            elseif ($pgNew -eq $pgOld) {
                                $replace = (
                                    [string]::CompareOrdinal(
                                        (script:Get-PlanningGraphStableWorkOrderRef -WorkOrder $wo),
                                        (script:Get-PlanningGraphStableWorkOrderRef -WorkOrder $bestWo)
                                    ) -lt 0
                                )
                            }
                        }
                    }

                    if ($replace) {
                        $bestWo = $wo
                        $bestAddressSim = $addressSimilarity
                        $bestAddrRank = $addrRank
                        $bestCityOk = $cityOk
                        $bestPostalOk = $postalOk
                    }
                }

                if ($null -ne $bestWo) {
                    $matchedWo = $bestWo
                    $pdfIdNorm = Normalize-ClientIdForJoin $bestWo.ClientID
                    $tierScore = if ($bestAddrRank -eq 0) { 75 } else { 65 }
                    $tierType = if ($bestAddrRank -eq 0) { 'ADDRESS' } else { 'CITY' }
                    $simPct = [int][Math]::Round([Math]::Max(0.0, $bestAddressSim) * 100.0)
                    Write-Host ("[FALLBACK-CONTEXT] ExcelId={0} PDFId={1}" -f $excelIdNorm, $pdfIdNorm)
                    Write-Host ("[FALLBACK-CONTEXT-SCORE] Address={0} City={1} Postal={2}" -f ([Math]::Round([Math]::Max(0.0, $bestAddressSim), 3)), $(if ($bestCityOk) { 'OK' } else { 'KO' }), $(if ($bestPostalOk) { 'OK' } else { 'KO' }))
                    Write-Host ("[MATCH] TYPE={0} SCORE={1} ExcelClientID={2} PdfClientID={3} ADDR_SIM_PCT={4}" -f $tierType, $tierScore, $excelIdNorm, $pdfIdNorm, $simPct)
                    $script:ClientIdMatcherStatus = 'PASS'
                    $matchType = $tierType
                    $matchReason = if ($bestAddrRank -eq 0) { 'CONTEXT_FULL_ADDRESS' } else { 'CONTEXT_CITY_POSTAL' }
                    $matchScore = $tierScore
                    $similarity = $simPct
                }
            }

        if ($null -ne $matchedWo) {
            $script:PlanningMatchFuzzyCount++
            $pdfIdNorm = Normalize-ClientIdForJoin $matchedWo.ClientID
            $woKey = script:Get-PlanningGraphStableWorkOrderRef -WorkOrder $matchedWo
            [void]$usedWoKeys.Add($woKey)
            Write-Host ("[MATCH-RESULT] Type={0} ExcelClientID={1} PDFClientID={2}" -f $matchType, $excelIdNorm, $pdfIdNorm)
            [void]$matches.Add([pscustomobject]@{
                ExcelOrder  = $slot.OrderIndex
                ExcelLabel  = $slot.Label
                MatchScore  = $matchScore
                Similarity  = $similarity
                MatchReason = $matchReason
                WorkOrder   = $matchedWo
                Entity      = $null
            })
        }
        else {
            if ($null -eq $slot) {
                Write-Warning '[MATCH-MISSING] slot null, non ajoute a Missing'
                continue
            }
            if (-not (script:Test-PlanningExcelSlotHasValidOrderIndex -Slot $slot)) { continue }
            $orderIdxMiss = [int]$slot.OrderIndex
            Write-Host ("[MATCH-RESULT] Type=NONE ExcelClientID={0} PDFClientID=" -f $excelIdNorm)
            [void]$missing.Add([pscustomobject]@{
                ExcelOrder = $orderIdxMiss
                Label      = $slot.Label
                Score      = 0
            })
        }
    }

    Write-PlanningExcelSubStep -SubStepIndex 7 -Title 'Matching flou (nom/adresse)' -Status 'SubStepEnd' `
        -Detail ("({0} correspondances)" -f $script:PlanningMatchFuzzyCount) -SubRatio 0.78

    Write-PlanningExcelSubStep -SubStepIndex 8 -Title 'Resolution des conflits' -Status 'SubStepStart' -SubRatio 0.82
    Write-PlanningExcelSubStep -SubStepIndex 8 -Title 'Resolution des conflits' -Status 'SubStepEnd' `
        -Detail ("({0} non-matches)" -f @($missing).Count) -SubRatio 0.95

    return [pscustomobject]@{
        Matches = script:Sort-PlanningMatchResultRows -InputObject @(
            @($matches.ToArray()) | ForEach-Object {
                [void](Trace-ObjectArrayLeak -Value $_.ExcelOrder -Name "ExcelOrder" -Location "BeforeSort:MatchWorkOrderToExcelOrderSmart.Matches")
                $_
            }
        )
        Missing = @($missing.ToArray())
        Duplicates = @()
        Strategy = 'CLIENTID_FIRST_CONTEXT'
    }
}

function Match-WorkOrderToExcelPositional {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$WorkOrders,
        [Parameter(Mandatory = $true)]
        [object[]]$ExcelOrder
    )
    Write-Warning "[MATCHER-POSITIONAL-DISABLED] Fallback to canonical matcher Match-WorkOrderToExcelOrderSmart."
    return (Match-WorkOrderToExcelOrderSmart -WorkOrders $WorkOrders -ExcelOrder $ExcelOrder)
}

function Extract-ExcelOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ExcelData,
        [Parameter(Mandatory = $true)]
        [object]$ColumnInfo
    )

    if ($null -ne $ColumnInfo) {
        script:Trace-ChirurgicalType -Value $ColumnInfo.ColumnIndex -Name 'ColumnInfo.ColumnIndex' -Location 'Extract-ExcelOrder:input'
        script:Trace-ChirurgicalType -Value $ColumnInfo.HeaderRow -Name 'ColumnInfo.HeaderRow' -Location 'Extract-ExcelOrder:input'
        if (Get-Command Trace-IfArrayLeak -ErrorAction SilentlyContinue) {
            [void](Trace-IfArrayLeak -Value $ColumnInfo.ColumnIndex -Label "Extract-ExcelOrder.ColumnIndex")
            [void](Trace-IfArrayLeak -Value $ColumnInfo.HeaderRow -Label "Extract-ExcelOrder.HeaderRow")
        }
    }
    if (Get-Command Trace-DeepType -ErrorAction SilentlyContinue) {
        if ($null -ne $ColumnInfo) {
            Trace-DeepType -Value $ColumnInfo.ColumnIndex -Label "Extract-ExcelOrder.ColumnInfo.ColumnIndex"
            Trace-DeepType -Value $ColumnInfo.HeaderRow -Label "Extract-ExcelOrder.ColumnInfo.HeaderRow"
        }
    }

    $sheet = @($ExcelData.Sheets | Where-Object { $_.Name -eq $ColumnInfo.SheetName })[0]
    if ($null -eq $sheet) {
        throw "Extract-ExcelOrder: onglet introuvable '$($ColumnInfo.SheetName)'."
    }

    [void](Trace-ObjectArrayLeak -Value $ColumnInfo.ColumnIndex -Name "ColumnIndex" -Location "Extract-ExcelOrder.ColumnInfo")
    $col1 = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $ColumnInfo.ColumnIndex -Name "ColumnInfo.ColumnIndex") -Name "ColumnInfo.ColumnIndex")
    $startZero = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $ColumnInfo.HeaderRow -Name "ColumnInfo.HeaderRow") -Name "ColumnInfo.HeaderRow")
    [void](Trace-TypeLeak -Value $col1 -Name "col1" -Location "Extract-ExcelOrder")
    [void](Trace-TypeLeak -Value $startZero -Name "startZero" -Location "Extract-ExcelOrder")
    script:Write-PlanningArithOpProbe -Location 'Extract-ExcelOrder:colZero' -Op 'sub' -Left $col1 -Right 1
    $colZero = (Safe-Subtract -Left $col1 -Right 1 -Context "Extract-ExcelOrder.colZero")
    $sheetRowCount = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $sheet.RowCount -Name "Extract.sheet.RowCount") -Name "Extract.sheet.RowCount")
    $sheetColCount = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $sheet.ColCount -Name "Extract.sheet.ColCount") -Name "Extract.sheet.ColCount")
    $items = [System.Collections.Generic.List[object]]::new()
    $rank = 1
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-PlanningDebugLog -Message "Extracting Excel rows under column" -Level "DEBUG" -Data @{
        SheetName    = $ColumnInfo.SheetName
        ColumnIndex  = $ColumnInfo.ColumnIndex
        HeaderRow    = $ColumnInfo.HeaderRow
        HeaderText   = $ColumnInfo.HeaderText
    }

    if (script:Test-CnExcelExtractionDebug) {
        $dayLabel = if ([string]::IsNullOrWhiteSpace([string]$ColumnInfo.HeaderText)) {
            [string]$ColumnInfo.SheetName
        } else {
            [string]$ColumnInfo.HeaderText
        }
        Write-Host ("[EXCEL-DEBUG] ===== JOUR {0} =====" -f $dayLabel) -ForegroundColor Cyan

        $debugTours = [System.Collections.Generic.List[object]]::new()
        $debugCurrentTour = [System.Collections.Generic.List[string]]::new()
        $debugEmptyStreak = 0
        $debugClientCount = 0

        for ($dbgRow = $startZero; $dbgRow -lt $sheetRowCount; $dbgRow++) {
            $rawValue = ''
            if ($colZero -ge 0 -and $colZero -lt $sheetColCount) {
                $rawCell = $sheet.Grid[$dbgRow][$colZero]
                if ($null -ne $rawCell) {
                    $rawValue = [string]$rawCell
                }
            }

            $trimmedValue = $rawValue.Trim()
            $excelRowOneBased = (Invoke-SafeOp -Left $dbgRow -Right 1 -Op "add" -Location "Extract-ExcelOrder.Debug.ExcelRow")

            if ([string]::IsNullOrWhiteSpace($trimmedValue)) {
                $debugEmptyStreak++
                if ($rawValue -eq '') {
                    Write-Host ("[EXCEL-DEBUG] Ligne {0} = VIDE" -f $excelRowOneBased) -ForegroundColor DarkGray
                } else {
                    Write-Host ("[EXCEL-DEBUG] Ligne {0} = `"{1}`"" -f $excelRowOneBased, $rawValue) -ForegroundColor DarkGray
                }

                if ($debugEmptyStreak -ge 3 -and $debugCurrentTour.Count -gt 0) {
                    [void]$debugTours.Add([pscustomobject]@{
                        Clients = @($debugCurrentTour.ToArray())
                    })
                    $debugCurrentTour.Clear()
                }
                continue
            }

            $debugEmptyStreak = 0
            $debugClientCount++
            [void]$debugCurrentTour.Add($trimmedValue)
            Write-Host ("[EXCEL-DEBUG] Ligne {0} = `"{1}`"" -f $excelRowOneBased, $rawValue) -ForegroundColor Gray
        }

        if ($debugCurrentTour.Count -gt 0) {
            [void]$debugTours.Add([pscustomobject]@{
                Clients = @($debugCurrentTour.ToArray())
            })
        }

        $tourNumber = 0
        foreach ($tour in @($debugTours.ToArray())) {
            $tourNumber++
            Write-Host ("[TOURNEE {0}]" -f $tourNumber) -ForegroundColor Yellow
            foreach ($client in @($tour.Clients)) {
                Write-Host (" - {0}" -f $client) -ForegroundColor Yellow
            }
            Write-Host ""
        }

        Write-Host ("[EXCEL-DEBUG] Clients lus (debug brut) = {0}" -f $debugClientCount) -ForegroundColor Cyan
        Write-Host ("[EXCEL-DEBUG] Tournees detectees (>=3 lignes vides) = {0}" -f $tourNumber) -ForegroundColor Cyan
    }

    $excelLines = [System.Collections.Generic.List[object]]::new()
    for ($r = $startZero; $r -lt $sheetRowCount; $r++) {
        $cellText = ''
        if ($colZero -ge 0 -and $colZero -lt $sheetColCount) {
            $cellText = [string]$sheet.Grid[$r][$colZero]
        }
        $cellText = $cellText.Trim()

        if ([string]::IsNullOrWhiteSpace($cellText)) {
            continue
        }

        $excelRowOneBased = (Invoke-SafeOp -Left $r -Right 1 -Op "add" -Location "Extract-ExcelOrder.ExcelLineRow")
        $splitLines = @($cellText -split "`r`n|`n|`r")
        foreach ($line in $splitLines) {
            [void]$excelLines.Add([pscustomobject]@{
                ExcelRow = $excelRowOneBased
                Text     = [string]$line
            })
        }
    }

    $clients = [System.Collections.Generic.List[object]]::new()
    $current = $null
    foreach ($excelLine in @($excelLines.ToArray())) {
        $line = [string]$excelLine.Text
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $line = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        if ($line -match '^\((\d{4,6})\)\s*(.+)$') {
            if ($null -ne $current) {
                [void]$clients.Add($current)
            }

            $current = [PSCustomObject]@{
                ClientId   = $matches[1]
                ClientName = $matches[2]
                ExcelRow   = $excelLine.ExcelRow
                RawLines   = @($line)
            }
            continue
        }

        if ($null -ne $current) {
            $current.RawLines += $line
        }
    }

    if ($null -ne $current) {
        [void]$clients.Add($current)
    }
    Write-Host "[EXCEL-REBUILD] Clients reconstruits: $($clients.Count)"
    Write-PlanningRebuildUiLog ("[EXCEL-REBUILD] Clients reconstruits: {0}" -f $clients.Count)

    $clientArr = @($clients.ToArray())
    $clientTotal = [Math]::Max(1, $clientArr.Count)
    $clientNum = 0
    foreach ($client in $clientArr) {
        $clientNum++
        $reportEvery = if ($clientTotal -le 40) { 1 } elseif ($clientTotal -le 200) { 5 } else { 10 }
        if ($clientNum -eq 1 -or $clientNum -eq $clientTotal -or ($clientNum % $reportEvery) -eq 0) {
            Write-PlanningExcelSubStep -SubStepIndex 4 -Status 'SubStepProgress' `
                -Detail ("Clients extraits : {0}/{1}" -f $clientNum, $clientTotal) `
                -SubRatio (0.35 + (0.10 * ($clientNum / $clientTotal)))
        }
        if ($rank -eq 1) { script:Write-PlanningArithOpProbe -Location 'Extract-ExcelOrder:excelRow' -Op 'add' -Left $client.ExcelRow -Right 0 }
        [void](Trace-ObjectArrayLeak -Value $rank -Name "OrderIndex" -Location "Extract-ExcelOrder.loop")
        [void]$items.Add([pscustomobject]@{
            OrderIndex    = $rank
            ExcelRow      = $client.ExcelRow
            Label         = $client.ClientName
            ClientId      = $client.ClientId
            RawLines      = @($client.RawLines)
            NormalizedKey = Normalize-ClientKey $client.ClientName
        })
        $rank++
    }

    $sw.Stop()
    $exMs = (ConvertTo-SafeLong -Value $sw.ElapsedMilliseconds -Name "ExcelRowsExtraction.Elapsed")
    Write-PlanningDebugLog -Message "STEP TIMING" -Level "DEBUG" -Data @{
        Step       = "ExcelRowsExtraction"
        DurationMs = $exMs
    }
    Write-PlanningDebugLog -Message "Excel rows extraction result" -Level "DEBUG" -Data @{
        RowsExtracted = $items.Count
    }

    if ($items.Count -gt 0) {
        $r0 = $items[0]
        script:Trace-ChirurgicalType -Value $r0.OrderIndex -Name 'rows[0].OrderIndex' -Location 'Extract-ExcelOrder:output'
        script:Trace-ChirurgicalType -Value $r0.ExcelRow -Name 'rows[0].ExcelRow' -Location 'Extract-ExcelOrder:output'
    }
    return @($items.ToArray())
}

function script:Add-ReorderedLineFromPageEntity {
    param(
        $OrderedList,
        [int]$Index,
        $PageEntity,
        $MatchObject,
        [string]$Source
    )
    $m = $MatchObject
    if ($Source -eq 'ExcelOrder' -and $null -ne $m) {
        [void](Trace-ObjectArrayLeak -Value $m.ExcelOrder -Name "ExcelOrder" -Location "Add-ReorderedLineFromPageEntity.match")
        $score = $m.MatchScore
        $sim = $m.Similarity
        $reason = $m.MatchReason
        $exOrd = if ($null -eq $m.ExcelOrder) { $null } else {
            (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $m.ExcelOrder -Name "AddLine.ExcelOrder") -Name "AddLine.ExcelSourceOrder")
        }
        $exLbl = $m.ExcelLabel
    }
    else {
        $score = 0; $sim = 0; $reason = 'PdfFallback'
        $exOrd = $null
        $exLbl = $null
    }
    [void](Trace-ObjectArrayLeak -Value $exOrd -Name "ExcelSourceOrder" -Location "Add-ReorderedLineFromPageEntity.exOrd")
    [void](Trace-ObjectArrayLeak -Value $PageEntity.PageNumber -Name "PageNumber" -Location "Add-ReorderedLineFromPageEntity.page")
    $pageNumLine = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $PageEntity.PageNumber -Name "AddLine.PageNumber") -Name "AddLine.PageNumber")
    [void]$OrderedList.Add([pscustomobject]@{
        FinalOrder        = $Index
        MatchScore        = $score
        Similarity        = $sim
        MatchReason       = $reason
        ClientID          = $PageEntity.ClientID
        ClientName        = $PageEntity.ClientName
        Address           = Get-EntityAddressText -Entity $PageEntity
        VisitDate         = $PageEntity.VisitDate
        Source            = $Source
        IsMatched         = ($Source -eq 'ExcelOrder')
        PageNumber        = $pageNumLine
        NormalizedKey     = $PageEntity.NormalizedKey
        ExcelSourceOrder  = $exOrd
        ExcelLabel        = $exLbl
    })
}

function script:Complete-ReorderedPlanningSequentialFinalOrder {
    param([object[]]$ReorderedLines)
    if ($null -eq $ReorderedLines -or @($ReorderedLines).Count -eq 0) { return @() }
    $out = [System.Collections.Generic.List[object]]::new()
    $ord = 1
    foreach ($line in @($ReorderedLines)) {
        if ($null -eq $line) { continue }
        $line | Add-Member -NotePropertyName FinalOrder -NotePropertyValue $ord -Force
        [void]$out.Add($line)
        $ord++
    }
    return @($out.ToArray())
}

function Build-ReorderedPlanning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$MatchResult,
        [Parameter(Mandatory = $true)]
        [object[]]$PdfEntities
    )

    Trace-DeepObjectLeak -Value $MatchResult -Name "MatchResult" -Location "Build-ReorderedPlanning.param"
    Trace-DeepObjectLeak -Value $PdfEntities -Name "PdfEntities" -Location "Build-ReorderedPlanning.param"
    $byPage = @{}
    foreach ($e in @($PdfEntities)) {
        if ($null -eq $e) { continue }
        [void](Trace-ObjectArrayLeak -Value $e.PageNumber -Name "PageNumber" -Location "BuildReordered.loop")
        [void](script:Trace-ChirurgicalType -Value $e.PageNumber -Name 'PdfEntity.PageNumber' -Location 'Build-ReorderedPlanning:byPage')
        $pn = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $e.PageNumber -Name "BuildReordered.byPage.pn") -Name "BuildReordered.byPage.pn")
        $byPage[$pn] = $e
    }

    $matchedLines = [System.Collections.Generic.List[object]]::new()
    Trace-DeepObjectLeak -Value $matchedLines -Name "ordered" -Location "Build-ReorderedPlanning.assign"
    $matchedPageNums = [System.Collections.Generic.HashSet[int]]::new()

    $matchesForReorder = @(
        foreach ($_ in @($MatchResult.Matches)) {
            if ($null -eq $_) { continue }
            [void](Trace-ObjectArrayLeak -Value $_.PageNumber -Name "PageNumber" -Location "BeforeSort:BuildReordered.mMatches")
            [void](Trace-ObjectArrayLeak -Value $_.ExcelOrder -Name "ExcelOrder" -Location "BeforeSort:BuildReordered.mMatches")
            [void](Trace-ObjectArrayLeak -Value $_.ExcelSourceOrder -Name "ExcelSourceOrder" -Location "BeforeSort:BuildReordered.mMatches")
            [void](Trace-ObjectArrayLeak -Value $_.ExcelOrder -Name "ExcelOrder" -Location "Sort.ExcelOrder.BuildReordered")
            $_
        }
    )
    $sortedMatchRows = @( script:Sort-PlanningMatchResultRows -InputObject $matchesForReorder )

    foreach ($m in $sortedMatchRows) {
        Trace-DeepObjectLeak -Value $m -Name "dto" -Location "Build-ReorderedPlanning.foreachMatch"
        [void](Trace-ObjectArrayLeak -Value $m.ExcelOrder -Name "ExcelOrder" -Location "BuildReordered.loop")
        if ($null -ne $m.PSObject.Properties['WorkOrder'] -and $null -ne $m.WorkOrder) {
            $wo = $m.WorkOrder
            Trace-DeepObjectLeak -Value $wo -Name "WorkOrder" -Location "Build-ReorderedPlanning.assign.wo"
            [void](script:Trace-ChirurgicalType -Value $wo.Pages -Name 'WorkOrder.Pages' -Location 'Build-ReorderedPlanning:workOrder')
            $pageNums = @(
                $wo.Pages | ForEach-Object {
                    (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $_ -Name "BuildReordered.wo.Pages.item") -Name "BuildReordered.wo.Page")
                } | ForEach-Object {
                    [pscustomobject]@{ __SortPageValue = $_ }
                } | Sort-Safe -Property '__SortPageValue' -KeyType Int | ForEach-Object {
                    $_.__SortPageValue
                }
            )
            foreach ($p in $pageNums) {
                $pe = $byPage[$p]
                if ($null -eq $pe) { continue }
                [void]$matchedPageNums.Add([int]$p)
                Add-ReorderedLineFromPageEntity -OrderedList $matchedLines -Index ($matchedLines.Count + 1) -PageEntity $pe -MatchObject $m -Source 'ExcelOrder'
            }
        }
        else {
            $entity = $m.Entity
            if ($null -eq $entity) { continue }
            $entPn = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $entity.PageNumber -Name "BuildReordered.mEntity.PageNumber") -Name "BuildReordered.mEntity.PageNumber.Int")
            [void]$matchedPageNums.Add($entPn)
            Add-ReorderedLineFromPageEntity -OrderedList $matchedLines -Index ($matchedLines.Count + 1) -PageEntity $entity -MatchObject $m -Source 'ExcelOrder'
        }
    }

    $unmatchedLines = [System.Collections.Generic.List[object]]::new()
    $byPageKeyInts = foreach ($bk in @($byPage.Keys)) {
        ConvertTo-SafeInt -Value (Normalize-Scalar -Value $bk -Name "BuildReordered.byPage.Keys") -Name "BuildReordered.byPage.Keys.Int"
    }
    $allPdfSorted = @($byPageKeyInts | Sort-Object -Unique | Sort-Object)
    foreach ($pnUm in @($allPdfSorted)) {
        $pnUmI = [int]$pnUm
        if ($matchedPageNums.Contains($pnUmI)) { continue }

        $peUm = $null
        foreach ($mapKey in @($byPage.Keys)) {
            $kn = ConvertTo-SafeInt -Value (Normalize-Scalar -Value $mapKey -Name 'BuildReorder.mapKeyPn') -Name 'BuildReorder.mapKeyPn.Int'
            if ($kn -eq $pnUmI) {
                $peUm = $byPage[$mapKey]
                break
            }
        }
        if ($null -eq $peUm) { continue }

        Add-ReorderedLineFromPageEntity -OrderedList $unmatchedLines -Index ($unmatchedLines.Count + 1) -PageEntity $peUm -MatchObject $null -Source 'PdfFallback'
    }

    Write-Host ("[UNMATCHED] Count = {0}" -f $unmatchedLines.Count)
    Write-Host ("[MATCHED] Count = {0}" -f $matchedLines.Count)
    Write-Host "[FINAL ORDER] Unmatched first applied"

    $combined = [System.Collections.Generic.List[object]]::new()
    foreach ($ulu in @($unmatchedLines)) { [void]$combined.Add($ulu) }
    foreach ($mli in @($matchedLines)) { [void]$combined.Add($mli) }

    if ($combined.Count -gt 0) {
        $l0 = $combined[0]
        [void](script:Trace-ChirurgicalType -Value $l0.ExcelSourceOrder -Name 'line.ExcelSourceOrder' -Location 'Build-ReorderedPlanning:ordered[0]')
    }
    return (script:Complete-ReorderedPlanningSequentialFinalOrder -ReorderedLines @($combined.ToArray()))
}

function Get-OdmPlanningOutputPdfLeafName {
    <#
    .SYNOPSIS
        Nom de fichier planning final : ODM_Mardi_23_Avril_2026.pdf (culture fr-FR, date de collecte ODM).
    #>
    param([AllowNull()][datetime]$VisitDate)

    $dt = if ($null -ne $VisitDate) { $VisitDate.Date } else { (Get-Date).Date }
    $fr = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')

    [string]$dayName = $dt.ToString('dddd', $fr)
    if ($dayName.Length -ge 1) {
        $dayName = $dayName.Substring(0, 1).ToUpper() + $dayName.Substring(1)
    }

    [string]$monthName = $dt.ToString('MMMM', $fr)
    if ($monthName.Length -ge 1) {
        $monthName = $monthName.Substring(0, 1).ToUpper() + $monthName.Substring(1)
    }

    $leaf = ('ODM_{0}_{1}_{2}_{3}.pdf' -f $dayName, $dt.Day, $monthName, $dt.Year)

    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $leaf.ToCharArray()) {
        if ($invalid -contains $ch) {
            [void]$sb.Append('_')
        }
        else {
            [void]$sb.Append($ch)
        }
    }
    $safe = $sb.ToString()
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return 'ODM.pdf'
    }
    return $safe
}

function Get-PlanningRebuildStepPercent {
    param(
        [int]$StepIndex,
        [int]$StepCount,
        [double]$SubRatio = 0
    )
    if ($StepCount -lt 1) { $StepCount = 5 }
    if ($StepIndex -lt 1) { return 0 }
    # Poids globaux (total 100) : STEP 1=15, 2=20, 3=5, 4=25, 5=35
    $stepWeights = @(15, 20, 5, 25, 35)
    if ($StepIndex -gt $stepWeights.Count) {
        $StepIndex = $stepWeights.Count
    }
    $base = 0.0
    for ($wi = 0; $wi -lt ($StepIndex - 1); $wi++) {
        $base += [double]$stepWeights[$wi]
    }
    $span = [double]$stepWeights[$StepIndex - 1]
    $ratio = [Math]::Max(0.0, [Math]::Min(1.0, $SubRatio))
    return [int][Math]::Min(100, [Math]::Max(0, [Math]::Round($base + ($ratio * $span))))
}

function ConvertTo-PlanningExcelColumnLetter {
    param([int]$ColumnIndexOneBased)
    if ($ColumnIndexOneBased -lt 1) { return '?' }
    $n = $ColumnIndexOneBased
    $letters = ''
    while ($n -gt 0) {
        $rem = ($n - 1) % 26
        $letters = [char](65 + $rem) + $letters
        $n = [int](($n - 1) / 26)
    }
    return $letters
}

function Write-PlanningExcelSubStep {
    param(
        [Parameter(Mandatory = $true)][int]$SubStepIndex,
        [string]$Title = $null,
        [Parameter(Mandatory = $true)][ValidateSet('SubStepStart', 'SubStepProgress', 'SubStepEnd', 'SubStepError')]
        [string]$Status,
        [string]$Detail = $null,
        [double]$SubRatio = 0
    )
    if ($null -eq $script:PlanningRebuildProgressCallback) { return }
    $subStepTitle = if (-not [string]::IsNullOrWhiteSpace($Title)) { $Title.TrimEnd('.') } else { $null }
    if ($Status -in @('SubStepProgress', 'SubStepEnd') -and (Get-Command Update-PlanningRebuildStepProgress -ErrorAction SilentlyContinue)) {
        $runDetail = if (-not [string]::IsNullOrWhiteSpace($Detail)) { [string]$Detail } else { $subStepTitle }
        Update-PlanningRebuildStepProgress -StepIndex 2 -StepCount 5 -Label 'Lecture Excel + matching' `
            -Status 'Running' -Detail $runDetail -SubRatio $SubRatio
    }
    Write-PlanningRebuildProgress -ProgressCallback $script:PlanningRebuildProgressCallback `
        -StepIndex 2 -StepCount 5 -Label 'Lecture Excel + matching' -Status $Status `
        -SubStep $subStepTitle -Detail $Detail -SubStepIndex $SubStepIndex -SubStepCount 8 `
        -Percent (Get-PlanningRebuildStepPercent -StepIndex 2 -StepCount 5 -SubRatio $SubRatio)
}

function Update-PlanningRebuildStepProgress {
    param(
        [int]$StepIndex,
        [int]$StepCount = 5,
        [string]$Label,
        [Parameter(Mandatory = $true)][ValidateSet('Running', 'OK', 'Error', 'SubRunning', 'SubOK', 'SubError', 'TourRunning', 'TourInfo')]
        [string]$Status,
        [string]$Detail = $null,
        [double]$SubRatio = 0,
        [string]$SubStep = $null,
        [int]$SubStepIndex = 0,
        [int]$SubStepCount = 0
    )
    if ($null -eq $script:PlanningRebuildProgressCallback) { return }
    $pct = Get-PlanningRebuildStepPercent -StepIndex $StepIndex -StepCount $StepCount -SubRatio $SubRatio
    if ($Status -eq 'OK') { $pct = Get-PlanningRebuildStepPercent -StepIndex $StepIndex -StepCount $StepCount -SubRatio 1.0 }
    Write-PlanningRebuildProgress -ProgressCallback $script:PlanningRebuildProgressCallback `
        -StepIndex $StepIndex -StepCount $StepCount -Label $Label -Status $Status -Detail $Detail -Percent $pct `
        -SubStep $SubStep -SubStepIndex $SubStepIndex -SubStepCount $SubStepCount
}

function Write-PlanningRebuildProgress {
    param(
        [AllowNull()][scriptblock]$ProgressCallback,
        [int]$StepIndex = 0,
        [int]$StepCount = 5,
        [string]$Label = '',
        [Parameter(Mandatory = $true)][ValidateSet('Running', 'OK', 'Error', 'Log', 'SubRunning', 'SubOK', 'SubError', 'SubStepStart', 'SubStepProgress', 'SubStepEnd', 'SubStepError', 'TourRunning', 'TourInfo', 'TreeLine', 'TourneeStart', 'TourneeProgress', 'TourneeEnd', 'Complete')]
        [string]$Status,
        [string]$Detail = $null,
        [int]$Percent = -1,
        [string]$SubStep = $null,
        [int]$SubStepIndex = 0,
        [int]$SubStepCount = 0,
        [string]$TreePrefix = $null,
        [string]$OutputPath = $null
    )
    if ($null -eq $ProgressCallback) { return }
    try {
        & $ProgressCallback @{
            StepIndex     = $StepIndex
            StepCount     = $StepCount
            Label         = $Label
            Status        = $Status
            Detail        = $Detail
            Percent       = $Percent
            SubStep       = $SubStep
            SubStepIndex  = $SubStepIndex
            SubStepCount  = $SubStepCount
            TreePrefix    = $TreePrefix
            OutputPath    = $OutputPath
        }
    }
    catch {
        Write-Warning ("[PLANNING-UI] ProgressCallback echoue : {0}" -f $_.Exception.Message)
    }
}

function Write-PlanningRebuildUiLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Detail
    )
    if ([string]::IsNullOrWhiteSpace($Detail)) { return }
    if ($null -eq $script:PlanningRebuildProgressCallback) { return }
    Write-PlanningRebuildProgress -ProgressCallback $script:PlanningRebuildProgressCallback -Status 'Log' -Detail $Detail
}

function Start-PlanningRebuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PdfPath,
        [Parameter(Mandatory = $true)]
        [string]$ExcelPath,
        [scriptblock]$ProgressCallback = $null
    )

    if ($true -eq $script:PlanningPipelineRunning) {
        Write-Host "[DEBUG] Start-PlanningRebuild : pipeline deja actif (reentrance) - ignore" -ForegroundColor DarkYellow
        return $null
    }
    $script:PlanningPipelineRunning = $true
    $script:PlanningRebuildProgressCallback = $ProgressCallback
    $script:PlanningRebuildLastError = $null
    $script:PlanningTourneeBlockTotal = 0
    Reset-PlanningRebuildStop
    $savedProgressPref = $ProgressPreference
    $savedVerbosePref = $VerbosePreference
    if ($env:CN_DEBUG_PIPELINE -notin @('1', 'true')) {
        $ProgressPreference = 'SilentlyContinue'
        $VerbosePreference = 'SilentlyContinue'
    }
    try {
    if (script:Test-CnChirurgicalTrace) { $script:ChirurgicalLeakLogged = $false }
    if (script:Test-CnObjectTrace) { $script:ObjectArrayLeakLogged = $false }
    if (script:Test-CnObjectTrace) { $script:SortExprLeakLogged = $false }
    if (script:Test-CnObjectTrace) { $script:SortPropLeakLogged = $false }
    if (script:Test-CnObjectTrace) { $script:TypeLeakLogged = $false }
    if ($env:CN_DEEP_OBJECT_TRACE -in @('1', 'true')) { $script:DeepLeakLogged = $false }
    $script:ArithLeakLogged = $false
    if ($env:CN_ARITH_HARD_TRACE -in @('1', 'true')) { $script:ArithHardLeakLogged = $false }
    if (Test-CnPipelineDebug) { Write-Host "[DEBUG] ENTER Start-PlanningRebuild (core)" -ForegroundColor DarkCyan }
    Write-Host "=== Planning rebuild start ===" -ForegroundColor Cyan
    Write-PlanningRebuildUiLog '=== Planning rebuild start ==='
    $planningStepTotal = 5
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log "[PlanningRebuilder] Start" "INFO" @{ pdf = $PdfPath; excel = $ExcelPath }
    }
    Write-PlanningDebugLog -Message "PlanningRebuilder - INPUT RECEIVED" -Level "DEBUG" -Data @{
        PdfPath   = $PdfPath
        ExcelPath = $ExcelPath
    }

    $pdftotextPath = $null
    try {
        $pdftotextPath = Resolve-PdfTotextPath
    }
    catch {
        $pdftotextPath = $null
    }
    if ([string]::IsNullOrWhiteSpace($pdftotextPath)) {
        $pdftotextMsg = @'
[PLANNING] pdftotext.exe introuvable — verifiez runtime\poppler\ dans l''installation, reconstruisez le package, ou definissez PDFTOTEXT_PATH.
'@
        script:Write-PlanningLog -Message $pdftotextMsg -Level 'ERROR'
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log $pdftotextMsg 'ERROR'
        }
        $script:PlanningRebuildLastError = $pdftotextMsg
        Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 1 -StepCount $planningStepTotal -Label 'Extraction PDF' -Status 'Error'
        return $null
    }
    script:Write-PlanningLog -Message ("[PLANNING] pdftotext : {0}" -f $pdftotextPath) -Level 'INFO'

    $pipelineTimingSw = [System.Diagnostics.Stopwatch]::StartNew()
    $stepTimingSw = [System.Diagnostics.Stopwatch]::StartNew()
    $script:PlanningPipelineStepMs = @{ 1 = 0; 2 = 0; 3 = 0; 4 = 0; 5 = 0 }
    $pdfRawLinesByPage = @{}

    script:Write-PlanningLog -Message "[PIPELINE] STEP 1: Extraction PDF" -Level 'INFO'
    $stepTimingSw.Restart()
    if (Test-PlanningRebuildStopRequested) { return $null }
    Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 1 -StepCount $planningStepTotal -Label 'Extraction PDF' -Status 'Running' -Percent 0
    $pdfExtractProgressCb = {
        param([int]$PageNumber, [int]$TotalPages, [string]$Detail = $null)
        if ($TotalPages -lt 1) { return }
        if ([string]::IsNullOrWhiteSpace($Detail)) {
            $Detail = ("pages extraites : {0}/{1}" -f $PageNumber, $TotalPages)
        }
        $ratio = [double]$PageNumber / [double]$TotalPages
        Update-PlanningRebuildStepProgress -StepIndex 1 -StepCount $planningStepTotal -Label 'Extraction PDF' -Status 'Running' `
            -Detail $Detail -SubRatio $ratio
    }
    $pdfData = $null
    try {
        $pdfData = Invoke-PdfExtraction -PdfPath $PdfPath -ProgressCallback $pdfExtractProgressCb
    } catch {
        script:Write-PlanningLog -Message ("[ERROR] Extraction PDF echouee : {0}" -f $_.Exception.Message) -Level 'ERROR'
        Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 1 -StepCount $planningStepTotal -Label 'Extraction PDF' -Status 'Error'
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log "[PlanningRebuilder] Extraction" "ERROR" $_.Exception.Message
        }
        return $null
    }
    if ($null -eq $pdfData) {
        script:Write-PlanningLog -Message '[ERROR] Extraction PDF : resultat nul' -Level 'ERROR'
        Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 1 -StepCount $planningStepTotal -Label 'Extraction PDF' -Status 'Error'
        return $null
    }
    if ($null -eq $pdfData.Pages -or @($pdfData.Pages).Count -eq 0) {
        script:Write-PlanningLog -Message '[ERROR] Extraction PDF : aucune page' -Level 'ERROR'
        Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 1 -StepCount $planningStepTotal -Label 'Extraction PDF' -Status 'Error'
        return $null
    }
    if ($pdfData.PdfTextUnusable -and $pdfData.UserAbortMessage) {
        script:Write-PlanningLog -Message ("[ERROR] {0}" -f $pdfData.UserAbortMessage) -Level 'ERROR'
        Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 1 -StepCount $planningStepTotal -Label 'Extraction PDF' -Status 'Error'
        return $null
    }
    if (Test-CnPipelineDebug) {
        foreach ($dm in @($pdfData.DiagnosticsMessages)) {
            if (-not [string]::IsNullOrWhiteSpace($dm)) { Write-Host "  [PIPELINE][DBG] $dm" -ForegroundColor DarkGray }
        }
    }

    $pdfEntitiesBag = @()
    Trace-DeepObjectLeak -Value $pdfEntitiesBag -Name "PdfEntities" -Location "Start-PlanningRebuild.init.pdfEntities"
    $pdfEntitiesList = [System.Collections.Generic.List[object]]::new()
    foreach ($page in @($pdfData.Pages)) {
        $cnLines = @()
        if ($null -ne $page -and $page.PSObject.Properties['ClientNameLines'] -and $null -ne $page.ClientNameLines) {
            $cnLines = @($page.ClientNameLines)
        }
        $entity = ConvertTo-PageEntity -PageNumber $page.PageNumber -Lines @($page.Lines) -ClientNameLines $cnLines
        if ($null -ne $entity) {
            $entity | Add-Member -NotePropertyName NormalizedKey -NotePropertyValue (Normalize-ClientKey $entity) -Force
            [void]$pdfEntitiesList.Add($entity)
        }
    }
    $pdfEntities = $pdfEntitiesList.ToArray()
    Trace-DeepObjectLeak -Value $pdfEntities -Name "PdfEntities" -Location "Start-PlanningRebuild.afterPageEntityLoop.pdfEntities"

    foreach ($page in @($pdfData.Pages)) {
        if ($null -eq $page) { continue }
        try {
            $pnRaw = [int]$page.PageNumber
        }
        catch { continue }
        if ($pnRaw -lt 1) { continue }
        $rawLines = @()
        if ($page.PSObject.Properties['RawLines'] -and $null -ne $page.RawLines) {
            $rawLines = @($page.RawLines)
        }
        elseif ($page.PSObject.Properties['Lines'] -and $null -ne $page.Lines) {
            $rawLines = @($page.Lines)
        }
        if ($rawLines.Count -gt 0) {
            $pdfRawLinesByPage[$pnRaw] = $rawLines
        }
    }

    Write-PlanningDebugLog -Message "Extracting VisitDate from PDF" -Level "DEBUG"
    $visitDate = Get-VisitDateFromEntities -PdfEntities $pdfEntities
    $sourceInfo = 'NONE'
    if ($null -ne $visitDate) {
        foreach ($entity in @($pdfEntities)) {
            if ($null -eq $entity) { continue }
            if ($null -ne $entity.VisitDate) { $sourceInfo = "Entity.Page=$($entity.PageNumber).VisitDate"; break }
            if ($null -ne $entity.Date) {
                try {
                    $tmpDate = [datetime]$entity.Date
                    if ($tmpDate -eq $visitDate) { $sourceInfo = "Entity.Page=$($entity.PageNumber).Date"; break }
                }
                catch { }
            }
        }
    }
    $visitNorm = Normalize-Date -InputValue $visitDate
    Write-PlanningDebugLog -Message "PDF VisitDate result" -Level "DEBUG" -Data @{
        VisitDate = $(if ($null -ne $visitDate) { $visitDate.ToString('yyyy-MM-dd') } else { $null })
        Normalized = $visitNorm
        Source    = $sourceInfo
    }
    if (-not $visitDate) {
        Write-PlanningDebugLog -Message "VisitDate is NULL -> fallback risk" -Level "WARN"
    }
    if ($null -eq $visitDate) {
        script:Write-PlanningLog -Message '[ERROR] Aucune VisitDate detectee dans le PDF (pipeline arrete)' -Level 'ERROR'
        Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 1 -StepCount $planningStepTotal -Label 'Extraction PDF' -Status 'Error'
        return $null
    }
    $extractedPageCount = @($pdfData.Pages).Count
    $script:PlanningPipelineStepMs[1] = $stepTimingSw.ElapsedMilliseconds
    Write-PlanningPipelineStepTiming -StepIndex 1 -Label 'Extraction PDF' -DurationMs $script:PlanningPipelineStepMs[1] `
        -Detail ("{0} pages" -f $extractedPageCount)
    Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 1 -StepCount $planningStepTotal -Label 'Extraction PDF' -Status 'OK' `
        -Detail ("({0} pages extraites)" -f $extractedPageCount) -Percent (Get-PlanningRebuildStepPercent -StepIndex 1 -StepCount $planningStepTotal -SubRatio 1.0)

    if (Test-PlanningRebuildStopRequested) { return $null }

    script:Write-PlanningLog -Message "[PIPELINE] STEP 2: Lecture Excel + matching" -Level 'INFO'
    $stepTimingSw.Restart()
    $script:ClientIdPipelineStatus = 'PASS'
    $script:ClientIdMatcherStatus = 'FAIL'
    $excelData = $null
    $column = $null
    $excelOrder = $null
    Trace-DeepObjectLeak -Value $excelOrder -Name "excelOrder" -Location "Start-PlanningRebuild.init"
    try {
        Write-PlanningExcelSubStep -SubStepIndex 1 -Title 'Verification du fichier Excel' -Status 'SubStepStart' -SubRatio 0.05
        if (Get-Command Test-ExcelFileIntegrity -ErrorAction SilentlyContinue) {
            $excelIntegrity = Test-ExcelFileIntegrity -Path $ExcelPath
            if (-not $excelIntegrity.IsValid) {
                $integrityErr = if ($null -ne $excelIntegrity.Error) { [string]$excelIntegrity.Error } else { 'fichier invalide' }
                throw "[ExcelLoader] Fichier structurellement invalide: $integrityErr"
            }
        }
        Write-PlanningExcelSubStep -SubStepIndex 1 -Title 'Verification du fichier Excel' -Status 'SubStepEnd' -SubRatio 0.1

        Write-PlanningExcelSubStep -SubStepIndex 2 -Title 'Ouverture du classeur' -Status 'SubStepStart' -SubRatio 0.08
        $excelExt = [System.IO.Path]::GetExtension($ExcelPath).ToLowerInvariant()
        if ($excelExt -in @('.csv', '.tsv', '.txt')) {
            $excelData = Import-PlanningExcel -ExcelPath $ExcelPath
        }
        else {
            $targetWeek = Get-Iso8601WeekOfYear -Date $visitDate
            $sheetNames = @(Get-ExcelSheetNames -ExcelPath $ExcelPath)
            $targetSheetName = Get-PlanningExcelSheetNameForIsoWeek -SheetNames $sheetNames -Week $targetWeek
            if ([string]::IsNullOrWhiteSpace($targetSheetName)) {
                throw ("[EXCEL] Onglet semaine S{0} non trouve dans le fichier Excel ({1} feuille(s))." -f $targetWeek, @($sheetNames).Count)
            }
            Write-Host ("[EXCEL] Semaine cible S{0} - chargement onglet '{1}' uniquement" -f $targetWeek, $targetSheetName) -ForegroundColor Green
            $excelData = Import-PlanningExcelSheet -ExcelPath $ExcelPath -SheetName $targetSheetName
        }
        Write-PlanningExcelSubStep -SubStepIndex 2 -Title 'Ouverture du classeur' -Status 'SubStepEnd' -SubRatio 0.10

        Write-PlanningExcelSubStep -SubStepIndex 3 -Title 'Recherche de la colonne date' -Status 'SubStepStart' -SubRatio 0.15
        $column = Find-ExcelColumnFromDate -ExcelData $excelData -VisitDate $visitDate -ExcelPath $ExcelPath
        $colLetter = ConvertTo-PlanningExcelColumnLetter -ColumnIndexOneBased ([int]$column.ColumnIndex)
        $colHeader = [string]$column.HeaderText
        if ([string]::IsNullOrWhiteSpace($colHeader)) { $colHeader = '(sans en-tete)' }
        Write-PlanningExcelSubStep -SubStepIndex 3 -Title 'Recherche de la colonne date' -Status 'SubStepEnd' `
            -Detail ('(colonne {0}, en-tete "{1}")' -f $colLetter, $colHeader) -SubRatio 0.20

        Write-PlanningExcelSubStep -SubStepIndex 4 -Title 'Extraction des lignes clients' -Status 'SubStepStart' -SubRatio 0.35
        $excelOrder = Extract-ExcelOrder -ExcelData $excelData -ColumnInfo $column
        Trace-DeepObjectLeak -Value $excelOrder -Name "excelOrder" -Location "Start-PlanningRebuild.afterExtractExcelOrder"
        $clientCount = @($excelOrder).Count
        Write-PlanningExcelSubStep -SubStepIndex 4 -Title 'Extraction des lignes clients' -Status 'SubStepEnd' `
            -Detail ("({0} clients trouves)" -f $clientCount) -SubRatio 0.45

        Write-PlanningExcelSubStep -SubStepIndex 5 -Title 'Normalisation des textes' -Status 'SubStepStart' -SubRatio 0.48
        Write-PlanningExcelSubStep -SubStepIndex 5 -Title 'Normalisation des textes' -Status 'SubStepEnd' -SubRatio 0.52
    } catch {
        $errMsg = $_.Exception.Message
        $script:PlanningRebuildLastError = $errMsg
        script:Write-PlanningLog -Message ("[ERROR] Excel / colonne planning : {0}" -f $errMsg) -Level 'ERROR'
        Write-PlanningExcelSubStep -SubStepIndex 0 -Title 'Lecture Excel' -Status 'SubStepError' -Detail (": $errMsg")
        Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 2 -StepCount $planningStepTotal -Label 'Lecture Excel + matching' -Status 'Error' -Detail $errMsg
        return $null
    }
    $workOrders = @(ConvertTo-WorkOrderEntityList -PageEntities @($pdfEntities))
    Trace-DeepObjectLeak -Value $workOrders -Name "WorkOrder" -Location "Start-PlanningRebuild.afterConvertToWorkOrderEntityList"
    Write-Host ("[Planning] Groupes ODM (WorkOrder) : {0}" -f $workOrders.Count) -ForegroundColor DarkGray
    $clientIdDiag = $null
    try {
        $clientIdDiag = (Invoke-ClientIdMatchAudit -WorkOrders $workOrders -ExcelOrder $excelOrder)
    }
    catch {
        Write-Warning ("[CLIENTID-AUDIT] Non bloquant: {0}" -f $_.Exception.Message)
    }
    $woValidation = $null
    try {
        $woValidation = (Test-WorkOrderGroupIntegrity -WorkOrders $workOrders -PageEntities @($pdfEntities))
    }
    catch {
        Write-Warning ("[WO-ERROR] Validation non bloquante indisponible : {0}" -f $_.Exception.Message)
    }
    try {
        $match = Match-WorkOrderToExcelOrderSmart -WorkOrders $workOrders -ExcelOrder $excelOrder
    }
    catch {
        $errMsg = $_.Exception.Message
        $script:PlanningRebuildLastError = $errMsg
        Write-Log "[PLANNING-INNER-FAIL]" "ERROR" @{
            Context  = "Match"
            Message  = $errMsg
            Stack    = $_.ScriptStackTrace
            Position = $_.InvocationInfo.PositionMessage
        }
        Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 2 -StepCount $planningStepTotal -Label 'Lecture Excel + matching' -Status 'Error' -Detail $errMsg
        throw
    }
    if ($null -ne $match -and -not [string]::IsNullOrWhiteSpace([string]$match.Strategy)) {
        Write-PlanningRebuildUiLog ("[MATCHER] Strategie: {0}" -f $match.Strategy)
    }
    if ($null -ne $match -and @($match.Matches).Count -gt 0) {
        Write-PlanningRebuildUiLog ("[MATCHER] Apparies: {0}" -f @($match.Matches).Count)
    }
    $matchExact = 0
    $matchFuzzy = 0
    if ($null -ne $match) {
        foreach ($mx in @($match.Matches)) {
            if ($null -eq $mx) { continue }
            try {
                $sc = [int]$mx.MatchScore
                if ($sc -ge 100) { $matchExact++ }
                elseif ($sc -gt 0) { $matchFuzzy++ }
            }
            catch { }
        }
    }
    $matchMissing = if ($null -ne $match) { @($match.Missing).Count } else { 0 }
    Write-PlanningExcelSubStep -SubStepIndex 8 -Title 'Finalisation' -Status 'SubStepEnd' `
        -Detail ("({0} match exacts, {1} flous, {2} non-matches)" -f $matchExact, $matchFuzzy, $matchMissing) -SubRatio 1.0
    $script:PlanningPipelineStepMs[2] = $stepTimingSw.ElapsedMilliseconds
    Write-PlanningPipelineStepTiming -StepIndex 2 -Label 'Lecture Excel + matching' -DurationMs $script:PlanningPipelineStepMs[2] `
        -Detail ("{0} exacts, {1} flous, {2} non-matches" -f $matchExact, $matchFuzzy, $matchMissing)
    Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 2 -StepCount $planningStepTotal -Label 'Lecture Excel + matching' -Status 'OK' `
        -Detail ("({0} match exacts, {1} flous, {2} non-matches)" -f $matchExact, $matchFuzzy, $matchMissing) `
        -Percent (Get-PlanningRebuildStepPercent -StepIndex 2 -StepCount $planningStepTotal -SubRatio 1.0)
    if (Test-PlanningRebuildStopRequested) { return $null }
    Trace-DeepObjectLeak -Value $match -Name "MatchResult" -Location "Start-PlanningRebuild.afterMatch"
    if ($null -ne $match -and @($match.Matches).Count -gt 0) {
        $match.Matches = @(
            Sort-Safe -InputObject @(
                foreach ($mx in @($match.Matches)) {
                    if ($null -eq $mx) { continue }
                    [void](Trace-ObjectArrayLeak -Value $mx.ExcelOrder -Name "ExcelOrder" -Location "Start-PlanningRebuild.SortMatches.ExcelOrder")
                    $mx
                }
            ) -Property 'ExcelOrder' -KeyType Int
        )
    }
    if ($null -ne $clientIdDiag) {
        $diagExtraction = if ($clientIdDiag.ExcelExtractionStatus -eq 'PASS' -and $clientIdDiag.PdfExtractionStatus -eq 'PASS') { 'PASS' } else { 'FAIL' }
        $diagPipeline = if ([string]::IsNullOrWhiteSpace([string]$script:ClientIdPipelineStatus)) { 'PASS' } else { $script:ClientIdPipelineStatus }
        $diagMatcher = if ([string]::IsNullOrWhiteSpace([string]$script:ClientIdMatcherStatus)) { 'FAIL' } else { $script:ClientIdMatcherStatus }
        Write-Host ("[CLIENTID-DIAG-SUMMARY] Format={0} Extraction={1} Coverage={2} Pipeline={3} Matcher={4}" -f $clientIdDiag.FormatStatus, $diagExtraction, $clientIdDiag.CoverageStatus, $diagPipeline, $diagMatcher)
    }

    script:Write-PlanningLog -Message "[PIPELINE] STEP 3: Reordonnancement planning" -Level 'INFO'
    $stepTimingSw.Restart()
    if (Test-PlanningRebuildStopRequested) { return $null }
    Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 3 -StepCount $planningStepTotal -Label 'Reordonnancement planning' -Status 'Running' `
        -Percent (Get-PlanningRebuildStepPercent -StepIndex 3 -StepCount $planningStepTotal -SubRatio 0)
    Update-PlanningRebuildStepProgress -StepIndex 3 -StepCount $planningStepTotal -Label 'Reordonnancement planning' -Status 'Running' `
        -Detail 'Construction lignes planning' -SubRatio 0.33
    if ($null -ne $woValidation) {
        Write-PlanningRebuildUiLog ("[WO-SUMMARY] TotalWorkOrders={0} OK={1} WARN={2} ERROR={3}" -f $woValidation.TotalWorkOrders, $woValidation.OK, $woValidation.WARN, $woValidation.ERROR)
    }
    try {
        $reordered = Build-ReorderedPlanning -MatchResult $match -PdfEntities $pdfEntities
    }
    catch {
        Write-Log "[PLANNING-INNER-FAIL]" "ERROR" @{
            Context  = "Match"
            Message  = $_.Exception.Message
            Stack    = $_.ScriptStackTrace
            Position = $_.InvocationInfo.PositionMessage
        }
        Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 3 -StepCount $planningStepTotal -Label 'Reordonnancement planning' -Status 'Error'
        throw
    }
    Update-PlanningRebuildStepProgress -StepIndex 3 -StepCount $planningStepTotal -Label 'Reordonnancement planning' -Status 'Running' `
        -Detail 'Preparation mapping pages' -SubRatio 0.66
    if (Test-PlanningRebuildStopRequested) { return $null }
    Trace-DeepObjectLeak -Value $reordered -Name "ordered" -Location "Start-PlanningRebuild.afterBuildReorderedPlanning"
    Write-Host "[REORDERED-SNAPSHOT] Count=$($reordered.Count) NullCount=$(@($reordered | Where-Object { $_ -eq $null }).Count)"

    $newPlanningResult = {
        param($OutPdf)
        return [pscustomobject]@{
            VisitDate           = $visitDate
            ExcelColumn         = $column
            ExcelOrder          = $excelOrder
            MatchResult         = $match
            ReorderedPlanning   = $reordered
            OutputPdf             = $OutPdf
        }
    }
    if ($null -eq $reordered -or @($reordered).Count -eq 0) {
        script:Write-PlanningLog -Message '[ERROR] Aucun planning reordonne (mapping / entites vides)' -Level 'ERROR'
        Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 3 -StepCount $planningStepTotal -Label 'Reordonnancement planning' -Status 'Error'
        return ( & $newPlanningResult -OutPdf $null )
    }
    Write-PlanningDebugLog -Message "PlanningRebuilder RESULT" -Level "INFO" -Data @{
        PdfDate      = $visitDate.ToString('yyyy-MM-dd')
        ExcelColumn  = $column.HeaderText
        RowsExtracted = @($excelOrder).Count
    }

    Write-Host ("Colonne detectee: Onglet='{0}' Colonne={1} Header='{2}'" -f $column.SheetName, $column.ColumnIndex, $column.HeaderText) -ForegroundColor Cyan
    Write-Host ("Excel Order Count = {0}" -f @($excelOrder).Count) -ForegroundColor Cyan
    Write-Host ("PDF Count = {0}" -f @($pdfEntities).Count) -ForegroundColor Cyan
    if (@($excelOrder).Count -ne @($pdfEntities).Count) {
        Write-Host "WARNING: mismatch volume Excel/PDF" -ForegroundColor Yellow
    }
    Write-Host ("Strategie matching: {0}" -f $match.Strategy) -ForegroundColor Cyan
    Write-Host "Planning final :" -ForegroundColor Green
    foreach ($line in @($reordered)) {
        $tag = if ($line.MatchScore -ge 60) { 'OK' } elseif ($line.MatchScore -gt 0) { 'WARN' } else { 'MAP' }
        if ($line.MatchScore -gt 0) {
            Write-Host ("[{0} {1}] {2} -> {3}" -f $tag, $line.MatchScore, $line.FinalOrder, $line.ClientName)
        }
        else {
            $xlab = if ($line.PSObject.Properties['ExcelLabel'] -and -not [string]::IsNullOrWhiteSpace($line.ExcelLabel)) { $line.ExcelLabel } else { '—' }
            Write-Host ("[MAP {0}] {1} -> {2}" -f $line.FinalOrder, $xlab, $line.ClientName)
        }
    }
    Write-Host ("DEBUG non matches: {0}" -f @($match.Missing).Count) -ForegroundColor Yellow
    Write-Host ("DEBUG doublons: {0}" -f @($match.Duplicates).Count) -ForegroundColor Yellow

    $rr = 0
    foreach ($ln in @($reordered)) {
        if ($null -ne $ln -and (script:Test-IsLeakyValueForArith -V $ln.PageNumber)) {
            script:Write-PlanningArithOpProbe -Location "Start-PlanningRebuild:reordered[$rr].PageNumber" -Op 'source-check' -Left $ln.PageNumber -Right $null
            break
        }
        $rr++
    }

    $pdfRealPageCount = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $pdfData.PageCount -Name "StartPlanningRebuild.Pdf.PageCount") -Name "StartPlanningRebuild.Pdf.PageCount.Int")
    if ($pdfRealPageCount -lt 1) {
        $pdfRealPageCount = @($pdfData.Pages).Count
    }

    $sanitizeRowsReorder = [System.Collections.Generic.List[object]]::new()

    foreach ($item in @($reordered)) {
        if ($null -eq $item -or $item.PageNumber -eq $null) {
            continue
        }
        if (-not $item.PSObject) {
            continue
        }

        $pNum = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $item.PageNumber -Name "StartPlanningRebuild.reordered.PageNumber") -Name "StartPlanningRebuild.pageSanitize")
        if ($pNum -lt 1 -or $pNum -gt $pdfRealPageCount) { continue }

        $tOrdSan = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $item.FinalOrder -Name "pdfSanitize.FinalOrder") -Name "pdfSanitize.FinalOrder.Int")
        [void]$sanitizeRowsReorder.Add([pscustomobject]@{
                RawPageNum = $pNum
                FinalOrder = $tOrdSan
            })
    }

    $presentPhysReorder = New-Object System.Collections.Generic.HashSet[int]
    foreach ($sr in @($sanitizeRowsReorder)) {
        [void]$presentPhysReorder.Add([int]$sr.RawPageNum)
    }

    $missingPhysForGs = foreach ($pn in (1..$pdfRealPageCount)) {
        if (-not $presentPhysReorder.Contains($pn)) { $pn }
    }
    $missingPhysForGs = @($missingPhysForGs | Sort-Object)
    if ($missingPhysForGs.Count -gt 0) {
        Write-Host ("[SANITIZE] Pages PDF hors reorder (injectees en tête de liste GS) : {0}" -f ($missingPhysForGs -join ',')) -ForegroundColor DarkYellow
    }

    $mergedForSort = [System.Collections.Generic.List[object]]::new()
    $globalOrd = 0
    foreach ($hPn in @($missingPhysForGs)) {
        $globalOrd++
        $hI = [int]$hPn
        [void]$mergedForSort.Add([pscustomobject]@{
                RawPageNum = $hI
                FinalOrder = (-1000000 + $hI)
                Ordinal    = $globalOrd
            })
    }
    foreach ($sr in @($sanitizeRowsReorder)) {
        $globalOrd++
        [void]$mergedForSort.Add([pscustomobject]@{
                RawPageNum = [int]$sr.RawPageNum
                FinalOrder = [int]$sr.FinalOrder
                Ordinal    = $globalOrd
            })
    }

    Update-PlanningRebuildStepProgress -StepIndex 3 -StepCount $planningStepTotal -Label 'Reordonnancement planning' -Status 'Running' `
        -Detail 'Tri final' -SubRatio 1.0
    $sortedGsPairs = Sort-SafeTripleInt -InputObject @($mergedForSort.ToArray()) -P1 FinalOrder -P2 Ordinal -P3 RawPageNum
    $orderedPhysicalForGs = @($sortedGsPairs | ForEach-Object { [int]$_.RawPageNum })
    Trace-DeepObjectLeak -Value $orderedPhysicalForGs -Name "rows" -Location "Start-PlanningRebuild.afterForEach.orderedGs"

    $script:PlanningPipelineStepMs[3] = $stepTimingSw.ElapsedMilliseconds
    Write-PlanningPipelineStepTiming -StepIndex 3 -Label 'Reordonnancement planning' -DurationMs $script:PlanningPipelineStepMs[3] `
        -Detail ("{0} groupes ODM, {1} pages sequence" -f @($workOrders).Count, @($sortedGsPairs).Count)
    Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 3 -StepCount $planningStepTotal -Label 'Reordonnancement planning' -Status 'OK' `
        -Detail ("({0} groupes ODM, {1} pages sequence)" -f @($workOrders).Count, @($sortedGsPairs).Count) `
        -Percent (Get-PlanningRebuildStepPercent -StepIndex 3 -StepCount $planningStepTotal -SubRatio 1.0)
    if (Test-PlanningRebuildStopRequested) { return $null }

    Write-Host ("[VALIDATION] PDF reel pages: {0}" -f $pdfRealPageCount)
    Write-Host ("[VALIDATION] Lignes reorder (avec doublons): {0}" -f @($sanitizeRowsReorder).Count)
    Write-Host ("[VALIDATION] Sequence Ghostscript (occurrences): {0}" -f @($sortedGsPairs).Count)
    $distinctReferenced = @($sortedGsPairs | ForEach-Object { [int]$_.RawPageNum } | Sort-Object -Unique)
    Write-Host ("[VALIDATION] Pages PDF distinctes dans la sequence GS: {0}" -f $distinctReferenced.Count)
    if ($distinctReferenced.Count -gt $pdfRealPageCount) {
        throw 'CRITICAL ERROR: page overflow detected (distinct > reel)'
    }

    $pages = $orderedPhysicalForGs

    # Validations métier (PDF / planning corrects, pas seulement techniques)
    $strictBiz = $env:CN_PLANNING_STRICT -in @('1', 'true')
    $bizValidationFailed = $false

    if ($env:CN_DEBUG_PLANNING -in @('1', 'true')) {
        Write-Host "=== DEBUG COMPLET ===" -ForegroundColor Magenta
        $reordered | Format-Table -AutoSize PageNumber, FinalOrder, ClientName, MatchScore
    }

    $invalidMatches = @($reordered | Where-Object {
        if ($null -eq $_) { return $false }
        if ($_.Source -eq 'PdfFallback') {
            return $false
        }
        if ($null -eq $_.FinalOrder) { return $true }
        try { if ([int]$_.FinalOrder -lt 1) { return $true } } catch { return $true }
        if ($null -eq $_.ClientID) { return $true }
        $cids = [string]$_.ClientID
        if ([string]::IsNullOrWhiteSpace($cids)) { return $true }
        $false
    })
    if ($invalidMatches.Count -gt 0) {
        script:Write-PlanningLog -Message '[ERROR] Matching incomplet ou invalide' -Level 'ERROR'
        $invalidMatches | Format-Table -AutoSize PageNumber, ClientName, MatchScore, FinalOrder, Source
        $bizValidationFailed = $true
    }

    $matchedOrderIndices = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($m in @($match.Matches)) { if ($null -ne $m) { [void]$matchedOrderIndices.Add([int]$m.ExcelOrder) } }
    foreach ($ex in Sort-Safe -InputObject @($excelOrder) -Property OrderIndex) {
        if ($null -eq $ex) { continue }
        if (Is-ExcelLabelKeyless -Label $ex.Label) { continue }
        $idx = [int]$ex.OrderIndex
        if ($idx -lt 1) { continue }
        if ($matchedOrderIndices.Contains($idx)) { continue }
        $inMissing = $null -ne ($match.Missing | Where-Object { $null -ne $_ -and [int]$_.ExcelOrder -eq $idx } | Select-Object -First 1)
        if ($inMissing) { continue }
        script:Write-PlanningLog -Message ("[ERROR] Ligne Excel OrderIndex {0} ('{1}') : pas de match ni d'entree manquante declaree" -f $idx, $ex.Label) -Level 'ERROR'
        $bizValidationFailed = $true
    }

    $totalPdfPages = @($pdfData.Pages).Count
    # Couverture : voir [VALIDATION] (pages distinctes = reel apres injection des trous dans la sequence GS)

    $nRe = [int]@($reordered).Count
    $expectedOrder = if ($nRe -gt 0) { 1..$nRe } else { @() }
    $actualOrder = @($reordered | ForEach-Object { [int]$_.FinalOrder })
    if (@(Compare-Object -ReferenceObject $expectedOrder -DifferenceObject $actualOrder).Count -gt 0) {
        script:Write-PlanningLog -Message '[ERROR] Ordre final incohérent' -Level 'ERROR'
        script:Write-PlanningLog -Message ("[ERROR]   Attendu (1..n): {0}" -f ($expectedOrder -join ',')) -Level 'ERROR'
        script:Write-PlanningLog -Message ("[ERROR]   Obtenu: {0}" -f ($actualOrder -join ',')) -Level 'ERROR'
        $bizValidationFailed = $true
    }

    if ($strictBiz -and $bizValidationFailed) {
        script:Write-PlanningLog -Message '[ERROR] Validation metier echouee (CN_PLANNING_STRICT)' -Level 'ERROR'
        return ( & $newPlanningResult -OutPdf $null )
    }

    $outputPdfPath = $null
    $pageMapping = $null
    $pageIndexOffset = 0

    if ($pages.Count -gt 0) {
        try {
            $duplicates = @(
                $pages |
                    ForEach-Object {
                        $val = $_
                        [void](script:Trace-SortExprLeak -Value $val -Name "PageNumber" -Location "Start-PlanningRebuild.GroupObject")
                        $val
                    } |
                    Group-Object |
                    Where-Object { $_.Count -gt 1 }
            )
        }
        catch {
            Write-Log "[PLANNING-INNER-FAIL]" "ERROR" @{
                Context  = "Sort/Match/Key"
                Message  = $_.Exception.Message
                Stack    = $_.ScriptStackTrace
                Position = $_.InvocationInfo.PositionMessage
            }
            throw
        }
        Trace-DeepObjectLeak -Value $duplicates -Name "group" -Location "Start-PlanningRebuild.afterGroupObject.duplicates"
        if ($duplicates.Count -gt 0) {
            $dupLbl = @( $duplicates | ForEach-Object { "{0}x{1}" -f $_.Name, $_.Count } ) -join ', '
            Write-Host ("[WARN] Meme numero de page physique repete dans la sequence GS (intentionnel possible) : {0}" -f $dupLbl) -ForegroundColor Yellow
        }

        $pdx = 0
        foreach ($pe in @($pages)) {
            if (script:Test-IsLeakyValueForArith -V $pe) {
                script:Write-PlanningArithOpProbe -Location "Start-PlanningRebuild:pages[$pdx].pre-Get-SafeMax" -Op 'minmax' -Left $pe -Right $null
                break
            }
            $pdx++
        }
        $maxP = (Get-SafeMax -Values $pages -Name "pdf.pages.Get-SafeMax")
        if ($maxP -gt 0) {
            $expected = 1..$maxP
            $missing = @($expected | Where-Object { $_ -notin $pages })
            if ($missing.Count -gt 0) {
                Write-Host ("[WARN] Pages manquantes: {0}" -f ($missing -join ', ')) -ForegroundColor Yellow
            }
        }
    }

    if ($pages.Count -gt 0) {
        $pdy = 0
        foreach ($pe2 in @($pages)) {
            if (script:Test-IsLeakyValueForArith -V $pe2) {
                script:Write-PlanningArithOpProbe -Location "Start-PlanningRebuild:pages[$pdy].pre-Get-SafeMin" -Op 'minmax' -Left $pe2 -Right $null
                break
            }
            $pdy++
        }
        $minPg = (Get-SafeMin -Values $pages -Name "pdf.pages.Get-SafeMin")
        if ($minPg -lt 1) {
            script:Write-PlanningArithOpProbe -Location 'Start-PlanningRebuild:pageIndexOffset' -Op 'sub' -Left 1 -Right $minPg
            $pageIndexOffset = (Safe-Subtract -Left 1 -Right $minPg -Context "Start-PlanningRebuild.pageIndexOffset")
            Write-Host "[PDF] Ajustement index: PageNumber min=$minPg -> offset +$pageIndexOffset (attendu index PDF 1..N)" -ForegroundColor Yellow
        }
    }

    try {
        $outputLeaf = Get-OdmPlanningOutputPdfLeafName -VisitDate $visitDate
        $outputPdfPath = [System.IO.Path]::Combine(
            [System.IO.Path]::GetDirectoryName($PdfPath),
            $outputLeaf
        )

        $pageMapping = @{}
        $mapProbeOnce = $true
        foreach ($sp in @($sortedGsPairs)) {
            $pNum = [int]$sp.RawPageNum
            $pOff = (ConvertTo-SafeInt -Value $pageIndexOffset -Name "pageIndexOffset")
            if ($mapProbeOnce) {
                script:Write-PlanningArithOpProbe -Location 'Start-PlanningRebuild:pdfMap' -Op 'add' -Left $pNum -Right $pOff
                $mapProbeOnce = $false
            }
            Trace-ArithmeticLeak -Left $pNum -Right $pOff -Operation "add" -Location "Start-PlanningRebuild.pdfMap"
            $pg = $pNum + $pOff
            if ($pg -lt 1) { $pg = 1 }
            $tOrd = [int]$sp.FinalOrder
            $rOrd = [int]$sp.Ordinal
            $pageMapping[[int]$pg] = [PSCustomObject]@{
                Tournee = $tOrd
                Rang    = $rOrd
            }
        }

        Write-Host "[PDF] Occurrences sequence GS: $($orderedPhysicalForGs.Count)" -ForegroundColor Cyan
        Write-Host "[PDF] Entrees mapping (cle par page physique, derniere occurrence): $($pageMapping.Count)" -ForegroundColor Cyan
        Write-Host "[PDF] Output: $outputPdfPath" -ForegroundColor Cyan
        if (Test-CnPipelineDebug) {
            Write-Host "[PDF] Ordre final (debug)" -ForegroundColor Gray
            $reordered | Format-Table -AutoSize PageNumber, FinalOrder
        }

        if ($orderedPhysicalForGs.Count -lt 1) {
            script:Write-PlanningLog -Message '[ERROR] Sequence GS vide — generation PDF impossible' -Level 'ERROR'
            Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 4 -StepCount $planningStepTotal -Label 'Generation PDF' -Status 'Error'
            return ( & $newPlanningResult -OutPdf $null )
        }
        if (-not (Get-Command Reorganiser-PDF -ErrorAction SilentlyContinue)) {
            script:Write-PlanningLog -Message '[ERROR] Reorganiser-PDF indisponible (Core\PDFReorganizer.ps1 non charge)' -Level 'ERROR'
            Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 4 -StepCount $planningStepTotal -Label 'Generation PDF' -Status 'Error'
            return ( & $newPlanningResult -OutPdf $null )
        }

        script:Write-PlanningLog -Message "[PIPELINE] STEP 4: Generation PDF" -Level 'INFO'
        $stepTimingSw.Restart()
        if (Test-PlanningRebuildStopRequested) { return $null }
        Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 4 -StepCount $planningStepTotal -Label 'Generation PDF' -Status 'Running' `
            -Percent (Get-PlanningRebuildStepPercent -StepIndex 4 -StepCount $planningStepTotal -SubRatio 0)
        $pdfReorgProgressCb = {
            param([int]$CurrentBatch, [int]$TotalBatches, [int]$CurrentPage)
            if ($TotalBatches -lt 1) { return }
            $ratio = [double]$CurrentBatch / [double]$TotalBatches
            Update-PlanningRebuildStepProgress -StepIndex 4 -StepCount $planningStepTotal -Label 'Generation PDF' -Status 'Running' `
                -Detail ("lot {0}/{1}" -f $CurrentBatch, $TotalBatches) -SubRatio $ratio
        }
        # Rediriger stdout Ghostscript pour eviter la pollution du flux de retour du job
        $oldVerbose = $VerbosePreference
        $oldProgress = $ProgressPreference
        $VerbosePreference = 'SilentlyContinue'
        $ProgressPreference = 'SilentlyContinue'

        $reorgOutput = Reorganiser-PDF -SourcePDF $PdfPath -OutputPDF $outputPdfPath -Mapping $pageMapping -OrderedPhysicalPages $orderedPhysicalForGs -SourcePdfPageCountHint $pdfRealPageCount -ProgressCallback $pdfReorgProgressCb 2>&1

        $VerbosePreference = $oldVerbose
        $ProgressPreference = $oldProgress

        if ($reorgOutput -is [boolean]) {
            $ok = $reorgOutput
        }
        else {
            $ok = ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $outputPdfPath))
        }
        if (-not $ok) {
            script:Write-PlanningLog -Message '[ERROR] Generation PDF echouee (Reorganiser-PDF a retourne false)' -Level 'ERROR'
            Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 4 -StepCount $planningStepTotal -Label 'Generation PDF' -Status 'Error'
            Write-PlanningRebuildPdfDebug -PageMapping $pageMapping -Reordered $reordered
            return ( & $newPlanningResult -OutPdf $null )
        }
        if (-not (Test-Path -LiteralPath $outputPdfPath)) {
            script:Write-PlanningLog -Message '[ERROR] PDF absent apres generation (fichier introuvable)' -Level 'ERROR'
            Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 4 -StepCount $planningStepTotal -Label 'Generation PDF' -Status 'Error'
            Write-PlanningRebuildPdfDebug -PageMapping $pageMapping -Reordered $reordered
            return ( & $newPlanningResult -OutPdf $null )
        }
        $fileItem = Get-Item -LiteralPath $outputPdfPath
        $fileSize = $fileItem.Length
        if ($fileSize -lt 1000) {
            script:Write-PlanningLog -Message ("[ERROR] PDF trop petit ou corrompu ({0} octets)" -f $fileSize) -Level 'ERROR'
            Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 4 -StepCount $planningStepTotal -Label 'Generation PDF' -Status 'Error'
            Write-PlanningRebuildPdfDebug -PageMapping $pageMapping -Reordered $reordered
            return ( & $newPlanningResult -OutPdf $null )
        }
        $script:PlanningPipelineStepMs[4] = $stepTimingSw.ElapsedMilliseconds
        Write-PlanningPipelineStepTiming -StepIndex 4 -Label 'Generation PDF' -DurationMs $script:PlanningPipelineStepMs[4] `
            -Detail ("{0} octets" -f $fileSize)
        Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 4 -StepCount $planningStepTotal -Label 'Generation PDF' -Status 'OK' `
            -Detail ("({0} octets)" -f $fileSize) -Percent (Get-PlanningRebuildStepPercent -StepIndex 4 -StepCount $planningStepTotal -SubRatio 1.0)
        if (Test-PlanningRebuildStopRequested) { return $null }
        script:Write-PlanningLog -Message ("[SUCCESS] PDF genere : {0} ({1} octets)" -f $outputPdfPath, $fileSize) -Level 'INFO'
        Write-PlanningRebuildUiLog ("[SUCCESS] PDF genere : {0}" -f $outputPdfPath)

        script:Write-PlanningLog -Message '[PIPELINE] STEP 5: Composition pages de garde tournées (+ page 1 globale)' -Level 'INFO'
        $stepTimingSw.Restart()
        if (Test-PlanningRebuildStopRequested) { return $null }
        $step5Env = $null
        if (Get-Command Test-PlanningStep5Environment -ErrorAction SilentlyContinue) {
            $step5Env = Test-PlanningStep5Environment
            if (-not $step5Env.Ok) {
                foreach ($issue in @($step5Env.Issues)) {
                    script:Write-PlanningLog -Message ("[PIPELINE] STEP 5 prerequis : {0}" -f $issue) -Level 'WARN'
                    Write-PlanningRebuildUiLog ("[ATTENTION] {0}" -f $issue)
                }
            }
        }
        Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 5 -StepCount $planningStepTotal -Label 'Composition pages de garde' -Status 'Running' `
            -Percent (Get-PlanningRebuildStepPercent -StepIndex 5 -StepCount $planningStepTotal -SubRatio 0)
        $script:PlanningTourneeBlockTotal = 0
        $script:PlanningTourneeGeneratedDocCount = 0
        $coverOk = $false
        if ($null -ne $step5Env -and -not $step5Env.Ok) {
            $script:PlanningRebuildLastError = ($step5Env.Issues -join ' ')
            Write-Warning ("[TOURNEE] Prerequis etape 5 non satisfaits — PDF brut conserve ({0} octets)." -f $fileSize)
        }
        elseif (Get-Command Invoke-PlanningTourneePdfCoverComposition -ErrorAction SilentlyContinue) {
            $coverOk = Invoke-PlanningTourneePdfCoverComposition -MainPdfPath $outputPdfPath `
                -SortedGsPairs @($sortedGsPairs) -Reordered @($reordered) -ExcelOrder @($excelOrder) `
                -ExcelData $excelData -ColumnInfo $column -VisitDate $visitDate -DeclaredPdfPageCount $pdfRealPageCount `
                -WorkOrders @($workOrders) -PdfEntities @($pdfEntities) -MatchResult $match -ProgressCallback $ProgressCallback `
                -PdfRawLinesByPage $pdfRawLinesByPage
            if (-not $coverOk) {
                $script:PlanningRebuildLastError = 'Composition des couvertures et templates echouee (Ghostscript, LibreOffice ou Excel, ou templates). Consultez src\Logs\app.log.'
                Write-Warning '[TOURNEE] La composition des couvertures a echoue — le fichier brut (sans pages de garde ni certificats) est conserve.'
                Write-PlanningRebuildUiLog '[ERREUR] Etape 5 incomplete — installez Ghostscript et LibreOffice ou Excel, puis relancez.'
            }
            else {
                $fileItem = Get-Item -LiteralPath $outputPdfPath
                $fileSize = $fileItem.Length
                script:Write-PlanningLog -Message ("[SUCCESS] PDF apres composition couvertures : {0} ({1} octets)" -f $outputPdfPath, $fileSize) -Level 'INFO'
                Write-PlanningRebuildUiLog ("[SUCCESS] PDF complet : {0} ({1:N0} octets)" -f $outputPdfPath, $fileSize)
            }
        }
        else {
            $script:PlanningRebuildLastError = 'PdfTourneeCoverComposer non charge.'
            script:Write-PlanningLog -Message '[PIPELINE] STEP 5: PdfTourneeCoverComposer non charge — couvertures ignorees.' -Level 'WARN'
        }
        $tourneeDoneDetail = if ($script:PlanningTourneeBlockTotal -gt 0) {
            ("({0} tournees traitees, {1} documents generes)" -f $script:PlanningTourneeBlockTotal, [int]$script:PlanningTourneeGeneratedDocCount)
        } else { $null }
        $step5PerfDetail = $null
        if ($null -ne $script:PlanningStep5Perf) {
            $p5 = $script:PlanningStep5Perf
            $step5PerfDetail = ("step5_gs_batch={0} step5_gs_page={1} step5_cea_step1={2} step5_cea_pdftotext={3}" -f `
                [int]$p5.GsBatchExtracts, [int]$p5.GsPageExtracts, [int]$p5.CeaFromStep1, [int]$p5.CeaPdftotextFallback)
        }
        $script:PlanningPipelineStepMs[5] = $stepTimingSw.ElapsedMilliseconds
        Write-PlanningPipelineStepTiming -StepIndex 5 -Label 'Composition pages de garde' -DurationMs $script:PlanningPipelineStepMs[5] -Detail $step5PerfDetail
        Write-PlanningPipelineTimingSummary -TotalMs $pipelineTimingSw.ElapsedMilliseconds -StepMs $script:PlanningPipelineStepMs -Step5Detail $step5PerfDetail
        $step5Status = if ($coverOk) { 'OK' } else { 'Error' }
        Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 5 -StepCount $planningStepTotal -Label 'Composition pages de garde' -Status $step5Status `
            -Detail $(if ($coverOk) { $tourneeDoneDetail } else { $script:PlanningRebuildLastError }) -Percent (Get-PlanningRebuildStepPercent -StepIndex 5 -StepCount $planningStepTotal -SubRatio 1.0)
        Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex 0 -StepCount 0 -Label 'Complete' -Status 'Complete' `
            -OutputPath $outputPdfPath -Percent 100
        Write-PlanningRebuildUiLog 'Traitement termine.'
        $script:PlanningTourneeBlockTotal = 0
    }
    catch {
        script:Write-PlanningLog -Message ("[ERROR] Erreur generation PDF : {0}" -f $_.Exception.Message) -Level 'ERROR'
        if ($null -ne $ProgressCallback) {
            $failedStep = 4
            if ($null -ne $outputPdfPath -and (Test-Path -LiteralPath $outputPdfPath)) { $failedStep = 5 }
            Write-PlanningRebuildProgress -ProgressCallback $ProgressCallback -StepIndex $failedStep -StepCount $planningStepTotal -Label $(if ($failedStep -eq 5) { 'Composition pages de garde' } else { 'Generation PDF' }) -Status 'Error'
        }
        Write-PlanningRebuildPdfDebug -PageMapping $pageMapping -Reordered $reordered
        return ( & $newPlanningResult -OutPdf $null )
    }

    $result = ( & $newPlanningResult -OutPdf $outputPdfPath )
    $qualityMetrics = $null
    if (Get-Command Invoke-QualityMonitor -ErrorAction SilentlyContinue) {
        try {
            $qualityMetrics = (Invoke-QualityMonitor -RunContext ([pscustomobject]@{
                WorkOrders          = @($workOrders)
                MatchResult         = $match
                ReorderedPlanning   = @($reordered)
                ExcelOrder          = @($excelOrder)
                PdfEntities         = @($pdfEntities)
                WorkOrderValidation = $woValidation
                OutputPdf           = $outputPdfPath
            }))
        }
        catch {
            Write-Warning ("[QUALITY-MONITOR] Non bloquant: {0}" -f $_.Exception.Message)
        }
        if ($null -ne $qualityMetrics) {
            Write-PlanningRebuildUiLog ("[QUALITY-MONITOR] RunScore={0} TotalWO={1} MatchedOK={2} WARN={3} ERROR={4}" -f $qualityMetrics.PipelineQualityScore, $qualityMetrics.TotalWorkOrders, $qualityMetrics.MatchedOK, $qualityMetrics.MatchedWARN, $qualityMetrics.MatchedERROR)
        }
    }
    if (Get-Command Invoke-RootCauseAnalysis -ErrorAction SilentlyContinue) {
        try {
            [void](Invoke-RootCauseAnalysis -RunContext ([pscustomobject]@{
                WorkOrders      = @($workOrders)
                MatchResult     = $match
                ExcelOrder      = @($excelOrder)
                PdfEntities     = @($pdfEntities)
                QualityMetrics  = $qualityMetrics
                OutputPdf       = $outputPdfPath
            }))
        }
        catch {
            Write-Warning ("[ROOT-CAUSE] Non bloquant: {0}" -f $_.Exception.Message)
        }
    }
    return $result
    }
    catch {
        Write-Log "[PLANNING-EXCEPTION]" "ERROR" @{
            Message  = $_.Exception.Message
            Type     = $_.Exception.GetType().FullName
            Stack    = $_.ScriptStackTrace
            Position = $_.InvocationInfo.PositionMessage
            Line     = $_.InvocationInfo.ScriptLineNumber
            Offset   = $_.InvocationInfo.OffsetInLine
            Script   = $_.InvocationInfo.ScriptName
        }
        throw
    }
    finally {
        $script:PlanningPipelineRunning = $false
        $script:PlanningRebuildProgressCallback = $null
        $ProgressPreference = $savedProgressPref
        $VerbosePreference = $savedVerbosePref
    }
}

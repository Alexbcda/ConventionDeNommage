# ============================================================
# GlobalMatchResolution.ps1
# Résolution globale des conflits sur MatchResult[] (1 ExcelRow ↔ 1 WorkOrder max).
# Aucune modification du matching Excel ; pas de recalcul de score (FinalScore = MatchScore retenu).
# Tie-break score égal : ODM > ClientID > VisitDate (via MatchedFields), puis WorkOrder, puis ExcelRowId.
# ============================================================

. (Join-Path $PSScriptRoot "..\Models\WorkOrderEntity.ps1")
. (Join-Path $PSScriptRoot "..\Models\MatchResult.ps1")
$_ss = Join-Path $PSScriptRoot '..\..\..\Common\SortSafe.ps1'
if (Test-Path -LiteralPath $_ss) { . $_ss }
# MatchResult doit précéder FinalAssignment (FinalAssignmentTrace référence MatchResult).
. (Join-Path $PSScriptRoot "..\Models\FinalAssignment.ps1")
$script:TypeLeakLogged = $false

function script:Trace-TypeLeak {
    param(
        $Value,
        [string]$Name,
        [string]$Location
    )
    if ($env:CN_OBJECT_TRACE -notin @('1', 'true')) { return $Value }
    if ($script:TypeLeakLogged) { return $Value }
    if ($Value -is [System.Object[]]) {
        $script:TypeLeakLogged = $true
        $count = [int]@($Value).Count
        $first = if ($count -gt 0) { $Value[0] } else { $null }
        $stack = (Get-PSCallStack | Select-Object -First 20 | Out-String)
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log ("[TYPE-LEAK] Name={0} Location={1} Type={2} Count={3} First={4} Stack={5}" -f $Name, $Location, $Value.GetType().FullName, $count, $first, $stack) "ERROR" $null
            Write-Log ("[SORT-EXPR-LEAK] Location={0} KeyType={1} Type={2} Count={3}" -f $Location, $Name, $Value.GetType().FullName, $count) "ERROR" $null
        }
    }
    return $Value
}

function script:Get-MatchResultTieBreakRank {
    <#
    Priorité déterministe pour égalité de MatchScore : ODM (4) > ClientID (2) > VisitDate (1).
    #>
    param([string[]]$MatchedFields)
    $rank = 0
    if ($null -eq $MatchedFields) { return 0 }
    foreach ($f in $MatchedFields) {
        switch ($f) {
            'ODM' { $rank += 4 }
            'ClientID' { $rank += 2 }
            'VisitDate' { $rank += 1 }
        }
    }
    return $rank
}

function script:Get-CompetingMatchResultsForEdge {
    param(
        [System.Collections.Generic.List[MatchResult]]$AllCandidates,
        [string]$WorkOrderKey,
        [string]$ExcelKey
    )
    $list = [System.Collections.Generic.List[MatchResult]]::new()
    foreach ($c in $AllCandidates) {
        if ($null -eq $c) { continue }
        if ($c.WorkOrder -ceq $WorkOrderKey -and ([string]$c.ExcelRowId) -ceq $ExcelKey) { continue }
        if ($c.WorkOrder -ceq $WorkOrderKey -or ([string]$c.ExcelRowId) -ceq $ExcelKey) {
            $list.Add($c)
        }
    }
    return @($list.ToArray())
}

function script:Get-WinnerDecisionReason {
    param(
        [MatchResult]$Winner,
        [MatchResult[]]$Competing
    )
    foreach ($c in $Competing) {
        if ($null -eq $c) { continue }
        if ($c.MatchScore -eq $Winner.MatchScore) {
            return 'WIN_TIEBREAK'
        }
    }
    return 'WIN_SCORE'
}

function script:New-FinalAssignment {
    param(
        [string]$WorkOrder,
        [object]$ExcelRowId,
        [int]$FinalScore,
        [bool]$ConflictResolved,
        [FinalAssignmentTrace]$Trace
    )
    $fa = [FinalAssignment]::new()
    $fa.WorkOrder = $WorkOrder
    $fa.ExcelRowId = $ExcelRowId
    $fa.FinalScore = $FinalScore
    $fa.ConflictResolved = $ConflictResolved
    $fa.Trace = $Trace
    return $fa
}

function script:Test-HasAlternateMatchOnSameAxis {
    param(
        [MatchResult[]]$AllMatches,
        [string]$WorkOrder,
        [object]$ExcelRowId
    )
    $excelKey = [string]$ExcelRowId
    foreach ($m in $AllMatches) {
        if ($null -eq $m) { continue }
        if ($m.WorkOrder -ceq $WorkOrder -and ([string]$m.ExcelRowId) -ceq $excelKey) { continue }
        if ($m.WorkOrder -ceq $WorkOrder -or ([string]$m.ExcelRowId) -ceq $excelKey) {
            return $true
        }
    }
    return $false
}

function Resolve-WorkOrderExcelFinalAssignments {
    <#
    .SYNOPSIS
    Résout globalement les conflits : une ligne Excel et un WorkOrder ne peuvent apparaître qu’une fois chacun.

    .DESCRIPTION
    Entrée : MatchResult[] (ex. Get-WorkOrderExcelMatchResults) et WorkOrderEntity[] (filtrage des WorkOrder connus).
    Tri déterministe des arêtes : -MatchScore, -TieBreak(ODM>ClientID>Date), WorkOrder croissant, ExcelRowId croissant.
    Glouton : première arête valide consomme ses deux nœuds ; les suivantes en conflit sont ignorées.
    FinalScore = MatchScore du résultat retenu (aucun recalcul).
    ConflictResolved = $true s’il existait au moins un autre MatchResult partageant le même WorkOrder ou le même ExcelRowId.
    Chaque FinalAssignment.Trace décrit la décision : WIN_SCORE (aucun concurrent même score sur les axes),
    WIN_TIEBREAK (égalité de score résolue par le tri), CompetingCandidates = autres MatchResult sur le même WO ou ExcelRowId.
    -Verbose : journalise sélections, REJECTED_CONFLICT (WO ou Excel déjà pris), et égalités résolues.

    .PARAMETER WorkOrderEntities
    Entités PDF ; seuls les MatchResult dont WorkOrder correspond à une entité (trim) sont pris en compte.

    .PARAMETER MatchResults
    Sortie brute du matching (scores inchangés).

    .OUTPUTS
    FinalAssignment[]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [WorkOrderEntity[]]$WorkOrderEntities,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [MatchResult[]]$MatchResults
    )

    $validWo = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($e in @($WorkOrderEntities | Where-Object { $null -ne $_ })) {
        $k = if ([string]::IsNullOrWhiteSpace($e.WorkOrder)) { '' } else { $e.WorkOrder.Trim() }
        [void]$validWo.Add($k)
    }

    $candidates = [System.Collections.Generic.List[MatchResult]]::new()
    foreach ($m in @($MatchResults | Where-Object { $null -ne $_ })) {
        if (-not $validWo.Contains($m.WorkOrder)) { continue }
        $candidates.Add($m)
    }

    $sorted = @(
        $candidates.ToArray() |
            Sort-Object `
                @{ Expression = { $k = - (Get-SortSafeKeyInt $_.MatchScore); [void](script:Trace-TypeLeak -Value $k -Name "MatchScore" -Location "GlobalMatchResolution.Sort.MatchScore"); $k }; Ascending = $true },
                @{ Expression = { $k = -(Get-MatchResultTieBreakRank -MatchedFields @($_.MatchedFields)); [void](script:Trace-TypeLeak -Value $k -Name "OrderIndex" -Location "GlobalMatchResolution.Sort.TieBreak"); $k }; Ascending = $true },
                @{ Expression = { $k = (Get-SortSafeKeyString $_.WorkOrder); [void](script:Trace-TypeLeak -Value $k -Name "WorkOrder" -Location "GlobalMatchResolution.Sort.WorkOrder"); $k }; Ascending = $true },
                @{ Expression = { $k = (Get-SortSafeKeyString $_.ExcelRowId); [void](script:Trace-TypeLeak -Value $k -Name "ExcelOrder" -Location "GlobalMatchResolution.Sort.ExcelRowId"); $k }; Ascending = $true }
    )

    $usedWorkOrder = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $usedExcel = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $out = [System.Collections.Generic.List[FinalAssignment]]::new()

    foreach ($m in $sorted) {
        $wk = $m.WorkOrder
        $ek = [string]$m.ExcelRowId
        if ($usedWorkOrder.Contains($wk)) {
            Write-Verbose "REJECTED_CONFLICT: WorkOrder='$wk' ExcelRowId='$ek' MatchScore=$($m.MatchScore) MatchedFields=$($m.MatchedFields -join ',') Reason=WORKORDER_ALREADY_ASSIGNED (conflit avec une affectation précédente sur ce WorkOrder)."
            continue
        }
        if ($usedExcel.Contains($ek)) {
            Write-Verbose "REJECTED_CONFLICT: WorkOrder='$wk' ExcelRowId='$ek' MatchScore=$($m.MatchScore) MatchedFields=$($m.MatchedFields -join ',') Reason=EXCEL_ROW_ALREADY_ASSIGNED (conflit avec une affectation précédente sur cette ligne Excel)."
            continue
        }

        [void]$usedWorkOrder.Add($wk)
        [void]$usedExcel.Add($ek)

        $tieRank = Get-MatchResultTieBreakRank -MatchedFields @($m.MatchedFields)
        $conflict = Test-HasAlternateMatchOnSameAxis -AllMatches $candidates.ToArray() -WorkOrder $wk -ExcelRowId $m.ExcelRowId

        $competing = @(Get-CompetingMatchResultsForEdge -AllCandidates $candidates -WorkOrderKey $wk -ExcelKey $ek)
        $decisionReason = Get-WinnerDecisionReason -Winner $m -Competing $competing

        $trace = [FinalAssignmentTrace]::new()
        $trace.WorkOrder = $wk
        $trace.ExcelRowId = $m.ExcelRowId
        $trace.DecisionReason = $decisionReason
        $trace.CompetingCandidates = $competing

        if ($decisionReason -eq 'WIN_TIEBREAK') {
            $competingSameScore = @($competing | Where-Object { $_.MatchScore -eq $m.MatchScore } | ForEach-Object { "WO=$($_.WorkOrder) Excel=$([string]$_.ExcelRowId) tieRank=$(Get-MatchResultTieBreakRank -MatchedFields @($_.MatchedFields))" }) -join ' | '
            Write-Verbose "TIE_RESOLVED: sélection parmi égalité de score $($m.MatchScore) sur axes WorkOrder/ExcelRow ; retenu WorkOrder='$wk' ExcelRowId='$ek' (tri: score, tieRank=$tieRank, WO, Excel). Concurrents même score: $competingSameScore"
        }

        Write-Verbose "SELECT: WorkOrder='$wk' ExcelRowId='$ek' FinalScore=$($m.MatchScore) DecisionReason=$decisionReason tieRank=$tieRank ConflictResolved=$conflict CompetingCandidates=$($competing.Count)"

        $out.Add((New-FinalAssignment -WorkOrder $wk -ExcelRowId $m.ExcelRowId -FinalScore $m.MatchScore -ConflictResolved $conflict -Trace $trace))
    }

    return @($out.ToArray())
}

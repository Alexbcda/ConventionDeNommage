# ============================================================
# FinalAssignment.ps1
# Affectation unique ExcelRow ↔ WorkOrder après résolution de conflits.
# Nécessite que la classe MatchResult soit déjà chargée si FinalAssignmentTrace est utilisée.
# ============================================================

if (-not ('MatchResult' -as [type])) {
    $matchResultPath = Join-Path $PSScriptRoot 'MatchResult.ps1'
    if (Test-Path -LiteralPath $matchResultPath) {
        . $matchResultPath
    }
    if (-not ('MatchResult' -as [type])) {
        throw "MatchResult.ps1 doit etre charge avant FinalAssignment.ps1 : $matchResultPath"
    }
}

class FinalAssignmentTrace {
    [string]$WorkOrder
    [object]$ExcelRowId
    # WIN_SCORE | WIN_TIEBREAK (affectation retenue). REJECTED_CONFLICT : journalisé en -Verbose uniquement pour les rejets.
    [string]$DecisionReason
    [MatchResult[]]$CompetingCandidates

    FinalAssignmentTrace() {
        $this.WorkOrder = $null
        $this.ExcelRowId = $null
        $this.DecisionReason = $null
        $this.CompetingCandidates = @()
    }
}

class FinalAssignment {
    [string]$WorkOrder
    [object]$ExcelRowId
    [int]$FinalScore
    [bool]$ConflictResolved
    [FinalAssignmentTrace]$Trace

    FinalAssignment() {
        $this.WorkOrder = $null
        $this.ExcelRowId = $null
        $this.FinalScore = 0
        $this.ConflictResolved = $false
        $this.Trace = $null
    }
}

# ============================================================
# MatchResult.ps1
# Résultat déterministe de comparaison WorkOrderEntity ↔ ligne Excel.
# ============================================================

class MatchResult {
    [string]$WorkOrder
    [object]$ExcelRowId
    [int]$MatchScore
    [string]$MatchReason
    [string[]]$MatchedFields

    MatchResult() {
        $this.WorkOrder = $null
        $this.ExcelRowId = $null
        $this.MatchScore = 0
        $this.MatchReason = 'ManualReview'
        $this.MatchedFields = @()
    }
}

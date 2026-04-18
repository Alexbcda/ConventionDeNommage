# ============================================================
# ValidationReport.ps1
# Résultat de la validation métier post-agrégation (WorkOrderEntity).
# ============================================================

class ValidationReport {
    [bool]$IsValid
    [int[]]$MissingPages
    [int[]]$DuplicatePages
    [string[]]$InvalidWorkOrders
    [string[]]$Warnings

    ValidationReport() {
        $this.IsValid = $true
        $this.MissingPages = @()
        $this.DuplicatePages = @()
        $this.InvalidWorkOrders = @()
        $this.Warnings = @()
    }
}

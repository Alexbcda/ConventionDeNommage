# ============================================================
# WorkOrderEntity.ps1
# Agrégat métier : une commande / intervention regroupant plusieurs pages.
# ============================================================

class WorkOrderEntity {
    [string]$WorkOrder
    [string]$ClientID
    [string]$ClientName
    [hashtable]$Address
    [System.Nullable[datetime]]$VisitDate
    [hashtable]$Contact
    [array]$Services
    [int[]]$Pages
    # Optionnel : une entrée par page du groupe (traçabilité du grouping, triée par PageNumber en sortie Build).
    [object[]]$Trace

    WorkOrderEntity() {
        $this.WorkOrder = $null
        $this.ClientID = $null
        $this.ClientName = $null
        $this.Address = @{
            Street     = $null
            PostalCode = $null
            City       = $null
        }
        $this.VisitDate = $null
        $this.Contact = @{
            Name  = $null
            Email = $null
        }
        $this.Services = @()
        $this.Pages = @()
        $this.Trace = $null
    }
}

# ============================================================
# PageEntity.ps1
# Modèle strict des entités extraites d'une page (texte déjà ligné).
# ============================================================

class PageEntity {
    [int]$PageNumber
    [string]$ClientID
    [string]$ClientName
    [hashtable]$Address
    [string]$WorkOrder
    [System.Nullable[datetime]]$VisitDate
    [hashtable]$Contact
    [array]$Services

    PageEntity([int]$pageNumber) {
        $this.PageNumber = $pageNumber
        $this.ClientID = $null
        $this.ClientName = $null
        $this.Address = @{
            Street     = $null
            PostalCode = $null
            City       = $null
        }
        $this.WorkOrder = $null
        $this.VisitDate = $null
        $this.Contact = @{
            Name  = $null
            Email = $null
        }
        $this.Services = @()
    }
}

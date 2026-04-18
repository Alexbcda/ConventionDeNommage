# ============================================================
# FieldResolutionPolicy.ps1
# Source unique de vérité pour les priorités Excel vs PDF par champ.
# Consommée par FieldResolutionEngine.ps1 (aucune copie ailleurs).
# Aucune logique métier — uniquement ordre de préférence.
# ============================================================

function Get-FieldResolutionPolicy {
    <#
    .SYNOPSIS
        Retourne les règles de priorité entre données Excel et PDF par champ.
    #>
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        ClientIdPriority     = @('PDF', 'Excel')
        WorkOrderPriority  = @('Excel', 'PDF')
        AddressPriority    = @('PDF')
        DatePriority       = @('PDF')
        ClientNamePriority = @('PDF', 'Excel')
    }
}

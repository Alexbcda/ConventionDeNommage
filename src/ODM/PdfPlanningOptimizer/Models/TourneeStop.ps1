# ============================================================
# TourneeStop.ps1
# Arrêt ordonné dans une tournée (données Excel ; pas encore lié au PDF).
# ============================================================

class TourneeStop {
    [int] $Position
    [string] $WorkOrder
    [string] $ClientId

    TourneeStop(
        [int] $position,
        [string] $workOrder,
        [string] $clientId
    ) {
        $this.Position = $position
        $this.WorkOrder = if ($null -eq $workOrder) { '' } else { [string]$workOrder }
        $this.ClientId = if ($null -eq $clientId) { '' } else { [string]$clientId }
    }
}

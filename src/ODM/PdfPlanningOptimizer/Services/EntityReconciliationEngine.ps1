# ============================================================
# NEUTRALISÉ — ne pas utiliser (aucune implémentation).
# Single Source of Truth = EntityTourneeMergeEngine.ps1 — Merge-EntityTournees
# DO NOT EXTEND
# ============================================================

function Invoke-EntityReconciliation {
    <#
    .SYNOPSIS
        Retiré. Utilisez Merge-EntityTournees (EntityTourneeMergeEngine.ps1).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$ExcelTournees,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$FinalResolvedTournees = @(),

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$ResolvedMatches,

        [Parameter(Mandatory = $false)]
        [object]$FieldResolutionPolicy = $null
    )

    throw 'Invoke-EntityReconciliation is retired. Single Source of Truth = EntityTourneeMergeEngine.ps1 — use Merge-EntityTournees.'
}

# ============================================================
# NEUTRALISÉ — ne pas utiliser (aucune implémentation).
# Single Source of Truth = EntityTourneeMergeEngine.ps1 — Merge-EntityTournees
# DO NOT EXTEND
# ============================================================

function Build-FinalResolvedTournees {
    <#
    .SYNOPSIS
        Retiré. Utilisez Merge-EntityTournees (EntityTourneeMergeEngine.ps1).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Tournees,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$ResolvedMatches,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$Entities = @()
    )

    throw 'Build-FinalResolvedTournees is retired. Single Source of Truth = EntityTourneeMergeEngine.ps1 — use Merge-EntityTournees.'
}

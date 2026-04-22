# ============================================================
# NEUTRALISÉ — ne pas utiliser (aucune implémentation).
# Single Source of Truth = EntityTourneeMergeEngine.ps1 — Merge-EntityTournees
# DO NOT EXTEND
# ============================================================

function Build-FinalTournees {
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
        [object[]]$ResolvedMatches
    )

    throw 'Build-FinalTournees is retired. Single Source of Truth = EntityTourneeMergeEngine.ps1 — use Merge-EntityTournees.'
}

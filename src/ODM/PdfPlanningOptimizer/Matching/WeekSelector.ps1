# ============================================================
# WeekSelector.ps1
# Rôle : Identifier la semaine cible à partir des données extraites.
# ============================================================

function Select-PlanningWeek {
    <#
    .SYNOPSIS
    Détecte ou sélectionne la semaine de planning à traiter.

    .PARAMETER ExtractedPdfData
    Données brutes extraites du PDF.

    .OUTPUTS
    PSCustomObject
    Informations de semaine détectée/sélectionnée (à définir).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [object]$ExtractedPdfData
    )

    # Stub uniquement : implémentation métier à venir.
    return $null
}

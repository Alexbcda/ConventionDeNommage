# ============================================================
# ExcelLoader.ps1
# Rôle : Charger les données de référence depuis un fichier Excel.
# ============================================================

function Import-PlanningExcelData {
    <#
    .SYNOPSIS
    Charge les données Excel utilisées pour le matching.

    .PARAMETER ExcelPath
    Chemin absolu ou relatif du fichier Excel source.

    .OUTPUTS
    PSCustomObject
    Jeu de données Excel normalisé (à définir).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExcelPath
    )

    # Stub uniquement : implémentation métier à venir.
    return $null
}

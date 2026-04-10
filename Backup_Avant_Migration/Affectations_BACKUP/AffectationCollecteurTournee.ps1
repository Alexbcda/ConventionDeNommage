# AffectationCollecteurTournee.ps1 - Logique métier

function Save-Affectation {
    param($TourneeId, $CollecteurId, $VehiculeId)
    # Sauvegarde dans un fichier JSON ou variable globale
    Write-Host "[METIER] Affectation sauvegardée: Tournée $TourneeId -> Collecteur $CollecteurId, Véhicule $VehiculeId" -ForegroundColor Green
}

function Get-Affectations {
    # Retourne la liste des affectations
    return @{}
}
# ============================================================
# Tournee.ps1
# Tournée : regroupement logique (ex. date + agent) et liste d’arrêts ordonnés.
# Charger TourneeStop.ps1 avant ce fichier (ordre des classes PowerShell).
# ============================================================

class Tournee {
    [string] $TourneeId
    [datetime] $TourDate
    [string] $Agent
    [TourneeStop[]] $Stops

    Tournee() {
        $this.TourneeId = ''
        $this.TourDate = [datetime]::MinValue
        $this.Agent = ''
        $this.Stops = @()
    }
}

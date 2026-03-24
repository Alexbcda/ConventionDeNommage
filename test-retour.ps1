# test-retour.ps1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. "C:\Users\alexa\Documents\ConventionDeNommage\src\ODM\Components\DataManager.ps1"
. "C:\Users\alexa\Documents\ConventionDeNommage\src\ODM\Components\PlanningPanel.ps1"

$collecteurs = Get-Collecteurs
$vehicules = Get-Vehicules
$planningData = $null

$resultat = Show-PlanningPanel -Collecteurs $collecteurs -Vehicules $vehicules -PlanningData ([ref]$planningData)

Write-Host "Type du résultat: $($resultat.GetType())" -ForegroundColor Yellow
Write-Host "Est-ce un Panel? $($resultat -is [System.Windows.Forms.Panel])" -ForegroundColor Yellow

if ($resultat -is [array]) {
    Write-Host "C'est un tableau avec $($resultat.Count) éléments" -ForegroundColor Red
    for ($i = 0; $i -lt $resultat.Count; $i++) {
        Write-Host "  [$i] Type: $($resultat[$i].GetType())" -ForegroundColor Gray
    }
}

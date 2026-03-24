# test-retour.ps1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptPath = "C:\Users\alexa\Documents\ConventionDeNommage\src"
. "$scriptPath\ODM\ODMViewer.ps1"

$resultat = Show-ODMViewer

Write-Host "Type de l'objet retourné: $($resultat.GetType())" -ForegroundColor Yellow
Write-Host "Est-ce un Panel? $($resultat -is [System.Windows.Forms.Panel])" -ForegroundColor Yellow
Write-Host "Propriétés disponibles:" -ForegroundColor Cyan
$resultat | Get-Member -MemberType Property | Select-Object -First 10 Name

if ($resultat -is [System.Windows.Forms.Panel]) {
    Write-Host "`n✅ C'est bien un Panel, on peut l'ajouter" -ForegroundColor Green
} else {
    Write-Host "`n❌ Ce n'est PAS un Panel" -ForegroundColor Red
}

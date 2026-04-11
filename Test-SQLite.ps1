. ".\src\Database\Database.ps1"
Initialize-Database
$agents = Get-Agents
Write-Host "Agents: $($agents.Count)" -ForegroundColor Cyan
$vehicules = Get-Vehicules
Write-Host "Vehicules: $($vehicules.Count)" -ForegroundColor Cyan

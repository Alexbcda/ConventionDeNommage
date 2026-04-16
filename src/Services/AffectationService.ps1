# Services/AffectationService.ps1

function Load-InitialData {
    $agents = Get-Agents
    $vehicules = Get-Vehicules
    Set-State -Key "Agents" -Value $agents
    Set-State -Key "Vehicules" -Value $vehicules
    return @{ Agents = $agents; Vehicules = $vehicules }
}

function Set-Date { param([string]$Date) Set-State -Key "Date" -Value $Date }
function Get-Date { return Get-State -Key "Date" }

function Set-NbTournees {
    param([int]$Nb)
    Set-State -Key "NbTournees" -Value $Nb
    $affectations = @{}
    for ($i = 1; $i -le $Nb; $i++) { $affectations[$i] = @{ Agent = $null; Vehicule = $null } }
    Set-State -Key "Affectations" -Value $affectations
}

function Get-NbTournees { return Get-State -Key "NbTournees" }

function Set-Affectation {
    param([int]$TourneeId, [string]$Agent, [string]$Vehicule)
    $affectations = Get-State -Key "Affectations"
    if (-not $affectations) { $affectations = @{} }
    $affectations[$TourneeId] = @{ Agent = $Agent; Vehicule = $Vehicule; TourneeId = $TourneeId }
    Set-State -Key "Affectations" -Value $affectations
}

function Get-Affectations { return Get-State -Key "Affectations" }

function Get-AgentsList {
    $agents = Get-State -Key "Agents"
    if ($agents.Count -eq 0) { return @("Agent 1", "Agent 2", "Agent 3") }
    $names = @(); foreach ($c in $agents) { $names += "$($c.prenom) $($c.nom)".Trim() }
    return $names
}

function Get-VehiculesList {
    $vehicules = Get-State -Key "Vehicules"
    if ($vehicules.Count -eq 0) { return @("Véhicule A", "Véhicule B", "Véhicule C") }
    $parcs = @(); foreach ($v in $vehicules) { if ($v.numero_parc) { $parcs += $v.numero_parc } }
    return $parcs
}

function Reset-Wizard { Reset-State; Load-InitialData }



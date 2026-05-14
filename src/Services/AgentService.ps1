# AgentService.ps1 — Service layer for agent operations
# UI (Panels/Forms) should ONLY call functions defined here.
# Architecture: UI → Service → Repository → Database

. "$PSScriptRoot\..\ODM\Agents\AgentRepository.ps1"

function Get-AgentList {
    param([switch]$IncludeInactive)
    if ($IncludeInactive) { return Get-AllAgents } else { return Get-Agents }
}

function Get-AgentDetails {
    param([Parameter(Mandatory=$true)] $Id)
    return Get-AgentByIdSafe -Id $Id
}

function Add-AgentEntry {
    param($Nom, $Prenom, $Telephone, $Email, $DateEntree, $DateSortie, $TypeContrat, $BaseHeuresSemaine = 35, $VehiculeId = $null, $Poste = "Collecteur")
    return Add-AgentWithValidation @PSBoundParameters
}

function Update-AgentEntry {
    param($Id, $Nom, $Prenom, $Telephone, $Email, $DateEntree, $DateSortie, $TypeContrat, $BaseHeuresSemaine = 35, $VehiculeId = $null, $Poste = "Collecteur")
    return Update-AgentWithValidation @PSBoundParameters
}

function Remove-AgentEntry {
    param([Parameter(Mandatory=$true)] $Id)
    return Remove-AgentWithValidation -Id $Id
}

function Get-PostesList {
    return Get-PostesListe
}

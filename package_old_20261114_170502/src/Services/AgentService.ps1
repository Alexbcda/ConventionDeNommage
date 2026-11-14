# AgentService.ps1 — Service layer for agent operations
# UI (Panels/Forms) should ONLY call functions defined here.
# Architecture: UI → Service (guard) → Repository (validation) → Database

. "$PSScriptRoot\..\ODM\Agents\AgentRepository.ps1"

function Assert-AgentServiceInput {
    param($Nom, $Prenom, $Email)
    Assert-RequiredString "Nom" $Nom -MaxLength 50
    Assert-RequiredString "Prenom" $Prenom -MaxLength 50
    if (-not [string]::IsNullOrWhiteSpace($Email) -and $Email.Trim().Length -gt 120) {
        throw "Email depasse la longueur maximale (120 caracteres)."
    }
}

function Get-AgentList {
    param([switch]$IncludeInactive)
    return Get-AgentRecords -IncludeInactive:$IncludeInactive
}

function Get-AgentDetails {
    param([Parameter(Mandatory=$true)] $Id)
    return Get-AgentByIdSafe -Id $Id
}

function Add-AgentEntry {
    param($Nom, $Prenom, $Telephone, $Email, $DateEntree, $DateSortie, $TypeContrat, $BaseHeuresSemaine = 35, $VehiculeId = $null, $Poste = "Collecteur")
    Assert-AgentServiceInput -Nom $Nom -Prenom $Prenom -Email $Email
    return Add-AgentWithValidation @PSBoundParameters
}

function Update-AgentEntry {
    param($Id, $Nom, $Prenom, $Telephone, $Email, $DateEntree, $DateSortie, $TypeContrat, $BaseHeuresSemaine = 35, $VehiculeId = $null, $Poste = "Collecteur")
    Assert-AgentServiceInput -Nom $Nom -Prenom $Prenom -Email $Email
    return Update-AgentWithValidation @PSBoundParameters
}

function Remove-AgentEntry {
    param([Parameter(Mandatory=$true)] $Id)
    return Remove-AgentWithValidation -Id $Id
}

function Get-PostesList {
    return Get-PostesRecords
}

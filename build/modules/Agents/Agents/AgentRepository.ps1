# AgentRepository.ps1 - Logique métier (ne duplique pas Database.ps1)

. "$PSScriptRoot\..\..\Database\Database.ps1"
. "$PSScriptRoot\..\..\Common\Validation.ps1"
. "$PSScriptRoot\..\..\Core\Logger.ps1"

function Assert-AgentContactFields {
    param([string]$Nom, [string]$Prenom, [string]$Telephone, [string]$Email)
    if (-not (Test-StringLength $Nom -Min 2 -Max 50)) { Write-Log "[Agents] Validation failed: nom" "WARN" @{ field = 'nom' }; throw "Nom invalide (2-50 caracteres)" }
    if (-not (Test-StringLength $Prenom -Min 2 -Max 50)) { Write-Log "[Agents] Validation failed: prenom" "WARN" @{ field = 'prenom' }; throw "Prenom invalide (2-50 caracteres)" }
    if (-not (Test-TelephoneValide $Telephone)) { Write-Log "[Agents] Validation failed: telephone" "WARN" @{ field = 'telephone' }; throw "Telephone invalide" }
    if (-not (Test-Email $Email)) { Write-Log "[Agents] Validation failed: email" "WARN" @{ field = 'email' }; throw "Email invalide" }
    if (-not [string]::IsNullOrWhiteSpace($Email) -and $Email.Trim().Length -gt 120) { throw "Email trop long (max 120)" }
}

# ============================================================
# AJOUT AVEC VALIDATION
# ============================================================

function Add-AgentWithValidation {
    param($Nom, $Prenom, $Telephone, $Email, $DateEntree, $DateSortie, $TypeContrat, $BaseHeuresSemaine = 35, $VehiculeId = $null, $Poste = "Collecteur")

    Assert-AgentContactFields -Nom $Nom -Prenom $Prenom -Telephone $Telephone -Email $Email

    try {
        return Add-Agent -Nom $Nom -Prenom $Prenom -Telephone $Telephone -Email $Email -DateEntree $DateEntree -DateSortie $DateSortie -TypeContrat $TypeContrat -BaseHeuresSemaine $BaseHeuresSemaine -VehiculeId $VehiculeId -Poste $Poste
    } catch {
        Write-Log "[Agents] Add failed" "ERROR" @{ message = $_.Exception.Message }
        throw
    }
}

# ============================================================
# MISE À JOUR AVEC VALIDATION
# ============================================================

function Update-AgentWithValidation {
    param($Id, $Nom, $Prenom, $Telephone, $Email, $DateEntree, $DateSortie, $TypeContrat, $BaseHeuresSemaine = 35, $VehiculeId = $null, $Poste = "Collecteur")

    $Id = Assert-EntityId "agent" $Id
    Assert-AgentContactFields -Nom $Nom -Prenom $Prenom -Telephone $Telephone -Email $Email

    try {
        return Update-Agent -Id $Id -Nom $Nom -Prenom $Prenom -Telephone $Telephone -Email $Email -DateEntree $DateEntree -DateSortie $DateSortie -TypeContrat $TypeContrat -BaseHeuresSemaine $BaseHeuresSemaine -VehiculeId $VehiculeId -Poste $Poste
    } catch {
        Write-Log "[Agents] Update failed" "ERROR" @{ message = $_.Exception.Message; id = $Id }
        throw
    }
}

# ============================================================
# SUPPRESSION AVEC VALIDATION
# ============================================================

function Remove-AgentWithValidation {
    param($Id)

    $Id = Assert-EntityId "agent" $Id

    try {
        return Remove-Agent -Id $Id
    } catch {
        Write-Log "[Agents] Remove failed" "ERROR" @{ message = $_.Exception.Message; id = $Id }
        throw
    }
}

# ============================================================
# LECTURE PAR ID AVEC VALIDATION
# ============================================================

function Get-AgentByIdSafe {
    param($Id)

    $Id = Assert-EntityId "agent" $Id
    return Get-AgentById -Id $Id
}

function Get-AgentRecords {
    param([switch]$IncludeInactive)
    if ($IncludeInactive) { return Get-AllAgents } else { return Get-Agents }
}

function Get-PostesRecords {
    return Get-PostesListe
}


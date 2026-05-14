# AgentRepository.ps1 - Logique métier (ne duplique pas Database.ps1)

. "$PSScriptRoot\..\..\Database\Database.ps1"
. "$PSScriptRoot\..\..\Common\Validation.ps1"
. "$PSScriptRoot\..\..\Core\Logger.ps1"

# ============================================================
# AJOUT AVEC VALIDATION
# ============================================================

function Add-AgentWithValidation {
    param($Nom, $Prenom, $Telephone, $Email, $DateEntree, $DateSortie, $TypeContrat, $BaseHeuresSemaine = 35, $VehiculeId = $null, $Poste = "Collecteur")
    
    Write-Log "[Agents] Add-AgentWithValidation begin" "INFO" @{
        type_contrat = $TypeContrat; base_heures_semaine = $BaseHeuresSemaine
        poste = $Poste; vehicule_id = $VehiculeId
    }

    # Validations
    if (-not (Test-NomValide $Nom)) { Write-Log "[Agents] Validation failed: nom" "WARN" @{ field = 'nom' }; throw "Nom invalide (min 2 caractères)" }
    if (-not (Test-PrenomValide $Prenom)) { Write-Log "[Agents] Validation failed: prenom" "WARN" @{ field = 'prenom' }; throw "Prénom invalide (min 2 caractères)" }
    if (-not (Test-TelephoneValide $Telephone)) { Write-Log "[Agents] Validation failed: telephone" "WARN" @{ field = 'telephone' }; throw "Téléphone invalide" }
    if (-not (Test-EmailValide $Email)) { Write-Log "[Agents] Validation failed: email" "WARN" @{ field = 'email' }; throw "Email invalide" }
    
    # Appel à la base
    try {
        $newId = Add-Agent -Nom $Nom -Prenom $Prenom -Telephone $Telephone -Email $Email -DateEntree $DateEntree -DateSortie $DateSortie -TypeContrat $TypeContrat -BaseHeuresSemaine $BaseHeuresSemaine -VehiculeId $VehiculeId -Poste $Poste
        Write-Log "[Agents] Add-AgentWithValidation success" "INFO" @{ id = $newId }
        return $newId
    } catch {
        Write-Log "[Agents] Add-AgentWithValidation failed" "ERROR" @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
        throw
    }
}


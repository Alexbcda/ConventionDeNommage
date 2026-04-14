# AgentRepository.ps1 - Logique métier (ne duplique pas Database.ps1)

. "$PSScriptRoot\..\..\Database\Database.ps1"
. "$PSScriptRoot\..\..\Core\Logger.ps1"

# ============================================================
# VALIDATIONS
# ============================================================

function Test-NomValide {
    param($Nom)
    if ([string]::IsNullOrWhiteSpace($Nom)) { return $false }
    return $Nom.Length -ge 2
}

function Test-PrenomValide {
    param($Prenom)
    if ([string]::IsNullOrWhiteSpace($Prenom)) { return $false }
    return $Prenom.Length -ge 2
}

function Test-TelephoneValide {
    param($Telephone)
    if ([string]::IsNullOrWhiteSpace($Telephone)) { return $true }
    $clean = $Telephone -replace '[^0-9+]', ''
    if ($clean -match '^0[1-9][0-9]{8}$') { return $true }
    if ($clean -match '^\+33[1-9][0-9]{8}$') { return $true }
    return $false
}

function Test-EmailValide {
    param($Email)
    if ([string]::IsNullOrWhiteSpace($Email)) { return $true }
    return $Email -match '^[^@\s]+@[^@\s]+\.[^@\s]+$'
}

# ============================================================
# AJOUT AVEC VALIDATION
# ============================================================

function Add-AgentWithValidation {
    param($Nom, $Prenom, $Telephone, $Email, $DateEntree, $DateSortie, $TypeContrat, $BaseHeuresSemaine = 35, $VehiculeId = $null, $Poste = "Collecteur")
    
    Write-Log "[Agents] Add-AgentWithValidation begin" "INFO" @{
        nom = $Nom; prenom = $Prenom; telephone = $Telephone; email = $Email
        type_contrat = $TypeContrat; base_heures_semaine = $BaseHeuresSemaine
        poste = $Poste; vehicule_id = $VehiculeId
        date_entree = $DateEntree; date_sortie = $DateSortie
    }

    # Validations
    if (-not (Test-NomValide $Nom)) { Write-Log "[Agents] Validation failed: nom" "WARN" @{ nom = $Nom }; throw "Nom invalide (min 2 caractères)" }
    if (-not (Test-PrenomValide $Prenom)) { Write-Log "[Agents] Validation failed: prenom" "WARN" @{ prenom = $Prenom }; throw "Prénom invalide (min 2 caractères)" }
    if (-not (Test-TelephoneValide $Telephone)) { Write-Log "[Agents] Validation failed: telephone" "WARN" @{ telephone = $Telephone }; throw "Téléphone invalide" }
    if (-not (Test-EmailValide $Email)) { Write-Log "[Agents] Validation failed: email" "WARN" @{ email = $Email }; throw "Email invalide" }
    
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

# ============================================================
# RECHERCHES
# ============================================================

function Search-Agents {
    param($Nom = "", $Prenom = "", $Poste = "")
    
    $agents = Get-Agents
    if ($Nom) { $agents = $agents | Where-Object { $_.nom -like "*$Nom*" } }
    if ($Prenom) { $agents = $agents | Where-Object { $_.prenom -like "*$Prenom*" } }
    if ($Poste) { $agents = $agents | Where-Object { $_.poste -eq $Poste } }
    return $agents
}

# ============================================================
# STATISTIQUES
# ============================================================

function Get-AgentsStatistics {
    $agents = Get-Agents
    return [PSCustomObject]@{
        Total = $agents.Count
        ParPoste = $agents | Group-Object poste | ForEach-Object { 
            [PSCustomObject]@{ Poste = $_.Name; Count = $_.Count }
        }
        Actifs = ($agents | Where-Object { $_.actif -eq 1 }).Count
        Inactifs = ($agents | Where-Object { $_.actif -eq 0 }).Count
    }
}

# ============================================================
# EXPORT
# ============================================================

function Export-AgentsToCsv {
    param($Path)
    $agents = Get-Agents
    $agents | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
    Write-Host "✅ Agents exportés vers $Path" -ForegroundColor Green
}

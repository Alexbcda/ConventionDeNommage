# AgentRepository.ps1 - Logique métier (ne duplique pas Database.ps1)

. "$PSScriptRoot\..\..\Database\Database.ps1"

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
    
    # Validations
    if (-not (Test-NomValide $Nom)) { throw "Nom invalide (min 2 caractères)" }
    if (-not (Test-PrenomValide $Prenom)) { throw "Prénom invalide (min 2 caractères)" }
    if (-not (Test-TelephoneValide $Telephone)) { throw "Téléphone invalide" }
    if (-not (Test-EmailValide $Email)) { throw "Email invalide" }
    
    # Appel à la base
    return Add-Agent -Nom $Nom -Prenom $Prenom -Telephone $Telephone -Email $Email -DateEntree $DateEntree -DateSortie $DateSortie -TypeContrat $TypeContrat -BaseHeuresSemaine $BaseHeuresSemaine -VehiculeId $VehiculeId -Poste $Poste
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

# Validation.ps1 - Fonctions de validation

function Test-Email {
    param([string]$Email)
    
    if ([string]::IsNullOrWhiteSpace($Email)) { return $false }
    
    # Vérifier le format email basique
    $pattern = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return $Email -match $pattern
}

function Test-Telephone {
    param([string]$Telephone)
    
    if ([string]::IsNullOrWhiteSpace($Telephone)) { return $false }
    
    # Supprimer les espaces et tirets
    $clean = $Telephone -replace '[\s\-]', ''
    
    # Format international: +XX XXXXXXXXX ou national: 0XXXXXXXXX
    $pattern = '^(\+[0-9]{1,3}|0)[0-9]{8,12}$'
    return $clean -match $pattern
}

function Test-NomPrenom {
    param([string]$Value)
    
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    
    # Au moins 2 caractères, lettres, espaces, tirets, apostrophes
    $pattern = '^[a-zA-ZÀ-ÿ\s\-\'']{2,50}$'
    return $Value -match $pattern
}

function Test-VehiculeDisponible {
    param(
        [string]$NumeroParc,
        [array]$Vehicules,
        [array]$Agents
    )
    
    if ([string]::IsNullOrWhiteSpace($NumeroParc)) { return $true } # Peut être vide
    
    # Vérifier si le véhicule existe
    $vehicule = $Vehicules | Where-Object { $_.immatriculation -eq $NumeroParc -or $_.id -eq $NumeroParc }
    if (-not $vehicule) { return $false }
    
    # Vérifier si le véhicule est déjà affecté à un autre agent
    $affecte = $Agents | Where-Object { $_.vehiculeDefaut -eq $NumeroParc -or $_.vehiculeDefaut -eq $vehicule.immatriculation }
    return $affecte.Count -eq 0
}

function Get-VehiculeInfo {
    param(
        [string]$NumeroParc,
        [array]$Vehicules,
        [array]$Agents
    )
    
    $vehicule = $Vehicules | Where-Object { $_.immatriculation -eq $NumeroParc -or $_.id -eq $NumeroParc }
    if (-not $vehicule) { return $null }
    
    $affecte = $Agents | Where-Object { $_.vehiculeDefaut -eq $NumeroParc -or $_.vehiculeDefaut -eq $vehicule.immatriculation }
    
    return @{
        Vehicule = $vehicule
        AffecteA = $affecte
    }
}


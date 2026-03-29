. "$PSScriptRoot\..\..\Core\DataManager.ps1"

function Add-Collecteur {
    param($Nom, $Prenom, $Telephone, $Email)
    
    Write-Host "[MGR] Ajout: $Nom $Prenom" -ForegroundColor Cyan
    
    # Récupérer les collecteurs
    $collecteurs = Get-Collecteurs
    if ($collecteurs -eq $null) {
        $collecteurs = @()
    }
    
    # Générer ID
    $newId = (Get-Random -Minimum 100 -Maximum 999)
    
    $newCollecteur = [PSCustomObject]@{
        id = $newId
        nom = $Nom
        prenom = $Prenom
        telephone = $Telephone
        email = $Email
    }
    
    # Ajouter
    $collecteurs = $collecteurs + @($newCollecteur)
    
    # Sauvegarder
    $vehicules = Get-Vehicules
    if ($vehicules -eq $null) { $vehicules = @() }
    
    Save-ODMData -Collecteurs $collecteurs -Vehicules $vehicules
    
    Write-Host "[MGR] Ajouté ID: $newId" -ForegroundColor Green
    return $newCollecteur
}

function Update-Collecteur {
    param($Id, $Nom, $Prenom, $Telephone, $Email)
    
    $collecteurs = Get-Collecteurs
    if ($collecteurs -eq $null) { $collecteurs = @() }
    
    for ($i = 0; $i -lt $collecteurs.Count; $i++) {
        if ($collecteurs[$i].id -eq $Id) {
            $collecteurs[$i] = [PSCustomObject]@{ 
                id = $Id
                nom = $Nom
                prenom = $Prenom
                telephone = $Telephone
                email = $Email
            }
            break
        }
    }
    
    $vehicules = Get-Vehicules
    if ($vehicules -eq $null) { $vehicules = @() }
    
    Save-ODMData -Collecteurs $collecteurs -Vehicules $vehicules
    return $true
}

function Remove-Collecteur {
    param($Id)
    
    $collecteurs = Get-Collecteurs
    if ($collecteurs -eq $null) { $collecteurs = @() }
    
    $newCollecteurs = @()
    foreach ($c in $collecteurs) {
        if ($c.id -ne $Id) {
            $newCollecteurs += $c
        }
    }
    
    $vehicules = Get-Vehicules
    if ($vehicules -eq $null) { $vehicules = @() }
    
    Save-ODMData -Collecteurs $newCollecteurs -Vehicules $vehicules
    return $true
}

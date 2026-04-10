# DataManager.ps1 - Gestion des données JSON
$script:DataPath = Join-Path $PSScriptRoot "..\..\Data\ressources.json"

function Get-Collecteurs {
    $data = Load-ODMData
    if ($data -and $data.collecteurs) {
        return $data.collecteurs
    }
    return @()
}

function Get-Vehicules {
    $data = Load-ODMData
    if ($data -and $data.vehicules) {
        return $data.vehicules
    }
    return @()
}

function Load-ODMData {
    if (Test-Path $script:DataPath) {
        $content = Get-Content $script:DataPath -Raw -ErrorAction SilentlyContinue
        if ($content) {
            $data = $content | ConvertFrom-Json
            if ($null -eq $data.collecteurs) { $data.collecteurs = @() }
            if ($null -eq $data.vehicules) { $data.vehicules = @() }
            if ($null -eq $data.clients) { $data.clients = @() }
            return $data
        }
    }
    return @{ collecteurs = @(); vehicules = @(); clients = @() }
}

function Save-ODMData {
    param($Collecteurs, $Vehicules, $Clients = @())
    
    $data = @{
        collecteurs = $Collecteurs
        vehicules = $Vehicules
        clients = $Clients
    }
    
    $json = $data | ConvertTo-Json -Depth 10
    $json | Out-File $script:DataPath -Encoding utf8 -Force
    return $true
}

function Get-VehiculesAvecAffectation {
    $vehicules = Get-Vehicules
    $collecteurs = Get-Collecteurs
    
    $collecteursLookup = @{}
    foreach ($c in $collecteurs) {
        $collecteursLookup[$c.id] = $c
    }
    
    foreach ($v in $vehicules) {
        if ($v.conducteurId -and $collecteursLookup[$v.conducteurId]) {
            $v | Add-Member -MemberType NoteProperty -Name "conducteurNomComplet" -Value "$($collecteursLookup[$v.conducteurId].prenom) $($collecteursLookup[$v.conducteurId].nom)" -Force
            $v | Add-Member -MemberType NoteProperty -Name "conducteurExiste" -Value $true -Force
        } else {
            $v | Add-Member -MemberType NoteProperty -Name "conducteurNomComplet" -Value "(Non affecté)" -Force
            $v | Add-Member -MemberType NoteProperty -Name "conducteurExiste" -Value $false -Force
            if ($v.conducteurId) { 
                $v.conducteurId = $null 
            }
        }
    }
    
    return $vehicules
}

function Get-VehiculeAvecAffectationById {
    param($Id)
    $vehicules = Get-VehiculesAvecAffectation
    return $vehicules | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}

function Get-VehiculeByCollecteurId {
    param($CollecteurId)
    $vehicules = Get-Vehicules
    return $vehicules | Where-Object { $_.conducteurId -eq $CollecteurId } | Select-Object -First 1
}

function Update-AffectationVehicule {
    param(
        [int]$VehiculeId,
        [int]$NouveauConducteurId
    )
    
    Write-Host "[DATA] ========== Update-AffectationVehicule ==========" -ForegroundColor Magenta
    Write-Host "[DATA] Vehicule ID: $VehiculeId" -ForegroundColor Yellow
    Write-Host "[DATA] Nouveau conducteur ID: $NouveauConducteurId" -ForegroundColor Yellow
    
    try {
        $vehicules = @(Get-Vehicules)
        $collecteurs = @(Get-Collecteurs)
        
        $vehiculeModifie = $false
        
        for ($i = 0; $i -lt $vehicules.Count; $i++) {
            if ($vehicules[$i].id -eq $VehiculeId) {
                if ($NouveauConducteurId -eq 0 -or $NouveauConducteurId -eq $null) {
                    $vehicules[$i].conducteurId = $null
                    Write-Host "[DATA] ✅ Véhicule $VehiculeId libéré" -ForegroundColor Yellow
                } else {
                    $vehicules[$i].conducteurId = $NouveauConducteurId
                    Write-Host "[DATA] ✅ Véhicule $VehiculeId affecté au conducteur $NouveauConducteurId" -ForegroundColor Green
                }
                
                $vehiculeModifie = $true
                break
            }
        }
        
        if (-not $vehiculeModifie) {
            Write-Host "[DATA] ❌ Véhicule $VehiculeId non trouvé" -ForegroundColor Red
            return $false
        }
        
        $result = Save-ODMData -Collecteurs $collecteurs -Vehicules $vehicules
        
        if ($result) {
            Write-Host "[DATA] ✅ Affectation enregistrée" -ForegroundColor Green
            return $true
        } else {
            Write-Host "[DATA] ❌ Erreur sauvegarde" -ForegroundColor Red
            return $false
        }
        
    } catch {
        Write-Host "[DATA] ❌ Exception: $_" -ForegroundColor Red
        return $false
    }
}

function Liberer-Vehicule {
    param([int]$VehiculeId)
    
    Write-Host "[DATA] Libération du véhicule $VehiculeId" -ForegroundColor Yellow
    return Update-AffectationVehicule -VehiculeId $VehiculeId -NouveauConducteurId $null
}

Write-Host "[DATA] DataManager.ps1 chargé" -ForegroundColor Green

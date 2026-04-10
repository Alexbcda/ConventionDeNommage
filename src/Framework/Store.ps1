# Framework/Store.ps1
# État global unique (Redux-like)

$script:GlobalState = @{
    Date = $null
    NbTournees = 0
    Affectations = @{}
    Collecteurs = @()
    Vehicules = @()
    CurrentRoute = "/date"
    Loading = $false
}

function Get-State {
    param([string]$Key)
    if ($Key) { return $script:GlobalState[$Key] }
    return $script:GlobalState
}

function Set-State {
    param([string]$Key, $Value)
    $script:GlobalState[$Key] = $Value
    Write-Host "[STATE] $Key mis à jour" -ForegroundColor Cyan
}

function Update-State {
    param([hashtable]$Updates)
    foreach ($key in $Updates.Keys) {
        $script:GlobalState[$key] = $Updates[$key]
    }
}

function Reset-State {
    $script:GlobalState = @{
        Date = $null
        NbTournees = 0
        Affectations = @{}
        Collecteurs = @()
        Vehicules = @()
        CurrentRoute = "/date"
        Loading = $false
    }
    Write-Host "[STATE] Réinitialisé" -ForegroundColor Yellow
}

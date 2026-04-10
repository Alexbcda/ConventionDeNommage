# AffectationNbTournees.ps1 - Gestion du nombre de tournées
function Get-NbTournees {
    $configPath = Join-Path $PSScriptRoot "..\..\Data\odm_config.json"
    if (Test-Path $configPath) {
        $config = Get-Content $configPath | ConvertFrom-Json
        return $config.NbTournees
    }
    return 1
}

function Set-NbTournees {
    param([int]$NbTournees)
    $configPath = Join-Path $PSScriptRoot "..\..\Data\odm_config.json"
    $config = @{ NbTournees = $NbTournees }
    $config | ConvertTo-Json | Out-File $configPath -Encoding UTF8 -Force
}




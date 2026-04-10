# AffectationCollecteurTournee.ps1 - Gestion des affectations
function Get-Affectations {
    $dataPath = Join-Path $PSScriptRoot "..\..\Data\affectations.json"
    if (Test-Path $dataPath) {
        return Get-Content $dataPath | ConvertFrom-Json
    }
    return @()
}

function Save-Affectation {
    param($Affectation)
    $affectations = Get-Affectations
    $affectations += $Affectation
    $affectations | ConvertTo-Json | Out-File (Join-Path $PSScriptRoot "..\..\Data\affectations.json") -Encoding UTF8 -Force
}




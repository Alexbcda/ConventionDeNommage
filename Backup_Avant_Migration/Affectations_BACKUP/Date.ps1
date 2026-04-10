# Date.ps1 - Logique métier UNIQUE

$script:AffectationDate = $null
$script:NbTournees = 0
$script:ConfigPath = "C:\Users\alexa\Documents\ConventionDeNommage\Data\default_nbtournees.json"

# ============================================================
# FONCTIONS DATE
# ============================================================

function Save-DateAffectation {
    param($Date)
    $script:AffectationDate = $Date
    Write-Host "[METIER] Date sauvegardée: $Date" -ForegroundColor Green
}

function Get-DateAffectation {
    return $script:AffectationDate
}

# ============================================================
# FONCTIONS NOMBRE DE TOURNÉES (session)
# ============================================================

function Save-NbTournees {
    param([int]$NbTournees)
    $script:NbTournees = $NbTournees
    Write-Host "[METIER] Nb tournées session: $NbTournees" -ForegroundColor Green
}

function Get-NbTournees {
    Write-Host "[METIER] Get Nb tournées: $script:NbTournees" -ForegroundColor Green
    return $script:NbTournees
}

# ============================================================
# FONCTIONS VALEUR PAR DÉFAUT (JSON)
# ============================================================

function Save-DefaultNbTournees {
    param([int]$NbTournees)
    try {
        $configDir = Split-Path $script:ConfigPath -Parent
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }
        $config = @{ DefaultNbTournees = $NbTournees }
        $config | ConvertTo-Json | Out-File -FilePath $script:ConfigPath -Encoding UTF8
        Write-Host "[CONFIG] Valeur par défaut sauvegardée: $NbTournees" -ForegroundColor Green
    } catch {
        Write-Host "[CONFIG] Erreur: $_" -ForegroundColor Red
    }
}

function Get-DefaultNbTournees {
    if (Test-Path $script:ConfigPath) {
        try {
            $config = Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
            if ($config.DefaultNbTournees -gt 0) {
                Write-Host "[CONFIG] Valeur par défaut chargée: $($config.DefaultNbTournees)" -ForegroundColor Green
                return $config.DefaultNbTournees
            }
        } catch {}
    }
    return 0
}
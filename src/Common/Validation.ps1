<# 
Validation.ps1 - Helpers de validation réutilisables (WinForms-friendly)

- Pas d'exécution dynamique (pas d'Invoke-Expression)
- Fonctions pures (pas d'accès DB)
#>

function Normalize-Telephone {
    param([string]$Telephone)
    if ($null -eq $Telephone) { return "" }
    # Garder uniquement les chiffres
    return ($Telephone -replace '[^0-9]', '')
}

function Format-Telephone {
    param([string]$Telephone)
    $digits = Normalize-Telephone $Telephone
    if ([string]::IsNullOrEmpty($digits)) { return "" }

    # Format "XX XX XX XX XX" à partir des digits disponibles
    $pairs = @()
    for ($i = 0; $i -lt $digits.Length; $i += 2) {
        $len = [Math]::Min(2, $digits.Length - $i)
        $pairs += $digits.Substring($i, $len)
    }
    return ($pairs -join " ")
}

function Test-Telephone {
    param([string]$Telephone)
    $digits = Normalize-Telephone $Telephone
    return ($digits.Length -eq 10)
}

function Normalize-Email {
    param([string]$Email)
    if ($null -eq $Email) { return "" }
    return $Email.Trim()
}

function Test-Email {
    param([string]$Email)
    $e = Normalize-Email $Email
    if ([string]::IsNullOrWhiteSpace($e)) { return $true } # champ optionnel

    if ($e -notmatch '@') { return $false }
    # Validation "stricte mais réaliste": local@domaine.tld avec tld >= 2
    if ($e -notmatch '^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$') { return $false }
    return $true
}


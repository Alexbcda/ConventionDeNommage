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
    # Nettoie (digits-only), valide (10 chiffres) puis formate en "XX XX XX XX XX"
    # - Champ vide autorisé => retourne ""
    # - Invalide => retourne $null
    if ([string]::IsNullOrWhiteSpace($Telephone)) { return "" }

    $digits = Normalize-Telephone $Telephone
    if ([string]::IsNullOrWhiteSpace($digits)) { return "" }
    if ($digits.Length -ne 10) { return $null }

    return ($digits.Substring(0,2) + " " +
            $digits.Substring(2,2) + " " +
            $digits.Substring(4,2) + " " +
            $digits.Substring(6,2) + " " +
            $digits.Substring(8,2))
}

function Test-Telephone {
    param([string]$Telephone)
    $formatted = Format-Telephone $Telephone
    return ($null -ne $formatted -and $formatted -ne "")
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

function Sanitize-TextInput {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    $t = $Text.Trim()
    # Retirer caractères/séquences suspects (couche UI supplémentaire)
    $t = $t -replace '[''\";<>]', ''
    $t = $t.Replace('--', '')
    return $t
}

function Test-SecuriteInput {
    param([string]$Text)
    if ($null -eq $Text) { return $true }
    $t = $Text
    # Refuser si présence de caractères/séquences dangereux
    if ($t -match '[''\";<>]') { return $false }
    if ($t.Contains("--")) { return $false }
    return $true
}

<#
Numéro de parc véhicule : obligatoire côté métier, format restreint (pas d’injection SQL / XSS).
#>
function Test-NumeroParcVehicule {
    param([string]$Value)
    if ($null -eq $Value) { return $false }
    $t = $Value.Trim()
    if ($t.Length -eq 0 -or $t.Length -gt 50) { return $false }
    if (-not (Test-SecuriteInput $t)) { return $false }
    if ($t -notmatch '^[A-Za-z0-9._\- ]+$') { return $false }
    return $true
}

function Get-NumeroParcError {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "Le numéro de parc est obligatoire." }
    if (-not (Test-NumeroParcVehicule $Value)) { return "Numéro de parc invalide (caractères ou longueur max 50)." }
    return ""
}

<#
Date stockée au format strict YYYY-MM-DD (couche BDD / API interne).
#>
function Test-YyyyMmDdDate {
    param([string]$DateStr)
    if ([string]::IsNullOrWhiteSpace($DateStr)) { return $true }
    return ($DateStr -match '^\d{4}-\d{2}-\d{2}$')
}

function Normalize-Whitespace {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    $t = $Text.Trim()
    # Remplacer les séquences d'espaces/tab par un seul espace
    $t = ($t -replace "\\s+", " ")
    return $t
}

function Test-NomValide {
    param([string]$Nom)
    if ([string]::IsNullOrWhiteSpace($Nom)) { return $false }
    return $Nom.Trim().Length -ge 2
}

function Test-PrenomValide {
    param([string]$Prenom)
    if ([string]::IsNullOrWhiteSpace($Prenom)) { return $false }
    return $Prenom.Trim().Length -ge 2
}

function Test-TelephoneValide {
    param([string]$Telephone)
    if ([string]::IsNullOrWhiteSpace($Telephone)) { return $true }
    $formatted = Format-Telephone $Telephone
    return ($null -ne $formatted)
}

function Test-EmailValide {
    param([string]$Email)
    return (Test-Email $Email)
}

<#
Conversion date YYYY-MM-DD (BDD) <-> dd/MM/yyyy (affichage FR).
#>
function Convert-DbToFrDate {
    param([string]$DateUs)
    if ([string]::IsNullOrWhiteSpace($DateUs)) { return "" }
    try {
        return ([datetime]::ParseExact($DateUs, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)).ToString("dd/MM/yyyy")
    } catch {
        return $DateUs
    }
}

function Convert-FrToDbDate {
    param([string]$DateFr)
    if ([string]::IsNullOrWhiteSpace($DateFr)) { return $null }
    try {
        $dt = [datetime]::ParseExact($DateFr, "dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)
        return $dt.ToString("yyyy-MM-dd")
    } catch {
        return $null
    }
}

function Test-DateFr {
    param([string]$DateStr)
    return ($null -ne (Convert-FrToDbDate $DateStr))
}

function Format-Nom {
    param([string]$Nom)
    $n = Normalize-Whitespace $Nom
    if ([string]::IsNullOrWhiteSpace($n)) { return "" }
    return $n.ToUpperInvariant()
}

function Format-Prenom {
    param([string]$Prenom)
    $p = Normalize-Whitespace $Prenom
    if ([string]::IsNullOrWhiteSpace($p)) { return "" }

    # Mettre chaque mot en "Title Case" simple: 1ère lettre maj, reste min
    $parts = $p.Split(' ')
    $out = foreach ($part in $parts) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        $lower = $part.ToLowerInvariant()
        if ($lower.Length -eq 1) { $lower.ToUpperInvariant() }
        else { $lower.Substring(0,1).ToUpperInvariant() + $lower.Substring(1) }
    }
    return ($out -join ' ')
}


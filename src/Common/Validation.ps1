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

function Normalize-Whitespace {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    $t = $Text.Trim()
    # Remplacer les séquences d'espaces/tab par un seul espace
    $t = ($t -replace "\\s+", " ")
    return $t
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


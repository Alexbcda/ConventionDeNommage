# Helpers partages pour placeholders certificat / bilan / CEA (sans WordML).

function Repair-CnsClientNumeroSignText {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { return '' }
    $t = [string]$Text
    if ($t.Length -lt 1) { return $t }
    $t = $t.Replace('N┬░', 'N°')
    $t = [regex]::Replace($t, '(?i)N\s*\?\s*(?=\d)', 'N°')
    $t = [regex]::Replace($t, 'N\s*\uFFFD\s*(?=\d)', 'N°')
    return $t
}

function ConvertTo-CnsDestructionCertificatePlaceholderValue {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '' }
    $t = Repair-CnsClientNumeroSignText -Text (([string]$Value).Trim())
    if ([string]::IsNullOrWhiteSpace($t)) { return '' }
    $norm = $t.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $norm.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    $plain = $sb.ToString().ToUpperInvariant()
    $sentinels = @(
        '-', '--', '—', '?', 'N/A', 'NA', 'ND', 'INCONNU', 'NON SPECIFIE', 'NON SPECIFIE',
        'A COMPLETER', 'A RENSEIGNER', 'NON RENSEIGNE', 'NON RENSEIGNEE', 'VIDE', 'TBD'
    )
    foreach ($s in $sentinels) {
        if ($plain -eq $s) { return '' }
    }
    if ($plain -match '^(A|A)\s*COMPL') { return '' }
    if ($plain -match 'COMPLETER') { return '' }
    $t = $t -replace '&apos;', "'"
    return $t
}

function Split-CnsCollecteurNomPrenom {
    param([AllowNull()][AllowEmptyString()][string]$CollecteurText)
    $t = ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $CollecteurText
    if ([string]::IsNullOrWhiteSpace($t)) {
        return @{ Nom = ''; Prenom = '' }
    }
    $parts = @(
        ($t -split '\s+') |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($parts.Count -lt 2) {
        return @{ Nom = $parts[0]; Prenom = '' }
    }
    return @{
        Prenom = $parts[0]
        Nom    = (($parts | Select-Object -Skip 1) -join ' ')
    }
}

function Normalize-CnsCertificateAgentLookupKey {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    $t = ([string]$Text).Trim()
    if ([string]::IsNullOrWhiteSpace($t)) { return '' }
    $norm = $t.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $norm.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString().ToUpperInvariant()
}

function Initialize-CnsCertificateAgentDbAccess {
    if ($script:CnsCertAgentDbLoadAttempted) { return }
    $script:CnsCertAgentDbLoadAttempted = $true
    $dbScript = Join-Path $PSScriptRoot '..\..\..\Database\Database.ps1'
    if (-not (Test-Path -LiteralPath $dbScript)) {
        Write-Warning ("[DESTRUCTION-CERT] Database.ps1 introuvable : {0}" -f $dbScript)
        return
    }
    try {
        . $dbScript
    }
    catch {
        Write-Warning ("[DESTRUCTION-CERT] Chargement Database.ps1 echoue : {0}" -f $_.Exception.Message)
    }
}

function Get-CnsCertificateAgentCatalog {
    if ($null -ne $script:CnsCertAgentCatalog) {
        return @($script:CnsCertAgentCatalog)
    }
    $script:CnsCertAgentCatalog = @()
    Initialize-CnsCertificateAgentDbAccess
    if (-not (Get-Command Get-Agents -ErrorAction SilentlyContinue)) {
        return @()
    }
    try {
        $script:CnsCertAgentCatalog = @(Get-Agents)
    }
    catch {
        Write-Warning ("[DESTRUCTION-CERT] Get-Agents echoue : {0}" -f $_.Exception.Message)
        $script:CnsCertAgentCatalog = @()
    }
    return @($script:CnsCertAgentCatalog)
}

function Find-CnsAgentNomByPrenomForCertificate {
    param([AllowNull()][string]$PrenomSearch)
    $key = Normalize-CnsCertificateAgentLookupKey -Text $PrenomSearch
    if ([string]::IsNullOrWhiteSpace($key)) { return $null }

    $agentHits = @()
    foreach ($agent in @(Get-CnsCertificateAgentCatalog)) {
        if ($null -eq $agent) { continue }
        try {
            $ap = Normalize-CnsCertificateAgentLookupKey -Text ([string]$agent.prenom)
            if ($ap -eq $key) { $agentHits += $agent }
        }
        catch { }
    }
    if ($agentHits.Count -lt 1) { return $null }

    $chosen = $agentHits[0]
    foreach ($agent in $agentHits) {
        try {
            $poste = Normalize-CnsCertificateAgentLookupKey -Text ([string]$agent.poste)
            if ($poste -match 'COLLECTEUR') { $chosen = $agent; break }
        }
        catch { }
    }

    try {
        $nom = [string]$chosen.nom
        if ([string]::IsNullOrWhiteSpace($nom)) { return $null }
        return $nom.Trim()
    }
    catch {
        return $null
    }
}

function Resolve-CnsCollecteurFieldsForCertificate {
    param([AllowNull()][string]$CollecteurExcelRaw)
    $npExcel = Split-CnsCollecteurNomPrenom -CollecteurText $CollecteurExcelRaw
    [string]$prenomOut = [string]$npExcel.Prenom
    if ([string]::IsNullOrWhiteSpace($prenomOut)) {
        $t = ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $CollecteurExcelRaw
        if (-not [string]::IsNullOrWhiteSpace($t)) {
            $prenomOut = (($t -split '\s+') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
        }
    }

    [string]$nomOut = [string]$npExcel.Nom
    $nomBdd = Find-CnsAgentNomByPrenomForCertificate -PrenomSearch $prenomOut
    if (-not [string]::IsNullOrWhiteSpace($nomBdd)) {
        $nomOut = $nomBdd
    }

    return @{
        Prenom = $prenomOut
        Nom    = $nomOut
    }
}

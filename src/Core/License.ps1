# License.ps1 — verification de licence ASSISTANT (etape 1 : module seul, non branche).
# PEM = enveloppe Base64 autour des parametres RSA XML (compatible Windows PowerShell 5.1).

$script:AssistantLicenseDirectory = $null

# Cle publique generee via Tools\New-AssistantLicenseKeyPair.ps1 (ne pas y mettre la cle privee).
$script:LicensePublicKeyPem = @'
-----BEGIN PUBLIC KEY-----
PFJTQUtleVZhbHVlPjxNb2R1bHVzPm90R3p1ZnF0VTBpQmdlWUlyZDVDK0g4VmRs
SVV0Z28wZkRYRVJKUTNSTXR3MkplcWxLaXVQZFU4SFFNSk1acEQrZTdJV1hwcW5O
STU2ZGNMaVg3VHl0TkNWNThCT21ENHNDV29jMmJtaGpPL2dBNHpCYUZtdFg3b3VD
OGx0TUgwaDdLTmRHbVNUZjNuTGdyblVjeFREUmZ5TkRKakVBNzlVVGNmWVBZa2Vi
aGZ2K1lvZUFjcmhKbUNrWmRaeWhlRTVDYnI5aWV6cUtWR2NtdWpWVHpkaWVIZS9h
MFVFaWNDc3JxczdZeG5zNDRzS2FJT01WZXptVDc3YzAreUQybVNrK3lRZ3ExUlFN
QStkVWxKVi8waHRTTFdxUi9HbHJtaVQrS1pIWCswZkt5eUhOSnl3ai9SS3YvdDJK
OVhvSjBYdFdnd1ZiVGZlaG1ZM0JteVR1RWhvUT09PC9Nb2R1bHVzPjxFeHBvbmVu
dD5BUUFCPC9FeHBvbmVudD48L1JTQUtleVZhbHVlPg==
-----END PUBLIC KEY-----
'@

function Get-LicenseDirectory {
    if (-not [string]::IsNullOrWhiteSpace($script:AssistantLicenseDirectory)) {
        return [string]$script:AssistantLicenseDirectory
    }
    return (Join-Path $env:LOCALAPPDATA 'ASSISTANT\license')
}

function Get-LicenseFilePath {
    return (Join-Path (Get-LicenseDirectory) 'license.lic')
}

function Get-LicenseLastSeenPath {
    return (Join-Path (Get-LicenseDirectory) 'lastseen.txt')
}

function Ensure-LicenseDirectory {
    $dir = Get-LicenseDirectory
    if (-not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }
    return $dir
}

function ConvertTo-LicensePem {
    param(
        [Parameter(Mandatory = $true)][string]$Body,
        [Parameter(Mandatory = $true)][ValidateSet('PUBLIC KEY', 'RSA PRIVATE KEY')][string]$Label
    )
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Body))
    $lines = for ($i = 0; $i -lt $b64.Length; $i += 64) {
        $len = [Math]::Min(64, $b64.Length - $i)
        $b64.Substring($i, $len)
    }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("-----BEGIN $Label-----")
    foreach ($line in $lines) { [void]$sb.AppendLine($line) }
    [void]$sb.AppendLine("-----END $Label-----")
    return $sb.ToString().TrimEnd() + [Environment]::NewLine
}

function ConvertFrom-LicensePem {
    param([Parameter(Mandatory = $true)][string]$Pem)
    $lines = $Pem -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object {
        $_ -and ($_ -notmatch '^-----')
    }
    $b64 = ($lines -join '')
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
}

function New-LicenseRsaFromPem {
    param(
        [Parameter(Mandatory = $true)][string]$Pem,
        [switch]$IncludePrivate
    )
    $xml = ConvertFrom-LicensePem -Pem $Pem
    $rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new()
    $rsa.PersistKeyInCsp = $false
    $rsa.FromXmlString($xml)
    return $rsa
}

function Get-LicenseCanonicalPayload {
    <#
    .SYNOPSIS
        Serialise le payload en JSON canonique (cles ordonnees, -Compress).
    #>
    param([Parameter(Mandatory = $true)]$Payload)

    $alertDates = @()
    if ($null -ne $Payload.alertDates) {
        $alertDates = @($Payload.alertDates | ForEach-Object { [string]$_ })
    }

    $ordered = [ordered]@{
        version    = [string]$Payload.version
        customer   = [string]$Payload.customer
        expiresOn  = [string]$Payload.expiresOn
        alertDates = @($alertDates)
        issuedAt   = [string]$Payload.issuedAt
        product    = [string]$Payload.product
    }
    return (($ordered | ConvertTo-Json -Compress -Depth 5))
}

function Test-LicenseSignature {
    param(
        [Parameter(Mandatory = $true)]$Payload,
        [Parameter(Mandatory = $true)][string]$SignatureBase64,
        [Parameter(Mandatory = $true)][string]$PublicKeyPem
    )
    if ([string]::IsNullOrWhiteSpace($PublicKeyPem) -or $PublicKeyPem -match 'REPLACE_ME') {
        return $false
    }
    $rsa = $null
    try {
        $rsa = New-LicenseRsaFromPem -Pem $PublicKeyPem
        $canonical = Get-LicenseCanonicalPayload -Payload $Payload
        $data = [Text.Encoding]::UTF8.GetBytes($canonical)
        $sig = [Convert]::FromBase64String($SignatureBase64)
        return [bool]$rsa.VerifyData($data, [System.Security.Cryptography.SHA256]::Create(), $sig)
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $rsa) { $rsa.Dispose() }
    }
}

function Get-LicenseLastSeenUtc {
    $path = Get-LicenseLastSeenPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }
    try {
        $raw = (Get-Content -LiteralPath $path -Raw -Encoding UTF8).Trim()
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return [DateTimeOffset]::Parse($raw, $null, [System.Globalization.DateTimeStyles]::RoundtripKind).UtcDateTime
    }
    catch {
        return $null
    }
}

function Set-LicenseLastSeenUtc {
    param([Parameter(Mandatory = $true)][datetime]$UtcDateTime)
    Ensure-LicenseDirectory | Out-Null
    $utc = [datetime]::SpecifyKind($UtcDateTime.ToUniversalTime(), [DateTimeKind]::Utc)
    $iso = $utc.ToString('o')
    Set-Content -LiteralPath (Get-LicenseLastSeenPath) -Value $iso -Encoding UTF8
}

function Get-LicenseStatus {
    <#
    .SYNOPSIS
        Lit et valide license.lic. Ne met pas a jour lastseen (pas d'effet de bord).
    #>
    $licensePath = Get-LicenseFilePath
    if (-not (Test-Path -LiteralPath $licensePath -PathType Leaf)) {
        return [pscustomobject]@{
            Status     = 'Missing'
            ExpiresOn  = $null
            Customer   = $null
            Message    = 'Licence absente'
            AlertDates = @()
        }
    }

    try {
        $raw = Get-Content -LiteralPath $licensePath -Raw -Encoding UTF8
        $doc = $raw | ConvertFrom-Json
    }
    catch {
        return [pscustomobject]@{
            Status     = 'Invalid'
            ExpiresOn  = $null
            Customer   = $null
            Message    = 'Licence invalide'
            AlertDates = @()
        }
    }

    if ($null -eq $doc.payload -or [string]::IsNullOrWhiteSpace([string]$doc.signature)) {
        return [pscustomobject]@{
            Status     = 'Invalid'
            ExpiresOn  = $null
            Customer   = $null
            Message    = 'Licence invalide'
            AlertDates = @()
        }
    }

    $payload = $doc.payload
    $okSig = Test-LicenseSignature -Payload $payload -SignatureBase64 ([string]$doc.signature) -PublicKeyPem $script:LicensePublicKeyPem
    if (-not $okSig) {
        return [pscustomobject]@{
            Status     = 'Invalid'
            ExpiresOn  = $null
            Customer   = $null
            Message    = 'Licence invalide'
            AlertDates = @()
        }
    }

    try {
        $expiresOn = [DateTimeOffset]::Parse([string]$payload.expiresOn, $null, [System.Globalization.DateTimeStyles]::RoundtripKind).UtcDateTime
    }
    catch {
        return [pscustomobject]@{
            Status     = 'Invalid'
            ExpiresOn  = $null
            Customer   = $null
            Message    = 'Licence invalide'
            AlertDates = @()
        }
    }

    $alertDates = @()
    if ($null -ne $payload.alertDates) {
        foreach ($a in @($payload.alertDates)) {
            try {
                $alertDates += [DateTimeOffset]::Parse([string]$a, $null, [System.Globalization.DateTimeStyles]::RoundtripKind).UtcDateTime
            }
            catch { }
        }
    }

    $now = [datetime]::UtcNow
    $lastSeen = Get-LicenseLastSeenUtc
    if ($null -ne $lastSeen) {
        $skewLimit = $lastSeen.AddDays(-1)
        if ($now -lt $skewLimit) {
            return [pscustomobject]@{
                Status     = 'Suspect'
                ExpiresOn  = $expiresOn
                Customer   = [string]$payload.customer
                Message    = 'Date systeme suspecte'
                AlertDates = $alertDates
            }
        }
    }

    if ($now -ge $expiresOn) {
        return [pscustomobject]@{
            Status     = 'Expired'
            ExpiresOn  = $expiresOn
            Customer   = [string]$payload.customer
            Message    = 'Licence expiree'
            AlertDates = $alertDates
        }
    }

    return [pscustomobject]@{
        Status     = 'Valid'
        ExpiresOn  = $expiresOn
        Customer   = [string]$payload.customer
        Message    = 'Licence valide'
        AlertDates = $alertDates
    }
}

function Test-LicenseValidity {
    $status = Get-LicenseStatus
    return ($status.Status -eq 'Valid')
}

function Show-LicenseAlert {
    param(
        [Parameter(Mandatory = $true)]$StatusObject
    )
    $message = [string]$StatusObject.Message
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = ('Statut licence : {0}' -f $StatusObject.Status)
    }
    $title = 'Licence ASSISTANT'
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $icon = switch ([string]$StatusObject.Status) {
            'Valid' { [System.Windows.Forms.MessageBoxIcon]::Information }
            'Missing' { [System.Windows.Forms.MessageBoxIcon]::Warning }
            'Expired' { [System.Windows.Forms.MessageBoxIcon]::Error }
            'Invalid' { [System.Windows.Forms.MessageBoxIcon]::Error }
            'Suspect' { [System.Windows.Forms.MessageBoxIcon]::Warning }
            default { [System.Windows.Forms.MessageBoxIcon]::Information }
        }
        [System.Windows.Forms.MessageBox]::Show(
            $message,
            $title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            $icon
        ) | Out-Null
    }
    catch {
        Write-Host ("[{0}] {1}" -f $title, $message) -ForegroundColor Yellow
    }
}

function Import-LicenseFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Host 'Import licence : fichier introuvable.' -ForegroundColor Red
        return $false
    }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $doc = $raw | ConvertFrom-Json
    }
    catch {
        Write-Host 'Import licence : fichier illisible ou JSON invalide.' -ForegroundColor Red
        return $false
    }
    if ($null -eq $doc.payload -or [string]::IsNullOrWhiteSpace([string]$doc.signature)) {
        Write-Host 'Import licence : structure invalide.' -ForegroundColor Red
        return $false
    }
    $okSig = Test-LicenseSignature -Payload $doc.payload -SignatureBase64 ([string]$doc.signature) -PublicKeyPem $script:LicensePublicKeyPem
    if (-not $okSig) {
        Write-Host 'Import licence : signature invalide — fichier non copie.' -ForegroundColor Red
        return $false
    }
    Ensure-LicenseDirectory | Out-Null
    $dest = Get-LicenseFilePath
    Copy-Item -LiteralPath $Path -Destination $dest -Force
    Write-Host ("Import licence : succes — {0}" -f $dest) -ForegroundColor Green
    return $true
}

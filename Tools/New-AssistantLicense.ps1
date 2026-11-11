#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Customer,
    [Parameter(Mandatory = $true)][datetime]$ExpiresOn,
    [datetime[]]$AlertDates = @(),
    [Parameter(Mandatory = $true)][string]$PrivateKeyPath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function ConvertFrom-LicensePem {
    param([Parameter(Mandatory = $true)][string]$Pem)
    $lines = $Pem -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object {
        $_ -and ($_ -notmatch '^-----')
    }
    $b64 = ($lines -join '')
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
}

function Get-LicenseCanonicalPayload {
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

if (-not (Test-Path -LiteralPath $PrivateKeyPath -PathType Leaf)) {
    throw "Cle privee introuvable : $PrivateKeyPath"
}

$expiresUtc = [datetime]::SpecifyKind($ExpiresOn.ToUniversalTime(), [DateTimeKind]::Utc)
if ($AlertDates.Count -eq 0) {
    $y = $expiresUtc.Year
    $AlertDates = @(
        [datetime]::SpecifyKind([datetime]::new($y, 5, 10, 0, 0, 0, [DateTimeKind]::Utc), [DateTimeKind]::Utc)
        [datetime]::SpecifyKind([datetime]::new($y, 5, 20, 0, 0, 0, [DateTimeKind]::Utc), [DateTimeKind]::Utc)
        [datetime]::SpecifyKind([datetime]::new($y, 5, 26, 0, 0, 0, [DateTimeKind]::Utc), [DateTimeKind]::Utc)
        [datetime]::SpecifyKind([datetime]::new($y, 5, 27, 0, 0, 0, [DateTimeKind]::Utc), [DateTimeKind]::Utc)
        [datetime]::SpecifyKind([datetime]::new($y, 5, 28, 0, 0, 0, [DateTimeKind]::Utc), [DateTimeKind]::Utc)
    )
}

$issuedAt = [datetime]::UtcNow
$payload = [pscustomobject]@{
    version    = '1.0'
    customer   = $Customer
    expiresOn  = $expiresUtc.ToString('o')
    alertDates = @($AlertDates | ForEach-Object {
            [datetime]::SpecifyKind($_.ToUniversalTime(), [DateTimeKind]::Utc).ToString('o')
        })
    issuedAt   = $issuedAt.ToString('o')
    product    = 'ASSISTANT'
}

$pem = Get-Content -LiteralPath $PrivateKeyPath -Raw -Encoding ASCII
$xml = ConvertFrom-LicensePem -Pem $pem
$rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new()
$rsa.PersistKeyInCsp = $false
try {
    $rsa.FromXmlString($xml)
    $canonical = Get-LicenseCanonicalPayload -Payload $payload
    $data = [Text.Encoding]::UTF8.GetBytes($canonical)
    $sigBytes = $rsa.SignData($data, [System.Security.Cryptography.SHA256]::Create())
    $sigB64 = [Convert]::ToBase64String($sigBytes)

    $doc = [ordered]@{
        payload   = $payload
        signature = $sigB64
    }
    $json = ($doc | ConvertTo-Json -Depth 6)

    $outDir = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Path $outDir -Force
    }
    Set-Content -LiteralPath $OutputPath -Value $json -Encoding UTF8

    Write-Host ''
    Write-Host 'Licence generee.' -ForegroundColor Green
    Write-Host ("Customer   : {0}" -f $Customer)
    Write-Host ("ExpiresOn  : {0}" -f $payload.expiresOn)
    Write-Host ("AlertDates : {0}" -f ($payload.alertDates -join ', '))
    Write-Host ("Output     : {0}" -f $OutputPath)
}
finally {
    $rsa.Dispose()
}

#Requires -Version 5.1
<#
.SYNOPSIS
    Genere une paire de cles RSA 2048 (PEM / XML interne) pour les licences ASSISTANT.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PrivateKeyPath,
    [Parameter(Mandatory = $true)][string]$PublicKeyPath
)

$ErrorActionPreference = 'Stop'

function ConvertTo-LicensePem {
    param(
        [Parameter(Mandatory = $true)][string]$Body,
        [Parameter(Mandatory = $true)][string]$Label
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

$rsa = [System.Security.Cryptography.RSACryptoServiceProvider]::new(2048)
$rsa.PersistKeyInCsp = $false
try {
    $privateXml = $rsa.ToXmlString($true)
    $publicXml = $rsa.ToXmlString($false)

    $privatePem = ConvertTo-LicensePem -Body $privateXml -Label 'RSA PRIVATE KEY'
    $publicPem = ConvertTo-LicensePem -Body $publicXml -Label 'PUBLIC KEY'

    $privDir = Split-Path -Parent $PrivateKeyPath
    if (-not [string]::IsNullOrWhiteSpace($privDir) -and -not (Test-Path -LiteralPath $privDir)) {
        $null = New-Item -ItemType Directory -Path $privDir -Force
    }
    $pubDir = Split-Path -Parent $PublicKeyPath
    if (-not [string]::IsNullOrWhiteSpace($pubDir) -and -not (Test-Path -LiteralPath $pubDir)) {
        $null = New-Item -ItemType Directory -Path $pubDir -Force
    }

    Set-Content -LiteralPath $PrivateKeyPath -Value $privatePem -Encoding ASCII
    Set-Content -LiteralPath $PublicKeyPath -Value $publicPem -Encoding ASCII

    Write-Host ''
    Write-Host 'Paire de cles generee.' -ForegroundColor Green
    Write-Host ("Privee : {0}" -f $PrivateKeyPath)
    Write-Host ("Publique : {0}" -f $PublicKeyPath)
    Write-Host ''
    Write-Host 'WARNING: Ne commitez JAMAIS la cle privee. Stockez-la hors du depot (ex. C:\Users\<vous>\.assistant-license\private.pem).' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Cle publique (a copier dans $script:LicensePublicKeyPem de src\Core\License.ps1) :' -ForegroundColor Cyan
    Write-Host $publicPem
}
finally {
    $rsa.Dispose()
}

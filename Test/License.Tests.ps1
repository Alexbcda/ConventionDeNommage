#Requires -Version 5.1
Describe 'License module (etape 1)' {

    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $licenseScript = Join-Path $repoRoot 'src\Core\License.ps1'
        $script:KeyPairTool = Join-Path $repoRoot 'Tools\New-AssistantLicenseKeyPair.ps1'
        $script:LicenseTool = Join-Path $repoRoot 'Tools\New-AssistantLicense.ps1'
        . $licenseScript

        $script:TestRoot = Join-Path $env:TEMP ("assistant_license_tests_{0}" -f ([Guid]::NewGuid().ToString('N')))
        $null = New-Item -ItemType Directory -Path $script:TestRoot -Force
        $script:AssistantLicenseDirectory = Join-Path $script:TestRoot 'license'
        $null = New-Item -ItemType Directory -Path $script:AssistantLicenseDirectory -Force

        $script:PrivateKeyPath = Join-Path $script:TestRoot 'private.pem'
        $script:PublicKeyPath = Join-Path $script:TestRoot 'public.pem'
        & $script:KeyPairTool -PrivateKeyPath $script:PrivateKeyPath -PublicKeyPath $script:PublicKeyPath | Out-Null
        $script:LicensePublicKeyPem = Get-Content -LiteralPath $script:PublicKeyPath -Raw -Encoding ASCII
    }

    AfterAll {
        if (Test-Path -LiteralPath $script:TestRoot) {
            Remove-Item -LiteralPath $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    BeforeEach {
        $script:AssistantLicenseDirectory = Join-Path $script:TestRoot 'license'
        if (-not (Test-Path -LiteralPath $script:AssistantLicenseDirectory)) {
            $null = New-Item -ItemType Directory -Path $script:AssistantLicenseDirectory -Force
        }
        Get-ChildItem -LiteralPath $script:AssistantLicenseDirectory -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        $script:LicensePublicKeyPem = Get-Content -LiteralPath $script:PublicKeyPath -Raw -Encoding ASCII
    }

    It 'Get-LicenseStatus : licence absente -> Missing' {
        $s = Get-LicenseStatus
        $s.Status | Should Be 'Missing'
        $s.Message | Should Be 'Licence absente'
    }

    It 'Get-LicenseStatus : licence valide -> Valid' {
        $out = Join-Path $script:TestRoot 'valid.lic'
        & $script:LicenseTool -Customer 'Test SA' -ExpiresOn ([datetime]::UtcNow.AddYears(1)) `
            -PrivateKeyPath $script:PrivateKeyPath -OutputPath $out | Out-Null
        Copy-Item -LiteralPath $out -Destination (Get-LicenseFilePath) -Force
        $s = Get-LicenseStatus
        $s.Status | Should Be 'Valid'
        $s.Customer | Should Be 'Test SA'
    }

    It 'Get-LicenseStatus : licence expiree -> Expired' {
        $out = Join-Path $script:TestRoot 'expired.lic'
        & $script:LicenseTool -Customer 'Test SA' -ExpiresOn ([datetime]::UtcNow.AddDays(-2)) `
            -PrivateKeyPath $script:PrivateKeyPath -OutputPath $out | Out-Null
        Copy-Item -LiteralPath $out -Destination (Get-LicenseFilePath) -Force
        $s = Get-LicenseStatus
        $s.Status | Should Be 'Expired'
    }

    It 'Get-LicenseStatus : payload modifie -> Invalid' {
        $out = Join-Path $script:TestRoot 'tamper.lic'
        & $script:LicenseTool -Customer 'Test SA' -ExpiresOn ([datetime]::UtcNow.AddYears(1)) `
            -PrivateKeyPath $script:PrivateKeyPath -OutputPath $out | Out-Null
        $doc = Get-Content -LiteralPath $out -Raw -Encoding UTF8 | ConvertFrom-Json
        $doc.payload.customer = 'Hacker'
        ($doc | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Get-LicenseFilePath) -Encoding UTF8
        $s = Get-LicenseStatus
        $s.Status | Should Be 'Invalid'
    }

    It 'Get-LicenseStatus : LastSeenUtc > Now -> Suspect' {
        $out = Join-Path $script:TestRoot 'skew.lic'
        & $script:LicenseTool -Customer 'Test SA' -ExpiresOn ([datetime]::UtcNow.AddYears(1)) `
            -PrivateKeyPath $script:PrivateKeyPath -OutputPath $out | Out-Null
        Copy-Item -LiteralPath $out -Destination (Get-LicenseFilePath) -Force
        Set-LicenseLastSeenUtc -UtcDateTime ([datetime]::UtcNow.AddDays(10))
        $s = Get-LicenseStatus
        $s.Status | Should Be 'Suspect'
        $s.Message | Should Be 'Date systeme suspecte'
    }

    It 'Import-LicenseFile : fichier valide -> copie OK' {
        $out = Join-Path $script:TestRoot 'import-ok.lic'
        & $script:LicenseTool -Customer 'Import SA' -ExpiresOn ([datetime]::UtcNow.AddYears(1)) `
            -PrivateKeyPath $script:PrivateKeyPath -OutputPath $out | Out-Null
        $ok = Import-LicenseFile -Path $out
        $ok | Should Be $true
        (Test-Path -LiteralPath (Get-LicenseFilePath)) | Should Be $true
        (Get-LicenseStatus).Status | Should Be 'Valid'
    }

    It 'Import-LicenseFile : fichier invalide -> rejet sans copie' {
        $bad = Join-Path $script:TestRoot 'import-bad.lic'
        @{ payload = @{ customer = 'x'; version = '1.0'; expiresOn = '2099-01-01T00:00:00Z'; alertDates = @(); issuedAt = '2026-01-01T00:00:00Z'; product = 'ASSISTANT' }; signature = 'AAAA' } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $bad -Encoding UTF8
        $destBefore = Test-Path -LiteralPath (Get-LicenseFilePath)
        $ok = Import-LicenseFile -Path $bad
        $ok | Should Be $false
        if (-not $destBefore) {
            (Test-Path -LiteralPath (Get-LicenseFilePath)) | Should Be $false
        }
    }
}

Describe 'License wiring in Main.ps1 (etape 2)' {

    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $script:MainPs1Path = Join-Path $repoRoot 'src\Main.ps1'
        $script:MainContent = Get-Content -LiteralPath $script:MainPs1Path -Raw -Encoding UTF8
    }

    It 'Main.ps1 dot-source License.ps1' {
        ($script:MainContent -match 'Core\\License\.ps1') | Should Be $true
    }

    It 'Main.ps1 appelle Get-LicenseStatus avant Start-GUI' {
        $idxStatus = $script:MainContent.IndexOf('Get-LicenseStatus')
        $idxGui = $script:MainContent.IndexOf('Start-GUI')
        ($idxStatus -ge 0) | Should Be $true
        ($idxGui -ge 0) | Should Be $true
        ($idxStatus -lt $idxGui) | Should Be $true
    }

    It 'Main.ps1 appelle Set-LicenseLastSeenUtc' {
        ($script:MainContent -match 'Set-LicenseLastSeenUtc') | Should Be $true
    }
}

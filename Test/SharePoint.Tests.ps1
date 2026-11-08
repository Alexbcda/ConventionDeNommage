#Requires -Version 5.1
<#
.SYNOPSIS
    Tests Pester — integration SharePoint / Microsoft Graph (manuel, hors pipeline principal).

.NOTES
    Non execute automatiquement : activer avec TEST_SHAREPOINT=1.

    $env:TEST_SHAREPOINT = '1'
    Invoke-Pester -Path .\Test\SharePoint.Tests.ps1

    Variables optionnelles :
      CN_SHAREPOINT_SITE_URL      (defaut: naevaelisealpes.sharepoint.com:/sites/EliseAlpes)
      CN_SHAREPOINT_PLANNING_FILE (defaut: Planning GRENOBLE 2026.xlsm)
#>

[CmdletBinding()]
param()

$script:SharePointModulePath = Join-Path $PSScriptRoot '..\src\Common\CnsSharePointConnector.ps1'
if (Test-Path -LiteralPath $script:SharePointModulePath) {
    . ([string](Resolve-Path -LiteralPath $script:SharePointModulePath))
}
else {
    Write-Host 'CnsSharePointConnector.ps1 absent du depot — tests SharePoint desactives.' -ForegroundColor Yellow
}

# Lot 2 — charger ConfigManager pour que Get-SharePointStableIds / Set-SharePointStableIds soient mockables
$script:ConfigManagerPath = Join-Path $PSScriptRoot '..\src\Core\ConfigManager.ps1'
if (Test-Path -LiteralPath $script:ConfigManagerPath) {
    . ([string](Resolve-Path -LiteralPath $script:ConfigManagerPath))
}

$script:DefaultSharePointSiteUrl = $(if (-not [string]::IsNullOrWhiteSpace($env:CN_SHAREPOINT_SITE_URL)) {
        $env:CN_SHAREPOINT_SITE_URL.Trim()
    }
    else {
        'naevaelisealpes.sharepoint.com:/sites/EliseAlpes'
    })

$script:DefaultSharePointPlanningFile = $(if (-not [string]::IsNullOrWhiteSpace($env:CN_SHAREPOINT_PLANNING_FILE)) {
        $env:CN_SHAREPOINT_PLANNING_FILE.Trim()
    }
    else {
        'Planning GRENOBLE 2026.xlsm'
    })

$script:SharePointTestsEnabled = (Test-Path -LiteralPath $script:SharePointModulePath) -and
    ($env:TEST_SHAREPOINT -in @('1', 'true', 'TRUE', 'yes', 'YES'))

Describe 'SharePoint Integration' {

    It 'T1 - Se connecte a Microsoft Graph' -Pending:(-not $script:SharePointTestsEnabled) {
        $result = Connect-SharePointGraph -Interactive
        $result | Should Be $true
        $ctx = Get-MgContext
        $ctx | Should Not BeNullOrEmpty
        [string]$ctx.Account | Should Not BeNullOrEmpty
    }

    It 'Verifie l existence du fichier planning sur SharePoint' -Pending:(-not $script:SharePointTestsEnabled) {
        $exists = Test-SharePointDriveItemExists -SiteUrl $script:DefaultSharePointSiteUrl `
            -FilePathOnSharePoint $script:DefaultSharePointPlanningFile
        $exists | Should Be $true
    }

    It 'Telecharge le fichier Planning GRENOBLE 2026.xlsm' -Pending:(-not $script:SharePointTestsEnabled) {
        $dest = Join-Path $env:TEMP 'Planning_GRENOBLE_2026.xlsm'
        $result = Get-SharePointFile -SiteUrl $script:DefaultSharePointSiteUrl `
            -FilePathOnSharePoint $script:DefaultSharePointPlanningFile `
            -DestinationPath $dest
        $result | Should Be $true
        (Test-Path -LiteralPath $dest -PathType Leaf) | Should Be $true
        (Get-Item -LiteralPath $dest).Length | Should BeGreaterThan 0
    }

    It 'Test-SharePointConnection : test complet bout en bout' -Pending:(-not $script:SharePointTestsEnabled) {
        $dest = Join-Path $env:TEMP ("Planning_GRENOBLE_2026_test_{0}.xlsm" -f ([Guid]::NewGuid().ToString('N')))
        try {
            $result = Test-SharePointConnection -SiteUrl $script:DefaultSharePointSiteUrl `
                -FilePathOnSharePoint $script:DefaultSharePointPlanningFile `
                -DestinationPath $dest
            $result | Should Be $true
            (Test-Path -LiteralPath $dest -PathType Leaf) | Should Be $true
        }
        finally {
            if (Test-Path -LiteralPath $dest) {
                Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'Connect-SharePointPlanning retourne un objet avec Status' {
        Mock Connect-SharePointGraph { return $true }
        Mock Get-SharePointPlanningFile { return $true }
        Mock Test-CnsSharePointGraphModuleAvailable { return $true }
        Mock Test-CnsSharePointGraphSessionValid { return $true }
        Mock Import-CnsSharePointGraphModule { }
        $local = Join-Path $env:TEMP ("cn_sp_test_{0}.xlsm" -f ([Guid]::NewGuid().ToString('N')))
        try {
            Set-Content -LiteralPath $local -Value 'test' -Encoding ASCII
            Mock Get-CnsSharePointLocalPlanningPath { return $local }
            $result = Connect-SharePointPlanning -ForceRefresh
            $result.Status | Should Be 'Connected'
            $result.FilePath | Should Be $local
        }
        finally {
            if (Test-Path -LiteralPath $local) { Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'SharePoint Lot 2 - download par ID (feature flag)' {
    BeforeEach {
        $script:CapturedUris = [System.Collections.Generic.List[string]]::new()
        $script:SetAppConfigCalls = [System.Collections.Generic.List[string]]::new()
        $script:Lot2Dest = Join-Path $env:TEMP ("cn_lot2_{0}.xlsm" -f ([Guid]::NewGuid().ToString('N')))
        Mock Import-CnsSharePointGraphModule { }
        Mock Get-MgContext { return @{ Account = 'user@test' } }
        Mock Connect-SharePointGraph { return $true }
        Mock Set-AppConfig {
            param([string]$Key, [string]$Value)
            [void]$script:SetAppConfigCalls.Add($Key)
        }
        Mock Invoke-MgGraphRequest {
            param($Method, $Uri, $OutputFilePath)
            [void]$script:CapturedUris.Add([string]$Uri)
            if (-not [string]::IsNullOrWhiteSpace($OutputFilePath)) {
                Set-Content -LiteralPath $OutputFilePath -Value 'PK-fake-xlsm' -Encoding ASCII
            }
        }
    }

    AfterEach {
        foreach ($p in @($script:Lot2Dest, "$($script:Lot2Dest).download")) {
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'Flag false + IDs presents -> utilise SharePointApiUrl' {
        Mock Test-SharePointUseStableIdsFlag { return $false }
        Mock Get-SharePointStableIds {
            return [pscustomobject]@{ DriveId = 'drive-1'; ItemId = 'item-1'; PlanningFileName = $null; LastValidatedAt = $null; SourceUrl = $null }
        }
        $url = 'https://graph.microsoft.com/v1.0/sites/host:/sites/X/drive/root:/Planning.xlsm:/content'
        $ok = Get-SharePointPlanningFile -Url $url -LocalPath $script:Lot2Dest
        $ok | Should Be $true
        $script:CapturedUris.Count | Should Be 1
        $script:CapturedUris[0] | Should Be $url
        ($script:CapturedUris[0] -match '/drives/') | Should Be $false
    }

    It 'Flag true + IDs absents -> utilise SharePointApiUrl (fallback)' {
        Mock Test-SharePointUseStableIdsFlag { return $true }
        Mock Get-SharePointStableIds {
            return [pscustomobject]@{ DriveId = $null; ItemId = $null; PlanningFileName = $null; LastValidatedAt = $null; SourceUrl = $null }
        }
        $url = 'https://graph.microsoft.com/v1.0/sites/host:/sites/X/drive/root:/Planning.xlsm:/content'
        $ok = Get-SharePointPlanningFile -Url $url -LocalPath $script:Lot2Dest
        $ok | Should Be $true
        $script:CapturedUris.Count | Should Be 1
        $script:CapturedUris[0] | Should Be $url
    }

    It 'Flag true + IDs presents -> utilise /drives/.../items/.../content' {
        Mock Test-SharePointUseStableIdsFlag { return $true }
        Mock Get-SharePointStableIds {
            return [pscustomobject]@{ DriveId = 'drive-abc'; ItemId = 'item-xyz'; PlanningFileName = $null; LastValidatedAt = $null; SourceUrl = $null }
        }
        $url = 'https://graph.microsoft.com/v1.0/sites/host:/sites/X/drive/root:/Planning.xlsm:/content'
        $ok = Get-SharePointPlanningFile -Url $url -LocalPath $script:Lot2Dest
        $ok | Should Be $true
        $script:CapturedUris.Count | Should Be 1
        $script:CapturedUris[0] | Should Be 'https://graph.microsoft.com/v1.0/drives/drive-abc/items/item-xyz/content'
    }

    It 'Flag true + IDs presents + echec ID -> fallback SharePointApiUrl' {
        Mock Test-SharePointUseStableIdsFlag { return $true }
        Mock Get-SharePointStableIds {
            return [pscustomobject]@{ DriveId = 'drive-dead'; ItemId = 'item-dead'; PlanningFileName = $null; LastValidatedAt = $null; SourceUrl = $null }
        }
        $url = 'https://graph.microsoft.com/v1.0/sites/host:/sites/X/drive/root:/Planning.xlsm:/content'
        $script:IdCallCount = 0
        Mock Invoke-MgGraphRequest {
            param($Method, $Uri, $OutputFilePath)
            [void]$script:CapturedUris.Add([string]$Uri)
            $script:IdCallCount++
            if ($Uri -match '/drives/') {
                throw '404 itemNotFound'
            }
            if (-not [string]::IsNullOrWhiteSpace($OutputFilePath)) {
                Set-Content -LiteralPath $OutputFilePath -Value 'PK-fallback' -Encoding ASCII
            }
        }
        $ok = Get-SharePointPlanningFile -Url $url -LocalPath $script:Lot2Dest
        $ok | Should Be $true
        $script:CapturedUris.Count | Should Be 2
        $script:CapturedUris[0] | Should Match '/drives/drive-dead/items/item-dead/content'
        $script:CapturedUris[1] | Should Be $url
    }

    It 'Lot 2 ne modifie jamais SharePointApiUrl' {
        Mock Test-SharePointUseStableIdsFlag { return $true }
        Mock Get-SharePointStableIds {
            return [pscustomobject]@{ DriveId = 'drive-abc'; ItemId = 'item-xyz'; PlanningFileName = $null; LastValidatedAt = $null; SourceUrl = $null }
        }
        $url = 'https://graph.microsoft.com/v1.0/sites/host:/sites/X/drive/root:/Planning.xlsm:/content'
        $null = Get-SharePointPlanningFile -Url $url -LocalPath $script:Lot2Dest
        ($script:SetAppConfigCalls -contains 'SharePointApiUrl') | Should Be $false
    }
}
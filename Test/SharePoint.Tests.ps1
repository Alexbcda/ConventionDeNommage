#Requires -Version 5.1
<#
.SYNOPSIS
    Tests Pester — integration SharePoint / Microsoft Graph (manuel, hors pipeline principal).

.NOTES
    Non execute automatiquement : activer avec TEST_SHAREPOINT=1.

    $env:TEST_SHAREPOINT = '1'
    Invoke-Pester -Path .\Test\SharePoint.Tests.ps1

    Variables optionnelles :
      CN_SHAREPOINT_SITE_URL      (defaut: naevaelisealpes.sharepoint.com:/sites/EliseAlpesFontaine)
      CN_SHAREPOINT_PLANNING_FILE (defaut: Planning FONTAINE 2026.xlsm)
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
        'naevaelisealpes.sharepoint.com:/sites/EliseAlpesFontaine'
    })

$script:DefaultSharePointPlanningFile = $(if (-not [string]::IsNullOrWhiteSpace($env:CN_SHAREPOINT_PLANNING_FILE)) {
        $env:CN_SHAREPOINT_PLANNING_FILE.Trim()
    }
    else {
        'Planning FONTAINE 2026.xlsm'
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

    It 'Telecharge le fichier Planning FONTAINE 2026.xlsm' -Pending:(-not $script:SharePointTestsEnabled) {
        $dest = Join-Path $env:TEMP 'Planning_FONTAINE_2026.xlsm'
        $result = Get-SharePointFile -SiteUrl $script:DefaultSharePointSiteUrl `
            -FilePathOnSharePoint $script:DefaultSharePointPlanningFile `
            -DestinationPath $dest
        $result | Should Be $true
        (Test-Path -LiteralPath $dest -PathType Leaf) | Should Be $true
        (Get-Item -LiteralPath $dest).Length | Should BeGreaterThan 0
    }

    It 'Test-SharePointConnection : test complet bout en bout' -Pending:(-not $script:SharePointTestsEnabled) {
        $dest = Join-Path $env:TEMP ("Planning_FONTAINE_2026_test_{0}.xlsm" -f ([Guid]::NewGuid().ToString('N')))
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
        # Lot 2 historique : ne pas declencher Resolve (nouveaux appels Graph hors perimetre).
        Mock Resolve-SharePointPlanningIds { return $null }
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

Describe 'SharePoint Resolve-SharePointPlanningIds' {
    It 'GET metadata sans /content ; persiste DriveId/ItemId' {
        $script:MetaUri = $null
        $script:SavedDrive = $null
        $script:SavedItem = $null
        Mock Import-CnsSharePointGraphModule { }
        Mock Get-MgContext { return @{ Account = 'user@test' } }
        Mock Connect-SharePointGraph { return $true }
        Mock Invoke-MgGraphRequest {
            param($Method, $Uri, $OutputFilePath)
            $script:MetaUri = [string]$Uri
            return [pscustomobject]@{
                id              = 'item-xyz'
                name            = 'Planning FONTAINE 2026.xlsm'
                parentReference = [pscustomobject]@{ driveId = 'drive-abc' }
            }
        }
        Mock Set-SharePointStableIds {
            param($DriveId, $ItemId, $CentreId)
            $script:SavedDrive = $DriveId
            $script:SavedItem = $ItemId
        }

        $url = 'https://graph.microsoft.com/v1.0/sites/host:/sites/EliseAlpesFontaine/drive/root:/Planning%20FONTAINE%202026.xlsm:/content'
        $r = Resolve-SharePointPlanningIds -Url $url -CentreId 'fontaine'
        $r.DriveId | Should Be 'drive-abc'
        $r.ItemId | Should Be 'item-xyz'
        ($script:MetaUri -match '(?i)/content/?$') | Should Be $false
        ($script:MetaUri -match '(?i)EliseAlpesFontaine') | Should Be $true
        ($script:MetaUri -match '(?i)Planning') | Should Be $true
        $script:SavedDrive | Should Be 'drive-abc'
        $script:SavedItem | Should Be 'item-xyz'
    }
}

Describe 'SharePoint Graph App Registration' {
    It 'scopes = Sites.Selected + offline_access (sans Files.Read.All)' {
        ($script:CnsSharePointGraphScopes -contains 'Sites.Selected') | Should Be $true
        ($script:CnsSharePointGraphScopes -contains 'Files.Read.All') | Should Be $false
        ($script:CnsSharePointGraphScopes -contains 'offline_access') | Should Be $true
        ($script:CnsSharePointGraphScopes -contains 'Sites.Read.All') | Should Be $false
    }

    It 'Connect-MgGraph recoit -ClientId si GraphClientId configure' {
        $script:CapturedClientId = $null
        Mock Get-GraphClientId { return '11111111-2222-3333-4444-555555555555' }
        Mock Show-CnsSharePointDeviceCodeDialog { }
        Mock Connect-MgGraph {
            param(
                $ClientId,
                $Scopes,
                $UseDeviceAuthentication,
                $UseWebAuthentication,
                $NoWelcome,
                $ErrorAction
            )
            $script:CapturedClientId = $ClientId
        }

        Invoke-CnsSharePointGraphConnectInteractive

        $script:CapturedClientId | Should Be '11111111-2222-3333-4444-555555555555'
    }

    It 'refuse Connect-MgGraph si GraphClientId absent' {
        $script:ConnectCalled = $false
        Mock Get-GraphClientId { return $null }
        Mock Connect-MgGraph { $script:ConnectCalled = $true }

        { Invoke-CnsSharePointGraphConnectInteractive } | Should Throw 'Client ID ASSISTANT non configure'
        $script:ConnectCalled | Should Be $false
    }

    It 'Set-GraphClientId rejette une valeur vide' {
        Mock Set-AppConfig { throw 'Set-AppConfig ne doit pas etre appele' }
        { Set-GraphClientId -ClientId '' } | Should Throw 'valeur vide'
        { Set-GraphClientId -ClientId '   ' } | Should Throw 'valeur vide'
    }

    It 'Set-GraphClientId accepte un GUID valide' {
        $script:SavedGraphClientId = $null
        Mock Set-AppConfig {
            param($Key, $Value)
            if ($Key -eq 'GraphClientId') { $script:SavedGraphClientId = $Value }
        }
        $guid = '11111111-2222-3333-4444-555555555555'
        $r = Set-GraphClientId -ClientId "  $guid  "
        $r | Should Be $guid
        $script:SavedGraphClientId | Should Be $guid
    }
}

Describe 'SharePoint Resolve-CnsSharePointConnectError AADSTS' {
    It 'AADSTS65001 retourne ConsentMissing' {
        $r = Resolve-CnsSharePointConnectError -ErrorMessage 'AADSTS65001: The user or administrator has not consented'
        $r.Status | Should Be 'ConsentMissing'
        $r.Message | Should Match 'IT-3'
    }

    It 'AADSTS7000218 retourne PublicClientFlowsDisabled' {
        $r = Resolve-CnsSharePointConnectError -ErrorMessage 'AADSTS7000218: The request body must contain client_secret'
        $r.Status | Should Be 'PublicClientFlowsDisabled'
        $r.Message | Should Match 'IT-2'
    }

    It '403 reste Denied (non-regression)' {
        $r = Resolve-CnsSharePointConnectError -ErrorMessage '403 Forbidden Access denied'
        $r.Status | Should Be 'Denied'
    }

    It '401 Unauthorized retourne Unauthorized' {
        $r = Resolve-CnsSharePointConnectError -ErrorMessage '401 Unauthorized'
        $r.Status | Should Be 'Unauthorized'
        $r.Message | Should Match '401'
    }

    It '403 Forbidden reste Denied apres retrait unauthorized' {
        $r = Resolve-CnsSharePointConnectError -ErrorMessage '403 Forbidden'
        $r.Status | Should Be 'Denied'
    }
}

Describe 'Show-ChangeUrlDialog validation URL fichier' {
    BeforeEach {
        $script:SaveCalled = $false
        $script:MessageBoxCaptions = [System.Collections.Generic.List[string]]::new()
        $script:CnsSharePointMessageBoxMock = {
            param($Text, $Caption, $Buttons, $Icon)
            [void]$script:MessageBoxCaptions.Add([string]$Caption)
            return [System.Windows.Forms.DialogResult]::OK
        }
        Mock Get-SharePointPlanningUrl {
            return 'https://graph.microsoft.com/v1.0/sites/host:/sites/EliseAlpesFontaine/drive/root:/OLD.xlsm:/content'
        }
        Mock Get-SharePointBrowserUrlFromGraph { return 'https://host/sites/EliseAlpesFontaine' }
        Mock Save-SharePointApiUrlConfig {
            param($ApiUrl)
            $script:SaveCalled = $true
            $script:SavedApiUrl = $ApiUrl
        }
    }

    AfterEach {
        $script:CnsSharePointMessageBoxMock = $null
    }

    It 'accepte une URL Graph fichier (/drive/root:/...:/content)' {
        $fileUrl = 'https://graph.microsoft.com/v1.0/sites/host:/sites/EliseAlpesFontaine/drive/root:/Planning%20FONTAINE%202026.xlsm:/content'
        Mock Show-SharePointUrlConfigDialog { return $fileUrl }

        $ok = Show-ChangeUrlDialog
        $ok | Should Be $true
        $script:SaveCalled | Should Be $true
        $script:SavedApiUrl | Should Be $fileUrl
    }

    It 'accepte une URL navigateur .xlsm' {
        $browserFileUrl = 'https://naevaelisealpes.sharepoint.com/sites/EliseAlpesFontaine/Shared%20Documents/Planning%20FONTAINE%202026.xlsm'
        Mock Show-SharePointUrlConfigDialog { return $browserFileUrl }

        $ok = Show-ChangeUrlDialog
        $ok | Should Be $true
        $script:SaveCalled | Should Be $true
        $script:SavedApiUrl | Should Be $browserFileUrl
    }

    It 'refuse une URL de site SharePoint' {
        $siteUrl = 'https://naevaelisealpes.sharepoint.com/sites/EliseAlpesFontaine'
        Mock Show-SharePointUrlConfigDialog { return $siteUrl }

        $ok = Show-ChangeUrlDialog
        $ok | Should Be $false
        $script:SaveCalled | Should Be $false
        ($script:MessageBoxCaptions -contains 'URL de fichier requise') | Should Be $true
    }
}

Describe 'Show-FirstLaunchConfig validation URL fichier' {
    BeforeEach {
        $script:SaveCalled = $false
        $script:MessageBoxCaptions = [System.Collections.Generic.List[string]]::new()
        $script:CnsSharePointMessageBoxMock = {
            param($Text, $Caption, $Buttons, $Icon)
            [void]$script:MessageBoxCaptions.Add([string]$Caption)
            return [System.Windows.Forms.DialogResult]::OK
        }
        Mock Save-SharePointApiUrlConfig {
            param($ApiUrl)
            $script:SaveCalled = $true
            $script:SavedApiUrl = $ApiUrl
        }
    }

    AfterEach {
        $script:CnsSharePointMessageBoxMock = $null
    }

    It 'refuse une URL de site SharePoint' {
        $siteUrl = 'https://naevaelisealpes.sharepoint.com/sites/EliseAlpesFontaine'
        Mock Show-SharePointUrlConfigDialog { return $siteUrl }

        $ok = Show-FirstLaunchConfig
        $ok | Should Be $false
        $script:SaveCalled | Should Be $false
        ($script:MessageBoxCaptions -contains 'URL de fichier requise') | Should Be $true
    }

    It 'accepte une URL fichier .xlsm' {
        $fileUrl = 'https://naevaelisealpes.sharepoint.com/sites/EliseAlpesFontaine/Shared%20Documents/Planning%20FONTAINE%202026.xlsm'
        Mock Show-SharePointUrlConfigDialog { return $fileUrl }

        $ok = Show-FirstLaunchConfig
        $ok | Should Be $true
        $script:SaveCalled | Should Be $true
        $script:SavedApiUrl | Should Be $fileUrl
    }
}
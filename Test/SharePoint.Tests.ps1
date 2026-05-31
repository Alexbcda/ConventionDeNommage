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

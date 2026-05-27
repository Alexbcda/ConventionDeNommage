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

$script:SharePointModulePath = Join-Path $PSScriptRoot '..\src\ODM\PdfPlanningOptimizer\Services\SharePointDownload.ps1' | Resolve-Path
. ([string]$script:SharePointModulePath)

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

$script:SharePointTestsEnabled = ($env:TEST_SHAREPOINT -in @('1', 'true', 'TRUE', 'yes', 'YES'))

Describe 'SharePoint Integration' {

    It 'Se connecte a Microsoft Graph' -Pending:(-not $script:SharePointTestsEnabled) {
        $result = Connect-SharePointGraph
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
}

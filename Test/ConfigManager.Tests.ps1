Describe 'ConfigManager - gestion centre' {

    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $configManagerPath = Join-Path $repoRoot 'src\Core\ConfigManager.ps1'
        . $configManagerPath
    }

    It 'Get-CnsUnrecognizedCentreDisplayName : libelle explicite' {
        Get-CnsUnrecognizedCentreDisplayName | Should Be 'Centre non reconnu'
    }

    It 'Get-CurrentCentre : URL inconnue sans CentreName -> Centre non reconnu' {
        Mock Get-AppConfig {
            param([string]$Key)
            switch ($Key) {
                'CentreId' { return '' }
                'CentreName' { return '' }
                'SharePointApiUrl' { return 'https://example.invalid/custom-url' }
            }
            return $null
        }
        Mock Get-CentresList {
            return @(
                [pscustomobject]@{
                    id               = 'fontaine'
                    name             = 'Fontaine'
                    sharePointApiUrl = 'https://graph.microsoft.com/fontaine'
                }
            )
        }

        $centre = Get-CurrentCentre
        $centre.id | Should Be 'custom'
        $centre.name | Should Be 'Centre non reconnu'
    }

    It 'Get-CurrentCentre : CentreId fontaine reconnu via centres.json' {
        Mock Get-AppConfig {
            param([string]$Key)
            switch ($Key) {
                'CentreId' { return 'fontaine' }
                'CentreName' { return '' }
                'SharePointApiUrl' { return 'https://graph.microsoft.com/other' }
            }
            return $null
        }
        Mock Get-CentreConfig {
            param([string]$CentreId)
            if ($CentreId -eq 'fontaine') {
                return [pscustomobject]@{
                    id               = 'fontaine'
                    name             = 'Fontaine'
                    sharePointApiUrl = 'https://graph.microsoft.com/fontaine'
                }
            }
            return $null
        }

        $centre = Get-CurrentCentre
        $centre.name | Should Be 'Fontaine'
        $centre.id | Should Be 'fontaine'
    }

    It 'Set-CurrentCentre : ecrit et verifie les 3 cles AppConfig' {
        $store = @{}
        Mock Set-AppConfig {
            param([string]$Key, [string]$Value)
            $store[$Key] = $Value
        }
        Mock Get-AppConfig {
            param([string]$Key)
            if ($store.ContainsKey($Key)) { return $store[$Key] }
            return $null
        }
        Mock Get-CentreConfig {
            return [pscustomobject]@{
                id               = 'fontaine'
                name             = 'Fontaine'
                sharePointApiUrl = 'https://graph.microsoft.com/fontaine'
                planningFileName = 'Planning FONTAINE 2026.xlsm'
            }
        }

        (Set-CurrentCentre -CentreId 'fontaine') | Should Be $true
        $store['CentreId'] | Should Be 'fontaine'
        $store['CentreName'] | Should Be 'Fontaine'
        $store['SharePointApiUrl'] | Should Be 'https://graph.microsoft.com/fontaine'
    }

    It 'Repair-CentreConfiguration : match URL puis reecrit le centre' {
        $store = @{
            SharePointApiUrl = 'https://graph.microsoft.com/fontaine'
            CentreId         = ''
            CentreName       = ''
        }
        Mock Get-AppConfig {
            param([string]$Key)
            if ($store.ContainsKey($Key)) { return $store[$Key] }
            return $null
        }
        Mock Set-AppConfig {
            param([string]$Key, [string]$Value)
            $store[$Key] = $Value
        }
        Mock Get-CentresList {
            return @(
                [pscustomobject]@{
                    id               = 'fontaine'
                    name             = 'Fontaine'
                    sharePointApiUrl = 'https://graph.microsoft.com/fontaine'
                }
            )
        }
        Mock Get-CentreConfig {
            param([string]$CentreId)
            if ($CentreId -eq 'fontaine') {
                return [pscustomobject]@{
                    id               = 'fontaine'
                    name             = 'Fontaine'
                    sharePointApiUrl = 'https://graph.microsoft.com/fontaine'
                }
            }
            return $null
        }

        (Repair-CentreConfiguration) | Should Be $true
        $store['CentreName'] | Should Be 'Fontaine'
        $store['CentreId'] | Should Be 'fontaine'
    }
}

Describe 'ConfigManager - SharePoint stable IDs (Lot 1)' {

    BeforeAll {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
        $configManagerPath = Join-Path $repoRoot 'src\Core\ConfigManager.ps1'
        . $configManagerPath
    }

    It 'Get-SharePointStableIds : cles absentes -> objet vide sans erreur' {
        Mock Get-AppConfig {
            param([string]$Key)
            return $null
        }

        $ids = Get-SharePointStableIds
        $ids.DriveId | Should Be $null
        $ids.ItemId | Should Be $null
        $ids.PlanningFileName | Should Be $null
        $ids.LastValidatedAt | Should Be $null
        $ids.SourceUrl | Should Be $null
    }

    It 'Set-SharePointStableIds puis Get : valeurs identiques' {
        $store = @{}
        Mock Set-AppConfig {
            param([string]$Key, [string]$Value)
            $store[$Key] = $Value
        }
        Mock Get-AppConfig {
            param([string]$Key)
            if ($store.ContainsKey($Key)) { return $store[$Key] }
            return $null
        }

        Set-SharePointStableIds `
            -DriveId 'drive-abc' `
            -ItemId 'item-xyz' `
            -PlanningFileName 'Planning FONTAINE 2026.xlsm' `
            -LastValidatedAt '2026-11-08T14:00:00Z' `
            -SourceUrl 'https://graph.microsoft.com/v1.0/sites/example'

        $ids = Get-SharePointStableIds
        $ids.DriveId | Should Be 'drive-abc'
        $ids.ItemId | Should Be 'item-xyz'
        $ids.PlanningFileName | Should Be 'Planning FONTAINE 2026.xlsm'
        $ids.LastValidatedAt | Should Be '2026-11-08T14:00:00Z'
        $ids.SourceUrl | Should Be 'https://graph.microsoft.com/v1.0/sites/example'
    }

    It 'Set-SharePointStableIds ne modifie pas SharePointApiUrl' {
        $store = @{
            SharePointApiUrl = 'https://graph.microsoft.com/v1.0/sites/keep-me'
        }
        Mock Set-AppConfig {
            param([string]$Key, [string]$Value)
            $store[$Key] = $Value
        }
        Mock Get-AppConfig {
            param([string]$Key)
            if ($store.ContainsKey($Key)) { return $store[$Key] }
            return $null
        }

        Set-SharePointStableIds -DriveId 'drive-1' -ItemId 'item-1'

        $store['SharePointApiUrl'] | Should Be 'https://graph.microsoft.com/v1.0/sites/keep-me'
        $store.ContainsKey('CentreId') | Should Be $false
        $store.ContainsKey('CentreName') | Should Be $false
    }
}

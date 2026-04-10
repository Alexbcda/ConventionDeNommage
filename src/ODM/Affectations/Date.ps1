# Date.ps1 - Gestion des dates
function Get-CNDateParDefaut {
    try {
        $configPath = Join-Path $PSScriptRoot "..\..\Data\odm_config.json"
        if (Test-Path $configPath) {
            $config = Get-Content $configPath | ConvertFrom-Json
            return [DateTime]::ParseExact($config.DateParDefaut, "yyyy-MM-dd", $null)
        }
    } catch {}
    return [DateTime]::Now.AddDays(-1)
}

function Set-CNDate {
    param([DateTime]$Date)
    $configPath = Join-Path $PSScriptRoot "..\..\Data\odm_config.json"
    $config = @{ DateParDefaut = $Date.ToString("yyyy-MM-dd") }
    $config | ConvertTo-Json | Out-File $configPath -Encoding UTF8 -Force
}




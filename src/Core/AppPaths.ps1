# AppPaths.ps1 - Resolution des chemins applicatifs (mode dev vs installe).
# Charge par Main.ps1 avant Logger et Database.
# Deux modes transparents :
#   - Dev : tous les chemins relatifs au repo (comportement historique)
#   - Installe : code dans Program Files, donnees dans ProgramData

function Get-AppInstallRoot {
    if (-not [string]::IsNullOrWhiteSpace($global:CN_InstallRoot)) {
        return $global:CN_InstallRoot
    }
    $root = $PSScriptRoot
    for ($i = 0; $i -lt 2; $i++) { $root = Split-Path -Parent $root }
    return $root
}

function Get-AppDataRoot {
    <#
    .SYNOPSIS
        Retourne la racine des donnees applicatives (config, Data, Logs).
        En mode installe : C:\ProgramData\ConventionDeNommage
        En mode dev : racine du repo (meme que InstallRoot).
    #>
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($global:CN_DataRoot)) {
        return $global:CN_DataRoot
    }

    if (-not [string]::IsNullOrWhiteSpace($env:CN_DATA_ROOT)) {
        $envPath = $env:CN_DATA_ROOT
        if (Test-Path -LiteralPath $envPath -PathType Container) {
            return $envPath
        }
    }

    $pdPath = Join-Path $env:ProgramData 'ConventionDeNommage'
    if (Test-Path -LiteralPath $pdPath -PathType Container) {
        $marker = Join-Path $pdPath 'config\runtime.json'
        if (Test-Path -LiteralPath $marker -PathType Leaf) {
            return $pdPath
        }
    }

    return (Get-AppInstallRoot)
}

function Initialize-AppPaths {
    <#
    .SYNOPSIS
        Initialise les chemins globaux et cree les dossiers manquants.
        Doit etre appelee une seule fois au demarrage (Main.ps1).
    #>
    [CmdletBinding()]
    param()

    $global:CN_InstallRoot = Get-AppInstallRoot
    $global:CN_DataRoot    = Get-AppDataRoot

    $global:CN_Paths = @{
        InstallRoot = $global:CN_InstallRoot
        DataRoot    = $global:CN_DataRoot
        Config      = Join-Path $global:CN_DataRoot 'config'
        Data        = Join-Path $global:CN_DataRoot 'Data'
        Logs        = Join-Path $global:CN_DataRoot 'Logs'
        Lib         = Join-Path $global:CN_InstallRoot 'lib'
        Runtime     = Join-Path $global:CN_InstallRoot 'runtime'
        Src         = Join-Path $global:CN_InstallRoot 'src'
        Resources   = Join-Path $global:CN_InstallRoot 'Resources'
    }

    foreach ($dir in @($global:CN_Paths.Config, $global:CN_Paths.Data, $global:CN_Paths.Logs)) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
            try { $null = New-Item -Path $dir -ItemType Directory -Force } catch {}
        }
    }

    return $global:CN_Paths
}

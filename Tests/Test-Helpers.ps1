<#
.SYNOPSIS
    Helpers partages pour les tests Phase 10.
#>

function Copy-ConventionDirectoryRobust {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDir,
        [Parameter(Mandatory = $true)][string]$TargetDir
    )

    if (Test-Path -LiteralPath $TargetDir) {
        Remove-Item -LiteralPath $TargetDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $null = New-Item -ItemType Directory -Path $TargetDir -Force

    $robocopy = Join-Path $env:SystemRoot 'System32\robocopy.exe'
    if (Test-Path -LiteralPath $robocopy) {
        $null = & $robocopy $SourceDir $TargetDir /E /R:2 /W:1 /NFL /NDL /NJH /NJS /nc /ns /np
        if ($LASTEXITCODE -lt 8) {
            return
        }
    }

    if (Test-Path -LiteralPath $TargetDir) {
        Remove-Item -LiteralPath $TargetDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $null = New-Item -ItemType Directory -Path $TargetDir -Force
    Copy-Item -LiteralPath (Join-Path $SourceDir '*') -Destination $TargetDir -Recurse -Force -ErrorAction Continue
}

function Copy-ConventionTestPackage {
    param(
        [Parameter(Mandatory = $true)][string]$Destination,
        [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
    )

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction SilentlyContinue
    }
    $null = New-Item -ItemType Directory -Path $Destination -Force

    $deployDirs = @('src', 'Data', 'lib', 'runtime', 'config')
    foreach ($dirName in $deployDirs) {
        $sourceDir = Join-Path $RepoRoot $dirName
        if (Test-Path -LiteralPath $sourceDir) {
            $targetDir = Join-Path $Destination $dirName
            Copy-ConventionDirectoryRobust -SourceDir $sourceDir -TargetDir $targetDir
        }
    }

    $outputDir = Join-Path $RepoRoot 'output'
    foreach ($fileName in @('ConventionDeNommage.exe', 'install.ps1', 'version.txt')) {
        $sourceFile = Join-Path $outputDir $fileName
        if (Test-Path -LiteralPath $sourceFile) {
            Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $Destination $fileName) -Force
        }
    }

    return [PSCustomObject]@{
        HasExe           = Test-Path -LiteralPath (Join-Path $Destination 'ConventionDeNommage.exe')
        HasInstallScript = Test-Path -LiteralPath (Join-Path $Destination 'install.ps1')
        HasLib           = Test-Path -LiteralPath (Join-Path $Destination 'lib\System.Data.SQLite.dll')
        HasConfig        = Test-Path -LiteralPath (Join-Path $Destination 'config\centres.json')
    }
}

function Initialize-ConventionCentreConfig {
    param(
        [Parameter(Mandatory = $true)][string]$InstallDir,
        [Parameter(Mandatory = $true)][string]$CentreId
    )

    $centresJson = Join-Path $InstallDir 'config\centres.json'
    if (-not (Test-Path -LiteralPath $centresJson)) {
        throw "config\centres.json introuvable dans $InstallDir"
    }

    $centresData = Get-Content -LiteralPath $centresJson -Raw -Encoding UTF8 | ConvertFrom-Json
    $selectedCentre = $centresData.centres | Where-Object { $_.id -eq $CentreId } | Select-Object -First 1
    if (-not $selectedCentre) {
        throw "Centre inconnu : $CentreId"
    }

    $dbScript = Join-Path $InstallDir 'src\Database\Database.ps1'
    . $dbScript
    $null = Initialize-Database
    Set-AppConfig -Key 'SharePointApiUrl' -Value ([string]$selectedCentre.sharePointApiUrl)
    Set-AppConfig -Key 'CentreId' -Value ([string]$selectedCentre.id)
    Set-AppConfig -Key 'CentreName' -Value ([string]$selectedCentre.name)

    return $selectedCentre
}

function Initialize-ConventionTestDatabase {
    param(
        [Parameter(Mandatory = $true)][string]$TestDir,
        [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
    )

    $dataDir = Join-Path $TestDir 'Data'
    $libDir = Join-Path $TestDir 'lib'
    $null = New-Item -ItemType Directory -Path $dataDir -Force

    if (-not (Test-Path -LiteralPath (Join-Path $libDir 'System.Data.SQLite.dll'))) {
        Copy-ConventionDirectoryRobust -SourceDir (Join-Path $RepoRoot 'lib') -TargetDir $libDir
    }

    . (Join-Path $RepoRoot 'src\Database\Database.ps1')
    $script:DbPath = Join-Path $dataDir 'gestion.db'
    $script:DllPath = Join-Path $libDir 'System.Data.SQLite.dll'
    $null = Initialize-Database
}

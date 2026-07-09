# Diagnostic complet de l'installation ASSISTANT.

function Resolve-AssistantInstallRoot {
    $candidates = @(
        $env:ASSISTANT_HOME,
        'C:\ASSISTANT',
        (Join-Path (Split-Path -Parent $PSScriptRoot) '..')
    )
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        try {
            $resolved = (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
            if (Test-Path -LiteralPath (Join-Path $resolved 'src\Main.ps1')) {
                return $resolved
            }
        }
        catch { }
    }
    return 'C:\ASSISTANT'
}

function Invoke-FullDiagnostic {
    [CmdletBinding()]
    param()

    $installRoot = Resolve-AssistantInstallRoot

    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host '   DIAGNOSTIC DE L''ASSISTANT' -ForegroundColor Cyan
    Write-Host "   $(Get-Date)" -ForegroundColor Gray
    Write-Host "   Racine : $installRoot" -ForegroundColor Gray
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host ''

    $results = [System.Collections.Generic.List[object]]::new()

    $folders = @(
        $installRoot,
        (Join-Path $installRoot 'src'),
        (Join-Path $installRoot 'templates'),
        (Join-Path $installRoot 'Data'),
        (Join-Path $installRoot 'src\ODM\PdfPlanningOptimizer'),
        (Join-Path $installRoot 'src\ODM\PdfPlanningOptimizer\PlanningUIHelpers.ps1')
    )
    foreach ($folder in $folders) {
        $exists = Test-Path -LiteralPath $folder
        $results.Add([PSCustomObject]@{
                Test   = "Chemin $folder"
                Status = if ($exists) { 'OK' } else { 'MANQUANT' }
            })
    }

    $modules = @('ImportExcel', 'Microsoft.Graph.Authentication')
    foreach ($mod in $modules) {
        $exists = Get-Module -Name $mod -ListAvailable -ErrorAction SilentlyContinue
        $results.Add([PSCustomObject]@{
                Test   = "Module $mod"
                Status = if ($exists) { 'Installe' } else { 'Manquant' }
            })
    }

    $helpersScript = Join-Path $installRoot 'src\ODM\PdfPlanningOptimizer\PlanningUIHelpers.ps1'
    if (Test-Path -LiteralPath $helpersScript) {
        if (-not (Get-Command Safe-UpdateUIControl -ErrorAction SilentlyContinue)) {
            . $helpersScript
        }
    }

    $functions = @('Safe-UpdateUIControl', 'Update-PlanningExcelPathLabel', 'Show-PlanningStatusMessage')
    foreach ($func in $functions) {
        $exists = Get-Command -Name $func -ErrorAction SilentlyContinue
        $results.Add([PSCustomObject]@{
                Test   = "Fonction $func"
                Status = if ($exists) { 'Definie' } else { 'Non definie' }
            })
    }

    $spScript = Join-Path $installRoot 'src\SharePoint\SharePointManager.ps1'
    if (-not (Test-Path -LiteralPath $spScript)) {
        $spScript = Join-Path $installRoot 'src\Common\CnsSharePointConnector.ps1'
    }
    if (Test-Path -LiteralPath $spScript) {
        try {
            if (-not (Get-Command Test-SharePointConnection -ErrorAction SilentlyContinue)) {
                . $spScript
            }
            $spResult = Test-SharePointConnection -Interactive
            $results.Add([PSCustomObject]@{
                    Test   = 'Connexion SharePoint'
                    Status = if ($spResult) { 'Connecte' } else { 'Echec ou annule' }
                })
        }
        catch {
            $results.Add([PSCustomObject]@{
                    Test   = 'Connexion SharePoint'
                    Status = "Erreur : $($_.Exception.Message)"
                })
        }
    }
    else {
        $results.Add([PSCustomObject]@{
                Test   = 'Connexion SharePoint'
                Status = 'Script SharePoint introuvable'
            })
    }

    $planningUrl = $null
    $connector = Join-Path $installRoot 'src\Common\CnsSharePointConnector.ps1'
    if (Test-Path -LiteralPath $connector) {
        if (-not (Get-Command Get-SharePointPlanningUrl -ErrorAction SilentlyContinue)) {
            . $connector
        }
        $planningUrl = Get-SharePointPlanningUrl
    }
    $results.Add([PSCustomObject]@{
            Test   = 'URL SharePoint configuree'
            Status = if ([string]::IsNullOrWhiteSpace($planningUrl)) { 'Non configuree' } else { 'Configuree' }
        })

    $results | Format-Table -AutoSize

    $ok = @($results | Where-Object { $_.Status -match '^(OK|Installe|Definie|Connecte|Configuree)$' }).Count
    $warn = @($results | Where-Object { $_.Status -match 'Manquant|Non configuree|Echec' }).Count
    $errorCount = @($results | Where-Object { $_.Status -match 'MANQUANT|Non definie|introuvable|Erreur' }).Count

    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host 'RESUME :' -ForegroundColor Yellow
    Write-Host "  Succes : $ok" -ForegroundColor Green
    Write-Host "  Avertissements : $warn" -ForegroundColor Yellow
    Write-Host "  Erreurs : $errorCount" -ForegroundColor Red
    Write-Host '========================================' -ForegroundColor Cyan
}

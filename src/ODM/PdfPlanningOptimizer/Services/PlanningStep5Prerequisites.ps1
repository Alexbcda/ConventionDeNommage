# Verification des prerequis etape 5 (pages de garde + templates XLSX).

. (Join-Path $PSScriptRoot '..\..\..\Core\GhostscriptResolve.ps1')
. (Join-Path $PSScriptRoot 'CnsExcelTemplateEngine.ps1')

function Get-PlanningAssistantInstallRoot {
    try {
        return (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
    }
    catch {
        return $null
    }
}

function Test-PlanningStep5Environment {
    <#
    .OUTPUTS
        PSCustomObject Ok, Issues, GhostscriptPath, LibreOfficePath, MissingTemplates
    #>
    $issues = [System.Collections.Generic.List[string]]::new()
    $root = Get-PlanningAssistantInstallRoot

    $gs = $null
    if (Get-Command Get-ResolvedGhostscriptPath -ErrorAction SilentlyContinue) {
        $gs = Get-ResolvedGhostscriptPath
    }
    if ([string]::IsNullOrWhiteSpace($gs)) {
        [void]$issues.Add('Ghostscript introuvable (gswin64c.exe) — pages de garde impossibles. Installez Ghostscript 10+.')
    }

    $lo = $null
    if (Get-Command Get-CnsLibreOfficeSofficePath -ErrorAction SilentlyContinue) {
        $lo = Get-CnsLibreOfficeSofficePath
    }
    $excelOk = $false
    if (Get-Command Test-CnsMicrosoftExcelAvailable -ErrorAction SilentlyContinue) {
        $excelOk = Test-CnsMicrosoftExcelAvailable
    }
    if ([string]::IsNullOrWhiteSpace($lo) -and -not $excelOk) {
        [void]$issues.Add('Aucun convertisseur XLSX→PDF (LibreOffice ou Excel requis).')
    }

    $missingTpl = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($root)) {
        foreach ($name in @('CertificatDeDestruction.xlsx', 'BilanDeCollecte.xlsx', 'CeaPointsDeCollectes.xlsx', 'FT.xlsx')) {
            $p = Join-Path $root ("templates\{0}" -f $name)
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
                [void]$missingTpl.Add($name)
            }
        }
    }
    else {
        [void]$issues.Add('Racine installation ASSISTANT introuvable depuis PlanningRebuilder.')
    }
    if ($missingTpl.Count -gt 0) {
        [void]$issues.Add(('Templates manquants dans {0}\templates\ : {1}' -f $root, ($missingTpl -join ', ')))
    }

    return [pscustomobject]@{
        Ok               = ($issues.Count -eq 0)
        Issues           = @($issues.ToArray())
        InstallRoot      = $root
        GhostscriptPath  = $gs
        LibreOfficePath  = $lo
        MissingTemplates = @($missingTpl.ToArray())
    }
}

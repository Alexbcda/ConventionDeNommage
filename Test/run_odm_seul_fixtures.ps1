# Test headless des détections ODM Seul (sans UI WinForms interactive).
# Usage : powershell -NoProfile -File Test\run_odm_seul_fixtures.ps1

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$panelScript = Join-Path $repoRoot 'src\ODM\OdmSeul\OdmSeulPanel.ps1'
$fixturesDir = Join-Path $PSScriptRoot 'Fixtures\PdfPlanningOptimizer'

if (-not (Test-Path -LiteralPath $panelScript)) {
    throw "OdmSeulPanel.ps1 introuvable : $panelScript"
}
if (-not (Test-Path -LiteralPath $fixturesDir)) {
    throw "Dossier fixtures introuvable : $fixturesDir"
}

. $panelScript

# Require* = doit être true ; ForbidAll = rien.pdf (aucune fiche)
$cases = @(
    @{ File = 'rien.pdf';        ForbidAll = $true }
    @{ File = 'destruction.pdf'; RequireCert = $true }
    @{ File = 'ftgrenoble.pdf';  RequireFt = $true }
    @{ File = 'cea.pdf';         RequireCea = $true }
)

$failed = 0
foreach ($c in $cases) {
    $path = Join-Path $fixturesDir $c.File
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host ("FAIL  {0} — fichier manquant" -f $c.File) -ForegroundColor Red
        $failed++
        continue
    }
    Write-Host ("--- {0} ---" -f $c.File) -ForegroundColor Cyan
    $r = Invoke-OdmSeulReadAndDetect -PdfPath $path
    $ok = [bool]$r.Ok
    $reasons = @()
    if ($c.ForbidAll) {
        if ($r.Cea -or $r.Cert -or $r.Dac -or $r.Ft) {
            $ok = $false
            $reasons += 'attendu aucune fiche'
        }
    }
    if ($c.RequireCea -and -not $r.Cea) { $ok = $false; $reasons += 'CEA manquant' }
    if ($c.RequireCert -and -not $r.Cert) { $ok = $false; $reasons += 'Certificat manquant' }
    if ($c.RequireFt -and -not $r.Ft) { $ok = $false; $reasons += 'FT manquant' }

    $line = ("Cea={0} Cert={1} Dac={2} Ft={3} | {4}" -f $r.Cea, $r.Cert, $r.Dac, $r.Ft, $r.Message)
    if ($ok) {
        Write-Host ("PASS  {0}" -f $line) -ForegroundColor Green
    }
    else {
        Write-Host ("FAIL  {0} | {1}" -f $line, ($reasons -join '; ')) -ForegroundColor Red
        $failed++
    }
}

# Smoke UI : Show-OdmSeulPanel ne doit pas lever sur ForeColor
Write-Host '--- smoke Show-OdmSeulPanel (ForeColor) ---' -ForegroundColor Cyan
try {
    $p = Show-OdmSeulPanel
    if ($null -eq $p) { throw 'Show-OdmSeulPanel a retourné $null' }
    $null = $p.ForeColor
    $p.Dispose()
    Write-Host 'PASS  Show-OdmSeulPanel sans exception ForeColor' -ForegroundColor Green
}
catch {
    Write-Host ("FAIL  Show-OdmSeulPanel : {0}" -f $_.Exception.Message) -ForegroundColor Red
    $failed++
}

if ($failed -gt 0) {
    Write-Host ("RESULTAT : {0} echec(s)" -f $failed) -ForegroundColor Red
    exit 1
}
Write-Host 'RESULTAT : OK' -ForegroundColor Green
exit 0

#Requires -Version 5.1
<#
.SYNOPSIS
    Audit complet ASSISTANT : tous les onglets + menu contextuel.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = 'C:\Users\alexa\Documents\ConventionDeNommage',
    [string]$InstallDir = 'C:\ASSISTANT',
    [switch]$SkipPlanningRun
)

$ErrorActionPreference = 'Stop'
$results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param([string]$Area, [string]$Test, [bool]$Ok, [string]$Detail = '')
    $results.Add([pscustomobject]@{ Area = $Area; Test = $Test; Ok = $Ok; Detail = $Detail })
    $c = if ($Ok) { 'Green' } else { 'Red' }
    $m = if ($Ok) { 'OK' } else { 'KO' }
    Write-Host "[$m] $Area — $Test" -ForegroundColor $c
    if ($Detail) { Write-Host "      $Detail" -ForegroundColor Gray }
}

# --- 1. Convention de nommage + menu contextuel ---
Write-Host "`n=== 1. CONVENTION DE NOMMAGE ===" -ForegroundColor Cyan

$regPath = 'HKCU:\Software\Classes\SystemFileAssociations\.pdf\shell\ASSISTANT'
try {
    $reg = Get-ItemProperty -LiteralPath $regPath -ErrorAction Stop
    $cmd = Get-ItemProperty -LiteralPath (Join-Path $regPath 'command') -ErrorAction Stop
    $labelOk = ($reg.'(default)' -eq 'Assistant')
    $iconOk = ($reg.Icon -like '*ASSISTANT.ico*')
    Add-Result -Area 'Contexte PDF' -Test 'Registre label Assistant' -Ok $labelOk -Detail $reg.'(default)'
    Add-Result -Area 'Contexte PDF' -Test 'Registre icone' -Ok $iconOk -Detail $reg.Icon
    Add-Result -Area 'Contexte PDF' -Test 'Commande ASSISTANT.bat "%1"' -Ok ($cmd.'(default)' -like '*ASSISTANT.bat*"%1"*') -Detail $cmd.'(default)'
}
catch {
    Add-Result -Area 'Contexte PDF' -Test 'Cle registre ASSISTANT' -Ok $false -Detail $_.Exception.Message
}

foreach ($rel in @('ASSISTANT.bat', 'ASSISTANT.ico', 'src\LaunchAssistant.ps1', 'src\ODM\ConventionNommage\ConventionNommageLogic.ps1')) {
    Add-Result -Area 'Lanceur' -Test $rel -Ok (Test-Path -LiteralPath (Join-Path $InstallDir $rel))
}

$fixtures = Join-Path $RepoRoot 'Test\Fixtures\PdfPlanningOptimizer\McDO.pdf'
if (-not (Test-Path -LiteralPath $fixtures)) { $fixtures = Join-Path $RepoRoot 'TestRenommage\document_original.pdf' }
if (Test-Path -LiteralPath $fixtures) {
    $cnDir = Join-Path $env:TEMP ('CN_Audit_' + [Guid]::NewGuid().ToString('n'))
    $null = New-Item -ItemType Directory -Path $cnDir -Force
    try {
        Copy-Item -LiteralPath $fixtures -Destination (Join-Path $cnDir 'McDO.pdf') -Force
        . (Join-Path $RepoRoot 'src\ODM\ConventionNommage\ConventionNommageLogic.ps1')
        $refDate = Get-ConventionNomReferenceDate
        $collecte = 'AUDIT'
        $pdf1 = Join-Path $cnDir 'McDO.pdf'
        Invoke-CNRenameAction -TemplateId 'certificat' -FichierPDF $pdf1 -UserText $collecte -DateSelectionnee $refDate | Out-Null
        $cert = Join-Path $cnDir ("Certificat de Destruction-{0}-du {1}.pdf" -f $collecte, $refDate.ToString('dd.MM.yyyy'))
        Add-Result -Area 'Renommage' -Test 'Bouton CERTIFICAT' -Ok (Test-Path -LiteralPath $cert) -Detail (Split-Path -Leaf $cert)
        Invoke-CNRenameAction -TemplateId 'planner' -FichierPDF $cert -UserText $collecte -DateSelectionnee $refDate | Out-Null
        $plan = Join-Path $cnDir ('{0}-{1}.pdf' -f $refDate.ToString('yyyyMMdd'), $collecte)
        Add-Result -Area 'Renommage' -Test 'Bouton PLANNER' -Ok (Test-Path -LiteralPath $plan) -Detail (Split-Path -Leaf $plan)
        Copy-Item -LiteralPath $fixtures -Destination (Join-Path $cnDir 'McDO_ft.pdf') -Force
        Invoke-CNRenameAction -TemplateId 'france-travail' -FichierPDF (Join-Path $cnDir 'McDO_ft.pdf') -UserText $collecte -DateSelectionnee $refDate | Out-Null
        $ft = Join-Path $cnDir ('{0}-{1}(1).pdf' -f $refDate.ToString('yyyyMMdd'), $collecte)
        Add-Result -Area 'Renommage' -Test 'Bouton FRANCE TRAVAIL (collision)' -Ok (Test-Path -LiteralPath $ft) -Detail (Split-Path -Leaf $ft)
    }
    catch {
        Add-Result -Area 'Renommage' -Test 'Chainage renommage' -Ok $false -Detail $_.Exception.Message
    }
    finally {
        Remove-Item -LiteralPath $cnDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
else {
    Add-Result -Area 'Renommage' -Test 'Fixture PDF' -Ok $false -Detail 'McDO.pdf introuvable'
}

# --- 2. Agents CRUD ---
Write-Host "`n=== 2. DONNEES AGENTS ===" -ForegroundColor Cyan
$dbDir = Join-Path $env:TEMP ('AgentAudit_' + [Guid]::NewGuid().ToString('n'))
$null = New-Item -ItemType Directory -Path $dbDir -Force
$env:ASSISTANT_DATA_DIR = $dbDir
try {
    . (Join-Path $RepoRoot 'src\ODM\Agents\AgentRepository.ps1')
    $null = Initialize-Database
    $id = Add-AgentWithValidation -Nom 'Dupont' -Prenom 'Jean' -Telephone '0612345678' -Email 'jean@test.fr' `
        -DateEntree '2024-01-01' -DateSortie $null -TypeContrat 'CDI' -Poste 'Collecteur'
    Add-Result -Area 'Agents' -Test 'CREATE' -Ok ($id -gt 0) -Detail "id=$id"
    $null = Update-AgentWithValidation -Id $id -Nom 'Dupont' -Prenom 'Jean-Paul' -Telephone '0612345678' -Email 'jean@test.fr' `
        -DateEntree '2024-01-01' -DateSortie $null -TypeContrat 'CDI' -Poste 'Collecteur'
    $row = Get-AgentByIdSafe -Id $id
    Add-Result -Area 'Agents' -Test 'UPDATE' -Ok ($row.Prenom -eq 'Jean-Paul') -Detail $row.Prenom
    $list = Get-AgentRecords
    Add-Result -Area 'Agents' -Test 'READ' -Ok ($list.Count -ge 1) -Detail "$($list.Count) agent(s)"
    $null = Remove-AgentWithValidation -Id $id
    $after = @(Get-AgentRecords).Count
    Add-Result -Area 'Agents' -Test 'DELETE' -Ok ($after -eq 0) -Detail "reste=$after"
    Add-Result -Area 'Agents' -Test 'AgentPanel.ps1' -Ok (Test-Path -LiteralPath (Join-Path $InstallDir 'src\ODM\Agents\AgentPanel.ps1'))
}
catch {
    Add-Result -Area 'Agents' -Test 'CRUD agents' -Ok $false -Detail $_.Exception.Message
}
finally {
    Remove-Item Env:ASSISTANT_DATA_DIR -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $dbDir -Recurse -Force -ErrorAction SilentlyContinue
}

# --- 3. Vehicules CRUD ---
Write-Host "`n=== 3. DONNEES VEHICULES ===" -ForegroundColor Cyan
$dbDir2 = Join-Path $env:TEMP ('VehAudit_' + [Guid]::NewGuid().ToString('n'))
$null = New-Item -ItemType Directory -Path $dbDir2 -Force
$env:ASSISTANT_DATA_DIR = $dbDir2
try {
    . (Join-Path $RepoRoot 'src\ODM\Vehicules\VehiculesRepository.ps1')
    $null = Initialize-Database
    $vid = Add-VehiculeWithValidation -NumeroParc 'PARC001' -Immatriculation 'AB-123-CD' -NumeroChassis 'VF1RJA00612345678' `
        -Marque 'Renault' -Modele 'Master' -DateMiseCirculation '2020-01-15' -DateEntree '2020-02-01'
    Add-Result -Area 'Vehicules' -Test 'CREATE' -Ok ($vid -gt 0) -Detail "id=$vid"
    $null = Update-Vehicule -Id $vid -NumeroParc 'PARC001' -Immatriculation 'AB-123-CD' -NumeroChassis 'VF1RJA00612345678' `
        -Marque 'Renault' -Modele 'Master L2H2' -DateMiseCirculation '2020-01-15' -DateEntree '2020-02-01'
    $vrow = Get-VehiculeById -Id $vid
    Add-Result -Area 'Vehicules' -Test 'UPDATE' -Ok ($vrow.Modele -like '*L2H2*') -Detail $vrow.Modele
    $vlist = Get-Vehicules
    Add-Result -Area 'Vehicules' -Test 'READ' -Ok ($vlist.Count -ge 1) -Detail "$($vlist.Count) vehicule(s)"
    Add-Result -Area 'Vehicules' -Test 'VehiculesPanel.ps1' -Ok (Test-Path -LiteralPath (Join-Path $InstallDir 'src\ODM\Vehicules\VehiculesPanel.ps1'))
}
catch {
    Add-Result -Area 'Vehicules' -Test 'CRUD vehicules' -Ok $false -Detail $_.Exception.Message
}
finally {
    Remove-Item Env:ASSISTANT_DATA_DIR -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $dbDir2 -Recurse -Force -ErrorAction SilentlyContinue
}

# --- 4. Edition planning ---
Write-Host "`n=== 4. EDITION PLANNING ===" -ForegroundColor Cyan
foreach ($rel in @(
    'src\ODM\PdfPlanningOptimizer\Services\PlanningRebuilder.ps1',
    'src\ODM\PdfPlanningOptimizer\Services\PdfTourneeCoverComposer.ps1',
    'templates\CertificatDeDestruction.xlsx',
    'templates\BilanDeCollecte.xlsx',
    'templates\CeaPointsDeCollectes.xlsx',
    'runtime\poppler',
    'lib\qpdf'
)) {
    $p = Join-Path $InstallDir $rel
    $ok = if ($rel -match 'poppler|qpdf') {
        $null -ne (Get-ChildItem -LiteralPath $p -Recurse -Filter $(if ($rel -match 'poppler') { 'pdftotext.exe' } else { 'qpdf.exe' }) -File -EA SilentlyContinue | Select-Object -First 1)
    } else { Test-Path -LiteralPath $p }
    Add-Result -Area 'Planning' -Test $rel -Ok $ok
}
. (Join-Path $InstallDir 'src\Core\GhostscriptResolve.ps1')
$gs = Get-ResolvedGhostscriptPath
Add-Result -Area 'Planning' -Test 'Ghostscript' -Ok ($null -ne $gs) -Detail $gs
$lo = @('C:\Program Files\LibreOffice\program\soffice.exe', 'C:\Program Files (x86)\LibreOffice\program\soffice.exe') | Where-Object { Test-Path $_ } | Select-Object -First 1
Add-Result -Area 'Planning' -Test 'LibreOffice' -Ok ($null -ne $lo) -Detail $lo

if (-not $SkipPlanningRun) {
    $pdfF = Join-Path $RepoRoot 'Test\Fixtures\PdfPlanningOptimizer\08062026.pdf'
    $xlsF = @(
        (Join-Path $RepoRoot 'Test\Fixtures\PdfPlanningOptimizer\Planning GRENOBLE.xlsm'),
        (Join-Path $RepoRoot 'Test\Fixtures\PdfPlanningOptimizer\PlanningGRENOBLE.xlsm')
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ((Test-Path $pdfF) -and $xlsF) {
        $work = Join-Path $env:TEMP ('PlanAudit_' + [Guid]::NewGuid().ToString('n'))
        $null = New-Item -ItemType Directory -Path $work -Force
        try {
            $env:ASSISTANT_DATA_DIR = (Join-Path $work 'Data')
            $null = New-Item -ItemType Directory -Path $env:ASSISTANT_DATA_DIR -Force
            $pop = Get-ChildItem (Join-Path $InstallDir 'runtime\poppler') -Recurse -Filter pdftotext.exe -File -EA SilentlyContinue | Select-Object -First 1
            if ($pop) { $env:PDFTOTEXT_PATH = $pop.DirectoryName }
            $imp = Join-Path $InstallDir 'runtime\ImportExcel'
            if (Test-Path $imp) { $env:PSModulePath = "$imp;$env:PSModulePath" }
            try { Add-Type -AssemblyName System.IO.Compression.FileSystem -EA Stop } catch {}
            . (Join-Path $InstallDir 'src\Database\Database.ps1')
            $null = Initialize-Database
            . (Join-Path $InstallDir 'src\ODM\PdfPlanningOptimizer\Services\PlanningRebuilder.ps1')
            $script:PlanningPipelineRunning = $false
            $null = Start-PlanningRebuild -PdfPath $pdfF -ExcelPath $xlsF
            $out = Get-ChildItem (Split-Path $pdfF) -Filter 'ODM_*.pdf' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($out -and $out.Length -gt 4000000) {
                Add-Result -Area 'Planning' -Test 'Run complet STEP 5' -Ok $true -Detail ("{0} ({0:N0} o)" -f $out.Name, $out.Length)
            }
            elseif ($out) {
                Add-Result -Area 'Planning' -Test 'Run complet STEP 5' -Ok $false -Detail ("PDF trop petit ({0} o) — etape 5 probablement echouee" -f $out.Length)
            }
            else {
                Add-Result -Area 'Planning' -Test 'Run complet STEP 5' -Ok $false -Detail $script:PlanningRebuildLastError
            }
        }
        catch {
            Add-Result -Area 'Planning' -Test 'Run planning' -Ok $false -Detail $_.Exception.Message
        }
        finally {
            Remove-Item Env:ASSISTANT_DATA_DIR -ErrorAction SilentlyContinue
            Remove-Item $work -Recurse -Force -EA SilentlyContinue
        }
    }
}

# --- 5. Outils ---
Write-Host "`n=== 5. OUTILS ===" -ForegroundColor Cyan
Add-Result -Area 'Outils' -Test 'OutilsPanel.ps1' -Ok (Test-Path -LiteralPath (Join-Path $InstallDir 'src\ODM\Outils\OutilsPanel.ps1'))
$dbDir3 = Join-Path $env:TEMP ('OutilsAudit_' + [Guid]::NewGuid().ToString('n'))
$null = New-Item -ItemType Directory -Path $dbDir3 -Force
$env:ASSISTANT_DATA_DIR = $dbDir3
try {
    . (Join-Path $RepoRoot 'src\Database\Database.ps1')
    $null = Initialize-Database
    Set-PlanningRebuildSetting -Key 'play_video_after_treatment' -Value '1'
    Set-PlanningRebuildSetting -Key 'video_delay_seconds' -Value '5'
    $v = Get-PlanningRebuildSetting -Key 'play_video_after_treatment'
    Add-Result -Area 'Outils' -Test 'Sauvegarde parametres planning' -Ok ($v -eq '1') -Detail "play_video=$v"
    $outilsScript = Join-Path $InstallDir 'src\ODM\Outils\OutilsPanel.ps1'
    if (Test-Path -LiteralPath $outilsScript) { . $outilsScript }
    Add-Result -Area 'Outils' -Test 'Show-OutilsPanel (fonction)' -Ok ([bool](Get-Command Show-OutilsPanel -EA SilentlyContinue))
}
catch {
    Add-Result -Area 'Outils' -Test 'Parametres DB' -Ok $false -Detail $_.Exception.Message
}
finally {
    Remove-Item Env:ASSISTANT_DATA_DIR -ErrorAction SilentlyContinue
    Remove-Item $dbDir3 -Recurse -Force -EA SilentlyContinue
}

# --- 6. Installation globale ---
Write-Host "`n=== 6. INSTALLATION ===" -ForegroundColor Cyan
$ver = Join-Path $InstallDir 'version.txt'
Add-Result -Area 'Install' -Test 'version.txt' -Ok (Test-Path $ver) -Detail $(if (Test-Path $ver) { Get-Content $ver -Raw } else { '' })
Add-Result -Area 'Install' -Test 'src\Main.ps1' -Ok (Test-Path (Join-Path $InstallDir 'src\Main.ps1'))
Add-Result -Area 'Install' -Test 'lib\SQLite' -Ok (Test-Path (Join-Path $InstallDir 'lib\SQLite.Interop.dll'))
Add-Result -Area 'Install' -Test 'config\centres.json' -Ok (Test-Path (Join-Path $InstallDir 'config\centres.json'))

# --- Synthese ---
Write-Host "`n=== SYNTHESE ===" -ForegroundColor Cyan
$failed = @($results | Where-Object { -not $_.Ok })
$results | Format-Table Area, Test, Ok, Detail -AutoSize
Write-Host "Total : $($results.Count) tests, $($failed.Count) echec(s), $($results.Count - $failed.Count) OK" -ForegroundColor $(if ($failed.Count -eq 0) { 'Green' } else { 'Yellow' })
if ($failed.Count -gt 0) {
    Write-Host "`nRegressions detectees :" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  - [$($_.Area)] $($_.Test) : $($_.Detail)" -ForegroundColor Red }
}
exit $(if ($failed.Count -eq 0) { 0 } else { 1 })

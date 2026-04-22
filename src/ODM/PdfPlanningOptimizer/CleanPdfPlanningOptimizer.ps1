#Requires -Version 5.1
<#
.SYNOPSIS
  Nettoie le module PdfPlanningOptimizer : déplace le code hors pipeline minimal vers Obsolete/.

.DESCRIPTION
  Pipeline conservé : Excel → PDF → Match → Merge → Export.
  Ne supprime aucun fichier. Idempotent (réexécutable). -DryRun simule sans modifier.

.PARAMETER ModuleRoot
  Racine du module (défaut : dossier de ce script).

.PARAMETER DryRun
  Affiche les actions sans déplacer ni créer de fichiers de rapport (sauf affichage console).

.EXAMPLE
  .\CleanPdfPlanningOptimizer.ps1

.EXAMPLE
  .\CleanPdfPlanningOptimizer.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string] $ModuleRoot = $PSScriptRoot,

    [Parameter()]
    [switch] $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Helpers

function Write-Info {
    param([string] $Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Ok {
    param([string] $Message)
    Write-Host $Message -ForegroundColor Green
}

function Write-WarnLine {
    param([string] $Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Write-ErrLine {
    param([string] $Message)
    Write-Host $Message -ForegroundColor Red
}

function Test-IsUnderObsolete {
    param([string] $FullPath, [string] $ObsoleteRoot)
    $normalized = $FullPath.TrimEnd('\')
    return $normalized -ieq $ObsoleteRoot.TrimEnd('\') -or $normalized.StartsWith($ObsoleteRoot.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-AllFilesRecursive {
    param([string] $Root)
    if (-not (Test-Path -LiteralPath $Root)) { return @() }
    return @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force -ErrorAction SilentlyContinue)
}

function Get-Ps1FilesExcludingObsolete {
    param([string] $ModuleRootPath, [string] $ObsoleteRoot)
    if (-not (Test-Path -LiteralPath $ModuleRootPath)) { return @() }
    return @(Get-ChildItem -LiteralPath $ModuleRootPath -Filter '*.ps1' -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-IsUnderObsolete -FullPath $_.FullName -ObsoleteRoot $ObsoleteRoot) })
}

#endregion

#region Main

try {
    if ([string]::IsNullOrWhiteSpace($ModuleRoot)) {
        $ModuleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    $ModuleRoot = (Resolve-Path -LiteralPath $ModuleRoot).Path
    $obsoleteRoot = Join-Path $ModuleRoot 'Obsolete'

    Write-Info "=== CleanPdfPlanningOptimizer ==="
    Write-Info "ModuleRoot : $ModuleRoot"
    if ($DryRun) {
        Write-WarnLine "Mode -DryRun : aucune modification sur disque (pas de déplacement, pas d'écriture de rapports)."
    }

    $foldersToMove = @('Anchors', 'Decision', 'Routing', 'Scoring', 'Debug')
    $serviceFilesToMove = @(
        'ArchitectureGuard.ps1',
        'EntityReconciliationEngine.ps1',
        'FinalResolvedTourneeBuilder.ps1',
        'FinalTourneeBuilder.ps1',
        'HumanMergeAdapter.ps1',
        'HumanResolvedMatchesStore.ps1',
        'MergeTelemetry.ps1',
        'ReplayDiffEngine.ps1',
        'WorkOrderValidation.ps1'
    )

    $renameMap = @{
        'Anchors'  = 'Anchors.ignore'
        'Decision' = 'Decision.ignore'
        'Routing'  = 'Routing.ignore'
        'Scoring'  = 'Scoring.ignore'
        'Debug'    = 'Debug.ignore'
    }

    # --- Comptages initiaux (tout le module y compris Obsolete si présent) ---
    $allFilesBefore = Get-AllFilesRecursive -Root $ModuleRoot
    $countAllBefore = $allFilesBefore.Count

    $movedFileCount = 0

    # --- 1. Créer Obsolete ---
    if (-not (Test-Path -LiteralPath $obsoleteRoot)) {
        if ($DryRun) {
            Write-Info "[DryRun] Créerait le dossier : $obsoleteRoot"
        }
        else {
            try {
                New-Item -ItemType Directory -Path $obsoleteRoot -Force | Out-Null
                Write-Ok "Dossier Obsolete créé ou existant : $obsoleteRoot"
            }
            catch {
                Write-ErrLine "Échec création Obsolete : $_"
                throw
            }
        }
    }
    else {
        Write-Info "Dossier Obsolete déjà présent : $obsoleteRoot"
    }

    # --- 2. Déplacer les dossiers ---
    foreach ($dirName in $foldersToMove) {
        $src = Join-Path $ModuleRoot $dirName
        $dest = Join-Path $obsoleteRoot $dirName

        if (-not (Test-Path -LiteralPath $src)) {
            if ((Test-Path -LiteralPath $dest) -or (Test-Path -LiteralPath (Join-Path $obsoleteRoot ($renameMap[$dirName])))) {
                Write-Info "Déjà traité (absent à la racine, présent sous Obsolete) : $dirName"
            }
            else {
                Write-WarnLine "Source absente, ignoré : $src"
            }
            continue
        }

        if (Test-Path -LiteralPath $dest) {
            Write-WarnLine "Destination existe déjà, déplacement ignoré : $dest"
            continue
        }

        $n = @(Get-ChildItem -LiteralPath $src -File -Recurse -Force -ErrorAction SilentlyContinue).Count
        if ($DryRun) {
            Write-Info "[DryRun] Déplacerait le dossier : $src -> $dest ($n fichier(s) dans l'arbre)"
            $movedFileCount += $n
        }
        else {
            try {
                Move-Item -LiteralPath $src -Destination $dest -Force:$false
                Write-Ok "Dossier déplacé : $dirName -> Obsolete\$dirName"
                $movedFileCount += $n
            }
            catch {
                Write-ErrLine "Échec déplacement dossier $dirName : $_"
            }
        }
    }

    # --- 3. Déplacer les fichiers Services ---
    $servicesPath = Join-Path $ModuleRoot 'Services'
    foreach ($fileName in $serviceFilesToMove) {
        $src = Join-Path $servicesPath $fileName
        $dest = Join-Path $obsoleteRoot $fileName

        if (-not (Test-Path -LiteralPath $src)) {
            if (Test-Path -LiteralPath $dest) {
                Write-Info "Déjà sous Obsolete : $fileName"
            }
            else {
                Write-WarnLine "Fichier source absent : $src"
            }
            continue
        }

        if (Test-Path -LiteralPath $dest) {
            Write-WarnLine "Destination existe déjà, déplacement ignoré : $dest"
            continue
        }

        if ($DryRun) {
            Write-Info "[DryRun] Déplacerait : $src -> $dest"
            $movedFileCount += 1
        }
        else {
            try {
                Move-Item -LiteralPath $src -Destination $dest -Force:$false
                Write-Ok "Fichier déplacé : Services\$fileName -> Obsolete\$fileName"
                $movedFileCount += 1
            }
            catch {
                Write-ErrLine "Échec déplacement $fileName : $_"
            }
        }
    }

    # --- 4. Renommer les dossiers dans Obsolete ( -> *.ignore) ---
    foreach ($entry in $renameMap.GetEnumerator()) {
        $oldName = $entry.Key
        $newName = $entry.Value
        $pathOld = Join-Path $obsoleteRoot $oldName
        $pathNew = Join-Path $obsoleteRoot $newName

        if (-not (Test-Path -LiteralPath $pathOld)) {
            if (Test-Path -LiteralPath $pathNew) {
                Write-Info "Déjà renommé : $newName"
            }
            else {
                Write-Info "Rien à renommer (dossier absent) : $pathOld"
            }
            continue
        }

        if (Test-Path -LiteralPath $pathNew) {
            Write-WarnLine "Cible de renommage existe déjà, ignoré : $pathNew"
            continue
        }

        if ($DryRun) {
            Write-Info "[DryRun] Renommerait : $pathOld -> $pathNew"
        }
        else {
            try {
                Rename-Item -LiteralPath $pathOld -NewName $newName
                Write-Ok "Dossier renommé : Obsolete\$oldName -> $newName"
            }
            catch {
                Write-ErrLine "Échec renommage $oldName : $_"
            }
        }
    }

    # --- 5. Scan références dans les .ps1 restants (hors Obsolete) ---
    $keywords = @('Anchors', 'Decision', 'Routing', 'Scoring', 'Debug')
    $scanFiles = @(Get-Ps1FilesExcludingObsolete -ModuleRootPath $ModuleRoot -ObsoleteRoot $obsoleteRoot |
        Where-Object { $_.Name -ne 'CleanPdfPlanningOptimizer.ps1' })

    Write-Info ""
    Write-Info "--- Références potentielles (mots-clés : $($keywords -join ', ')) dans les .ps1 hors Obsolete ---"

    $matchLineCount = 0
    foreach ($ps1 in $scanFiles) {
        $lines = @(Get-Content -LiteralPath $ps1.FullName -ErrorAction SilentlyContinue)
        if ($lines.Count -eq 0) { continue }
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $hits = @()
            foreach ($kw in $keywords) {
                if ($line -like "*$kw*") {
                    $hits += $kw
                }
            }
            if ($hits.Count -gt 0) {
                $matchLineCount++
                $lineNum = $i + 1
                $hitsUnique = ($hits | Select-Object -Unique) -join ', '
                Write-Host "Fichier: $($ps1.FullName)" -ForegroundColor Gray
                Write-Host "Ligne  : $lineNum" -ForegroundColor Gray
                Write-Host "Mots-clés détectés: $hitsUnique" -ForegroundColor DarkCyan
                Write-Host "Contenu: $line" -ForegroundColor White
                Write-Host ""
            }
        }
    }

    if ($matchLineCount -eq 0) {
        Write-Ok "Aucune ligne contenant ces mots-clés dans les .ps1 restants."
    }
    else {
        Write-WarnLine "Total lignes signalées : $matchLineCount"
    }

    # --- 6. Structure après nettoyage (fichier texte) ---
    $structureLines = [System.Collections.Generic.List[string]]::new()
    $structureLines.Add('PdfPlanningOptimizer - structure simplifiee apres nettoyage (pipeline : Excel -> PDF -> Match -> Merge -> Export)')
    $structureLines.Add("Généré : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $structureLines.Add("")
    $structureLines.Add($ModuleRoot)
    $structureLines.Add("")

    $topDirs = Get-ChildItem -LiteralPath $ModuleRoot -Directory -Force -ErrorAction SilentlyContinue | Sort-Object Name
    foreach ($d in $topDirs) {
        $structureLines.Add('[DIR]  ' + $d.Name + '\')
    }
    $topFiles = Get-ChildItem -LiteralPath $ModuleRoot -File -Force -ErrorAction SilentlyContinue | Sort-Object Name
    foreach ($f in $topFiles) {
        $structureLines.Add("[FILE] $($f.Name)")
    }

    $structureText = $structureLines -join [Environment]::NewLine

    if (-not $DryRun) {
        $structurePath = Join-Path $obsoleteRoot 'STRUCTURE_APRES_NETTOYAGE.txt'
        try {
            Set-Content -LiteralPath $structurePath -Value $structureText -Encoding UTF8
            Write-Ok "Écrit : $structurePath"
        }
        catch {
            Write-ErrLine "Échec écriture STRUCTURE_APRES_NETTOYAGE.txt : $_"
        }
    }
    else {
        Write-Info "[DryRun] Écrirait : $(Join-Path $obsoleteRoot 'STRUCTURE_APRES_NETTOYAGE.txt')"
        Write-Host $structureText -ForegroundColor DarkGray
    }

    # --- 7. README Obsolete ---
    $readmeBody = @"
# Dossier Obsolete - PdfPlanningOptimizer

## Pourquoi ces elements ont ete deplaces

Le module migre vers un **pipeline minimal** :

**Excel -> Tournees -> PDF -> Entites -> Match (WorkOrder exact) -> Merge (PDF prioritaire) -> Export**

Les dossiers **Anchors**, **Decision**, **Routing**, **Scoring**, **Debug** et les scripts Services listes ci-dessous relevent d une couche consideree comme *over-engineering* pour ce perimetre. Ils ont ete **deplaces** (pas supprimes) pour clarifier l architecture et reduire la surface de maintenance.

Les dossiers renommés en ``*.ignore`` evitent qu ils soient pris pour du code actif a la racine du module.

## Contenu typique

- Dossiers : ``Anchors.ignore``, ``Decision.ignore``, ``Routing.ignore``, ``Scoring.ignore``, ``Debug.ignore``
- Scripts (anciennement dans ``Services/``) : garde architecture, builders *Final*, reconciliation, telemetrie merge, validation, etc.

## Apres validation

Une fois les tests et l integration valides sur le pipeline simplifie, le contenu de ``Obsolete/`` peut etre **supprime definitivement** (ou archive ailleurs). Aucune obligation de le conserver au-dela de la periode de transition.

## Imports existants

Les scripts restants peuvent encore contenir des **references** aux anciens chemins ; elles sont **signalees** par ``CleanPdfPlanningOptimizer.ps1`` lors du scan. Corriger ces imports au fil de la migration.

---
*Genere par ``CleanPdfPlanningOptimizer.ps1``.*
"@

    if (-not $DryRun) {
        $readmePath = Join-Path $obsoleteRoot 'README_OBSOLETE.md'
        try {
            Set-Content -LiteralPath $readmePath -Value ($readmeBody.TrimEnd()) -Encoding UTF8
            Write-Ok "Écrit : $readmePath"
        }
        catch {
            Write-ErrLine "Échec écriture README_OBSOLETE.md : $_"
        }
    }
    else {
        Write-Info "[DryRun] Écrirait : $(Join-Path $obsoleteRoot 'README_OBSOLETE.md')"
    }

    # --- 8. Rapport final ---
    $allFilesAfter = Get-AllFilesRecursive -Root $ModuleRoot
    $obsoleteFiles = @(Get-AllFilesRecursive -Root $obsoleteRoot)
    $keptFiles = @($allFilesAfter | Where-Object { -not (Test-IsUnderObsolete -FullPath $_.FullName -ObsoleteRoot $obsoleteRoot) })

    $nbKept = $keptFiles.Count
    $nbInObsolete = $obsoleteFiles.Count
    $totalForPercent = $nbKept + $nbInObsolete
    $pct = if ($totalForPercent -gt 0) { [math]::Round(100.0 * $nbInObsolete / $totalForPercent, 2) } else { 0 }

    Write-Info ""
    Write-Info "========== RAPPORT FINAL =========="
    Write-Info "Fichiers (tous types) dans le module au début du script : $countAllBefore"
    Write-Ok "Fichiers conservés (hors Obsolete/)     : $nbKept"
    Write-Ok "Fichiers sous Obsolete/ (déplacés/archivés) : $nbInObsolete"
    Write-Info "Part du total sous Obsolete/ (réduction / archivage) : $pct %"
    Write-Info "Dossiers de premier niveau restants :"
    $remainingTop = Get-ChildItem -LiteralPath $ModuleRoot -Directory -Force -ErrorAction SilentlyContinue | Sort-Object Name
    foreach ($rd in $remainingTop) {
        Write-Host "  - $($rd.Name)" -ForegroundColor White
    }

    if ($DryRun) {
        Write-WarnLine "DryRun : fichiers déplacés estimés cette exécution (approx.) : $movedFileCount"
    }

    Write-Ok "Terminé."
}
catch {
    Write-ErrLine "Erreur fatale : $_"
    exit 1
}

#endregion

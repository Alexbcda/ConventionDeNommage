# ============================================================
# PdfPlanningOptimizer.ps1
# Rôle : Point d'entrée d'orchestration du pipeline PDF/Excel.
# PHASE 2 : Orchestration uniquement (aucune logique métier).
#
# Single Source of Truth = EntityTourneeMergeEngine (Merge-EntityTournees).
# Les scripts Final* (FinalTourneeBuilder, FinalResolvedTourneeBuilder, EntityReconciliationEngine) sont neutralisés ;
# ne pas les importer — aucune fusion finale hors EntityTourneeMergeEngine.ps1.
# ============================================================

# Import des composants du module
. (Join-Path $PSScriptRoot "Extractors\PdfExtractor.ps1")
. (Join-Path $PSScriptRoot "Extractors\ExcelLoader.ps1")
. (Join-Path $PSScriptRoot "Matching\WeekSelector.ps1")
. (Join-Path $PSScriptRoot "Matching\FuzzyMatcher.ps1")
. (Join-Path $PSScriptRoot "Matching\ExcelWorkOrderMatch.ps1")
. (Join-Path $PSScriptRoot "Matching\GlobalMatchResolution.ps1")
. (Join-Path $PSScriptRoot "Export\FinalAssignmentExport.ps1")
. (Join-Path $PSScriptRoot "Services\PdfReorderService.ps1")
# Fusion finale Excel + PDF (seul point de vérité pour les tournées enrichies) :
. (Join-Path $PSScriptRoot "Services\EntityTourneeMergeEngine.ps1")

# ArchitectureGuard : cmdlets legacy (Final*) — Etme_GuardMode = 'STRICT' (throw) | 'TRACE' (Verbose uniquement).
$global:Etme_GuardMode = 'STRICT'

function Invoke-PdfPlanningOptimizer {
    <#
    .SYNOPSIS
    Orchestre le pipeline PdfPlanningOptimizer sans implémentation métier.

    .PARAMETER SourcePdfPath
    Chemin du fichier PDF source.

    .PARAMETER ExcelPath
    Chemin du fichier Excel de référence.

    .PARAMETER OutputPdfPath
    Chemin du PDF de sortie réorganisé.

    .OUTPUTS
    PSCustomObject
    Résumé des objets intermédiaires et du résultat final.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePdfPath,

        [Parameter(Mandatory = $true)]
        [string]$ExcelPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPdfPath
    )

    # Etape 1 : PDF -> extraction
    $pdfData = Invoke-PdfExtraction -PdfPath $SourcePdfPath
    if ($pdfData.PdfTextUnusable -and $pdfData.UserAbortMessage) {
        throw $pdfData.UserAbortMessage
    }

    # Etape 2 : Excel -> chargement (stub)
    $excelData = Import-PlanningExcelData -ExcelPath $ExcelPath

    # Etape 3 : selection semaine (stub)
    $selectedWeek = Select-PlanningWeek -ExtractedPdfData $pdfData
    # TODO (Phase 3): Integrer la logique de selection de semaine en tenant compte des donnees Excel.

    # Etape 4 : matching PDF/Excel (stub)
    $matches = Find-PlanningMatches -PdfData $pdfData -ExcelData $excelData
    # TODO (Phase 3): Appliquer le filtrage/contraintes de matching selon la semaine selectionnee.

    # Etape 5 : reorganisation PDF (stub)
    $outputPath = Invoke-PdfReorder -SourcePdfPath $SourcePdfPath -Matches $matches -OutputPdfPath $OutputPdfPath

    # Retour de pipeline pour faciliter les tests et le debug pas-a-pas.
    return [pscustomobject]@{
        PdfData      = $pdfData
        ExcelData    = $excelData
        SelectedWeek = $selectedWeek
        Matches      = $matches
        OutputPath   = $outputPath
    }
}

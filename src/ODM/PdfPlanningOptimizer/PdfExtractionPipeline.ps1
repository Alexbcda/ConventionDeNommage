# ============================================================
# PdfExtractionPipeline.ps1
# Orchestrateur unique : normalisation → ancres → blocs → validation
# → extraction (scoring intégré) → rôles sémantiques.
# Composition uniquement — ne modifie pas les modules sous-jacents.
# Chargement : . (Join-Path $PSScriptRoot 'PdfExtractionPipeline.ps1')
# ============================================================

. (Join-Path $PSScriptRoot 'Extractors\PdfTextNormalizer.ps1')
# Code sous Obsolete\*.ignore (CleanPdfPlanningOptimizer.ps1)
. (Join-Path $PSScriptRoot 'Obsolete\Anchors.ignore\AnchorEngine.ps1')
. (Join-Path $PSScriptRoot 'Obsolete\Anchors.ignore\AnchorBlockBuilder.ps1')
. (Join-Path $PSScriptRoot 'Obsolete\Anchors.ignore\AnchorBlockValidator.ps1')
. (Join-Path $PSScriptRoot 'Obsolete\Anchors.ignore\AnchorEntityExtractor.ps1')
. (Join-Path $PSScriptRoot 'Obsolete\Anchors.ignore\AnchorRoleResolver.ps1')
. (Join-Path $PSScriptRoot 'Models\PdfExtractionResult.ps1')
. (Join-Path $PSScriptRoot 'Obsolete\Scoring.ignore\EntityConfidenceScorer.ps1')
. (Join-Path $PSScriptRoot 'Obsolete\Decision.ignore\EntityDecisionEngine.ps1')
. (Join-Path $PSScriptRoot 'Obsolete\Routing.ignore\EntityRoutingEngine.ps1')

function Invoke-PdfExtractionPipeline {
    <#
    .SYNOPSIS
        Exécute la chaîne complète d’extraction par ancres sur un texte (idéalement normalisé).

    .PARAMETER Text
        Texte multi-lignes issu du PDF ou équivalent.

    .OUTPUTS
        PdfExtractionResult (Blocks, Entities, Roles, ConfidenceScores, Decisions, Routing, Metadata).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$SourceFile = $null
    )

    $workingText = $Text
    if ($null -eq $workingText) {
        $workingText = ''
    }

    $previousEap = $ErrorActionPreference
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $ErrorActionPreference = 'Stop'
        # --- 1. Normalisation (délégation PdfTextNormalizer ; détection par diff) ---
        Write-Verbose 'Pipeline [Normalisation]: début.'
        $unifiedInput = $workingText -replace "`r`n", "`n" -replace "`r", "`n"
        if ($null -eq $unifiedInput) { $unifiedInput = '' }
        # Normalize-PdfNoiseText attend [string[]] ; éviter le scalaire '' ou tableaux ambigus.
        $linesIn = if ($unifiedInput.Length -eq 0) {
            [string[]]@('')
        }
        else {
            [string[]]($unifiedInput -split "`n", [System.StringSplitOptions]::None)
        }
        # PowerShell ne lie pas [string[]] contenant '' (lignes vides) vers -Lines ; espace réservé puis Trim côté normaliseur.
        $linesForNorm = [System.Collections.Generic.List[string]]::new()
        foreach ($ln in $linesIn) {
            if ($null -eq $ln -or [string]::IsNullOrEmpty([string]$ln)) {
                [void]$linesForNorm.Add(' ')
            }
            else {
                [void]$linesForNorm.Add([string]$ln)
            }
        }
        $normLines = Normalize-PdfNoiseText -Lines @($linesForNorm.ToArray())
        $afterNorm = $normLines -join "`n"
        if ($afterNorm -ceq $unifiedInput) {
            Write-Verbose ('Pipeline [Normalisation]: fin - aucun changement (' + $linesIn.Count + ' lignes) ; entree deja normalisee.')
        }
        else {
            $workingText = $afterNorm
            Write-Verbose ('Pipeline [Normalisation]: fin - texte ajuste (' + $linesIn.Count + ' lignes) via Normalize-PdfNoiseText.')
        }

        # --- 2. Find-Anchors ---
        Write-Verbose 'Pipeline [Find-Anchors]: début.'
        $anchors = @(Find-Anchors -Text $workingText -Verbose)
        Write-Verbose "Pipeline [Find-Anchors]: fin — $($anchors.Count) ancre(s)."

        # --- 3. Build-AnchorBlocks ---
        Write-Verbose 'Pipeline [Build-AnchorBlocks]: début.'
        $blocks = @(Build-AnchorBlocks -Text $workingText -Anchors $anchors -Verbose)
        Write-Verbose "Pipeline [Build-AnchorBlocks]: fin — $($blocks.Count) bloc(s)."

        # --- 4. Validate-AnchorBlocks ---
        Write-Verbose 'Pipeline [Validate-AnchorBlocks]: début.'
        $validation = @(Validate-AnchorBlocks -Blocks $blocks -Text $workingText -Verbose)
        $vOk = @($validation | Where-Object { $null -ne $_ -and $_.IsValid }).Count
        $vSus = @($validation | Where-Object { $null -ne $_ -and $_.IsSuspicious }).Count
        Write-Verbose "Pipeline [Validate-AnchorBlocks]: fin — $($validation.Count) rapport(s) ; valides=$vOk ; suspects=$vSus."

        # --- 5. Extraction + scoring (Get-BestAnchorMatch dans Extract-AnchorEntities) ---
        Write-Verbose 'Pipeline [Extract-AnchorEntities / scoring]: début.'
        $entities = @(Extract-AnchorEntities -ValidatedBlocks $validation -Blocks $blocks -Text $workingText -Verbose)
        Write-Verbose "Pipeline [Extract-AnchorEntities / scoring]: fin — $($entities.Count) lignes entite(s)."

        # --- 5b. Confiance entités (MVP) — rapports validation passés via -Blocks (alias BlockValidation) ---
        Write-Verbose 'Pipeline [Compute-EntityConfidence]: début.'
        $confidenceScores = @(Compute-EntityConfidence -Entities $entities -Blocks $validation -Verbose)
        Write-Verbose "Pipeline [Compute-EntityConfidence]: fin — $($confidenceScores.Count) score(s)."

        # --- 5c. Décision (OK / REVIEW / REJECT) ---
        Write-Verbose 'Pipeline [Resolve-EntityDecision]: début.'
        $decisions = @(Resolve-EntityDecision -ConfidenceScores $confidenceScores -Verbose)
        Write-Verbose "Pipeline [Resolve-EntityDecision]: fin — $($decisions.Count) décision(s)."

        # --- 5d. Routage par statut ---
        Write-Verbose 'Pipeline [Route-Entities]: début.'
        $routing = Route-Entities -Entities $entities -Decisions $decisions -Verbose
        Write-Verbose "Pipeline [Route-Entities]: fin — Ok=$($routing.OkEntities.Count) Review=$($routing.ReviewQueue.Count) Rejected=$($routing.Rejected.Count)."

        # --- 6. Resolve-AnchorRoles ---
        Write-Verbose 'Pipeline [Resolve-AnchorRoles]: début.'
        $roles = @(Resolve-AnchorRoles -Blocks $blocks -ScoredAnchors $entities -Text $workingText -Verbose)
        Write-Verbose "Pipeline [Resolve-AnchorRoles]: fin — $($roles.Count) résolution(s) de rôles."

        Write-Verbose 'Pipeline: terminé avec succès.'

        $sw.Stop()
        return New-PdfExtractionResult `
            -Blocks $blocks `
            -Entities $entities `
            -Roles $roles `
            -ConfidenceScores $confidenceScores `
            -Decisions $decisions `
            -Routing $routing `
            -BlockCount $blocks.Count `
            -EntityCount $entities.Count `
            -RoleCount $roles.Count `
            -SuspiciousBlockCount $vSus `
            -ValidBlockCount $vOk `
            -ProcessingTimeMs $sw.ElapsedMilliseconds `
            -SourceFile $SourceFile
    }
    catch {
        if ($sw.IsRunning) { $sw.Stop() }
        throw ('PdfExtractionPipeline: echec - ' + $_.Exception.Message)
    }
    finally {
        $ErrorActionPreference = $previousEap
    }
}

# --- Test sur 1 fichier texte du dépôt (exécution directe uniquement, pas dot-sourcing) ---
if ($MyInvocation.InvocationName -ne '.') {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    $samplePath = Join-Path $repoRoot 'ordre_de_missions.txt'
    if (-not (Test-Path -LiteralPath $samplePath)) {
        Write-Warning "PdfExtractionPipeline: fichier d’exemple introuvable : $samplePath"
    }
    else {
        Write-Host ('=== PdfExtractionPipeline - test sur : ' + $samplePath + ' ===') -ForegroundColor Cyan
        $raw = Get-Content -LiteralPath $samplePath -Raw -Encoding UTF8
        $result = Invoke-PdfExtractionPipeline -Text $raw -SourceFile $samplePath -Verbose
        Write-Host '--- Routage (elements par categorie) ---' -ForegroundColor Cyan
        Write-Host ("OkEntities    : {0}" -f @($result.Routing.OkEntities).Count)
        Write-Host ("ReviewQueue   : {0}" -f @($result.Routing.ReviewQueue).Count)
        Write-Host ("Rejected      : {0}" -f @($result.Routing.Rejected).Count)
    }
}

# ============================================================
# MergeTelemetry.ps1
# Observabilité passive v1 autour de Merge-EntityTournees.
#
# Aucune dépendance métier : ne lit pas Excel/PDF/ResolvedMatches ; uniquement des compteurs
# et des chaînes fournies par le merge engine (consommation passive).
# ============================================================

$script:MergeTelemetryState = @{
    Active                 = $false
    TourCount              = 0
    StopCount              = 0
    ByMergeStatus          = @{}
    ByDecisionStatus       = @{}
    Stopwatch              = $null
    LastReport             = $null
}

function script:MergeTelemetry-Bump {
    param(
        [hashtable]$Table,
        [string]$Key
    )
    if ([string]::IsNullOrWhiteSpace($Key)) {
        $Key = '(empty)'
    }
    if (-not $Table.ContainsKey($Key)) {
        $Table[$Key] = 0
    }
    $Table[$Key] = [int]$Table[$Key] + 1
}

function script:MergeTelemetry-RecordTour {
    if (-not $script:MergeTelemetryState.Active) { return }
    $script:MergeTelemetryState.TourCount = [int]$script:MergeTelemetryState.TourCount + 1
}

function script:MergeTelemetry-RecordStop {
    param(
        [string]$MergeStatus,
        [string]$DecisionStatus
    )
    if (-not $script:MergeTelemetryState.Active) { return }
    $script:MergeTelemetryState.StopCount = [int]$script:MergeTelemetryState.StopCount + 1
    MergeTelemetry-Bump -Table $script:MergeTelemetryState.ByMergeStatus -Key $MergeStatus
    MergeTelemetry-Bump -Table $script:MergeTelemetryState.ByDecisionStatus -Key $DecisionStatus
}

function Start-MergeTelemetry {
    <#
    .SYNOPSIS
        Initialise une session de mesure pour un appel Merge-EntityTournees (niveau externe).

    .NOTES
        MergeTelemetry contrat v1 — ne pas modifier les sémantiques sans bump de version.
        Aucune logique métier : état interne uniquement.
    #>
    [CmdletBinding()]
    param()

    $script:MergeTelemetryState.Active = $true
    $script:MergeTelemetryState.TourCount = 0
    $script:MergeTelemetryState.StopCount = 0
    $script:MergeTelemetryState.ByMergeStatus = @{}
    $script:MergeTelemetryState.ByDecisionStatus = @{}
    $script:MergeTelemetryState.Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $script:MergeTelemetryState.LastReport = $null
}

function Stop-MergeTelemetry {
    <#
    .SYNOPSIS
        Finalise la session et remplit LastReport pour Get-MergeTelemetryReport.

    .NOTES
        Contrat v1 — objet LastReport (champs figés) :
        - MergeTelemetryContractVersion (int) : toujours 1 pour cette version.
        - TourCountProcessed (int)
        - StopCount (int)
        - MergeStatusDistribution (PSCustomObject : paires nom→effectif, triées par nom de clé)
        - DecisionStatusDistribution (PSCustomObject idem)
        - Elapsed (TimeSpan)
        - ElapsedMilliseconds (int64)
        Renommage / suppression = changement de contrat (incrémenter version + doc).
    #>
    [CmdletBinding()]
    param()

    if (-not $script:MergeTelemetryState.Active) {
        return
    }

    $sw = $script:MergeTelemetryState.Stopwatch
    if ($null -ne $sw) {
        $sw.Stop()
    }

    $elapsed = if ($null -ne $sw) { $sw.Elapsed } else { [timespan]::Zero }
    $elapsedMs = [int64]$elapsed.TotalMilliseconds

    $distMerge = [ordered]@{}
    foreach ($k in ($script:MergeTelemetryState.ByMergeStatus.Keys | Sort-Object)) {
        $distMerge[$k] = $script:MergeTelemetryState.ByMergeStatus[$k]
    }
    $distDec = [ordered]@{}
    foreach ($k in ($script:MergeTelemetryState.ByDecisionStatus.Keys | Sort-Object)) {
        $distDec[$k] = $script:MergeTelemetryState.ByDecisionStatus[$k]
    }

    $script:MergeTelemetryState.LastReport = [pscustomobject]@{
        MergeTelemetryContractVersion = 1
        TourCountProcessed             = [int]$script:MergeTelemetryState.TourCount
        StopCount                      = [int]$script:MergeTelemetryState.StopCount
        MergeStatusDistribution        = [pscustomobject]$distMerge
        DecisionStatusDistribution     = [pscustomobject]$distDec
        Elapsed                        = $elapsed
        ElapsedMilliseconds            = $elapsedMs
    }

    $script:MergeTelemetryState.Active = $false
}

function Get-MergeTelemetryReport {
    <#
    .SYNOPSIS
        Dernier rapport produit par Stop-MergeTelemetry (lecture seule).

    .NOTES
        Contrat v1 — mêmes propriétés que LastReport (voir Stop-MergeTelemetry .NOTES).
        Rapport vide : MergeTelemetryContractVersion = 1, compteurs à zéro, distributions vides.
    #>
    [CmdletBinding()]
    param()

    if ($null -eq $script:MergeTelemetryState.LastReport) {
        return [pscustomobject]@{
            MergeTelemetryContractVersion = 1
            TourCountProcessed             = 0
            StopCount                      = 0
            MergeStatusDistribution        = [pscustomobject]@{}
            DecisionStatusDistribution     = [pscustomobject]@{}
            Elapsed                        = [timespan]::Zero
            ElapsedMilliseconds            = 0
        }
    }
    return $script:MergeTelemetryState.LastReport
}

# ============================================================
# PdfExtractionResult.ps1
# Contrat de sortie stable pour Invoke-PdfExtractionPipeline.
# ============================================================

function New-PdfExtractionResult {
    <#
    .SYNOPSIS
        Construit l’objet résultat standard du pipeline d’extraction PDF (ancres).
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Blocks,

        [AllowEmptyCollection()]
        [object[]]$Entities,

        [AllowEmptyCollection()]
        [object[]]$Roles,

        [AllowEmptyCollection()]
        [object[]]$ConfidenceScores = @(),

        [AllowEmptyCollection()]
        [object[]]$Decisions = @(),

        [AllowNull()]
        [object]$Routing = $null,

        [int]$BlockCount = 0,
        [int]$EntityCount = 0,
        [int]$RoleCount = 0,
        [int]$SuspiciousBlockCount = 0,
        [int]$ValidBlockCount = 0,
        [long]$ProcessingTimeMs = 0,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$SourceFile
    )

    $okCount = @($Decisions | Where-Object { $null -ne $_ -and [string]$_.Status -ceq 'OK' }).Count
    $reviewCount = @($Decisions | Where-Object { $null -ne $_ -and [string]$_.Status -ceq 'REVIEW' }).Count
    $rejectCount = @($Decisions | Where-Object { $null -ne $_ -and [string]$_.Status -ceq 'REJECT' }).Count

    $routedOk = 0
    $routedReview = 0
    $routedReject = 0
    if ($null -ne $Routing) {
        if ($null -ne $Routing.PSObject.Properties['OkEntities']) {
            $routedOk = @($Routing.OkEntities).Count
        }
        if ($null -ne $Routing.PSObject.Properties['ReviewQueue']) {
            $routedReview = @($Routing.ReviewQueue).Count
        }
        if ($null -ne $Routing.PSObject.Properties['Rejected']) {
            $routedReject = @($Routing.Rejected).Count
        }
    }

    $meta = [pscustomobject]@{
        BlockCount           = $BlockCount
        EntityCount          = $EntityCount
        RoleCount            = $RoleCount
        SuspiciousBlockCount = $SuspiciousBlockCount
        ValidBlockCount      = $ValidBlockCount
        OkCount              = $okCount
        ReviewCount          = $reviewCount
        RejectCount          = $rejectCount
        RoutedOkCount        = $routedOk
        RoutedReviewCount    = $routedReview
        RoutedRejectCount    = $routedReject
        ProcessingTimeMs     = $ProcessingTimeMs
        SourceFile           = $SourceFile
    }

    return [pscustomobject]@{
        Blocks            = $Blocks
        Entities          = $Entities
        Roles             = $Roles
        ConfidenceScores  = $ConfidenceScores
        Decisions         = $Decisions
        Routing           = $Routing
        Metadata          = $meta
    }
}

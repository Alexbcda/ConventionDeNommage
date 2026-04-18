# ============================================================
# EntityDecisionEngine.ps1
# Couche décisionnelle MVP à partir des scores de confiance.
# Chargement : . (Join-Path $PSScriptRoot 'Decision\EntityDecisionEngine.ps1')
# ============================================================

function Resolve-EntityDecision {
    <#
    .SYNOPSIS
        Attribue un statut (OK / REVIEW / REJECT) à partir du ConfidenceScore.

    .PARAMETER ConfidenceScores
        Sortie Compute-EntityConfidence (ClientBlockId, ConfidenceScore, …).

    .OUTPUTS
        ClientBlockId, ConfidenceScore, Status (OK si >= 80 ; REVIEW si 50–79 ; REJECT si < 50).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$ConfidenceScores
    )

    Write-Verbose "Resolve-EntityDecision: début — $($ConfidenceScores.Count) score(s)."

    $out = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $ConfidenceScores) {
        if ($null -eq $row) { continue }

        $cid = [int]$row.ClientBlockId
        $score = [int]$row.ConfidenceScore

        $status = if ($score -ge 80) {
            'OK'
        }
        elseif ($score -ge 50) {
            'REVIEW'
        }
        else {
            'REJECT'
        }

        Write-Verbose "Resolve-EntityDecision: ClientBlockId=$cid score=$score -> Status=$status"

        $out.Add([pscustomobject]@{
            ClientBlockId     = $cid
            ConfidenceScore   = $score
            Status            = $status
        })
    }

    Write-Verbose "Resolve-EntityDecision: fin — $($out.Count) décision(s)."
    return $out.ToArray()
}

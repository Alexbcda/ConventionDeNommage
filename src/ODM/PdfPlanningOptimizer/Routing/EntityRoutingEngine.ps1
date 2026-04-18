# ============================================================
# EntityRoutingEngine.ps1
# Routage des entités extraites selon le statut de décision (OK / REVIEW / REJECT).
# Chargement : . (Join-Path $PSScriptRoot 'Routing\EntityRoutingEngine.ps1')
# ============================================================

function Route-Entities {
    <#
    .SYNOPSIS
        Répartit les entités dans OkEntities, ReviewQueue ou Rejected selon Status.

    .PARAMETER Entities
        Sortie Extract-AnchorEntities.

    .PARAMETER Decisions
        Sortie Resolve-EntityDecision (ClientBlockId, Status).

    .OUTPUTS
        OkEntities, ReviewQueue, Rejected (tableaux d’objets entité).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Entities,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Decisions
    )

    Write-Verbose "Route-Entities: début — $($Entities.Count) entité(s), $($Decisions.Count) décision(s)."

    $decByCid = @{}
    foreach ($d in $Decisions) {
        if ($null -eq $d) { continue }
        $decByCid[[int]$d.ClientBlockId] = $d
    }

    $okList = [System.Collections.Generic.List[object]]::new()
    $reviewList = [System.Collections.Generic.List[object]]::new()
    $rejectList = [System.Collections.Generic.List[object]]::new()

    foreach ($ent in $Entities) {
        if ($null -eq $ent) { continue }
        $cid = [int]$ent.ClientBlockId
        if (-not $decByCid.ContainsKey($cid)) {
            Write-Verbose "Route-Entities: aucune décision pour ClientBlockId=$cid — entité ignorée."
            continue
        }

        $status = [string]$decByCid[$cid].Status
        switch -CaseSensitive ($status) {
            'OK' {
                [void]$okList.Add($ent)
                Write-Verbose "Route-Entities: ClientBlockId=$cid -> OkEntities"
            }
            'REVIEW' {
                [void]$reviewList.Add($ent)
                Write-Verbose "Route-Entities: ClientBlockId=$cid -> ReviewQueue"
            }
            'REJECT' {
                [void]$rejectList.Add($ent)
                Write-Verbose "Route-Entities: ClientBlockId=$cid -> Rejected"
            }
            default {
                Write-Verbose "Route-Entities: ClientBlockId=$cid — Status inconnu '$status', ignoré."
            }
        }
    }

    $out = [pscustomobject]@{
        OkEntities    = @($okList.ToArray())
        ReviewQueue   = @($reviewList.ToArray())
        Rejected      = @($rejectList.ToArray())
    }

    Write-Verbose "Route-Entities: fin — Ok=$($out.OkEntities.Count) ; Review=$($out.ReviewQueue.Count) ; Rejected=$($out.Rejected.Count)."
    return $out
}

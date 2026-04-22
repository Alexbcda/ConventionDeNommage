# ============================================================
# EntityConfidenceScorer.ps1
# Score de confiance MVP sur les entités extraites (0–100).
# Chargement : . (Join-Path $PSScriptRoot 'Scoring\EntityConfidenceScorer.ps1')
# ============================================================

function Compute-EntityConfidence {
    <#
    .SYNOPSIS
        Calcule un score de confiance par entité extraite.

    .PARAMETER Entities
        Sortie Extract-AnchorEntities (ClientBlockId, ClientName, ClientId, WorkOrders, Address, Date).

    .PARAMETER BlockValidation
        Sortie Validate-AnchorBlocks (ClientBlockId, IsSuspicious, NoiseScore, …) pour les pénalités.

    .PARAMETER Blocks
        Alias de BlockValidation (même jeu de données que les « blocs » validés côté pipeline).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Entities,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [Alias('Blocks')]
        [object[]]$BlockValidation
    )

    Write-Verbose "Compute-EntityConfidence: début — $($Entities.Count) entité(s), $($BlockValidation.Count) rapport(s) validation."

    $valByCid = @{}
    foreach ($v in $BlockValidation) {
        if ($null -eq $v) { continue }
        $cid = [int]$v.ClientBlockId
        $valByCid[$cid] = $v
    }

    $out = [System.Collections.Generic.List[object]]::new()

    foreach ($ent in $Entities) {
        if ($null -eq $ent) { continue }

        $cid = [int]$ent.ClientBlockId
        $missing = [System.Collections.Generic.List[string]]::new()
        $score = 0

        if (-not [string]::IsNullOrWhiteSpace([string]$ent.ClientName)) {
            $score += 20
        }
        else {
            [void]$missing.Add('ClientName')
        }

        $idStr = if ($null -ne $ent.ClientId) { [string]$ent.ClientId } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($idStr)) {
            $score += 20
        }
        else {
            [void]$missing.Add('ClientId')
        }

        $wos = @($ent.WorkOrders)
        if ($wos.Count -ge 1) {
            $score += 20
        }
        else {
            [void]$missing.Add('WorkOrders')
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$ent.Address)) {
            $score += 20
        }
        else {
            [void]$missing.Add('Address')
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$ent.Date)) {
            $score += 20
        }
        else {
            [void]$missing.Add('Date')
        }

        if ($valByCid.ContainsKey($cid)) {
            $vr = $valByCid[$cid]
            if ($null -ne $vr -and [bool]$vr.IsSuspicious) {
                $score -= 10
                Write-Verbose "Compute-EntityConfidence: ClientBlockId=$cid — pénalité IsSuspicious (-10)."
            }
            $ns = 0
            if ($null -ne $vr.PSObject.Properties['NoiseScore']) {
                $ns = [int]$vr.NoiseScore
            }
            if ($ns -gt 0) {
                $score -= 5
                Write-Verbose "Compute-EntityConfidence: ClientBlockId=$cid — pénalité NoiseScore=$ns (-5)."
            }
        }

        if ($score -lt 0) { $score = 0 }
        if ($score -gt 100) { $score = 100 }

        Write-Verbose "Compute-EntityConfidence: ClientBlockId=$cid — score=$score ; manquants=$([string]::Join(',', $missing))."

        $out.Add([pscustomobject]@{
            ClientBlockId     = $cid
            ConfidenceScore   = $score
            MissingFields     = @($missing.ToArray())
        })
    }

    Write-Verbose "Compute-EntityConfidence: fin — $($out.Count) score(s)."
    return $out.ToArray()
}

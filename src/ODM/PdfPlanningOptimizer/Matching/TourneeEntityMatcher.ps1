# ============================================================
# TourneeEntityMatcher.ps1
# Association des WorkOrders extraits (PDF / pipeline) aux arrêts Excel (tournées).
# Déterministe : pas de fuzzy sur les ODM ; trim + comparaison ordinale (WO insensible à la casse).
# ============================================================

function script:Normalize-IdForMatch {
    param([string]$s)
    if ($null -eq $s) { return '' }
    return ([string]$s).Trim()
}

function script:Test-WorkOrderStringsEqual {
    param([string]$A, [string]$B)
    $x = Normalize-IdForMatch -s $A
    $y = Normalize-IdForMatch -s $B
    if ($x -eq '' -or $y -eq '') { return $false }
    return [string]::Equals($x, $y, [System.StringComparison]::OrdinalIgnoreCase)
}

function script:Test-ClientIdsAligned {
    param([string]$ExcelId, [string]$PdfId)
    $e = Normalize-IdForMatch -s $ExcelId
    $p = Normalize-IdForMatch -s $PdfId
    if ($e -eq '' -and $p -eq '') { return $true }
    if ($e -eq '' -or $p -eq '') { return $false }
    return [string]::Equals($e, $p, [System.StringComparison]::OrdinalIgnoreCase)
}

function script:Get-EntityWorkOrderCandidates {
    param([object]$Entity)
    $list = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Entity) { return @($list) }
    $wos = $Entity.WorkOrders
    if ($null -eq $wos) { return @($list) }
    foreach ($w in @($wos)) {
        if ($null -eq $w) { continue }
        $t = ([string]$w).Trim()
        if ($t -ne '') { [void]$list.Add($t) }
    }
    return @($list)
}

function Match-EntitiesToTournees {
    <#
    .SYNOPSIS
        Associe les WorkOrders des entités extraites aux arrêts Excel des tournées.

    .PARAMETER Tournees
        Liste de Tournee (Stops avec Position, WorkOrder, ClientId).

    .PARAMETER Entities
        Lignes type Extract-AnchorEntities (WorkOrders, ClientId, ClientBlockId, …).

    .OUTPUTS
        PSCustomObject par arrêt Excel : TourneeId, Position, Status (MATCH / REVIEW / MISSING),
        ExcelWorkOrder, ExcelClientId, MatchedEntity, ClientBlockId.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Tournees,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Entities
    )

    Write-Verbose "Match-EntitiesToTournees: début — $($Tournees.Count) tournée(s), $($Entities.Count) entité(s)."

    $pool = [System.Collections.Generic.List[object]]::new()
    foreach ($e in $Entities) {
        if ($null -eq $e) { continue }
        [void]$pool.Add([pscustomobject]@{
            Entity       = $e
            ClientBlockId = [int]$e.ClientBlockId
            Used         = $false
        })
    }

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($tour in $Tournees) {
        if ($null -eq $tour) { continue }
        $tid = [string]$tour.TourneeId
        $stops = @($tour.Stops)
        if ($stops.Count -eq 0) { continue }

        foreach ($stop in $stops) {
            if ($null -eq $stop) { continue }
            $pos = [int]$stop.Position
            $excelWo = [string]$stop.WorkOrder
            $excelCid = [string]$stop.ClientId

            if ([string]::IsNullOrWhiteSpace((Normalize-IdForMatch -s $excelWo))) {
                Write-Verbose "Match-EntitiesToTournees: [$tid] pos=$pos — WorkOrder Excel vide -> MISSING."
                [void]$results.Add([pscustomobject]@{
                    TourneeId       = $tid
                    Position        = $pos
                    Status          = 'MISSING'
                    ExcelWorkOrder  = $excelWo
                    ExcelClientId   = $excelCid
                    MatchedEntity   = $null
                    ClientBlockId   = $null
                })
                continue
            }

            $picked = $null
            foreach ($slot in $pool) {
                if ($slot.Used) { continue }
                $ent = $slot.Entity
                $wos = Get-EntityWorkOrderCandidates -Entity $ent
                $woHit = $false
                foreach ($cw in $wos) {
                    if (Test-WorkOrderStringsEqual -A $excelWo -B $cw) {
                        $woHit = $true
                        break
                    }
                }
                if (-not $woHit) { continue }

                $pdfCid = $null
                if ($null -ne $ent.PSObject.Properties['ClientId']) {
                    $pdfCid = [string]$ent.ClientId
                }

                $picked = [pscustomobject]@{
                    Slot  = $slot
                    PdfCid = $pdfCid
                }
                break
            }

            if ($null -eq $picked) {
                Write-Verbose "Match-EntitiesToTournees: [$tid] pos=$pos WO='$excelWo' -> MISSING."
                [void]$results.Add([pscustomobject]@{
                    TourneeId       = $tid
                    Position        = $pos
                    Status          = 'MISSING'
                    ExcelWorkOrder  = $excelWo
                    ExcelClientId   = $excelCid
                    MatchedEntity   = $null
                    ClientBlockId   = $null
                })
                continue
            }

            $slot = $picked.Slot
            $pdfCid = $picked.PdfCid
            $aligned = Test-ClientIdsAligned -ExcelId $excelCid -PdfId $pdfCid

            if ($aligned) {
                $status = 'MATCH'
            }
            else {
                $status = 'REVIEW'
            }

            $slot.Used = $true
            Write-Verbose "Match-EntitiesToTournees: [$tid] pos=$pos WO='$excelWo' -> $status (ClientBlockId=$($slot.ClientBlockId))."

            [void]$results.Add([pscustomobject]@{
                TourneeId       = $tid
                Position        = $pos
                Status          = $status
                ExcelWorkOrder  = $excelWo
                ExcelClientId   = $excelCid
                MatchedEntity   = $slot.Entity
                ClientBlockId   = $slot.ClientBlockId
            })
        }
    }

    $arr = @($results.ToArray())
    Write-Verbose "Match-EntitiesToTournees: fin — $($arr.Count) ligne(s)."
    return $arr
}

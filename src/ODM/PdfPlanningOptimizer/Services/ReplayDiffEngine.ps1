# ============================================================
# ReplayDiffEngine.ps1
# Diff deterministe entre deux etats en memoire : PSCustomObject avec Tournees -> Stops
# (meme enveloppe que la sortie Merge-EntityTournees.Tournees).
# Aucun acces fichier ; aucune dependance aux merge engines (pas de dot-source).
# ============================================================

$script:Rde_CompareFields = @('ClientId', 'WorkOrder', 'Address', 'Date', 'ClientName')

function script:Rde-GetStopKey {
    param(
        [string]$TourneeId,
        [int]$Position
    )
    return ('{0}|{1}' -f [string]$TourneeId, [int]$Position)
}

function script:Rde-NormalizeStringId {
    param([object]$Value)
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Trim()
}

function script:Rde-NormalizeComparable {
    param(
        [string]$FieldName,
        [object]$Value
    )
    if ($null -eq $Value) { return '' }
    switch ($FieldName) {
        'Date' {
            if ($Value -is [datetime]) {
                return $Value.ToUniversalTime().ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
            }
            $s = ([string]$Value).Trim()
            try {
                $dt = [datetime]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)
                return $dt.ToUniversalTime().ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
            }
            catch {
                return $s
            }
        }
        Default {
            return Rde-NormalizeStringId -Value $Value
        }
    }
}

function script:Rde-ValuesEqual {
    param(
        [string]$FieldName,
        [object]$A,
        [object]$B
    )
    $na = Rde-NormalizeComparable -FieldName $FieldName -Value $A
    $nb = Rde-NormalizeComparable -FieldName $FieldName -Value $B
    if ($FieldName -in @('ClientId', 'WorkOrder')) {
        return [string]::Equals($na, $nb, [System.StringComparison]::OrdinalIgnoreCase)
    }
    return [string]::Equals($na, $nb, [System.StringComparison]::OrdinalIgnoreCase)
}

function script:Rde-FlattenStopsByKey {
    param([object]$Replay)
    $map = @{}
    if ($null -eq $Replay) { return $map }
    $tours = @($Replay.Tournees)
    foreach ($t in $tours) {
        if ($null -eq $t) { continue }
        $tid = [string]$t.TourneeId
        $stops = @($t.Stops) | Sort-Object -Property @{ Expression = { [int]$_.Position }; Ascending = $true }
        foreach ($s in $stops) {
            if ($null -eq $s) { continue }
            $pos = [int]$s.Position
            $k = Rde-GetStopKey -TourneeId $tid -Position $pos
            $map[$k] = @{
                TourneeId = $tid
                Position  = $pos
                Stop      = $s
            }
        }
    }
    return $map
}

function script:Rde-ShallowStopSnapshot {
    param([object]$Stop)
    if ($null -eq $Stop) { return $null }
    $o = [ordered]@{}
    foreach ($p in $Stop.PSObject.Properties) {
        if ($p.MemberType -ne 'NoteProperty' -and $p.MemberType -ne 'Property') { continue }
        $o[$p.Name] = $p.Value
    }
    return [pscustomobject]$o
}

function Compare-HumanReplayStates {
    <#
    .SYNOPSIS
        Compare deux structures PSCustomObject Tournees -> Stops (cle TourneeId|Position).

    .OUTPUTS
        PSCustomObject : ChangedStops, AddedStops, RemovedStops, FieldLevelDiffs, Summary.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ReplayA,

        [Parameter(Mandatory = $true)]
        [object]$ReplayB
    )

    $mapA = Rde-FlattenStopsByKey -Replay $ReplayA
    $mapB = Rde-FlattenStopsByKey -Replay $ReplayB

    $keysA = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($k in $mapA.Keys) { [void]$keysA.Add($k) }
    $keysB = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($k in $mapB.Keys) { [void]$keysB.Add($k) }

    $allKeys = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($k in $keysA) { [void]$allKeys.Add($k) }
    foreach ($k in $keysB) { [void]$allKeys.Add($k) }

    $keyTuples = foreach ($k in @($allKeys)) {
        $parts = $k -split '\|', 2
        [pscustomobject]@{ Key = $k; T = [string]$parts[0]; P = [int]$parts[1] }
    }
    $sortedKeys = @($keyTuples | Sort-Object -Property @{ Expression = 'T'; Ascending = $true }, @{ Expression = 'P'; Ascending = $true } | ForEach-Object { $_.Key })

    $onlyInA = 0
    foreach ($k in @($keysA)) {
        if (-not $keysB.Contains($k)) { $onlyInA++ }
    }
    $onlyInB = 0
    foreach ($k in @($keysB)) {
        if (-not $keysA.Contains($k)) { $onlyInB++ }
    }
    Write-Verbose ("ReplayDiffEngine: cles comparees (union) = {0} ; clefs seulement A = {1} ; seulement B = {2}" -f $allKeys.Count, $onlyInA, $onlyInB)

    $removed = [System.Collections.Generic.List[object]]::new()
    $added = [System.Collections.Generic.List[object]]::new()
    $changed = [System.Collections.Generic.List[object]]::new()
    $fieldDiffs = [System.Collections.Generic.List[object]]::new()
    $fieldImpact = @{}
    foreach ($f in $script:Rde_CompareFields) {
        $fieldImpact[$f] = 0
    }

    foreach ($k in $sortedKeys) {
        $inA = $mapA.ContainsKey($k)
        $inB = $mapB.ContainsKey($k)
        if ($inA -and -not $inB) {
            $e = $mapA[$k]
            [void]$removed.Add([pscustomobject]@{
                TourneeId = $e.TourneeId
                Position  = $e.Position
                Stop      = (Rde-ShallowStopSnapshot -Stop $e.Stop)
            })
            continue
        }
        if ($inB -and -not $inA) {
            $e = $mapB[$k]
            [void]$added.Add([pscustomobject]@{
                TourneeId = $e.TourneeId
                Position  = $e.Position
                Stop      = (Rde-ShallowStopSnapshot -Stop $e.Stop)
            })
            continue
        }
        if ($inA -and $inB) {
            $sa = $mapA[$k].Stop
            $sb = $mapB[$k].Stop
            $rowChanged = $false
            foreach ($fn in $script:Rde_CompareFields) {
                $va = $null
                $vb = $null
                if ($null -ne $sa -and $null -ne $sa.PSObject.Properties[$fn]) { $va = $sa.PSObject.Properties[$fn].Value }
                if ($null -ne $sb -and $null -ne $sb.PSObject.Properties[$fn]) { $vb = $sb.PSObject.Properties[$fn].Value }
                if (-not (Rde-ValuesEqual -FieldName $fn -A $va -B $vb)) {
                    $rowChanged = $true
                    [void]$fieldDiffs.Add([pscustomobject]@{
                        TourneeId = $mapA[$k].TourneeId
                        Position  = $mapA[$k].Position
                        Field     = $fn
                        ValueA    = $va
                        ValueB    = $vb
                    })
                    $fieldImpact[$fn] = [int]$fieldImpact[$fn] + 1
                }
            }
            if ($rowChanged) {
                [void]$changed.Add([pscustomobject]@{
                    TourneeId = $mapA[$k].TourneeId
                    Position  = $mapA[$k].Position
                })
            }
        }
    }

    Write-Verbose ("ReplayDiffEngine: divergences - Removed={0}, Added={1}, ChangedStops={2}, FieldDiffRows={3}" -f `
            $removed.Count, $added.Count, $changed.Count, $fieldDiffs.Count)
    foreach ($fn in $script:Rde_CompareFields) {
        $c = [int]$fieldImpact[$fn]
        if ($c -gt 0) {
            Write-Verbose ("ReplayDiffEngine: ecarts champ [{0}] = {1}" -f $fn, $c)
        }
    }

    $summary = [pscustomobject]@{
        TotalStops      = [int]$allKeys.Count
        ChangedStops    = [int]$changed.Count
        AddedStops      = [int]$added.Count
        RemovedStops    = [int]$removed.Count
        FieldDiffRows   = [int]$fieldDiffs.Count
        FieldImpact     = [pscustomobject]$fieldImpact
    }

    return [pscustomobject]@{
        ChangedStops    = @($changed.ToArray())
        AddedStops      = @($added.ToArray())
        RemovedStops    = @($removed.ToArray())
        FieldLevelDiffs = @($fieldDiffs.ToArray())
        Summary         = $summary
    }
}

function Invoke-ReplayDiffEngineSelfTest {
    <#
    .SYNOPSIS
        Test minimal : deux stops identiques sauf ClientId ; FieldLevelDiffs doit contenir ClientId.
    #>
    [CmdletBinding()]
    param()
    $stopBase = [pscustomobject]@{
        Position   = 1
        ClientId   = 'CID-A'
        WorkOrder  = 'WO1'
        Address    = '1 rue X'
        Date       = [datetime]'2026-04-18'
        ClientName = 'Nom'
    }
    $stopB = [pscustomobject]@{
        Position   = 1
        ClientId   = 'cid-b'
        WorkOrder  = 'WO1'
        Address    = '1 rue X'
        Date       = [datetime]'2026-04-18'
        ClientName = 'Nom'
    }
    $replayA = [pscustomobject]@{
        Tournees = @(
            [pscustomobject]@{
                TourneeId = 'T-SELF'
                Stops     = @($stopBase)
            }
        )
    }
    $replayB = [pscustomobject]@{
        Tournees = @(
            [pscustomobject]@{
                TourneeId = 'T-SELF'
                Stops     = @($stopB)
            }
        )
    }
    $diff = Compare-HumanReplayStates -ReplayA $replayA -ReplayB $replayB
    $clientDiffs = @($diff.FieldLevelDiffs | Where-Object { $_.Field -ceq 'ClientId' })
    if ($clientDiffs.Count -ne 1) {
        throw ('Invoke-ReplayDiffEngineSelfTest: attendu 1 ecart ClientId, obtenu {0}' -f $clientDiffs.Count)
    }
    if ([int]$diff.Summary.ChangedStops -ne 1) {
        throw ('Invoke-ReplayDiffEngineSelfTest: Summary.ChangedStops attendu 1, obtenu {0}' -f $diff.Summary.ChangedStops)
    }
    return $true
}

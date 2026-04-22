# ============================================================
# TourneeInteractiveReview.ps1
# Couche « human-in-the-loop » : validation des associations
# tournée / arrêt / entité PDF sans matching ni scoring.
# ============================================================

function script:Copy-ResolvedMatchRow {
    param([object]$Row)
    if ($null -eq $Row) { return $null }
    $h = [ordered]@{}
    foreach ($p in $Row.PSObject.Properties) {
        $h[$p.Name] = $p.Value
    }
    return [pscustomobject]$h
}

function script:Get-TourneeMetaForReview {
    param(
        [object[]]$Tournees,
        [string]$TourneeId
    )
    foreach ($t in $Tournees) {
        if ($null -eq $t) { continue }
        if ([string]$t.TourneeId -ceq $TourneeId) {
            $agent = ''
            if ($null -ne $t.PSObject.Properties['Agent']) { $agent = [string]$t.Agent }
            $td = [datetime]::MinValue
            if ($null -ne $t.PSObject.Properties['TourDate']) {
                $v = $t.TourDate
                if ($null -ne $v -and $v -is [datetime]) { $td = [datetime]$v }
            }
            return @{ Agent = $agent; TourDate = $td }
        }
    }
    return @{ Agent = '(inconnu)'; TourDate = [datetime]::MinValue }
}

function script:Get-FirstWorkOrderDisplay {
    param([object]$Entity)
    if ($null -eq $Entity) { return '' }
    if ($null -eq $Entity.PSObject.Properties['WorkOrders']) { return '' }
    $w = @($Entity.WorkOrders)
    if ($w.Count -eq 0) { return '' }
    return ([string]$w[0]).Trim()
}

function script:Show-EntityPickerMenu {
    param([object[]]$Entities)
    Write-Host ''
    $idx = 0
    foreach ($ent in $Entities) {
        if ($null -eq $ent) { continue }
        $idx++
        $cid = ''
        if ($null -ne $ent.PSObject.Properties['ClientId']) { $cid = [string]$ent.ClientId }
        $cn = ''
        if ($null -ne $ent.PSObject.Properties['ClientName']) { $cn = [string]$ent.ClientName }
        $wo = Get-FirstWorkOrderDisplay -Entity $ent
        Write-Host ("[{0}] ClientId {1} | WO {2} | {3}" -f $idx, $cid, $wo, $cn) -ForegroundColor Gray
    }
    Write-Host '[0] aucune' -ForegroundColor DarkGray
}

function script:Resolve-EntityPickByIndex {
    param(
        [int]$Index,
        [object[]]$Entities
    )
    if ($Index -eq 0) { return @{ Ok = $true; Entity = $null } }
    $n = 0
    foreach ($ent in $Entities) {
        if ($null -eq $ent) { continue }
        $n++
        if ($n -eq $Index) {
            return @{ Ok = $true; Entity = $ent }
        }
    }
    return @{ Ok = $false; Entity = $null }
}

function Review-TourneesInteractively {
    <#
    .SYNOPSIS
        Validation humaine des ResolvedMatches par tournée et par arrêt (sans recalcul de matching).

    .PARAMETER Tournees
        Tournées Excel (métadonnées Agent / TourDate pour l’affichage).

    .PARAMETER ResolvedMatches
        Lignes issues de Resolve-MatchConflicts (FinalEntity, OriginalStatus, …).

    .PARAMETER Entities
        Pool d’entités PDF pour le choix manuel (option 2).

    .PARAMETER Interactive
        Active menus et saisie utilisateur.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Tournees,

        [Parameter(Mandatory = $true)]
        $ResolvedMatches,

        $Entities,

        [switch]$Interactive
    )

    $entityList = @()
    if ($null -ne $Entities) {
        $entityList = @($Entities | Where-Object { $null -ne $_ })
    }

    $working = [System.Collections.Generic.List[object]]::new()
    foreach ($r in @($ResolvedMatches)) {
        if ($null -eq $r) { continue }
        [void]$working.Add((Copy-ResolvedMatchRow -Row $r))
    }

    $snapshot = for ($si = 0; $si -lt $working.Count; $si++) {
        $sr = $working[$si]
        $cb = $null
        if ($null -ne $sr.FinalEntity -and $null -ne $sr.FinalEntity.PSObject.Properties['ClientBlockId']) {
            try {
                $cb = [int]$sr.FinalEntity.ClientBlockId
            }
            catch {
                $cb = $null
            }
        }
        [pscustomobject]@{
            ClientBlockIdSnapshot = $cb
            ResolutionSource    = if ($null -ne $sr.PSObject.Properties['ResolutionSource']) { [string]$sr.ResolutionSource } else { '' }
        }
    }

    $distinctTourneeIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($w in $working) {
        if ($null -ne $w.PSObject.Properties['TourneeId']) {
            [void]$distinctTourneeIds.Add([string]$w.TourneeId)
        }
    }
    $tourneesCount = $distinctTourneeIds.Count

    $updatedCount = 0

    if (-not $Interactive) {
        Write-Verbose "Review-TourneesInteractively: mode non interactif — $($working.Count) ligne(s) recopiée(s) sans modification."
        return [pscustomobject]@{
            ResolvedMatches = @($working.ToArray())
            ReviewSummary   = [pscustomobject]@{
                TourneesCount = $tourneesCount
                UpdatedCount  = 0
            }
        }
    }

    Write-Verbose "Review-TourneesInteractively: début interactif — $tourneesCount tournée(s), $($working.Count) ligne(s)."

    $byTour = $working | Group-Object -Property {
        [string]$_.TourneeId
    }

    foreach ($grp in ($byTour | Sort-Object -Property Name)) {
        $tid = [string]$grp.Name
        $meta = Get-TourneeMetaForReview -Tournees @($Tournees) -TourneeId $tid
        $dateStr = if ($meta.TourDate -eq [datetime]::MinValue) {
            '(date inconnue)'
        }
        else {
            $meta.TourDate.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        }

        Write-Host ''
        Write-Host '========================================' -ForegroundColor Cyan
        Write-Host ("TOURNEE : {0} | {1}" -f $meta.Agent, $dateStr) -ForegroundColor Cyan
        Write-Host '========================================' -ForegroundColor Cyan

        $rows = @($grp.Group | Sort-Object -Property @{ Expression = { [int]$_.Position }; Ascending = $true })
        Write-Verbose "Review-TourneesInteractively: tournée '$tid' — $($rows.Count) arrêt(s)."

        foreach ($row in $rows) {
            $pos = [int]$row.Position
            $excelWo = if ($null -ne $row.PSObject.Properties['ExcelWorkOrder']) { [string]$row.ExcelWorkOrder } else { '' }
            $excelCid = if ($null -ne $row.PSObject.Properties['ExcelClientId']) { [string]$row.ExcelClientId } else { '' }
            $orig = if ($null -ne $row.PSObject.Properties['OriginalStatus']) { [string]$row.OriginalStatus } else { '' }
            $rsrc = if ($null -ne $row.PSObject.Properties['ResolutionSource']) { [string]$row.ResolutionSource } else { '' }

            Write-Host ''
            Write-Host ("[Position {0}]" -f $pos) -ForegroundColor White
            Write-Host ("ExcelWorkOrder : {0}" -f $excelWo)
            Write-Host ("ExcelClientId  : {0}" -f $excelCid)
            Write-Host ("OriginalStatus : {0}" -f $orig)
            Write-Host ("ResolutionSource : {0}" -f $rsrc)

            $fe = $null
            if ($null -ne $row.PSObject.Properties['FinalEntity']) {
                $fe = $row.FinalEntity
            }
            if ($null -ne $fe) {
                Write-Host 'FinalEntity (si existant) :' -ForegroundColor DarkCyan
                $fcid = ''; $fcn = ''; $faddr = ''
                if ($null -ne $fe.PSObject.Properties['ClientId']) { $fcid = [string]$fe.ClientId }
                if ($null -ne $fe.PSObject.Properties['ClientName']) { $fcn = [string]$fe.ClientName }
                if ($null -ne $fe.PSObject.Properties['Address']) { $faddr = [string]$fe.Address }
                Write-Host ("  - ClientId   : {0}" -f $fcid)
                Write-Host ("  - ClientName : {0}" -f $fcn)
                if ($faddr -ne '') {
                    Write-Host ("  - Address    : {0}" -f $faddr)
                }
            }
            else {
                Write-Host 'FinalEntity : (aucun)' -ForegroundColor DarkGray
            }

            $ost = $orig
            if ($ost -notin 'MATCH', 'REVIEW', 'MISSING') {
                $ost = 'MATCH'
            }

            Write-Host ''
            Write-Host 'ACTION :' -ForegroundColor Yellow
            Write-Host '  0 = skip (ne rien changer)'
            Write-Host '  1 = garder tel quel (FinalEntity inchangé)'
            Write-Host '  2 = choisir une entité PDF'
            Write-Host '  3 = supprimer toute entité (FinalEntity = $null)'

            $ans = Read-Host 'Choix'
            if ($null -eq $ans) { $ans = '' }
            $ans = $ans.Trim()

            switch -Regex ($ans) {
                '^0$' {
                    Write-Verbose "Review-TourneesInteractively: [$tid] pos=$pos — skip (aucune modification)."
                }
                '^1$' {
                    Write-Verbose "Review-TourneesInteractively: [$tid] pos=$pos — garder tel quel."
                }
                '^2$' {
                    if ($entityList.Count -eq 0) {
                        Write-Warning 'Aucune entité dans -Entities — aucun changement.'
                        Write-Verbose "Review-TourneesInteractively: [$tid] pos=$pos — choix 2 annulé (liste vide)."
                        continue
                    }
                    Show-EntityPickerMenu -Entities $entityList
                    $pick = Read-Host 'Numéro entité (0 = aucune)'
                    if ($null -eq $pick) { $pick = '' }
                    $n = 0
                    if (-not [int]::TryParse($pick.Trim(), [ref]$n)) {
                        Write-Warning 'Numéro invalide — ignoré.'
                        continue
                    }
                    $res = Resolve-EntityPickByIndex -Index $n -Entities $entityList
                    if (-not $res.Ok) {
                        Write-Warning 'Index hors plage — ignoré.'
                        continue
                    }
                    $row.FinalEntity = $res.Entity
                    $row.ResolutionSource = 'Interactive'
                    Write-Verbose "Review-TourneesInteractively: [$tid] pos=$pos — entité PDF assignée (Interactive)."
                }
                '^3$' {
                    $row.FinalEntity = $null
                    $row.ResolutionSource = 'Interactive'
                    Write-Verbose "Review-TourneesInteractively: [$tid] pos=$pos — FinalEntity effacé (Interactive)."
                }
                default {
                    Write-Warning "Choix non reconnu '$ans' — ignoré."
                }
            }
        }

        Write-Verbose "Review-TourneesInteractively: fin tournée '$tid'."
    }

    for ($ui = 0; $ui -lt $working.Count; $ui++) {
        $w = $working[$ui]
        $snap = $snapshot[$ui]
        $cbNow = $null
        if ($null -ne $w.FinalEntity -and $null -ne $w.FinalEntity.PSObject.Properties['ClientBlockId']) {
            try {
                $cbNow = [int]$w.FinalEntity.ClientBlockId
            }
            catch {
                $cbNow = $null
            }
        }
        $rsNew = if ($null -ne $w.PSObject.Properties['ResolutionSource']) { [string]$w.ResolutionSource } else { '' }
        $cbWas = $snap.ClientBlockIdSnapshot
        $rsWas = $snap.ResolutionSource
        $entityChanged = ($cbWas -ne $cbNow)
        $srcChanged = ($rsWas -cne $rsNew)
        if ($entityChanged -or $srcChanged) {
            $updatedCount++
        }
    }

    Write-Verbose "Review-TourneesInteractively: fin globale — UpdatedCount=$updatedCount."

    return [pscustomobject]@{
        ResolvedMatches = @($working.ToArray())
        ReviewSummary   = [pscustomobject]@{
            TourneesCount = $tourneesCount
            UpdatedCount  = $updatedCount
        }
    }
}

# ============================================================
# MatchResolution.ps1
# Résolution manuelle des lignes REVIEW / MISSING issues de
# Match-EntitiesToTournees (choix de l’entité PDF finale par arrêt).
# ============================================================

function script:Show-MatchResolutionEntityMenu {
    param([object[]]$Entities)
    if ($null -eq $Entities -or $Entities.Count -eq 0) {
        Write-Host '  (Aucune entité candidate dans -Entities.)' -ForegroundColor DarkGray
        return
    }
    $i = 0
    foreach ($ent in $Entities) {
        if ($null -eq $ent) { continue }
        $i++
        $cid = ''
        if ($null -ne $ent.PSObject.Properties['ClientId']) {
            $cid = [string]$ent.ClientId
        }
        $cb = ''
        if ($null -ne $ent.PSObject.Properties['ClientBlockId']) {
            $cb = [string]$ent.ClientBlockId
        }
        $wos = ''
        if ($null -ne $ent.PSObject.Properties['WorkOrders']) {
            $wos = (@($ent.WorkOrders) -join ', ')
        }
        Write-Host ("  [{0}] ClientBlockId={1} ClientId={2} WO=[{3}]" -f $i, $cb, $cid, $wos) -ForegroundColor Gray
    }
}

function script:Resolve-MatchEntityFromIndex {
    param(
        [string]$Line,
        [object[]]$Entities
    )
    if ([string]::IsNullOrWhiteSpace($Line)) { return @{ Ok = $false; Entity = $null } }
    $n = 0
    if (-not [int]::TryParse($Line.Trim(), [ref]$n)) {
        return @{ Ok = $false; Entity = $null }
    }
    if ($n -lt 1 -or $n -gt $Entities.Count) {
        return @{ Ok = $false; Entity = $null }
    }
    $idx = 0
    foreach ($ent in $Entities) {
        if ($null -eq $ent) { continue }
        $idx++
        if ($idx -eq $n) {
            return @{ Ok = $true; Entity = $ent }
        }
    }
    return @{ Ok = $false; Entity = $null }
}

function Resolve-MatchConflicts {
    <#
    .SYNOPSIS
        Produit une liste résolue avec FinalEntity pour chaque ligne de matching (REVIEW / MISSING traitables en interactif).

    .PARAMETER MatchResults
        Sortie Match-EntitiesToTournees (Status, MatchedEntity, ExcelWorkOrder, …).

    .PARAMETER Entities
        Jeu d’entités PDF (Extract-AnchorEntities) pour substitution manuelle des arrêts REVIEW / MISSING.

    .PARAMETER Interactive
        Si activé : invite pour les lignes REVIEW et MISSING (MATCH conservé par défaut sur Entrée).

    .OUTPUTS
        [pscustomobject] @{ ResolvedMatches = @( … FinalEntity, ResolutionSource, … ) }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$MatchResults,

        [Parameter(Mandatory = $false)]
        [switch]$Interactive,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$Entities = @()
    )

    $entityList = @($Entities | Where-Object { $null -ne $_ })
    Write-Verbose "Resolve-MatchConflicts: début — $($MatchResults.Count) ligne(s) ; Interactive=$Interactive ; entités candidate=$($entityList.Count)."

    $out = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $MatchResults) {
        if ($null -eq $row) { continue }

        $tid = [string]$row.TourneeId
        $pos = [int]$row.Position
        $st = [string]$row.Status
        $excelWo = if ($null -ne $row.PSObject.Properties['ExcelWorkOrder']) { [string]$row.ExcelWorkOrder } else { '' }
        $excelCid = if ($null -ne $row.PSObject.Properties['ExcelClientId']) { [string]$row.ExcelClientId } else { '' }
        $matched = $null
        if ($null -ne $row.PSObject.Properties['MatchedEntity']) {
            $matched = $row.MatchedEntity
        }

        $final = $matched
        $source = 'Passthrough'

        if (-not $Interactive) {
            if ($st -ceq 'MISSING') {
                $final = $null
            }
            [void]$out.Add([pscustomobject]@{
                TourneeId       = $tid
                Position        = $pos
                OriginalStatus  = $st
                ExcelWorkOrder  = $excelWo
                ExcelClientId   = $excelCid
                FinalEntity     = $final
                ResolutionSource = $source
            })
            continue
        }

        # --- Interactif ---
        if ($st -ceq 'MATCH') {
            Write-Host ""
            Write-Host "[MATCH] Tournee=$tid Position=$pos — ODM Excel='$excelWo'" -ForegroundColor Green
            if ($null -ne $matched) {
                $mcb = ''; $mcid = ''
                if ($null -ne $matched.PSObject.Properties['ClientBlockId']) { $mcb = [string]$matched.ClientBlockId }
                if ($null -ne $matched.PSObject.Properties['ClientId']) { $mcid = [string]$matched.ClientId }
                Write-Host "  Entité retenue : ClientBlockId=$mcb ClientId=$mcid" -ForegroundColor DarkGray
            }
            Write-Host "  [Entrée] conserver | ou numéro dans la liste pour remplacer | 0 pour effacer" -ForegroundColor Yellow
            Show-MatchResolutionEntityMenu -Entities $entityList
            $ans = Read-Host "  >"
            if ($null -eq $ans) { $ans = '' }
            $ans = $ans.Trim()
            if ($ans -eq '' -or $ans -eq 'c' -or $ans -eq 'C') {
                $final = $matched
                $source = 'InteractiveKeep'
            }
            elseif ($ans -eq '0') {
                $final = $null
                $source = 'InteractiveClear'
            }
            else {
                $pick = Resolve-MatchEntityFromIndex -Line $ans -Entities $entityList
                if (-not $pick.Ok) {
                    Write-Warning 'Choix invalide — conservation de l’entité initiale.'
                    $final = $matched
                    $source = 'InteractiveKeep'
                }
                else {
                    $final = $pick.Entity
                    $source = 'InteractivePick'
                }
            }
        }
        elseif ($st -ceq 'REVIEW') {
            Write-Host ""
            Write-Host "[REVIEW] Tournee=$tid Position=$pos — ODM Excel='$excelWo' ExcelClientId='$excelCid'" -ForegroundColor DarkYellow
            if ($null -ne $matched) {
                $mcb = ''; $mcid = ''
                if ($null -ne $matched.PSObject.Properties['ClientBlockId']) { $mcb = [string]$matched.ClientBlockId }
                if ($null -ne $matched.PSObject.Properties['ClientId']) { $mcid = [string]$matched.ClientId }
                Write-Host "  Entité proposée : ClientBlockId=$mcb ClientId=$mcid" -ForegroundColor DarkGray
            }
            else {
                Write-Host '  Aucune entité proposée (données inattendues).' -ForegroundColor DarkGray
            }
            Write-Host "  [Entrée] confirmer cette entité | numéro = autre entité | 0 = aucune" -ForegroundColor Yellow
            Show-MatchResolutionEntityMenu -Entities $entityList
            $ans = Read-Host "  >"
            if ($null -eq $ans) { $ans = '' }
            $ans = $ans.Trim()
            if ($ans -eq '' -or $ans -eq 'c' -or $ans -eq 'C') {
                $final = $matched
                $source = 'InteractiveKeep'
            }
            elseif ($ans -eq '0') {
                $final = $null
                $source = 'InteractiveClear'
            }
            else {
                $pick = Resolve-MatchEntityFromIndex -Line $ans -Entities $entityList
                if (-not $pick.Ok) {
                    Write-Warning 'Choix invalide — conservation de l’entité proposée.'
                    $final = $matched
                    $source = 'InteractiveKeep'
                }
                else {
                    $final = $pick.Entity
                    $source = 'InteractivePick'
                }
            }
        }
        elseif ($st -ceq 'MISSING') {
            Write-Host ""
            Write-Host "[MISSING] Tournee=$tid Position=$pos — ODM Excel='$excelWo' ExcelClientId='$excelCid'" -ForegroundColor Red
            Write-Host "  Choisir une entité par numéro | 0 ou Entrée = aucune" -ForegroundColor Yellow
            Show-MatchResolutionEntityMenu -Entities $entityList
            $ans = Read-Host "  >"
            if ($null -eq $ans) { $ans = '' }
            $ans = $ans.Trim()
            if ($ans -eq '' -or $ans -eq '0') {
                $final = $null
                $source = 'InteractiveClear'
            }
            else {
                $pick = Resolve-MatchEntityFromIndex -Line $ans -Entities $entityList
                if (-not $pick.Ok) {
                    Write-Warning 'Choix invalide — aucune entité retenue.'
                    $final = $null
                    $source = 'InteractiveClear'
                }
                else {
                    $final = $pick.Entity
                    $source = 'InteractivePick'
                }
            }
        }
        else {
            $final = $matched
            $source = 'Passthrough'
        }

        [void]$out.Add([pscustomobject]@{
            TourneeId          = $tid
            Position           = $pos
            OriginalStatus     = $st
            ExcelWorkOrder     = $excelWo
            ExcelClientId      = $excelCid
            FinalEntity        = $final
            ResolutionSource   = $source
        })
    }

    $resolved = @($out.ToArray())
    Write-Verbose "Resolve-MatchConflicts: fin — $($resolved.Count) ligne(s) résolue(s)."

    return [pscustomobject]@{
        ResolvedMatches = $resolved
    }
}

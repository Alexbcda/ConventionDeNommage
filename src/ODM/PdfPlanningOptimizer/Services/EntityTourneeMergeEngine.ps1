# ============================================================
# EntityTourneeMergeEngine.ps1
# Single Source of Truth = EntityTourneeMergeEngine (Merge-EntityTournees).
# UNIQUE couche de fusion finale Excel ↔ PDF.
#
# Flux (vérité métier multi-sources) :
#   Excel (fichier / lignes)
#     → Tournee + TourneeStop (ordre métier, structure)
#   PDF + pipeline amont (anchors, entités)
#     → ResolvedMatches (FinalEntity, statuts, ExcelWorkOrder/ExcelClientId par arrêt)
#   HumanResolvedMatchesStore (journal événements, optionnel) + Merge-HumanAndPdfDecisions
#     → ResolvedMatchesFinal (priorité humain > PDF, clé TourneeId|Position)
#   Merge-EntityTournees
#     → sortie finale enrichie (champs résolus + MergeStatus + traçabilité)
#
# Règles : liaison arrêt par TourneeId|Position (repli WorkOrder si besoin) ;
# arbitrage des champs uniquement via FieldResolutionEngine (policy unique).
# Aucun scoring, aucun matching ODM, aucun parsing documentaire ici.
# ============================================================

$_fre = Join-Path $PSScriptRoot 'FieldResolutionEngine.ps1'
if (-not (Test-Path -LiteralPath $_fre)) {
    throw "EntityTourneeMergeEngine: FieldResolutionEngine.ps1 introuvable: $_fre"
}
. $_fre

$_mtel = Join-Path $PSScriptRoot 'MergeTelemetry.ps1'
if (-not (Test-Path -LiteralPath $_mtel)) {
    throw "EntityTourneeMergeEngine: MergeTelemetry.ps1 introuvable: $_mtel"
}
. $_mtel

$_hma = Join-Path $PSScriptRoot 'HumanMergeAdapter.ps1'
if (-not (Test-Path -LiteralPath $_hma)) {
    throw "EntityTourneeMergeEngine: HumanMergeAdapter.ps1 introuvable: $_hma"
}
. $_hma

$_hrms = Join-Path $PSScriptRoot 'HumanResolvedMatchesStore.ps1'
if (-not (Test-Path -LiteralPath $_hrms)) {
    throw "EntityTourneeMergeEngine: HumanResolvedMatchesStore.ps1 introuvable: $_hrms"
}
. $_hrms

if ($null -eq (Get-Variable -Scope Global -Name Etme_MergeCallDepth -ErrorAction SilentlyContinue)) {
    $global:Etme_MergeCallDepth = 0
}

function script:Etme-NormalizeWo {
    param([string]$s)
    if ($null -eq $s) { return '' }
    return ([string]$s).Trim()
}

function script:Etme-BuildResolvedPositionMap {
    param([AllowEmptyCollection()][object[]]$ResolvedMatches)
    $map = @{}
    if ($null -eq $ResolvedMatches) { return $map }
    foreach ($r in $ResolvedMatches) {
        if ($null -eq $r) { continue }
        if ($null -eq $r.PSObject.Properties['TourneeId'] -or $null -eq $r.PSObject.Properties['Position']) { continue }
        $tid = [string]$r.TourneeId
        $pos = [int]$r.Position
        $k = "$tid|$pos"
        if (-not $map.ContainsKey($k)) {
            $map[$k] = $r
        }
    }
    return $map
}

function script:Etme-FindResolvedLine {
    param(
        [hashtable]$PositionMap,
        [AllowEmptyCollection()][object[]]$ResolvedMatches,
        [string]$TourneeId,
        [int]$Position,
        [string]$ExcelWorkOrder
    )
    $k = "$TourneeId|$Position"
    if ($PositionMap.ContainsKey($k)) {
        return $PositionMap[$k]
    }
    $woN = Etme-NormalizeWo $ExcelWorkOrder
    if ($woN -eq '' -or $null -eq $ResolvedMatches) {
        return $null
    }
    foreach ($r in $ResolvedMatches) {
        if ($null -eq $r) { continue }
        if ($null -eq $r.PSObject.Properties['TourneeId']) { continue }
        if ([string]$r.TourneeId -ne $TourneeId) { continue }
        if ($null -eq $r.PSObject.Properties['WorkOrder']) { continue }
        $rw = Etme-NormalizeWo ([string]$r.WorkOrder)
        if ($rw -ne '' -and [string]::Equals($rw, $woN, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $r
        }
    }
    return $null
}

function script:Etme-GetExcelFieldsForStop {
    param(
        [object]$Stop,
        [object]$ResolvedLine
    )
    $excelWo = [string]$Stop.WorkOrder
    $excelCid = [string]$Stop.ClientId
    if ($null -ne $ResolvedLine -and $null -ne $ResolvedLine.PSObject.Properties['ExcelWorkOrder']) {
        $xw = [string]$ResolvedLine.ExcelWorkOrder
        if (-not [string]::IsNullOrWhiteSpace($xw)) {
            $excelWo = $xw
        }
    }
    if ($null -ne $ResolvedLine -and $null -ne $ResolvedLine.PSObject.Properties['ExcelClientId']) {
        $xc = $ResolvedLine.ExcelClientId
        if ($null -ne $xc) {
            $excelCid = [string]$xc
        }
    }
    return @{
        ExcelWorkOrder = $excelWo
        ExcelClientId  = $excelCid
    }
}

function script:Etme-BuildExcelRowFromStop {
    param(
        [object]$TourneeStop,
        [hashtable]$ExcelFields
    )
    return [pscustomobject]@{
        WorkOrder = $ExcelFields.ExcelWorkOrder
        ClientId  = $ExcelFields.ExcelClientId
        Position  = [int]$TourneeStop.Position
    }
}

function script:Etme-ResolveEntityFieldsWithPolicy {
    param(
        [object]$Entity,
        [object]$ExcelRow,
        [object]$Policy
    )
    $clientId = Resolve-FieldValue -PdfValue (Fre-GetPdfClientId -Entity $Entity) -ExcelValue (Fre-GetExcelClientId -Row $ExcelRow) -Priority $Policy.ClientIdPriority -FieldName 'ClientId'
    $workOrder = Resolve-FieldValue -PdfValue (Fre-GetPdfWorkOrder -Entity $Entity) -ExcelValue (Fre-GetExcelWorkOrder -Row $ExcelRow) -Priority $Policy.WorkOrderPriority -FieldName 'WorkOrder'
    $address = Resolve-FieldValue -PdfValue (Fre-GetPdfAddress -Entity $Entity) -ExcelValue (Fre-GetExcelAddress -Row $ExcelRow) -Priority $Policy.AddressPriority -FieldName 'Address'
    $date = Resolve-FieldValue -PdfValue (Fre-GetPdfDate -Entity $Entity) -ExcelValue (Fre-GetExcelDate -Row $ExcelRow) -Priority $Policy.DatePriority -FieldName 'Date'
    $clientName = Resolve-FieldValue -PdfValue (Fre-GetPdfClientName -Entity $Entity) -ExcelValue (Fre-GetExcelClientName -Row $ExcelRow) -Priority $Policy.ClientNamePriority -FieldName 'ClientName'
    return [pscustomobject]@{
        ClientId   = $clientId
        WorkOrder  = $workOrder
        Address    = $address
        Date       = $date
        ClientName = $clientName
    }
}

function script:Etme-NormalizeComparable {
    param(
        [string]$FieldName,
        [object]$Value
    )
    if ($null -eq $Value) { return '' }
    switch ($FieldName) {
        'Address' {
            return Fre-FormatAddressScalar -Raw $Value
        }
        'Date' {
            if ($Value -is [datetime]) {
                return $Value.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
            }
            return ([string]$Value).Trim()
        }
        Default {
            return ([string]$Value).Trim()
        }
    }
}

function script:Etme-GetAmbiguousFields {
    param(
        [object]$Entity,
        [object]$ExcelRow
    )
    $list = [System.Collections.Generic.List[string]]::new()
    $pairs = @(
        @{ N = 'ClientId'; P = { Fre-GetPdfClientId -Entity $Entity }; E = { Fre-GetExcelClientId -Row $ExcelRow } }
        @{ N = 'WorkOrder'; P = { Fre-GetPdfWorkOrder -Entity $Entity }; E = { Fre-GetExcelWorkOrder -Row $ExcelRow } }
        @{ N = 'Address'; P = { Fre-GetPdfAddress -Entity $Entity }; E = { Fre-GetExcelAddress -Row $ExcelRow } }
        @{ N = 'Date'; P = { Fre-GetPdfDate -Entity $Entity }; E = { Fre-GetExcelDate -Row $ExcelRow } }
        @{ N = 'ClientName'; P = { Fre-GetPdfClientName -Entity $Entity }; E = { Fre-GetExcelClientName -Row $ExcelRow } }
    )
    foreach ($p in $pairs) {
        $pv = & $p.P
        $ev = & $p.E
        if (-not (Fre-IsPresentValue $pv)) { continue }
        if (-not (Fre-IsPresentValue $ev)) { continue }
        $np = Etme-NormalizeComparable -FieldName $p.N -Value $pv
        $ne = Etme-NormalizeComparable -FieldName $p.N -Value $ev
        if (-not [string]::Equals($np, $ne, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$list.Add($p.N)
        }
    }
    return , @($list.ToArray())
}

function script:Etme-GetClientBlockId {
    param([object]$Entity)
    if ($null -eq $Entity) { return $null }
    if ($null -eq $Entity.PSObject.Properties['ClientBlockId']) { return $null }
    try {
        return [int]$Entity.ClientBlockId
    }
    catch {
        return $null
    }
}

function script:Etme-ComputeMergeStatus {
    param(
        [object]$Engine,
        [bool]$HasPdfEntity,
        [string]$DecisionStatus,
        [string[]]$AmbiguousFields
    )
    $ds = if ($null -eq $DecisionStatus) { '' } else { [string]$DecisionStatus }
    if ($AmbiguousFields.Count -gt 0) {
        return 'CONFLICT'
    }
    if ($ds -match 'CONFLICT') {
        return 'CONFLICT'
    }
    $cid = Etme-NormalizeComparable -FieldName 'ClientId' -Value $Engine.ClientId
    $wo = Etme-NormalizeComparable -FieldName 'WorkOrder' -Value $Engine.WorkOrder
    if ($cid -eq '' -and $wo -eq '' -and -not $HasPdfEntity) {
        return 'MISSING'
    }
    $addr = Etme-NormalizeComparable -FieldName 'Address' -Value $Engine.Address
    $dt = Etme-NormalizeComparable -FieldName 'Date' -Value $Engine.Date
    $cn = Etme-NormalizeComparable -FieldName 'ClientName' -Value $Engine.ClientName
    $allCore = ($cid -ne '' -and $wo -ne '' -and $addr -ne '' -and $dt -ne '' -and $cn -ne '')
    if ($allCore) {
        return 'MATCH'
    }
    return 'PARTIAL'
}

function Merge-EntityTournees {
    <#
    .SYNOPSIS
        Fusion unique Excel (structure / ordre) + PDF (ResolvedMatches / FinalEntity) + policy champs.

    .PARAMETER ExcelTournees
        Tournées Excel : vérité d’ordre (liste et Position des arrêts).

    .PARAMETER ResolvedMatches
        Décisions par arrêt : TourneeId + Position (clé principale) ; optionnellement WorkOrder pour repli de liaison.

    .PARAMETER FieldResolutionPolicy
        Optionnel : sinon Get-FieldResolutionPolicy.

    .PARAMETER HumanResolvedMatches
        Optionnel : décisions humaines (même forme que le store).
        Si le paramètre est **fourni** dans l'appel (y compris `-HumanResolvedMatches @()` ou `$null`),
        `$effectiveHumanResolvedMatches` = cette valeur seule : **aucune** lecture de HumanResolvedMatchesStore.
        Si le paramètre est **absent**, rejouer le journal via Rebuild-HumanResolvedState uniquement (aucune autre source).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$ExcelTournees,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$ResolvedMatches,

        [Parameter(Mandatory = $false)]
        [object]$FieldResolutionPolicy = $null,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$HumanResolvedMatches
    )

    $policy = if ($null -ne $FieldResolutionPolicy) { $FieldResolutionPolicy } else { Get-FieldResolutionPolicy }

    $effectiveHumanResolvedMatches = @()
    if ($PSBoundParameters.ContainsKey('HumanResolvedMatches')) {
        if ($null -eq $HumanResolvedMatches) {
            $effectiveHumanResolvedMatches = @()
        }
        else {
            $effectiveHumanResolvedMatches = @( foreach ($h in @($HumanResolvedMatches)) { if ($null -ne $h) { $h } } )
        }
    }
    else {
        $effectiveHumanResolvedMatches = @(Rebuild-HumanResolvedState)
    }

    $resolvedMatchesFinal = @(Merge-HumanAndPdfDecisions -ResolvedMatches $ResolvedMatches -HumanResolvedMatches $effectiveHumanResolvedMatches)

    $mergeResult = $null
    $global:Etme_MergeCallDepth = [int]$global:Etme_MergeCallDepth + 1
    $etmeMergeTelemetryOuterSession = ([int]$global:Etme_MergeCallDepth -eq 1)
    try {
        if ($etmeMergeTelemetryOuterSession) {
            try { Start-MergeTelemetry } catch { }
        }

        $posMap = Etme-BuildResolvedPositionMap -ResolvedMatches $resolvedMatchesFinal

        $outTournees = [System.Collections.Generic.List[object]]::new()
        $summary = @{
            TotalStops = 0
            MATCH      = 0
            PARTIAL    = 0
            MISSING    = 0
            CONFLICT   = 0
        }

        foreach ($excelTour in @($ExcelTournees)) {
        if ($null -eq $excelTour) { continue }

        try { MergeTelemetry-RecordTour } catch { }

        $tid = [string]$excelTour.TourneeId
        $td = $excelTour.TourDate
        if ($null -eq $td) { $td = [datetime]::MinValue }
        $agent = ''
        if ($null -ne $excelTour.PSObject.Properties['Agent']) {
            $agent = [string]$excelTour.Agent
        }

        $stopsOut = [System.Collections.Generic.List[object]]::new()
        $stopsOrdered = @($excelTour.Stops) | Sort-Object -Property @{ Expression = { [int]$_.Position }; Ascending = $true }

        foreach ($stop in $stopsOrdered) {
            if ($null -eq $stop) { continue }

            $pos = [int]$stop.Position
            $resolvedLine = Etme-FindResolvedLine -PositionMap $posMap -ResolvedMatches $resolvedMatchesFinal -TourneeId $tid -Position $pos -ExcelWorkOrder ([string]$stop.WorkOrder)

            $xl = Etme-GetExcelFieldsForStop -Stop $stop -ResolvedLine $resolvedLine
            $excelRow = Etme-BuildExcelRowFromStop -TourneeStop $stop -ExcelFields $xl

            $finalEnt = $null
            if ($null -ne $resolvedLine -and $null -ne $resolvedLine.PSObject.Properties['FinalEntity']) {
                $finalEnt = $resolvedLine.FinalEntity
            }

            $pdfEntity = $finalEnt

            $engine = Etme-ResolveEntityFieldsWithPolicy -Entity $pdfEntity -ExcelRow $excelRow -Policy $policy

            $ambiguous = Etme-GetAmbiguousFields -Entity $pdfEntity -ExcelRow $excelRow

            $decisionStatus = 'MISSING'
            if ($null -ne $resolvedLine -and $null -ne $resolvedLine.PSObject.Properties['OriginalStatus']) {
                $ov = [string]$resolvedLine.OriginalStatus
                if (-not [string]::IsNullOrWhiteSpace($ov)) {
                    $decisionStatus = $ov
                }
            }

            $rsrc = $null
            if ($null -ne $resolvedLine -and $null -ne $resolvedLine.PSObject.Properties['ResolutionSource']) {
                $rsrc = [string]$resolvedLine.ResolutionSource
            }

            $hasPdf = ($null -ne $finalEnt)
            $mergeStatus = Etme-ComputeMergeStatus -Engine $engine -HasPdfEntity $hasPdf -DecisionStatus $decisionStatus -AmbiguousFields $ambiguous

            $summary.TotalStops++
            $summary[$mergeStatus]++

            try { MergeTelemetry-RecordStop -MergeStatus $mergeStatus -DecisionStatus $decisionStatus } catch { }

            $wos = @()
            if ($null -ne $finalEnt -and $null -ne $finalEnt.PSObject.Properties['WorkOrders']) {
                $wos = @($finalEnt.WorkOrders)
            }

            $cb = Etme-GetClientBlockId -Entity $finalEnt

            [void]$stopsOut.Add([pscustomobject]@{
                Position             = $pos
                ExcelWorkOrder       = $xl.ExcelWorkOrder
                ExcelClientId        = $xl.ExcelClientId
                ClientId             = $engine.ClientId
                WorkOrder            = $engine.WorkOrder
                Address              = $engine.Address
                Date                 = $engine.Date
                ClientName           = $engine.ClientName
                WorkOrders           = $wos
                ClientBlockId        = $cb
                DecisionStatus       = $decisionStatus
                ResolutionSource     = $rsrc
                MergeStatus          = $mergeStatus
                AmbiguousFields      = @($ambiguous)
            })

            Write-Verbose ("Merge-EntityTournees: [{0}] pos={1} -> {2}" -f $tid, $pos, $mergeStatus)
        }

        [void]$outTournees.Add([pscustomobject]@{
            TourneeId = $tid
            TourDate  = $td
            Agent     = $agent
            Stops     = @($stopsOut.ToArray())
        })
    }

        $mergeResult = [pscustomobject]@{
            Tournees = @($outTournees.ToArray())
            Summary  = [pscustomobject]$summary
        }
    }
    finally {
        if ($etmeMergeTelemetryOuterSession) {
            try { Stop-MergeTelemetry } catch { }
        }
        $global:Etme_MergeCallDepth = [Math]::Max(0, [int]$global:Etme_MergeCallDepth - 1)
    }

    return $mergeResult
}

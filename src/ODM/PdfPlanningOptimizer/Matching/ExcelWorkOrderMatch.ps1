# ============================================================
# ExcelWorkOrderMatch.ps1
# Couche indépendante : score déterministe (0–100) WorkOrderEntity vs lignes Excel.
# Pas de fuzzy, pas de ML : égalités exactes uniquement. Pondération explicite (somme = 100).
# Aucune dépendance au pipeline PDF ; dot-source WorkOrderEntity + MatchResult.
# ============================================================

. (Join-Path $PSScriptRoot "..\Models\WorkOrderEntity.ps1")
. (Join-Path $PSScriptRoot "..\Models\MatchResult.ps1")

# Pondération explicite (déterministe, somme = 100)
$script:ExcelMatchWeightClientId = 40
$script:ExcelMatchWeightOdm = 35
$script:ExcelMatchWeightVisitDate = 25

function script:Get-ExcelRowPropertyValue {
    param(
        [object]$Row,
        [string[]]$PropertyNames
    )
    if ($null -eq $Row) { return $null }

    foreach ($name in $PropertyNames) {
        $val = $null
        if ($Row -is [hashtable]) {
            if ($Row.ContainsKey($name)) {
                $val = $Row[$name]
            }
        }
        else {
            $prop = $Row.PSObject.Properties[$name]
            if ($null -ne $prop) {
                $val = $prop.Value
            }
        }
        if ($null -ne $val -and '' -ne [string]$val) {
            return $val
        }
    }
    return $null
}

function script:Get-ExcelRowIdentifier {
    param(
        [object]$Row,
        [int]$FallbackIndex
    )
    $id = Get-ExcelRowPropertyValue -Row $Row -PropertyNames @(
        'ExcelRowId', 'RowId', 'Id', 'LineId', 'RowNumber', '__RowIndex'
    )
    if ($null -ne $id) {
        return $id
    }
    return $FallbackIndex
}

function script:Get-WorkOrderEntityOdmStrings {
    param([WorkOrderEntity]$Entity)
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if ($null -eq $Entity -or -not $Entity.Services) {
        return @($set)
    }
    foreach ($svc in $Entity.Services) {
        if ($null -eq $svc) { continue }
        $odm = $null
        if ($svc -is [hashtable]) {
            if ($svc.ContainsKey('ODM')) { $odm = $svc['ODM'] }
        }
        else {
            $p = $svc.PSObject.Properties['ODM']
            if ($null -ne $p) { $odm = $p.Value }
        }
        if ($null -eq $odm) { continue }
        $s = ([string]$odm).Trim()
        if ($s -ne '') {
            [void]$set.Add($s)
        }
    }
    return @($set)
}

function script:Get-ExcelRowOdmStrings {
    param([object]$Row)
    $raw = Get-ExcelRowPropertyValue -Row $Row -PropertyNames @('ODM', 'Odm', 'RefODM', 'ReferenceODM')
    if ($null -eq $raw) { return @() }
    if ($raw -is [System.Collections.IEnumerable] -and $raw -isnot [string]) {
        $list = [System.Collections.Generic.List[string]]::new()
        foreach ($x in $raw) {
            if ($null -eq $x) { continue }
            $t = ([string]$x).Trim()
            if ($t -ne '') { $list.Add($t) }
        }
        return @($list)
    }
    return @(([string]$raw).Trim())
}

function script:Test-ExactStringMatch {
    param([string]$A, [string]$B)
    if ([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)) {
        return $false
    }
    return ($A.Trim() -ceq $B.Trim())
}

function script:Get-WorkOrderEntityVisitDateOrNull {
    param([WorkOrderEntity]$Wo)
    if ($null -eq $Wo) { return $null }
    $v = $Wo.VisitDate
    if ($null -eq $v) { return $null }
    if ($v -is [datetime]) {
        return [datetime]$v
    }
    if ($v.GetType().FullName -eq 'System.Nullable`1[System.DateTime]') {
        if ($v.HasValue) { return $v.Value }
    }
    return $null
}

function script:Test-ExactVisitDateMatch {
    param(
        [datetime]$EntityVisit,
        [object]$ExcelVisitRaw
    )
    if ($null -eq $ExcelVisitRaw) { return $false }

    $excelDt = $null
    if ($ExcelVisitRaw -is [datetime]) {
        $excelDt = [datetime]$ExcelVisitRaw
    }
    else {
        $s = [string]$ExcelVisitRaw
        if ([string]::IsNullOrWhiteSpace($s)) { return $false }
        try {
            $excelDt = [datetime]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture)
        }
        catch {
            return $false
        }
    }

    $a = $EntityVisit
    # Égalité civile déterministe (composantes calendaires + heure ; ignore DateTimeKind).
    return (
        $a.Year -eq $excelDt.Year -and
        $a.Month -eq $excelDt.Month -and
        $a.Day -eq $excelDt.Day -and
        $a.Hour -eq $excelDt.Hour -and
        $a.Minute -eq $excelDt.Minute -and
        $a.Second -eq $excelDt.Second
    )
}

function script:Test-OdmExactMatchBetweenSets {
    param([string[]]$EntityOdms, [string[]]$ExcelOdms)
    foreach ($e in $EntityOdms) {
        foreach ($x in $ExcelOdms) {
            if ($e -ceq $x) { return $true }
        }
    }
    return $false
}

function script:New-MatchResult {
    param(
        [string]$WorkOrder,
        [object]$ExcelRowId,
        [int]$MatchScore,
        [string[]]$MatchedFields
    )
    $m = [MatchResult]::new()
    $m.WorkOrder = $WorkOrder
    $m.ExcelRowId = $ExcelRowId
    $m.MatchScore = $MatchScore
    $m.MatchedFields = @($MatchedFields)
    return $m
}

function Get-WorkOrderExcelMatchResults {
    <#
    .SYNOPSIS
    Compare chaque WorkOrderEntity à chaque ligne Excel et calcule un score déterministe (0–100).

    .DESCRIPTION
    Pondération fixe (somme 100) : ClientID 40, ODM 35, VisitDate 25.
    Correspondance uniquement par égalité stricte (chaînes sensibles à la casse ; dates par Ticks après parse invariant).

    .PARAMETER WorkOrderEntities
    Entités issues du PDF (ou autre source).

    .PARAMETER ExcelRows
    Objets ou hashtables ; champs reconnus (premier non vide) :
    - Identifiant : ExcelRowId, RowId, Id, LineId, RowNumber, __RowIndex ; sinon index 0-based.
    - ClientID : ClientID, ClientCode, CodeClient
    - ODM : ODM, Odm, RefODM, ReferenceODM (chaîne ou collection de chaînes)
    - Date : VisitDate, DateVisite, Date (aligné sur WorkOrderEntity.VisitDate)

    .PARAMETER MinimumScore
    Seuil minimal du score (0–100). Valeur -1 (défaut) = aucun filtre ; sinon exclut les paires dont le score est strictement inférieur.

    .PARAMETER BestMatchPerWorkOrderOnly
    Ne conserve, pour chaque WorkOrder (chaîne), que la ligne Excel au score maximal (ties : ExcelRowId croissant string).

    .OUTPUTS
    MatchResult[]
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [WorkOrderEntity[]]$WorkOrderEntities,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$ExcelRows,

        [Parameter(Mandatory = $false)]
        [ValidateRange(-1, 100)]
        [int]$MinimumScore = -1,

        [switch]$BestMatchPerWorkOrderOnly
    )

    $results = [System.Collections.Generic.List[MatchResult]]::new()

    $excelList = @($ExcelRows)
    $woList = @($WorkOrderEntities | Where-Object { $null -ne $_ })

    $excelIndex = 0
    foreach ($row in $excelList) {
        $excelRowId = Get-ExcelRowIdentifier -Row $row -FallbackIndex $excelIndex
        $excelClient = Get-ExcelRowPropertyValue -Row $row -PropertyNames @('ClientID', 'ClientCode', 'CodeClient')
        $excelVisitRaw = Get-ExcelRowPropertyValue -Row $row -PropertyNames @('VisitDate', 'DateVisite', 'Date')
        $excelOdms = @(Get-ExcelRowOdmStrings -Row $row)

        foreach ($wo in $woList) {
            $matched = [System.Collections.Generic.List[string]]::new()
            $score = 0

            $woKey = if ([string]::IsNullOrWhiteSpace($wo.WorkOrder)) { '' } else { $wo.WorkOrder.Trim() }

            if (-not [string]::IsNullOrWhiteSpace($wo.ClientID) -and $null -ne $excelClient) {
                if (Test-ExactStringMatch -A $wo.ClientID -B ([string]$excelClient)) {
                    $score += $script:ExcelMatchWeightClientId
                    $matched.Add('ClientID')
                }
            }

            $entityOdms = @(Get-WorkOrderEntityOdmStrings -Entity $wo)
            if ($entityOdms.Count -gt 0 -and $excelOdms.Count -gt 0) {
                if (Test-OdmExactMatchBetweenSets -EntityOdms $entityOdms -ExcelOdms $excelOdms) {
                    $score += $script:ExcelMatchWeightOdm
                    $matched.Add('ODM')
                }
            }

            $woVisitDt = Get-WorkOrderEntityVisitDateOrNull -Wo $wo
            if ($null -ne $woVisitDt -and (Test-ExactVisitDateMatch -EntityVisit $woVisitDt -ExcelVisitRaw $excelVisitRaw)) {
                $score += $script:ExcelMatchWeightVisitDate
                $matched.Add('VisitDate')
            }

            if ($MinimumScore -ge 0 -and $score -lt $MinimumScore) {
                continue
            }

            $results.Add((New-MatchResult -WorkOrder $woKey -ExcelRowId $excelRowId -MatchScore $score -MatchedFields @($matched)))
        }
        $excelIndex++
    }

    $arr = @($results.ToArray())

    if ($BestMatchPerWorkOrderOnly) {
        $grouped = $arr | Group-Object -Property WorkOrder
        $best = [System.Collections.Generic.List[MatchResult]]::new()
        foreach ($g in $grouped) {
            $top = @(
                $g.Group |
                    Sort-Object @{ Expression = { $_.MatchScore }; Descending = $true }, @{ Expression = { [string]$_.ExcelRowId }; Ascending = $true }
            ) | Select-Object -First 1
            if ($null -ne $top) {
                $best.Add($top)
            }
        }
        return @($best.ToArray())
    }

    return @($arr | Sort-Object WorkOrder, { -$_.MatchScore }, { [string]$_.ExcelRowId })
}

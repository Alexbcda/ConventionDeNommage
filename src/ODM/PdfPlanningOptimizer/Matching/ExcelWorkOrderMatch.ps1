# ============================================================
# ExcelWorkOrderMatch.ps1
# Matching robuste WorkOrderEntity ↔ lignes Excel :
# 1) ExactID prioritaire (score 100) ; chemin critique
# 2) Fallback fuzzy Nom+Adresse (score 70–95) uniquement sans match ID
# 3) ManualReview (score 0) si aucun candidat valide
# ============================================================

. (Join-Path $PSScriptRoot "..\Models\WorkOrderEntity.ps1")
. (Join-Path $PSScriptRoot "..\Models\MatchResult.ps1")
$_ss = Join-Path $PSScriptRoot '..\..\..\Common\SortSafe.ps1'
if (Test-Path -LiteralPath $_ss) { . $_ss }

$script:FuzzyAcceptThreshold = 75
$script:FuzzyNameWeight = 0.60
$script:FuzzyAddressWeight = 0.40
$script:TypeLeakLogged = $false

function script:Trace-TypeLeak {
    param(
        $Value,
        [string]$Name,
        [string]$Location
    )
    if ($env:CN_OBJECT_TRACE -notin @('1', 'true')) { return $Value }
    if ($script:TypeLeakLogged) { return $Value }
    if ($Value -is [System.Object[]]) {
        $script:TypeLeakLogged = $true
        $count = [int]@($Value).Count
        $first = if ($count -gt 0) { $Value[0] } else { $null }
        $stack = (Get-PSCallStack | Select-Object -First 20 | Out-String)
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log ("[TYPE-LEAK] Name={0} Location={1} Type={2} Count={3} First={4} Stack={5}" -f $Name, $Location, $Value.GetType().FullName, $count, $first, $stack) "ERROR" $null
            Write-Log ("[SORT-EXPR-LEAK] Location={0} KeyType={1} Type={2} Count={3}" -f $Location, $Name, $Value.GetType().FullName, $count) "ERROR" $null
        }
    }
    return $Value
}

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

function script:Get-EntityAddressComposite {
    param([WorkOrderEntity]$Entity)
    if ($null -eq $Entity) { return '' }
    if ($Entity.Address -is [hashtable]) {
        $parts = @(
            [string]$Entity.Address.Street
            [string]$Entity.Address.PostalCode
            [string]$Entity.Address.City
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        return ($parts -join ' ').Trim()
    }
    return ''
}

function script:Get-ExcelRowAddressComposite {
    param([object]$Row)
    $single = Get-ExcelRowPropertyValue -Row $Row -PropertyNames @('Address', 'Adresse')
    if ($null -ne $single -and -not [string]::IsNullOrWhiteSpace([string]$single)) {
        return ([string]$single).Trim()
    }
    $parts = @(
        Get-ExcelRowPropertyValue -Row $Row -PropertyNames @('Street', 'Rue', 'AddressStreet')
        Get-ExcelRowPropertyValue -Row $Row -PropertyNames @('PostalCode', 'CodePostal', 'Zip')
        Get-ExcelRowPropertyValue -Row $Row -PropertyNames @('City', 'Ville')
    ) | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) }
    return (@($parts | ForEach-Object { ([string]$_).Trim() }) -join ' ').Trim()
}

function script:Remove-Diacritics {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $normalized.ToCharArray()) {
        $cat = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($cat -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString().Normalize([Text.NormalizationForm]::FormC)
}

function script:Normalize-TextForSimilarity {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $v = Remove-Diacritics -Text $Value
    $v = $v.ToUpperInvariant()
    $v = [regex]::Replace($v, '[^A-Z0-9\s]', ' ')
    $v = [regex]::Replace($v, '\s+', ' ').Trim()
    return $v
}

function script:Get-LevenshteinDistance {
    param(
        [string]$A,
        [string]$B
    )
    if ($null -eq $A) { $A = '' }
    if ($null -eq $B) { $B = '' }
    $n = $A.Length
    $m = $B.Length
    if ($n -eq 0) { return $m }
    if ($m -eq 0) { return $n }
    $d = [int[,]]::new($n + 1, $m + 1)
    for ($i = 0; $i -le $n; $i++) { $d[$i, 0] = $i }
    for ($j = 0; $j -le $m; $j++) { $d[0, $j] = $j }
    for ($i = 1; $i -le $n; $i++) {
        for ($j = 1; $j -le $m; $j++) {
            $cost = if ($A[$i - 1] -eq $B[$j - 1]) { 0 } else { 1 }
            $d[$i, $j] = [Math]::Min(
                [Math]::Min($d[$i - 1, $j] + 1, $d[$i, $j - 1] + 1),
                $d[$i - 1, $j - 1] + $cost
            )
        }
    }
    return $d[$n, $m]
}

function script:Get-JaccardTokenScore {
    param(
        [string]$A,
        [string]$B
    )
    $ta = @((Normalize-TextForSimilarity -Value $A) -split '\s+' | Where-Object { $_ -ne '' })
    $tb = @((Normalize-TextForSimilarity -Value $B) -split '\s+' | Where-Object { $_ -ne '' })
    if ($ta.Count -eq 0 -or $tb.Count -eq 0) { return 0.0 }
    $sa = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $sb = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($t in $ta) { [void]$sa.Add($t) }
    foreach ($t in $tb) { [void]$sb.Add($t) }
    $inter = [System.Collections.Generic.HashSet[string]]::new($sa, [StringComparer]::Ordinal)
    $inter.IntersectWith($sb)
    $union = [System.Collections.Generic.HashSet[string]]::new($sa, [StringComparer]::Ordinal)
    $union.UnionWith($sb)
    if ($union.Count -eq 0) { return 0.0 }
    return ([double]$inter.Count / [double]$union.Count)
}

function Get-SimilarityScore {
    [CmdletBinding()]
    param(
        [string]$Left,
        [string]$Right
    )
    $a = Normalize-TextForSimilarity $Left
    $b = Normalize-TextForSimilarity $Right
    if ([string]::IsNullOrWhiteSpace($a) -or [string]::IsNullOrWhiteSpace($b)) { return 0 }
    $maxLen = [Math]::Max($a.Length, $b.Length)
    if ($maxLen -eq 0) { return 100 }
    $lev = Get-LevenshteinDistance -A $a -B $b
    $levScore = [Math]::Max(0.0, 1.0 - ($lev / [double]$maxLen))
    $jacScore = Get-JaccardTokenScore -A $a -B $b
    $combined = (0.7 * $levScore) + (0.3 * $jacScore)
    return [int][Math]::Round($combined * 100.0)
}

function script:Test-ExactClientIdMatch {
    param(
        [WorkOrderEntity]$Entity,
        [object]$ExcelRow
    )
    $excelClient = Get-ExcelRowPropertyValue -Row $ExcelRow -PropertyNames @('ClientID', 'ClientId', 'ClientCode', 'CodeClient')
    if ($null -eq $excelClient) { return $false }
    $a = ([string]$Entity.ClientID).Trim()
    $b = ([string]$excelClient).Trim()
    if ([string]::IsNullOrWhiteSpace($a) -or [string]::IsNullOrWhiteSpace($b)) { return $false }
    return [string]::Equals($a, $b, [System.StringComparison]::OrdinalIgnoreCase)
}

function script:Get-FuzzyWeightedScore {
    param(
        [WorkOrderEntity]$Entity,
        [object]$ExcelRow
    )
    $nameEntity = [string]$Entity.ClientName
    $nameExcel = [string](Get-ExcelRowPropertyValue -Row $ExcelRow -PropertyNames @('ClientName', 'NomClient', 'RaisonSociale', 'Client'))
    $addrEntity = Get-EntityAddressComposite -Entity $Entity
    $addrExcel = Get-ExcelRowAddressComposite -Row $ExcelRow

    $nameScore = Get-SimilarityScore -Left $nameEntity -Right $nameExcel
    $addrScore = Get-SimilarityScore -Left $addrEntity -Right $addrExcel
    $weighted = ($script:FuzzyNameWeight * $nameScore) + ($script:FuzzyAddressWeight * $addrScore)
    return [int][Math]::Round($weighted)
}

function script:Convert-FuzzyToMatchScore {
    param([int]$Similarity)
    if ($Similarity -lt $script:FuzzyAcceptThreshold) { return 0 }
    $clamped = [Math]::Min(100, [Math]::Max($script:FuzzyAcceptThreshold, $Similarity))
    # 75 -> 70 ; 100 -> 95
    return [int][Math]::Round(70 + (($clamped - $script:FuzzyAcceptThreshold) * (25.0 / (100 - $script:FuzzyAcceptThreshold))))
}

function script:New-MatchResult {
    param(
        [string]$WorkOrder,
        [object]$ExcelRowId,
        [int]$MatchScore,
        [string]$MatchReason,
        [string[]]$MatchedFields
    )
    $m = [MatchResult]::new()
    $m.WorkOrder = $WorkOrder
    $m.ExcelRowId = $ExcelRowId
    $m.MatchScore = $MatchScore
    $m.MatchReason = $MatchReason
    $m.MatchedFields = @($MatchedFields)
    return $m
}

function script:Get-SortedExcelRows {
    param([object[]]$ExcelRows)
    $rows = [System.Collections.Generic.List[object]]::new()
    $idx = 0
    foreach ($r in @($ExcelRows)) {
        $rid = Get-ExcelRowIdentifier -Row $r -FallbackIndex $idx
        [void]$rows.Add([pscustomobject]@{
            Row       = $r
            ExcelRowId = $rid
            SortKey   = [string]$rid
        })
        $idx++
    }
    return Sort-Safe -InputObject @($rows.ToArray()) -Property SortKey -KeyType String
}

function Get-WorkOrderExcelMatchResults {
    <#
    .SYNOPSIS
    Matching robuste avec priorité ExactID puis fallback fuzzy Nom+Adresse.

    .DESCRIPTION
    - Phase 1 (prioritaire): Exact ClientID -> score 100, MatchReason=ExactID.
    - Phase 2 (fallback): uniquement pour entités sans match ID, uniquement sur lignes Excel non utilisées,
      score fuzzy basé sur ClientName (60%) + Adresse (40%) avec seuil >= 75%.
      MatchScore converti en plage 70-95, MatchReason=FuzzyNameAddress.
    - Sinon: score 0, MatchReason=ManualReview.

    Chaque WorkOrderEntity et chaque ligne Excel sont consommés au plus une fois.
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
    $woList = @($WorkOrderEntities | Where-Object { $null -ne $_ })
    $sortedExcel = @(Get-SortedExcelRows -ExcelRows $ExcelRows)

    $usedExcel = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $matchedWo = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

    # Phase 1: ExactID (ultra prioritaire)
    foreach ($wo in $woList) {
        $woKey = if ([string]::IsNullOrWhiteSpace($wo.WorkOrder)) { '' } else { $wo.WorkOrder.Trim() }
        foreach ($er in $sortedExcel) {
            $excelKey = [string]$er.ExcelRowId
            if ($usedExcel.Contains($excelKey)) { continue }
            if (Test-ExactClientIdMatch -Entity $wo -ExcelRow $er.Row) {
                $mr = New-MatchResult -WorkOrder $woKey -ExcelRowId $er.ExcelRowId -MatchScore 100 -MatchReason 'ExactID' -MatchedFields @('ClientID')
                $results.Add($mr)
                [void]$usedExcel.Add($excelKey)
                [void]$matchedWo.Add($woKey)
                break
            }
        }
    }

    # Phase 2: Fuzzy fallback (uniquement sans match ID)
    foreach ($wo in $woList) {
        $woKey = if ([string]::IsNullOrWhiteSpace($wo.WorkOrder)) { '' } else { $wo.WorkOrder.Trim() }
        if ($matchedWo.Contains($woKey)) { continue }

        $bestExcel = $null
        $bestSimilarity = -1
        foreach ($er in $sortedExcel) {
            $excelKey = [string]$er.ExcelRowId
            if ($usedExcel.Contains($excelKey)) { continue }
            $sim = Get-FuzzyWeightedScore -Entity $wo -ExcelRow $er.Row
            if ($sim -gt $bestSimilarity) {
                $bestSimilarity = $sim
                $bestExcel = $er
            }
        }

        if ($null -eq $bestExcel) {
            $results.Add((New-MatchResult -WorkOrder $woKey -ExcelRowId $null -MatchScore 0 -MatchReason 'ManualReview' -MatchedFields @()))
            continue
        }

        $score = Convert-FuzzyToMatchScore -Similarity $bestSimilarity
        if ($score -gt 0) {
            $results.Add((New-MatchResult -WorkOrder $woKey -ExcelRowId $bestExcel.ExcelRowId -MatchScore $score -MatchReason 'FuzzyNameAddress' -MatchedFields @('ClientName', 'Address')))
            [void]$usedExcel.Add([string]$bestExcel.ExcelRowId)
            [void]$matchedWo.Add($woKey)
        }
        else {
            $results.Add((New-MatchResult -WorkOrder $woKey -ExcelRowId $null -MatchScore 0 -MatchReason 'ManualReview' -MatchedFields @()))
        }
    }

    $arr = @($results.ToArray())
    if ($MinimumScore -ge 0) {
        $arr = @($arr | Where-Object { $_.MatchScore -ge $MinimumScore })
    }
    if ($BestMatchPerWorkOrderOnly) {
        return @(
            $arr | Sort-Object `
                @{ Expression = { $k = (Get-SortSafeKeyString $_.WorkOrder); [void](script:Trace-TypeLeak -Value $k -Name "WorkOrder" -Location "ExcelWorkOrderMatch.Sort.WorkOrder"); $k } },
                @{ Expression = { $k = - (Get-SortSafeKeyInt $_.MatchScore); [void](script:Trace-TypeLeak -Value $k -Name "MatchScore" -Location "ExcelWorkOrderMatch.Sort.MatchScore"); $k }; Ascending = $true } |
            Group-Object { $g = (Get-SortSafeKeyString $_.WorkOrder); [void](script:Trace-TypeLeak -Value $g -Name "WorkOrder" -Location "ExcelWorkOrderMatch.Group.WorkOrder"); $g } | ForEach-Object { $_.Group[0] }
        )
    }
    return @(
        $arr | Sort-Object `
            @{ Expression = { $k = (Get-SortSafeKeyString $_.WorkOrder); [void](script:Trace-TypeLeak -Value $k -Name "WorkOrder" -Location "ExcelWorkOrderMatch.Sort.WorkOrder2"); $k } },
            @{ Expression = { $k = - (Get-SortSafeKeyInt $_.MatchScore); [void](script:Trace-TypeLeak -Value $k -Name "MatchScore" -Location "ExcelWorkOrderMatch.Sort.MatchScore2"); $k }; Ascending = $true },
            @{ Expression = { $k = (Get-SortSafeKeyString $_.ExcelRowId); [void](script:Trace-TypeLeak -Value $k -Name "ExcelOrder" -Location "ExcelWorkOrderMatch.Sort.ExcelRowId"); $k }; Ascending = $true }
    )
}

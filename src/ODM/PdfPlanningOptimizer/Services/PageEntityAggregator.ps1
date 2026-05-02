# ============================================================
# PageEntityAggregator.ps1
# Rôle : Transformer une liste de PageEntity en liste de WorkOrderEntity
#         Grouping : une seule source pour groupKey = état monotone currentWorkOrder (WO page → préfixe ODM → héritage).
#          __UNSPECIFIED__ uniquement avant le premier signal ; aucune lecture globale, aucun merge, aucune heuristique.
#          Fusion Client / Adresse / Services inchangée.
# Aucun Excel, matching, parsing PDF ni orchestration.
# ============================================================

. (Join-Path $PSScriptRoot "..\Models\PageEntity.ps1")
. (Join-Path $PSScriptRoot "..\Models\WorkOrderEntity.ps1")
$_sg = Join-Path $PSScriptRoot '..\..\..\Common\ScalarGuard.ps1'
if (Test-Path -LiteralPath $_sg) { . $_sg }
$_ss = Join-Path $PSScriptRoot '..\..\..\Common\SortSafe.ps1'
if (Test-Path -LiteralPath $_ss) { . $_ss }

# Clé interne unique lorsque aucun WorkOrder courant n'est connu (début de document sans signal).
$script:UnspecifiedInternalKey = '__UNSPECIFIED__'
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

function script:Test-IsNonEmptyString {
    param([string]$Value)
    return -not [string]::IsNullOrWhiteSpace($Value)
}

function script:Get-FirstNonEmptyString {
    param([string[]]$Candidates)
    foreach ($c in $Candidates) {
        if (Test-IsNonEmptyString $c) { return $c.Trim() }
    }
    return $null
}

# --- TRUTH : préfixe ODM depuis PageEntity (déjà matérialisé, aucune autre source) ---
function script:Get-OdmWorkOrderPrefixFromPage {
    param([PageEntity]$Page)
    if ($null -eq $Page -or -not $Page.Services) { return $null }

    $rxOdm = [regex]'^\s*(\d{7})-\d+\s*$'
    foreach ($svc in $Page.Services) {
        if ($null -eq $svc) { continue }
        $odm = $svc['ODM']
        if (-not (Test-IsNonEmptyString $odm)) { continue }
        $m = $rxOdm.Match([string]$odm.Trim())
        if ($m.Success) {
            return $m.Groups[1].Value
        }
        $parts = $odm.Trim() -split '-', 2
        if ($parts.Count -ge 1 -and (Test-IsNonEmptyString $parts[0])) {
            return $parts[0].Trim()
        }
    }

    return $null
}

function script:Test-IsSyntheticUnspecifiedKey {
    param([string]$Key)
    return (Test-IsNonEmptyString $Key) -and ($Key -eq $script:UnspecifiedInternalKey)
}

function script:Group-PagesBySequentialWorkOrder {
    <#
    PDF → pages triées → état monotone currentWorkOrder → groupKey (même valeur ou __UNSPECIFIED__).
    Une seule règle de décision pour la clé : la sortie de l'état après la page courante.

    Retourne un PSCustomObject :
      - Groups : hashtable ordonnée PageEntity[] par clé de groupe (comportement inchangé pour le grouping).
      - TracesPerGroupKey : traces d'assignation par clé (liste d'entrées PageNumber, SignalType, SignalValue, CurrentWorkOrderAfterStep).

    Verbose : journalise chaque transition (source WO / ODM / INHERIT).
    #>
    [CmdletBinding()]
    param([PageEntity[]]$PagesSorted)

    $groups = [ordered]@{}
    $tracesPerGroupKey = [ordered]@{}
    $currentWorkOrder = $null

    foreach ($page in $PagesSorted) {
        if ($null -eq $page) { continue }

        $signalType = $null
        $signalValue = $null

        if (Test-IsNonEmptyString $page.WorkOrder) {
            $signalType = 'WO'
            $signalValue = $page.WorkOrder.Trim()
            $currentWorkOrder = $signalValue
        }
        else {
            $prefix = Get-OdmWorkOrderPrefixFromPage -Page $page
            if (Test-IsNonEmptyString $prefix) {
                $signalType = 'ODM'
                $signalValue = $prefix
                $currentWorkOrder = $prefix
            }
            else {
                $signalType = 'INHERIT'
                $signalValue = $null
            }
            # Sinon (INHERIT) : ne pas modifier $currentWorkOrder (ne jamais repasser à $null après init).
        }
        Write-Host ("[TRACE-WO-BUILD] Page={0} WorkOrderDetected=""{1}""" -f $page.PageNumber, $(if (Test-IsNonEmptyString $currentWorkOrder) { $currentWorkOrder } else { '' }))

        $groupKey = if (Test-IsNonEmptyString $currentWorkOrder) {
            $currentWorkOrder
        }
        else {
            $script:UnspecifiedInternalKey
        }

        Write-Verbose (
            "PageEntityAggregator: Page {0} | signal={1} | signalValue='{2}' | currentWorkOrderAfter='{3}' | groupKey='{4}'" -f @(
                $page.PageNumber,
                $signalType,
                $(if ($null -eq $signalValue) { '' } else { $signalValue }),
                $(if ($null -eq $currentWorkOrder) { '' } else { $currentWorkOrder }),
                $groupKey
            )
        )

        if (-not $groups.Contains($groupKey)) {
            $groups[$groupKey] = [System.Collections.Generic.List[PageEntity]]::new()
            $tracesPerGroupKey[$groupKey] = [System.Collections.Generic.List[hashtable]]::new()
        }
        $groups[$groupKey].Add($page)
        [void]$tracesPerGroupKey[$groupKey].Add(@{
            PageNumber                 = $page.PageNumber
            SignalType                 = $signalType
            SignalValue                = $signalValue
            CurrentWorkOrderAfterStep  = $currentWorkOrder
        })
    }

    return [pscustomobject]@{
        Groups               = $groups
        TracesPerGroupKey    = $tracesPerGroupKey
    }
}

function script:Copy-HashtableShallow {
    param([hashtable]$Source)
    $h = @{}
    if ($null -eq $Source) { return $h }
    foreach ($k in $Source.Keys) {
        $h[$k] = $Source[$k]
    }
    return $h
}

function script:Copy-ServiceEntry {
    param([object]$Service)
    if ($null -eq $Service) { return $null }
    if ($Service -is [hashtable]) {
        return (Copy-HashtableShallow -Source $Service)
    }
    $h = @{}
    foreach ($p in $Service.PSObject.Properties) {
        $h[$p.Name] = $p.Value
    }
    return $h
}

function script:Merge-AddressFromPages {
    param([PageEntity[]]$PagesSorted)
    $out = @{
        Street     = $null
        PostalCode = $null
        City       = $null
    }
    $keys = @('Street', 'PostalCode', 'City')
    foreach ($p in $PagesSorted) {
        if ($null -eq $p -or $null -eq $p.Address) { continue }
        foreach ($k in $keys) {
            if ($null -ne $out[$k]) { continue }
            $v = $p.Address[$k]
            if (Test-IsNonEmptyString ([string]$v)) { $out[$k] = [string]$v }
        }
    }
    return $out
}

function script:Merge-ContactFromPages {
    param([PageEntity[]]$PagesSorted)
    $out = @{
        Name  = $null
        Email = $null
    }
    foreach ($p in $PagesSorted) {
        if ($null -eq $p -or $null -eq $p.Contact) { continue }
        foreach ($k in @('Name', 'Email')) {
            if ($null -ne $out[$k]) { continue }
            $v = $p.Contact[$k]
            if (Test-IsNonEmptyString ([string]$v)) { $out[$k] = [string]$v }
        }
    }
    return $out
}

function script:Merge-ServiceHashtableNonDestructive {
    param(
        [hashtable]$Target,
        [hashtable]$Supplement
    )
    if ($null -eq $Target -or $null -eq $Supplement) { return }

    foreach ($k in $Supplement.Keys) {
        $cur = $Target[$k]
        $inc = $Supplement[$k]
        $curEmpty = ($null -eq $cur) -or ((-not ($cur -is [datetime])) -and (-not (Test-IsNonEmptyString ([string]$cur))))
        $incHas = ($null -ne $inc) -and (($inc -is [datetime]) -or (Test-IsNonEmptyString ([string]$inc)))
        if ($curEmpty -and $incHas) {
            $Target[$k] = $inc
        }
    }
}

function script:Merge-ServicesDedupeByOdm {
    param([PageEntity[]]$PagesSorted)
    $order = [System.Collections.Generic.List[string]]::new()
    $byOdm = @{}
    $noOdm = [System.Collections.Generic.List[object]]::new()

    foreach ($p in $PagesSorted) {
        if ($null -eq $p -or -not $p.Services) { continue }
        foreach ($svc in $p.Services) {
            if ($null -eq $svc) { continue }
            $copy = Copy-ServiceEntry -Service $svc
            if ($null -eq $copy) { continue }

            $odmKey = $copy['ODM']
            if (-not (Test-IsNonEmptyString ([string]$odmKey))) {
                $noOdm.Add($copy)
                continue
            }

            $norm = $odmKey.Trim()
            if (-not $byOdm.ContainsKey($norm)) {
                $byOdm[$norm] = $copy
                $order.Add($norm)
            }
            else {
                Merge-ServiceHashtableNonDestructive -Target $byOdm[$norm] -Supplement $copy
            }
        }
    }

    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($k in $order) {
        $list.Add($byOdm[$k])
    }
    foreach ($x in $noOdm) {
        $list.Add($x)
    }

    return $list.ToArray()
}

function script:Test-AddressHasAnyValue {
    param([hashtable]$Address)
    if ($null -eq $Address) { return $false }
    foreach ($k in @('Street', 'PostalCode', 'City')) {
        $v = $Address[$k]
        if (Test-IsNonEmptyString ([string]$v)) { return $true }
    }
    return $false
}

function script:Get-SeedValuesFromPages {
    param([PageEntity[]]$PagesSorted)
    $seedClientId = $null
    $seedClientName = $null
    $seedAddress = @{ Street = $null; PostalCode = $null; City = $null }

    foreach ($p in @($PagesSorted)) {
        if ($null -eq $p) { continue }
        if (-not (Test-IsNonEmptyString $seedClientId) -and (Test-IsNonEmptyString $p.ClientID)) {
            $seedClientId = $p.ClientID.Trim()
        }
        if (-not (Test-IsNonEmptyString $seedClientName) -and (Test-IsNonEmptyString $p.ClientName)) {
            $seedClientName = $p.ClientName.Trim()
        }
        if (-not (Test-AddressHasAnyValue $seedAddress) -and (Test-AddressHasAnyValue $p.Address)) {
            foreach ($k in @('Street', 'PostalCode', 'City')) {
                $v = $p.Address[$k]
                if (Test-IsNonEmptyString ([string]$v)) {
                    $seedAddress[$k] = [string]$v
                }
            }
        }
        if ((Test-IsNonEmptyString $seedClientId) -and (Test-IsNonEmptyString $seedClientName) -and (Test-AddressHasAnyValue $seedAddress)) {
            break
        }
    }

    return [pscustomobject]@{
        ClientID   = $seedClientId
        ClientName = $seedClientName
        Address    = $seedAddress
    }
}

function script:Propagate-MissingPageFieldsInGroup {
    param(
        [PageEntity[]]$PagesSorted,
        [string]$WorkOrderKey
    )
    $seed = Get-SeedValuesFromPages -PagesSorted $PagesSorted
    foreach ($p in @($PagesSorted)) {
        if ($null -eq $p) { continue }

        if (-not (Test-IsNonEmptyString $p.ClientID) -and (Test-IsNonEmptyString $seed.ClientID)) {
            $p.ClientID = $seed.ClientID
            Write-Host "[WO-PROPAGATION] Page=$($p.PageNumber) → héritage ClientID=$($seed.ClientID)"
        }
        if (-not (Test-IsNonEmptyString $p.ClientName) -and (Test-IsNonEmptyString $seed.ClientName)) {
            $p.ClientName = $seed.ClientName
        }
        if ($null -eq $p.Address) {
            $p.Address = @{ Street = $null; PostalCode = $null; City = $null }
        }
        foreach ($k in @('Street', 'PostalCode', 'City')) {
            $cur = $p.Address[$k]
            if (-not (Test-IsNonEmptyString ([string]$cur)) -and (Test-IsNonEmptyString ([string]$seed.Address[$k]))) {
                $p.Address[$k] = [string]$seed.Address[$k]
            }
        }
        $woBefore = [string]$p.WorkOrder
        if (-not (Test-IsNonEmptyString $p.WorkOrder) -and (Test-IsNonEmptyString $WorkOrderKey) -and -not (Test-IsSyntheticUnspecifiedKey $WorkOrderKey)) {
            $p.WorkOrder = $WorkOrderKey
        }
        $woAfter = [string]$p.WorkOrder
        if ($woBefore -ne $woAfter) {
            Write-Host ("[TRACE-WO-PROPAGATION] Before=""{0}"" After=""{1}"" Page={2}" -f $woBefore, $woAfter, $p.PageNumber)
        }
    }
}

function script:Build-WorkOrderEntityFromGroup {
    param(
        [string]$InternalKey,
        [PageEntity[]]$PagesInGroup,
        $TraceEntries = $null
    )

    $sorted = Sort-Safe -InputObject @($PagesInGroup) -Property PageNumber
    $pageNumbers = [int[]](
        $sorted |
            ForEach-Object { (Get-SortSafeKeyInt $_.PageNumber) } |
            ForEach-Object {
                [void](script:Trace-TypeLeak -Value $_ -Name "PageNumber" -Location "PageEntityAggregator.Sort.PageNumbers")
                $_
            } |
            Sort-Object -Unique
    )

    $entity = [WorkOrderEntity]::new()

    $woFromPages = Get-FirstNonEmptyString @($sorted | ForEach-Object { $_.WorkOrder })
    if (Test-IsNonEmptyString $woFromPages) {
        $entity.WorkOrder = $woFromPages
    }
    elseif (-not (Test-IsSyntheticUnspecifiedKey $InternalKey)) {
        $entity.WorkOrder = $InternalKey
    }
    else {
        $entity.WorkOrder = $null
    }

    $entity.ClientID = Get-FirstNonEmptyString @($sorted | ForEach-Object { $_.ClientID })
    $entity.ClientName = Get-FirstNonEmptyString @($sorted | ForEach-Object { $_.ClientName })

    $entity.Address = Merge-AddressFromPages -PagesSorted $sorted
    $entity.Contact = Merge-ContactFromPages -PagesSorted $sorted

    foreach ($p in $sorted) {
        if ($null -eq $p) { continue }
        if ($null -ne $entity.VisitDate) { break }
        if ($null -ne $p.VisitDate) { $entity.VisitDate = $p.VisitDate }
    }

    $entity.Services = @(Merge-ServicesDedupeByOdm -PagesSorted $sorted)
    $entity.Pages = [int[]]@(
        $pageNumbers | ForEach-Object {
            ConvertTo-SafeInt -Value (Normalize-Scalar -Value $_ -Name 'WO.Pages') -Name 'WO.Pages'
        }
    )
    if ($entity.Pages -is [System.Object[]]) {
        Write-Log "WO.Pages still Object[] after normalization" "ERROR"
    }

    if ($null -ne $TraceEntries -and $TraceEntries.Count -gt 0) {
        $entity.Trace = @(
            $TraceEntries |
                Sort-Object {
                    $k = (Get-SortSafeKeyInt $($_['PageNumber']))
                    [void](script:Trace-TypeLeak -Value $k -Name "PageNumber" -Location "PageEntityAggregator.Sort.TraceEntries")
                    $k
                }
        )
    }

    return $entity
}

function script:Get-IntegrityNameSimilarityPercent {
    param(
        [string]$A,
        [string]$B
    )
    if ([string]::IsNullOrWhiteSpace($A) -or [string]::IsNullOrWhiteSpace($B)) { return 0 }

    $normalize = {
        param([string]$s)
        $v = $s.ToUpperInvariant().Trim()
        $v = [regex]::Replace($v, '[^A-Z0-9\s]', ' ')
        $v = [regex]::Replace($v, '\s+', ' ').Trim()
        return $v
    }

    $a0 = & $normalize $A
    $b0 = & $normalize $B
    if ([string]::IsNullOrWhiteSpace($a0) -or [string]::IsNullOrWhiteSpace($b0)) { return 0 }

    $n = $a0.Length
    $m = $b0.Length
    if ($n -eq 0 -and $m -eq 0) { return 100 }
    if ($n -eq 0 -or $m -eq 0) { return 0 }

    $d = [int[,]]::new($n + 1, $m + 1)
    for ($i = 0; $i -le $n; $i++) { $d[$i, 0] = $i }
    for ($j = 0; $j -le $m; $j++) { $d[0, $j] = $j }

    for ($i = 1; $i -le $n; $i++) {
        for ($j = 1; $j -le $m; $j++) {
            $cost = if ($a0[$i - 1] -eq $b0[$j - 1]) { 0 } else { 1 }
            $del = $d[$i - 1, $j] + 1
            $ins = $d[$i, $j - 1] + 1
            $sub = $d[$i - 1, $j - 1] + $cost
            $d[$i, $j] = [Math]::Min([Math]::Min($del, $ins), $sub)
        }
    }

    $dist = $d[$n, $m]
    $maxLen = [Math]::Max($n, $m)
    if ($maxLen -le 0) { return 100 }
    return [int][Math]::Round((1.0 - ([double]$dist / [double]$maxLen)) * 100.0)
}

function Test-WorkOrderGroupIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [WorkOrderEntity[]]$WorkOrders,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [PageEntity[]]$PageEntities
    )

    $byPage = @{}
    foreach ($p in @($PageEntities)) {
        if ($null -eq $p) { continue }
        $pn = [int](Get-SortSafeKeyInt $p.PageNumber)
        $byPage[$pn] = $p
    }

    $ok = 0
    $warn = 0
    $error = 0

    foreach ($wo in @($WorkOrders)) {
        if ($null -eq $wo) { continue }
        $woLabel = if (Test-IsNonEmptyString $wo.WorkOrder) { $wo.WorkOrder } else { '__UNSPECIFIED__' }
        $pages = @($wo.Pages | ForEach-Object { [int](Get-SortSafeKeyInt $_) })
        $pageCount = @($pages).Count

        $pageObjs = @()
        foreach ($pn in $pages) {
            if ($byPage.ContainsKey($pn)) { $pageObjs += $byPage[$pn] }
        }

        $errIssues = [System.Collections.Generic.List[string]]::new()
        $warnIssues = [System.Collections.Generic.List[string]]::new()

        $pageWorkOrders = @(
            $pageObjs |
                ForEach-Object { [string]$_.WorkOrder } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
        if ($pageWorkOrders.Count -gt 1) {
            [void]$errIssues.Add('INCONSISTENT_WORKORDER')
        }
        if (-not (Test-IsNonEmptyString $wo.WorkOrder)) {
            $missingWoPages = @($pageObjs | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.WorkOrder) })
            if ($missingWoPages.Count -gt 0) {
                [void]$errIssues.Add('MISSING_WORKORDER')
            }
        }

        $odmPrefixes = @(
            $pageObjs |
                ForEach-Object { Get-OdmWorkOrderPrefixFromPage -Page $_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
        if ((Test-IsNonEmptyString $wo.WorkOrder) -and $odmPrefixes.Count -gt 0) {
            foreach ($pref in $odmPrefixes) {
                if ([string]$pref -ne [string]$wo.WorkOrder) {
                    [void]$errIssues.Add('WORKORDER_ODM_MISMATCH')
                    break
                }
            }
        }

        $pageClientIds = @(
            $pageObjs |
                ForEach-Object { [string]$_.ClientID } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
        if ($pageClientIds.Count -eq 0) {
            [void]$errIssues.Add('MISSING_CLIENT_DATA')
        }
        elseif ($pageClientIds.Count -gt 1) {
            [void]$warnIssues.Add('INCONSISTENT_CLIENT')
        }

        $pageClientNames = @(
            $pageObjs |
                ForEach-Object { [string]$_.ClientName } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
        if ($pageClientNames.Count -eq 0) {
            if (-not $errIssues.Contains('MISSING_CLIENT_DATA')) {
                [void]$errIssues.Add('MISSING_CLIENT_DATA')
            }
        }
        elseif ($pageClientNames.Count -gt 1) {
            $isVeryDifferent = $false
            for ($i = 0; $i -lt $pageClientNames.Count; $i++) {
                for ($j = $i + 1; $j -lt $pageClientNames.Count; $j++) {
                    $sim = Get-IntegrityNameSimilarityPercent -A $pageClientNames[$i] -B $pageClientNames[$j]
                    if ($sim -lt 80) { $isVeryDifferent = $true; break }
                }
                if ($isVeryDifferent) { break }
            }
            if ($isVeryDifferent) {
                [void]$warnIssues.Add('INCONSISTENT_CLIENT')
            }
        }

        $cities = @(
            $pageObjs |
                ForEach-Object { if ($null -ne $_.Address) { [string]$_.Address['City'] } else { '' } } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
        if ($cities.Count -gt 1) {
            [void]$warnIssues.Add('INCONSISTENT_ADDRESS_CITY')
        }

        $postalCodes = @(
            $pageObjs |
                ForEach-Object { if ($null -ne $_.Address) { [string]$_.Address['PostalCode'] } else { '' } } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
        if ($postalCodes.Count -gt 1) {
            [void]$warnIssues.Add('INCONSISTENT_ADDRESS_POSTAL')
        }

        $errDistinct = @($errIssues.ToArray() | Sort-Object -Unique)
        $warnDistinct = @($warnIssues.ToArray() | Sort-Object -Unique)

        if ($errDistinct.Count -gt 0) {
            $wo | Add-Member -NotePropertyName QualityStatus -NotePropertyValue 'ERROR' -Force
            $wo | Add-Member -NotePropertyName QualityIssues -NotePropertyValue @($errDistinct) -Force
            foreach ($issue in $errDistinct) {
                Write-Host "[WO-ERROR] WorkOrder=$woLabel Issue=$issue Pages=$pageCount"
            }
            $error++
            continue
        }

        if ($warnDistinct.Count -gt 0) {
            $wo | Add-Member -NotePropertyName QualityStatus -NotePropertyValue 'WARN' -Force
            $wo | Add-Member -NotePropertyName QualityIssues -NotePropertyValue @($warnDistinct) -Force
            foreach ($issue in $warnDistinct) {
                Write-Host "[WO-WARN] WorkOrder=$woLabel Issue=$issue Pages=$pageCount"
            }
            $warn++
            continue
        }

        $wo | Add-Member -NotePropertyName QualityStatus -NotePropertyValue 'OK' -Force
        $wo | Add-Member -NotePropertyName QualityIssues -NotePropertyValue @() -Force
        Write-Host "[WO-VALID] WorkOrder=$woLabel Pages=$pageCount Status=OK"
        $ok++
    }

    $total = $ok + $warn + $error
    Write-Host "[WO-SUMMARY] TotalWorkOrders=$total"
    Write-Host "[WO-SUMMARY] OK=$ok"
    Write-Host "[WO-SUMMARY] WARN=$warn"
    Write-Host "[WO-SUMMARY] ERROR=$error"

    return [pscustomobject]@{
        TotalWorkOrders = $total
        OK              = $ok
        WARN            = $warn
        ERROR           = $error
    }
}

function ConvertTo-WorkOrderEntityList {
    <#
    .SYNOPSIS
    Regroupe des PageEntity par WorkOrder en parcours séquentiel (PageNumber croissant) :
    état monotone WorkOrder (groupKey = même source), puis WorkOrderEntity.

    .PARAMETER PageEntities
    Liste des pages déjà extraites (PageEntity).

    .OUTPUTS
    WorkOrderEntity[]
    Entités agrégées ; ordre des groupes = ordre croissant du premier numéro de page du groupe.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [PageEntity[]]$PageEntities
    )

    if ($null -eq $PageEntities -or $PageEntities.Count -eq 0) {
        return @()
    }

    $sortedPages = @(
        Sort-Safe -InputObject @(
            $PageEntities | Where-Object { $null -ne $_ }
        ) -Property PageNumber
    )
    $groupParams = @{ PagesSorted = $sortedPages }
    if ($PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Verbose')) {
        $groupParams['Verbose'] = $true
    }
    $groupingOutcome = Group-PagesBySequentialWorkOrder @groupParams
    $groups = $groupingOutcome.Groups

    $results = [System.Collections.Generic.List[WorkOrderEntity]]::new()
    foreach ($key in $groups.Keys) {
        $list = $groups[$key].ToArray()
        $workOrderLabel = if (Test-IsNonEmptyString $key) { $key } else { '' }
        Write-Host "[WO-GROUP] WorkOrder=$workOrderLabel regroupement pages=$(@($list).Count)"
        Write-Host ("[TRACE-WO-GROUP] WorkOrder={0} Pages={1}" -f $workOrderLabel, $(@($list).Count))
        Propagate-MissingPageFieldsInGroup -PagesSorted $list -WorkOrderKey $key
        $traceList = $groupingOutcome.TracesPerGroupKey[$key]
        $built = (Build-WorkOrderEntityFromGroup -InternalKey $key -PagesInGroup $list -TraceEntries $traceList)
        Write-Host ("[TRACE-WO-CLIENT] WorkOrder={0} ClientID={1}" -f $built.WorkOrder, $built.ClientID)
        if (([string]$built.ClientID).Trim() -eq '23778') {
            Write-Host ("[TRACE-WO] WorkOrder={0} ClientID={1}" -f $built.WorkOrder, $built.ClientID)
        }
        $results.Add($built)
        $woDone = if (Test-IsNonEmptyString $built.WorkOrder) { $built.WorkOrder } else { $workOrderLabel }
        Write-Host "[WO-COMPLETE] WorkOrder=$woDone Pages=$($built.Pages.Count)"
    }

    $ordered = @(
        $results.ToArray() |
            Sort-Object {
                $k = (Get-SafeMin -Values $_.Pages -Name "WO.SortMinPage")
                [void](script:Trace-TypeLeak -Value $k -Name "OrderIndex" -Location "PageEntityAggregator.Sort.WorkOrders")
                $k
            }
    )
    return $ordered
}

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

# Clé interne unique lorsque aucun WorkOrder courant n'est connu (début de document sans signal).
$script:UnspecifiedInternalKey = '__UNSPECIFIED__'

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

function script:Build-WorkOrderEntityFromGroup {
    param(
        [string]$InternalKey,
        [PageEntity[]]$PagesInGroup,
        $TraceEntries = $null
    )

    $sorted = @($PagesInGroup | Sort-Object -Property PageNumber)
    $pageNumbers = [int[]]($sorted | ForEach-Object { $_.PageNumber } | Sort-Object -Unique)

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
    $entity.Pages = $pageNumbers

    if ($null -ne $TraceEntries -and $TraceEntries.Count -gt 0) {
        $entity.Trace = @(
            $TraceEntries |
                Sort-Object { [int]($_['PageNumber']) }
        )
    }

    return $entity
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
        $PageEntities |
            Where-Object { $null -ne $_ } |
            Sort-Object -Property PageNumber
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
        $traceList = $groupingOutcome.TracesPerGroupKey[$key]
        $results.Add((Build-WorkOrderEntityFromGroup -InternalKey $key -PagesInGroup $list -TraceEntries $traceList))
    }

    $ordered = @($results.ToArray() | Sort-Object { ($_.Pages | Measure-Object -Minimum).Minimum })
    return $ordered
}

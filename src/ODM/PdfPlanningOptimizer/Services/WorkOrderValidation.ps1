# ============================================================
# WorkOrderValidation.ps1
# Rôle : Valider la cohérence des WorkOrderEntity après agrégation.
# Aucun Excel, matching, parsing PDF ; pas de modification des extracteurs.
# ============================================================

. (Join-Path $PSScriptRoot "..\Models\PageEntity.ps1")
. (Join-Path $PSScriptRoot "..\Models\WorkOrderEntity.ps1")
. (Join-Path $PSScriptRoot "..\Models\ValidationReport.ps1")

$script:RxOdmFormat = [regex]'^\d{7}-\d+$'

function script:Get-WorkOrderDisplayKey {
    param([WorkOrderEntity]$Wo)
    if ($null -eq $Wo) { return '(null entity)' }
    if (-not [string]::IsNullOrWhiteSpace($Wo.WorkOrder)) {
        return $Wo.WorkOrder.Trim()
    }
    $pages = if ($Wo.Pages) { ($Wo.Pages | Sort-Object) -join ',' } else { '' }
    return "(WorkOrder null; pages=$pages)"
}

function script:Add-Warning {
    param(
        [ValidationReport]$Report,
        [string]$Message,
        [switch]$Emit
    )
    $prior = if ($Report.Warnings) { @($Report.Warnings) } else { @() }
    $Report.Warnings = @($prior + @($Message))
    if ($Emit) {
        Write-Warning $Message
    }
}

function script:Resolve-MostFrequentDateOrdered {
    <#
    Plus fréquente ; en cas d'égalité, première date rencontrée dans l'ordre des pages.
    #>
    param([datetime[]]$DatesOrdered)
    if ($null -eq $DatesOrdered -or $DatesOrdered.Count -eq 0) { return $null }
    if ($DatesOrdered.Count -eq 1) { return $DatesOrdered[0] }

    $freq = @{}
    $firstIndex = @{}
    $i = 0
    foreach ($d in $DatesOrdered) {
        $key = $d.Ticks
        if (-not $freq.ContainsKey($key)) {
            $freq[$key] = 0
            $firstIndex[$key] = $i
        }
        $freq[$key]++
        $i++
    }

    $bestKey = $null
    $bestCount = -1
    $bestFirstIdx = [int]::MaxValue
    foreach ($key in $freq.Keys) {
        $c = [int]$freq[$key]
        $fi = [int]$firstIndex[$key]
        if ($c -gt $bestCount -or ($c -eq $bestCount -and $fi -lt $bestFirstIdx)) {
            $bestCount = $c
            $bestFirstIdx = $fi
            $bestKey = $key
        }
    }

    return [datetime]::new([long]$bestKey)
}

function Invoke-WorkOrderEntityValidation {
    <#
    .SYNOPSIS
    Contrôle la cohérence des WorkOrderEntity par rapport aux PageEntity sources.

    .PARAMETER WorkOrders
    Liste agrégée de WorkOrderEntity.

    .PARAMETER PageEntities
    Liste des PageEntity ayant servi à l’agrégation (référence des pages et dates par page).

    .PARAMETER EmitWarnings
    Si défini, émet chaque avertissement via Write-Warning.

    .OUTPUTS
    ValidationReport
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [WorkOrderEntity[]]$WorkOrders,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [PageEntity[]]$PageEntities,

        [switch]$EmitWarnings
    )

    $report = [ValidationReport]::new()
    $warn = {
        param([string]$msg)
        Add-Warning -Report $report -Message $msg -Emit:$EmitWarnings
    }

    $pageByNumber = @{}
    foreach ($p in $PageEntities) {
        if ($null -eq $p) { continue }
        $pageByNumber[$p.PageNumber] = $p
    }

    $expectedPages = @($pageByNumber.Keys | Sort-Object)
    $pageOwner = @{}
    $duplicateSet = @{}

    foreach ($wo in $WorkOrders) {
        if ($null -eq $wo) { continue }
        $woKey = Get-WorkOrderDisplayKey -Wo $wo
        if (-not $wo.Pages) { continue }

        $seenLocal = @{}
        foreach ($pn in $wo.Pages) {
            if ($seenLocal.ContainsKey($pn)) {
                $duplicateSet[[int]$pn] = $true
                & $warn "Page $pn dupliquée dans le même WorkOrder ($woKey)."
            }
            $seenLocal[$pn] = $true

            if ($pageOwner.ContainsKey($pn)) {
                $duplicateSet[[int]$pn] = $true
                & $warn "Page $pn assignée à plusieurs WorkOrders : '$($pageOwner[$pn])' et '$woKey'."
            }
            else {
                $pageOwner[$pn] = $woKey
            }
        }
    }

    foreach ($p in $expectedPages) {
        if (-not $pageOwner.ContainsKey($p)) {
            $existingMissing = if ($report.MissingPages) { @([int[]]$report.MissingPages) } else { @() }
            $list = [System.Collections.Generic.List[int]]::new()
            foreach ($x in $existingMissing) { $list.Add($x) }
            $list.Add([int]$p)
            $report.MissingPages = [int[]]@($list | Sort-Object -Unique)
            & $warn "Page manquante dans les WorkOrderEntity : $p."
        }
    }

    if ($duplicateSet.Count -gt 0) {
        $report.DuplicatePages = [int[]]@($duplicateSet.Keys | Sort-Object)
    }

    $nullWoKeys = @()
    foreach ($wo in $WorkOrders) {
        if ($null -eq $wo) { continue }
        if ([string]::IsNullOrWhiteSpace($wo.WorkOrder)) {
            $nullWoKeys += @(Get-WorkOrderDisplayKey -Wo $wo)
        }
    }

    if (@($nullWoKeys).Count -eq 1) {
        & $warn "WorkOrder null : cas isolé accepté ($($nullWoKeys[0]))."
    }
    elseif (@($nullWoKeys).Count -gt 1) {
        foreach ($k in @($nullWoKeys)) {
            & $warn "WorkOrder null (groupe) : $k."
        }
        & $warn "Plusieurs WorkOrderEntity sans numéro de commande ($(@($nullWoKeys).Count)) ; seul un cas isolé est attendu."
    }

    $invalidWoLookup = @{}
    foreach ($wo in $WorkOrders) {
        if ($null -eq $wo) { continue }
        $woKey = Get-WorkOrderDisplayKey -Wo $wo
        if (-not $wo.Services) { continue }

        foreach ($svc in $wo.Services) {
            if ($null -eq $svc) { continue }
            $odm = $svc['ODM']
            if ($null -eq $odm -or [string]::IsNullOrWhiteSpace([string]$odm)) {
                & $warn "Service sans ODM sous le WorkOrder '$woKey'."
                continue
            }
            $odmStr = [string]$odm.Trim()
            if (-not $script:RxOdmFormat.IsMatch($odmStr)) {
                $invalidWoLookup[$woKey] = $true
                & $warn "ODM invalide pour '$woKey' : '$odmStr' (attendu : 7 chiffres, tiret, chiffres)."
            }
        }
    }
    $report.InvalidWorkOrders = @($invalidWoLookup.Keys | Sort-Object)

    foreach ($wo in $WorkOrders) {
        if ($null -eq $wo -or -not $wo.Pages) { continue }
        $woKey = Get-WorkOrderDisplayKey -Wo $wo

        $dates = @()
        foreach ($pn in ($wo.Pages | Sort-Object)) {
            if (-not $pageByNumber.ContainsKey($pn)) { continue }
            $pe = $pageByNumber[$pn]
            if ($null -eq $pe.VisitDate) { continue }
            $dates += $pe.VisitDate.Value
        }

        if (@($dates).Count -le 1) { continue }

        $distinct = @($dates | Sort-Object -Unique)
        if ($distinct.Count -le 1) { continue }

        $chosen = Resolve-MostFrequentDateOrdered -DatesOrdered @([datetime[]]$dates)
        $detail = ($distinct | ForEach-Object { $_.ToString('dd/MM/yyyy') }) -join ', '
        & $warn "Dates de passage multiples pour '$woKey' : $detail. Règle appliquée : plus fréquente, sinon première chronologiquement ; retenue : $($chosen.ToString('dd/MM/yyyy'))."

        if ($null -ne $wo.VisitDate -and $wo.VisitDate.Value.Date -ne $chosen.Date) {
            & $warn "VisitDate agrégée ($($wo.VisitDate.Value.ToString('dd/MM/yyyy'))) diffère de la date retenue par pages ($($chosen.ToString('dd/MM/yyyy'))) pour '$woKey'."
        }
    }

    $hasStructuralIssue = (@($report.MissingPages).Count -gt 0) -or (@($report.DuplicatePages).Count -gt 0) -or (@($report.InvalidWorkOrders).Count -gt 0)
    $hasMultipleNullWo = (@($nullWoKeys).Count -gt 1)

    $report.IsValid = -not ($hasStructuralIssue -or $hasMultipleNullWo)

    return $report
}

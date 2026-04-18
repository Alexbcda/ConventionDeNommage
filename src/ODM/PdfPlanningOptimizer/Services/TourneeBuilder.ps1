# ============================================================
# TourneeBuilder.ps1
# Construction de tournées à partir de lignes Excel tabulaires.
# Aucun lien PDF ni matching — structuration uniquement.
# ============================================================

$_modelsDir = Join-Path $PSScriptRoot '..\Models'
if (-not (Test-Path -LiteralPath $_modelsDir)) {
    $_modelsDir = Join-Path $PSScriptRoot 'Models'
}
. (Join-Path $_modelsDir 'TourneeStop.ps1')
. (Join-Path $_modelsDir 'Tournee.ps1')

function script:Get-TourneeRowProperty {
    param(
        [object]$Row,
        [string[]]$Names
    )
    if ($null -eq $Row) { return $null }
    foreach ($name in $Names) {
        $val = $null
        if ($Row -is [hashtable]) {
            if ($Row.ContainsKey($name)) { $val = $Row[$name] }
        }
        else {
            $p = $Row.PSObject.Properties[$name]
            if ($null -ne $p) { $val = $p.Value }
        }
        if ($null -ne $val -and '' -ne ([string]$val).Trim()) {
            return $val
        }
    }
    return $null
}

function script:ConvertTo-TourneeDateTime {
    param([object]$Raw)
    if ($null -eq $Raw) { return [datetime]::MinValue }
    if ($Raw -is [datetime]) { return ([datetime]$Raw).Date }
    $s = ([string]$Raw).Trim()
    if ($s -eq '') { return [datetime]::MinValue }
    try {
        return ([datetime]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture)).Date
    }
    catch {
        return [datetime]::MinValue
    }
}

function script:Get-TourneeGroupKey {
    param(
        [object]$Row,
        [int]$RowIndex
    )
    $dRaw = Get-TourneeRowProperty -Row $Row -Names @(
        'VisitDate', 'TourDate', 'DatePassage', 'Date', 'DateVisite', 'Jour'
    )
    $tourDate = ConvertTo-TourneeDateTime -Raw $dRaw
    $datePart = if ($tourDate -eq [datetime]::MinValue) {
        '__DATE_UNKNOWN__'
    }
    else {
        $tourDate.ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
    }

    $agentRaw = Get-TourneeRowProperty -Row $Row -Names @(
        'Agent', 'Commercial', 'AgentName', 'Chauffeur', 'TourAgent', 'Responsable'
    )
    $agentPart = '__AGENT_UNKNOWN__'
    if ($null -ne $agentRaw) {
        $trimAgent = ([string]$agentRaw).Trim()
        if (-not [string]::IsNullOrWhiteSpace($trimAgent)) {
            $agentPart = $trimAgent
        }
    }

    return "$datePart|$agentPart"
}

function script:Get-TourneeStopPosition {
    param(
        [object]$Row,
        [int]$FallbackIndex
    )
    $p = Get-TourneeRowProperty -Row $Row -Names @(
        'Position', 'Rang', 'Ordre', 'StopOrder', 'NoOrdre', 'Sequence'
    )
    if ($null -ne $p) {
        $n = 0
        $sNum = ([string]$p).Trim()
        if ([int]::TryParse($sNum, [System.Globalization.NumberStyles]::Integer, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$n)) {
            return $n
        }
    }
    return $FallbackIndex + 1
}

function script:Get-TourneeWorkOrder {
    param([object]$Row)
    $v = Get-TourneeRowProperty -Row $Row -Names @(
        'WorkOrder', 'ODM', 'OrdreMission', 'NoODM', 'NumeroODM', 'Intervention'
    )
    if ($null -eq $v) { return '' }
    return ([string]$v).Trim()
}

function script:Get-TourneeClientId {
    param([object]$Row)
    $v = Get-TourneeRowProperty -Row $Row -Names @(
        'ClientId', 'ClientID', 'NoClient', 'N°Client', 'CodeClient', 'IdClient'
    )
    if ($null -eq $v) { return '' }
    return ([string]$v).Trim()
}

function script:New-TourneeId {
    param(
        [datetime]$TourDate,
        [string]$Agent
    )
    $d = if ($TourDate -eq [datetime]::MinValue) { 'NODATE' } else { $TourDate.ToString('yyyyMMdd') }
    $safe = [regex]::Replace([string]$Agent, '[^\w\-]+', '_')
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'AGENT' }
    return "${d}_$safe"
}

function Build-TourneesFromExcel {
    <#
    .SYNOPSIS
        Regroupe des lignes Excel par tournée (date de passage + agent) et produit des Tournee avec stops ordonnés.

    .PARAMETER ExcelRows
        Tableau de lignes (PSCustomObject ou hashtable) avec champs reconnus par alias (voir code).

    .OUTPUTS
        [Tournee[]] Tournées avec Stops triés par Position puis ordre d’apparition.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$ExcelRows
    )

    Write-Verbose "Build-TourneesFromExcel: début — $($ExcelRows.Count) ligne(s)."

    if ($null -eq $ExcelRows -or $ExcelRows.Count -eq 0) {
        Write-Verbose 'Build-TourneesFromExcel: aucune ligne — retour vide.'
        return @()
    }

    $wrapped = for ($i = 0; $i -lt $ExcelRows.Count; $i++) {
        [pscustomobject]@{
            Row   = $ExcelRows[$i]
            Index = $i
        }
    }

    $groups = $wrapped | Group-Object -Property {
        Get-TourneeGroupKey -Row $_.Row -RowIndex $_.Index
    }

    $list = [System.Collections.Generic.List[Tournee]]::new()

    foreach ($g in $groups) {
        $ordered = $g.Group | Sort-Object -Property @{
            Expression = { Get-TourneeStopPosition -Row $_.Row -FallbackIndex $_.Index }
            Ascending  = $true
        }, @{
            Expression = { $_.Index }
            Ascending  = $true
        }

        $first = $ordered[0].Row
        $dRaw = Get-TourneeRowProperty -Row $first -Names @(
            'VisitDate', 'TourDate', 'DatePassage', 'Date', 'DateVisite', 'Jour'
        )
        $tourDate = ConvertTo-TourneeDateTime -Raw $dRaw
        $agentRaw = Get-TourneeRowProperty -Row $first -Names @(
            'Agent', 'Commercial', 'AgentName', 'Chauffeur', 'TourAgent', 'Responsable'
        )
        $agent = if ($null -eq $agentRaw) { '' } else { ([string]$agentRaw).Trim() }

        $tid = New-TourneeId -TourDate $tourDate -Agent $agent

        $stops = [System.Collections.Generic.List[TourneeStop]]::new()
        foreach ($w in $ordered) {
            $pos = Get-TourneeStopPosition -Row $w.Row -FallbackIndex $w.Index
            $wo = Get-TourneeWorkOrder -Row $w.Row
            $cid = Get-TourneeClientId -Row $w.Row
            [void]$stops.Add([TourneeStop]::new($pos, $wo, $cid))
        }

        $t = [Tournee]::new()
        $t.TourneeId = $tid
        $t.TourDate = $tourDate
        $t.Agent = $agent
        $t.Stops = @($stops.ToArray())
        [void]$list.Add($t)

        Write-Verbose "Build-TourneesFromExcel: tournée $tid — $($t.Stops.Count) arrêt(s)."
    }

    $arr = @($list.ToArray()) | Sort-Object -Property TourneeId
    Write-Verbose "Build-TourneesFromExcel: fin — $($arr.Count) tournée(s)."
    return $arr
}

# --- Validation locale (exécution directe du script uniquement) ---
if ($MyInvocation.InvocationName -ne '.') {
    $sampleRows = @(
        [pscustomobject]@{
            VisitDate = '2026-04-23'
            Agent     = 'Dupont'
            Position  = 2
            WorkOrder = '1111111-22222222'
            ClientId  = 'C100'
        }
        [pscustomobject]@{
            VisitDate = '2026-04-23'
            Agent     = 'Dupont'
            Position  = 1
            WorkOrder = '1111111-33333333'
            ClientId  = 'C101'
        }
        [pscustomobject]@{
            VisitDate = '2026-04-24'
            Agent     = 'Martin'
            Position  = 1
            WorkOrder = '9999999-88888888'
            ClientId  = 'C200'
        }
    )

    Write-Host '=== TourneeBuilder — validation sur lignes fictives ===' -ForegroundColor Cyan
    $built = @(Build-TourneesFromExcel -ExcelRows $sampleRows -Verbose)
    Write-Host ("Tournées: {0}" -f $built.Count)
    foreach ($t in $built) {
        Write-Host ("- {0} | date={1:yyyy-MM-dd} agent=[{2}] stops={3}" -f $t.TourneeId, $t.TourDate, $t.Agent, $t.Stops.Count)
        foreach ($s in $t.Stops) {
            Write-Host ("    pos={0} WO={1} ClientId={2}" -f $s.Position, $s.WorkOrder, $s.ClientId)
        }
    }
    if ($built.Count -ne 2) { throw 'Validation TourneeBuilder: nombre de tournées attendu = 2.' }
    $t23 = @($built | Where-Object { $_.TourDate -eq [datetime]'2026-04-23' } | Select-Object -First 1)
    if ($t23.Stops[0].Position -ne 1 -or $t23.Stops[1].Position -ne 2) {
        throw 'Validation TourneeBuilder: ordre des stops incorrect.'
    }
    Write-Host '=== Validation OK ===' -ForegroundColor Green
}

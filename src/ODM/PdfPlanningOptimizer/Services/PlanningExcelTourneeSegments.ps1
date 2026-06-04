# Segments tournée (pages de garde) :
# - Colonne DATE : clients (regex identique Extract-ExcelOrder). Début de tournée = premier client après rupture (>=2 lignes DATE vides).
# - Collecteur / véhicule : colonne à gauche de DATE, lignes 1 et 2 au-dessus du premier client de la tournée.
# - Date affichée : première date reconnue au-dessus du bloc si présente, sinon FallbackVisitDate (pas de découpe par date seule).

function NormalizeText {
    <#
    .SYNOPSIS
        NFC ; remplacements UNIQUEMENT string -> string (œ/Œ, Ø/ø). Accents conserves.
    #>
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$TextIn
    )
    if ($null -eq $TextIn) { return '' }
    $t = ([string]$TextIn).Trim()
    $t = $t.Normalize([System.Text.NormalizationForm]::FormC)
    foreach ($pair in @(
            @("`u{00D8}", 'oe'), @("`u{00F8}", 'oe'), @('Ø', 'oe'), @('ø', 'oe'),
            @('œ', 'oe'), @('Œ', 'Oe')
        )) {
        $t = [string]::new($t).Replace([string]$pair[0], [string]$pair[1])
    }
    return [string]::new($t)
}

function Normalize-CnsCoverMetadataText {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )
    return (NormalizeText -TextIn $Text)
}

function Get-PlanningGridCellRaw {
    param(
        [Parameter(Mandatory = $true)] $Sheet,
        [Parameter(Mandatory = $true)] [int]$RowZeroBased,
        [Parameter(Mandatory = $true)] [int]$ColZeroBased,
        [Parameter(Mandatory = $true)] [int]$SheetColCount
    )
    if ($RowZeroBased -lt 0 -or $ColZeroBased -lt 0 -or $ColZeroBased -ge $SheetColCount) { return '' }
    $gr = $Sheet.Grid[$RowZeroBased]
    if ($null -eq $gr -or $ColZeroBased -ge @($gr).Count) { return '' }
    return [string]$gr[$ColZeroBased]
}

function Get-PlanningExcelDateCellJJMMAAAAOrNull {
    <#
    .SYNOPSIS
        Retourne JJ/MM/AAAA si la cellule contient une date reconnue ; sinon $null (pas de fallback).
    #>
    param([AllowNull()][AllowEmptyString()][string]$CellRaw)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $cell = NormalizeText -TextIn $CellRaw
    if ([string]::IsNullOrWhiteSpace($cell)) { return $null }

    foreach ($pattern in @('(\d{1,2})/(\d{1,2})/(\d{4})\b', '\b(\d{1,2})-(\d{1,2})-(\d{4})\b')) {
        $mx = [regex]::Match($cell, $pattern)
        if (-not ($mx.Success -and $mx.Groups.Count -ge 4)) { continue }
        try {
            $d = [int]::Parse([string]$mx.Groups[1].Value, $inv)
            $mo = [int]::Parse([string]$mx.Groups[2].Value, $inv)
            $y = [int]::Parse([string]$mx.Groups[3].Value, $inv)
            $dtUse = Get-Date -Year $y -Month $mo -Day $d -Hour 12 -Minute 0 -Second 0
            return $dtUse.ToString('dd/MM/yyyy', $inv)
        }
        catch { continue }
    }

    $mxIso = [regex]::Match($cell, '\b(\d{4})-(\d{2})-(\d{2})\b')
    if ($mxIso.Success) {
        try {
            $y = [int]$mxIso.Groups[1].Value
            $mo = [int]$mxIso.Groups[2].Value
            $d = [int]$mxIso.Groups[3].Value
            $dtIso = Get-Date -Year $y -Month $mo -Day $d -Hour 12 -Minute 0 -Second 0
            return $dtIso.ToString('dd/MM/yyyy', $inv)
        }
        catch { }
    }

    return $null
}

function Test-PlanningExcelDateColumnHasClientLine {
    <#
    .SYNOPSIS
        True si la cellule colonne DATE contient au moins une ligne client (id) — aligné sur Extract-ExcelOrder.
    #>
    param([AllowNull()][AllowEmptyString()][string]$CellRaw)
    $cell = NormalizeText -TextIn $CellRaw
    if ([string]::IsNullOrWhiteSpace($cell)) { return $false }
    foreach ($line in @($cell -split "`r`n|`n|`r")) {
        $ln = ([string]$line).Trim()
        if ($ln -match '^\((\d{4,6})\)\s*(.+)$') { return $true }
    }
    return $false
}

function Convert-CnsTourSegJJMMAAAAToDatetime {
    param([AllowNull()][AllowEmptyString()][string]$DisplayJM, [datetime]$FallbackVisit)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    [datetime]$t = $FallbackVisit.Date
    try {
        $m = [regex]::Match([string]$DisplayJM, '^(\d{1,2})/(\d{1,2})/(\d{4})$')
        if ($m.Success) {
            $dD = [int]::Parse([string]$m.Groups[1].Value, $inv)
            $dM = [int]::Parse([string]$m.Groups[2].Value, $inv)
            $dY = [int]::Parse([string]$m.Groups[3].Value, $inv)
            $t = Get-Date -Year $dY -Month $dM -Day $dD -Hour 12 -Minute 0 -Second 0
        }
    }
    catch { }
    return $t
}

function Add-CnsExcelTourneeFromClientWindow {
    param(
        $Sheet,
        [int]$FirstClientRowZ,
        [int]$LastClientRowZ,
        [int]$ColLeftMeta,
        [int]$ColZeroDate,
        [int]$StartZero,
        [int]$SheetColCount,
        [datetime]$FallbackVisitDate,
        [System.Collections.Generic.List[object]]$TourStarts
    )
    [int]$fcZ = $FirstClientRowZ
    [int]$lcZ = $LastClientRowZ
    [int]$cZ = $fcZ - 2
    [int]$vZ = $fcZ - 1
    [string]$rawCol = ''
    [string]$rawVeh = ''
    if ($cZ -ge $StartZero) {
        $rawCol = [string](Get-PlanningGridCellRaw -Sheet $Sheet -RowZeroBased $cZ -ColZeroBased $ColLeftMeta -SheetColCount $SheetColCount)
    }
    if ($vZ -ge $StartZero) {
        $rawVeh = [string](Get-PlanningGridCellRaw -Sheet $Sheet -RowZeroBased $vZ -ColZeroBased $ColLeftMeta -SheetColCount $SheetColCount)
    }
    [string]$collecteurNorm = NormalizeText -TextIn $rawCol
    [string]$vehiculeNorm = NormalizeText -TextIn $rawVeh
    $structOk = ($cZ -ge $StartZero) -and ($vZ -ge $StartZero) -and
        (-not [string]::IsNullOrWhiteSpace($collecteurNorm)) -and (-not [string]::IsNullOrWhiteSpace($vehiculeNorm))
    [string]$collecteur = $collecteurNorm
    if ([string]::IsNullOrWhiteSpace($collecteur)) { $collecteur = 'INCONNU' }
    [string]$vehicule = $vehiculeNorm
    if ([string]::IsNullOrWhiteSpace($vehicule)) { $vehicule = 'NON SPECIFIE' }

    [string]$dateDisp = ($FallbackVisitDate.Date.ToString('dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture))
    [datetime]$tourDate = $FallbackVisitDate.Date
    for ($u = $fcZ - 1; $u -ge $StartZero; $u--) {
        $up = Get-PlanningGridCellRaw -Sheet $Sheet -RowZeroBased $u -ColZeroBased $ColZeroDate -SheetColCount $SheetColCount
        $dj = Get-PlanningExcelDateCellJJMMAAAAOrNull -CellRaw $up
        if ($null -ne $dj) {
            $dateDisp = [string]$dj
            $tourDate = Convert-CnsTourSegJJMMAAAAToDatetime -DisplayJM $dateDisp -FallbackVisit $FallbackVisitDate
            break
        }
    }

    Write-Host ("[EXCEL-PARSE] Tour client L{0}-L{1} DateAff={2} Collecteur={3} Vehicule={4}" -f ($fcZ + 1), ($lcZ + 1), $dateDisp, $collecteur, $vehicule) -ForegroundColor Cyan
    [void]$TourStarts.Add([pscustomobject]@{
        FirstClientRowOneBased = [int]($fcZ + 1)
        LastClientRowOneBased  = [int]($lcZ + 1)
        DisplayDateJM          = [string]$dateDisp
        TourDate               = $tourDate
        Collecteur             = $collecteur
        Vehicule               = $vehicule
        TourneeComplete        = [bool]$structOk
    })
}

function Get-CnsPlanningWorkOrderKeyFromMatchWorkOrderField {
    <#
    .SYNOPSIS
        Cle WorkOrder normalisee depuis un champ .WorkOrder de ligne de match (entite ou chaine).
    #>
    param([AllowNull()] $WorkOrderField)
    if ($null -eq $WorkOrderField) { return $null }
    if ($WorkOrderField -is [string]) {
        $s = [string]$WorkOrderField
        if ([string]::IsNullOrWhiteSpace($s)) { return $null }
        return $s.Trim()
    }
    try {
        $s2 = [string]$WorkOrderField.WorkOrder
        if ([string]::IsNullOrWhiteSpace($s2)) { return $null }
        return $s2.Trim()
    }
    catch { return $null }
}

function Get-CnsWorkOrderBaseIdFromToken {
    <#
    .SYNOPSIS
        Identifiant WorkOrder (partie avant le tiret ODM) : 7 chiffres, ex. 5517128 depuis 5517128-19811636.
    #>
    param([AllowNull()][AllowEmptyString()][string]$Token)
    if ([string]::IsNullOrWhiteSpace($Token)) { return $null }
    $t = ([string]$Token).Trim()
    if ($t -match '(?i)^(\d{7})') { return $Matches[1] }
    if ($t -match '(?i)(\d{7})') { return $Matches[1] }
    return $null
}

function Get-CnsWorkOrderBaseIdFromEntity {
    param([AllowNull()] $WorkOrderEntity)
    if ($null -eq $WorkOrderEntity) { return $null }
    try {
        $b = Get-CnsWorkOrderBaseIdFromToken -Token ([string]$WorkOrderEntity.WorkOrder)
        if (-not [string]::IsNullOrWhiteSpace($b)) { return $b }
    }
    catch { }
    foreach ($service in @($WorkOrderEntity.Services)) {
        if ($null -eq $service) { continue }
        try {
            $b2 = Get-CnsWorkOrderBaseIdFromToken -Token ([string]$service.ODM)
            if (-not [string]::IsNullOrWhiteSpace($b2)) { return $b2 }
        }
        catch { }
    }
    return $null
}

function Test-CnsServiceTypeIsDestructionPrestationLine {
    <#
    .SYNOPSIS
        Bloc prestation DESTRUCTION PDF : "Destruction de ..." ou "Destruction confidentielle de ..." (pas le seul mot destruction).
    #>
    param([AllowNull()][AllowEmptyString()][string]$Type)
    if ([string]::IsNullOrWhiteSpace($Type)) { return $false }
    $t = ([string]$Type).Trim()
    if ($t -match '(?i)^Destruction(\s+confidentielle)?\s+de\b') { return $true }
    if ($t -match '(?i)^Destruction\s+confidentielle\b') { return $true }
    return $false
}

function Test-CnsWorkOrderRequiresDestructionCertificate {
    <#
    .SYNOPSIS
        Certificat : ligne prestation Destruction + ODM partageant le meme WorkOrderId (7 chiffres avant tiret).
    #>
    param([AllowNull()] $WorkOrderEntity)
    if ($null -eq $WorkOrderEntity) { return $false }
    [string]$baseId = Get-CnsWorkOrderBaseIdFromEntity -WorkOrderEntity $WorkOrderEntity
    if ([string]::IsNullOrWhiteSpace($baseId)) { return $false }
    foreach ($service in @($WorkOrderEntity.Services)) {
        if ($null -eq $service) { continue }
        [string]$type = ''
        [string]$odm = ''
        try { $type = [string]$service.Type } catch { }
        try { $odm = [string]$service.ODM } catch { }
        if (-not (Test-CnsServiceTypeIsDestructionPrestationLine -Type $type)) { continue }
        [string]$odmBase = Get-CnsWorkOrderBaseIdFromToken -Token $odm
        if ($odmBase -eq $baseId) { return $true }
    }
    return $false
}

function Test-CnsServiceTextIndicatesDestruction {
    <#
    .SYNOPSIS
        Alias historique : regle stricte certificat (bloc Destruction + WorkOrderId).
    #>
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ($null -eq $Text -or [string]::IsNullOrWhiteSpace($Text)) { return $false }
    return (Test-CnsServiceTypeIsDestructionPrestationLine -Type $Text)
}

function Test-CnsWorkOrderIndicatesDestructionPrestation {
    <#
    .SYNOPSIS
        True si le WO a une prestation Destruction liee par WorkOrderId (regle certificat STEP 5).
    #>
    param([AllowNull()] $WorkOrderEntity)
    return (Test-CnsWorkOrderRequiresDestructionCertificate -WorkOrderEntity $WorkOrderEntity)
}

function Get-CnsPlanningTourneeSpecialFlagsFromWorkOrder {
    <#
    .SYNOPSIS
        Prestations speciales visibles sur la page de garde tournée (services agrégés WorkOrderEntity).
    #>
    param([AllowNull()] $WorkOrderEntity)
    if ($null -eq $WorkOrderEntity) { return @() }
    [string]$client = ''
    try {
        $cn = $WorkOrderEntity.ClientName
        if ($null -ne $cn) { $client = [string]$cn }
    }
    catch { }
    [string]$baseId = Get-CnsWorkOrderBaseIdFromEntity -WorkOrderEntity $WorkOrderEntity
    $buf = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($service in @($WorkOrderEntity.Services)) {
        if ($null -eq $service) { continue }
        [string]$type = ''
        [string]$odm = ''
        try { $type = [string]$service.Type } catch { }
        try { $odm = [string]$service.ODM } catch { }
        if ((Test-CnsServiceTypeIsDestructionPrestationLine -Type $type) -and
            (-not [string]::IsNullOrWhiteSpace($baseId)) -and
            ((Get-CnsWorkOrderBaseIdFromToken -Token $odm) -eq $baseId)) {
            [void]$buf.Add(@{ Type = 'Destruction confidentielle'; Client = $client })
        }
        if ($type -like '*pile*') {
            [void]$buf.Add(@{ Type = 'Piles'; Client = $client })
        }
        if ($type -like '*DEEE*') {
            [void]$buf.Add(@{ Type = 'DEEE'; Client = $client })
        }
        if (($type -like '*tube*') -or ($type -like '*néon*') -or ($type -like '*neon*')) {
            [void]$buf.Add(@{ Type = 'Néon'; Client = $client })
        }
    }
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $dedup = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($h in $buf) {
        $pair = ('{0}|{1}' -f [string]$h.Type, [string]$h.Client)
        if ($seen.Add($pair)) { [void]$dedup.Add($h) }
    }
    return @($dedup.ToArray())
}

function Get-CnsTourneePrimaryTextFromExcelOrderSlot {
    <#
    .SYNOPSIS
        Texte affichable pour une ligne Excel d'ordre (Label ou premiere ligne RawLines) — collecteur / vehicule par rang dans la tournee.
    #>
    param($OrderSlot)
    if ($null -eq $OrderSlot) { return $null }
    try {
        $lab = [string]$OrderSlot.Label
        if (-not [string]::IsNullOrWhiteSpace($lab)) { return (NormalizeText -TextIn $lab) }
    }
    catch { }
    try {
        $rl = @($OrderSlot.RawLines)
        if ($rl.Count -gt 0) {
            $first = [string]$rl[0]
            if (-not [string]::IsNullOrWhiteSpace($first)) { return (NormalizeText -TextIn $first) }
        }
    }
    catch { }
    return $null
}

function Get-PlanningExcelDateColumnInfo {
    <#
    .SYNOPSIS
        Colonne date (planning) : index 1-based + 0-based + ligne de départ lecture.
    #>
    param(
        [Parameter(Mandatory = $true)] $ColumnInfo,
        [Parameter(Mandatory = $true)] [int]$SheetColCount
    )
    $col1 = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $ColumnInfo.ColumnIndex -Name 'TourSeg.Date.Col1') -Name 'TourSeg.Date.Col1.Int')
    $startZero = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $ColumnInfo.HeaderRow -Name 'TourSeg.Header.Zero') -Name 'TourSeg.Header.Zero.Int')
    $dateZero = (Safe-Subtract -Left $col1 -Right 1 -Context 'TourSeg.dateZero')
    $collectZero = (Safe-Subtract -Left $col1 -Right 2 -Context 'TourSeg.collectZero')
    if ($collectZero -lt 0 -or $collectZero -ge $SheetColCount) {
        [int]$collectZero = -1
    }
    if ($null -ne $ColumnInfo.PSObject.Properties['CollectorColumnIndex']) {
        try {
            $c1x = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $ColumnInfo.CollectorColumnIndex -Name 'TourSeg.Collector.Override1') -Name 'TourSeg.Collector.Override1.Int')
            $czx = (Safe-Subtract -Left $c1x -Right 1 -Context 'TourSeg.collectZeroOverride')
            if ($czx -ge 0 -and $czx -lt $SheetColCount) { [int]$collectZero = $czx }
        }
        catch { }
    }
    [int]$vehicleZero = [int]$dateZero
    if ($null -ne $ColumnInfo.PSObject.Properties['VehicleColumnIndex']) {
        try {
            $v1 = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $ColumnInfo.VehicleColumnIndex -Name 'TourSeg.Vehicle.Col1') -Name 'TourSeg.Vehicle.Col1.Int')
            $vz = (Safe-Subtract -Left $v1 -Right 1 -Context 'TourSeg.vehicleZero')
            if ($vz -ge 0 -and $vz -lt $SheetColCount) { $vehicleZero = $vz }
        }
        catch { }
    }
    elseif ($null -ne $ColumnInfo.PSObject.Properties['VehicleColumnZeroBased']) {
        try {
            $vzb = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $ColumnInfo.VehicleColumnZeroBased -Name 'TourSeg.Vehicle.Zero') -Name 'TourSeg.Vehicle.Zero.Int')
            if ($vzb -ge 0 -and $vzb -lt $SheetColCount) { $vehicleZero = $vzb }
        }
        catch { }
    }
    return [pscustomobject]@{
        DateColumnIndexOneBased     = [int]$col1
        DateColumnZeroBased         = [int]$dateZero
        CollectorColumnZeroBased    = [int]$collectZero
        VehicleColumnZeroBased      = [int]$vehicleZero
        HeaderRowZeroBasedStartRead = [int]$startZero
    }
}

function Get-PlanningExcelTourneeCoverSegments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] $ExcelData,
        [Parameter(Mandatory = $true)] $ColumnInfo,
        [Parameter(Mandatory = $true)] [datetime]$FallbackVisitDate,
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [object[]]$ExcelOrder,
        [hashtable]$OrderToWorkOrder = $null
    )

    $sheet = @($ExcelData.Sheets | Where-Object { $_.Name -eq $ColumnInfo.SheetName })[0]
    if ($null -eq $sheet) { return @() }

    $sheetRowCount = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $sheet.RowCount -Name "TourneeSeg.sheet.RowCount") -Name "TourneeSeg.sheet.RowCount")
    $sheetColCount = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $sheet.ColCount -Name "TourneeSeg.sheet.ColCount") -Name "TourneeSeg.sheet.ColCount")

    $zc = Get-PlanningExcelDateColumnInfo -ColumnInfo $ColumnInfo -SheetColCount $sheetColCount
    [int]$colZeroDate = $zc.DateColumnZeroBased
    [int]$colZeroCollector = [int]$zc.CollectorColumnZeroBased
    if ($colZeroCollector -lt 0 -or $colZeroCollector -ge $sheetColCount) {
        $colZeroCollector = $colZeroDate
    }
    [int]$colZeroVehicle = [int]$zc.VehicleColumnZeroBased
    if ($colZeroVehicle -lt 0 -or $colZeroVehicle -ge $sheetColCount) {
        $colZeroVehicle = $colZeroDate
    }
    [int]$colLeftMeta = $colZeroCollector
    [int]$startZero = $zc.HeaderRowZeroBasedStartRead
    $maxZ = [int]$sheetRowCount - 1
    if ($maxZ -lt $startZero) { $maxZ = $startZero }

    [int]$ruptureEmptyRows = 2
    $tourStarts = [System.Collections.Generic.List[object]]::new()
    $state = 'IDLE'
    [int]$emptyStreak = 0
    [int]$curFirstClientZ = -1
    [int]$curLastClientZ = -1

    for ($r = [int]$startZero; $r -le [int]$maxZ; $r++) {
        $dateCell = Get-PlanningGridCellRaw -Sheet $sheet -RowZeroBased $r -ColZeroBased $colZeroDate -SheetColCount $sheetColCount
        $trimDate = (NormalizeText -TextIn $dateCell).Trim()
        $isEmpty = [string]::IsNullOrWhiteSpace($trimDate)
        $isClient = if (-not $isEmpty) { Test-PlanningExcelDateColumnHasClientLine -CellRaw $dateCell } else { $false }

        if ($state -eq 'IDLE') {
            if ($isEmpty) { continue }
            if (-not $isClient) { continue }
            $state = 'IN_TOUR'
            $curFirstClientZ = $r
            $curLastClientZ = $r
            $emptyStreak = 0
            continue
        }

        if ($isClient) {
            $curLastClientZ = $r
            $emptyStreak = 0
            continue
        }
        if ($isEmpty) {
            $emptyStreak++
            if ($emptyStreak -ge $ruptureEmptyRows) {
                if ($state -eq 'IN_TOUR' -and $curFirstClientZ -ge 0) {
                    Add-CnsExcelTourneeFromClientWindow -Sheet $sheet -FirstClientRowZ $curFirstClientZ -LastClientRowZ $curLastClientZ `
                        -ColLeftMeta $colLeftMeta -ColZeroDate $colZeroDate -StartZero $startZero -SheetColCount $sheetColCount `
                        -FallbackVisitDate $FallbackVisitDate -TourStarts $tourStarts
                }
                $state = 'IDLE'
                $curFirstClientZ = -1
                $curLastClientZ = -1
                $emptyStreak = 0
            }
            continue
        }
        $emptyStreak = 0
    }
    if ($state -eq 'IN_TOUR' -and $curFirstClientZ -ge 0) {
        Add-CnsExcelTourneeFromClientWindow -Sheet $sheet -FirstClientRowZ $curFirstClientZ -LastClientRowZ $curLastClientZ `
            -ColLeftMeta $colLeftMeta -ColZeroDate $colZeroDate -StartZero $startZero -SheetColCount $sheetColCount `
            -FallbackVisitDate $FallbackVisitDate -TourStarts $tourStarts
    }

    $segments = New-Object System.Collections.Generic.List[object]
    $cap = $tourStarts.Count

    for ($ti = 0; $ti -lt $cap; $ti++) {
        $ts = $tourStarts[$ti]
        [int]$lo1 = [int]$ts.FirstClientRowOneBased
        [int]$hi1 = [int]$ts.LastClientRowOneBased

        $orderIdx = [System.Collections.Generic.HashSet[int]]::new()
        foreach ($ex in @($ExcelOrder)) {
            if ($null -eq $ex) { continue }
            try { [int]$oi = [int]$ex.OrderIndex } catch { continue }
            try { [int]$er = [int]$ex.ExcelRow } catch { continue }
            if ($er -ge $lo1 -and $er -le $hi1) {
                [void]$orderIdx.Add($oi)
            }
        }

        $orderList = @($orderIdx | Sort-Object)
        if ($orderList.Count -eq 0 -and @($ExcelOrder).Count -gt 0) {
            foreach ($ex in @($ExcelOrder)) {
                if ($null -eq $ex) { continue }
                try {
                    [int]$er = [int]$ex.ExcelRow
                    if ($er -ge $lo1 -and $er -le $hi1) {
                        [void]$orderIdx.Add([int]$ex.OrderIndex)
                    }
                }
                catch { }
            }
            $orderList = @($orderIdx | Sort-Object)
        }
        if ($orderList.Count -eq 0 -and $cap -eq 1 -and @($ExcelOrder).Count -gt 0) {
            foreach ($ex in @($ExcelOrder)) {
                if ($null -eq $ex) { continue }
                try { [void]$orderIdx.Add([int]$ex.OrderIndex) } catch { }
            }
            $orderList = @($orderIdx | Sort-Object)
        }

        [string]$collecteurSeg = [string]$ts.Collecteur
        [string]$vehiculeSeg = [string]$ts.Vehicule

        $specialAgg = [System.Collections.Generic.List[hashtable]]::new()
        $specialSeen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        if ($null -ne $OrderToWorkOrder) {
            foreach ($oi in $orderList) {
                try { [int]$oiK = [int]$oi } catch { continue }
                $woEnt = $OrderToWorkOrder[$oiK]
                if ($null -eq $woEnt) { continue }
                foreach ($fl in @(Get-CnsPlanningTourneeSpecialFlagsFromWorkOrder -WorkOrderEntity $woEnt)) {
                    $pk = ('{0}|{1}' -f [string]$fl.Type, [string]$fl.Client)
                    if ($specialSeen.Add($pk)) { [void]$specialAgg.Add($fl) }
                }
            }
        }

        Write-Host ("[TOURNEE-CREATE] Segment={0} Clients L{1}-L{2} Complete={3} OrderCount={4}" -f ($segments.Count + 1), $lo1, $hi1, $ts.TourneeComplete, $orderList.Count) -ForegroundColor Magenta

        [void]$segments.Add([pscustomobject]@{
            SegmentIndex    = ($segments.Count + 1)
            Collecteur      = $collecteurSeg
            Vehicule          = $vehiculeSeg
            TourDate          = $ts.TourDate
            DisplayDateJM     = [string]$ts.DisplayDateJM
            OrderIndices      = $orderList
            TourneeComplete   = [bool]$ts.TourneeComplete
            SpecialFlags      = @($specialAgg.ToArray())
        })
    }

    if (($segments.Count -eq 0) -and (@($ExcelOrder).Count -gt 0)) {
        $fd = ($FallbackVisitDate.Date.ToString('dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture))
        Write-Host ("[EXCEL-PARSE] Date={0} Collecteur={1} Vehicule={2}" -f $fd, 'INCONNU', 'NON SPECIFIE') -ForegroundColor Cyan
        $allOrders = @(Sort-Safe -InputObject @($ExcelOrder) -Property OrderIndex -KeyType Int | ForEach-Object { [int]$_.OrderIndex })
        Write-Host ("[TOURNEE-CREATE] Segment=1 (fallback sans date detectee) Complete=False OrderCount={0}" -f $allOrders.Count) -ForegroundColor Magenta
        $slotByOrderFb = @{}
        foreach ($ex in @($ExcelOrder)) {
            if ($null -eq $ex) { continue }
            try { $slotByOrderFb[[int]$ex.OrderIndex] = $ex } catch { }
        }
        [string]$colFb = 'INCONNU'
        [string]$vehFb = 'NON SPECIFIE'
        if ($allOrders.Count -ge 1) {
            $txf = Get-CnsTourneePrimaryTextFromExcelOrderSlot -OrderSlot $slotByOrderFb[[int]$allOrders[0]]
            if (-not [string]::IsNullOrWhiteSpace($txf)) { $colFb = $txf }
        }
        if ($allOrders.Count -ge 2) {
            $txf2 = Get-CnsTourneePrimaryTextFromExcelOrderSlot -OrderSlot $slotByOrderFb[[int]$allOrders[1]]
            if (-not [string]::IsNullOrWhiteSpace($txf2)) { $vehFb = $txf2 }
        }
        $specialFb = [System.Collections.Generic.List[hashtable]]::new()
        $specialSeenFb = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        if ($null -ne $OrderToWorkOrder) {
            foreach ($oi in $allOrders) {
                $woE = $OrderToWorkOrder[[int]$oi]
                if ($null -eq $woE) { continue }
                foreach ($fl in @(Get-CnsPlanningTourneeSpecialFlagsFromWorkOrder -WorkOrderEntity $woE)) {
                    $pk = ('{0}|{1}' -f [string]$fl.Type, [string]$fl.Client)
                    if ($specialSeenFb.Add($pk)) { [void]$specialFb.Add($fl) }
                }
            }
        }
        return @([pscustomobject]@{
            SegmentIndex    = 1
            Collecteur      = $colFb
            Vehicule          = $vehFb
            TourDate          = $FallbackVisitDate.Date
            DisplayDateJM     = $fd
            OrderIndices      = $allOrders
            TourneeComplete   = $false
            SpecialFlags      = @($specialFb.ToArray())
        })
    }

    return @($segments.ToArray())
}

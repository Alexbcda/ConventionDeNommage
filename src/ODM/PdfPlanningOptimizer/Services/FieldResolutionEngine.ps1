# ============================================================
# FieldResolutionEngine.ps1
# Point unique de résolution des priorités PDF vs Excel (valeurs scalaires).
# Politique déclarative : uniquement via Models/FieldResolutionPolicy.ps1 (Get-FieldResolutionPolicy).
# ============================================================

$_frp = Join-Path $PSScriptRoot '..\Models\FieldResolutionPolicy.ps1'
if (-not (Test-Path -LiteralPath $_frp)) {
    throw "FieldResolutionEngine: FieldResolutionPolicy.ps1 introuvable: $_frp"
}
. $_frp

function script:Fre-GetPropertyValue {
    param(
        [object]$Object,
        [string[]]$PropertyNames
    )
    if ($null -eq $Object) { return $null }
    foreach ($name in $PropertyNames) {
        $val = $null
        if ($Object -is [hashtable]) {
            if ($Object.ContainsKey($name)) { $val = $Object[$name] }
        }
        else {
            $prop = $Object.PSObject.Properties[$name]
            if ($null -ne $prop) { $val = $prop.Value }
        }
        if ($null -ne $val -and -not ($val -is [string] -and [string]::IsNullOrWhiteSpace($val))) {
            return $val
        }
    }
    return $null
}

function script:Fre-IsPresentValue {
    param([object]$Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [string]) {
        return -not [string]::IsNullOrWhiteSpace($Value)
    }
    return $true
}

function script:Fre-NormalizeOutValue {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        $t = $Value.Trim()
        if ($t -eq '') { return $null }
        return $t
    }
    return $Value
}

function script:Fre-FormatAddressScalar {
    param([object]$Raw)
    if ($null -eq $Raw) { return $null }
    if ($Raw -is [string]) {
        $t = $Raw.Trim()
        if ($t -eq '') { return $null }
        return $t
    }
    if ($Raw -is [hashtable]) {
        $parts = [System.Collections.Generic.List[string]]::new()
        foreach ($key in @('Street', 'PostalCode', 'City')) {
            if (-not $Raw.ContainsKey($key)) { continue }
            $v = $Raw[$key]
            if ($null -eq $v) { continue }
            $s = ([string]$v).Trim()
            if ($s -ne '') { [void]$parts.Add($s) }
        }
        if ($parts.Count -eq 0) { return $null }
        return ($parts -join ', ')
    }
    $s2 = ([string]$Raw).Trim()
    if ($s2 -eq '') { return $null }
    return $s2
}

function script:Fre-GetPdfClientId {
    param([object]$Entity)
    $v = Fre-GetPropertyValue -Object $Entity -PropertyNames @('ClientId', 'ClientID')
    if ($null -eq $v) { return $null }
    return ([string]$v).Trim()
}

function script:Fre-GetExcelClientId {
    param([object]$Row)
    $v = Fre-GetPropertyValue -Object $Row -PropertyNames @(
        'ClientId', 'ClientID', 'NoClient', 'CodeClient', 'IdClient'
    )
    if ($null -eq $v) { return $null }
    return ([string]$v).Trim()
}

function script:Fre-GetPdfWorkOrder {
    param([object]$Entity)
    if ($null -eq $Entity) { return $null }
    $wo = Fre-GetPropertyValue -Object $Entity -PropertyNames @('WorkOrder')
    if (Fre-IsPresentValue $wo) { return ([string]$wo).Trim() }
    $wosProp = $Entity.PSObject.Properties['WorkOrders']
    if ($null -ne $wosProp) {
        $arr = @($wosProp.Value)
        if ($arr.Count -gt 0 -and $null -ne $arr[0]) {
            $s = ([string]$arr[0]).Trim()
            if ($s -ne '') { return $s }
        }
    }
    return $null
}

function script:Fre-GetExcelWorkOrder {
    param([object]$Row)
    $v = Fre-GetPropertyValue -Object $Row -PropertyNames @(
        'WorkOrder', 'ODM', 'OrdreMission', 'NoODM', 'NumeroODM', 'Intervention'
    )
    if ($null -eq $v) { return $null }
    return ([string]$v).Trim()
}

function script:Fre-GetPdfAddress {
    param([object]$Entity)
    if ($null -eq $Entity) { return $null }
    $addr = Fre-GetPropertyValue -Object $Entity -PropertyNames @('Address', 'Adresse')
    return Fre-FormatAddressScalar -Raw $addr
}

function script:Fre-GetExcelAddress {
    param([object]$Row)
    $v = Fre-GetPropertyValue -Object $Row -PropertyNames @(
        'Address', 'Adresse', 'Rue', 'Lieu'
    )
    return Fre-FormatAddressScalar -Raw $v
}

function script:Fre-GetPdfDate {
    param([object]$Entity)
    Fre-GetPropertyValue -Object $Entity -PropertyNames @('Date', 'VisitDate')
}

function script:Fre-GetExcelDate {
    param([object]$Row)
    Fre-GetPropertyValue -Object $Row -PropertyNames @(
        'VisitDate', 'TourDate', 'DatePassage', 'Date', 'DateVisite', 'Jour'
    )
}

function script:Fre-GetPdfClientName {
    param([object]$Entity)
    $v = Fre-GetPropertyValue -Object $Entity -PropertyNames @('ClientName', 'NomClient')
    if ($null -eq $v) { return $null }
    return ([string]$v).Trim()
}

function script:Fre-GetExcelClientName {
    param([object]$Row)
    $v = Fre-GetPropertyValue -Object $Row -PropertyNames @(
        'ClientName', 'NomClient', 'RaisonSociale', 'Client'
    )
    if ($null -eq $v) { return $null }
    return ([string]$v).Trim()
}

function Resolve-FieldValue {
    <#
    .SYNOPSIS
        Retourne la première valeur non vide selon l'ordre Priority (PDF / Excel).
    #>
    [CmdletBinding()]
    param(
        $PdfValue,
        $ExcelValue,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Priority,
        [Parameter(Mandatory = $false)]
        [string]$FieldName = ''
    )

    foreach ($src in @($Priority)) {
        $candidate = $null
        switch ($src) {
            'PDF' { $candidate = $PdfValue; break }
            'Excel' { $candidate = $ExcelValue; break }
            Default { continue }
        }
        if (-not (Fre-IsPresentValue $candidate)) { continue }

        $out = Fre-NormalizeOutValue -Value $candidate
        if ($null -eq $out) { continue }

        if ($FieldName -ne '') {
            Write-Verbose ("Resolve-FieldValue [{0}]: source={1} final={2}" -f $FieldName, $src, $out)
        }
        return $out
    }

    if ($FieldName -ne '') {
        Write-Verbose ("Resolve-FieldValue [{0}]: source=(none) final=" -f $FieldName)
    }
    return $null
}

function Resolve-EntityFields {
    <#
    .SYNOPSIS
        Résout ClientId, WorkOrder, Address, Date, ClientName à partir d'une entité PDF et d'une ligne Excel.
    #>
    [CmdletBinding()]
    param(
        [object]$Entity,
        [object]$ExcelRow
    )

    $policy = Get-FieldResolutionPolicy

    $clientId = Resolve-FieldValue -PdfValue (Fre-GetPdfClientId -Entity $Entity) -ExcelValue (Fre-GetExcelClientId -Row $ExcelRow) -Priority $policy.ClientIdPriority -FieldName 'ClientId'

    $workOrder = Resolve-FieldValue -PdfValue (Fre-GetPdfWorkOrder -Entity $Entity) -ExcelValue (Fre-GetExcelWorkOrder -Row $ExcelRow) -Priority $policy.WorkOrderPriority -FieldName 'WorkOrder'

    $address = Resolve-FieldValue -PdfValue (Fre-GetPdfAddress -Entity $Entity) -ExcelValue (Fre-GetExcelAddress -Row $ExcelRow) -Priority $policy.AddressPriority -FieldName 'Address'

    $date = Resolve-FieldValue -PdfValue (Fre-GetPdfDate -Entity $Entity) -ExcelValue (Fre-GetExcelDate -Row $ExcelRow) -Priority $policy.DatePriority -FieldName 'Date'

    $clientName = Resolve-FieldValue -PdfValue (Fre-GetPdfClientName -Entity $Entity) -ExcelValue (Fre-GetExcelClientName -Row $ExcelRow) -Priority $policy.ClientNamePriority -FieldName 'ClientName'

    return [pscustomobject]@{
        ClientId   = $clientId
        WorkOrder  = $workOrder
        Address    = $address
        Date       = $date
        ClientName = $clientName
    }
}

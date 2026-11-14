# SortSafe.ps1 — tri sans op_Subtraction sur clés non scalaires (Object[] → premier élément, puis int/string)
# CN_SORT_DEBUG=1 : log [SORT-SAFE] si une clé d’origine est tableau
# Ne remplace pas ScalarGuard (aucune dépendance requise)

function script:Test-CnSortDebug {
    return ($env:CN_SORT_DEBUG -in @('1', 'true'))
}

function Get-SortSafeKeyInt {
    <#
    .SYNOPSIS
        Scalarise une valeur de tri (évite clé Sort-Object de type System.Object[]).
    #>
    [CmdletBinding()]
    param(
        $Value
    )
    if ($null -eq $Value) { return 0 }
    if ($Value -is [Array] -or $Value -is [System.Object[]]) {
        if (script:Test-CnSortDebug) {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log "[SORT-SAFE] clé int non scalaire (array) — prise de [0]" "INFO" @{
                    Type = $Value.GetType().FullName; Count = @($Value).Count
                }
            }
        }
        if (@($Value).Count -lt 1) { return 0 }
        $Value = $Value[0]
    }
    try {
        if ($Value -is [int] -or $Value -is [long] -or $Value -is [byte] -or $Value -is [double] -or $Value -is [float] -or $Value -is [decimal]) {
            return [int][double]$Value
        }
        return [int][double]::Parse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return 0
    }
}

function Get-SortSafeKeyString {
    [CmdletBinding()]
    param(
        $Value
    )
    if ($null -eq $Value) { return [string]'' }
    if ($Value -is [Array] -or $Value -is [System.Object[]]) {
        if (script:Test-CnSortDebug) {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log "[SORT-SAFE] clé string non scalaire (array) — prise de [0]" "INFO" @{
                    Type = $Value.GetType().FullName; Count = @($Value).Count
                }
            }
        }
        if (@($Value).Count -lt 1) { return [string]'' }
        $Value = $Value[0]
    }
    return [string]$Value
}

function Sort-Safe {
    <#
    .SYNOPSIS
        Sort-Object sur une propriété, avec clé d’entier ou de chaîne normalisée (pas de clé tableaux).
    .EXAMPLE
        Sort-Safe -InputObject $list -Property PageNumber
        Sort-Safe -InputObject $list -Property WorkOrder -KeyType String
    #>
    [CmdletBinding()]
    param(
    [Parameter(Position = 0, ValueFromPipeline = $true)]
    $InputObject,
    [Parameter(Mandatory = $true, Position = 1)]
    [string] $Property,
        [ValidateSet('Int', 'String')]
        [string] $KeyType = 'Int',
        [switch] $Descending
    )
    begin {
        $buffer = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($item in @($InputObject)) {
            [void]$buffer.Add($item)
        }
    }
    end {
        $list = @($buffer.ToArray())
        if ($list.Count -eq 0) { return @() }
        if ($KeyType -eq 'String') {
            if ($Descending) {
                return @(
                    $list | Sort-Object -Property @{ Expression = { (Get-SortSafeKeyString $_.$Property) }; Descending = $true }
                )
            }
            return @(
                $list | Sort-Object -Property @{ Expression = { (Get-SortSafeKeyString $_.$Property) } }
            )
        }
        if ($Descending) {
            return @(
                $list | Sort-Object -Property @{ Expression = { (Get-SortSafeKeyInt $_.$Property) }; Descending = $true }
            )
        }
        return @(
            $list | Sort-Object -Property @{ Expression = { (Get-SortSafeKeyInt $_.$Property) } }
        )
    }
}

function Sort-SafeTripleInt {
    <#
    .SYNOPSIS
        Tri à trois colonnes entières (ex. PDF Tournee, Rang, PageNum).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,
        [Parameter(Mandatory = $true)]
        [string] $P1,
        [Parameter(Mandatory = $true)]
        [string] $P2,
        [Parameter(Mandatory = $true)]
        [string] $P3
    )
    $list = @($InputObject)
    if ($list.Count -eq 0) { return @() }
    return @(
        $list | Sort-Object -Property @(
            @{ Expression = { (Get-SortSafeKeyInt $_.$P1) } }
            @{ Expression = { (Get-SortSafeKeyInt $_.$P2) } }
            @{ Expression = { (Get-SortSafeKeyInt $_.$P3) } }
        )
    )
}

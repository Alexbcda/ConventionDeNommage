# ============================================================
# ScalarGuard.ps1 — normalisation scalaire (évite System.Object[] / op_Subtraction)
# Variables d’environnement : CN_TYPE_GUARD=1 (logs [TYPE-GUARD]), CN_DEEP_TYPE_DEBUG=1 (types + stack)
# ============================================================

function Test-CnTypeGuard {
    return ($env:CN_TYPE_GUARD -in @('1', 'true'))
}

function Test-CnDeepTypeDebug {
    return ($env:CN_DEEP_TYPE_DEBUG -in @('1', 'true'))
}

function script:Write-ScalarLog {
    param(
        [string]$Message,
        [string]$Level = 'INFO',
        $Data = $null
    )
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log $Message $Level $Data
    } else {
        if ($Level -in @('ERROR', 'FAIL')) { Write-Error $Message }
        else { Write-Warning $Message }
    }
}

function Trace-IfArrayLeak {
    param(
        $Value,
        [string]$Label
    )
    if ($Value -is [Array] -or $Value -is [Object[]]) {
        $depth = if (Test-CnDeepTypeDebug) { 25 } else { 10 }
        $stack = (Get-PSCallStack | Select-Object -First $depth | ForEach-Object { $_.ToString() }) -join ' | '
        $valStr = if (@($Value).Count -le 6) { $Value -join ',' } else { "len=" + @($Value).Count }
        $typeHint = if (@($Value).Count -gt 0 -and $null -ne $Value[0]) { $Value[0].GetType().FullName } else { 'empty' }
        script:Write-ScalarLog -Message ("[ARRAY-LEAK DETECTED] {0} VALUE={1} ELEM0_TYPE={2} STACK: {3}" -f $Label, $valStr, $typeHint, $stack) -Level 'ERROR'
        return $true
    }
    return $false
}

function Trace-DeepType {
    <#
    .SYNOPSIS
        Si CN_DEEP_TYPE_DEBUG=1 : type réel (FullName) d’une variable « critique » ; stack étendu si tableaux.
    #>
    param(
        $Value,
        [string]$Label
    )
    if (-not (Test-CnDeepTypeDebug)) { return }
    $t = if ($null -eq $Value) { 'null' } else { $Value.GetType().FullName }
    script:Write-ScalarLog -Message ("[DEEP-TYPE] {0} => {1}" -f $Label, $t) -Level "INFO" -Data $null
    if ($Value -is [Array] -or $Value -is [Object[]]) {
        $depth = 25
        $stack = (Get-PSCallStack | Select-Object -First $depth | ForEach-Object { $_.ToString() }) -join ' | '
        $valStr = if (@($Value).Count -le 6) { $Value -join ',' } else { "len=" + @($Value).Count }
        script:Write-ScalarLog -Message ("[DEEP-TYPE-ARRAY] {0} VALUE={1} STACK: {2}" -f $Label, $valStr, $stack) -Level "ERROR" -Data $null
    }
}

function Normalize-Scalar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Value,
        [string]$Name = "unknown"
    )
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return $Value }
    if ($Value -is [Array] -or $Value -is [Object[]]) {
        if (Test-CnTypeGuard -or (Test-CnDeepTypeDebug)) {
            [void](Trace-IfArrayLeak -Value $Value -Label $Name)
            $joined = if (@($Value).Count -le 8) { $Value -join ',' } else { "len=" + @($Value).Count }
            if (Test-CnTypeGuard) {
                script:Write-ScalarLog -Message ("[TYPE-GUARD] Array detected in {0} → taking [0] | data={1}" -f $Name, $joined) -Level "WARN" $null
            }
        }
        if (@($Value).Count -lt 1) { return $null }
        return (Normalize-Scalar -Value $Value[0] -Name ($Name + '[0]'))
    }
    return $Value
}

function ConvertTo-SafeInt {
    [CmdletBinding()]
    param(
        $Value,
        [string]$Name = "unknown"
    )
    $v = (Normalize-Scalar -Value $Value -Name $Name)
    if ($null -eq $v) { return 0 }
    try {
        if ($v -is [int]) { return $v }
        if ($v -is [long] -or $v -is [double] -or $v -is [float] -or $v -is [decimal]) {
            return [int][Math]::Round([double]$v, [System.MidpointRounding]::AwayFromZero)
        }
        $s = [string]$v
        if ($s -in @('', [string][char]0)) { return 0 }
        return [int][Math]::Round([double]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture), [System.MidpointRounding]::AwayFromZero)
    } catch {
        $t = if ($null -ne $v) { $v.GetType().Name } else { 'null' }
        script:Write-ScalarLog -Message ("[TYPE-ERROR] Cannot convert to int in {0} | value={1} type={2}" -f $Name, $v, $t) -Level "ERROR" $null
        throw
    }
}

function ConvertTo-SafeLong {
    [CmdletBinding()]
    param(
        $Value,
        [string]$Name = "unknown"
    )
    $v = (Normalize-Scalar -Value $Value -Name $Name)
    if ($null -eq $v) { return 0L }
    try {
        if ($v -is [long]) { return $v }
        if ($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [float] -or $v -is [decimal]) {
            return [long][Math]::Round([double]$v, [System.MidpointRounding]::AwayFromZero)
        }
        $s = [string]$v
        if ($s -in @('', [string][char]0)) { return 0L }
        return [long][Math]::Round([double]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture), [System.MidpointRounding]::AwayFromZero)
    } catch {
        $t = if ($null -ne $v) { $v.GetType().Name } else { 'null' }
        script:Write-ScalarLog -Message ("[TYPE-ERROR] Cannot convert to long in {0} | value={1} type={2}" -f $Name, $v, $t) -Level "ERROR" $null
        throw
    }
}

function Safe-Subtract {
    [CmdletBinding()]
    param(
        $Left,
        $Right,
        [string]$Context = "unknown"
    )
    $l = ConvertTo-SafeInt -Value $Left -Name ("Left:" + $Context)
    $r = ConvertTo-SafeInt -Value $Right -Name ("Right:" + $Context)
    return $l - $r
}

function Get-SafeMin {
    <#
    .SYNOPSIS
        Minimum scalaire sûr : normalise chaque élément (Object[] en entrée) avant Measure-Object -Minimum.
    #>
    [CmdletBinding()]
    param(
        $Values,
        [string]$Name = "Get-SafeMin"
    )
    if ($null -eq $Values) { return 0 }
    if ($Values -is [string]) {
        return (ConvertTo-SafeInt -Value $Values -Name $Name)
    }
    if ($Values -is [ValueType]) {
        return (ConvertTo-SafeInt -Value $Values -Name $Name)
    }
    $arr = @($Values)
    if ($arr.Count -eq 0) { return 0 }
    if ($arr.Count -eq 1) {
        return (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $arr[0] -Name ($Name + "[0]")) -Name $Name)
    }
    $ints = [System.Collections.Generic.List[int]]::new()
    foreach ($x in $arr) {
        $xNorm = (Normalize-Scalar -Value $x -Name ($Name + ".item"))
        [void]$ints.Add((ConvertTo-SafeInt -Value $xNorm -Name ($Name + ".itemInt")))
    }
    if ($ints.Count -eq 0) { return 0 }
    $m = $ints | Measure-Object -Minimum
    $minV = if ($null -ne $m) { $m.Minimum } else { $null }
    return (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $minV -Name ($Name + ".min")) -Name ($Name + ".out"))
}

function Get-SafeMax {
    <#
    .SYNOPSIS
        Maximum scalaire sûr (même principe que Get-SafeMin).
    #>
    [CmdletBinding()]
    param(
        $Values,
        [string]$Name = "Get-SafeMax"
    )
    if ($null -eq $Values) { return 0 }
    if ($Values -is [string]) {
        return (ConvertTo-SafeInt -Value $Values -Name $Name)
    }
    if ($Values -is [ValueType]) {
        return (ConvertTo-SafeInt -Value $Values -Name $Name)
    }
    $arr = @($Values)
    if ($arr.Count -eq 0) { return 0 }
    if ($arr.Count -eq 1) {
        return (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $arr[0] -Name ($Name + "[0]")) -Name $Name)
    }
    $ints = [System.Collections.Generic.List[int]]::new()
    foreach ($x in $arr) {
        $xNorm = (Normalize-Scalar -Value $x -Name ($Name + ".item"))
        [void]$ints.Add((ConvertTo-SafeInt -Value $xNorm -Name ($Name + ".itemInt")))
    }
    if ($ints.Count -eq 0) { return 0 }
    $m = $ints | Measure-Object -Maximum
    $maxV = if ($null -ne $m) { $m.Maximum } else { $null }
    return (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $maxV -Name ($Name + ".max")) -Name ($Name + ".out"))
}

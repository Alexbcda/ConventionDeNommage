# Jours feries francais (metropole) : fixes + variables (Paques, Ascension, Pentecote).

function Get-EasterSundayDate {
    <#
    .SYNOPSIS
        Dimanche de Paques (calendrier gregorien, algorithme de Meeus/Jones/Butcher).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$Year
    )
    $a = $Year % 19
    $b = [int][Math]::Floor($Year / 100)
    $c = $Year % 100
    $d = [int][Math]::Floor($b / 4)
    $e = $b % 4
    $f = [int][Math]::Floor(($b + 8) / 25)
    $g = [int][Math]::Floor(($b - $f + 1) / 3)
    $h = (19 * $a + $b - $d - $g + 15) % 30
    $i = [int][Math]::Floor($c / 4)
    $k = $c % 4
    $l = (32 + 2 * $e + 2 * $i - $h - $k) % 7
    $m = [int][Math]::Floor(($a + 11 * $h + 22 * $l) / 451)
    $month = [int][Math]::Floor(($h + $l - 7 * $m + 114) / 31)
    $day = (($h + $l - 7 * $m + 114) % 31) + 1
    return (Get-Date -Year $Year -Month $month -Day $day).Date
}

function Get-FrenchPublicHolidays {
    <#
    .SYNOPSIS
        Liste des jours feries francais (metropole) pour une annee civile.
    .OUTPUTS
        [datetime[]] Dates a minuit (Date only).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$Year
    )
    $dates = New-Object System.Collections.Generic.List[datetime]
    $fixed = @(
        (1, 1), (5, 1), (5, 8), (7, 14), (8, 15), (11, 1), (11, 11), (12, 25)
    )
    foreach ($fd in @($fixed)) {
        [void]$dates.Add((Get-Date -Year $Year -Month $fd[0] -Day $fd[1]).Date)
    }
    $easter = Get-EasterSundayDate -Year $Year
    [void]$dates.Add($easter.AddDays(1).Date)   # Lundi de Paques
    [void]$dates.Add($easter.AddDays(39).Date)  # Ascension (jeudi)
    [void]$dates.Add($easter.AddDays(50).Date) # Lundi de Pentecote
    return @($dates | Sort-Object -Unique)
}

function IsFrenchPublicHoliday {
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$Date
    )
    $d = $Date.Date
    foreach ($h in @(Get-FrenchPublicHolidays -Year $d.Year)) {
        if ($h -eq $d) { return $true }
    }
    return $false
}

function Test-CnsFrenchWorkingDay {
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$Date
    )
    $d = $Date.Date
    if ($d.DayOfWeek -eq [DayOfWeek]::Saturday -or $d.DayOfWeek -eq [DayOfWeek]::Sunday) {
        return $false
    }
    if (IsFrenchPublicHoliday -Date $d) { return $false }
    return $true
}

function Add-WorkingDaysWithFrenchHolidays {
    <#
    .SYNOPSIS
        Ajoute N jours ouvrés (lundi-vendredi) hors jours feries francais, a partir du lendemain de StartDate.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$StartDate,
        [Parameter(Mandatory = $true)]
        [int]$WorkingDays,
        [System.Globalization.CultureInfo]$Culture = [System.Globalization.CultureInfo]::InvariantCulture
    )
    if ($WorkingDays -lt 1) {
        return $StartDate.Date
    }
    $cursor = $StartDate.Date
    $added = 0
    while ($added -lt $WorkingDays) {
        $cursor = $cursor.AddDays(1)
        if (Test-CnsFrenchWorkingDay -Date $cursor) {
            $added++
        }
    }
    return $cursor
}

function Add-2WorkingDaysWithFrenchHolidays {
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$StartDate
    )
    return (Add-WorkingDaysWithFrenchHolidays -StartDate $StartDate -WorkingDays 2)
}

function Format-CnsFrenchDate {
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$Date
    )
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    return $Date.ToString('dd/MM/yyyy', $inv)
}

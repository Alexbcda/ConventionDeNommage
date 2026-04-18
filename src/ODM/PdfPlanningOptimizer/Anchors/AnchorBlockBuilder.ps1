# ============================================================
# AnchorBlockBuilder.ps1
# Segmentation logique : regroupement d’ancres en blocs client (sans parsing métier).
# Chargement : . (Join-Path $PSScriptRoot 'Anchors\AnchorBlockBuilder.ps1')
# ============================================================

function script:Get-EndIndexInclusiveForLineStart {
    param(
        [string]$Text,
        [int]$LineStartIndex
    )
    $len = $Text.Length
    if ($len -eq 0) { return -1 }
    if ($LineStartIndex -lt 0) { $LineStartIndex = 0 }
    if ($LineStartIndex -ge $len) { return $len - 1 }
    $nl = $Text.IndexOf("`n", $LineStartIndex, [System.StringComparison]::Ordinal)
    if ($nl -lt 0) {
        return $len - 1
    }
    return [Math]::Max($LineStartIndex, $nl - 1)
}

function Build-AnchorBlocks {
    <#
    .SYNOPSIS
        Regroupe les ancres (sortie Find-Anchors) en blocs client délimités par CLIENT_BLOCK_START.

    .PARAMETER Text
        Texte normalisé (même base que pour Find-Anchors).

    .PARAMETER Anchors
        Liste d’objets { Name, Index, Line }.

    .OUTPUTS
        [pscustomobject] ClientBlockId, StartIndex, EndIndex, Anchors, RawTextBlock
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Anchors
    )

    Write-Verbose 'Build-AnchorBlocks: début.'

    if ($null -eq $Text) {
        Write-Verbose 'Build-AnchorBlocks: Text est $null — retour vide.'
        return @()
    }

    $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"

    if ($null -eq $Anchors -or $Anchors.Count -eq 0) {
        Write-Verbose 'Build-AnchorBlocks: aucune ancre — retour vide.'
        return @()
    }

    $sorted = @(
        $Anchors |
            Where-Object { $null -ne $_ } |
            Sort-Object -Property @{ Expression = { [int]$_.Index }; Ascending = $true }
    )

    $clientStarts = [System.Collections.Generic.List[int]]::new()
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        if ([string]$sorted[$i].Name -ceq 'CLIENT_BLOCK_START') {
            [void]$clientStarts.Add($i)
        }
    }

    $blocks = [System.Collections.Generic.List[object]]::new()
    $nextBlockId = 1

    # Ancres avant le premier CLIENT_BLOCK_START : bloc 0 (préambule)
    if ($clientStarts.Count -eq 0) {
        Write-Verbose 'Build-AnchorBlocks: aucun CLIENT_BLOCK_START — un seul bloc regroupant toutes les ancres (ClientBlockId=0).'
        $grp = $sorted
        $startIdx = [int]$grp[0].Index
        $lastA = $grp[$grp.Count - 1]
        $endLastLine = Get-EndIndexInclusiveForLineStart -Text $normalized -LineStartIndex ([int]$lastA.Index)
        $raw = if ($endLastLine -ge $startIdx) {
            $normalized.Substring($startIdx, $endLastLine - $startIdx + 1)
        }
        else {
            ''
        }
        $blocks.Add([pscustomobject]@{
            ClientBlockId = 0
            StartIndex    = $startIdx
            EndIndex      = $endLastLine
            Anchors       = @($grp)
            RawTextBlock  = $raw
        })
        Write-Verbose "Build-AnchorBlocks: bloc 0 — $($grp.Count) ancre(s)."
        Write-Verbose "Build-AnchorBlocks: fin — 1 bloc créé."
        return $blocks.ToArray()
    }

    $firstClientIdx = $clientStarts[0]
    if ($firstClientIdx -gt 0) {
        $preamble = $sorted[0..($firstClientIdx - 1)]
        $pStart = [int]$preamble[0].Index
        $pLast = $preamble[$preamble.Count - 1]
        $pEndLine = Get-EndIndexInclusiveForLineStart -Text $normalized -LineStartIndex ([int]$pLast.Index)
        $cStart = [int]$sorted[$firstClientIdx].Index
        $pEnd = [Math]::Min($pEndLine, $cStart - 1)
        if ($pEnd -lt $pStart) { $pEnd = $pEndLine }
        $pRaw = if ($pEnd -ge $pStart) {
            $normalized.Substring($pStart, $pEnd - $pStart + 1)
        }
        else {
            ''
        }
        $blocks.Add([pscustomobject]@{
            ClientBlockId = 0
            StartIndex    = $pStart
            EndIndex      = $pEnd
            Anchors       = @($preamble)
            RawTextBlock  = $pRaw
        })
        Write-Verbose "Build-AnchorBlocks: bloc préambule (ClientBlockId=0) — $($preamble.Count) ancre(s)."
    }

    for ($b = 0; $b -lt $clientStarts.Count; $b++) {
        $from = $clientStarts[$b]
        $to = if ($b + 1 -lt $clientStarts.Count) {
            $clientStarts[$b + 1] - 1
        }
        else {
            $sorted.Count - 1
        }
        $grp = $sorted[$from..$to]
        $startIdx = [int]$grp[0].Index
        $lastA = $grp[$grp.Count - 1]
        $endLastLine = Get-EndIndexInclusiveForLineStart -Text $normalized -LineStartIndex ([int]$lastA.Index)

        $endIdx = $endLastLine
        if ($b + 1 -lt $clientStarts.Count) {
            $nextClientStart = [int]$sorted[$clientStarts[$b + 1]].Index
            $cap = $nextClientStart - 1
            if ($cap -ge $startIdx) {
                $endIdx = [Math]::Min($endLastLine, $cap)
            }
        }

        $raw = if ($endIdx -ge $startIdx) {
            $normalized.Substring($startIdx, $endIdx - $startIdx + 1)
        }
        else {
            ''
        }

        $blocks.Add([pscustomobject]@{
            ClientBlockId = $nextBlockId
            StartIndex    = $startIdx
            EndIndex      = $endIdx
            Anchors       = @($grp)
            RawTextBlock  = $raw
        })
        $anchorNames = @($grp | ForEach-Object { $_.Name }) -join ', '
        Write-Verbose "Build-AnchorBlocks: bloc client ClientBlockId=$nextBlockId — $($grp.Count) ancre(s) [$anchorNames]."
        $nextBlockId++
    }

    Write-Verbose "Build-AnchorBlocks: fin — $($blocks.Count) bloc(s) créé(s)."
    return $blocks.ToArray()
}

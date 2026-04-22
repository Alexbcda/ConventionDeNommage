# ============================================================
# AnchorScoring.ps1
# Scoring contextuel pour choisir la meilleure ligne (adresse, date) dans un bloc.
# Motifs : Get-AnchorPattern uniquement (registre inchangé).
# Chargement : . (Join-Path $PSScriptRoot 'Anchors\AnchorScoring.ps1')
# ============================================================

$_asRegPath = Join-Path $PSScriptRoot 'AnchorPatternRegistry.ps1'
if (-not (Test-Path -LiteralPath $_asRegPath)) {
    $_asRegPath = Join-Path $PSScriptRoot 'Anchors\AnchorPatternRegistry.ps1'
}
if (-not (Get-Command -Name Get-AnchorPattern -ErrorAction SilentlyContinue)) {
    . $_asRegPath
}

function script:Get-AnchorScoringLineIndexFromCharIndex {
    param(
        [string]$Text,
        [int]$CharIndex
    )
    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    if ($CharIndex -le 0) { return 0 }
    $cap = [Math]::Min($CharIndex, $Text.Length)
    $before = $Text.Substring(0, $cap)
    return ([regex]::Matches($before, "`n", [System.Text.RegularExpressions.RegexOptions]::None)).Count
}

function Get-BestAnchorMatch {
    <#
    .SYNOPSIS
        Sélectionne la meilleure ligne pour AddressPattern ou DatePattern selon un score contextuel.

    .OUTPUTS
        PSCustomObject { Result [string], BestScore [double], CandidateSummary [string] }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$Anchors,

        [Parameter(Mandatory = $true)]
        [ValidateSet('AddressPattern', 'DatePattern')]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        Write-Verbose 'Get-BestAnchorMatch: texte vide — aucun résultat.'
        return [pscustomobject]@{
            Result            = $null
            BestScore         = [double]::NegativeInfinity
            CandidateSummary  = 'aucun'
        }
    }

    $marker = Get-AnchorPattern -Type ClientNamePattern -Verbose:$false
    $sPostal = Get-AnchorPattern -Type AddressPattern -Verbose:$false
    $sWo = Get-AnchorPattern -Type WorkOrderPattern -Verbose:$false
    $sDate = Get-AnchorPattern -Type DatePattern -Verbose:$false
    $rxPostal = [regex]::new($sPostal)
    $rxWoFull = [regex]::new($sWo)
    $rxDate = [regex]::new($sDate)
    $rxAdvNoise = [regex]'(?i)\b(contrat|facture|chorus)\b'

    $lines = @($Text -split "`n", [System.StringSplitOptions]::None)

    # Ligne de référence « client » : premier CLIENT_BLOCK_START dans Anchors, sinon première ligne avec marqueur
    $refLineIdx = 0
    $foundClientAnchor = $false
    if ($Anchors) {
        foreach ($a in $Anchors) {
            if ($null -eq $a) { continue }
            if ([string]$a.Name -ceq 'CLIENT_BLOCK_START') {
                $refLineIdx = Get-AnchorScoringLineIndexFromCharIndex -Text $Text -CharIndex ([int]$a.Index)
                $foundClientAnchor = $true
                Write-Verbose "Get-BestAnchorMatch: ancre CLIENT_BLOCK_START → ligne référence index=$refLineIdx (0-based)."
                break
            }
        }
    }
    if (-not $foundClientAnchor) {
        for ($li = 0; $li -lt $lines.Count; $li++) {
            if ($lines[$li].IndexOf($marker, [System.StringComparison]::Ordinal) -ge 0) {
                $refLineIdx = $li
                Write-Verbose "Get-BestAnchorMatch: pas d’ancre CLIENT — référence par marqueur ClientNamePattern → ligne $refLineIdx."
                break
            }
        }
    }

    if ($Type -eq 'AddressPattern') {
        $kw = [regex]'(?i)\b(rue|avenue|route|routes|boulevard|bd|chemin|allee|impasse|place|quai|passage|lotissement|voie|cours|square|residence|za|zac)\b'
        $bestScore = [double]::NegativeInfinity
        $bestIdx = -1
        $summary = [System.Text.StringBuilder]::new()

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if (-not $rxPostal.IsMatch($line)) { continue }

            # Exclusion : ligne avec marqueur client ou paire type WO
            if ($line.IndexOf($marker, [System.StringComparison]::Ordinal) -ge 0) {
                Write-Verbose "Get-BestAnchorMatch [Address] ligne $i : exclue (contient marqueur ClientNamePattern)."
                continue
            }
            if ($rxWoFull.IsMatch($line)) {
                Write-Verbose "Get-BestAnchorMatch [Address] ligne $i : exclue (motif WorkOrderPattern)."
                continue
            }

            $dist = [Math]::Abs($i - $refLineIdx)
            $scoreProx = [Math]::Max(0, 40 - ($dist * 4))
            $kwMatches = $kw.Matches($line)
            $scoreKw = [double]($kwMatches.Count * 8)
            $scoreTotal = $scoreProx + $scoreKw

            [void]$summary.AppendLine("  candidat ligne $i score=$([math]::Round($scoreTotal,2)) (prox=$scoreProx, mots-clés=$scoreKw) | $line")

            Write-Verbose "Get-BestAnchorMatch [Address] ligne $i score=$([math]::Round($scoreTotal,2)) (proximité ref=$scoreProx, mots-clés=$scoreKw)."

            if ($scoreTotal -gt $bestScore) {
                $bestScore = $scoreTotal
                $bestIdx = $i
            }
        }

        if ($bestIdx -lt 0) {
            Write-Verbose 'Get-BestAnchorMatch [Address] : aucun candidat postal valide après filtres.'
            return [pscustomobject]@{
                Result            = $null
                BestScore         = $bestScore
                CandidateSummary  = $summary.ToString()
            }
        }

        $prev = if ($bestIdx -gt 0) { $lines[$bestIdx - 1].Trim() } else { '' }
        $cur = $lines[$bestIdx].Trim()
        $addr = @($prev, $cur) -join "`n"
        Write-Verbose "Get-BestAnchorMatch [Address] : meilleure ligne index=$bestIdx score=$([math]::Round($bestScore,2))."
        return [pscustomobject]@{
            Result            = $addr
            BestScore         = $bestScore
            CandidateSummary  = $summary.ToString()
        }
    }

    # DatePattern
    $bestDateScore = [double]::NegativeInfinity
    $bestDateIdx = -1
    $dateSb = [System.Text.StringBuilder]::new()

    for ($j = 0; $j -lt $lines.Count; $j++) {
        $ln = $lines[$j]
        if (-not $rxDate.IsMatch($ln)) { continue }
        if ($rxAdvNoise.IsMatch($ln)) {
            Write-Verbose "Get-BestAnchorMatch [Date] ligne $j : ignorée (bruit ADV)."
            continue
        }

        $distD = [Math]::Abs($j - $refLineIdx)
        $scoreD = [Math]::Max(0, 50 - ($distD * 3))
        if ($ln -match '(?i)Date\s+de\s+passage') {
            $scoreD += 25
        }

        [void]$dateSb.AppendLine("  candidat ligne $j score=$([math]::Round($scoreD,2)) | $ln")
        Write-Verbose "Get-BestAnchorMatch [Date] ligne $j score=$([math]::Round($scoreD,2))."

        if ($scoreD -gt $bestDateScore) {
            $bestDateScore = $scoreD
            $bestDateIdx = $j
        }
    }

    if ($bestDateIdx -lt 0) {
        Write-Verbose 'Get-BestAnchorMatch [Date] : aucune ligne date valide (hors bruit ADV).'
        return [pscustomobject]@{
            Result            = $null
            BestScore         = $bestDateScore
            CandidateSummary  = $dateSb.ToString()
        }
    }

    $dateOut = $lines[$bestDateIdx].Trim()
    Write-Verbose "Get-BestAnchorMatch [Date] : meilleure ligne index=$bestDateIdx score=$([math]::Round($bestDateScore,2))."
    return [pscustomobject]@{
        Result            = $dateOut
        BestScore         = $bestDateScore
        CandidateSummary  = $dateSb.ToString()
    }
}

# ============================================================
# AnchorEngine.ps1
# Moteur de repères (anchors) sur texte normalisé : détection uniquement,
# pas d’extraction métier finale par regex sur champs.
# Chargement : . (Join-Path $PSScriptRoot 'Anchors\AnchorEngine.ps1')
# ============================================================

function Find-Anchors {
    <#
    .SYNOPSIS
        Repère des ancres MVP dans un texte normalisé (ligne par ligne).

    .PARAMETER Text
        Texte multi-lignes (déjà normalisé en amont).

    .OUTPUTS
        Liste d’objets PSCustomObject { Name, Index, Line }.
        Index = index de caractère 0-based du début de la ligne contenant l’ancre.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    Write-Verbose "Find-Anchors: début (longueur texte=$($Text.Length))."
    $result = [System.Collections.Generic.List[object]]::new()

    if ($null -eq $Text) {
        Write-Verbose 'Find-Anchors: texte $null, retour vide.'
        return @()
    }

    $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    $lines = $normalized -split "`n", [System.StringSplitOptions]::None
    $lineCount = $lines.Count
    Write-Verbose "Find-Anchors: $lineCount ligne(s) après découpage."

    $pos = 0
    for ($i = 0; $i -lt $lineCount; $i++) {
        $line = $lines[$i]
        $lineStartIndex = $pos

        if ($line -match 'N°') {
            Write-Verbose "Find-Anchors: CLIENT_BLOCK_START — ligne $($i + 1), index=$lineStartIndex."
            $result.Add([pscustomobject]@{
                Name  = 'CLIENT_BLOCK_START'
                Index = $lineStartIndex
                Line  = $line
            })
        }

        if ($line -match '\b\d{5}\b') {
            Write-Verbose "Find-Anchors: ADDRESS_BLOCK — ligne $($i + 1), index=$lineStartIndex."
            $result.Add([pscustomobject]@{
                Name  = 'ADDRESS_BLOCK'
                Index = $lineStartIndex
                Line  = $line
            })
        }

        if ($line -match '(?i)Date\s+de\s+passage') {
            Write-Verbose "Find-Anchors: DATE_BLOCK — ligne $($i + 1), index=$lineStartIndex."
            $result.Add([pscustomobject]@{
                Name  = 'DATE_BLOCK'
                Index = $lineStartIndex
                Line  = $line
            })
        }

        if ($line -match '\b\d{7}-\d{8}\b') {
            Write-Verbose "Find-Anchors: WORKORDER_LINE — ligne $($i + 1), index=$lineStartIndex."
            $result.Add([pscustomobject]@{
                Name  = 'WORKORDER_LINE'
                Index = $lineStartIndex
                Line  = $line
            })
        }

        if ($i -lt $lineCount - 1) {
            $pos += $line.Length + 1
        }
        else {
            $pos += $line.Length
        }
    }

    Write-Verbose "Find-Anchors: fin — $($result.Count) ancre(s) trouvée(s)."
    return $result.ToArray()
}

function Extract-AnchorContext {
    <#
    .SYNOPSIS
        Extrait un bloc de texte autour de l’ancre : 5 lignes avant et 5 après (ligne de l’ancre incluse).

    .PARAMETER Text
        Texte normalisé complet.

    .PARAMETER Anchor
        Objet avec au minimum Index (début de ligne) ou Line pour retrouver la ligne.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [object]$Anchor
    )

    Write-Verbose "Extract-AnchorContext: début (anchor.Name=$($Anchor.Name))."

    if ($null -eq $Text -or $Text.Length -eq 0) {
        Write-Verbose 'Extract-AnchorContext: texte vide.'
        return ''
    }

    $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    $lines = $normalized -split "`n", [System.StringSplitOptions]::None
    $n = $lines.Count

    $lineIndex = 0
    if ($null -ne $Anchor.PSObject.Properties['Index']) {
        $idx = [int]$Anchor.Index
        if ($idx -lt 0) { $idx = 0 }
        if ($idx -gt $normalized.Length) { $idx = $normalized.Length }
        $before = $normalized.Substring(0, $idx)
        $lineIndex = ($before -split "`n", [System.StringSplitOptions]::None).Count - 1
        Write-Verbose "Extract-AnchorContext: ligne dérivée de Index=$idx → lineIndex=$lineIndex (0-based)."
    }
    elseif ($null -ne $Anchor.PSObject.Properties['Line'] -and -not [string]::IsNullOrEmpty([string]$Anchor.Line)) {
        $target = [string]$Anchor.Line
        for ($j = 0; $j -lt $n; $j++) {
            if ($lines[$j] -ceq $target) {
                $lineIndex = $j
                Write-Verbose "Extract-AnchorContext: ligne trouvée par correspondance exacte de Line → lineIndex=$lineIndex."
                break
            }
        }
    }
    else {
        Write-Verbose 'Extract-AnchorContext: impossible de déterminer la ligne (Index / Line manquants).'
        return ''
    }

    $from = [Math]::Max(0, $lineIndex - 5)
    $to = [Math]::Min($n - 1, $lineIndex + 5)
    $slice = $lines[$from..$to]
    $out = $slice -join "`n"

    Write-Verbose "Extract-AnchorContext: lignes $from à $to (total $($slice.Count))."
    Write-Verbose "Extract-AnchorContext: fin (longueur bloc=$($out.Length))."
    return $out
}

# ============================================================
# HumanMergeAdapter.ps1
# Agrégation PDF + décisions humaines persistées → ResolvedMatchesFinal.
# Clé TourneeId|Position ; priorité absolue aux lignes humaines (FinalEntity, statut PDF = OriginalStatus).
# Aucune dépendance aux autres scripts du dépôt ; pas de scoring ni parsing documentaire.
# ============================================================

function script:Hma-ResolvedMatchKey {
    param(
        [object]$Row
    )
    if ($null -eq $Row) { return $null }
    if ($null -eq $Row.PSObject.Properties['TourneeId'] -or $null -eq $Row.PSObject.Properties['Position']) {
        return $null
    }
    $tid = [string]$Row.TourneeId
    $pos = [int]$Row.Position
    return "$tid|$pos"
}

function script:Hma-StringPresent {
    param([object]$Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [string]) { return -not [string]::IsNullOrWhiteSpace($Value) }
    return $true
}

function script:Hma-CopyResolvedMatchLine {
    param([object]$Row)
    if ($null -eq $Row) { return $null }
    $o = [ordered]@{}
    foreach ($p in $Row.PSObject.Properties) {
        if ($p.MemberType -ne 'NoteProperty' -and $p.MemberType -ne 'Property') { continue }
        $o[$p.Name] = $p.Value
    }
    return [pscustomobject]$o
}

function script:Hma-MergePdfRowWithHuman {
    param(
        [object]$PdfRow,
        [object]$HumanRow
    )
    $o = [ordered]@{}
    foreach ($p in $PdfRow.PSObject.Properties) {
        if ($p.MemberType -ne 'NoteProperty' -and $p.MemberType -ne 'Property') { continue }
        $o[$p.Name] = $p.Value
    }

    if ($null -ne $HumanRow.PSObject.Properties['FinalEntity']) {
        $o['FinalEntity'] = $HumanRow.FinalEntity
    }
    if ($null -ne $HumanRow.PSObject.Properties['OriginalStatus']) {
        $o['OriginalStatus'] = $HumanRow.OriginalStatus
    }
    if ($null -ne $HumanRow.PSObject.Properties['ResolutionSource']) {
        $o['ResolutionSource'] = $HumanRow.ResolutionSource
    }

    if ($null -ne $HumanRow.PSObject.Properties['ExcelWorkOrder'] -and (Hma-StringPresent $HumanRow.ExcelWorkOrder)) {
        $o['ExcelWorkOrder'] = [string]$HumanRow.ExcelWorkOrder
    }
    if ($null -ne $HumanRow.PSObject.Properties['ExcelClientId'] -and (Hma-StringPresent $HumanRow.ExcelClientId)) {
        $o['ExcelClientId'] = $HumanRow.ExcelClientId
    }

    foreach ($extra in @('UserId', 'UtcSaved')) {
        if ($null -ne $HumanRow.PSObject.Properties[$extra]) {
            $o[$extra] = $HumanRow.PSObject.Properties[$extra].Value
        }
    }

    return [pscustomobject]$o
}

function Merge-HumanAndPdfDecisions {
    <#
    .SYNOPSIS
        Fusionne les ResolvedMatches PDF avec les décisions humaines (clé TourneeId|Position).

    .DESCRIPTION
        Les lignes humaines priment sur FinalEntity et OriginalStatus (statut pipeline PDF).
        Champs ExcelWorkOrder / ExcelClientId : valeur humaine si renseignée, sinon PDF.
        Les entrées humaines absentes du PDF sont conservées en fin de liste.

    .OUTPUTS
        [object[]] — même forme que ResolvedMatches (human-aware), alias ResolvedMatchesFinal.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$ResolvedMatches = @(),

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$HumanResolvedMatches = @()
    )

    $pdfOrder = [System.Collections.Generic.List[string]]::new()
    $pdfByKey = @{}
    foreach ($r in @($ResolvedMatches)) {
        if ($null -eq $r) { continue }
        $k = Hma-ResolvedMatchKey -Row $r
        if ([string]::IsNullOrWhiteSpace($k)) { continue }
        if (-not $pdfByKey.ContainsKey($k)) {
            [void]$pdfOrder.Add($k)
            $pdfByKey[$k] = $r
        }
    }

    $humanByKey = @{}
    foreach ($h in @($HumanResolvedMatches)) {
        if ($null -eq $h) { continue }
        $kh = Hma-ResolvedMatchKey -Row $h
        if ([string]::IsNullOrWhiteSpace($kh)) { continue }
        $humanByKey[$kh] = $h
    }

    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($k in $pdfOrder) {
        $pdfRow = $pdfByKey[$k]
        if ($humanByKey.ContainsKey($k)) {
            [void]$out.Add((Hma-MergePdfRowWithHuman -PdfRow $pdfRow -HumanRow $humanByKey[$k]))
        }
        else {
            [void]$out.Add((Hma-CopyResolvedMatchLine -Row $pdfRow))
        }
    }

    foreach ($hk in @($humanByKey.Keys)) {
        if ($pdfByKey.ContainsKey($hk)) { continue }
        [void]$out.Add((Hma-CopyResolvedMatchLine -Row $humanByKey[$hk]))
    }

    return @($out.ToArray())
}

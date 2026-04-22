# ============================================================
# AnchorEntityExtractor.ps1
# Extraction sémantique légère à partir des blocs validés (mapping texte, pas de fuzzy).
# Chargement : . (Join-Path $PSScriptRoot 'Anchors\AnchorEntityExtractor.ps1')
# Motifs : exclusivement AnchorPatternRegistry (aucune regex inline).
# ============================================================

$_anchorRegPath = Join-Path $PSScriptRoot 'AnchorPatternRegistry.ps1'
if (-not (Test-Path -LiteralPath $_anchorRegPath)) {
    $_anchorRegPath = Join-Path $PSScriptRoot 'Anchors\AnchorPatternRegistry.ps1'
}
. $_anchorRegPath

$_anchorScoringPath = Join-Path $PSScriptRoot 'AnchorScoring.ps1'
if (-not (Test-Path -LiteralPath $_anchorScoringPath)) {
    $_anchorScoringPath = Join-Path $PSScriptRoot 'Anchors\AnchorScoring.ps1'
}
. $_anchorScoringPath

function script:Resolve-AnchorPatternString {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'ClientNamePattern',
            'ClientIdPattern',
            'WorkOrderPattern',
            'AddressPattern',
            'DatePattern'
        )]
        [string]$Type
    )
    try {
        if (-not (Get-Command -Name Get-AnchorPattern -ErrorAction SilentlyContinue)) {
            throw 'Get-AnchorPattern absent'
        }
        $s = Get-AnchorPattern -Type $Type -Verbose:$false
        if ($null -eq $s) {
            throw 'pattern null'
        }
        return [string]$s
    }
    catch {
        throw 'Missing anchor pattern type'
    }
}

function Extract-AnchorEntities {
    <#
    .SYNOPSIS
        Extrait ClientName, ClientId, WorkOrders, Address, Date pour chaque bloc client validé.

    .PARAMETER ValidatedBlocks
        Sortie de Validate-AnchorBlocks (ClientBlockId, IsValid, …).

    .PARAMETER Blocks
        Sortie de Build-AnchorBlocks (obligatoire : RawTextBlock par ClientBlockId).

    .PARAMETER Text
        Texte normalisé complet (repli si RawTextBlock absent sur un bloc).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$ValidatedBlocks,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Blocks,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    Write-Verbose 'Extract-AnchorEntities: début — aucune regex inline ; source exclusive AnchorPatternRegistry.'

    $out = [System.Collections.Generic.List[object]]::new()
    $extractedCount = 0
    $incompleteFieldsTotal = 0

    if ($null -eq $ValidatedBlocks -or $ValidatedBlocks.Count -eq 0) {
        Write-Verbose 'Extract-AnchorEntities: aucun élément validé — 0 client, 0 champ incomplet.'
        return @()
    }

    try {
        $strClientNameMarker = Resolve-AnchorPatternString -Type ClientNamePattern
        $sClientId = Resolve-AnchorPatternString -Type ClientIdPattern
        $sWorkOrder = Resolve-AnchorPatternString -Type WorkOrderPattern
        $sAddress = Resolve-AnchorPatternString -Type AddressPattern
        $sDate = Resolve-AnchorPatternString -Type DatePattern
        $rxClientId = [regex]::new($sClientId)
        $rxWorkOrder = [regex]::new($sWorkOrder)
    }
    catch {
        throw 'Missing anchor pattern type'
    }

    Write-Verbose "Extract-AnchorEntities: précompilation — ClientNamePattern (marqueur)='$strClientNameMarker'"
    Write-Verbose "Extract-AnchorEntities: précompilation — ClientIdPattern='$sClientId'"
    Write-Verbose "Extract-AnchorEntities: précompilation — WorkOrderPattern='$sWorkOrder'"
    Write-Verbose "Extract-AnchorEntities: Address / Date — sélection contextuelle via Get-BestAnchorMatch (AnchorScoring) ; AddressPattern='$sAddress' DatePattern='$sDate'"

    foreach ($val in $ValidatedBlocks) {
        if ($null -eq $val) { continue }
        $cid = [int]$val.ClientBlockId
        if ($cid -eq 0) { continue }
        if (-not [bool]$val.IsValid) { continue }

        $blk = @($Blocks | Where-Object { $null -ne $_ -and [int]$_.ClientBlockId -eq $cid } | Select-Object -First 1)
        if ($blk.Count -eq 0) {
            Write-Verbose "Extract-AnchorEntities: aucun bloc structurel pour ClientBlockId=$cid — ignoré."
            continue
        }

        $blockObj = $blk[0]
        $raw = [string]$blockObj.RawTextBlock
        if ([string]::IsNullOrEmpty($raw) -and $null -ne $blockObj.PSObject.Properties['StartIndex'] -and $null -ne $blockObj.PSObject.Properties['EndIndex']) {
            $si = [int]$blockObj.StartIndex
            $ei = [int]$blockObj.EndIndex
            if ($null -ne $Text -and $Text.Length -gt 0 -and $ei -ge $si) {
                $eiCap = [Math]::Min($ei, $Text.Length - 1)
                if ($eiCap -ge $si) {
                    $raw = $Text.Substring($si, $eiCap - $si + 1)
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($raw)) {
            Write-Verbose "Extract-AnchorEntities: RawTextBlock vide pour ClientBlockId=$cid — ignoré."
            continue
        }

        Write-Verbose "Extract-AnchorEntities: ClientBlockId=$cid — motifs registre : ClientNamePattern='$strClientNameMarker' | ClientIdPattern='$sClientId' | WorkOrderPattern='$sWorkOrder' | AddressPattern='$sAddress' | DatePattern='$sDate'"

        # 1. ClientName : avant le marqueur ClientNamePattern sur la première ligne du bloc qui le contient
        $clientName = $null
        $lines = @($raw -split "`n", [System.StringSplitOptions]::None)
        foreach ($line in $lines) {
            $idx = $line.IndexOf($strClientNameMarker, [System.StringComparison]::Ordinal)
            if ($idx -ge 0) {
                if ($idx -gt 0) {
                    $clientName = $line.Substring(0, $idx).Trim()
                }
                break
            }
        }

        # 2. ClientId
        $clientId = $null
        $mId = $rxClientId.Match($raw)
        if ($mId.Success) {
            $clientId = $mId.Groups[1].Value
        }

        # 3. WorkOrders
        $woList = [System.Collections.Generic.List[string]]::new()
        foreach ($m in $rxWorkOrder.Matches($raw)) {
            [void]$woList.Add($m.Groups[1].Value)
        }
        $workOrders = @($woList.ToArray() | Select-Object -Unique)

        # 4. Address — scoring contextuel (plus de première occurrence seule)
        $blockAnchors = @($blockObj.Anchors)
        $addrPick = Get-BestAnchorMatch -Anchors $blockAnchors -Type AddressPattern -Text $raw -Verbose
        $address = $addrPick.Result
        if ($addrPick.CandidateSummary) {
            Write-Verbose "Extract-AnchorEntities: détail scoring Address —`n$($addrPick.CandidateSummary)"
        }

        # 5. Date — scoring contextuel (bruit ADV filtré dans AnchorScoring)
        $datePick = Get-BestAnchorMatch -Anchors $blockAnchors -Type DatePattern -Text $raw -Verbose
        $dateLine = $datePick.Result
        if ($datePick.CandidateSummary) {
            Write-Verbose "Extract-AnchorEntities: détail scoring Date —`n$($datePick.CandidateSummary)"
        }

        if ([string]::IsNullOrWhiteSpace($clientName)) { $incompleteFieldsTotal++ }
        if ([string]::IsNullOrWhiteSpace($clientId)) { $incompleteFieldsTotal++ }
        if ($workOrders.Count -eq 0) { $incompleteFieldsTotal++ }
        if ([string]::IsNullOrWhiteSpace($address)) { $incompleteFieldsTotal++ }
        if ([string]::IsNullOrWhiteSpace($dateLine)) { $incompleteFieldsTotal++ }

        $extractedCount++
        $out.Add([pscustomobject]@{
            ClientBlockId = $cid
            ClientName    = $clientName
            ClientId      = $clientId
            WorkOrders    = $workOrders
            Address       = $address
            Date          = $dateLine
        })
        Write-Verbose "Extract-AnchorEntities: ClientBlockId=$cid extrait (WO: $($workOrders.Count))."
    }

    Write-Verbose "Extract-AnchorEntities: nombre de clients extraits = $extractedCount."
    Write-Verbose "Extract-AnchorEntities: nombre de champs incomplets (cumul) = $incompleteFieldsTotal."
    Write-Verbose 'Extract-AnchorEntities: fin — regex inline supprimées ; motifs issus uniquement de AnchorPatternRegistry.'

    return $out.ToArray()
}

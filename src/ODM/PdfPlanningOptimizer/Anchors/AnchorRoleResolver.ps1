# ============================================================
# AnchorRoleResolver.ps1
# Couche de résolution sémantique : rôles explicites au-dessus des scores / extraction.
# Ne modifie ni AnchorScoring ni AnchorPatternRegistry.
# Chargement : . (Join-Path $PSScriptRoot 'Anchors\AnchorRoleResolver.ps1')
# ============================================================

$_arrRegPath = Join-Path $PSScriptRoot 'AnchorPatternRegistry.ps1'
if (-not (Test-Path -LiteralPath $_arrRegPath)) {
    $_arrRegPath = Join-Path $PSScriptRoot 'Anchors\AnchorPatternRegistry.ps1'
}
if (-not (Get-Command -Name Get-AnchorPattern -ErrorAction SilentlyContinue)) {
    . $_arrRegPath
}

function script:Get-AnchorRoleResolverBlockRaw {
    param(
        [object[]]$Blocks,
        [int]$ClientBlockId,
        [string]$FullText
    )
    $b = @($Blocks | Where-Object { $null -ne $_ -and [int]$_.ClientBlockId -eq $ClientBlockId } | Select-Object -First 1)
    if ($b.Count -eq 0) { return $null }
    $o = $b[0]
    $raw = [string]$o.RawTextBlock
    if (-not [string]::IsNullOrEmpty($raw)) { return $raw }
    if ($null -ne $o.PSObject.Properties['StartIndex'] -and $null -ne $o.PSObject.Properties['EndIndex']) {
        $si = [int]$o.StartIndex
        $ei = [int]$o.EndIndex
        if (-not [string]::IsNullOrEmpty($FullText) -and $ei -ge $si) {
            $eiCap = [Math]::Min($ei, $FullText.Length - 1)
            if ($eiCap -ge $si) {
                return $FullText.Substring($si, $eiCap - $si + 1)
            }
        }
    }
    return $null
}

function script:Test-AnchorRoleClientAddressOverlap {
    param(
        [string]$RawBlock,
        [string]$ClientName,
        [string]$AddressValue,
        [regex]$RxPostal,
        [string]$ClientNameMarker
    )
    if ([string]::IsNullOrWhiteSpace($RawBlock)) { return $false }
    if ([string]::IsNullOrWhiteSpace($ClientName)) { return $false }
    $cn = $ClientName.Trim()
    if ($cn.Length -lt 2) { return $false }

    $lines = @($RawBlock -split "`n", [System.StringSplitOptions]::None)
    foreach ($line in $lines) {
        # Ignorer les lignes d’en-tête client (N°…) : le \d{5} du numéro client n’est pas une adresse.
        if ($line.IndexOf($ClientNameMarker, [System.StringComparison]::Ordinal) -ge 0) { continue }
        if (-not $RxPostal.IsMatch($line)) { continue }
        if ($line.IndexOf($cn, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }
    return $false
}

function Resolve-AnchorRoles {
    <#
    .SYNOPSIS
        Attribue des rôles sémantiques aux champs issus de l’extraction et du scoring (BestMatch Address/Date).

    .PARAMETER Blocks
        Sortie Build-AnchorBlocks (RawTextBlock / indices).

    .PARAMETER ScoredAnchors
        Une ligne par bloc client : mêmes propriétés que Extract-AnchorEntities
        (ClientBlockId, ClientName, ClientId, WorkOrders, Address, Date) avec Address/Date = résultats BestMatch.

    .PARAMETER Text
        Texte normalisé complet (repli RawTextBlock).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Blocks,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$ScoredAnchors,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    Write-Verbose 'Resolve-AnchorRoles: début.'

    $sPostal = Get-AnchorPattern -Type AddressPattern -Verbose:$false
    $marker = Get-AnchorPattern -Type ClientNamePattern -Verbose:$false
    $rxPostal = [regex]::new($sPostal)

    $out = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $ScoredAnchors) {
        if ($null -eq $row) { continue }
        $cid = [int]$row.ClientBlockId
        if ($cid -eq 0) { continue }

        $cn = [string]$row.ClientName
        $cidStr = [string]$row.ClientId
        $wos = @($row.WorkOrders)
        $addr = [string]$row.Address
        $dt = [string]$row.Date

        $raw = Get-AnchorRoleResolverBlockRaw -Blocks $Blocks -ClientBlockId $cid -FullText $Text

        $overlap = $false
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $overlap = Test-AnchorRoleClientAddressOverlap -RawBlock $raw -ClientName $cn -AddressValue $addr -RxPostal $rxPostal -ClientNameMarker $marker
            if ($overlap) {
                Write-Verbose "Resolve-AnchorRoles: conflit de rôle détecté (ClientName / Address sur une même ligne physique) — ClientBlockId=$cid."
                Write-Warning "Resolve-AnchorRoles [ClientBlockId=$cid]: chevauchement ClientName / Address — conserver les valeurs amont ; vérifier la mise en page."
            }
        }

        $roles = [ordered]@{
            ClientName = @{ Role = 'HeaderEntity'; Value = $cn }
            ClientId   = @{ Role = 'IdentifierEntity'; Value = $cidStr }
            Address    = @{ Role = 'AddressEntity'; Value = $addr }
            Date       = @{ Role = 'TimeEntity'; Value = $dt }
            WorkOrders = @{ Role = 'WorkOrderListEntity'; Value = $wos }
        }

        Write-Verbose "Resolve-AnchorRoles: ClientBlockId=$cid — ROLE(HeaderEntity) ← ClientName"
        Write-Verbose "Resolve-AnchorRoles: ClientBlockId=$cid — ROLE(IdentifierEntity) ← ClientId"
        Write-Verbose "Resolve-AnchorRoles: ClientBlockId=$cid — ROLE(AddressEntity) ← Address"
        Write-Verbose "Resolve-AnchorRoles: ClientBlockId=$cid — ROLE(TimeEntity) ← Date"
        Write-Verbose "Resolve-AnchorRoles: ClientBlockId=$cid — ROLE(WorkOrderListEntity) ← WorkOrders ($($wos.Count) entrée(s))"

        $out.Add([pscustomobject]@{
            ClientBlockId = $cid
            Roles         = $roles
        })
    }

    Write-Verbose "Resolve-AnchorRoles: fin — $($out.Count) bloc(s) résolu(s)."
    return $out.ToArray()
}

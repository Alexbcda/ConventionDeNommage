# ============================================================
# ManualResolution.ps1
# Correction manuelle des décisions REVIEW / REJECT (hors moteur automatique).
# ============================================================

function script:Normalize-ManualDecisionStatus {
    param([string]$Value)
    $t = ([string]$Value).Trim().ToUpperInvariant()
    switch ($t) {
        'OK' { return 'OK' }
        'REVIEW' { return 'REVIEW' }
        'REJECT' { return 'REJECT' }
        default { throw "Statut invalide pour résolution manuelle : '$Value' (attendu : OK, REVIEW, REJECT)." }
    }
}

function script:Get-ManualResolutionEntityLabel {
    param(
        [int]$ClientBlockId,
        [object[]]$Entities
    )
    if ($null -eq $Entities -or $Entities.Count -eq 0) { return '' }
    $ent = @(
        $Entities |
            Where-Object { $null -ne $_ -and [int]$_.ClientBlockId -eq $ClientBlockId } |
            Select-Object -First 1
    )
    if ($ent.Count -eq 0) { return '' }
    $e = $ent[0]
    $cid = ''
    if ($null -ne $e.PSObject.Properties['ClientId'] -and -not [string]::IsNullOrWhiteSpace([string]$e.ClientId)) {
        $cid = ([string]$e.ClientId).Trim()
    }
    $cn = ''
    if ($null -ne $e.PSObject.Properties['ClientName'] -and -not [string]::IsNullOrWhiteSpace([string]$e.ClientName)) {
        $cn = ([string]$e.ClientName).Trim()
    }
    if ($cid -ne '' -and $cn -ne '') { return "ClientId=$cid ; $cn" }
    if ($cid -ne '') { return "ClientId=$cid" }
    if ($cn -ne '') { return $cn }
    return ''
}

function Resolve-ManualDecisions {
    <#
    .SYNOPSIS
        Permet de corriger les statuts REVIEW / REJECT (console interactive et/ou surcharges).

    .PARAMETER Decisions
        Sortie Resolve-EntityDecision (ClientBlockId, ConfidenceScore, Status).

    .PARAMETER Entities
        Optionnel : entités extraites pour afficher un libellé (ClientId / ClientName) en mode interactif.

    .PARAMETER Interactive
        Si présent : invite pour chaque ligne encore en REVIEW ou REJECT après application des surcharges.

    .PARAMETER StatusOverrides
        Table [ClientBlockId] = 'OK' | 'REVIEW' | 'REJECT' — clés int ou string numérique.

    .OUTPUTS
        Nouvelles lignes décision (ClientBlockId, ConfidenceScore, Status, ResolutionSource).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Decisions,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]]$Entities = @(),

        [Parameter(Mandatory = $false)]
        [switch]$Interactive,

        [Parameter(Mandatory = $false)]
        [hashtable]$StatusOverrides
    )

    Write-Verbose "Resolve-ManualDecisions: début — $($Decisions.Count) décision(s) ; Interactive=$Interactive."

    $overrideTable = @{}
    if ($null -ne $StatusOverrides) {
        foreach ($key in $StatusOverrides.Keys) {
            $id = 0
            if ($key -is [int] -or $key -is [long]) {
                $id = [int]$key
            }
            else {
                $ks = ([string]$key).Trim()
                if (-not [int]::TryParse($ks, [ref]$id)) {
                    throw "Resolve-ManualDecisions: clé de surcharge invalide (ClientBlockId attendu) : '$key'."
                }
            }
            $overrideTable[$id] = Normalize-ManualDecisionStatus -Value ([string]$StatusOverrides[$key])
        }
    }

    $out = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $Decisions) {
        if ($null -eq $row) { continue }

        $cb = [int]$row.ClientBlockId
        $score = [int]$row.ConfidenceScore
        $status = [string]$row.Status
        $source = 'Automatic'

        if ($overrideTable.ContainsKey($cb)) {
            $status = $overrideTable[$cb]
            $source = 'Override'
            Write-Verbose "Resolve-ManualDecisions: ClientBlockId=$cb — surcharge -> $status."
        }

        $out.Add([pscustomobject]@{
            ClientBlockId     = $cb
            ConfidenceScore   = $score
            Status            = $status
            ResolutionSource  = $source
        })
    }

    if ($Interactive) {
        $updated = [System.Collections.Generic.List[object]]::new()
        foreach ($row in $out) {
            $st = [string]$row.Status
            if ($st -cne 'REVIEW' -and $st -cne 'REJECT') {
                [void]$updated.Add($row)
                continue
            }

            $cb = [int]$row.ClientBlockId
            $label = Get-ManualResolutionEntityLabel -ClientBlockId $cb -Entities $Entities
            $hint = if ($label -ne '') { " — $label" } else { '' }

            Write-Host ""
            Write-Host ("ClientBlockId={0}{1}" -f $cb, $hint) -ForegroundColor Cyan
            Write-Host ("  Score={0}  Statut actuel={1}" -f $row.ConfidenceScore, $row.Status) -ForegroundColor DarkGray
            Write-Host "  Nouveau statut : OK | REVIEW | REJECT | (Entrée = conserver)" -ForegroundColor Yellow

            $line = Read-Host "  >"
            if ($null -eq $line) { $line = '' }
            $line = $line.Trim()

            if ($line -eq '') {
                [void]$updated.Add($row)
                Write-Verbose "Resolve-ManualDecisions: ClientBlockId=$cb — conservé ($st)."
                continue
            }

            try {
                $newSt = Normalize-ManualDecisionStatus -Value $line
            }
            catch {
                Write-Warning $_.Exception.Message
                [void]$updated.Add($row)
                continue
            }

            [void]$updated.Add([pscustomobject]@{
                ClientBlockId     = $cb
                ConfidenceScore   = $row.ConfidenceScore
                Status            = $newSt
                ResolutionSource  = 'Interactive'
            })
            Write-Verbose "Resolve-ManualDecisions: ClientBlockId=$cb — interactif -> $newSt."
        }
        $out = $updated
    }

    $arr = @($out.ToArray())
    Write-Verbose "Resolve-ManualDecisions: fin — $($arr.Count) décision(s)."
    return $arr
}

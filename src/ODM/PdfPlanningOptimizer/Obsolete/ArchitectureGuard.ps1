# ============================================================
# ArchitectureGuard.ps1
# Verrou d’architecture : EntityTourneeMergeEngine est la seule voie de fusion supportée.
# Variables globales : Etme_MergeCallDepth (EntityTourneeMergeEngine), Etme_GuardMode (STRICT | TRACE).
# ============================================================

if ($null -eq (Get-Variable -Scope Global -Name Etme_MergeCallDepth -ErrorAction SilentlyContinue)) {
    $global:Etme_MergeCallDepth = 0
}

if ($null -eq (Get-Variable -Scope Global -Name Etme_GuardMode -ErrorAction SilentlyContinue)) {
    $global:Etme_GuardMode = 'STRICT'
}

function script:Get-EtmeGuardMode {
    $m = 'STRICT'
    if ($null -ne (Get-Variable -Scope Global -Name Etme_GuardMode -ErrorAction SilentlyContinue)) {
        $v = [string]$global:Etme_GuardMode
        if ($v -eq 'TRACE') {
            $m = 'TRACE'
        }
    }
    return $m
}

function Get-EtmeGuardStatus {
    <#
    .SYNOPSIS
        État courant du ArchitectureGuard (mode, profondeur Merge) — lecture seule, sans effet de bord.

    .NOTES
        Contrat stable Get-EtmeGuardStatus — version 1.
        Propriétés garanties pour compatibilité ascendante des consommateurs : Mode (string), MergeDepth (int),
        IsStrict (bool), IsTrace (bool). Ne pas renommer ni supprimer sans bump de version documenté dans
        docs/ArchitectureGuard.md. Toute propriété additive exige la même mise à jour documentaire.
    #>
    [CmdletBinding()]
    param()

    $mode = Get-EtmeGuardMode
    $depth = 0
    if ($null -ne (Get-Variable -Scope Global -Name Etme_MergeCallDepth -ErrorAction SilentlyContinue)) {
        $depth = [int]$global:Etme_MergeCallDepth
    }

    return [pscustomobject]@{
        Mode       = $mode
        MergeDepth = $depth
        IsStrict   = ($mode -eq 'STRICT')
        IsTrace    = ($mode -eq 'TRACE')
    }
}

function script:Get-EtmeInfrastructureScriptLeafNames {
    return @(
        'ArchitectureGuard.ps1'
        'EntityTourneeMergeEngine.ps1'
    )
}

function script:Get-EtmeFirstStackFrameOutsideMergeInfrastructure {
    $infra = Get-EtmeInfrastructureScriptLeafNames
    foreach ($f in (Get-PSCallStack)) {
        if ($null -eq $f.ScriptName -or [string]::IsNullOrWhiteSpace($f.ScriptName)) {
            continue
        }
        $leaf = Split-Path -Leaf $f.ScriptName
        if ($infra -contains $leaf) {
            continue
        }
        return $f
    }
    return $null
}

function Assert-NoDirectLegacyCall {
    <#
    .SYNOPSIS
        Contrôle les invocations « legacy » hors Merge-EntityTournees lorsque Etme_MergeCallDepth = 0 (tests, instrumentation).
        Les modules Final* sont neutralisés et n’utilisent pas ce guard. Mode STRICT : throw. Mode TRACE : Verbose uniquement.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LegacyCommandName
    )

    $stackText = Get-PSCallStack | Out-String
    Write-Verbose "ArchitectureGuard [Assert-NoDirectLegacyCall] full stack for '${LegacyCommandName}':`n${stackText}"

    $firstOutside = Get-EtmeFirstStackFrameOutsideMergeInfrastructure
    if ($null -ne $firstOutside) {
        $line = $firstOutside.ScriptLineNumber
        $fn = $firstOutside.FunctionName
        if ([string]::IsNullOrWhiteSpace($fn) -and $null -ne $firstOutside.PSObject.Properties['Command']) {
            $fn = [string]$firstOutside.Command
        }
        Write-Verbose ("ArchitectureGuard: first call site outside MergeEngine infrastructure — Function={0}, Script={1}, Line={2}" -f $fn, $firstOutside.ScriptName, $line)
    }
    else {
        Write-Verbose 'ArchitectureGuard: no stack frame found outside MergeEngine infrastructure (unexpected).'
    }

    $depth = 0
    if ($null -ne (Get-Variable -Scope Global -Name Etme_MergeCallDepth -ErrorAction SilentlyContinue)) {
        $depth = [int]$global:Etme_MergeCallDepth
    }

    if ($depth -gt 0) {
        Write-Verbose "ArchitectureGuard: legacy '${LegacyCommandName}' invoked with Etme_MergeCallDepth=${depth} (Merge-EntityTournees active) — unexpected; see stacks above."
        return
    }

    $mode = Get-EtmeGuardMode
    if ($mode -eq 'TRACE') {
        Write-Verbose "ArchitectureGuard: Etme_GuardMode=TRACE — no throw for direct legacy '${LegacyCommandName}' (see stacks above)."
        return
    }

    throw 'Illegal direct legacy invocation outside Merge context'
}

function Assert-UseMergeEngineOnly {
    <#
    .SYNOPSIS
        Délègue à Assert-NoDirectLegacyCall (compatibilité des anciens appels).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LegacyCommandName
    )

    Assert-NoDirectLegacyCall -LegacyCommandName $LegacyCommandName @PSBoundParameters
}

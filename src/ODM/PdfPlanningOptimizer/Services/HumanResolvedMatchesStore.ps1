# ============================================================
# HumanResolvedMatchesStore.ps1
# Journal d'événements append-only (persistance optionnelle) → replay vers ResolvedMatches.
# Format de sortie identique au contrat Merge-EntityTournees / HumanMergeAdapter.
# Aucune logique métier, aucun scoring, aucun parsing Excel/PDF.
# Aucune dépendance aux autres scripts du dépôt.
# ============================================================

$script:Hrms_EventSchemaVersion = 2
$script:Hrms_ActionSetResolvedStop = 'SetResolvedStop'
$script:Hrms_ActionClearResolvedStop = 'ClearResolvedStop'

# Métadonnées de sortie replay (hors schéma événement v2) — couche de contrat déterministe.
$script:Hrms_HumanReplayContractVersion = 1

function script:Hrms-HashFileSha256Hex {
    param([string]$LiteralPath)
    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        return 'MISSING'
    }
    $bytes = [System.IO.File]::ReadAllBytes($LiteralPath)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $h = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($h) -replace '-', '')
    }
    finally {
        if ($null -ne $sha) { $sha.Dispose() }
    }
}

function script:Hrms-GetEngineVersionFingerprint {
    $etme = Join-Path $PSScriptRoot 'EntityTourneeMergeEngine.ps1'
    $fre = Join-Path $PSScriptRoot 'FieldResolutionEngine.ps1'
    if (-not (Test-Path -LiteralPath $etme)) {
        throw "HumanResolvedMatchesStore: EntityTourneeMergeEngine.ps1 introuvable pour empreinte replay: $etme"
    }
    if (-not (Test-Path -LiteralPath $fre)) {
        throw "HumanResolvedMatchesStore: FieldResolutionEngine.ps1 introuvable pour empreinte replay: $fre"
    }
    $he = Hrms-HashFileSha256Hex -LiteralPath $etme
    $hf = Hrms-HashFileSha256Hex -LiteralPath $fre
    return ('ETME={0};FRE={1}' -f $he, $hf)
}

function script:Hrms-AttachReplayContractMetadata {
    param(
        [object]$Row,
        [string]$EngineVersionFingerprint
    )
    $o = [ordered]@{}
    foreach ($p in $Row.PSObject.Properties) {
        if ($p.MemberType -ne 'NoteProperty' -and $p.MemberType -ne 'Property') { continue }
        $o[$p.Name] = $p.Value
    }
    $o['ReplayContractVersion'] = [int]$script:Hrms_HumanReplayContractVersion
    $o['EngineVersion'] = [string]$EngineVersionFingerprint
    return [pscustomobject]$o
}

function script:Hrms-ValidateHumanReplayOutputContract {
    param(
        [AllowEmptyCollection()]
        [object[]]$Rows,
        [string]$ExpectedEngineFingerprint
    )
    foreach ($r in @($Rows)) {
        if ($null -eq $r) { continue }
        if ($null -eq $r.PSObject.Properties['ReplayContractVersion']) {
            throw 'HumanResolvedMatchesStore: sortie replay sans ReplayContractVersion (contrat v1).'
        }
        if ([int]$r.ReplayContractVersion -ne [int]$script:Hrms_HumanReplayContractVersion) {
            throw ('HumanResolvedMatchesStore: ReplayContractVersion inattendu: {0}' -f $r.ReplayContractVersion)
        }
        if ($null -eq $r.PSObject.Properties['EngineVersion']) {
            throw 'HumanResolvedMatchesStore: sortie replay sans EngineVersion.'
        }
        $ev = [string]$r.EngineVersion
        if ($ev -cne $ExpectedEngineFingerprint) {
            throw "HumanResolvedMatchesStore: EngineVersion replay does not match expected engine fingerprint."
        }
    }
}

function script:Hrms-GetRepositoryRoot {
    $p = $PSScriptRoot
    for ($i = 0; $i -lt 4; $i++) {
        $p = [System.IO.Path]::GetDirectoryName($p)
    }
    return $p
}

function script:Hrms-GetDefaultEventLogPath {
    return (Join-Path (Hrms-GetRepositoryRoot) 'Data\human_events.jsonl')
}

function script:Hrms-EnsureParentDirectory {
    param([string]$FilePath)
    if ([string]::IsNullOrWhiteSpace($FilePath)) { return }
    $dir = [System.IO.Path]::GetDirectoryName($FilePath)
    if ([string]::IsNullOrWhiteSpace($dir)) { return }
    if (-not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -LiteralPath $dir -Force)
    }
}

function script:Hrms-DeepCloneViaJson {
    param([object]$Object)
    if ($null -eq $Object) { return $null }
    return ($Object | ConvertTo-Json -Depth 40 -Compress | ConvertFrom-Json)
}

function script:Hrms-EntryToPersistedRecord {
    param(
        [string]$TourneeId,
        [int]$Position,
        [object]$FinalEntity,
        [string]$ResolutionSource,
        [string]$UserId,
        [object]$Timestamp,
        [string]$OriginalStatus,
        [string]$ExcelWorkOrder,
        [string]$ExcelClientId
    )
    $feJson = $null
    if ($null -ne $FinalEntity) {
        $feJson = Hrms-DeepCloneViaJson -Object $FinalEntity
    }
    $ts = $Timestamp
    if ($null -eq $ts) {
        $ts = [datetime]::UtcNow
    }
    if ($ts -isnot [datetime]) {
        $ts = [datetime]$ts
    }
    $rec = [ordered]@{
        TourneeId        = [string]$TourneeId
        Position         = [int]$Position
        FinalEntity      = $feJson
        ResolutionSource = if ($null -eq $ResolutionSource) { '' } else { [string]$ResolutionSource }
        UserId             = if ($null -eq $UserId) { $null } else { [string]$UserId }
        UtcSaved           = $ts.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if (-not [string]::IsNullOrWhiteSpace($OriginalStatus)) {
        $rec['OriginalStatus'] = [string]$OriginalStatus
    }
    if (-not [string]::IsNullOrWhiteSpace($ExcelWorkOrder)) {
        $rec['ExcelWorkOrder'] = [string]$ExcelWorkOrder
    }
    if ($null -ne $ExcelClientId -and '' -ne [string]$ExcelClientId) {
        $rec['ExcelClientId'] = [string]$ExcelClientId
    }
    return [pscustomobject]$rec
}

function script:Hrms-PersistedRecordToResolvedMatch {
    param([object]$Record)
    $fe = $Record.FinalEntity
    $out = [ordered]@{
        TourneeId          = [string]$Record.TourneeId
        Position           = [int]$Record.Position
        FinalEntity        = $fe
        ResolutionSource   = [string]$Record.ResolutionSource
    }
    if ($null -ne $Record.PSObject.Properties['OriginalStatus']) {
        $out['OriginalStatus'] = [string]$Record.OriginalStatus
    }
    if ($null -ne $Record.PSObject.Properties['ExcelWorkOrder']) {
        $out['ExcelWorkOrder'] = [string]$Record.ExcelWorkOrder
    }
    if ($null -ne $Record.PSObject.Properties['ExcelClientId']) {
        $out['ExcelClientId'] = [string]$Record.ExcelClientId
    }
    if ($null -ne $Record.PSObject.Properties['UserId']) {
        $out['UserId'] = $Record.UserId
    }
    if ($null -ne $Record.PSObject.Properties['UtcSaved']) {
        $out['UtcSaved'] = [string]$Record.UtcSaved
    }
    return [pscustomobject]$out
}

function script:Hrms-GetProp {
    param(
        [object]$Object,
        [string[]]$Names
    )
    if ($null -eq $Object) { return $null }
    foreach ($n in $Names) {
        $p = $Object.PSObject.Properties[$n]
        if ($null -ne $p) { return $p.Value }
    }
    return $null
}

function script:Hrms-ParseTimestamp {
    param([object]$Raw)
    if ($null -eq $Raw) { return [datetime]::MinValue }
    if ($Raw -is [datetime]) { return $Raw.ToUniversalTime() }
    $s = [string]$Raw
    if ([string]::IsNullOrWhiteSpace($s)) { return [datetime]::MinValue }
    return [datetime]::Parse($s, $null, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)
}

function script:Hrms-ReadEventLines {
    param([string]$StorePath)
    if (-not (Test-Path -LiteralPath $StorePath)) {
        return @()
    }
    $raw = [System.IO.File]::ReadAllLines($StorePath, [System.Text.UTF8Encoding]::new($false))
    return @($raw)
}

function script:Hrms-ParseEventLine {
    param(
        [string]$Line,
        [int]$LineIndex
    )
    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
    $e = $Line | ConvertFrom-Json
    Add-Member -InputObject $e -NotePropertyName '_LineIndex' -NotePropertyValue $LineIndex -Force
    return $e
}

function script:Hrms-NormalizeEventObject {
    param([object]$Event)
    if ($null -eq $Event) { return $null }
    $action = [string](Hrms-GetProp -Object $Event -Names @('Action', 'action'))
    $tid = [string](Hrms-GetProp -Object $Event -Names @('TourneeId', 'tourneeId'))
    $pos = Hrms-GetProp -Object $Event -Names @('Position', 'position')
    $posI = if ($null -eq $pos) { 0 } else { [int]$pos }
    $val = Hrms-GetProp -Object $Event -Names @('Value', 'value')
    $uid = Hrms-GetProp -Object $Event -Names @('UserId', 'userId')
    $ts = Hrms-GetProp -Object $Event -Names @('Timestamp', 'timestamp')
    $lineIx = Hrms-GetProp -Object $Event -Names @('_LineIndex', '_lineIndex')
    if ($null -eq $lineIx) { $lineIx = 0 } else { $lineIx = [int]$lineIx }
    return [pscustomobject]@{
        Action     = $action
        TourneeId  = $tid
        Position   = $posI
        Value      = $val
        UserId     = $uid
        Timestamp  = $ts
        _LineIndex = $lineIx
    }
}

function script:Hrms-SortEventsDeterministic {
    param([object[]]$Events)
    if ($null -eq $Events -or @($Events).Count -eq 0) {
        return @()
    }
    $norm = foreach ($ev in @($Events)) {
        if ($null -eq $ev) { continue }
        $n = Hrms-NormalizeEventObject -Event $ev
        $dt = Hrms-ParseTimestamp -Raw $n.Timestamp
        [pscustomobject]@{
            Raw        = $ev
            Norm       = $n
            SortTime   = $dt.Ticks
            TourneeId  = [string]$n.TourneeId
            Position   = [int]$n.Position
            LineIndex  = [int]$n._LineIndex
        }
    }
    return @(
        $norm | Sort-Object -Property @{ Expression = 'SortTime'; Ascending = $true },
        @{ Expression = 'TourneeId'; Ascending = $true },
        @{ Expression = 'Position'; Ascending = $true },
        @{ Expression = 'LineIndex'; Ascending = $true }
    )
}

function script:Hrms-ValueToPersistedFields {
    param([object]$Value)
    if ($null -eq $Value) {
        return @{
            FinalEntity        = $null
            ResolutionSource   = ''
            OriginalStatus     = $null
            ExcelWorkOrder     = $null
            ExcelClientId      = $null
        }
    }
    $fe = Hrms-GetProp -Object $Value -Names @('FinalEntity', 'finalEntity')
    $rs = Hrms-GetProp -Object $Value -Names @('ResolutionSource', 'resolutionSource')
    $os = Hrms-GetProp -Object $Value -Names @('OriginalStatus', 'originalStatus')
    $ew = Hrms-GetProp -Object $Value -Names @('ExcelWorkOrder', 'excelWorkOrder')
    $ec = Hrms-GetProp -Object $Value -Names @('ExcelClientId', 'excelClientId')
    return @{
        FinalEntity        = $fe
        ResolutionSource   = if ($null -eq $rs) { '' } else { [string]$rs }
        OriginalStatus     = $os
        ExcelWorkOrder     = $ew
        ExcelClientId      = $ec
    }
}

function script:Hrms-EventToPersistedRecord {
    param([object]$Event)
    $n = Hrms-NormalizeEventObject -Event $Event
    $ts = Hrms-ParseTimestamp -Raw $n.Timestamp
    $vf = Hrms-ValueToPersistedFields -Value $n.Value
    return (Hrms-EntryToPersistedRecord `
            -TourneeId $n.TourneeId `
            -Position $n.Position `
            -FinalEntity $vf.FinalEntity `
            -ResolutionSource $vf.ResolutionSource `
            -UserId $n.UserId `
            -Timestamp $ts `
            -OriginalStatus $(if ($null -eq $vf.OriginalStatus) { $null } else { [string]$vf.OriginalStatus }) `
            -ExcelWorkOrder $(if ($null -eq $vf.ExcelWorkOrder) { $null } else { [string]$vf.ExcelWorkOrder }) `
            -ExcelClientId $vf.ExcelClientId)
}

function Append-HumanEvent {
    <#
    .SYNOPSIS
        Ajoute un événement immuable au journal (append-only JSONL).

    .PARAMETER Action
        SetResolvedStop | ClearResolvedStop

    .PARAMETER Value
        Pour SetResolvedStop : objet avec FinalEntity, ResolutionSource, optionnellement OriginalStatus, ExcelWorkOrder, ExcelClientId.
        Ignoré pour ClearResolvedStop (peut être $null).

    .NOTES
        Si -Value est absent, les paramètres plats FinalEntity, ResolutionSource, etc. construisent Value (compatibilité API précédente).
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByValue')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('SetResolvedStop', 'ClearResolvedStop')]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [string]$TourneeId,

        [Parameter(Mandatory = $true)]
        [int]$Position,

        [Parameter(Mandatory = $false, ParameterSetName = 'ByValue')]
        [object]$Value,

        [Parameter(Mandatory = $false, ParameterSetName = 'Flat')]
        [object]$FinalEntity,

        [Parameter(Mandatory = $false, ParameterSetName = 'Flat')]
        [AllowEmptyString()]
        [string]$ResolutionSource,

        [Parameter(Mandatory = $false, ParameterSetName = 'Flat')]
        [string]$OriginalStatus,

        [Parameter(Mandatory = $false, ParameterSetName = 'Flat')]
        [string]$ExcelWorkOrder,

        [Parameter(Mandatory = $false, ParameterSetName = 'Flat')]
        [string]$ExcelClientId,

        [Parameter(Mandatory = $false)]
        [string]$UserId,

        [Parameter(Mandatory = $false)]
        [object]$Timestamp,

        [Parameter(Mandatory = $false)]
        [string]$StorePath
    )

    $path = if (-not [string]::IsNullOrWhiteSpace($StorePath)) { $StorePath } else { Hrms-GetDefaultEventLogPath }

    $ts = $null
    if ($null -ne $PSBoundParameters['Timestamp']) {
        $ts = $Timestamp
    }
    if ($null -eq $ts) {
        $ts = [datetime]::UtcNow
    }
    if ($ts -isnot [datetime]) {
        $ts = [datetime]$ts
    }
    $tsIso = $ts.ToUniversalTime().ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)

    $uid = $null
    if ($null -ne $PSBoundParameters['UserId']) {
        $uid = $UserId
    }

    $valOut = $null
    if ($Action -eq 'ClearResolvedStop') {
        $valOut = $null
    }
    elseif ($Action -eq 'SetResolvedStop') {
        if ($PSCmdlet.ParameterSetName -eq 'Flat') {
            $valOut = [ordered]@{}
            if ($null -ne $PSBoundParameters['FinalEntity']) {
                $valOut['FinalEntity'] = Hrms-DeepCloneViaJson -Object $FinalEntity
            }
            else {
                $valOut['FinalEntity'] = $null
            }
            $valOut['ResolutionSource'] = if ($null -eq $ResolutionSource) { '' } else { [string]$ResolutionSource }
            if (-not [string]::IsNullOrWhiteSpace($OriginalStatus)) {
                $valOut['OriginalStatus'] = [string]$OriginalStatus
            }
            if (-not [string]::IsNullOrWhiteSpace($ExcelWorkOrder)) {
                $valOut['ExcelWorkOrder'] = [string]$ExcelWorkOrder
            }
            if ($null -ne $ExcelClientId -and '' -ne [string]$ExcelClientId) {
                $valOut['ExcelClientId'] = [string]$ExcelClientId
            }
            $valOut = [pscustomobject]$valOut
        }
        else {
            if ($null -eq $Value) {
                throw "Append-HumanEvent: -Value requis pour Action=SetResolvedStop (jeu ByValue)."
            }
            $valOut = Hrms-DeepCloneViaJson -Object $Value
        }
    }

    $evt = [ordered]@{
        schemaVersion = $script:Hrms_EventSchemaVersion
        Action        = $Action
        TourneeId     = [string]$TourneeId
        Position      = [int]$Position
        Value         = $valOut
        UserId        = $uid
        Timestamp     = $tsIso
    }
    $line = ([pscustomobject]$evt | ConvertTo-Json -Depth 40 -Compress)
    Hrms-EnsureParentDirectory -FilePath $path
    $enc = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::AppendAllText($path, $line + [Environment]::NewLine, $enc)
}

function Get-HumanEvents {
    <#
    .SYNOPSIS
        Retourne tous les événements du journal, triés de façon déterministe (Timestamp, TourneeId, Position, ordre fichier).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$StorePath
    )

    $path = if (-not [string]::IsNullOrWhiteSpace($StorePath)) { $StorePath } else { Hrms-GetDefaultEventLogPath }
    $lines = Hrms-ReadEventLines -StorePath $path
    $parsed = [System.Collections.Generic.List[object]]::new()
    $i = 0
    foreach ($ln in $lines) {
        $p = Hrms-ParseEventLine -Line $ln -LineIndex $i
        if ($null -ne $p) {
            [void]$parsed.Add($p)
        }
        $i++
    }
    $sortedWrappers = Hrms-SortEventsDeterministic -Events @($parsed.ToArray())
    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($w in $sortedWrappers) {
        [void]$out.Add($w.Norm)
    }
    return @($out.ToArray())
}

function Rebuild-HumanResolvedState {
    <#
    .SYNOPSIS
        Rejoue le journal et produit la liste ResolvedMatches (meme contrat que l ancien Load-HumanResolvedMatches).

    .DESCRIPTION
        Dernier evenement SetResolvedStop par cle TourneeId|Position l emporte ; ClearResolvedStop supprime la cle.
        Ordre des lignes : TourneeId puis Position (deterministe).
        Chaque ligne inclut ReplayContractVersion = 1 et EngineVersion (empreinte SHA256 des fichiers
        EntityTourneeMergeEngine.ps1 + FieldResolutionEngine.ps1), validée avant retour.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$StorePath
    )

    $engineFp = Hrms-GetEngineVersionFingerprint

    $path = if (-not [string]::IsNullOrWhiteSpace($StorePath)) { $StorePath } else { Hrms-GetDefaultEventLogPath }
    $lines = Hrms-ReadEventLines -StorePath $path
    $parsed = [System.Collections.Generic.List[object]]::new()
    $i = 0
    foreach ($ln in $lines) {
        $p = Hrms-ParseEventLine -Line $ln -LineIndex $i
        if ($null -ne $p) {
            [void]$parsed.Add($p)
        }
        $i++
    }
    $sortedWrappers = Hrms-SortEventsDeterministic -Events @($parsed.ToArray())
    $state = @{}
    foreach ($w in $sortedWrappers) {
        $ev = $w.Norm
        if ($null -eq $ev) { continue }
        $action = [string]$ev.Action
        $k = "$([string]$ev.TourneeId)|$([int]$ev.Position)"
        switch ($action) {
            $script:Hrms_ActionSetResolvedStop {
                $state[$k] = $w.Raw
            }
            $script:Hrms_ActionClearResolvedStop {
                if ($state.ContainsKey($k)) {
                    $state.Remove($k)
                }
            }
        }
    }

    $keyTuples = foreach ($k in @($state.Keys)) {
        $parts = $k -split '\|', 2
        [pscustomobject]@{ Key = $k; T = [string]$parts[0]; P = [int]$parts[1] }
    }
    $sortedKeys = @($keyTuples | Sort-Object -Property @{ Expression = 'T'; Ascending = $true }, @{ Expression = 'P'; Ascending = $true })

    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($kt in $sortedKeys) {
        $rawEv = $state[$kt.Key]
        $rec = Hrms-EventToPersistedRecord -Event $rawEv
        $row = Hrms-PersistedRecordToResolvedMatch -Record $rec
        [void]$list.Add((Hrms-AttachReplayContractMetadata -Row $row -EngineVersionFingerprint $engineFp))
    }
    $out = @($list.ToArray())
    Hrms-ValidateHumanReplayOutputContract -Rows $out -ExpectedEngineFingerprint $engineFp
    return $out
}

function Get-HumanResolvedMatchesStorePath {
    <#
    .SYNOPSIS
        Chemin par defaut du journal d evenements (JSONL). Alias historique store.
    #>
    [CmdletBinding()]
    param()
    return Hrms-GetDefaultEventLogPath
}

function Get-HumanEventLogPath {
    <#
    .SYNOPSIS
        Chemin par défaut du fichier human_events.jsonl.
    #>
    [CmdletBinding()]
    param()
    return Hrms-GetDefaultEventLogPath
}

function Get-HumanReplayEngineFingerprint {
    <#
    .SYNOPSIS
        Empreinte déterministe des fichiers EntityTourneeMergeEngine.ps1 et FieldResolutionEngine.ps1 (SHA256).

    .NOTES
        Doit correspondre au champ EngineVersion sur chaque ligne retournée par Rebuild-HumanResolvedState.
    #>
    [CmdletBinding()]
    param()
    return Hrms-GetEngineVersionFingerprint
}

function Get-HumanReplayContractVersion {
    <#
    .SYNOPSIS
        Version du contrat de métadonnées replay (entier fixe porté sur chaque ligne Rebuild-HumanResolvedState).
    #>
    [CmdletBinding()]
    param()
    return [int]$script:Hrms_HumanReplayContractVersion
}

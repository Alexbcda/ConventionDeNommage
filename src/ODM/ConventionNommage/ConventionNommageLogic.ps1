# ConventionNommageLogic.ps1 — Renommage PDF : sécurité production, chemins longs, anti–race condition
#
# OWASP : pas d’Invoke-Expression ; entrées = données ; renommage confiné au dossier du PDF source.
# SQLite : requêtes paramétrées dans Database.ps1 (hors fichier).

. (Join-Path $PSScriptRoot '..\..\Common\DesktopSecurity.ps1')
. (Join-Path $PSScriptRoot '..\..\Common\TextEncoding.ps1')
if (-not (Get-Command Convert-ToUiText -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\..\Common\UiText.ps1')
}

$script:CN_MaxRawInputLength = 4096
$script:CN_MaxSanitizedLength = 100
$script:CN_MaxTemplatesJsonBytes = 262144  # 256 KiB
$script:CN_AllowedTemplateIds = @('certificat', 'planner', 'france-travail')
$script:CN_MaxCollisionAttempts = 100000
$script:CN_MoveMaxAttempts = 3
$script:CN_MoveRetryDelayMs = 50
# Win32 : ERROR_FILE_EXISTS=80, ERROR_ALREADY_EXISTS=183
$script:CN_Win32CollisionCodes = @(80, 183)
# Erreurs système : ne pas confondre avec une collision (pas de boucle d’index)
$script:CN_Win32FatalCodes = @(112, 3, 161, 123, 206, 21, 15, 111, 55, 145)
# Transitoires : verrou / partage — retry Move uniquement
$script:CN_Win32TransientCodes = @(32, 33)

<#
.SYNOPSIS
  Extrait un code d’erreur Win32 depuis la chaîne d’exceptions (IOException.HResult FACILITY_WIN32 ou Win32Exception).
#>
function Get-CNWin32ErrorCodeFromException {
    param([System.Exception]$Exception)
    $ex = $Exception
    while ($null -ne $ex) {
        if ($ex -is [System.ComponentModel.Win32Exception]) {
            return [int]$ex.NativeErrorCode
        }
        try {
            $hr = $ex.HResult
            # FACILITY_WIN32 : 0x8007xxxx — code Win32 dans les 16 bits bas
            if (($hr -band 0xFFFF0000) -eq [int]0x80070000) {
                return [int]($hr -band 0xFFFF)
            }
        }
        catch { }
        $ex = $ex.InnerException
    }
    return $null
}

function Test-IsFileCollisionException {
    param([System.Exception]$Exception)
    $code = Get-CNWin32ErrorCodeFromException -Exception $Exception
    if ($null -ne $code) {
        return ($code -in $script:CN_Win32CollisionCodes)
    }
    return $false
}

function Test-IsFatalSystemIOException {
    param([System.Exception]$Exception)
    $code = Get-CNWin32ErrorCodeFromException -Exception $Exception
    if ($null -ne $code) {
        return ($code -in $script:CN_Win32FatalCodes)
    }
    return $false
}

function Test-IsTransientWin32ErrorForMoveRetry {
    param([System.Exception]$Exception)
    $code = Get-CNWin32ErrorCodeFromException -Exception $Exception
    if ($null -ne $code) {
        return ($code -in $script:CN_Win32TransientCodes)
    }
    return $false
}

<#
.SYNOPSIS
  Valide dateFormat pour DateTime.ToString : uniquement yyyy, MM, dd et séparateurs . - / (et espaces).
#>
function Test-CNDateFormat {
    param([string]$DateFormat)
    if ([string]::IsNullOrWhiteSpace($DateFormat)) { return $false }
    $df = $DateFormat.Trim()
    if ($df.Length -gt 32) { return $false }
    if ($df -cmatch '[^yMd\.\-\/ ]') { return $false }
    if ($df -cnotmatch 'yyyy') { return $false }
    if ($df -cnotmatch 'MM') { return $false }
    if ($df -cnotmatch 'dd') { return $false }
    $rem = $df
    while ($rem.Contains('yyyy')) { $rem = $rem.Replace('yyyy', '') }
    while ($rem.Contains('MM')) { $rem = $rem.Replace('MM', '') }
    while ($rem.Contains('dd')) { $rem = $rem.Replace('dd', '') }
    $rem = $rem -replace '[\.\-\/ ]', ''
    if ($rem.Length -gt 0) { return $false }
    try {
        $sample = [datetime]::new(2026, 6, 15)
        $formatted = $sample.ToString($df)
        if ($formatted.Length -gt 64) { return $false }
    }
    catch {
        return $false
    }
    return $true
}

function Write-CNErrorLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [System.Exception]$Exception = $null,
        [string]$Context = ''
    )
    try {
        $logDir = Join-Path $PSScriptRoot '..\..\..\Logs'
        if (-not (Test-Path -LiteralPath $logDir -PathType Container)) {
            $null = New-Item -Path $logDir -ItemType Directory -Force -ErrorAction SilentlyContinue
        }
        $logFile = Join-Path $logDir 'ConventionNommage-errors.log'
        Rotate-LogIfNeeded -LogFile $logFile
        $ts = [datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss.fff')
        $hrText = ''
        if ($null -ne $Exception) {
            try {
                $hrText = ' HResult=0x{0:X8}' -f $Exception.HResult
            }
            catch { }
            $w32 = Get-CNWin32ErrorCodeFromException -Exception $Exception
            if ($null -ne $w32) {
                $hrText += " Win32=$w32"
            }
        }
        $ctx = if ([string]::IsNullOrWhiteSpace($Context)) { '' } else { " | $Context" }
        $line = "[$ts] [pid=$PID] $Message$hrText$ctx"
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($null -ne $Exception) {
            $detail = $Exception.ToString()
            Add-Content -LiteralPath $logFile -Value $detail -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    }
    catch { }
}

function Invoke-CNFileMoveOnce {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    $src = $LiteralPath
    $dst = $Destination
    if ($src.Length -ge 260 -or $dst.Length -ge 260) {
        $src = Get-CNLongPathFull -Path $src
        $dst = Get-CNLongPathFull -Path $dst
    }
    [System.IO.File]::Move($src, $dst)
}

function Get-ConventionNomReferenceDate {
    $today = [datetime]::Today
    switch ($today.DayOfWeek) {
        'Monday' { return $today.AddDays(-3) }
        { $_ -in 'Tuesday', 'Wednesday', 'Thursday', 'Friday' } { return $today.AddDays(-1) }
        default { return $today.AddDays(-1) }
    }
}

function Remove-StringDiacritics {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $normalized.ToCharArray()) {
        $cat = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($cat -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString().Normalize([Text.NormalizationForm]::FormC)
}

function Test-WindowsReservedFileStem {
    param([string]$Stem)
    if ([string]::IsNullOrWhiteSpace($Stem)) { return $false }
    $u = $Stem.Trim().ToUpperInvariant()
    $reserved = @(
        'CON', 'PRN', 'AUX', 'NUL'
    ) + (1..9 | ForEach-Object { "COM$_" }) + (1..9 | ForEach-Object { "LPT$_" })
    return ($u -in $reserved)
}

<#
.SYNOPSIS
  Sanitization idempotente : segment de nom de fichier = lettres, chiffres, espace, tiret uniquement.
  Supprime Cf (invisibles), contrôles, séquences dangereuses, points début/fin ; NFD + sans accents.
#>
function Sanitize-PointDeCollecte {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Text
    )

    if ($null -eq $Text) {
        throw [System.ArgumentException]::new('Veuillez saisir le point de collecte')
    }
    if ($Text.Length -gt $script:CN_MaxRawInputLength) {
        throw [System.ArgumentException]::new('Saisie trop longue.')
    }

    $t = $Text.Trim()
    if ([string]::IsNullOrWhiteSpace($t)) {
        throw [System.ArgumentException]::new('Veuillez saisir le point de collecte')
    }

    # Contrôles ASCII + Unicode Cf (caractères de format / invisibles)
    $t = $t -replace "[\x00-\x1F\x7F]", ''
    try {
        $t = [regex]::Replace($t, '\p{Cf}', '', [System.Text.RegularExpressions.RegexOptions]::None)
    }
    catch { }

    while ($t.Contains('..')) {
        $t = $t.Replace('..', '')
    }

    foreach ($ch in @('$', [char]0x60, ';', '&', '|', '(', ')')) {
        $t = $t.Replace([string]$ch, '')
    }

    $t = $t -replace '[\\/:*?"<>|]', ''
    $t = Remove-StringDiacritics -Text $t

    # Autorisé : lettres, chiffres, espace, tiret (aucun autre symbole)
    $t = $t -replace '[^a-zA-Z0-9 \-]', ''
    $t = ($t -replace '\s+', ' ').Trim()

    while ($t.Length -gt 0 -and $t[0] -eq '.') { $t = $t.TrimStart('.').Trim() }
    while ($t.Length -gt 0 -and $t[$t.Length - 1] -eq '.') { $t = $t.TrimEnd('.').Trim() }

    if ($t.Length -gt $script:CN_MaxSanitizedLength) {
        $t = $t.Substring(0, $script:CN_MaxSanitizedLength).TrimEnd()
    }

    if ([string]::IsNullOrWhiteSpace($t)) {
        throw [System.ArgumentException]::new(
            'Le point de collecte ne contient aucun caractère utilisable après nettoyage.'
        )
    }

    if (Test-WindowsReservedFileStem -Stem $t) {
        $t = 'X-' + $t
        if ($t.Length -gt $script:CN_MaxSanitizedLength) {
            $t = $t.Substring(0, $script:CN_MaxSanitizedLength).TrimEnd()
        }
    }

    return $t
}

function Get-CNLongPathFull {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full.StartsWith('\\?\', [System.StringComparison]::Ordinal)) { return $full }
    if ($full.Length -lt 260) { return $full }
    if ($full.StartsWith('\\')) {
        return '\\?\UNC\' + $full.Substring(2)
    }
    return '\\?\' + $full
}

function Move-ItemWithLongPathSupport {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    for ($attempt = 1; $attempt -le $script:CN_MoveMaxAttempts; $attempt++) {
        try {
            Invoke-CNFileMoveOnce -LiteralPath $LiteralPath -Destination $Destination
            return
        }
        catch {
            $ex = $_.Exception
            if ($attempt -lt $script:CN_MoveMaxAttempts -and (Test-IsTransientWin32ErrorForMoveRetry -Exception $ex)) {
                Write-CNErrorLog -Message 'Move retry (transient lock)' -Exception $ex -Context "attempt=$attempt/$($script:CN_MoveMaxAttempts)"
                Start-Sleep -Milliseconds $script:CN_MoveRetryDelayMs
                continue
            }
            # Collision fichier existant : bruit attendu dans Resolve-FileNameCollision — pas de log erreur
            if (-not (Test-IsFileCollisionException -Exception $ex)) {
                Write-CNErrorLog -Message 'Move failed' -Exception $ex -Context "attempt=$attempt/$($script:CN_MoveMaxAttempts)"
            }
            throw
        }
    }
}

<#
.SYNOPSIS
  Déplace le fichier existant vers base(n).ext par tentatives successives (anti race : pas de décision sur Test-Path seul).
#>
function Resolve-FileNameCollision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath
    )

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        return
    }

    $dir = [System.IO.Path]::GetDirectoryName($LiteralPath)
    $leaf = [System.IO.Path]::GetFileName($LiteralPath)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($leaf)
    $ext = [System.IO.Path]::GetExtension($leaf)

    $i = 1
    while ($i -le $script:CN_MaxCollisionAttempts) {
        $candidateLeaf = '{0}({1}){2}' -f $base, $i, $ext
        $candidateFull = [System.IO.Path]::Combine($dir, $candidateLeaf)

        try {
            Move-ItemWithLongPathSupport -LiteralPath $LiteralPath -Destination $candidateFull
            return
        }
        catch [System.UnauthorizedAccessException] {
            Write-CNErrorLog -Message 'Resolve collision: access denied' -Exception $_.Exception -Context $LiteralPath
            throw [System.IO.IOException]::new('Accès refusé lors du déplacement du fichier en conflit.', $_.Exception)
        }
        catch {
            $ex = $_.Exception
            if (Test-IsFileCollisionException -Exception $ex) {
                $i++
                continue
            }
            if (Test-IsFatalSystemIOException -Exception $ex) {
                Write-CNErrorLog -Message 'Resolve collision: fatal I/O' -Exception $ex -Context $LiteralPath
                throw [System.IO.IOException]::new("Erreur disque ou chemin d'accès.", $ex)
            }
            if ($ex -is [System.IO.IOException]) {
                Write-CNErrorLog -Message 'Resolve collision: non-collision I/O' -Exception $ex -Context "i=$i $LiteralPath"
                throw [System.IO.IOException]::new('Impossible de déplacer le fichier en conflit.', $ex)
            }
            Write-CNErrorLog -Message 'Resolve collision: unexpected' -Exception $ex -Context $LiteralPath
            throw
        }
    }

    throw [System.IO.IOException]::new('Impossible de résoudre la collision de fichiers.')
}

function Test-CNTargetPathIsSafe {
    param(
        [string]$SourceFile,
        [string]$TargetFullPath
    )
    $srcDir = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($SourceFile))
    $destDir = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($TargetFullPath))
    return (
        [string]::Compare($srcDir, $destDir, [System.StringComparison]::OrdinalIgnoreCase) -eq 0
    )
}

function Test-CNFormatTemplateString {
    param([string]$Format)
    if ([string]::IsNullOrWhiteSpace($Format)) { return $false }
    if ($Format -match '[\\/]') { return $false }
    $tmp = $Format
    $tmp = $tmp.Replace('{text}', "`0").Replace('{date}', "`1")
    if ($tmp -match '[{}]') { return $false }
    if ($Format -notmatch '\{text\}' -or $Format -notmatch '\{date\}') { return $false }
    return $true
}

function Get-CNValidatedTemplates {
    param([string]$TemplatePath)

    if (-not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
        throw [System.IO.InvalidOperationException]::new('templates.json introuvable.')
    }

    $len = (Get-Item -LiteralPath $TemplatePath).Length
    if ($len -gt $script:CN_MaxTemplatesJsonBytes) {
        throw [System.IO.InvalidOperationException]::new('templates.json trop volumineux.')
    }

    $raw = Get-Content -LiteralPath $TemplatePath -Raw -Encoding UTF8
    if (Test-TextLikelyUtf8Mojibake -Text $raw) {
        $raw = Fix-Encoding -Text $raw
    }
    if ($raw.Length -gt $script:CN_MaxTemplatesJsonBytes) {
        throw [System.IO.InvalidOperationException]::new('templates.json trop volumineux.')
    }
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw [System.IO.InvalidOperationException]::new('Configuration des modèles vide.')
    }

    try {
        $json = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw [System.IO.InvalidOperationException]::new('Configuration des modèles illisible.')
    }

    if ($null -eq $json.templates) {
        throw [System.IO.InvalidOperationException]::new('Structure de configuration des modèles invalide.')
    }

    $list = @($json.templates)
    $out = @{}
    foreach ($tpl in $list) {
        if ($null -eq $tpl.id -or $tpl.id -isnot [string]) { continue }
        $id = [string]$tpl.id
        if ($id -notmatch '^[a-z0-9-]{1,48}$') { continue }
        if ($id -notin $script:CN_AllowedTemplateIds) { continue }
        if ($tpl.enabled -eq $false) { continue }
        if ($null -eq $tpl.format -or $tpl.format -isnot [string]) { continue }
        if ($null -eq $tpl.dateFormat -or $tpl.dateFormat -isnot [string]) { continue }

        $fmt = [string]$tpl.format
        $df = [string]$tpl.dateFormat
        if (Get-Command Convert-ToUiText -ErrorAction SilentlyContinue) {
            $fmt = Convert-ToUiText -Text $fmt
            $df = Convert-ToUiText -Text $df
        }
        if ($fmt -match '[\\/]') { continue }
        if ($fmt -notmatch '\{text\}' -or $fmt -notmatch '\{date\}') { continue }
        if ($fmt.Length -lt 3 -or $fmt.Length -gt 400) { continue }
        if ($df.Length -lt 2 -or $df.Length -gt 40) { continue }
        if (-not (Test-CNDateFormat -DateFormat $df)) { continue }
        if (-not (Test-CNFormatTemplateString -Format $fmt)) { continue }

        $out[$id] = @{
            format     = $fmt
            dateFormat = $df
        }
    }

    foreach ($req in $script:CN_AllowedTemplateIds) {
        if (-not $out.ContainsKey($req)) {
            throw [System.IO.InvalidOperationException]::new('Modèle de nommage incomplet.')
        }
    }

    return $out
}

function Invoke-CNRenameAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplateId,

        [Parameter(Mandatory = $true)]
        [string]$FichierPDF,

        [Parameter(Mandatory = $true)]
        [string]$UserText,

        [Parameter(Mandatory = $true)]
        [datetime]$DateSelectionnee
    )

    Test-CNRateLimit

    if ($TemplateId -notin $script:CN_AllowedTemplateIds) {
        throw [System.ArgumentException]::new('Modèle de renommage inconnu.')
    }

    if ([string]::IsNullOrWhiteSpace($FichierPDF)) {
        throw [System.ArgumentException]::new('Fichier PDF non spécifié.')
    }

    if (-not (Test-Path -LiteralPath $FichierPDF -PathType Leaf)) {
        throw [System.IO.FileNotFoundException]::new('Fichier PDF introuvable.')
    }

    $cleanText = Sanitize-PointDeCollecte -Text $UserText

    $templatePath = Join-Path $PSScriptRoot '..\..\..\Data\templates.json'
    $templates = Get-CNValidatedTemplates -TemplatePath $templatePath
    $template = $templates[$TemplateId]

    $formattedDate = $DateSelectionnee.ToString($template.dateFormat)
    $nouveauNom = $template.format.Replace('{text}', $cleanText).Replace('{date}', $formattedDate)
    if (-not $nouveauNom.EndsWith('.pdf', [System.StringComparison]::OrdinalIgnoreCase)) {
        $nouveauNom += '.pdf'
    }

    if ($nouveauNom -match '[\\/]' -or [System.IO.Path]::GetFileName($nouveauNom) -ne $nouveauNom) {
        throw [System.IO.InvalidOperationException]::new('Nom de fichier généré invalide.')
    }

    if ($nouveauNom.Length -gt 255) {
        throw [System.IO.InvalidOperationException]::new('Nom de fichier trop long.')
    }

    $dossier = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($FichierPDF))
    $nouveauChemin = [System.IO.Path]::Combine($dossier, $nouveauNom)

    if (-not (Test-CNTargetPathIsSafe -SourceFile $FichierPDF -TargetFullPath $nouveauChemin)) {
        throw [System.UnauthorizedAccessException]::new('Chemin de destination non autorisé.')
    }

    $srcFull = [System.IO.Path]::GetFullPath($FichierPDF)
    $dstFull = [System.IO.Path]::GetFullPath($nouveauChemin)
    if ($srcFull -eq $dstFull) {
        return $true
    }

    if (Test-Path -LiteralPath $nouveauChemin -PathType Leaf) {
        Resolve-FileNameCollision -LiteralPath $nouveauChemin
    }

    $destPath = [System.IO.Path]::Combine($dossier, $nouveauNom)
    try {
        Move-ItemWithLongPathSupport -LiteralPath $FichierPDF -Destination $destPath
    }
    catch {
        $ex = $_.Exception
        if (Test-IsFatalSystemIOException -Exception $ex) {
            Write-CNErrorLog -Message 'Invoke-CNRenameAction: fatal I/O' -Exception $ex -Context $FichierPDF
            throw [System.IO.IOException]::new('Impossible de renommer le fichier.', $ex)
        }
        if (Test-Path -LiteralPath $destPath -PathType Leaf) {
            Resolve-FileNameCollision -LiteralPath $destPath
            Move-ItemWithLongPathSupport -LiteralPath $FichierPDF -Destination $destPath
            return $true
        }
        Write-CNErrorLog -Message 'Invoke-CNRenameAction: rename failed' -Exception $ex -Context $FichierPDF
        throw [System.IO.IOException]::new('Impossible de renommer le fichier.', $ex)
    }

    return $true
}

# ConventionNommageHandlers.ps1 - Handlers WinForms au scope script (visibles depuis les evenements CLR)
# Chargé par ConventionNommage.ps1 après Logic, avant Panel.
#
# Dependances : si ce fichier est dot-source seul, on charge Logic + placeholder (pas de fonctions invisibles).
$CNHandlersDir = $PSScriptRoot
if (-not (Get-Command Invoke-CNRenameAction -ErrorAction SilentlyContinue)) {
    . (Join-Path $CNHandlersDir 'ConventionNommageLogic.ps1')
}
if (-not (Get-Command Get-WinFormsTextBoxUserText -ErrorAction SilentlyContinue)) {
    . (Join-Path $CNHandlersDir '..\..\Common\WinFormsPlaceholder.ps1')
}

# Initialisation une seule fois (plusieurs dot-sources : Main + GUI) - ne pas reecraser si deja defini.
if (-not (Get-Variable -Name CN_DebugClickMode -Scope Script -ErrorAction SilentlyContinue)) {
    $script:CN_DebugClickMode = $false
}
if (-not (Get-Variable -Name CN_ClickTestStopMode -Scope Script -ErrorAction SilentlyContinue)) {
    $script:CN_ClickTestStopMode = $false
}

function Write-CNDiagnosticLog {
    param([string]$Message)
    if ($script:CN_DebugClickMode) {
        Write-Host "[CN-DIAG] $Message" -ForegroundColor Cyan
    }
}

function Write-CNClickTrace {
    param([string]$Message)
    if ($null -ne $script:CN_ClickTraceTestLog) {
        [void]$script:CN_ClickTraceTestLog.Add($Message)
    }
    Write-Host $Message -ForegroundColor DarkCyan
}

<#
.SYNOPSIS
  MessageBox métier ; en test Pester, alimente $script:CN_UITestMessages au lieu d afficher une fenêtre modale.
#>
function Invoke-CNConventionNommageUserMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [string]$Caption = 'Convention de nommage',

        [System.Windows.Forms.MessageBoxButtons]$Buttons = [System.Windows.Forms.MessageBoxButtons]::OK,

        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::None
    )
    $uiText = $Text
    $uiCap = $Caption
    if (Get-Command Convert-ToUiText -ErrorAction SilentlyContinue) {
        $uiText = Convert-ToUiText -Text $Text
        $uiCap = Convert-ToUiText -Text $Caption
    }
    if ($null -ne $script:CN_UITestMessages) {
        [void]$script:CN_UITestMessages.Add([pscustomobject]@{
            Text    = $uiText
            Caption = $uiCap
            Icon    = $Icon.ToString()
        })
        return
    }
    [void][System.Windows.Forms.MessageBox]::Show($uiText, $uiCap, $Buttons, $Icon)
}

function Start-CNConventionNommageUiTestCapture {
    $script:CN_UITestMessages = [System.Collections.Generic.List[object]]::new()
    $script:CN_ClickTraceTestLog = [System.Collections.Generic.List[string]]::new()
}

function Clear-CNConventionNommageUiTestCapture {
    $script:CN_UITestMessages = $null
    $script:CN_ClickTraceTestLog = $null
}

function Get-CNClickButtonLabel {
    param([string]$TemplateId)
    switch ($TemplateId) {
        'certificat' { return 'Certificat' }
        'planner' { return 'Planner' }
        'france-travail' { return 'France Travail' }
        default { return $TemplateId }
    }
}

function Get-CNArgumentExceptionUserMessage {
    param([System.ArgumentException]$Exception)
    # Uniquement erreurs « métier » hors sanitization (la sanitization ne doit pas produire de message métier UI).
    switch ($Exception.Message) {
        'Modèle de renommage inconnu.' { return "Ce modèle de renommage n'est pas disponible." }
        'Fichier PDF non spécifié.' { return "Aucun fichier PDF valide n'est associé à cette fenêtre." }
        default { return $null }
    }
}

<#
.SYNOPSIS
  Retourne $true si au moins un gestionnaire est abonné à Click (liste d'événements WinForms).
#>
function Test-CNButtonClickHandlerAttached {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.Control]$Control
    )
    if ($null -eq $Control) { return $false }
    try {
        $tCtl = [System.Windows.Forms.Control]
        $flags = [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Static
        $fi = $tCtl.GetField('s_clickEvent', $flags)
        if ($null -eq $fi) { $fi = $tCtl.GetField('EventClick', $flags) }
        if ($null -eq $fi) { return $false }
        $key = $fi.GetValue($null)
        $tComp = [System.ComponentModel.Component]
        $pi = $tComp.GetProperty(
            'Events',
            [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance
        )
        if ($null -eq $pi) { return $false }
        $elist = $pi.GetValue($Control, $null)
        if ($null -eq $elist) { return $false }
        $handler = $elist[$key]
        return ($null -ne $handler)
    }
    catch {
        Write-CNDiagnosticLog "Test-CNButtonClickHandlerAttached: $($_.Exception.Message)"
        return $false
    }
}

function Get-ControlByNameSafe {
    param(
        [System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$Context = ''
    )
    if ($null -eq $Parent) {
        $msg = "Get-ControlByNameSafe: Parent est NULL ($Context) - controle '$Name'."
        Write-CNDiagnosticLog $msg
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-CNDiagnosticLog "Get-ControlByNameSafe: nom vide ($Context)."
        return $null
    }
    $found = @($Parent.Controls) | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $found) {
        $names = (@($Parent.Controls) | ForEach-Object { $_.Name }) -join ', '
        Write-CNDiagnosticLog "Get-ControlByNameSafe: '$Name' introuvable sous parent Hash=$($Parent.GetHashCode()) ($Context). Enfants: [$names]"
    }
    return $found
}

function Get-CNConventionNommagePanelFromControl {
    param([System.Windows.Forms.Control]$Sender)
    if ($null -eq $Sender) { return $null }
    $cur = $Sender
    while ($null -ne $cur) {
        if ($cur -is [System.Windows.Forms.Panel]) {
            foreach ($child in $cur.Controls) {
                if ($child -is [System.Windows.Forms.TextBox] -and $child.Name -eq 'txtCollecte') {
                    return [System.Windows.Forms.Panel]$cur
                }
            }
        }
        $cur = $cur.Parent
    }
    return $null
}

function Update-ForcedDateLabel {
    param(
        [System.Windows.Forms.DateTimePicker]$Picker
    )
    if ($null -eq $Picker) { return }
    $P = Get-CNConventionNommagePanelFromControl -Sender $Picker
    if ($null -eq $P -or $null -eq $P.Tag) { return }
    $ref = [datetime]$P.Tag.RefDate
    $label = Get-ControlByNameSafe -Parent $P -Name 'lblModeForce' -Context 'Update-ForcedDateLabel'
    if (-not $label) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'Erreur interne : controle lblModeForce introuvable sur le panneau.',
            'Convention de nommage',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }
    $forced = ($Picker.Value.Date -ne $ref.Date)
    $label.Visible = $forced
}

function Set-CNPanelButtonsEnabled {
    param(
        [System.Windows.Forms.Panel]$P,
        [bool]$Enabled
    )
    foreach ($c in $P.Controls) {
        if ($c -is [System.Windows.Forms.Button]) {
            $c.Enabled = $Enabled
        }
    }
}

function Invoke-CNConventionRenameClick {
    param(
        [System.Windows.Forms.Button]$Sender,
        [string]$TemplateId
    )
    $dbgLabel = switch ($TemplateId) {
        'certificat' { 'CERTIFICAT' }
        'planner' { 'PLANNER' }
        'france-travail' { 'FRANCE TRAVAIL' }
        default { $TemplateId }
    }

    # 1 - Preuve de clic (toujours en premier geste visible si debug / test)
    if ($script:CN_DebugClickMode -or $script:CN_ClickTestStopMode) {
        [void][System.Windows.Forms.MessageBox]::Show(
            "CLICK DETECTED: $dbgLabel",
            'CN - etape 1',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }

    Write-CNDiagnosticLog "HANDLER EXECUTED - TemplateId=$TemplateId"

    if ($null -eq $Sender) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'Erreur : Sender NULL - le gestionnaire na pas recu le bouton.',
            'CN - Sender',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }

    # 2 - Sender.Name
    $senderName = $Sender.Name
    if ([string]::IsNullOrWhiteSpace($senderName)) { $senderName = '(sans Name - definir btnCert/btnPlan/btnFT sur le panel)' }

    # 3 - Identite parent / panel resolu
    $p = Get-CNConventionNommagePanelFromControl -Sender $Sender
    $parentDirect = $Sender.Parent
    $hcResolved = if ($null -ne $p) { $p.GetHashCode() } else { -1 }
    $hcParent = if ($null -ne $parentDirect) { $parentDirect.GetHashCode() } else { -2 }

    $panelMismatch = $false
    if ($null -eq $p) {
        $panelMismatch = $true
    }
    elseif ($null -eq $parentDirect) {
        $panelMismatch = $true
    }
    elseif ($p -ne $parentDirect) {
        $panelMismatch = $true
    }
    elseif ($hcResolved -ne $hcParent) {
        $panelMismatch = $true
    }

    if ($panelMismatch) {
        [void][System.Windows.Forms.MessageBox]::Show(
            @(
                'UI INSTANCE MISMATCH'
                "Panel resolu (via txtCollecte) HashCode=$hcResolved"
                "Sender.Parent HashCode=$hcParent"
                "Reference identique: $($null -ne $p -and $null -ne $parentDirect -and ($p -eq $parentDirect))"
                "Sender.Name: $senderName"
            ) -join "`r`n",
            'CN - panel',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }

    if ($null -eq $p.Tag) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'Panel.Tag NULL - etat interne invalide.',
            'CN - Tag',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }

    # Rapport liaison (rempli au init panel dans Tag.EventAttachLog)
    $attachLog = [string]$p.Tag['EventAttachLog']
    if ([string]::IsNullOrWhiteSpace($attachLog)) {
        $attachLog = '(EventAttachLog absent - recharger ConventionNommage.ps1 / panel)'
    }

    $thisBtnAttached = Test-CNButtonClickHandlerAttached -Control $Sender
    if ($script:CN_DebugClickMode -or $script:CN_ClickTestStopMode) {
        [void][System.Windows.Forms.MessageBox]::Show(
            @(
                "Sender.Name: $senderName"
                "PANEL VALID - HashCode=$hcResolved"
                "$attachLog"
                "EVENT (reflexion sur ce bouton) attache: $thisBtnAttached"
                'HANDLER EXECUTED'
            ) -join "`r`n",
            'CN - etapes 2-3',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }

    # 4 - Scope fonctions (avant acces controles metier / rename)
    $cmdRename = Get-Command Invoke-CNRenameAction -ErrorAction SilentlyContinue
    $cmdSan = Get-Command Sanitize-PointDeCollecte -ErrorAction SilentlyContinue
    if (-not $cmdRename -or -not $cmdSan) {
        $miss = @()
        if (-not $cmdRename) { $miss += 'Invoke-CNRenameAction' }
        if (-not $cmdSan) { $miss += 'Sanitize-PointDeCollecte' }
        [void][System.Windows.Forms.MessageBox]::Show(
            ('MISSING FUNCTION AT RUNTIME:' + [Environment]::NewLine + ($miss -join [Environment]::NewLine)),
            'CN - scope',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }

    if ($p.Tag.RenamingNow) { return }

    # 5-6 - Controles obligatoires
    $txtRaw = Get-ControlByNameSafe -Parent $p -Name 'txtCollecte' -Context 'Invoke-CNConventionRenameClick'
    $dtRaw = Get-ControlByNameSafe -Parent $p -Name 'datePicker' -Context 'Invoke-CNConventionRenameClick'
    if (-not $txtRaw) {
        [void][System.Windows.Forms.MessageBox]::Show(
            "CONTROLE NULL : txtCollecte introuvable sur le panel (HashCode=$hcResolved). Voir console [CN-DIAG].",
            'CN - controle',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }
    if (-not $dtRaw) {
        [void][System.Windows.Forms.MessageBox]::Show(
            "CONTROLE NULL : datePicker introuvable sur le panel (HashCode=$hcResolved). Voir console [CN-DIAG].",
            'CN - controle',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }
    $txt = [System.Windows.Forms.TextBox]$txtRaw
    $dt = [System.Windows.Forms.DateTimePicker]$dtRaw

    if ($script:CN_DebugClickMode -or $script:CN_ClickTestStopMode) {
        [void][System.Windows.Forms.MessageBox]::Show(
            @(
                'CONTROLES OK'
                "txtCollecte: type=$($txt.GetType().Name)"
                "datePicker: type=$($dt.GetType().Name)"
            ) -join "`r`n",
            'CN - etapes 4-5',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
    }

    if ($script:CN_ClickTestStopMode) {
        [void][System.Windows.Forms.MessageBox]::Show(
            "FIN MODE TEST - flux UI OK.`nInvoke-CNRenameAction non appele (CN_ClickTestStopMode).",
            'CN - stop test',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }

    # --- STEP 1 : lecture UI ---
    $userCollecte = Get-WinFormsTextBoxUserText -TextBox $txt
    $pdf = [string]$p.Tag.FichierPDF

    # --- STEP 2 : validation métier STRICTE (sans log [CLICK], sans sanitization) ---
    $collecteEmpty = [string]::IsNullOrWhiteSpace($userCollecte)
    if ($collecteEmpty) {
        Invoke-CNConventionNommageUserMessage -Text 'Renseigner le point de collecte.' -Caption 'Convention de nommage' -Icon Warning
        return
    }

    $pdfAttached = (-not [string]::IsNullOrWhiteSpace($pdf)) -and (Test-Path -LiteralPath $pdf -PathType Leaf)
    if (-not $pdfAttached) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[CN] PDF invalide au clic renommage' 'WARN' @{
                tagPdf   = [string]$pdf
                testPath = if ([string]::IsNullOrWhiteSpace($pdf)) { $false } else { Test-Path -LiteralPath $pdf -PathType Leaf }
            }
        }
        Invoke-CNConventionNommageUserMessage -Text "Aucun fichier PDF valide n'est associé à cette fenêtre." -Caption 'Convention de nommage' -Icon Warning
        return
    }

    $pdfPathDisplay = if ([string]::IsNullOrWhiteSpace($pdf)) { '(none)' } else { $pdf }
    $clickButtonLabel = Get-CNClickButtonLabel -TemplateId $TemplateId
    $collecteEmptyTag = if ($collecteEmpty) { 'True' } else { 'False' }
    $pdfAttachedTag = if ($pdfAttached) { 'True' } else { 'False' }
    Write-CNClickTrace "[CLICK] Button=$clickButtonLabel | CollecteEmpty=$collecteEmptyTag | PdfAttached=$pdfAttachedTag | PdfPath=$pdfPathDisplay"

    # --- STEP 3 : sanitization (aucun message métier depuis Sanitize ; erreur → message unique + log fichier) ---
    try {
        $null = Sanitize-PointDeCollecte -Text $userCollecte
    }
    catch {
        Write-CNErrorLog -Message 'Invoke-CNConventionRenameClick: sanitization' -Exception $_.Exception -Context 'RenameClick'
        Invoke-CNConventionNommageUserMessage -Text "La saisie n'a pas pu être traitée." -Caption 'Convention de nommage' -Icon Warning
        return
    }

    $p.Tag.RenamingNow = $true
    Set-CNPanelButtonsEnabled -P $p -Enabled $false
    $renameOk = $false
    Write-CNClickTrace "[CLICK] Button=$clickButtonLabel | Action=Invoke-CNRenameAction | PdfPath=$pdfPathDisplay"
    try {
        if ($script:CN_DebugClickMode) {
            [void][System.Windows.Forms.MessageBox]::Show(
                'RENAME CALL TRIGGERED - Invoke-CNRenameAction va sexecuter.',
                'CN - rename',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
        $null = Invoke-CNRenameAction -TemplateId $TemplateId -FichierPDF $pdf -UserText $userCollecte -DateSelectionnee $dt.Value
        $renameOk = $true
        $p.FindForm().Close()
    }
    catch {
        $ex = $_.Exception

        if ($ex.Message -eq "Trop d'actions. Veuillez patienter.") {
            Invoke-CNConventionNommageUserMessage -Text $ex.Message -Caption 'Convention de nommage' -Icon Warning
            return
        }

        if ($ex -is [System.ArgumentException]) {
            $argEx = [System.ArgumentException]$ex
            $userMsg = Get-CNArgumentExceptionUserMessage -Exception $argEx
            if ($null -ne $userMsg) {
                Invoke-CNConventionNommageUserMessage -Text $userMsg -Caption 'Convention de nommage' -Icon Warning
                return
            }
            Write-CNErrorLog -Message 'Invoke-CNConventionRenameClick: ArgumentException' -Exception $argEx -Context 'RenameClick'
            Invoke-CNConventionNommageUserMessage -Text "La saisie n'a pas pu être traitée." -Caption 'Convention de nommage' -Icon Warning
            return
        }

        # FileNotFoundException dérive de IOException : à traiter avant le test IOException.
        if ($ex -is [System.IO.FileNotFoundException]) {
            Write-CNErrorLog -Message 'Invoke-CNConventionRenameClick: PDF introuvable' -Exception $ex -Context 'RenameClick'
            Invoke-CNConventionNommageUserMessage -Text "Aucun fichier PDF valide n'est associé à cette fenêtre." -Caption 'Convention de nommage' -Icon Warning
            return
        }

        if ($ex -is [System.IO.IOException]) {
            Write-CNErrorLog -Message 'Invoke-CNConventionRenameClick: I/O renommage' -Exception $ex -Context 'RenameClick'
            Invoke-CNConventionNommageUserMessage -Text "Erreur lors du renommage du fichier.`nLe fichier est peut-être utilisé ou le disque est plein." -Caption 'Erreur fichier' -Icon Error
            return
        }

        Write-CNErrorLog -Message 'Invoke-CNConventionRenameClick: exception non gérée' -Exception $ex -Context 'RenameClick'
        Invoke-CNConventionNommageUserMessage -Text "La saisie n'a pas pu être traitée." -Caption 'Convention de nommage' -Icon Warning
    }
    finally {
        if ($null -ne $p -and $null -ne $p.Tag) {
            $p.Tag.RenamingNow = $false
            if (-not $renameOk) {
                Set-CNPanelButtonsEnabled -P $p -Enabled $true
            }
        }
    }
}

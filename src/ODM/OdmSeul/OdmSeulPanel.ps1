# OdmSeulPanel.ps1 — Onglet « ODM Seul »
# Couleurs : littéraux FromArgb uniquement (pas de Get-OdmSeulUi / pas de $script:Couleur*).
# Fonctions : définies SANS préfixe script: — les handlers WinForms appellent Get-Xxx (pas script:Get-Xxx).

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

# Ancré au dotsource de CE fichier (fiable même si $PSScriptRoot change ensuite dans les handlers).
$script:OdmSeulPanelDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($script:OdmSeulPanelDir)) {
    $script:OdmSeulPanelDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

function Set-OdmSeulButtonLook {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Button]$Button,
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][System.Drawing.Color]$BorderColor,
        [Parameter(Mandatory = $true)][System.Drawing.Color]$BackColor,
        [Parameter(Mandatory = $true)][System.Drawing.Color]$ForeColor,
        [int]$Width = 180,
        [int]$Height = 40
    )
    $Button.Text = $Text
    $Button.Size = [System.Drawing.Size]::new($Width, $Height)
    $Button.FlatStyle = 'Flat'
    $Button.FlatAppearance.BorderSize = 2
    $Button.FlatAppearance.BorderColor = $BorderColor
    $Button.BackColor = $BackColor
    $Button.ForeColor = $ForeColor
    $Button.Font = [System.Drawing.Font]::new('Arial', 10, [System.Drawing.FontStyle]::Bold)
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Button.FlatAppearance.MouseOverBackColor = $BorderColor
    $Button.FlatAppearance.MouseDownBackColor = $BorderColor
}

function Ensure-OdmSeulDatabaseCommands {
    if ((Get-Command Get-Agents -ErrorAction SilentlyContinue) -and (Get-Command Get-Vehicules -ErrorAction SilentlyContinue)) {
        return $true
    }
    $db = Join-Path $PSScriptRoot '..\..\Database\Database.ps1'
    if (-not (Test-Path -LiteralPath $db)) { return $false }
    . $db
    return ((Get-Command Get-Agents -ErrorAction SilentlyContinue) -and (Get-Command Get-Vehicules -ErrorAction SilentlyContinue))
}

function Import-OdmSeulPs1ToScriptScope {
    <#
    .SYNOPSIS
        Dot-source un .ps1 puis promeut ses fonctions au scope script.
        1) Essaye « . fichier » (préserve $PSScriptRoot automatique dans les fonctions imbriquées).
        2) Si parse ANSI échoue (fichiers UTF-8 sans BOM, ex. PdfExtractor), recharge via ScriptBlock UTF-8.
    #>
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    if ([string]::IsNullOrWhiteSpace($LiteralPath)) { return $false }
    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) { return $false }
    $full = [System.IO.Path]::GetFullPath($LiteralPath)
    $dir = [System.IO.Path]::GetDirectoryName($full)
    $before = @{}
    Get-ChildItem -Path 'Function:' -ErrorAction SilentlyContinue | ForEach-Object { $before[$_.Name] = $true }

    $loaded = $false
    try {
        . $full
        $loaded = $true
    }
    catch {
        $loaded = $false
    }

    if (-not $loaded) {
        # Recharge via copie temporaire UTF-8 BOM dans le MÊME dossier :
        # $PSScriptRoot reste le dossier Extractors (chemins relatifs OK), contrairement à un ScriptBlock.
        $utf8 = New-Object System.Text.UTF8Encoding $false
        $text = [System.IO.File]::ReadAllText($full, $utf8)
        if ($text.Length -gt 0 -and [int][char]$text[0] -eq 0xFEFF) {
            $text = $text.Substring(1)
        }
        $utf8bom = New-Object System.Text.UTF8Encoding $true
        $tempBom = Join-Path $dir ('_odm_seul_utf8_' + [Guid]::NewGuid().ToString('N') + '.ps1')
        try {
            [System.IO.File]::WriteAllText($tempBom, $text, $utf8bom)
            . $tempBom
            $loaded = $true
        }
        catch {
            Write-Warning ("Import-OdmSeulPs1ToScriptScope UTF-8 BOM échoué ({0}): {1}" -f $full, $_.Exception.Message)
            return $false
        }
        finally {
            Remove-Item -LiteralPath $tempBom -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $loaded) { return $false }

    Get-ChildItem -Path 'Function:' -ErrorAction SilentlyContinue | ForEach-Object {
        $name = [string]$_.Name
        if ($before.ContainsKey($name)) { return }
        $leaf = $name
        if ($leaf.StartsWith('script:')) { $leaf = $leaf.Substring(7) }
        if ([string]::IsNullOrWhiteSpace($leaf) -or $leaf -eq 'script') { return }
        try {
            Set-Item -Path ("function:script:{0}" -f $leaf) -Value $_.ScriptBlock -Force
        }
        catch { }
    }
    return $true
}

function Ensure-OdmSeulPdfPipelineLoaded {
    $odmSeul_panelRoot = [string]$script:OdmSeulPanelDir
    if ([string]::IsNullOrWhiteSpace($odmSeul_panelRoot)) {
        return $false
    }
    $odmSeul_extractorsDir = [System.IO.Path]::GetFullPath((Join-Path $odmSeul_panelRoot '..\PdfPlanningOptimizer\Extractors'))
    $odmSeul_servicesDir = [System.IO.Path]::GetFullPath((Join-Path $odmSeul_panelRoot '..\PdfPlanningOptimizer\Services'))
    $odmSeul_pdfExt = [System.IO.Path]::Combine($odmSeul_extractorsDir, 'PdfExtractor.ps1')
    $odmSeul_entity = [System.IO.Path]::Combine($odmSeul_extractorsDir, 'EntityExtractor.ps1')
    $odmSeul_metier = [System.IO.Path]::Combine($odmSeul_servicesDir, 'CnsPdfMetierPrestation.ps1')

    if (-not (Get-Command Invoke-PdfExtraction -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($odmSeul_pdfExt) -or -not (Test-Path -LiteralPath $odmSeul_pdfExt)) { return $false }
        if (-not (Import-OdmSeulPs1ToScriptScope -LiteralPath $odmSeul_pdfExt)) { return $false }
    }
    if (-not (Get-Command ConvertTo-PageEntity -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($odmSeul_entity) -or -not (Test-Path -LiteralPath $odmSeul_entity)) { return $false }
        if (-not (Import-OdmSeulPs1ToScriptScope -LiteralPath $odmSeul_entity)) { return $false }
    }
    if (-not (Get-Command Test-CnsStep5FragSliceRequiresCeaDocument -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($odmSeul_metier) -or -not (Test-Path -LiteralPath $odmSeul_metier)) { return $false }
        if (-not (Import-OdmSeulPs1ToScriptScope -LiteralPath $odmSeul_metier)) { return $false }
    }
    return [bool](Get-Command Invoke-PdfExtraction -ErrorAction SilentlyContinue)
}

function Invoke-OdmSeulReadAndDetect {
    param(
        [Parameter(Mandatory = $true)][string]$PdfPath,
        [AllowNull()][scriptblock]$OnProgress = $null
    )

    $result = [pscustomobject]@{
        Ok      = $false
        Cea     = $false
        Cert    = $false
        Dac     = $false
        Ft      = $false
        Message = ''
        Pages   = 0
    }

    if (-not (Ensure-OdmSeulPdfPipelineLoaded)) {
        $result.Message = 'Pipeline PDF / détection métier introuvable.'
        return $result
    }

    $progressCb = {
        param($PageNumber, $TotalPages, $Detail)
        if ($null -ne $OnProgress) {
            try { & $OnProgress $PageNumber $TotalPages $Detail } catch { }
        }
        try { [System.Windows.Forms.Application]::DoEvents() } catch { }
    }

    $pdfData = $null
    try {
        $pdfData = Invoke-PdfExtraction -PdfPath $PdfPath -ProgressCallback $progressCb
    }
    catch {
        $result.Message = ("Extraction PDF échouée : {0}" -f $_.Exception.Message)
        return $result
    }

    if ($null -eq $pdfData -or $null -eq $pdfData.Pages -or @($pdfData.Pages).Count -lt 1) {
        $result.Message = 'Extraction PDF : aucune page.'
        return $result
    }
    if ($pdfData.PdfTextUnusable -and $pdfData.UserAbortMessage) {
        $result.Message = [string]$pdfData.UserAbortMessage
        return $result
    }

    $result.Pages = @($pdfData.Pages).Count
    $pageIndex = 0
    foreach ($page in @($pdfData.Pages)) {
        $pageIndex++
        try { [System.Windows.Forms.Application]::DoEvents() } catch { }

        $rawLines = @()
        if ($null -ne $page.PSObject.Properties['RawLines'] -and $null -ne $page.RawLines) {
            $rawLines = @($page.RawLines)
        }
        elseif ($null -ne $page.PSObject.Properties['Lines'] -and $null -ne $page.Lines) {
            $rawLines = @($page.Lines)
        }

        $pn = 1
        try { $pn = [int]$page.PageNumber } catch { $pn = $pageIndex }

        if ($null -ne $OnProgress) {
            try { & $OnProgress $pageIndex $result.Pages ("détection page {0}/{1}" -f $pageIndex, $result.Pages) } catch { }
        }

        try {
            if (Test-CnsStep5FragSliceRequiresCeaDocument -FragSlicePdfPath $PdfPath -PrecomputedRawLines $rawLines -RawPageNumOneBased $pn) {
                $result.Cea = $true
            }
        }
        catch { }

        try {
            if (Test-CnsStep5FragSliceRequiresBioDechetsDocument -FragSlicePdfPath $PdfPath -PrecomputedRawLines $rawLines -RawPageNumOneBased $pn) {
                $result.Dac = $true
            }
        }
        catch { }

        try {
            if (Test-CnsStep5FragSliceRequiresFtDocument -FragSlicePdfPath $PdfPath -PrecomputedRawLines $rawLines -RawPageNumOneBased $pn) {
                $result.Ft = $true
            }
        }
        catch { }

        $entity = $null
        try {
            $cnLines = @()
            if ($null -ne $page.PSObject.Properties['ClientNameLines'] -and $null -ne $page.ClientNameLines) {
                $cnLines = @($page.ClientNameLines)
            }
            $entity = ConvertTo-PageEntity -PageNumber $pn -Lines @($page.Lines) -ClientNameLines $cnLines
        }
        catch { $entity = $null }

        try {
            if ($null -ne $entity -and (Test-CnsPdfPageRequiresDestructionCertificate -PageEntity $entity -WorkOrderEntity $null)) {
                $result.Cert = $true
            }
            elseif (-not $result.Cert -and $rawLines.Count -gt 0 -and (Get-Command Test-CnsPdfTextLineIsDestructionPrestation -ErrorAction SilentlyContinue)) {
                foreach ($ln in $rawLines) {
                    if (Test-CnsPdfTextLineIsDestructionPrestation -Line ([string]$ln)) {
                        $result.Cert = $true
                        break
                    }
                }
            }
        }
        catch { }

        if ((Get-Command Get-CnsPdfPageMetierAnalysis -ErrorAction SilentlyContinue) -and ($null -ne $entity)) {
            try {
                $analysis = Get-CnsPdfPageMetierAnalysis -PageEntity $entity -WorkOrderEntity $null
                if ($analysis.RequiresDestructionCertificate) { $result.Cert = $true }
            }
            catch { }
        }
    }

    $hits = @()
    if ($result.Cea) { $hits += 'CEA' }
    if ($result.Cert) { $hits += 'Certificat' }
    if ($result.Dac) { $hits += 'DAC' }
    if ($result.Ft) { $hits += 'FT' }
    $result.Ok = $true
    if ($hits.Count -gt 0) {
        $result.Message = ('PDF lu ({0} page(s)) — détecté : {1}' -f $result.Pages, ($hits -join ', '))
    }
    else {
        $result.Message = ('PDF lu ({0} page(s)) — aucune fiche métier détectée.' -f $result.Pages)
    }
    return $result
}

function Update-OdmSeulGenerateEnabled {
    param([Parameter(Mandatory = $true)]$Context)
    if (-not $Context.ReadOk) {
        $Context.BtnGenerer.Enabled = $false
        return
    }
    $any = $Context.ChkCea.Checked -or $Context.ChkCert.Checked -or $Context.ChkDac.Checked -or $Context.ChkFt.Checked `
        -or $Context.ChkEntete.Checked -or $Context.ChkBilan.Checked
    $Context.BtnGenerer.Enabled = [bool]$any
}

function Show-OdmSeulGenerationInputDialog {
    <#
    .SYNOPSIS
        Popup : champs Entête (heure / collecteur / véhicule — non bloquants) + date dépôt DAC (obligatoire si NeedDac).
    #>
    param(
        [bool]$NeedEntete = $false,
        [bool]$NeedDac = $false
    )

    if (-not $NeedEntete -and -not $NeedDac) {
        return @{
            CollecteurLabel   = ''
            CollecteurId      = $null
            DateDepot         = $null
            VehiculeLabel     = ''
            VehiculeId        = $null
            HeurePriseService = ''
        }
    }

    $colorFond = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $colorVert = [System.Drawing.Color]::FromArgb(26, 159, 123)
    $colorBlanc = [System.Drawing.Color]::FromArgb(255, 255, 255)
    $colorTexte = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $colorTexteFonce = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $fontNormal = [System.Drawing.Font]::new('Arial', 10, [System.Drawing.FontStyle]::Regular)

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'Informations pour la génération'
    $form.StartPosition = 'CenterParent'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ShowInTaskbar = $false
    $form.BackColor = $colorFond

    $y = 16
    $agentIds = New-Object System.Collections.Generic.List[object]
    $vehiculeIds = New-Object System.Collections.Generic.List[object]
    $cboCollecteur = $null
    $cboVehicule = $null
    $dtpHeure = $null
    $dtpDate = $null

    if ($NeedEntete) {
        $lblH = [System.Windows.Forms.Label]::new()
        $lblH.Text = 'Heure de prise de service (facultatif)'
        $lblH.Font = $fontNormal
        $lblH.ForeColor = $colorTexte
        $lblH.Location = [System.Drawing.Point]::new(16, $y)
        $lblH.Size = [System.Drawing.Size]::new(320, 24)
        $form.Controls.Add($lblH)
        $y += 26

        $dtpHeure = [System.Windows.Forms.DateTimePicker]::new()
        $dtpHeure.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
        $dtpHeure.CustomFormat = 'HH:mm'
        $dtpHeure.ShowUpDown = $true
        $dtpHeure.ShowCheckBox = $true
        $dtpHeure.Checked = $false
        $dtpHeure.Font = $fontNormal
        $dtpHeure.Location = [System.Drawing.Point]::new(16, $y)
        $dtpHeure.Size = [System.Drawing.Size]::new(120, 28)
        $form.Controls.Add($dtpHeure)
        $y += 40

        $lblC = [System.Windows.Forms.Label]::new()
        $lblC.Text = 'Collecteur'
        $lblC.Font = $fontNormal
        $lblC.ForeColor = $colorTexte
        $lblC.Location = [System.Drawing.Point]::new(16, $y)
        $lblC.Size = [System.Drawing.Size]::new(120, 24)
        $form.Controls.Add($lblC)

        $cboCollecteur = [System.Windows.Forms.ComboBox]::new()
        $cboCollecteur.DropDownStyle = 'DropDownList'
        $cboCollecteur.Font = $fontNormal
        $cboCollecteur.Location = [System.Drawing.Point]::new(140, ($y - 2))
        $cboCollecteur.Size = [System.Drawing.Size]::new(360, 28)
        [void]$cboCollecteur.Items.Add('Aucun')
        [void]$agentIds.Add($null)
        if (Ensure-OdmSeulDatabaseCommands) {
            foreach ($a in @(Get-Agents)) {
                if ($null -eq $a) { continue }
                $prenom = ''; $nom = ''
                try { $prenom = ([string]$a.prenom).Trim() } catch { }
                try { $nom = ([string]$a.nom).Trim() } catch { }
                $label = ('{0} {1}' -f $prenom, $nom).Trim()
                if ([string]::IsNullOrWhiteSpace($label)) { continue }
                [void]$cboCollecteur.Items.Add($label)
                [void]$agentIds.Add($a.id)
            }
        }
        $cboCollecteur.SelectedIndex = 0
        $form.Controls.Add($cboCollecteur)
        $y += 40

        $lblV = [System.Windows.Forms.Label]::new()
        $lblV.Text = 'Véhicule'
        $lblV.Font = $fontNormal
        $lblV.ForeColor = $colorTexte
        $lblV.Location = [System.Drawing.Point]::new(16, $y)
        $lblV.Size = [System.Drawing.Size]::new(120, 24)
        $form.Controls.Add($lblV)

        $cboVehicule = [System.Windows.Forms.ComboBox]::new()
        $cboVehicule.DropDownStyle = 'DropDownList'
        $cboVehicule.Font = $fontNormal
        $cboVehicule.Location = [System.Drawing.Point]::new(140, ($y - 2))
        $cboVehicule.Size = [System.Drawing.Size]::new(360, 28)
        [void]$cboVehicule.Items.Add('Aucun')
        [void]$vehiculeIds.Add($null)
        if (Ensure-OdmSeulDatabaseCommands) {
            foreach ($v in @(Get-Vehicules)) {
                if ($null -eq $v) { continue }
                $parc = ''; $immat = ''; $id = $null
                try { $parc = ([string]$v.numero_parc).Trim() } catch { }
                try { $immat = ([string]$v.immatriculation).Trim() } catch { }
                try { $id = $v.id } catch { $id = $null }
                $label = ('{0} — {1}' -f $(if ($parc) { $parc } else { '?' }), $(if ($immat) { $immat } else { '?' }))
                [void]$cboVehicule.Items.Add($label)
                [void]$vehiculeIds.Add($id)
            }
        }
        $cboVehicule.SelectedIndex = 0
        $form.Controls.Add($cboVehicule)
        $y += 40
    }

    if ($NeedDac) {
        $lbl = [System.Windows.Forms.Label]::new()
        $lbl.Text = "Préciser date de dépôt à l'exutoire"
        $lbl.Font = $fontNormal
        $lbl.ForeColor = $colorTexte
        $lbl.Location = [System.Drawing.Point]::new(16, $y)
        $lbl.Size = [System.Drawing.Size]::new(360, 24)
        $form.Controls.Add($lbl)
        $y += 26

        $dtpDate = [System.Windows.Forms.DateTimePicker]::new()
        $dtpDate.Format = [System.Windows.Forms.DateTimePickerFormat]::Short
        $dtpDate.Font = $fontNormal
        $dtpDate.Location = [System.Drawing.Point]::new(16, $y)
        $dtpDate.Size = [System.Drawing.Size]::new(200, 28)
        $dtpDate.Value = [datetime]::Today
        $form.Controls.Add($dtpDate)
        $y += 40
    }

    $btnOk = [System.Windows.Forms.Button]::new()
    Set-OdmSeulButtonLook -Button $btnOk -Text 'Valider' `
        -BorderColor $colorVert -BackColor $colorBlanc -ForeColor $colorTexteFonce -Width 100 -Height 32
    $btnOk.Location = [System.Drawing.Point]::new(280, ($y + 12))
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($btnOk)

    $btnCancel = [System.Windows.Forms.Button]::new()
    Set-OdmSeulButtonLook -Button $btnCancel -Text 'Annuler' `
        -BorderColor $colorTexteFonce -BackColor $colorBlanc -ForeColor $colorTexteFonce -Width 100 -Height 32
    $btnCancel.Location = [System.Drawing.Point]::new(400, ($y + 12))
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($btnCancel)

    $form.ClientSize = [System.Drawing.Size]::new(560, ($y + 60))
    $form.AcceptButton = $btnOk
    $form.CancelButton = $btnCancel

    $dialogResult = $form.ShowDialog()
    if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
        $form.Dispose()
        return $null
    }

    $out = @{
        CollecteurLabel   = ''
        CollecteurId      = $null
        DateDepot         = $null
        VehiculeLabel     = ''
        VehiculeId        = $null
        HeurePriseService = ''
    }

    if ($NeedEntete) {
        if ($null -ne $dtpHeure -and $dtpHeure.Checked) {
            $out.HeurePriseService = $dtpHeure.Value.ToString('HH:mm')
        }
        if ($null -ne $cboCollecteur -and $cboCollecteur.SelectedIndex -gt 0) {
            $out.CollecteurLabel = [string]$cboCollecteur.SelectedItem
            $out.CollecteurId = $agentIds[$cboCollecteur.SelectedIndex]
        }
        if ($null -ne $cboVehicule -and $cboVehicule.SelectedIndex -gt 0) {
            $out.VehiculeLabel = [string]$cboVehicule.SelectedItem
            $out.VehiculeId = $vehiculeIds[$cboVehicule.SelectedIndex]
        }
    }
    if ($NeedDac -and $null -ne $dtpDate) {
        $out.DateDepot = [datetime]$dtpDate.Value.Date
    }

    $form.Dispose()
    return $out
}

function Show-OdmSeulPanel {
    # Couleurs littérales locales (jamais $null sous lazy-load)
    $colorFond = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $colorOrange = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $colorVert = [System.Drawing.Color]::FromArgb(26, 159, 123)
    $colorBleu = [System.Drawing.Color]::FromArgb(26, 106, 168)
    $colorBlanc = [System.Drawing.Color]::FromArgb(255, 255, 255)
    $colorTexte = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $colorTexteFonce = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $fontTitre = [System.Drawing.Font]::new('Arial', 18, [System.Drawing.FontStyle]::Bold)
    $fontGroupe = [System.Drawing.Font]::new('Arial', 12, [System.Drawing.FontStyle]::Bold)
    $fontNormal = [System.Drawing.Font]::new('Arial', 10, [System.Drawing.FontStyle]::Regular)

    $panel = [System.Windows.Forms.Panel]::new()
    $panel.Name = 'OdmSeulPanel'
    $panel.Dock = 'Fill'
    $panel.BackColor = $colorFond
    $panel.Padding = [System.Windows.Forms.Padding]::new(20)
    $panel.AutoScroll = $true

    # Composer (génération réelle) — dotsource + promotion script
    $composerPath = Join-Path $script:OdmSeulPanelDir 'OdmSeulComposer.ps1'
    if (-not (Get-Command Invoke-OdmSeulGeneration -ErrorAction SilentlyContinue)) {
        if (-not (Test-Path -LiteralPath $composerPath)) {
            throw ("OdmSeulComposer.ps1 introuvable : {0}" -f $composerPath)
        }
        if (-not (Import-OdmSeulPs1ToScriptScope -LiteralPath $composerPath)) {
            throw 'Échec chargement OdmSeulComposer.ps1'
        }
    }

    # Capturer les CommandInfo au moment de la construction (handlers WinForms = autre résolution de noms)
    $cmdSetBtn = Get-Command Set-OdmSeulButtonLook -CommandType Function -ErrorAction Stop
    $cmdRead = Get-Command Invoke-OdmSeulReadAndDetect -CommandType Function -ErrorAction Stop
    $cmdUpdateGen = Get-Command Update-OdmSeulGenerateEnabled -CommandType Function -ErrorAction Stop
    $cmdPopup = Get-Command Show-OdmSeulGenerationInputDialog -CommandType Function -ErrorAction Stop
    $cmdGenerate = Get-Command Invoke-OdmSeulGeneration -CommandType Function -ErrorAction Stop

    $ctx = @{
        PdfPath         = $null
        ReadOk          = $false
        Analysis        = $null
        CmdSetBtn       = $cmdSetBtn
        CmdRead         = $cmdRead
        CmdUpdateGen    = $cmdUpdateGen
        CmdPopup        = $cmdPopup
        CmdGenerate     = $cmdGenerate
        ColorVert       = $colorVert
        ColorBlanc      = $colorBlanc
        ColorTexte      = $colorTexte
        ColorOrange     = $colorOrange
        ColorTexteFonce = $colorTexteFonce
    }

    $lblTitle = [System.Windows.Forms.Label]::new()
    $lblTitle.Text = 'ODM Seul'
    $lblTitle.Font = $fontTitre
    $lblTitle.ForeColor = $colorOrange
    $lblTitle.Location = [System.Drawing.Point]::new(0, 0)
    $lblTitle.Size = [System.Drawing.Size]::new(700, 40)
    $panel.Controls.Add($lblTitle)

    $grpLoad = [System.Windows.Forms.GroupBox]::new()
    $grpLoad.Text = '1. Chargement ODM'
    $grpLoad.Font = $fontGroupe
    $grpLoad.ForeColor = $colorTexteFonce
    $grpLoad.Location = [System.Drawing.Point]::new(0, 50)
    $grpLoad.Size = [System.Drawing.Size]::new(900, 100)
    $grpLoad.Anchor = 'Top,Left,Right'

    $btnLoad = [System.Windows.Forms.Button]::new()
    $btnLoad.Name = 'btnOdmSeulLoad'
    Set-OdmSeulButtonLook -Button $btnLoad -Text "Charger l'ODM..." `
        -BorderColor $colorOrange -BackColor $colorBlanc -ForeColor $colorTexteFonce -Width 180 -Height 40
    $btnLoad.Location = [System.Drawing.Point]::new(12, 32)

    $lblPdf = [System.Windows.Forms.Label]::new()
    $lblPdf.Name = 'lblOdmSeulPdf'
    $lblPdf.Text = 'Aucun PDF sélectionné'
    $lblPdf.Font = $fontNormal
    $lblPdf.ForeColor = $colorTexte
    $lblPdf.Location = [System.Drawing.Point]::new(210, 28)
    $lblPdf.Size = [System.Drawing.Size]::new(670, 22)
    $lblPdf.Anchor = 'Top,Left,Right'

    $lblStatus = [System.Windows.Forms.Label]::new()
    $lblStatus.Name = 'lblOdmSeulStatus'
    $lblStatus.Text = ''
    $lblStatus.Font = $fontNormal
    $lblStatus.ForeColor = $colorTexte
    $lblStatus.Location = [System.Drawing.Point]::new(210, 54)
    $lblStatus.Size = [System.Drawing.Size]::new(670, 22)
    $lblStatus.Anchor = 'Top,Left,Right'

    $grpLoad.Controls.AddRange(@($btnLoad, $lblPdf, $lblStatus))
    $panel.Controls.Add($grpLoad)

    $grpFiches = [System.Windows.Forms.GroupBox]::new()
    $grpFiches.Text = 'Fiches métiers (détectées — décocher pour exclure)'
    $grpFiches.Font = $fontGroupe
    $grpFiches.ForeColor = $colorTexteFonce
    $grpFiches.Location = [System.Drawing.Point]::new(0, 165)
    $grpFiches.Size = [System.Drawing.Size]::new(900, 100)
    $grpFiches.Anchor = 'Top,Left,Right'
    $grpFiches.Enabled = $false

    $chkCea = [System.Windows.Forms.CheckBox]::new()
    $chkCea.Text = 'CEA Points de Collecte'
    $chkCea.Font = $fontNormal
    $chkCea.ForeColor = $colorTexte
    $chkCea.Location = [System.Drawing.Point]::new(16, 32)
    $chkCea.Size = [System.Drawing.Size]::new(280, 24)

    $chkCert = [System.Windows.Forms.CheckBox]::new()
    $chkCert.Text = 'Certificat de Destruction'
    $chkCert.Font = $fontNormal
    $chkCert.ForeColor = $colorTexte
    $chkCert.Location = [System.Drawing.Point]::new(310, 32)
    $chkCert.Size = [System.Drawing.Size]::new(280, 24)

    $chkDac = [System.Windows.Forms.CheckBox]::new()
    $chkDac.Text = 'DAC'
    $chkDac.Font = $fontNormal
    $chkDac.ForeColor = $colorTexte
    $chkDac.Location = [System.Drawing.Point]::new(16, 62)
    $chkDac.Size = [System.Drawing.Size]::new(280, 24)

    $chkFt = [System.Windows.Forms.CheckBox]::new()
    $chkFt.Text = 'Fiche Inventaire France Travail'
    $chkFt.Font = $fontNormal
    $chkFt.ForeColor = $colorTexte
    $chkFt.Location = [System.Drawing.Point]::new(310, 62)
    $chkFt.Size = [System.Drawing.Size]::new(320, 24)

    $grpFiches.Controls.AddRange(@($chkCea, $chkCert, $chkDac, $chkFt))
    $panel.Controls.Add($grpFiches)

    $grpOptions = [System.Windows.Forms.GroupBox]::new()
    $grpOptions.Text = '2. Options'
    $grpOptions.Font = $fontGroupe
    $grpOptions.ForeColor = $colorTexteFonce
    $grpOptions.Location = [System.Drawing.Point]::new(0, 280)
    $grpOptions.Size = [System.Drawing.Size]::new(900, 70)
    $grpOptions.Anchor = 'Top,Left,Right'
    $grpOptions.Enabled = $false

    $chkEntete = [System.Windows.Forms.CheckBox]::new()
    $chkEntete.Text = 'Insérer Entête'
    $chkEntete.Font = $fontNormal
    $chkEntete.ForeColor = $colorTexte
    $chkEntete.Location = [System.Drawing.Point]::new(16, 30)
    $chkEntete.Size = [System.Drawing.Size]::new(280, 24)

    $chkBilan = [System.Windows.Forms.CheckBox]::new()
    $chkBilan.Text = 'Insérer Bilan de collecte'
    $chkBilan.Font = $fontNormal
    $chkBilan.ForeColor = $colorTexte
    $chkBilan.Location = [System.Drawing.Point]::new(310, 30)
    $chkBilan.Size = [System.Drawing.Size]::new(280, 24)

    $grpOptions.Controls.AddRange(@($chkEntete, $chkBilan))
    $panel.Controls.Add($grpOptions)

    $progressBar = [System.Windows.Forms.ProgressBar]::new()
    $progressBar.Name = 'pbOdmSeulProgress'
    $progressBar.Location = [System.Drawing.Point]::new(0, 360)
    $progressBar.Size = [System.Drawing.Size]::new(900, 18)
    $progressBar.Anchor = 'Top,Left,Right'
    $progressBar.Style = 'Continuous'
    $progressBar.Minimum = 0
    $progressBar.Maximum = 100
    $progressBar.Value = 0
    $progressBar.Visible = $false
    $panel.Controls.Add($progressBar)

    $btnGenerer = [System.Windows.Forms.Button]::new()
    $btnGenerer.Name = 'btnOdmSeulGenerer'
    Set-OdmSeulButtonLook -Button $btnGenerer -Text 'Générer les documents' `
        -BorderColor $colorBleu -BackColor $colorBlanc -ForeColor $colorTexteFonce -Width 220 -Height 40
    $btnGenerer.Location = [System.Drawing.Point]::new(0, 388)
    $btnGenerer.Enabled = $false
    $panel.Controls.Add($btnGenerer)

    $ctx.BtnLoad = $btnLoad
    $ctx.LblPdf = $lblPdf
    $ctx.LblStatus = $lblStatus
    $ctx.ProgressBar = $progressBar
    $ctx.GrpFiches = $grpFiches
    $ctx.GrpOptions = $grpOptions
    $ctx.ChkCea = $chkCea
    $ctx.ChkCert = $chkCert
    $ctx.ChkDac = $chkDac
    $ctx.ChkFt = $chkFt
    $ctx.ChkEntete = $chkEntete
    $ctx.ChkBilan = $chkBilan
    $ctx.BtnGenerer = $btnGenerer
    $panel.Tag = $ctx

    $onChk = {
        param($sender, $e)
        $c = $panel.Tag
        & $c.CmdUpdateGen -Context $c
    }.GetNewClosure()
    foreach ($chk in @($chkCea, $chkCert, $chkDac, $chkFt, $chkEntete, $chkBilan)) {
        $chk.Add_CheckedChanged($onChk)
    }

    $btnLoad.Add_Click({
        param($sender, $e)
        $c = $panel.Tag

        $ofd = [System.Windows.Forms.OpenFileDialog]::new()
        $ofd.Filter = 'PDF (*.pdf)|*.pdf'
        $ofd.Title = "Charger l'ODM"
        $ofd.CheckFileExists = $true
        if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

        $c.PdfPath = $ofd.FileName
        $c.ReadOk = $false
        $c.Analysis = $null
        $c.LblPdf.Text = $c.PdfPath
        $c.LblPdf.ForeColor = $c.ColorTexte
        $c.GrpFiches.Enabled = $false
        $c.GrpOptions.Enabled = $false
        $c.BtnGenerer.Enabled = $false
        foreach ($chk in @($c.ChkCea, $c.ChkCert, $c.ChkDac, $c.ChkFt, $c.ChkEntete, $c.ChkBilan)) {
            $chk.Checked = $false
        }

        & $c.CmdSetBtn -Button $c.BtnLoad -Text 'Lecture en cours...' `
            -BorderColor $c.ColorVert -BackColor $c.ColorVert -ForeColor $c.ColorBlanc -Width 180 -Height 40
        $c.BtnLoad.Enabled = $false
        $c.LblStatus.Text = 'Lecture du PDF...'
        $c.LblStatus.ForeColor = $c.ColorTexte
        try { [System.Windows.Forms.Application]::DoEvents() } catch { }

        $onProgress = {
            param($PageNumber, $TotalPages, $Detail)
            $c.LblStatus.Text = [string]$Detail
            try { [System.Windows.Forms.Application]::DoEvents() } catch { }
        }.GetNewClosure()

        try {
            $analysis = & $c.CmdRead -PdfPath ([string]$c.PdfPath) -OnProgress $onProgress
            $c.Analysis = $analysis
            if ($analysis.Ok) {
                $c.ReadOk = $true
                $c.GrpFiches.Enabled = $true
                $c.GrpOptions.Enabled = $true
                $c.ChkCea.Checked = [bool]$analysis.Cea
                $c.ChkCert.Checked = [bool]$analysis.Cert
                $c.ChkDac.Checked = [bool]$analysis.Dac
                $c.ChkFt.Checked = [bool]$analysis.Ft
                & $c.CmdUpdateGen -Context $c
                $c.LblStatus.Text = [string]$analysis.Message
                $c.LblStatus.ForeColor = $c.ColorTexte
            }
            else {
                $c.LblStatus.Text = [string]$analysis.Message
                $c.LblStatus.ForeColor = $c.ColorOrange
            }
        }
        catch {
            $c.LblStatus.Text = ("Erreur lecture : {0}" -f $_.Exception.Message)
            $c.LblStatus.ForeColor = $c.ColorOrange
        }
        finally {
            & $c.CmdSetBtn -Button $c.BtnLoad -Text '✓ PDF lu' `
                -BorderColor $c.ColorVert -BackColor $c.ColorVert -ForeColor $c.ColorBlanc -Width 180 -Height 40
            $c.BtnLoad.Enabled = $true
            try { [System.Windows.Forms.Application]::DoEvents() } catch { }
        }
    }.GetNewClosure())

    $btnGenerer.Add_Click({
        param($sender, $e)
        $c = $panel.Tag
        if (-not $c.ReadOk -or [string]::IsNullOrWhiteSpace([string]$c.PdfPath)) { return }
        if (-not ($c.ChkCea.Checked -or $c.ChkCert.Checked -or $c.ChkDac.Checked -or $c.ChkFt.Checked -or $c.ChkEntete.Checked -or $c.ChkBilan.Checked)) {
            return
        }

        $needEntete = [bool]$c.ChkEntete.Checked
        $needDac = [bool]$c.ChkDac.Checked

        $inputs = & $c.CmdPopup -NeedEntete:$needEntete -NeedDac:$needDac
        if ($null -eq $inputs) { return }

        # SegmentMeta synthétique (sans Excel tournée) — champs Entête facultatifs
        $collecteurPrenom = ''
        $collecteurNom = ''
        if (-not [string]::IsNullOrWhiteSpace([string]$inputs.CollecteurLabel)) {
            $parts = @(([string]$inputs.CollecteurLabel).Trim() -split '\s+', 2)
            if ($parts.Count -ge 1) { $collecteurPrenom = $parts[0] }
            if ($parts.Count -ge 2) { $collecteurNom = $parts[1] }
        }
        $vehiculeParc = ''
        $vehiculeImmat = ''
        if (-not [string]::IsNullOrWhiteSpace([string]$inputs.VehiculeLabel)) {
            $vp = [string]$inputs.VehiculeLabel
            if ($vp -match '^(.*?)\s+[—\-]\s+(.*)$') {
                $vehiculeParc = $Matches[1].Trim()
                $vehiculeImmat = $Matches[2].Trim()
            }
            else {
                $vehiculeParc = $vp.Trim()
            }
        }
        $dateDepot = $null
        if ($needDac -and $null -ne $inputs.DateDepot) {
            $dateDepot = [datetime]$inputs.DateDepot
        }
        # Chaînes vides (jamais $null) — évite crash page de garde / générateurs Excel.
        $heurePrise = ''
        try {
            if (-not [string]::IsNullOrWhiteSpace([string]$inputs.HeurePriseService)) {
                $heurePrise = ([string]$inputs.HeurePriseService).Trim()
            }
        }
        catch { }

        $segmentMeta = [pscustomobject]@{
            Collecteur               = ('{0} {1}' -f $collecteurPrenom, $collecteurNom).Trim()
            CollecteurPrenom         = $collecteurPrenom
            CollecteurNom            = $collecteurNom
            CollecteurId             = $(if ($null -ne $inputs.CollecteurId) { $inputs.CollecteurId } else { $null })
            Vehicule                 = $(if ($vehiculeImmat) { $vehiculeImmat } else { $vehiculeParc })
            VehiculeNumeroParc       = $vehiculeParc
            VehiculeImmatriculation   = $vehiculeImmat
            NumeroParc               = $vehiculeParc
            Plaque                   = $vehiculeImmat
            VehiculeId               = $(if ($null -ne $inputs.VehiculeId) { $inputs.VehiculeId } else { $null })
            DateDepotDac             = $dateDepot
            HeurePriseService        = $heurePrise
            ODMNumero                = ''
            ServiceLabel             = ''
            TourneeComplete          = $true
        }

        $options = [pscustomobject]@{
            Cea        = [bool]$c.ChkCea.Checked
            Certificat = [bool]$c.ChkCert.Checked
            Dac        = [bool]$c.ChkDac.Checked
            Ft         = [bool]$c.ChkFt.Checked
            Entete     = [bool]$c.ChkEntete.Checked
            Bilan      = [bool]$c.ChkBilan.Checked
        }

        $c.BtnGenerer.Enabled = $false
        $c.BtnLoad.Enabled = $false
        $c.GrpFiches.Enabled = $false
        $c.GrpOptions.Enabled = $false
        if ($null -ne $c.ProgressBar -and -not $c.ProgressBar.IsDisposed) {
            $c.ProgressBar.Value = 0
            $c.ProgressBar.Visible = $true
        }
        $c.LblStatus.Text = 'Génération en cours...'
        $c.LblStatus.ForeColor = $c.ColorTexte
        try { [System.Windows.Forms.Application]::DoEvents() } catch { }

        $onProgress = {
            param($state)
            if ($null -eq $c -or $null -eq $c.ProgressBar -or $c.ProgressBar.IsDisposed) { return }
            if ($null -ne $c.LblStatus -and -not $c.LblStatus.IsDisposed -and $null -ne $state) {
                try {
                    if ($null -ne $state.Message) { $c.LblStatus.Text = [string]$state.Message }
                }
                catch { }
            }
            try {
                if ($null -ne $state -and $null -ne $state.Percent) {
                    $pct = [int][Math]::Min(100, [Math]::Max(0, [int]$state.Percent))
                    if ($c.ProgressBar.Value -ne $pct) { $c.ProgressBar.Value = $pct }
                }
            }
            catch { }
            try { [System.Windows.Forms.Application]::DoEvents() } catch { }
        }.GetNewClosure()

        $genResult = $null
        try {
            $genResult = & $c.CmdGenerate -OdmPdfPath ([string]$c.PdfPath) -Options $options -SegmentMeta $segmentMeta -OnProgress $onProgress
        }
        catch {
            $genResult = [pscustomobject]@{
                Ok           = $false
                OutputPath   = $null
                ErrorMessage = $_.Exception.Message
            }
        }
        finally {
            if ($null -ne $c.ProgressBar -and -not $c.ProgressBar.IsDisposed) {
                try {
                    $c.ProgressBar.Visible = $false
                    $c.ProgressBar.Value = 0
                }
                catch { }
            }
            try { $c.BtnLoad.Enabled = $true } catch { }
            try {
                if ($c.ReadOk) {
                    $c.GrpFiches.Enabled = $true
                    $c.GrpOptions.Enabled = $true
                }
            }
            catch { }
            try { & $c.CmdUpdateGen -Context $c } catch { }
        }

        if ($null -ne $genResult -and $genResult.Ok) {
            $c.LblStatus.Text = 'Document généré et disponible dans le dossier Téléchargements.'
            $c.LblStatus.ForeColor = $c.ColorTexte
            [System.Windows.Forms.MessageBox]::Show(
                'Document généré et disponible dans le dossier Téléchargements.',
                'ODM Seul',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
        else {
            $err = if ($null -ne $genResult -and -not [string]::IsNullOrWhiteSpace([string]$genResult.ErrorMessage)) {
                [string]$genResult.ErrorMessage
            }
            else {
                'Erreur inconnue lors de la génération.'
            }
            $c.LblStatus.Text = ('Échec génération : {0}' -f $err)
            $c.LblStatus.ForeColor = $c.ColorOrange
            [System.Windows.Forms.MessageBox]::Show(
                ("Échec de la génération.`r`n`r`n{0}" -f $err),
                'ODM Seul',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    }.GetNewClosure())

    return $panel
}

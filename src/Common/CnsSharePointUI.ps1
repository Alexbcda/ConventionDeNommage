# Affichage WinForms des etats SharePoint (connexion planning).

. (Join-Path $PSScriptRoot 'CnsSharePointConnector.ps1')
. (Join-Path $PSScriptRoot 'Styles.ps1')

function Get-SharePointUiStateDefinition {
    param(
        [Parameter(Mandatory = $true)][string]$Status
    )
    switch ($Status) {
        'Connected' {
            return @{
                Icon           = '🟢'
                Message        = 'Connecte'
                ForeColor      = [System.Drawing.Color]::Green
                StatusDotColor = [System.Drawing.Color]::Green
                DegradedMode   = $false
                Buttons        = @(
                    @{ Id = 'Refresh'; Text = 'Actualiser'; Glyph = '🔄' }
                )
            }
        }
        'Connecting' {
            return @{
                Icon           = '🟡'
                Message        = 'Connexion en cours...'
                ForeColor      = [System.Drawing.Color]::Orange
                StatusDotColor = [System.Drawing.Color]::Orange
                DegradedMode   = $true
                Buttons        = @()
            }
        }
        'Expired' {
            return @{
                Icon           = '🟡'
                Message        = 'Session expiree - reconnectez-vous'
                ForeColor      = [System.Drawing.Color]::Orange
                StatusDotColor = [System.Drawing.Color]::Orange
                DegradedMode   = $true
                Buttons        = @(
                    @{ Id = 'Login'; Text = 'Reconnecter'; Glyph = '🔐' }
                )
            }
        }
        'WamBlocked' {
            return @{
                Icon           = '🟡'
                Message        = 'Connexion SharePoint - suivez les instructions Device Code dans la console'
                ForeColor      = [System.Drawing.Color]::Orange
                StatusDotColor = [System.Drawing.Color]::Orange
                DegradedMode   = $true
                Buttons        = @(
                    @{ Id = 'Login'; Text = 'Reconnecter'; Glyph = '🔐' }
                )
            }
        }
        'Denied' {
            return @{
                Icon           = '🔴'
                Message        = 'Acces refuse - verifier vos droits'
                ForeColor      = [System.Drawing.Color]::Red
                StatusDotColor = [System.Drawing.Color]::Red
                DegradedMode   = $true
                Buttons        = @(
                    @{ Id = 'Copy'; Text = 'Copier'; Glyph = '📋' }
                )
            }
        }
        'Offline' {
            return @{
                Icon           = '🔴'
                Message        = 'Connexion échouée – cliquez sur "Connexion" pour réessayer'
                ForeColor      = [System.Drawing.Color]::Red
                StatusDotColor = [System.Drawing.Color]::Red
                DegradedMode   = $true
                Buttons        = @()
            }
        }
        default {
            return @{
                Icon           = '🔴'
                Message        = 'Erreur SharePoint'
                ForeColor      = [System.Drawing.Color]::Red
                StatusDotColor = [System.Drawing.Color]::Red
                DegradedMode   = $true
                Buttons        = @(
                    @{ Id = 'Login'; Text = 'Se connecter'; Glyph = '🔐' }
                )
            }
        }
    }
}

function Format-SharePointDate {
    param([AllowNull()]$Date)

    $parsed = $null
    if ($null -ne $Date) {
        try { $parsed = [datetime]$Date } catch { return 'Date inconnue' }
    }
    if ($null -eq $parsed -or $parsed -eq [datetime]::MinValue) {
        return 'Date inconnue'
    }
    $now = Get-Date
    if ($parsed.Date -eq $now.Date) {
        return ("Aujourd'hui {0}" -f $parsed.ToString('HH:mm:ss'))
    }
    if ($parsed.Date -eq $now.AddDays(-1).Date) {
        return ("Hier {0}" -f $parsed.ToString('HH:mm:ss'))
    }
    return $parsed.ToString('dd/MM/yyyy HH:mm:ss')
}

function Format-CnsSharePointSyncLabel {
    param([AllowNull()][datetime]$LastSync)
    if ($null -eq $LastSync -or $LastSync -eq [datetime]::MinValue) {
        return 'Derniere synchronisation : jamais'
    }
    return ('Derniere synchronisation : {0}' -f (Format-SharePointDate -Date $LastSync))
}

function Set-CnsSharePointConnectButtonPosition {
    param(
        [System.Windows.Forms.Control]$ConnectBtn,
        [int]$Margin = 12,
        [int]$RowY = 28
    )
    if ($null -eq $ConnectBtn -or $null -eq $ConnectBtn.Parent) { return }

    $parent = $ConnectBtn.Parent
    $visibleWidth = $parent.ClientSize.Width
    if ($visibleWidth -le 0) { $visibleWidth = $parent.Width }

    $hostPanel = $parent.Parent
    if ($null -ne $hostPanel -and $hostPanel -is [System.Windows.Forms.ScrollableControl]) {
        $viewportWidth = $hostPanel.ClientSize.Width
        if ($viewportWidth -gt 0) { $visibleWidth = $viewportWidth }
    }

    $newX = [Math]::Max($Margin, $visibleWidth - $ConnectBtn.Width - $Margin - 150)
    if ($newX + $ConnectBtn.Width + $Margin -gt $parent.ClientSize.Width) {
        $newX = $parent.ClientSize.Width - $ConnectBtn.Width - $Margin
    }
    if ($newX -lt $Margin) { $newX = $Margin }

    $ConnectBtn.Location = [System.Drawing.Point]::new($newX, $RowY)
}

function New-SharePointStatusControls {
    param(
        [System.Windows.Forms.Control]$Parent,
        [System.Drawing.Point]$Location,
        [System.Drawing.Size]$Size
    )

    $connectBtnWidth = 160
    $connectBtnHeight = 32
    $statusRowY = 28
    $dateRowY = 64
    $horizontalPad = 12

    $group = [System.Windows.Forms.GroupBox]::new()
    $group.Name = 'grpSharePoint'
    $group.Text = ''
    $group.Location = $Location
    $group.Size = [System.Drawing.Size]::new($Size.Width, [Math]::Max(120, $Size.Height))
    $group.MaximumSize = [System.Drawing.Size]::new(1200, 9999)
    $group.Anchor = 'Top,Left,Right'
    $group.Font = $script:PoliceTitre3

    $clientWidth = $group.ClientSize.Width
    if ($clientWidth -le 0) { $clientWidth = $Size.Width }

    $lblIcon = [System.Windows.Forms.Label]::new()
    $lblIcon.Name = 'lblSharePointIcon'
    $lblIcon.AutoSize = $true
    $lblIcon.Font = [System.Drawing.Font]::new('Segoe UI Emoji', 14, [System.Drawing.FontStyle]::Regular)
    $lblIcon.Location = [System.Drawing.Point]::new($horizontalPad, $statusRowY)
    $lblIcon.Visible = $false

    $pnlStatusDot = [System.Windows.Forms.Panel]::new()
    $pnlStatusDot.Name = 'pnlSharePointStatusDot'
    $pnlStatusDot.Size = [System.Drawing.Size]::new(14, 14)
    $pnlStatusDot.Location = [System.Drawing.Point]::new($horizontalPad + 2, $statusRowY + 9)
    $pnlStatusDot.BackColor = [System.Drawing.Color]::Gray

    $lblStatus = [System.Windows.Forms.Label]::new()
    $lblStatus.Name = 'lblSharePointStatus'
    $lblStatus.AutoSize = $false
    $lblStatus.Location = [System.Drawing.Point]::new($horizontalPad, $statusRowY)
    $lblStatus.Size = [System.Drawing.Size]::new(500, $connectBtnHeight)
    $lblStatus.Anchor = 'Top,Left'
    $lblStatus.AutoEllipsis = $true
    $lblStatus.Font = $script:PoliceNormal
    $lblStatus.ForeColor = $script:CouleurTexteSecondairePanel
    $lblStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

    $lblFileName = [System.Windows.Forms.Label]::new()
    $lblFileName.Name = 'lblSharePointFileName'
    $lblFileName.AutoSize = $false
    $lblFileName.Visible = $false
    $lblFileName.Size = [System.Drawing.Size]::new(1, 1)
    $lblFileName.Text = '-'

    $lblDate = [System.Windows.Forms.Label]::new()
    $lblDate.Name = 'lblSharePointDate'
    $lblDate.AutoSize = $false
    $lblDate.Location = [System.Drawing.Point]::new($horizontalPad, $dateRowY)
    $lblDate.Size = [System.Drawing.Size]::new([Math]::Min(600, $clientWidth - 400), 25)
    $lblDate.Anchor = 'Top,Left'
    $lblDate.Font = $script:PoliceLabelSecondaireFenetre
    $lblDate.ForeColor = $script:CouleurTexteSecondairePanel
    $lblDate.Text = 'Derniere synchronisation : -'

    $lblLocalMode = [System.Windows.Forms.Label]::new()
    $lblLocalMode.Name = 'lblSharePointLocalMode'
    $lblLocalMode.AutoSize = $false
    $lblLocalMode.Location = [System.Drawing.Point]::new($horizontalPad, $dateRowY + 24)
    $lblLocalMode.Size = [System.Drawing.Size]::new($clientWidth - 24, 18)
    $lblLocalMode.Anchor = 'Top,Left,Right'
    $lblLocalMode.Font = $script:PoliceLabelSecondaireFenetre
    $lblLocalMode.ForeColor = [System.Drawing.Color]::FromArgb(180, 100, 0)
    $lblLocalMode.Visible = $false
    $lblLocalMode.Text = 'Mode local - modifications non synchronisees'

    $flowButtons = [System.Windows.Forms.FlowLayoutPanel]::new()
    $flowButtons.Name = 'flowSharePointButtons'
    $flowButtons.FlowDirection = 'LeftToRight'
    $flowButtons.WrapContents = $false
    $flowButtons.AutoSize = $false
    $flowButtons.Location = [System.Drawing.Point]::new($clientWidth - 380, $dateRowY - 2)
    $flowButtons.Size = [System.Drawing.Size]::new(360, $connectBtnHeight)
    $flowButtons.Anchor = 'Top,Right'
    $flowButtons.Padding = [System.Windows.Forms.Padding]::new(0)

    $btnConnect = [System.Windows.Forms.Button]::new()
    $btnConnect.Name = 'btnSharePointConnect'
    Set-BtnCertificatStyle -BtnCertificat $btnConnect
    $btnConnect.Text = 'Connexion'
    $btnConnect.Size = [System.Drawing.Size]::new($connectBtnWidth, $connectBtnHeight)
    $btnConnect.Location = [System.Drawing.Point]::new($clientWidth - $connectBtnWidth - $horizontalPad, $statusRowY)
    $btnConnect.Anchor = 'Top,Right'
    $btnConnect.Visible = $false

    foreach ($ctrl in @($lblIcon, $pnlStatusDot, $lblStatus, $lblFileName, $lblDate, $lblLocalMode, $flowButtons, $btnConnect)) {
        $group.Controls.Add($ctrl)
    }
    $group.PerformLayout()
    $clientWidth = $group.ClientSize.Width
    if ($clientWidth -le 0) { $clientWidth = $Size.Width }
    $flowButtons.Location = [System.Drawing.Point]::new([Math]::Max($horizontalPad, $clientWidth - 380), $dateRowY - 2)
    Set-CnsSharePointConnectButtonPosition -ConnectBtn $btnConnect -Margin $horizontalPad -RowY $statusRowY
    $labelMaxWidth = $btnConnect.Location.X - $horizontalPad - 8
    if ($labelMaxWidth -ge 100) {
        $lblStatus.Width = [Math]::Min(500, $labelMaxWidth)
    }
    $btnConnect.BringToFront()
    if ($null -ne $Parent) {
        $Parent.Controls.Add($group)
    }

    return @{
        GroupBox   = $group
        Icon       = $lblIcon
        StatusDot  = $pnlStatusDot
        Status     = $lblStatus
        FileName   = $lblFileName
        Date       = $lblDate
        LocalMode  = $lblLocalMode
        Buttons    = $flowButtons
        Connect    = $btnConnect
        Message    = $lblStatus
        Sync       = $lblDate
    }
}

function Update-SharePointUI {
    param(
        [Parameter(Mandatory = $true)]
        $State,
        [Parameter(Mandatory = $true)]
        [hashtable]$Labels,
        [AllowNull()]$Buttons = $null,
        [AllowNull()]$LastSync,
        [string]$Message = $null,
        [string]$FilePath = $null,
        [scriptblock]$OnAction = $null
    )

    $status = $null
    $stateMessage = $null
    $stateFilePath = $FilePath

    if ($State -is [string]) {
        $status = [string]$State
        $stateMessage = $Message
    }
    elseif ($null -ne $State) {
        $status = [string]$State.Status
        $stateMessage = [string]$State.Message
        if (-not [string]::IsNullOrWhiteSpace([string]$State.FilePath)) {
            $stateFilePath = [string]$State.FilePath
        }
        if ($null -eq $LastSync -and $null -ne $State.LastSync) {
            try { $LastSync = [datetime]$State.LastSync } catch { $LastSync = $null }
        }
    }

    $lastSyncDate = $null
    if ($null -ne $LastSync) {
        try { $lastSyncDate = [datetime]$LastSync } catch { $lastSyncDate = $null }
    }

    if ([string]::IsNullOrWhiteSpace($status)) { $status = 'Error' }
    $def = Get-SharePointUiStateDefinition -Status $status

    $statusDot = $Labels.StatusDot
    if ($null -eq $statusDot -and $Labels.ContainsKey('StatusDot')) {
        $statusDot = $Labels.StatusDot
    }
    if ($null -ne $statusDot -and $statusDot -is [System.Windows.Forms.Control]) {
        $statusDot.BackColor = $def.StatusDotColor
        $statusDot.Visible = $false
    }

    if ($null -ne $Labels.Icon) {
        $Labels.Icon.Text = [string]$def.Icon
        if ($def.ForeColor) {
            $Labels.Icon.ForeColor = $def.ForeColor
        }
    }

    $statusText = if (-not [string]::IsNullOrWhiteSpace($stateMessage)) { [string]$stateMessage } else { [string]$def.Message }
    $statusForeColor = if ($def.ForeColor) { $def.ForeColor } else { $script:CouleurTexteSecondairePanel }

    $fileLeaf = $null
    $fileLabel = $Labels.FileNameLabel
    if ($null -eq $fileLabel -and $Labels.ContainsKey('FileName')) {
        $fileLabel = $Labels.FileName
    }
    if (-not [string]::IsNullOrWhiteSpace($stateFilePath)) {
        $fileLeaf = Split-Path -Leaf $stateFilePath
    }
    elseif ($status -eq 'Connected') {
        $fileLeaf = $script:CnsSharePointPlanningFileName
    }
    if ($null -ne $fileLabel) {
        if (-not [string]::IsNullOrWhiteSpace($fileLeaf)) {
            $fileLabel.Text = $fileLeaf
        }
        else {
            $fileLabel.Text = '-'
        }
        if ($fileLabel -is [System.Windows.Forms.Control]) {
            $fileLabel.Visible = $false
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($fileLeaf) -and $status -in @('Connected', 'Expired')) {
        if ($statusText -notmatch [regex]::Escape($fileLeaf)) {
            $statusText = ('{0} - {1}' -f $statusText, $fileLeaf)
        }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$def.Icon)) {
        $statusText = ('{0} {1}' -f $def.Icon, $statusText)
    }

    if ($null -ne $Labels.StatusLabel) {
        $Labels.StatusLabel.Text = $statusText
        $Labels.StatusLabel.ForeColor = $statusForeColor
    }
    if ($null -ne $Labels.Message) {
        $Labels.Message.Text = $statusText
        $Labels.Message.ForeColor = $statusForeColor
    }

    foreach ($statusLbl in @($Labels.StatusLabel, $Labels.Message)) {
        if ($null -ne $statusLbl -and $statusLbl -is [System.Windows.Forms.Label]) {
            $statusLbl.AutoSize = $false
            $statusLbl.AutoEllipsis = $true
            if ($statusLbl.Height -lt 32) { $statusLbl.Height = 32 }
        }
    }

    $importExcelBtn = $null
    if ($Labels.ContainsKey('ImportExcel')) {
        $importExcelBtn = $Labels.ImportExcel
    }
    $planningUIMode = $null
    if ($Labels.ContainsKey('PlanningUIMode')) {
        $planningUIMode = [string]$Labels.PlanningUIMode
    }
    if ($planningUIMode -eq 'SharePoint') {
        $showImportExcel = ($status -notin @('Connected', 'Connecting'))
    }
    elseif ($planningUIMode -eq 'Local') {
        $showImportExcel = $true
    }
    else {
        $showImportExcel = [bool]$def.DegradedMode
        if (-not $showImportExcel) {
            $effectiveExcel = $null
            if ($Labels.ContainsKey('EffectiveExcelPath')) {
                $effectiveExcel = [string]$Labels.EffectiveExcelPath
            }
            if ([string]::IsNullOrWhiteSpace($effectiveExcel) -or -not (Test-Path -LiteralPath $effectiveExcel)) {
                $showImportExcel = $true
            }
        }
    }
    if ($null -ne $importExcelBtn -and $importExcelBtn -is [System.Windows.Forms.Control]) {
        $importExcelBtn.Visible = $showImportExcel
    }

    $connectBtn = $null
    if ($Labels.ContainsKey('Connect')) {
        $connectBtn = $Labels.Connect
    }
    if ($null -ne $connectBtn -and $connectBtn -is [System.Windows.Forms.Control]) {
        $connectBtnWidth = 160
        $connectBtnHeight = 32
        $isLocalMode = ($planningUIMode -eq 'Local')

        if ($status -eq 'Connecting') {
            Set-BtnQuitterStyle -BtnQuitter $connectBtn
            $connectBtn.Text = '⏳ Connexion en cours...'
            $connectBtn.Tag = 'Connect'
            $connectBtn.Size = [System.Drawing.Size]::new($connectBtnWidth, $connectBtnHeight)
            $connectBtn.Enabled = $false
            $showConnectBtn = $true
        }
        elseif ($status -eq 'Connected' -and -not $isLocalMode) {
            Set-BtnCertificatStyle -BtnCertificat $connectBtn
            $connectBtn.Text = '🔓 Déconnexion'
            $connectBtn.Tag = 'Disconnect'
            $connectBtn.Size = [System.Drawing.Size]::new($connectBtnWidth, $connectBtnHeight)
            $connectBtn.Enabled = $true
            $showConnectBtn = $true
        }
        else {
            Set-BtnCertificatStyle -BtnCertificat $connectBtn
            $connectBtn.Text = '🔐 Connexion'
            $connectBtn.Tag = 'Connect'
            $connectBtn.Size = [System.Drawing.Size]::new($connectBtnWidth, $connectBtnHeight)
            $connectBtnEnabled = $status -in @('Expired', 'Offline', 'Denied', 'Error', 'WamBlocked') -or $isLocalMode
            $connectBtn.Enabled = $connectBtnEnabled
            $showConnectBtn = $isLocalMode -or ($status -in @('Expired', 'Offline', 'Denied', 'Error', 'WamBlocked'))
        }

        $connectBtn.Visible = $showConnectBtn
        $connectBtn.Anchor = 'Top,Right'
        $connectBtn.Location = [System.Drawing.Point]::new(480, 28)

        $statusLabel = $null
        if ($Labels.ContainsKey('StatusLabel')) { $statusLabel = $Labels.StatusLabel }
        elseif ($Labels.ContainsKey('Status')) { $statusLabel = $Labels.Status }
        if ($null -ne $statusLabel -and $statusLabel -is [System.Windows.Forms.Control]) {
            $statusLabel.AutoSize = $false
            $statusLabel.AutoEllipsis = $true
            $labelMaxWidth = [Math]::Min(500, $connectBtn.Location.X - 12 - 8)
            if ($labelMaxWidth -ge 100) {
                $statusLabel.Size = [System.Drawing.Size]::new($labelMaxWidth, 32)
            }
            else {
                $statusLabel.Size = [System.Drawing.Size]::new(500, 32)
            }
            $statusLabel.Text = $statusText
        }

        if ($showConnectBtn) {
            $connectBtn.Visible = $true
            $connectBtn.BringToFront()
            if ($null -ne $connectBtn.Parent) {
                $connectBtn.Parent.Refresh()
            }
            $connectBtn.Invalidate()
        }

        # DIAGNOSTIC DETAILLE DU BOUTON CONNEXION
        if ($connectBtn -and $connectBtn.Parent) {
            $parent = $connectBtn.Parent
            $parentWidth = $parent.ClientSize.Width
            $btnX = $connectBtn.Location.X
            $btnRight = $btnX + $connectBtn.Width

            Write-Host '=== DIAGNOSTIC BOUTON CONNEXION ===' -ForegroundColor Cyan
            Write-Host "Etat : $status"
            Write-Host "Visible calcule : $showConnectBtn"
            Write-Host "btnConnect.Visible = $($connectBtn.Visible)"
            Write-Host "btnConnect.Location = $($connectBtn.Location)"
            Write-Host "btnConnect.Size = $($connectBtn.Size)"
            Write-Host "btnConnect.Parent = $($parent.Name)"
            Write-Host "Parent.ClientSize = $parentWidth"
            Write-Host "btnConnect.Dans les limites ? = $(($btnX -ge 0 -and $btnRight -le $parentWidth))"
            Write-Host "Parent.Visible = $($parent.Visible)"
            Write-Host "Parent.Enabled = $($parent.Enabled)"
            Write-Host "btnConnect.BackColor = $($connectBtn.BackColor)"
            Write-Host "btnConnect.ForeColor = $($connectBtn.ForeColor)"

            Write-Host 'Controles du parent :'
            foreach ($ctrl in $parent.Controls) {
                $chevauch = ($ctrl -ne $connectBtn -and
                    $ctrl.Visible -and
                    $ctrl.Bounds.IntersectsWith($connectBtn.Bounds))
                Write-Host "  - $($ctrl.Name) : Loc=$($ctrl.Location) Size=$($ctrl.Size) Visible=$($ctrl.Visible) CHEVAUCHE=$chevauch"
            }
            Write-Host '===================================' -ForegroundColor Cyan
        }
    }

    $fileLabel = $Labels.FileNameLabel
    if ($null -eq $fileLabel -and $Labels.ContainsKey('FileName')) {
        $fileLabel = $Labels.FileName
    }
    if ($null -ne $fileLabel -and $fileLabel -is [System.Windows.Forms.Control]) {
        $fileLabel.Visible = $false
    }

    $dateLabel = $Labels.DateLabel
    if ($null -eq $dateLabel -and $Labels.ContainsKey('Date')) {
        $dateLabel = $Labels.Date
    }
    if ($null -eq $dateLabel -and $null -ne $Labels.Sync) {
        $dateLabel = $Labels.Sync
    }
    if ($null -ne $dateLabel) {
        if ($null -ne $lastSyncDate -and $lastSyncDate -ne [datetime]::MinValue) {
            $dateLabel.Text = ('Derniere synchronisation : {0}' -f (Format-SharePointDate -Date $lastSyncDate))
        }
        else {
            $dateLabel.Text = 'Derniere synchronisation : jamais'
        }
    }

    if ($null -ne $Labels.LocalMode) {
        $isLocal = ($status -eq 'Connected') -and (-not [string]::IsNullOrWhiteSpace($stateFilePath)) `
            -and ($stateFilePath -like "*\local\*")
        $preferLocal = (Get-CnsPlanningRegistryValue -Name 'PreferLocalMode') -in @('1', 'true', 'TRUE')
        $Labels.LocalMode.Visible = ($isLocal -or $preferLocal)
    }

    $flow = $Buttons
    if ($null -eq $flow) { return }
    if ($null -ne $OnAction) {
        $script:CnsSharePointUiActionHandler = $OnAction
    }
    $flow.SuspendLayout()
    $flow.Controls.Clear()
    foreach ($btnDef in @($def.Buttons)) {
        $btn = [System.Windows.Forms.Button]::new()
        $btn.Name = "btnSharePoint$($btnDef.Id)"
        $btn.Tag = $btnDef.Id
        $text = if ($btnDef.Glyph) { "{0} {1}" -f $btnDef.Glyph, $btnDef.Text } else { $btnDef.Text }
        Set-BtnBorderStyle -Button $btn -Text $text -BorderColor $script:CouleurBleu -Width 120 -Height 36
        $btn.Add_Click({
            param($sender, $e)
            $id = [string]$sender.Tag
            if ($null -ne $script:CnsSharePointUiActionHandler) {
                & $script:CnsSharePointUiActionHandler $id
            }
        })
        $flow.Controls.Add($btn)
    }
    $flow.ResumeLayout($true)
    $flow.Visible = (@($def.Buttons).Count -gt 0)

    if ($null -ne $connectBtn -and $connectBtn -is [System.Windows.Forms.Control] -and $connectBtn.Visible) {
        $connectBtn.Anchor = 'Top,Right'
        $connectBtn.Location = [System.Drawing.Point]::new(480, 28)
        $connectBtn.BringToFront()
        $connectBtn.Invalidate()
    }
}

function Copy-SharePointErrorToClipboard {
    param(
        $State,
        $ErrorDetails = $null
    )
    $detail = if (-not [string]::IsNullOrWhiteSpace($ErrorDetails)) { [string]$ErrorDetails }
    elseif ($null -ne $State -and -not [string]::IsNullOrWhiteSpace([string]$State.ErrorDetail)) { [string]$State.ErrorDetail }
    else { 'Erreur SharePoint inconnue' }
    $status = if ($null -ne $State) { [string]$State.Status } else { 'Error' }
    $msg = if ($null -ne $State) { [string]$State.Message } else { '' }
    $text = @(
        '=== Erreur SharePoint ConventionDeNommage ==='
        "Statut : $status"
        "Message : $msg"
        "Detail : $detail"
        "Date : $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))"
    ) -join [Environment]::NewLine
    [System.Windows.Forms.Clipboard]::SetText($text)
}

function Show-SharePointErrorDialog {
    param(
        $State,
        $ErrorDetails = $null
    )
    $detail = if (-not [string]::IsNullOrWhiteSpace($ErrorDetails)) { [string]$ErrorDetails }
    elseif ($null -ne $State -and -not [string]::IsNullOrWhiteSpace([string]$State.ErrorDetail)) { [string]$State.ErrorDetail }
    else { 'Aucun detail disponible.' }
    $msg = if ($null -ne $State) { [string]$State.Message } else { 'Erreur SharePoint' }
    $body = "$msg`n`n$detail`n`nActions possibles : copier l'erreur, utiliser un fichier local, ou reessayer."
    [System.Windows.Forms.MessageBox]::Show(
        $body,
        'SharePoint - Erreur',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
}

function Invoke-SharePointLocalFilePicker {
    $ofd = [System.Windows.Forms.OpenFileDialog]::new()
    $ofd.Filter = 'Excel (*.xlsx;*.xlsm;*.xls)|*.xlsx;*.xlsm;*.xls|Tous les fichiers (*.*)|*.*'
    $ofd.Title = 'Selectionner le fichier planning local'
    if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }
    try {
        return (Set-CnsSharePointLocalPlanningFile -SourcePath $ofd.FileName)
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            'Mode local',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return $null
    }
}

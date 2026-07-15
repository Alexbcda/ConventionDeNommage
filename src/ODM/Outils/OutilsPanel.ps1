# OutilsPanel.ps1 — Parametres utilisateur (video tutoriel, etc.)

. (Join-Path $PSScriptRoot '..\..\Common\Styles.ps1')
if (-not (Get-Command Get-PlanningRebuildSetting -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\..\Database\Database.ps1')
}

function Write-OutilsPanelLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    $line = "[OUTILS] $Message"
    Write-Host $line -ForegroundColor DarkGray
    if (Get-Command Write-PlanningRebuildUiLog -ErrorAction SilentlyContinue) {
        Write-PlanningRebuildUiLog $line
    }
}

function Save-OutilsPlanningRebuildSettings {
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.CheckBox]$ChkPlayVideo,
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.TextBox]$TxtVideoPath,
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.NumericUpDown]$NumDelay,
        [string]$Reason = 'auto'
    )

    $playValue = if ($ChkPlayVideo.Checked) { '1' } else { '0' }
    $videoPathValue = [string]$TxtVideoPath.Text
    if ([string]::IsNullOrWhiteSpace($videoPathValue)) {
        $videoPathValue = 'media/videos/tutoriel_convention_nommage.mp4'
    }
    $delayValue = $NumDelay.Value.ToString()

    Set-PlanningRebuildSetting -Key 'play_video_after_treatment' -Value $playValue
    Set-PlanningRebuildSetting -Key 'video_path' -Value $videoPathValue
    Set-PlanningRebuildSetting -Key 'video_delay_seconds' -Value $delayValue

    if ($playValue -eq '0' -and (Get-Command Stop-PlanningRebuildPendingVideoTimer -ErrorAction SilentlyContinue)) {
        Stop-PlanningRebuildPendingVideoTimer
    }

    Write-OutilsPanelLog ("Auto-save ({0}) : play_video={1} delay={2}s path={3}" -f $Reason, $playValue, $delayValue, $videoPathValue)

    return @{
        PlayValue      = $playValue
        VideoPathValue = $videoPathValue
        DelayValue     = $delayValue
    }
}

function Find-OutilsDescendantControlByName {
    param(
        [System.Windows.Forms.Control]$Root,
        [string]$Name
    )
    if ($null -eq $Root) { return $null }
    if ([string]$Root.Name -eq $Name) { return $Root }
    foreach ($child in @($Root.Controls)) {
        $found = Find-OutilsDescendantControlByName -Root $child -Name $Name
        if ($null -ne $found) { return $found }
    }
    return $null
}

function Show-OutilsPanel {
    $panel = [System.Windows.Forms.Panel]::new()
    $panel.Dock = 'Fill'
    $panel.BackColor = $script:CouleurGrisFond
    $panel.Padding = [System.Windows.Forms.Padding]::new(20)
    $panel.AutoScroll = $true

    $lblTitle = [System.Windows.Forms.Label]::new()
    $lblTitle.Text = 'Outils et parametres'
    $lblTitle.Font = $script:PoliceTitreGestionFenetre
    $lblTitle.ForeColor = $script:CouleurOrange
    $lblTitle.Location = [System.Drawing.Point]::new(0, 0)
    $lblTitle.Size = [System.Drawing.Size]::new(500, 50)
    $panel.Controls.Add($lblTitle)

    $connectorScript = Join-Path $PSScriptRoot '..\..\Common\CnsSharePointConnector.ps1'
    if (Test-Path -LiteralPath $connectorScript) {
        . $connectorScript
    }
    $updateManager = Join-Path $PSScriptRoot '..\..\Core\UpdateManager.ps1'
    if (Test-Path -LiteralPath $updateManager) {
        . $updateManager
    }

    $grpSharePoint = [System.Windows.Forms.GroupBox]::new()
    $grpSharePoint.Name = 'grpSharePointConfig'
    $grpSharePoint.Text = 'Configuration SharePoint'
    $grpSharePoint.Location = [System.Drawing.Point]::new(0, 60)
    $grpSharePoint.Size = [System.Drawing.Size]::new(700, 150)
    $grpSharePoint.Font = $script:PoliceTitre3

    $configManagerScript = Join-Path $PSScriptRoot '..\..\Core\ConfigManager.ps1'
    if (Test-Path -LiteralPath $configManagerScript) {
        if (-not (Get-Command Show-ConfigureCentreDialog -ErrorAction SilentlyContinue)) {
            . $configManagerScript
        }
    }

    $lblSharePointInfo = [System.Windows.Forms.Label]::new()
    $lblSharePointInfo.Text = "Changer l'adresse SharePoint"
    $lblSharePointInfo.Font = $script:PoliceLabelSecondaireFenetre
    $lblSharePointInfo.ForeColor = [System.Drawing.Color]::FromArgb(180, 100, 0)
    $lblSharePointInfo.Location = [System.Drawing.Point]::new(15, 25)
    $lblSharePointInfo.Size = [System.Drawing.Size]::new(500, 25)
    $grpSharePoint.Controls.Add($lblSharePointInfo)

    $btnChangeUrl = [System.Windows.Forms.Button]::new()
    $btnChangeUrl.Name = 'btnChangeSharePointUrl'
    $btnChangeUrl.Text = '🔧 Changer l''adresse SharePoint'
    $btnChangeUrl.Size = [System.Drawing.Size]::new(260, 40)
    $btnChangeUrl.Location = [System.Drawing.Point]::new(15, 55)
    $btnChangeUrl.BackColor = $script:CouleurOrange
    $btnChangeUrl.ForeColor = $script:CouleurBlanc
    $btnChangeUrl.FlatStyle = 'Flat'
    $btnChangeUrl.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnChangeUrl.Font = $script:PoliceBouton
    $btnChangeUrl.Add_Click({
        try {
            if (-not (Get-Command Show-ChangeUrlDialog -ErrorAction SilentlyContinue)) {
                throw 'Module SharePoint non charge correctement'
            }
            $changed = Show-ChangeUrlDialog
            if ($changed) {
                if (Get-Command Restart-Application -ErrorAction SilentlyContinue) {
                    Restart-Application
                }
                else {
                    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                        Write-Log '[Outils] Restart-Application non disponible' 'ERROR' @{}
                    }
                    [System.Windows.Forms.MessageBox]::Show(
                        'Configuration sauvegardee. Veuillez redemarrer l''application manuellement.',
                        'Redemarrage requis',
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Information
                    ) | Out-Null
                }
            }
        }
        catch {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log '[Outils] Erreur changement URL' 'ERROR' @{ message = $_.Exception.Message }
            }
            else {
                Write-OutilsPanelLog ("Erreur changement URL : {0}" -f $_.Exception.Message)
            }
            [System.Windows.Forms.MessageBox]::Show(
                ("Erreur : {0}" -f $_.Exception.Message),
                'Erreur',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })
    $grpSharePoint.Controls.Add($btnChangeUrl)

    $btnConfigureCentre = [System.Windows.Forms.Button]::new()
    $btnConfigureCentre.Name = 'btnConfigureCentre'
    $btnConfigureCentre.Text = 'Configurer le centre'
    $btnConfigureCentre.Size = [System.Drawing.Size]::new(260, 40)
    $btnConfigureCentre.Location = [System.Drawing.Point]::new(290, 55)
    $btnConfigureCentre.BackColor = $script:CouleurOrange
    $btnConfigureCentre.ForeColor = $script:CouleurBlanc
    $btnConfigureCentre.FlatStyle = 'Flat'
    $btnConfigureCentre.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnConfigureCentre.Font = $script:PoliceBouton
    $btnConfigureCentre.Add_Click({
        try {
            if (-not (Get-Command Show-ConfigureCentreDialog -ErrorAction SilentlyContinue)) {
                throw 'ConfigManager non charge correctement'
            }
            $configured = Show-ConfigureCentreDialog
            if ($configured) {
                if (Get-Command Restart-Application -ErrorAction SilentlyContinue) {
                    Restart-Application
                }
                else {
                    [System.Windows.Forms.MessageBox]::Show(
                        'Centre enregistre. Veuillez redemarrer l''application manuellement.',
                        'Redemarrage requis',
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Information
                    ) | Out-Null
                }
            }
        }
        catch {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log '[Outils] Erreur configuration centre' 'ERROR' @{ message = $_.Exception.Message }
            }
            [System.Windows.Forms.MessageBox]::Show(
                ("Erreur : {0}" -f $_.Exception.Message),
                'Erreur',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })
    $grpSharePoint.Controls.Add($btnConfigureCentre)
    $panel.Controls.Add($grpSharePoint)

    $showSuperviseurOutils = $false
    if ($showSuperviseurOutils) {
        $exportImportScript = Join-Path $PSScriptRoot '..\..\Database\ExportImport.ps1'
        if (Test-Path -LiteralPath $exportImportScript) {
            . $exportImportScript
        }

        $grpSuperviseur = [System.Windows.Forms.GroupBox]::new()
        $grpSuperviseur.Name = 'grpSuperviseur'
        $grpSuperviseur.Text = 'Superviseur - Export/Import des données'
        $grpSuperviseur.Location = [System.Drawing.Point]::new(0, 170)
        $grpSuperviseur.Size = [System.Drawing.Size]::new(700, 100)
        $grpSuperviseur.Font = $script:PoliceTitre3

        $lblSuperviseurInfo = [System.Windows.Forms.Label]::new()
        $lblSuperviseurInfo.Text = '⚠️ Fonction réservée au chef / superviseur. Permet de synchroniser les données entre centres.'
        $lblSuperviseurInfo.Font = $script:PoliceLabelSecondaireFenetre
        $lblSuperviseurInfo.ForeColor = [System.Drawing.Color]::FromArgb(180, 100, 0)
        $lblSuperviseurInfo.Location = [System.Drawing.Point]::new(15, 25)
        $lblSuperviseurInfo.Size = [System.Drawing.Size]::new(550, 25)
        $grpSuperviseur.Controls.Add($lblSuperviseurInfo)

        $btnExport = [System.Windows.Forms.Button]::new()
        $btnExport.Name = 'btnExportData'
        $btnExport.Text = '📤 Exporter les données du centre'
        $btnExport.Size = [System.Drawing.Size]::new(240, 40)
        $btnExport.Location = [System.Drawing.Point]::new(15, 55)
        $btnExport.BackColor = $script:CouleurVert
        $btnExport.ForeColor = $script:CouleurBlanc
        $btnExport.FlatStyle = 'Flat'
        $btnExport.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btnExport.Font = $script:PoliceBouton

        $btnImport = [System.Windows.Forms.Button]::new()
        $btnImport.Name = 'btnImportData'
        $btnImport.Text = '📥 Importer les données du centre'
        $btnImport.Size = [System.Drawing.Size]::new(240, 40)
        $btnImport.Location = [System.Drawing.Point]::new(265, 55)
        $btnImport.BackColor = $script:CouleurOrange
        $btnImport.ForeColor = $script:CouleurBlanc
        $btnImport.FlatStyle = 'Flat'
        $btnImport.Cursor = [System.Windows.Forms.Cursors]::Hand
        $btnImport.Font = $script:PoliceBouton

        $btnExport.Add_Click({
            try {
                if (-not (Get-Command Export-CenterData -ErrorAction SilentlyContinue)) {
                    throw 'Module ExportImport.ps1 non charge'
                }
                $null = Export-CenterData -IncludeAppConfig
            }
            catch {
                if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                    Write-Log '[Outils] Erreur export' 'ERROR' @{ message = $_.Exception.Message }
                }
                else {
                    Write-OutilsPanelLog ("Erreur export : {0}" -f $_.Exception.Message)
                }
                [System.Windows.Forms.MessageBox]::Show(
                    ("Erreur lors de l'export : {0}" -f $_.Exception.Message),
                    'Erreur',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                ) | Out-Null
            }
        })

        $btnImport.Add_Click({
            try {
                if (-not (Get-Command Import-CenterData -ErrorAction SilentlyContinue)) {
                    throw 'Module ExportImport.ps1 non charge'
                }
                $ok = Import-CenterData
                if (-not $ok) { return }

                $mainForm = $this.FindForm()
                if ($null -eq $mainForm) { return }

                $agentsGrid = Find-OutilsDescendantControlByName -Root $mainForm -Name 'AgentsGrid'
                $vehiculesGrid = Find-OutilsDescendantControlByName -Root $mainForm -Name 'VehiculesGrid'
                $chkAgents = Find-OutilsDescendantControlByName -Root $mainForm -Name 'chkHistoriqueAgents'
                $chkVehicules = Find-OutilsDescendantControlByName -Root $mainForm -Name 'chkHistoriqueVehicules'
                $lblVehiculesEmpty = Find-OutilsDescendantControlByName -Root $mainForm -Name 'lblVehiculesEmpty'

                if ($null -ne $agentsGrid -and (Get-Command Refresh-AgentsGrid -ErrorAction SilentlyContinue)) {
                    $includeAgents = $false
                    if ($chkAgents -is [System.Windows.Forms.CheckBox]) { $includeAgents = $chkAgents.Checked }
                    Refresh-AgentsGrid -Grid $agentsGrid -IncludeHistorique $includeAgents
                }
                if ($null -ne $vehiculesGrid -and (Get-Command Refresh-VehiculesGrid -ErrorAction SilentlyContinue)) {
                    $includeVeh = $false
                    if ($chkVehicules -is [System.Windows.Forms.CheckBox]) { $includeVeh = $chkVehicules.Checked }
                    Refresh-VehiculesGrid -Grid $vehiculesGrid -IncludeHistorique $includeVeh -EmptyStateLabel $lblVehiculesEmpty
                }
            }
            catch {
                if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                    Write-Log '[Outils] Erreur import' 'ERROR' @{ message = $_.Exception.Message }
                }
                else {
                    Write-OutilsPanelLog ("Erreur import : {0}" -f $_.Exception.Message)
                }
                [System.Windows.Forms.MessageBox]::Show(
                    ("Erreur lors de l'import : {0}" -f $_.Exception.Message),
                    'Erreur',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                ) | Out-Null
            }
        })

        $grpSuperviseur.Controls.AddRange(@($btnExport, $btnImport))
        $panel.Controls.Add($grpSuperviseur)
    }

    $grpVideoY = if ($showSuperviseurOutils) { 280 } else { 220 }
    $grpVideo = [System.Windows.Forms.GroupBox]::new()
    $grpVideo.Name = 'grpVideo'
    $grpVideo.Text = 'Video de demonstration'
    $grpVideo.Location = [System.Drawing.Point]::new(0, $grpVideoY)
    $grpVideo.Size = [System.Drawing.Size]::new(700, 130)
    $grpVideo.Font = $script:PoliceTitre3

    $chkPlayVideo = [System.Windows.Forms.CheckBox]::new()
    $chkPlayVideo.Name = 'chkPlayVideo'
    $chkPlayVideo.Text = "Lancer la video au clic sur Lancer (Edition planning)"
    $chkPlayVideo.Location = [System.Drawing.Point]::new(15, 30)
    $chkPlayVideo.Size = [System.Drawing.Size]::new(500, 25)
    $chkPlayVideo.Checked = (([string](Get-PlanningRebuildSetting -Key 'play_video_after_treatment')) -eq '1')
    $grpVideo.Controls.Add($chkPlayVideo)

    $lblVideoPath = [System.Windows.Forms.Label]::new()
    $lblVideoPath.Text = 'Chemin de la video :'
    $lblVideoPath.Location = [System.Drawing.Point]::new(15, 65)
    $lblVideoPath.Size = [System.Drawing.Size]::new(120, 25)
    $grpVideo.Controls.Add($lblVideoPath)

    $txtVideoPath = [System.Windows.Forms.TextBox]::new()
    $txtVideoPath.Name = 'txtVideoPath'
    $pathSetting = [string](Get-PlanningRebuildSetting -Key 'video_path')
    if ([string]::IsNullOrWhiteSpace($pathSetting)) {
        $pathSetting = 'media/videos/tutoriel_convention_nommage.mp4'
    }
    $txtVideoPath.Text = $pathSetting
    $txtVideoPath.Location = [System.Drawing.Point]::new(140, 65)
    $txtVideoPath.Size = [System.Drawing.Size]::new(400, 25)
    $grpVideo.Controls.Add($txtVideoPath)

    $btnBrowseVideo = [System.Windows.Forms.Button]::new()
    $btnBrowseVideo.Name = 'btnBrowseVideo'
    $btnBrowseVideo.Text = 'Parcourir'
    $btnBrowseVideo.Size = [System.Drawing.Size]::new(100, 25)
    $btnBrowseVideo.Location = [System.Drawing.Point]::new(550, 65)
    $btnBrowseVideo.Add_Click({
        param($sender, $e)
        $ofd = [System.Windows.Forms.OpenFileDialog]::new()
        $ofd.Filter = 'Fichiers video (*.mp4;*.avi;*.mov;*.wmv)|*.mp4;*.avi;*.mov;*.wmv'
        $ofd.Title = 'Selectionnez la video tutoriel'
        if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

        $parent = $sender.Parent
        $tb = $null
        if ($null -ne $parent) {
            foreach ($ctrl in @($parent.Controls)) {
                if ($ctrl -is [System.Windows.Forms.TextBox] -and [string]$ctrl.Name -eq 'txtVideoPath') {
                    $tb = $ctrl
                    break
                }
            }
        }
        if ($null -ne $tb) {
            $tb.Text = $ofd.FileName
        }
        else {
            [System.Windows.Forms.MessageBox]::Show(
                'Controle chemin video introuvable.',
                'Erreur',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })
    $grpVideo.Controls.Add($btnBrowseVideo)

    $lblDelay = [System.Windows.Forms.Label]::new()
    $lblDelay.Text = 'Delai avant lancement :'
    $lblDelay.Location = [System.Drawing.Point]::new(15, 100)
    $lblDelay.Size = [System.Drawing.Size]::new(150, 25)
    $grpVideo.Controls.Add($lblDelay)

    $numDelay = [System.Windows.Forms.NumericUpDown]::new()
    $numDelay.Name = 'numDelay'
    $numDelay.Minimum = 0
    $numDelay.Maximum = 3600
    $delayVal = 5
    $delaySetting = Get-PlanningRebuildSetting -Key 'video_delay_seconds'
    if ($null -ne $delaySetting -and -not [string]::IsNullOrWhiteSpace([string]$delaySetting)) {
        try { $delayVal = [int]$delaySetting } catch { $delayVal = 5 }
    }
    $numDelay.Value = [Math]::Max(0, [Math]::Min(30, $delayVal))
    $numDelay.Location = [System.Drawing.Point]::new(170, 100)
    $numDelay.Size = [System.Drawing.Size]::new(60, 25)
    $grpVideo.Controls.Add($numDelay)

    $lblDelayUnit = [System.Windows.Forms.Label]::new()
    $lblDelayUnit.Text = 'secondes'
    $lblDelayUnit.Location = [System.Drawing.Point]::new(240, 100)
    $lblDelayUnit.Size = [System.Drawing.Size]::new(80, 25)
    $grpVideo.Controls.Add($lblDelayUnit)

    $panel.Controls.Add($grpVideo)

    $autoSaveReady = $false
    $settingsCtx = @{
        ChkPlayVideo = $chkPlayVideo
        TxtVideoPath = $txtVideoPath
        NumDelay     = $numDelay
    }
    $panel.Tag = $settingsCtx

    $chkPlayVideo.Add_CheckedChanged({
        param($sender, $e)
        if (-not $autoSaveReady) { return }
        $value = if ($sender.Checked) { '1' } else { '0' }
        Set-PlanningRebuildSetting -Key 'play_video_after_treatment' -Value $value
        if ($value -eq '0' -and (Get-Command Stop-PlanningRebuildPendingVideoTimer -ErrorAction SilentlyContinue)) {
            Stop-PlanningRebuildPendingVideoTimer
        }
        Write-OutilsPanelLog "Auto-save : play_video = $value"
    })

    $numDelay.Add_ValueChanged({
        param($sender, $e)
        if (-not $autoSaveReady) { return }
        $value = $sender.Value.ToString()
        Set-PlanningRebuildSetting -Key 'video_delay_seconds' -Value $value
        Write-OutilsPanelLog "Auto-save : delay = $value"
    })

    $txtVideoPath.Add_TextChanged({
        param($sender, $e)
        if (-not $autoSaveReady) { return }
        $value = [string]$sender.Text
        if ([string]::IsNullOrWhiteSpace($value)) { return }
        Set-PlanningRebuildSetting -Key 'video_path' -Value $value
        Write-OutilsPanelLog "Auto-save : video_path = $value"
    })

    $autoSaveReady = $true

    return $panel
}

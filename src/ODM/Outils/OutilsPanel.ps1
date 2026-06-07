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

    $grpVideo = [System.Windows.Forms.GroupBox]::new()
    $grpVideo.Name = 'grpVideo'
    $grpVideo.Text = 'Video de demonstration'
    $grpVideo.Location = [System.Drawing.Point]::new(0, 60)
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

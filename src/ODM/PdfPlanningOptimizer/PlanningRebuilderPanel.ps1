. "$PSScriptRoot\Services\PlanningRebuilder.ps1"
. "$PSScriptRoot\..\..\Common\Styles.ps1"

$script:PlanningCurrentProgressLine = $null
$script:PlanningProgressTextStart = 0
$script:PlanningActiveStepIndex = 0
$script:PlanningSubStepTextStart = 0
$script:PlanningSubStepOpen = $false
$script:PlanningLastTourHeaderIndex = 0
$script:PlanningStepHadSubLines = $false
$script:PlanningCurrentStepIndex = 0
$script:PlanningProgressHadError = $false
$script:PlanningExcelSubStepProgressStart = 0
$script:PlanningStep2ActivityTimer = $null
$script:PlanningStep2ActivityLabel = $null
$script:PlanningStep2EllipsisPhase = 0
$script:PlanningStep2ActivityActive = $false

function Stop-PlanningRebuildStep2ActivityAnimation {
    $script:PlanningStep2ActivityActive = $false
    if ($null -ne $script:PlanningStep2ActivityTimer) {
        $script:PlanningStep2ActivityTimer.Stop()
    }
    if ($null -ne $script:PlanningStep2ActivityLabel) {
        $script:PlanningStep2ActivityLabel.Visible = $false
        $script:PlanningStep2ActivityLabel.Text = ''
    }
}

function Start-PlanningRebuildStep2ActivityAnimation {
    param([System.Windows.Forms.Label]$ActivityLabel)
    if ($null -eq $ActivityLabel) { return }
    if ($script:PlanningStep2ActivityActive -and $script:PlanningStep2ActivityLabel -eq $ActivityLabel) { return }

    Stop-PlanningRebuildStep2ActivityAnimation
    $script:PlanningStep2ActivityLabel = $ActivityLabel
    $script:PlanningStep2EllipsisPhase = 0
    $script:PlanningStep2ActivityActive = $true
    $ActivityLabel.Visible = $true
    $ActivityLabel.Text = 'Analyse en cours.'

    if ($null -eq $script:PlanningStep2ActivityTimer) {
        $script:PlanningStep2ActivityTimer = [System.Windows.Forms.Timer]::new()
        $script:PlanningStep2ActivityTimer.Interval = 450
        $script:PlanningStep2ActivityTimer.Add_Tick({
            if (-not $script:PlanningStep2ActivityActive -or $null -eq $script:PlanningStep2ActivityLabel) { return }
            $script:PlanningStep2EllipsisPhase = ($script:PlanningStep2EllipsisPhase + 1) % 4
            $dots = switch ($script:PlanningStep2EllipsisPhase) {
                0 { '.' }
                1 { '..' }
                2 { '...' }
                default { '.' }
            }
            $script:PlanningStep2ActivityLabel.Text = "Analyse en cours$dots"
        })
    }
    $script:PlanningStep2ActivityTimer.Start()
}

function Sync-PlanningRebuildStep2ActivityAnimation {
    param(
        [int]$StepIndex,
        [string]$Status
    )
    if ($StepIndex -eq 2) {
        if ($Status -in @('SubStepStart', 'SubStepProgress', 'SubStepEnd', 'SubRunning', 'SubOK', 'Running')) {
            Start-PlanningRebuildStep2ActivityAnimation -ActivityLabel $script:PlanningStep2ActivityLabel
        }
        elseif ($Status -in @('OK', 'Error', 'SubStepError')) {
            Stop-PlanningRebuildStep2ActivityAnimation
        }
        return
    }
    if ($StepIndex -gt 2 -and $script:PlanningStep2ActivityActive) {
        Stop-PlanningRebuildStep2ActivityAnimation
    }
}

function Reset-PlanningRebuildProgressUiState {
    $script:PlanningCurrentProgressLine = $null
    $script:PlanningProgressTextStart = 0
    $script:PlanningActiveStepIndex = 0
    $script:PlanningSubStepTextStart = 0
    $script:PlanningSubStepOpen = $false
    $script:PlanningLastTourHeaderIndex = 0
    $script:PlanningStepHadSubLines = $false
    $script:PlanningExcelSubStepProgressStart = 0
}

function Get-PlanningRebuildOutputFileSizeLabel {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return 'inconnue'
    }
    $bytes = (Get-Item -LiteralPath $Path).Length
    $fr = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    if ($bytes -ge 1048576) {
        $mo = [double]$bytes / 1048576.0
        return ('{0} Mo ({1} octets)' -f ($mo.ToString('0.0', $fr)), ($bytes.ToString('N0', $fr)))
    }
    if ($bytes -ge 1024) {
        $ko = [double]$bytes / 1024.0
        return ('{0} Ko ({1} octets)' -f ($ko.ToString('0.0', $fr)), ($bytes.ToString('N0', $fr)))
    }
    return ('{0} octets' -f ($bytes.ToString('N0', $fr)))
}

function Scroll-PlanningRebuildDebugToEnd {
    param([System.Windows.Forms.TextBoxBase]$DebugBox)
    if ($null -eq $DebugBox) { return }

    $DebugBox.Select($DebugBox.TextLength, 0)
    $DebugBox.ScrollToCaret()
    $DebugBox.SelectionStart = $DebugBox.TextLength
    $DebugBox.SelectionLength = 0
    if (-not $DebugBox.Focused) { [void]$DebugBox.Focus() }
    $DebugBox.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

function Add-PlanningRebuildDebugLogLine {
    param(
        [System.Windows.Forms.TextBoxBase]$DebugBox,
        [string]$Line
    )
    if ($null -eq $DebugBox -or [string]::IsNullOrWhiteSpace($Line)) { return }
    [void]$DebugBox.AppendText($Line + [Environment]::NewLine)
    Scroll-PlanningRebuildDebugToEnd -DebugBox $DebugBox
}

function Update-PlanningRebuildDebugProgress {
    param(
        [System.Windows.Forms.TextBoxBase]$DebugBox,
        [System.Windows.Forms.ProgressBar]$ProgressBar,
        [int]$StepIndex,
        [int]$StepCount,
        [string]$Label,
        [ValidateSet('Running', 'OK', 'Error', 'SubRunning', 'SubOK', 'SubError', 'SubStepStart', 'SubStepProgress', 'SubStepEnd', 'SubStepError', 'TourRunning', 'TourInfo', 'TreeLine', 'TourneeStart', 'TourneeProgress', 'TourneeEnd', 'Complete')]
        [string]$Status,
        [string]$Detail = $null,
        [int]$Percent = -1,
        [string]$SubStep = $null,
        [int]$SubStepIndex = 0,
        [int]$SubStepCount = 0,
        [string]$TreePrefix = $null,
        [string]$OutputPath = $null
    )

    if ($null -eq $DebugBox) {
        return
    }

    Sync-PlanningRebuildStep2ActivityAnimation -StepIndex $StepIndex -Status $Status

    if ($Status -eq 'Complete') {
        Stop-PlanningRebuildStep2ActivityAnimation
        $DebugBox.Clear()
        Reset-PlanningRebuildProgressUiState
        $script:PlanningCurrentStepIndex = 0
        $script:PlanningProgressHadError = $false
        $outPath = if (-not [string]::IsNullOrWhiteSpace($OutputPath)) { [string]$OutputPath } else { [string]$Detail }
        $sizeLabel = Get-PlanningRebuildOutputFileSizeLabel -Path $outPath
        [void]$DebugBox.AppendText('========================================' + [Environment]::NewLine)
        [void]$DebugBox.AppendText('[SUCCES] TRAITEMENT TERMINE' + [Environment]::NewLine)
        [void]$DebugBox.AppendText('========================================' + [Environment]::NewLine)
        if (-not [string]::IsNullOrWhiteSpace($outPath)) {
            [void]$DebugBox.AppendText(('Fichier genere : {0}' -f $outPath) + [Environment]::NewLine)
            [void]$DebugBox.AppendText(('Taille : {0}' -f $sizeLabel) + [Environment]::NewLine)
        }
        [void]$DebugBox.AppendText('========================================' + [Environment]::NewLine)
        if ($null -ne $ProgressBar) { $ProgressBar.Value = 100 }
        Scroll-PlanningRebuildDebugToEnd -DebugBox $DebugBox
        return
    }

    if ($StepIndex -eq 1 -and $Status -eq 'Running' -and -not [string]::IsNullOrWhiteSpace($Detail) -and $Detail -match '(?i)^pages extraites\s*:') {
        $script:PlanningStepHadSubLines = $false
        $script:PlanningActiveStepIndex = $StepIndex
        $script:PlanningCurrentStepIndex = $StepIndex
        $newLine = ('[{0}/{1}] Extraction PDF... {2}' -f $StepIndex, $StepCount, $Detail)
        if ($null -ne $script:PlanningCurrentProgressLine -and $script:PlanningActiveStepIndex -eq $StepIndex -and $DebugBox.Text.Length -ge $script:PlanningProgressTextStart) {
            $DebugBox.Text = $DebugBox.Text.Substring(0, $script:PlanningProgressTextStart)
        }
        elseif ($DebugBox.Text.Length -gt 0 -and -not $DebugBox.Text.EndsWith([Environment]::NewLine)) {
            [void]$DebugBox.AppendText([Environment]::NewLine)
            $script:PlanningProgressTextStart = $DebugBox.Text.Length
        }
        else {
            $script:PlanningProgressTextStart = $DebugBox.Text.Length
        }
        [void]$DebugBox.AppendText($newLine)
        $script:PlanningCurrentProgressLine = $newLine
        if ($null -ne $ProgressBar -and $Percent -ge 0) {
            $clamped = [Math]::Min(100, [Math]::Max($ProgressBar.Minimum, $Percent))
            if ($ProgressBar.Value -ne $clamped) { $ProgressBar.Value = $clamped }
        }
        Scroll-PlanningRebuildDebugToEnd -DebugBox $DebugBox
        return
    }

    if ($StepIndex -eq 5 -and $Status -eq 'TourneeStart') {
        $DebugBox.Clear()
        Reset-PlanningRebuildProgressUiState
        $script:PlanningCurrentStepIndex = 5
        $script:PlanningStepHadSubLines = $true
        $script:PlanningActiveStepIndex = 5
        $script:PlanningProgressTextStart = 0
        [void]$DebugBox.AppendText(('[{0}/{1}] {2}...{3}' -f $StepIndex, $StepCount, $Label, [Environment]::NewLine))
        [void]$DebugBox.AppendText([Environment]::NewLine)
        [void]$DebugBox.AppendText('  Phase 2 : Traitement des tournees' + [Environment]::NewLine)
        $tourIdx = if (-not [string]::IsNullOrWhiteSpace($Detail)) { [string]$Detail } else { '?' }
        [void]$DebugBox.AppendText(("  Tournee {0} en cours{1}" -f $tourIdx, [Environment]::NewLine))
        [void]$DebugBox.AppendText([Environment]::NewLine)
        $script:PlanningCurrentProgressLine = ('[{0}/{1}] {2}...' -f $StepIndex, $StepCount, $Label)
        if ($null -ne $ProgressBar -and $Percent -ge 0) {
            $clamped = [Math]::Min(100, [Math]::Max($ProgressBar.Minimum, $Percent))
            if ($ProgressBar.Value -ne $clamped) { $ProgressBar.Value = $clamped }
        }
        Scroll-PlanningRebuildDebugToEnd -DebugBox $DebugBox
        return
    }

    if ($StepIndex -eq 5 -and $Status -eq 'TourneeProgress' -and -not [string]::IsNullOrWhiteSpace($Detail)) {
        $script:PlanningStepHadSubLines = $true
        [void]$DebugBox.AppendText(('  {0}{1}' -f $Detail, [Environment]::NewLine))
        if ($null -ne $ProgressBar -and $Percent -ge 0) {
            $clamped = [Math]::Min(100, [Math]::Max($ProgressBar.Minimum, $Percent))
            if ($ProgressBar.Value -ne $clamped) { $ProgressBar.Value = $clamped }
        }
        Scroll-PlanningRebuildDebugToEnd -DebugBox $DebugBox
        return
    }

    if ($StepIndex -eq 5 -and $Status -eq 'TourneeEnd') {
        return
    }

    if ($StepIndex -eq 2 -and $Status -eq 'SubStepStart') {
        $DebugBox.Clear()
        Reset-PlanningRebuildProgressUiState
        $script:PlanningCurrentStepIndex = 2
        $script:PlanningStepHadSubLines = $true
        $script:PlanningActiveStepIndex = 2
        $stepNum = if ($SubStepIndex -gt 0) { $SubStepIndex } else { 1 }
        $stepTotal = if ($SubStepCount -gt 0) { $SubStepCount } else { 8 }
        $title = if (-not [string]::IsNullOrWhiteSpace($SubStep)) { [string]$SubStep } else { [string]$Detail }
        $title = $title.TrimEnd('.')
        [void]$DebugBox.AppendText(('[{0}/{1}] {2}...{3}' -f $StepIndex, $StepCount, $Label, [Environment]::NewLine))
        [void]$DebugBox.AppendText([Environment]::NewLine)
        $script:PlanningExcelSubStepProgressStart = $DebugBox.Text.Length
        [void]$DebugBox.AppendText(('  Etape {0}/{1} : {2}...' -f $stepNum, $stepTotal, $title))
        $script:PlanningCurrentProgressLine = ('[{0}/{1}] {2}...' -f $StepIndex, $StepCount, $Label)
        if ($null -ne $ProgressBar -and $Percent -ge 0) {
            $clamped = [Math]::Min(100, [Math]::Max($ProgressBar.Minimum, $Percent))
            if ($ProgressBar.Value -ne $clamped) { $ProgressBar.Value = $clamped }
        }
        Scroll-PlanningRebuildDebugToEnd -DebugBox $DebugBox
        return
    }

    if ($StepIndex -eq 2 -and $Status -eq 'SubStepProgress' -and -not [string]::IsNullOrWhiteSpace($Detail)) {
        $script:PlanningStepHadSubLines = $true
        if ($DebugBox.Text.Length -ge $script:PlanningExcelSubStepProgressStart) {
            $DebugBox.Text = $DebugBox.Text.Substring(0, $script:PlanningExcelSubStepProgressStart)
        }
        $script:PlanningExcelSubStepProgressStart = $DebugBox.Text.Length
        [void]$DebugBox.AppendText(('  {0}' -f $Detail))
        if ($null -ne $ProgressBar -and $Percent -ge 0) {
            $clamped = [Math]::Min(100, [Math]::Max($ProgressBar.Minimum, $Percent))
            if ($ProgressBar.Value -ne $clamped) { $ProgressBar.Value = $clamped }
        }
        Scroll-PlanningRebuildDebugToEnd -DebugBox $DebugBox
        return
    }

    if ($StepIndex -eq 2 -and $Status -eq 'SubStepEnd') {
        $script:PlanningStepHadSubLines = $true
        $title = if (-not [string]::IsNullOrWhiteSpace($SubStep)) { [string]$SubStep } else { 'Etape' }
        $title = $title.TrimEnd('.')
        if ($DebugBox.Text.Length -ge $script:PlanningExcelSubStepProgressStart) {
            $DebugBox.Text = $DebugBox.Text.Substring(0, $script:PlanningExcelSubStepProgressStart)
        }
        $resultSuffix = ''
        if (-not [string]::IsNullOrWhiteSpace($Detail)) {
            $d = [string]$Detail
            if (-not $d.StartsWith(' ') -and -not $d.StartsWith('(')) { $d = " $d" }
            $resultSuffix = $d
        }
        [void]$DebugBox.AppendText(('  {0}... [OK]{1}' -f $title, $resultSuffix))
        [void]$DebugBox.AppendText([Environment]::NewLine)
        if ($null -ne $ProgressBar -and $Percent -ge 0) {
            $clamped = [Math]::Min(100, [Math]::Max($ProgressBar.Minimum, $Percent))
            if ($ProgressBar.Value -ne $clamped) { $ProgressBar.Value = $clamped }
        }
        Scroll-PlanningRebuildDebugToEnd -DebugBox $DebugBox
        return
    }

    if ($StepIndex -eq 2 -and $Status -eq 'SubStepError') {
        $script:PlanningProgressHadError = $true
        $title = if (-not [string]::IsNullOrWhiteSpace($SubStep)) { [string]$SubStep } else { 'Etape' }
        $errSuffix = ''
        if (-not [string]::IsNullOrWhiteSpace($Detail)) {
            $errSuffix = if ([string]$Detail.StartsWith(' ')) { [string]$Detail } else { " $Detail" }
        }
        if ($DebugBox.Text.Length -ge $script:PlanningExcelSubStepProgressStart) {
            $DebugBox.Text = $DebugBox.Text.Substring(0, $script:PlanningExcelSubStepProgressStart)
        }
        [void]$DebugBox.AppendText(('  {0}... [ERREUR]{1}' -f $title, $errSuffix))
        [void]$DebugBox.AppendText([Environment]::NewLine)
        Scroll-PlanningRebuildDebugToEnd -DebugBox $DebugBox
        return
    }

    $detailSuffix = ''
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        $detailSuffix = " $Detail"
    }

    if ($Status -eq 'Error') {
        $script:PlanningProgressHadError = $true
    }
    elseif ($Status -eq 'Running' -and $StepIndex -gt 0 -and -not $script:PlanningProgressHadError) {
        if ($script:PlanningCurrentStepIndex -ne 0 -and $StepIndex -ne $script:PlanningCurrentStepIndex) {
            $DebugBox.Clear()
            Reset-PlanningRebuildProgressUiState
        }
        $script:PlanningCurrentStepIndex = $StepIndex
    }

    switch ($Status) {
        'Running' {
            $script:PlanningStepHadSubLines = $false
            $line = ('[{0}/{1}] {2}...{3}' -f $StepIndex, $StepCount, $Label, $detailSuffix)
            if ($null -ne $script:PlanningCurrentProgressLine -and $script:PlanningActiveStepIndex -eq $StepIndex) {
                if ($DebugBox.Text.Length -ge $script:PlanningProgressTextStart) {
                    $DebugBox.Text = $DebugBox.Text.Substring(0, $script:PlanningProgressTextStart)
                }
            }
            else {
                $script:PlanningProgressTextStart = $DebugBox.Text.Length
            }
            [void]$DebugBox.AppendText($line)
            $script:PlanningCurrentProgressLine = $line
            $script:PlanningActiveStepIndex = $StepIndex
        }
        'OK' {
            $line = ('[{0}/{1}] {2}... [OK]{3}' -f $StepIndex, $StepCount, $Label, $detailSuffix)
            if ($script:PlanningStepHadSubLines) {
                if ($DebugBox.Text.Length -gt 0 -and -not $DebugBox.Text.EndsWith([Environment]::NewLine)) {
                    [void]$DebugBox.AppendText([Environment]::NewLine)
                }
                [void]$DebugBox.AppendText($line)
                [void]$DebugBox.AppendText([Environment]::NewLine)
            }
            else {
                if ($null -ne $script:PlanningCurrentProgressLine -and $DebugBox.Text.Length -ge $script:PlanningProgressTextStart) {
                    $DebugBox.Text = $DebugBox.Text.Substring(0, $script:PlanningProgressTextStart)
                }
                [void]$DebugBox.AppendText($line)
                [void]$DebugBox.AppendText([Environment]::NewLine)
            }
            $script:PlanningCurrentProgressLine = $null
            $script:PlanningActiveStepIndex = 0
            $script:PlanningProgressTextStart = $DebugBox.Text.Length
            $script:PlanningSubStepOpen = $false
            $script:PlanningStepHadSubLines = $false
        }
        'Error' {
            if ($null -ne $script:PlanningCurrentProgressLine -and $DebugBox.Text.Length -ge $script:PlanningProgressTextStart) {
                $DebugBox.Text = $DebugBox.Text.Substring(0, $script:PlanningProgressTextStart)
            }
            $line = ('[{0}/{1}] {2}... [ERREUR]{3}' -f $StepIndex, $StepCount, $Label, $detailSuffix)
            [void]$DebugBox.AppendText($line)
            [void]$DebugBox.AppendText([Environment]::NewLine)
            $script:PlanningCurrentProgressLine = $null
            $script:PlanningActiveStepIndex = 0
            $script:PlanningProgressTextStart = $DebugBox.Text.Length
            $script:PlanningSubStepOpen = $false
        }
        'SubRunning' {
            $script:PlanningStepHadSubLines = $true
            if ($null -ne $script:PlanningCurrentProgressLine -and $script:PlanningActiveStepIndex -eq $StepIndex) {
                if ($DebugBox.Text.Length -gt 0 -and -not $DebugBox.Text.EndsWith([Environment]::NewLine)) {
                    [void]$DebugBox.AppendText([Environment]::NewLine)
                }
            }
            if ($script:PlanningSubStepOpen -and $DebugBox.Text.Length -ge $script:PlanningSubStepTextStart) {
                $DebugBox.Text = $DebugBox.Text.Substring(0, $script:PlanningSubStepTextStart)
            }
            $script:PlanningSubStepTextStart = $DebugBox.Text.Length
            $msg = if (-not [string]::IsNullOrWhiteSpace($SubStep)) { $SubStep } else { [string]$Detail }
            $msg = $msg.TrimEnd('.')
            [void]$DebugBox.AppendText(('  {0}...' -f $msg))
            $script:PlanningSubStepOpen = $true
        }
        'SubOK' {
            if ($script:PlanningSubStepOpen -and $DebugBox.Text.Length -ge $script:PlanningSubStepTextStart) {
                $DebugBox.Text = $DebugBox.Text.Substring(0, $script:PlanningSubStepTextStart)
            }
            $msg = if (-not [string]::IsNullOrWhiteSpace($SubStep)) { $SubStep } else { [string]$Detail }
            $msg = $msg.TrimEnd('.')
            $mid = if (-not [string]::IsNullOrWhiteSpace($Detail) -and -not [string]::IsNullOrWhiteSpace($SubStep)) { $Detail } else { '' }
            if ([string]::IsNullOrWhiteSpace($mid)) {
                [void]$DebugBox.AppendText(('  {0}... [OK]' -f $msg))
            }
            else {
                if (-not $mid.StartsWith(' ') -and -not $mid.StartsWith('(')) { $mid = " $mid" }
                [void]$DebugBox.AppendText(('  {0}...{1} [OK]' -f $msg, $mid))
            }
            [void]$DebugBox.AppendText([Environment]::NewLine)
            $script:PlanningSubStepOpen = $false
            $script:PlanningSubStepTextStart = $DebugBox.Text.Length
        }
        'SubError' {
            if ($script:PlanningSubStepOpen -and $DebugBox.Text.Length -ge $script:PlanningSubStepTextStart) {
                $DebugBox.Text = $DebugBox.Text.Substring(0, $script:PlanningSubStepTextStart)
            }
            $msg = if (-not [string]::IsNullOrWhiteSpace($SubStep)) { $SubStep } else { [string]$Detail }
            [void]$DebugBox.AppendText(('  {0}... [ERREUR]{1}' -f $msg, $detailSuffix))
            [void]$DebugBox.AppendText([Environment]::NewLine)
            $script:PlanningSubStepOpen = $false
            $script:PlanningSubStepTextStart = $DebugBox.Text.Length
        }
        'TourRunning' {
            $script:PlanningStepHadSubLines = $true
            if ($SubStepIndex -gt 1 -and $script:PlanningLastTourHeaderIndex -ne $SubStepIndex) {
                [void]$DebugBox.AppendText([Environment]::NewLine)
            }
            $script:PlanningLastTourHeaderIndex = $SubStepIndex
            $hdr = if (-not [string]::IsNullOrWhiteSpace($SubStep)) { $SubStep } else { 'Tournee' }
            $suffix = if (-not [string]::IsNullOrWhiteSpace($Detail)) { " : $Detail" } else { '' }
            if ($SubStepCount -gt 0) {
                $line = ('  {0} {1}/{2}{3}' -f $hdr, $SubStepIndex, $SubStepCount, $suffix)
            }
            else {
                $line = ('  {0}{1}' -f $hdr, $suffix)
            }
            [void]$DebugBox.AppendText($line)
            [void]$DebugBox.AppendText([Environment]::NewLine)
        }
        'TourInfo' {
            $script:PlanningStepHadSubLines = $true
            $info = if (-not [string]::IsNullOrWhiteSpace($Detail)) { $Detail } else { [string]$SubStep }
            if (-not [string]::IsNullOrWhiteSpace($info)) {
                [void]$DebugBox.AppendText(('    {0}' -f $info))
                [void]$DebugBox.AppendText([Environment]::NewLine)
            }
        }
        'TreeLine' {
            $script:PlanningStepHadSubLines = $true
            if ($null -ne $script:PlanningCurrentProgressLine -and $script:PlanningActiveStepIndex -eq $StepIndex) {
                if ($DebugBox.Text.Length -gt 0 -and -not $DebugBox.Text.EndsWith([Environment]::NewLine)) {
                    [void]$DebugBox.AppendText([Environment]::NewLine)
                }
            }
            if ([string]::IsNullOrWhiteSpace($Detail)) { $Detail = '' }
            $pfx = if ($null -ne $TreePrefix) { [string]$TreePrefix } else { '' }
            $txt = [string]$Detail
            if (-not [string]::IsNullOrWhiteSpace($txt)) {
                [void]$DebugBox.AppendText($pfx + $txt)
            }
            [void]$DebugBox.AppendText([Environment]::NewLine)
        }
    }

    if ($null -ne $ProgressBar -and $Percent -ge 0) {
        $clamped = [Math]::Min(100, [Math]::Max($ProgressBar.Minimum, $Percent))
        if ($ProgressBar.Value -ne $clamped) {
            $ProgressBar.Value = $clamped
        }
    }

    Scroll-PlanningRebuildDebugToEnd -DebugBox $DebugBox
}

function Show-PlanningRebuilderPanel {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $script:PlanningPdfPath = $null
    $script:PlanningExcelPath = $null

    $panel = [System.Windows.Forms.Panel]::new()
    $panel.Name = "PlanningRebuilderPanel"
    $panel.Dock = "Fill"
    $panel.BackColor = $script:CouleurGrisFond
    $panel.Padding = [System.Windows.Forms.Padding]::new(20)

    $lblTitle = [System.Windows.Forms.Label]::new()
    $lblTitle.Text = "Edition du planning"
    $lblTitle.Font = $script:PoliceTitreGestionFenetre
    $lblTitle.ForeColor = $script:CouleurOrange
    $lblTitle.Location = [System.Drawing.Point]::new(20, 20)
    $lblTitle.Size = [System.Drawing.Size]::new(500, 50)
    $panel.Controls.Add($lblTitle)

    $lblPdf = [System.Windows.Forms.Label]::new()
    $lblPdf.Name = "lblPdf"
    $lblPdf.Text = "PDF: non selectionne"
    $lblPdf.Font = $script:PoliceLabelSecondaireFenetre
    $lblPdf.ForeColor = $script:CouleurTexteSecondairePanel
    $lblPdf.Location = [System.Drawing.Point]::new(20, 80)
    $lblPdf.Size = [System.Drawing.Size]::new(1100, 22)
    $panel.Controls.Add($lblPdf)

    $lblExcel = [System.Windows.Forms.Label]::new()
    $lblExcel.Name = "lblExcel"
    $lblExcel.Text = "Excel: non selectionne"
    $lblExcel.Font = $script:PoliceLabelSecondaireFenetre
    $lblExcel.ForeColor = $script:CouleurTexteSecondairePanel
    $lblExcel.Location = [System.Drawing.Point]::new(20, 105)
    $lblExcel.Size = [System.Drawing.Size]::new(1100, 22)
    $panel.Controls.Add($lblExcel)

    $btnPdf = [System.Windows.Forms.Button]::new()
    Set-BtnBorderStyle -Button $btnPdf -Text "Importer PDF" -BorderColor $script:CouleurBleu -Width 170 -Height 45
    $btnPdf.Location = [System.Drawing.Point]::new(20, 140)
    $panel.Controls.Add($btnPdf)

    $btnExcel = [System.Windows.Forms.Button]::new()
    Set-BtnBorderStyle -Button $btnExcel -Text "Importer Excel" -BorderColor $script:CouleurVert -Width 170 -Height 45
    $btnExcel.Location = [System.Drawing.Point]::new(200, 140)
    $panel.Controls.Add($btnExcel)

    $btnRun = [System.Windows.Forms.Button]::new()
    $btnRun.Name = 'btnRunPlanning'
    Set-BtnBorderStyle -Button $btnRun -Text "Lancer le traitement" -BorderColor $script:CouleurCertificat -Width 220 -Height 45
    $btnRun.Location = [System.Drawing.Point]::new(380, 140)
    $panel.Controls.Add($btnRun)

    $txtDebug = [System.Windows.Forms.RichTextBox]::new()
    $txtDebug.Name = "txtDebug"
    $txtDebug.Multiline = $true
    $txtDebug.ScrollBars = "Vertical"
    $txtDebug.ReadOnly = $true
    $txtDebug.HideSelection = $false
    $txtDebug.WordWrap = $false
    $txtDebug.Location = [System.Drawing.Point]::new(20, 200)
    $txtDebug.Size = [System.Drawing.Size]::new(1100, 465)
    $txtDebug.Anchor = "Top,Bottom,Left,Right"
    $panel.Controls.Add($txtDebug)

    $progressBar = [System.Windows.Forms.ProgressBar]::new()
    $progressBar.Name = 'progressBar'
    $progressBar.Location = [System.Drawing.Point]::new(20, 680)
    $progressBar.Size = [System.Drawing.Size]::new(1100, 20)
    $progressBar.Style = 'Continuous'
    $progressBar.Minimum = 0
    $progressBar.Maximum = 100
    $progressBar.Value = 0
    $progressBar.Visible = $true
    $progressBar.Anchor = 'Bottom,Left,Right'
    $panel.Controls.Add($progressBar)

    $lblStep2Activity = [System.Windows.Forms.Label]::new()
    $lblStep2Activity.Name = 'lblStep2Activity'
    $lblStep2Activity.Text = ''
    $lblStep2Activity.Visible = $false
    $lblStep2Activity.AutoSize = $true
    $lblStep2Activity.Location = [System.Drawing.Point]::new(20, 668)
    $lblStep2Activity.Font = $script:PoliceLabelSecondaireFenetre
    $lblStep2Activity.ForeColor = $script:CouleurTexteSecondairePanel
    $lblStep2Activity.Anchor = 'Bottom,Left'
    $panel.Controls.Add($lblStep2Activity)
    $script:PlanningStep2ActivityLabel = $lblStep2Activity

    function script:Get-PlanningCtrl {
        param(
            [System.Windows.Forms.Control]$Root,
            [string]$Name,
            [Type]$ExpectedType
        )
        if ($null -eq $Root) { return $null }
        $ctrl = $Root.Controls[$Name]
        if ($null -eq $ctrl) { return $null }
        if ($null -ne $ExpectedType -and $ctrl -isnot $ExpectedType) { return $null }
        return $ctrl
    }

    $btnPdf.Add_Click({
        $ofd = [System.Windows.Forms.OpenFileDialog]::new()
        $ofd.Filter = "PDF (*.pdf)|*.pdf|Tous les fichiers (*.*)|*.*"
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:PlanningPdfPath = $ofd.FileName
            $root = $this.Parent
            $lbl = Get-PlanningCtrl -Root $root -Name "lblPdf" -ExpectedType ([System.Windows.Forms.Label])
            if ($null -ne $lbl) {
                $lbl.Text = "PDF: $($script:PlanningPdfPath)"
            }
        }
    })

    $btnExcel.Add_Click({
        $ofd = [System.Windows.Forms.OpenFileDialog]::new()
        $ofd.Filter = "Excel (*.xlsx;*.xlsm;*.xls)|*.xlsx;*.xlsm;*.xls|Tous les fichiers (*.*)|*.*"
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:PlanningExcelPath = $ofd.FileName
            $root = $this.Parent
            $lbl = Get-PlanningCtrl -Root $root -Name "lblExcel" -ExpectedType ([System.Windows.Forms.Label])
            if ($null -ne $lbl) {
                $lbl.Text = "Excel: $($script:PlanningExcelPath)"
            }
        }
    })

    $onRunPlanning = {
        param($sender, $e)
        $__dbg = ($env:CN_DEBUG_PLANNING_UI -in @('1', 'true')) -or ($env:CN_DEBUG_PIPELINE -in @('1', 'true'))
        if ($__dbg) { Write-Host '[DEBUG] CLICK btnRunPlanning' -ForegroundColor Magenta }
        if ($script:PlanningRebuildUiBusy) {
            if ($__dbg) { Write-Host '[DEBUG] IGNORE: double run / deja en cours' -ForegroundColor DarkYellow }
            return
        }

        $root = $this.Parent
        $dbg = Get-PlanningCtrl -Root $root -Name "txtDebug" -ExpectedType ([System.Windows.Forms.TextBoxBase])
        $pbar = Get-PlanningCtrl -Root $root -Name "progressBar" -ExpectedType ([System.Windows.Forms.ProgressBar])
        if ($null -eq $dbg) {
            Write-Host '[DEBUG] txtDebug introuvable ou type incompatible (attendu TextBoxBase/RichTextBox)' -ForegroundColor Red
        }
        if ([string]::IsNullOrWhiteSpace($script:PlanningPdfPath) -or [string]::IsNullOrWhiteSpace($script:PlanningExcelPath)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Selectionnez d'abord un PDF et un Excel.",
                "Edition planning",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            return
        }

        $script:PlanningRebuildUiBusy = $true
        Stop-PlanningRebuildStep2ActivityAnimation
        Reset-PlanningRebuildProgressUiState
        $script:PlanningCurrentStepIndex = 0
        $script:PlanningProgressHadError = $false
        $script:PlanningStep2ActivityLabel = Get-PlanningCtrl -Root $root -Name 'lblStep2Activity' -ExpectedType ([System.Windows.Forms.Label])
        if ($null -ne $btnRun) { $btnRun.Enabled = $false }
        try {
            if ($__dbg) { Write-Host '[DEBUG] ENTER Start-PlanningRebuild (UI)' -ForegroundColor Magenta }
            if ($null -ne $dbg) { $dbg.Clear() }
            if ($null -ne $pbar) { $pbar.Value = 0 }
            [System.Windows.Forms.Application]::DoEvents()

            $progressCb = {
                try {
                if ($args.Count -eq 1 -and $args[0] -is [hashtable]) {
                    $h = $args[0]
                    $st = [string]$h.Status
                    if ($st -eq 'Log') { return }
                    Update-PlanningRebuildDebugProgress -DebugBox $dbg -ProgressBar $pbar `
                        -StepIndex ([int]$h.StepIndex) -StepCount ([int]$h.StepCount) -Label ([string]$h.Label) `
                        -Status $st -Detail ([string]$h.Detail) -Percent $(if ($h.ContainsKey('Percent')) { [int]$h.Percent } else { -1 }) `
                        -TreePrefix ([string]$h.TreePrefix) -OutputPath $(if ($h.ContainsKey('OutputPath')) { [string]$h.OutputPath } else { $null })
                    return
                }
                $StepIndex = [int]$args[0]
                $StepCount = [int]$args[1]
                $Label = [string]$args[2]
                $Status = [string]$args[3]
                $Detail = if ($args.Count -gt 4) { [string]$args[4] } else { $null }
                $Percent = if ($args.Count -gt 5) { [int]$args[5] } else { -1 }
                $SubStep = if ($args.Count -gt 6) { [string]$args[6] } else { $null }
                $SubStepIndex = if ($args.Count -gt 7) { [int]$args[7] } else { 0 }
                $SubStepCount = if ($args.Count -gt 8) { [int]$args[8] } else { 0 }
                $TreePrefix = if ($args.Count -gt 9) { [string]$args[9] } else { $null }
                $OutputPath = if ($args.Count -gt 10) { [string]$args[10] } else { $null }
                if ($Status -eq 'Log') { return }
                Update-PlanningRebuildDebugProgress -DebugBox $dbg -ProgressBar $pbar -StepIndex $StepIndex -StepCount $StepCount `
                    -Label $Label -Status $Status -Detail $Detail -Percent $Percent `
                    -SubStep $SubStep -SubStepIndex $SubStepIndex -SubStepCount $SubStepCount -TreePrefix $TreePrefix -OutputPath $OutputPath
                }
                catch {
                    $stFail = if ($args.Count -eq 1 -and $args[0] -is [hashtable]) { [string]$args[0].Status } else { $Status }
                    Write-Warning ("[PLANNING-UI] progressCb echoue (Status={0}) : {1}" -f $stFail, $_.Exception.Message)
                }
            }

            $result = Start-PlanningRebuild -PdfPath $script:PlanningPdfPath -ExcelPath $script:PlanningExcelPath -ProgressCallback $progressCb

            if ($null -eq $result) {
                if ($null -ne $dbg) {
                    if ($null -eq $script:PlanningCurrentProgressLine) {
                        [void]$dbg.AppendText("Traitement interrompu." + [Environment]::NewLine)
                    }
                    Scroll-PlanningRebuildDebugToEnd -DebugBox $dbg
                }
                if ($null -ne $pbar) { $pbar.Value = 0 }
                return
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$result.OutputPdf)) {
                if ($null -ne $pbar) { $pbar.Value = 100 }
            }

        }
        catch {
            if ($null -ne $dbg) {
                if ($null -ne $script:PlanningCurrentProgressLine) {
                    [void]$dbg.AppendText(' [ERREUR]')
                    [void]$dbg.AppendText([Environment]::NewLine)
                    $script:PlanningCurrentProgressLine = $null
                }
                [void]$dbg.AppendText(("ERREUR: {0}" -f $_.Exception.Message) + [Environment]::NewLine)
                Scroll-PlanningRebuildDebugToEnd -DebugBox $dbg
                [System.Windows.Forms.Application]::DoEvents()
            }
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                "Echec traitement planning",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
        finally {
            Stop-PlanningRebuildStep2ActivityAnimation
            if ($null -ne $btnRun) { $btnRun.Enabled = $true }
            if ($null -ne $pbar -and $null -eq $result) { $pbar.Value = 0 }
            $script:PlanningRebuildUiBusy = $false
        }
    }

    if ($null -eq $script:PlanningRunHandlerRegistry) {
        $script:PlanningRunHandlerRegistry = @{}
    }
    $btnKey = [string]([System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($btnRun))
    if (-not $script:PlanningRunHandlerRegistry.ContainsKey($btnKey)) {
        $null = $btnRun.add_Click($onRunPlanning)
        $script:PlanningRunHandlerRegistry[$btnKey] = $true
    }

    return $panel
}

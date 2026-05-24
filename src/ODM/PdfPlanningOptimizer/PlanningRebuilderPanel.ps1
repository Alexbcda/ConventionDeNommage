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

function Reset-PlanningRebuildProgressUiState {
    $script:PlanningCurrentProgressLine = $null
    $script:PlanningProgressTextStart = 0
    $script:PlanningActiveStepIndex = 0
    $script:PlanningSubStepTextStart = 0
    $script:PlanningSubStepOpen = $false
    $script:PlanningLastTourHeaderIndex = 0
    $script:PlanningStepHadSubLines = $false
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

function Add-PlanningRebuildDebugLogLine {
    param(
        [System.Windows.Forms.TextBox]$DebugBox,
        [string]$Line
    )
    if ($null -eq $DebugBox -or [string]::IsNullOrWhiteSpace($Line)) { return }
    [void]$DebugBox.AppendText($Line + [Environment]::NewLine)
    $DebugBox.SelectionStart = $DebugBox.Text.Length
    $DebugBox.SelectionLength = 0
    $DebugBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Update-PlanningRebuildDebugProgress {
    param(
        [System.Windows.Forms.TextBox]$DebugBox,
        [System.Windows.Forms.ProgressBar]$ProgressBar,
        [int]$StepIndex,
        [int]$StepCount,
        [string]$Label,
        [ValidateSet('Running', 'OK', 'Error', 'SubRunning', 'SubOK', 'SubError', 'TourRunning', 'TourInfo', 'TreeLine', 'Complete')]
        [string]$Status,
        [string]$Detail = $null,
        [int]$Percent = -1,
        [string]$SubStep = $null,
        [int]$SubStepIndex = 0,
        [int]$SubStepCount = 0,
        [string]$TreePrefix = $null,
        [string]$OutputPath = $null
    )
    if ($null -eq $DebugBox) { return }

    if ($Status -eq 'Complete') {
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
        $DebugBox.SelectionStart = $DebugBox.Text.Length
        $DebugBox.SelectionLength = 0
        $DebugBox.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
        return
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

    $detailSuffix = ''
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        $detailSuffix = " $Detail"
    }

    switch ($Status) {
        'Running' {
            $isPageDetail = (-not [string]::IsNullOrWhiteSpace($Detail)) -and ($Detail -match '^(?i)page \d+/\d+$')
            if ($isPageDetail -and $script:PlanningActiveStepIndex -eq $StepIndex -and $null -ne $script:PlanningCurrentProgressLine) {
                $script:PlanningStepHadSubLines = $true
                if ($DebugBox.Text.Length -gt 0 -and -not $DebugBox.Text.EndsWith([Environment]::NewLine)) {
                    [void]$DebugBox.AppendText([Environment]::NewLine)
                }
                [void]$DebugBox.AppendText(('  {0}' -f $Detail))
                [void]$DebugBox.AppendText([Environment]::NewLine)
                break
            }
            $script:PlanningStepHadSubLines = $false
            $line = ('[{0}/{1}] {2}...{3}' -f $StepIndex, $StepCount, $Label, $(if ($isPageDetail) { '' } else { $detailSuffix }))
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

    $DebugBox.SelectionStart = $DebugBox.Text.Length
    $DebugBox.SelectionLength = 0
    $DebugBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
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

    $listResult = [System.Windows.Forms.ListBox]::new()
    $listResult.Name = "listResult"
    $listResult.Location = [System.Drawing.Point]::new(20, 200)
    $listResult.Size = [System.Drawing.Size]::new(1100, 220)
    $listResult.Anchor = "Top,Left,Right"
    $panel.Controls.Add($listResult)

    $txtDebug = [System.Windows.Forms.TextBox]::new()
    $txtDebug.Name = "txtDebug"
    $txtDebug.Multiline = $true
    $txtDebug.ScrollBars = "Vertical"
    $txtDebug.ReadOnly = $true
    $txtDebug.Location = [System.Drawing.Point]::new(20, 435)
    $txtDebug.Size = [System.Drawing.Size]::new(1100, 230)
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
        $list = Get-PlanningCtrl -Root $root -Name "listResult" -ExpectedType ([System.Windows.Forms.ListBox])
        $dbg = Get-PlanningCtrl -Root $root -Name "txtDebug" -ExpectedType ([System.Windows.Forms.TextBox])
        $pbar = Get-PlanningCtrl -Root $root -Name "progressBar" -ExpectedType ([System.Windows.Forms.ProgressBar])
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
        Reset-PlanningRebuildProgressUiState
        $script:PlanningCurrentStepIndex = 0
        $script:PlanningProgressHadError = $false
        if ($null -ne $btnRun) { $btnRun.Enabled = $false }
        try {
            if ($__dbg) { Write-Host '[DEBUG] ENTER Start-PlanningRebuild (UI)' -ForegroundColor Magenta }
            if ($null -ne $list) { $list.Items.Clear() }
            if ($null -ne $dbg) { $dbg.Clear() }
            if ($null -ne $pbar) { $pbar.Value = 0 }
            [System.Windows.Forms.Application]::DoEvents()

            $progressCb = {
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

            $result = Start-PlanningRebuild -PdfPath $script:PlanningPdfPath -ExcelPath $script:PlanningExcelPath -ProgressCallback $progressCb

            if ($null -eq $result) {
                if ($null -ne $list) { $list.Items.Add("Echec : pipeline interrompu (extraction, dates, ou autre arret) — consulter la sortie console.") | Out-Null }
                if ($null -ne $dbg) {
                    if ($null -eq $script:PlanningCurrentProgressLine) {
                        [void]$dbg.AppendText("Traitement interrompu." + [Environment]::NewLine)
                    }
                    $dbg.SelectionStart = $dbg.Text.Length
                    $dbg.ScrollToCaret()
                }
                if ($null -ne $pbar) { $pbar.Value = 0 }
                return
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$result.OutputPdf)) {
                if ($null -ne $pbar) { $pbar.Value = 100 }
            }

            if ($null -ne $list) { $list.Items.Add("Planning final :") | Out-Null }
            foreach ($line in @($result.ReorderedPlanning)) {
                if ($null -ne $list) { $list.Items.Add(("{0} -> {1} [{2}]" -f $line.FinalOrder, $line.ClientName, $line.MatchScore)) | Out-Null }
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
                $dbg.SelectionStart = $dbg.Text.Length
                $dbg.ScrollToCaret()
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

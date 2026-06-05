. "$PSScriptRoot\Services\PlanningRebuilder.ps1"
. (Join-Path $PSScriptRoot '..\..\Common\Styles.ps1')
. (Join-Path $PSScriptRoot '..\..\Common\CnsSharePointConnector.ps1')
. (Join-Path $PSScriptRoot '..\..\Common\CnsSharePointUI.ps1')

if (-not (Get-Command Update-SharePointUI -ErrorAction SilentlyContinue)) {
    throw 'PlanningRebuilderPanel.ps1 : Update-SharePointUI introuvable — verifier le dot-sourcing de CnsSharePointUI.ps1.'
}

# References de commandes en $script: — visibles depuis les closures BackgroundWorker.
$script:UpdateSharePointUiCmd = Get-Command Update-SharePointUI -ErrorAction Stop
$script:ConnectSharePointPlanningCmd = Get-Command Connect-SharePointPlanning -ErrorAction Stop
$script:SyncSharePointPlanningFileCmd = Get-Command Sync-SharePointPlanningFile -ErrorAction Stop
$script:PlanningRebuilderPanelContext = $null
$script:PlanningRunning = $false
$script:PlanningFormClosingRegistered = $false
$script:PlanningHostRunspace = $null
$script:PlanningRebuildJob = $null
$script:PlanningRebuildJobTimer = $null
$script:PlanningProgressTimer = $null
$script:PlanningJobProgressFile = $null
$script:PlanningJobProgressLastLine = $null
$script:SharePointExcelPath = $null
$script:ManualExcelPath = $null
$script:ActiveExcelPath = $null
$script:ManualModeEnabled = $false
$script:CurrentUIMode = 'SharePoint'
$script:PlanningSharePointStatus = 'Offline'

function Test-PlanningSharePointIsConnected {
    return ($script:PlanningSharePointStatus -eq 'Connected')
}

function Test-PlanningAllowsManualExcelImport {
    return $true
}

function Test-PlanningUsesManualExcel {
    return (-not [string]::IsNullOrWhiteSpace($script:ManualExcelPath))
}

function Stop-PlanningRebuildJobIfRunning {
    if ($null -ne $script:PlanningProgressTimer) {
        try { $script:PlanningProgressTimer.Stop() } catch { }
    }
    if ($null -ne $script:PlanningRebuildJobTimer) {
        try { $script:PlanningRebuildJobTimer.Stop() } catch { }
    }
    if ($null -ne $script:PlanningRebuildJob) {
        try {
            if ($script:PlanningRebuildJob.State -eq 'Running') {
                Stop-Job -Job $script:PlanningRebuildJob -ErrorAction SilentlyContinue
            }
        }
        catch { }
        Remove-Job -Job $script:PlanningRebuildJob -Force -ErrorAction SilentlyContinue
        $script:PlanningRebuildJob = $null
    }
}

function Receive-PlanningRebuildJobOutput {
    param(
        [System.Management.Automation.Job]$Job
    )

    $receiveErrors = @()
    $output = @()
    try {
        $raw = Receive-Job -Job $Job -ErrorAction SilentlyContinue -ErrorVariable receiveErrors
        if ($null -ne $raw) {
            foreach ($item in @($raw)) {
                if ($null -eq $item) { continue }
                $itemStr = [string]$item
                if ($itemStr -match '(?i)GPL Ghostscript|Copyright|Processing pages|Loading|(?:^|\s)done(?:\s|$)|Page \d+|calc_pdf_Export|convert .+ as a Calc document') { continue }
                $output += $item
            }
        }
    }
    catch {
        $catchMsg = [string]$_.Exception.Message
        if ($catchMsg -notmatch '(?i)Ghostscript|processing data from the background') {
            $receiveErrors += $_
        }
    }

    $jobErrors = @()
    foreach ($childJob in @($Job.ChildJobs)) {
        if ($null -eq $childJob -or $null -eq $childJob.Error) { continue }
        foreach ($rec in @($childJob.Error)) {
            if ($null -ne $rec) { $jobErrors += $rec }
        }
    }

    $result = $null
    foreach ($item in $output) {
        if ($null -eq $item) { continue }
        if ($item.PSObject.Properties['OutputPdf']) {
            $result = $item
        }
    }
    if ($null -eq $result -and $output.Count -eq 1) {
        $result = $output[0]
    }

    return [pscustomobject]@{
        Output        = $output
        Result        = $result
        ReceiveErrors = @($receiveErrors)
        JobErrors     = @($jobErrors)
    }
}

function Get-PlanningRebuildJobErrorMessage {
    param(
        [System.Management.Automation.Job]$Job,
        [string]$FallbackMessage = 'Echec du traitement planning',
        [AllowNull()][string]$ReceiveCatchMessage = $null,
        $ReceiveErrors = @(),
        $JobErrors = @(),
        $JobOutput = @()
    )

    if (-not [string]::IsNullOrWhiteSpace($ReceiveCatchMessage)) {
        if ($ReceiveCatchMessage -notmatch '(?i)Ghostscript|processing data from the background|GPL Ghostscript|Copyright|Processing pages') {
            return $ReceiveCatchMessage
        }
    }
    if ($null -ne $Job.JobStateInfo.Reason -and $null -ne $Job.JobStateInfo.Reason.Message) {
        $reasonMsg = [string]$Job.JobStateInfo.Reason.Message
        if (-not [string]::IsNullOrWhiteSpace($reasonMsg) -and
            $reasonMsg -notmatch '(?i)Ghostscript|processing data from the background|GPL Ghostscript|Copyright|Processing pages|(?:^|\s)done(?:\s|$)') {
            return $reasonMsg
        }
    }
    foreach ($rec in @($JobErrors)) {
        if ($null -eq $rec) { continue }
        $m = if ($null -ne $rec.Exception) { [string]$rec.Exception.Message } else { [string]$rec }
        if ([string]::IsNullOrWhiteSpace($m)) { continue }
        if ($m -match '(?i)Ghostscript|processing data from the background|GPL Ghostscript|Copyright|Processing pages|(?:^|\s)done(?:\s|$)') { continue }
        return $m
    }
    foreach ($rec in @($ReceiveErrors)) {
        if ($null -eq $rec) { continue }
        $m = if ($rec -is [System.Management.Automation.ErrorRecord] -and $null -ne $rec.Exception) {
            [string]$rec.Exception.Message
        }
        else { [string]$rec }
        if ([string]::IsNullOrWhiteSpace($m)) { continue }
        if ($m -match '(?i)Ghostscript|processing data from the background|GPL Ghostscript|Copyright|Processing pages|(?:^|\s)done(?:\s|$)') { continue }
        return $m
    }
    foreach ($line in @($JobOutput)) {
        if ($null -eq $line) { continue }
        $s = [string]$line
        if ($s -match '(?i)\[(ERROR|JOB-ERROR|PLANNING-EXCEPTION)\]') {
            return $s
        }
    }
    return $FallbackMessage
}

function Complete-PlanningRebuildJobUi {
    param(
        [System.Management.Automation.Job]$Job,
        [System.Windows.Forms.Control]$RootPanel
    )

    Stop-PlanningRebuildStep2ActivityAnimation

    $result = $null
    $errMsg = $null
    $jobState = $Job.State
    $receiveCatchMessage = $null
    $jobPayload = $null

    try {
        $jobPayload = Receive-PlanningRebuildJobOutput -Job $Job
        $result = $jobPayload.Result

        if ($jobState -eq 'Failed') {
            $errMsg = Get-PlanningRebuildJobErrorMessage -Job $Job `
                -ReceiveErrors $jobPayload.ReceiveErrors -JobErrors $jobPayload.JobErrors -JobOutput $jobPayload.Output
        }
        elseif ($jobState -eq 'Completed' -and $null -ne $result) {
            $outPdfProp = $result.PSObject.Properties['OutputPdf']
            if ($null -ne $outPdfProp -and [string]::IsNullOrWhiteSpace([string]$outPdfProp.Value)) {
                $result = $null
            }
        }
    }
    catch {
        $jobState = 'Failed'
        $receiveCatchMessage = [string]$_.Exception.Message
        $errMsg = Get-PlanningRebuildJobErrorMessage -Job $Job -ReceiveCatchMessage $receiveCatchMessage `
            -ReceiveErrors $(if ($null -ne $jobPayload) { $jobPayload.ReceiveErrors } else { @() }) `
            -JobErrors $(if ($null -ne $jobPayload) { $jobPayload.JobErrors } else { @() }) `
            -JobOutput $(if ($null -ne $jobPayload) { $jobPayload.Output } else { @() })
    }
    finally {
        Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue
        if ($script:PlanningRebuildJob -eq $Job) { $script:PlanningRebuildJob = $null }
        if ($null -ne $script:PlanningRebuildJobTimer) {
            try { $script:PlanningRebuildJobTimer.Stop() } catch { }
        }
        if ($null -ne $script:PlanningProgressTimer) {
            try { $script:PlanningProgressTimer.Stop() } catch { }
        }
    }

    Safe-UpdateUIControl -Control $RootPanel -UpdateAction {
        $ui = $script:PlanningRebuilderPanelContext.Ui
        if ($ui.BtnPdf -is [System.Windows.Forms.Control]) { $ui.BtnPdf.Enabled = $true }
        if ($ui.BtnLancer -is [System.Windows.Forms.Control]) { $ui.BtnLancer.Enabled = $true }
        if ($ui.BtnStop -is [System.Windows.Forms.Control]) { $ui.BtnStop.Enabled = $false }
    }

    if ($jobState -eq 'Failed') {
        if ([string]::IsNullOrWhiteSpace($errMsg)) {
            $errMsg = Get-PlanningRebuildJobErrorMessage -Job $Job -ReceiveCatchMessage $receiveCatchMessage `
                -ReceiveErrors $(if ($null -ne $jobPayload) { $jobPayload.ReceiveErrors } else { @() }) `
                -JobErrors $(if ($null -ne $jobPayload) { $jobPayload.JobErrors } else { @() }) `
                -JobOutput $(if ($null -ne $jobPayload) { $jobPayload.Output } else { @() })
        }
        Safe-UpdateUIControl -Control $RootPanel -UpdateAction {
            $ui = $script:PlanningRebuilderPanelContext.Ui
            [void]$ui.TxtDebug.AppendText(("ERREUR DETAILLEE : {0}" -f $errMsg) + [Environment]::NewLine)
            if ($null -ne $jobPayload -and @($jobPayload.JobErrors).Count -gt 0) {
                foreach ($je in @($jobPayload.JobErrors)) {
                    if ($null -eq $je) { continue }
                    $detail = if ($null -ne $je.Exception) { [string]$je.Exception.Message } else { [string]$je }
                    if (-not [string]::IsNullOrWhiteSpace($detail)) {
                        [void]$ui.TxtDebug.AppendText(("  -> {0}" -f $detail) + [Environment]::NewLine)
                    }
                }
            }
            $ui.LblStepProgress.Text = 'Echec du traitement'
            $ui.ProgressBar.Value = 0
            $ui.LblPercent.Text = '0%'
        }
        [System.Windows.Forms.MessageBox]::Show(
            $errMsg,
            'Echec traitement planning',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    elseif ($jobState -eq 'Stopped') {
        Safe-UpdateUIControl -Control $RootPanel -UpdateAction {
            $ui = $script:PlanningRebuilderPanelContext.Ui
            if ($script:PlanningStopRequested) {
                [void]$ui.TxtDebug.AppendText('Traitement annule par l''utilisateur.' + [Environment]::NewLine)
                $ui.LblStepProgress.Text = 'Traitement annule'
            }
            else {
                [void]$ui.TxtDebug.AppendText('Traitement interrompu.' + [Environment]::NewLine)
                $ui.LblStepProgress.Text = 'Traitement interrompu'
            }
            $ui.ProgressBar.Value = 0
            $ui.LblPercent.Text = '0%'
        }
    }
    elseif ($null -eq $result) {
        $nullDetail = Get-PlanningRebuildJobErrorMessage -Job $Job -FallbackMessage 'Le traitement s''est termine sans generer de PDF.' `
            -ReceiveErrors $(if ($null -ne $jobPayload) { $jobPayload.ReceiveErrors } else { @() }) `
            -JobErrors $(if ($null -ne $jobPayload) { $jobPayload.JobErrors } else { @() }) `
            -JobOutput $(if ($null -ne $jobPayload) { $jobPayload.Output } else { @() })
        Safe-UpdateUIControl -Control $RootPanel -UpdateAction {
            $ui = $script:PlanningRebuilderPanelContext.Ui
            [void]$ui.TxtDebug.AppendText('Le job s''est termine sans PDF genere.' + [Environment]::NewLine)
            if (-not [string]::IsNullOrWhiteSpace($nullDetail)) {
                [void]$ui.TxtDebug.AppendText(("Detail : {0}" -f $nullDetail) + [Environment]::NewLine)
            }
            $ui.LblStepProgress.Text = 'Traitement interrompu'
            $ui.ProgressBar.Value = 0
            $ui.LblPercent.Text = '0%'
        }
        [System.Windows.Forms.MessageBox]::Show(
            ("Le traitement s'est termine sans generer de PDF.{0}{0}Detail : {1}" -f [Environment]::NewLine, $nullDetail),
            'Aucun PDF genere',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
    }
    else {
        $outPdf = [string]$result.OutputPdf
        if (-not [string]::IsNullOrWhiteSpace($outPdf)) {
            $outName = Split-Path -Leaf $outPdf
            Safe-UpdateUIControl -Control $RootPanel -UpdateAction {
                $ui = $script:PlanningRebuilderPanelContext.Ui
                $ui.ProgressBar.Value = 100
                $ui.LblPercent.Text = '100%'
                $ui.LblStepProgress.Text = 'Traitement termine'
                if ([string]::IsNullOrWhiteSpace($ui.LblOutputPdf.Text)) {
                    $ui.LblOutputPdf.Text = ('PDF genere : {0}' -f $outName)
                }
            }
            Reset-PlanningAfterTreatment
        }
        else {
            Safe-UpdateUIControl -Control $RootPanel -UpdateAction {
                $ui = $script:PlanningRebuilderPanelContext.Ui
                [void]$ui.TxtDebug.AppendText('Resultat job sans chemin OutputPdf.' + [Environment]::NewLine)
                $ui.LblStepProgress.Text = 'Traitement interrompu'
                $ui.ProgressBar.Value = 0
                $ui.LblPercent.Text = '0%'
            }
        }
    }

    Set-PlanningRunningState -IsRunning $false
}

function Test-PlanningRebuildInputPaths {
    param(
        [switch]$ShowMessage
    )

    if ([string]::IsNullOrWhiteSpace($script:PlanningPdfPath) -or -not (Test-Path -LiteralPath $script:PlanningPdfPath)) {
        if ($ShowMessage) {
            [System.Windows.Forms.MessageBox]::Show(
                'Veuillez d''abord importer un fichier PDF.',
                'PDF manquant',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        }
        return $null
    }

    $excelPath = Resolve-ActiveExcelPath

    if ([string]::IsNullOrWhiteSpace($excelPath) -or -not (Test-Path -LiteralPath $excelPath)) {
        if ($ShowMessage) {
            $message = if (Test-PlanningSharePointIsConnected) {
                'Veuillez importer un fichier Excel ou synchroniser SharePoint.'
            }
            else {
                'Veuillez importer un fichier Excel (planning) via « Importer Excel ».'
            }
            [System.Windows.Forms.MessageBox]::Show(
                $message,
                'Excel manquant',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        }
        return $null
    }

    $script:ActiveExcelPath = $excelPath
    return [pscustomobject]@{
        PdfPath   = $script:PlanningPdfPath
        ExcelPath = $excelPath
    }
}

function Start-PlanningRebuildJob {
    param(
        [string]$PdfPath,
        [string]$ExcelPath,
        [System.Windows.Forms.Control]$RootPanel
    )

    Stop-PlanningRebuildJobIfRunning
    $script:PlanningRebuildJob = $null

    foreach ($name in @(
            'CN_DEBUG_PIPELINE', 'CN_DEBUG_PLANNING', 'CN_DEBUG_PLANNING_FLOW',
            'PDF_DEBUG', 'CN_CHIRURGICAL_TRACE', 'CN_DEEP_OBJECT_TRACE'
        )) {
        Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
    }

    Get-Process -Name 'soffice*', 'gswin*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $env:TEMP -Filter 'cn_*' -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    if (Get-Command Write-PlanningRebuildUiLog -ErrorAction SilentlyContinue) {
        Write-PlanningRebuildUiLog '[DIRECT] Appel synchrone (sans Start-Job)'
    }

    Safe-UpdateUIControl -Control $RootPanel -UpdateAction {
        $ui = $script:PlanningRebuilderPanelContext.Ui
        if ($ui.BtnPdf) { $ui.BtnPdf.Enabled = $false }
        if ($ui.BtnLancer) { $ui.BtnLancer.Enabled = $false }
        if ($ui.BtnStop) { $ui.BtnStop.Enabled = $true }
        if ($ui.TxtDebug) { $ui.TxtDebug.Clear() }
        if ($ui.ProgressBar) { $ui.ProgressBar.Value = 0 }
        $ui.LblStepProgress.Text = 'Traitement en cours...'
        $script:PlanningRebuildStepUiStartTime = $null
        $script:PlanningRebuildStepUiLastIndex = 0
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $result = Start-PlanningRebuild -PdfPath $PdfPath -ExcelPath $ExcelPath -ProgressCallback $script:InvokePlanningRebuildProgressUi

        $sw.Stop()
        $elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 1)

        if ($result -and $result.OutputPdf) {
            $outPdf = $result.OutputPdf
            $size = (Get-Item -LiteralPath $outPdf).Length
            $sizeMo = [math]::Round($size / 1MB, 2)

            Safe-UpdateUIControl -Control $RootPanel -UpdateAction {
                $ui = $script:PlanningRebuilderPanelContext.Ui
                $ui.ProgressBar.Value = 100
                $ui.LblPercent.Text = '100%'
                $ui.LblStepProgress.Text = 'Traitement termine'
                $ui.LblOutputPdf.Text = "PDF genere : $(Split-Path -Leaf $outPdf) ($sizeMo Mo)"
                [void]$ui.TxtDebug.AppendText("`nSUCCES en $elapsed secondes !`r`n")
            }

            Reset-PlanningAfterTreatment

            [System.Windows.Forms.MessageBox]::Show(
                "PDF genere avec succes en $elapsed secondes !`n`n$outPdf",
                'Succes',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
        else {
            throw 'Aucun PDF genere'
        }
    }
    catch {
        $sw.Stop()
        Safe-UpdateUIControl -Control $RootPanel -UpdateAction {
            $ui = $script:PlanningRebuilderPanelContext.Ui
            $ui.LblStepProgress.Text = 'Echec du traitement'
            [void]$ui.TxtDebug.AppendText("`nECHEC : $($_.Exception.Message)`r`n")
        }
        [System.Windows.Forms.MessageBox]::Show(
            "Erreur : $($_.Exception.Message)",
            'Echec',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    finally {
        Safe-UpdateUIControl -Control $RootPanel -UpdateAction {
            $ui = $script:PlanningRebuilderPanelContext.Ui
            if ($ui.BtnPdf) { $ui.BtnPdf.Enabled = $true }
            if ($ui.BtnLancer) { $ui.BtnLancer.Enabled = $true }
            if ($ui.BtnStop) { $ui.BtnStop.Enabled = $false }
        }
        Set-PlanningRunningState -IsRunning $false
    }
}

function Safe-UpdateUIControl {
    param(
        [System.Windows.Forms.Control]$Control,
        [scriptblock]$UpdateAction
    )

    if ($null -eq $Control -or $Control.IsDisposed) { return }
    $form = $Control.FindForm()
    if ($null -eq $form -or $form.IsDisposed) { return }

    try {
        if ($Control.InvokeRequired) {
            $Control.Invoke([System.Action]{ & $UpdateAction })
        }
        else {
            & $UpdateAction
        }
    }
    catch {
        Write-Debug ("Safe-UpdateUIControl: {0}" -f $_.Exception.Message)
    }
}

function Set-PlanningRunningState {
    param([bool]$IsRunning)
    $script:PlanningRebuildUiBusy = $IsRunning
    $script:PlanningRunning = $IsRunning
}

function Set-PlanningControlText {
    param(
        $Control,
        [string]$Text
    )
    if ($null -eq $Control) { return }
    if ($Control -isnot [System.Windows.Forms.Control]) { return }
    if ($Control.IsDisposed) { return }
    $Control.Text = [string]$Text
}

$script:InvokePlanningRebuildProgressUi = {
    param(
        [Parameter(Position = 0)]
        $Event = $null,
        [int]$StepIndex = 0,
        [int]$StepCount = 0,
        [string]$Label = '',
        [string]$Status = '',
        [string]$Detail = $null,
        [int]$Percent = -1,
        [string]$SubStep = $null,
        [int]$SubStepIndex = 0,
        [int]$SubStepCount = 0,
        [string]$TreePrefix = $null,
        [string]$OutputPath = $null
    )
    if ($Event -is [hashtable]) {
        $h = $Event
        if ($h.ContainsKey('StepIndex')) { $StepIndex = [int]$h.StepIndex }
        if ($h.ContainsKey('StepCount')) { $StepCount = [int]$h.StepCount }
        if ($h.ContainsKey('Label')) { $Label = [string]$h.Label }
        if ($h.ContainsKey('Status')) { $Status = [string]$h.Status }
        if ($h.ContainsKey('Detail')) { $Detail = [string]$h.Detail }
        if ($h.ContainsKey('Percent')) { $Percent = [int]$h.Percent }
        if ($h.ContainsKey('SubStep')) { $SubStep = [string]$h.SubStep }
        if ($h.ContainsKey('SubStepIndex')) { $SubStepIndex = [int]$h.SubStepIndex }
        if ($h.ContainsKey('SubStepCount')) { $SubStepCount = [int]$h.SubStepCount }
        if ($h.ContainsKey('TreePrefix')) { $TreePrefix = [string]$h.TreePrefix }
        if ($h.ContainsKey('OutputPath')) { $OutputPath = [string]$h.OutputPath }
    }
    if (-not [string]::IsNullOrWhiteSpace($Status) -and $Status -eq 'Log') {
        $ctxLog = $script:PlanningRebuilderPanelContext
        if ($null -eq $ctxLog -or $null -eq $ctxLog.Panel -or $null -eq $ctxLog.Ui) { return }
        if ([string]::IsNullOrWhiteSpace($Detail)) { return }
        Safe-UpdateUIControl -Control $ctxLog.Panel -UpdateAction {
            $uiLog = $script:PlanningRebuilderPanelContext.Ui
            $script:PlanningStepHadSubLines = $true
            Add-PlanningRebuildDebugLogLine -DebugBox $uiLog.TxtDebug -Line ('  {0}' -f $Detail)
        }
        return
    }
    $ctx = $script:PlanningRebuilderPanelContext
    if ($null -eq $ctx -or $null -eq $ctx.Panel -or $null -eq $ctx.Ui) { return }
    Safe-UpdateUIControl -Control $ctx.Panel -UpdateAction {
        $ui = $script:PlanningRebuilderPanelContext.Ui
        Update-PlanningRebuildDebugProgress -DebugBox $ui.TxtDebug -ProgressBar $ui.ProgressBar `
            -StepIndex $StepIndex -StepCount $StepCount -Label $Label -Status $Status -Detail $Detail `
            -Percent $Percent -SubStep $SubStep -SubStepIndex $SubStepIndex -SubStepCount $SubStepCount `
            -TreePrefix $TreePrefix -OutputPath $OutputPath `
            -StepLabel $ui.LblStepProgress -OutputLabel $ui.LblOutputPdf -PercentLabel $ui.LblPercent
    }
}

# Scriptblock en $script: (visible depuis BackgroundWorker ; les fonctions dot-sourcees dans Start-GUI ne le sont pas).
$script:InvokePlanningSharePointUiUpdate = {
    param($State)
    $script:PlanningSharePointState = $State
    if ($null -ne $State -and -not [string]::IsNullOrWhiteSpace([string]$State.Status)) {
        $script:PlanningSharePointStatus = [string]$State.Status
    }
    elseif ($State -is [string] -and -not [string]::IsNullOrWhiteSpace($State)) {
        $script:PlanningSharePointStatus = $State
    }
    Set-CnsSharePointConnectionState -State $State
    if ($null -ne $State -and -not [string]::IsNullOrWhiteSpace([string]$State.FilePath)) {
        if ($State.Status -eq 'Connected') {
            $script:SharePointExcelPath = [string]$State.FilePath
            if ($script:CurrentUIMode -eq 'SharePoint') {
                $script:ActiveExcelPath = $script:SharePointExcelPath
            }
        }
    }
    $ctx = $script:PlanningRebuilderPanelContext
    if ($null -eq $ctx -or $null -eq $ctx.Panel) { return }
    $uiState = $State
    $uiCmd = $script:UpdateSharePointUiCmd
    $uiAction = {
        $c = $script:PlanningRebuilderPanelContext
        $uiStateLocal = $uiState
        $lastSync = $null
        if ($null -ne $uiStateLocal -and $null -ne $uiStateLocal.LastSync) {
            try { $lastSync = [datetime]$uiStateLocal.LastSync } catch { $lastSync = $null }
        }
        $statusCode = if ($null -ne $uiStateLocal) { [string]$uiStateLocal.Status } else { 'Error' }
        if ([string]::IsNullOrWhiteSpace($statusCode)) { $statusCode = 'Error' }
        $importExcelBtn = $null
        if ($null -ne $c.Ui) { $importExcelBtn = $c.Ui.BtnImportExcel }
        $effectiveExcel = $script:SharePointExcelPath
        $uiParams = @{
            State   = $statusCode
            Labels  = @{
                FileNameLabel      = $c.SpUi.FileName
                StatusLabel        = $c.SpUi.Status
                DateLabel          = $c.SpUi.Date
                Icon               = $c.SpUi.Icon
                StatusDot          = $c.SpUi.StatusDot
                LocalMode          = $c.SpUi.LocalMode
                ImportExcel        = $importExcelBtn
                Connect            = $c.SpUi.Connect
                EffectiveExcelPath = $effectiveExcel
                PlanningUIMode     = $script:CurrentUIMode
            }
            Buttons  = $c.SpUi.Buttons
            OnAction = $c.SharePointActionHandler
        }
        if ($null -ne $lastSync -and $lastSync -ne [datetime]::MinValue) {
            $uiParams['LastSync'] = $lastSync
        }
        if ($null -ne $uiStateLocal -and -not [string]::IsNullOrWhiteSpace([string]$uiStateLocal.Message)) {
            $uiParams['Message'] = [string]$uiStateLocal.Message
        }
        if ($null -ne $uiStateLocal -and -not [string]::IsNullOrWhiteSpace([string]$uiStateLocal.FilePath)) {
            $uiParams['FilePath'] = [string]$uiStateLocal.FilePath
        }
        & $uiCmd @uiParams
        Update-PlanningUIMode -SharePointStatus $statusCode
        Update-ExcelButtonVisibility -SharePointStatus $statusCode
        if ($script:CurrentUIMode -eq 'SharePoint') {
            Update-PlanningExcelPathLabel
        }
        elseif ($script:CurrentUIMode -eq 'Local') {
            Update-PlanningExcelPathLabel
        }
    }
    $rootPanel = $ctx.Panel
    Safe-UpdateUIControl -Control $rootPanel -UpdateAction $uiAction
}

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
$script:PlanningRebuildStepUiStartTime = $null
$script:PlanningRebuildStepUiLastIndex = 0
$script:PlanningStep2ActivityTimer = $null
$script:PlanningStep2ActivityLabel = $null
$script:PlanningStep2EllipsisPhase = 0
$script:PlanningStep2ActivityActive = $false

function Reset-PlanningPdfImportSelection {
    $script:PlanningPdfPath = $null
    $ctx = $script:PlanningRebuilderPanelContext
    if ($null -eq $ctx -or $null -eq $ctx.Panel) { return }
    Safe-UpdateUIControl -Control $ctx.Panel -UpdateAction {
        $ui = $script:PlanningRebuilderPanelContext.Ui
        if ($null -ne $ui -and $null -ne $ui.LblPdf -and $ui.LblPdf -is [System.Windows.Forms.Control]) {
            $ui.LblPdf.Text = '📄 Aucun PDF sélectionné'
            $ui.LblPdf.ForeColor = $script:CouleurTexteSecondairePanel
        }
    }
}

function Reset-PlanningAfterTreatment {
    Reset-PlanningPdfImportSelection
    if ($script:CurrentUIMode -eq 'Local') {
        $script:ManualExcelPath = $null
        $script:ActiveExcelPath = $null
        Update-PlanningExcelPathLabel
    }
    elseif ($script:CurrentUIMode -eq 'SharePoint') {
        Reset-PlanningPdfImportSelection
    }
}

function Sync-PlanningModeFlagsFromUIMode {
    $script:ManualModeEnabled = ($script:CurrentUIMode -eq 'Local')
}

function Reset-PlanningImportSelections {
    $script:PlanningPdfPath = $null
    $script:ManualExcelPath = $null
    $script:SharePointExcelPath = $null
    $script:ActiveExcelPath = $null
    $ctx = $script:PlanningRebuilderPanelContext
    if ($null -eq $ctx -or $null -eq $ctx.Panel) { return }
    Safe-UpdateUIControl -Control $ctx.Panel -UpdateAction {
        $ui = $script:PlanningRebuilderPanelContext.Ui
        if ($null -ne $ui -and $null -ne $ui.LblPdf -and $ui.LblPdf -is [System.Windows.Forms.Control]) {
            $ui.LblPdf.Text = '📄 Aucun PDF sélectionné'
            $ui.LblPdf.ForeColor = $script:CouleurTexteSecondairePanel
        }
        if ($null -ne $ui -and $null -ne $ui.LblOutputPdf -and $ui.LblOutputPdf -is [System.Windows.Forms.Control]) {
            $ui.LblOutputPdf.Text = ''
        }
    }
    Update-PlanningExcelPathLabel
}

function Update-ExcelButtonVisibility {
    param(
        [string]$SharePointStatus = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($SharePointStatus)) {
        $script:PlanningSharePointStatus = $SharePointStatus
    }

    $ctx = $script:PlanningRebuilderPanelContext
    if ($null -eq $ctx -or $null -eq $ctx.Ui) { return }
    $showExcelButton = Test-PlanningAllowsManualExcelImport
    if ($null -ne $ctx.Ui.BtnImportExcel -and $ctx.Ui.BtnImportExcel -is [System.Windows.Forms.Control]) {
        $ctx.Ui.BtnImportExcel.Visible = $showExcelButton
    }
}

function Update-PlanningUIMode {
    param(
        [string]$SharePointStatus = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($SharePointStatus)) {
        $script:PlanningSharePointStatus = $SharePointStatus
    }

    Update-ExcelButtonVisibility -SharePointStatus $script:PlanningSharePointStatus

    $ctx = $script:PlanningRebuilderPanelContext
    if ($null -eq $ctx -or $null -eq $ctx.Ui) { return }
    $ui = $ctx.Ui
    if ($null -ne $ui.BtnLancer -and $ui.BtnLancer -is [System.Windows.Forms.Control]) {
        $ui.BtnLancer.Visible = $true
    }
    if ($null -ne $ui.BtnResetToSharePoint -and $ui.BtnResetToSharePoint -is [System.Windows.Forms.Control]) {
        $ui.BtnResetToSharePoint.Visible = $false
    }
    if ($null -ne $ui.LblStepProgress -and $ui.LblStepProgress -is [System.Windows.Forms.Control]) {
        if (Test-PlanningSharePointIsConnected) {
            Set-PlanningControlText -Control $ui.LblStepProgress -Text 'Importez un PDF, puis cliquez sur Lancer (Excel SharePoint synchronise).'
        }
        else {
            Set-PlanningControlText -Control $ui.LblStepProgress -Text 'Importez PDF et Excel, puis cliquez sur Lancer.'
        }
    }
}

function Switch-PlanningToLocalUIMode {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    $script:CurrentUIMode = 'Local'
    Sync-PlanningModeFlagsFromUIMode
    Reset-PlanningImportSelections
    Update-PlanningUIMode
    Update-PlanningSharePointUiState -State ([pscustomobject]@{
            Status  = 'Offline'
            Message = 'Déconnecté – mode local'
        })
}

function Switch-PlanningToSharePointUIMode {
    $script:CurrentUIMode = 'SharePoint'
    Sync-PlanningModeFlagsFromUIMode
    Reset-PlanningImportSelections
    Update-PlanningUIMode
    Update-PlanningExcelPathLabel
}

function Resolve-ActiveExcelPath {
    if (-not [string]::IsNullOrWhiteSpace($script:ManualExcelPath)) {
        return $script:ManualExcelPath
    }
    if ($script:CurrentUIMode -eq 'SharePoint' -and (Test-PlanningSharePointIsConnected)) {
        if (-not [string]::IsNullOrWhiteSpace($script:SharePointExcelPath)) {
            return $script:SharePointExcelPath
        }
    }
    return $null
}

function Sync-PlanningActiveExcelPath {
    $script:ActiveExcelPath = Resolve-ActiveExcelPath
    return $script:ActiveExcelPath
}

function Update-PlanningExcelPathLabel {
    $ctx = $script:PlanningRebuilderPanelContext
    if ($null -eq $ctx -or $null -eq $ctx.Ui) { return }
    $lbl = $ctx.Ui.LblExcel
    $resetBtn = $ctx.Ui.BtnResetToSharePoint
    if ($null -eq $lbl -or $lbl -isnot [System.Windows.Forms.Control]) { return }

    if (-not [string]::IsNullOrWhiteSpace($script:ManualExcelPath)) {
        $manualSuffix = if ($script:CurrentUIMode -eq 'Local') { 'mode local' } else { 'import manuel' }
        Set-PlanningControlText -Control $lbl -Text ('📁 {0} ({1})' -f (Split-Path -Leaf $script:ManualExcelPath), $manualSuffix)
    }
    elseif ($script:CurrentUIMode -eq 'SharePoint' -and -not [string]::IsNullOrWhiteSpace($script:SharePointExcelPath)) {
        Set-PlanningControlText -Control $lbl -Text ('📁 {0} (SharePoint)' -f (Split-Path -Leaf $script:SharePointExcelPath))
    }
    else {
        Set-PlanningControlText -Control $lbl -Text '📁 Aucun Excel sélectionné'
    }
    if ($null -ne $resetBtn -and $resetBtn -is [System.Windows.Forms.Control]) {
        $resetBtn.Visible = $false
    }
}

function Update-PlanningSharePointUiState {
    param($State)
    & $script:InvokePlanningSharePointUiUpdate -State $State
}

function Set-PlanningSharePointConnectButtonEnabled {
    param([bool]$Enabled)
    $ctx = $script:PlanningRebuilderPanelContext
    if ($null -eq $ctx -or $null -eq $ctx.SpUi -or $null -eq $ctx.SpUi.Connect) { return }
    $rootPanel = $ctx.Panel
    if ($null -eq $rootPanel -or $rootPanel.IsDisposed) { return }
    Safe-UpdateUIControl -Control $rootPanel -UpdateAction {
        $connectBtn = $script:PlanningRebuilderPanelContext.SpUi.Connect
        if ($null -ne $connectBtn -and $connectBtn -is [System.Windows.Forms.Control] -and -not $connectBtn.IsDisposed) {
            $connectBtn.Enabled = $Enabled
        }
    }
}

function Stop-PlanningSharePointWorkerForInteractiveLogin {
    if ($null -eq $script:PlanningSharePointWorker) { return }
    if (-not $script:PlanningSharePointWorker.IsBusy) { return }
    try {
        Request-CnsSharePointConnectCancel
        $script:PlanningSharePointWorker.CancelAsync()
    }
    catch { }
    $deadline = (Get-Date).AddSeconds(3)
    while ($script:PlanningSharePointWorker.IsBusy -and (Get-Date) -lt $deadline) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
    }
}

function Start-PlanningSharePointSync {
    param(
        [switch]$ForceRefresh,
        [switch]$InteractiveLogin,
        [switch]$ShowConnecting
    )
    if ($null -ne $script:PlanningSharePointWorker -and $script:PlanningSharePointWorker.IsBusy) {
        if (-not $InteractiveLogin) { return }
        Stop-PlanningSharePointWorkerForInteractiveLogin
    }
    Reset-CnsSharePointConnectCancel
    if ($ShowConnecting) {
        $connectMsg = if ($InteractiveLogin) {
            'Authentification Microsoft 365 - suivez la fenetre ou le navigateur'
        } else {
            'Connexion SharePoint en cours...'
        }
        Update-PlanningSharePointUiState -State ([pscustomobject]@{
                Status  = 'Connecting'
                Message = $connectMsg
            })
    }

    if ($InteractiveLogin) {
        if (Test-CnsSharePointAuthInProgress) {
            Write-Host 'Authentification Microsoft 365 deja en cours...' -ForegroundColor Yellow
            return
        }
        Set-PlanningSharePointConnectButtonEnabled -Enabled $false
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        if (-not (Test-MicrosoftGraphModule -PromptInstall)) {
            Set-PlanningSharePointConnectButtonEnabled -Enabled $true
            Update-PlanningSharePointUiState -State ([pscustomobject]@{
                    Status      = 'Error'
                    Message     = 'Module Microsoft.Graph requis - installez-le manuellement'
                    ErrorDetail = 'Microsoft.Graph absent'
                })
            return
        }
        try {
            Connect-SharePointGraph -Interactive | Out-Null
        }
        catch {
            $errMsg = [string]$_.Exception.Message
            $resolved = Resolve-CnsSharePointConnectError -ErrorMessage $errMsg
            Update-PlanningSharePointUiState -State ([pscustomobject]@{
                    Status      = $resolved.Status
                    Message     = $resolved.Message
                    ErrorDetail = $errMsg
                })
            Set-PlanningSharePointConnectButtonEnabled -Enabled $true
            return
        }
        finally {
            if (-not (Test-CnsSharePointAuthInProgress)) {
                Set-PlanningSharePointConnectButtonEnabled -Enabled $true
            }
        }
    }

    $syncCmd = $script:SyncSharePointPlanningFileCmd
    $connectCmd = $script:ConnectSharePointPlanningCmd
    $wantRefresh = [bool]$ForceRefresh
    $script:PlanningSharePointWorker = [System.ComponentModel.BackgroundWorker]::new()
    $script:PlanningSharePointWorker.WorkerSupportsCancellation = $true
    $workerRunspace = $script:PlanningHostRunspace
    $script:PlanningSharePointWorker.Add_DoWork({
        param($sender, $e)
        if ($null -ne $workerRunspace) { [runspace]::DefaultRunspace = $workerRunspace }
        if ($e.Cancel) { return }
        if ($wantRefresh) {
            $e.Result = & $syncCmd
        }
        else {
            $e.Result = & $connectCmd
        }
    })
    $script:PlanningSharePointWorker.Add_RunWorkerCompleted({
        param($sender, $e)
        $rootPanel = $script:PlanningRebuilderPanelContext.Panel
        if ($null -eq $rootPanel -or $rootPanel.IsDisposed) { return }
        Safe-UpdateUIControl -Control $rootPanel -UpdateAction {
            if ($e.Cancelled) {
                & $script:InvokePlanningSharePointUiUpdate -State ([pscustomobject]@{
                        Status  = 'Error'
                        Message = 'Connexion annulee'
                    })
                return
            }
            if ($null -ne $e.Error) {
                $errorMsg = [string]$e.Error.Message
                $stateMessage = 'Connexion échouée – cliquez sur "Connexion" pour réessayer'
                & $script:InvokePlanningSharePointUiUpdate -State ([pscustomobject]@{
                        Status      = 'Offline'
                        Message     = $stateMessage
                        ErrorDetail = $errorMsg
                    })
                return
            }
            & $script:InvokePlanningSharePointUiUpdate -State $e.Result
            if ($script:PlanningPendingAutoRun -and $script:CurrentUIMode -eq 'SharePoint' `
                -and $null -ne $e.Result -and $e.Result.Status -eq 'Connected' `
                -and -not $script:PlanningRebuildUiBusy -and -not [string]::IsNullOrWhiteSpace($script:PlanningPdfPath)) {
                $script:PlanningPendingAutoRun = $false
                $rebuildHandler = $script:PlanningRebuilderPanelContext.RebuildRunHandler
                if ($null -ne $rebuildHandler) {
                    & $rebuildHandler
                }
            }
        }
    })
    $script:PlanningSharePointWorker.RunWorkerAsync()
}

function Start-SharePointConnectionBackground {
    param(
        [switch]$InteractiveLogin,
        [switch]$ForceRefresh
    )
    if ($InteractiveLogin -or $ForceRefresh) {
        Start-PlanningSharePointSync -ForceRefresh:$ForceRefresh -InteractiveLogin:$InteractiveLogin -ShowConnecting
        return
    }
    if ($script:PlanningSharePointConnectionStarted) { return }
    $script:PlanningSharePointConnectionStarted = $true
    Start-PlanningSharePointSync -ShowConnecting
}

function Invoke-PlanningPanelDeferredInit {
    Start-SharePointConnectionBackground
}

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
    $script:PlanningRebuildStepUiStartTime = $null
    $script:PlanningRebuildStepUiLastIndex = 0
}

function Get-PlanningRebuildStepElapsedLabelSuffix {
    param([int]$StepIndex)
    if ($StepIndex -lt 1) { return '' }
    if ($StepIndex -ne $script:PlanningRebuildStepUiLastIndex -or $null -eq $script:PlanningRebuildStepUiStartTime) {
        $script:PlanningRebuildStepUiStartTime = Get-Date
        $script:PlanningRebuildStepUiLastIndex = $StepIndex
    }
    $elapsedSeconds = [math]::Round(((Get-Date) - $script:PlanningRebuildStepUiStartTime).TotalSeconds, 1)
    return (' ({0} s)' -f $elapsedSeconds)
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
    if ($null -eq $DebugBox -or $DebugBox.IsDisposed) { return }

    $DebugBox.Select($DebugBox.TextLength, 0)
    $DebugBox.ScrollToCaret()
    $DebugBox.SelectionStart = $DebugBox.TextLength
    $DebugBox.SelectionLength = 0
    if (-not $DebugBox.Focused) { [void]$DebugBox.Focus() }
    $DebugBox.Refresh()
    try { [System.Windows.Forms.Application]::DoEvents() } catch { }
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
        [string]$OutputPath = $null,
        [System.Windows.Forms.Label]$StepLabel = $null,
        [System.Windows.Forms.Label]$OutputLabel = $null,
        [System.Windows.Forms.Label]$PercentLabel = $null
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
        if ($null -ne $OutputLabel -and -not [string]::IsNullOrWhiteSpace($outPath)) {
            $OutputLabel.Text = ('PDF genere : {0}' -f (Split-Path -Leaf $outPath))
        }
        if ($null -ne $StepLabel) { $StepLabel.Text = 'Traitement termine' }
        if ($null -ne $PercentLabel) { $PercentLabel.Text = '100%' }
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

    if ($StepIndex -eq 5 -and $Status -eq 'Running' -and -not [string]::IsNullOrWhiteSpace($Detail)) {
        $script:PlanningCurrentStepIndex = 5
        $script:PlanningActiveStepIndex = 5
        $newLine = ('[{0}/{1}] {2}... {3}' -f $StepIndex, $StepCount, $Label, $Detail)
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
        if ($null -ne $PercentLabel -and $Percent -ge 0) { $PercentLabel.Text = ('{0}%' -f [Math]::Min(100, $Percent)) }
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
        if ($null -ne $PercentLabel -and $Percent -ge 0) { $PercentLabel.Text = ('{0}%' -f [Math]::Min(100, $Percent)) }
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
        if ($null -ne $PercentLabel) {
            $PercentLabel.Text = ('{0}%' -f $clamped)
        }
    }

    if ($null -ne $StepLabel -and $StepIndex -gt 0 -and $StepCount -gt 0 -and $Status -notin @('Complete', 'Log')) {
        $elapsedSuffix = Get-PlanningRebuildStepElapsedLabelSuffix -StepIndex $StepIndex
        $stepText = ('Etape {0}/{1} : {2}{3}' -f $StepIndex, $StepCount, $Label, $elapsedSuffix)
        if (-not [string]::IsNullOrWhiteSpace($SubStep)) {
            $stepText = ('{0} - {1}' -f $stepText, $SubStep)
        }
        if (-not [string]::IsNullOrWhiteSpace($Detail) -and $Status -in @('Running', 'SubStepProgress', 'TourneeProgress')) {
            $stepText = ('{0} — {1}' -f $stepText, $Detail)
        }
        $StepLabel.Text = $stepText
    }

    Scroll-PlanningRebuildDebugToEnd -DebugBox $DebugBox
}

function Show-PlanningRebuilderPanel {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $script:PlanningHostRunspace = [runspace]::DefaultRunspace

    $script:PlanningPdfPath = $null
    $script:SharePointExcelPath = $null
    $script:ManualExcelPath = $null
    $script:ActiveExcelPath = $null
    $script:ManualModeEnabled = $false
    $script:CurrentUIMode = 'SharePoint'
    Sync-PlanningModeFlagsFromUIMode
    $script:PlanningSharePointState = $null
    $script:PlanningSharePointWorker = $null
    $script:PlanningRebuildJob = $null
    $script:PlanningPendingAutoRun = $false
    $script:PlanningSharePointConnectionStarted = $false

    $panel = [System.Windows.Forms.Panel]::new()
    $panel.Name = 'PlanningRebuilderPanel'
    $panel.Dock = 'Fill'
    $panel.BackColor = $script:CouleurGrisFond
    $panel.Padding = [System.Windows.Forms.Padding]::new(20)
    $panel.AutoScroll = $true

    $lblTitle = [System.Windows.Forms.Label]::new()
    $lblTitle.Text = 'Edition du planning'
    $lblTitle.Font = $script:PoliceTitreGestionFenetre
    $lblTitle.ForeColor = $script:CouleurOrange
    $lblTitle.Location = [System.Drawing.Point]::new(0, 0)
    $lblTitle.Size = [System.Drawing.Size]::new(500, 50)
    $panel.Controls.Add($lblTitle)

    $lblSharePointSection = [System.Windows.Forms.Label]::new()
    $lblSharePointSection.Name = 'lblSharePointSection'
    $lblSharePointSection.Text = 'CONNEXION SHAREPOINT'
    $lblSharePointSection.Font = $script:PoliceTitre3
    $lblSharePointSection.ForeColor = $script:CouleurTexteSecondairePanel
    $lblSharePointSection.Location = [System.Drawing.Point]::new(0, 52)
    $lblSharePointSection.Size = [System.Drawing.Size]::new(500, 22)
    $panel.Controls.Add($lblSharePointSection)

    $spUi = New-SharePointStatusControls -Parent $panel -Location ([System.Drawing.Point]::new(0, 76)) -Size ([System.Drawing.Size]::new(1100, 120))
    $script:PlanningRebuilderPanelContext = @{
        Panel                   = $panel
        SpUi                    = $spUi
        SharePointActionHandler = $null
        RebuildRunHandler       = $null
    }

    $grpPdf = [System.Windows.Forms.GroupBox]::new()
    $grpPdf.Name = 'grpPdfImport'
    $grpPdf.Text = 'Import du PDF et Excel'
    $grpPdf.Location = [System.Drawing.Point]::new(0, 210)
    $grpPdf.Size = [System.Drawing.Size]::new(1100, 90)
    $grpPdf.Anchor = 'Top,Left,Right'
    $grpPdf.Font = $script:PoliceTitre3

    $btnPdf = [System.Windows.Forms.Button]::new()
    $btnPdf.Name = 'btnPdf'
    Set-BtnCertificatStyle -BtnCertificat $btnPdf
    $btnPdf.Text = '📄 Importer PDF'
    $btnPdf.Size = [System.Drawing.Size]::new(170, 40)
    $btnPdf.Location = [System.Drawing.Point]::new(12, 28)

    $btnImportExcel = [System.Windows.Forms.Button]::new()
    $btnImportExcel.Name = 'btnImportExcel'
    Set-BtnPlannerStyle -BtnPlanner $btnImportExcel
    $btnImportExcel.Text = '📁 Importer Excel'
    $btnImportExcel.Size = [System.Drawing.Size]::new(170, 40)
    $btnImportExcel.Location = [System.Drawing.Point]::new(190, 28)
    $btnImportExcel.Visible = $false

    $btnResetToSharePoint = [System.Windows.Forms.Button]::new()
    $btnResetToSharePoint.Name = 'btnResetToSharePoint'
    Set-BtnBorderStyle -Button $btnResetToSharePoint -Text '🌐 Mode SharePoint' -BorderColor $script:CouleurBleu -Width 150 -Height 40
    $btnResetToSharePoint.Location = [System.Drawing.Point]::new(368, 28)
    $btnResetToSharePoint.Visible = $false

    $lblPdf = [System.Windows.Forms.Label]::new()
    $lblPdf.Name = 'lblPdf'
    $lblPdf.Text = '📄 Aucun PDF sélectionné'
    $lblPdf.Font = $script:PoliceLabelSecondaireFenetre
    $lblPdf.ForeColor = $script:CouleurTexteSecondairePanel
    $lblPdf.Location = [System.Drawing.Point]::new(530, 28)
    $lblPdf.Size = [System.Drawing.Size]::new(550, 22)
    $lblPdf.Anchor = 'Top,Left,Right'

    $lblExcel = [System.Windows.Forms.Label]::new()
    $lblExcel.Name = 'lblExcel'
    $lblExcel.Text = '📁 Aucun Excel sélectionné'
    $lblExcel.Font = $script:PoliceLabelSecondaireFenetre
    $lblExcel.ForeColor = $script:CouleurTexteSecondairePanel
    $lblExcel.Location = [System.Drawing.Point]::new(530, 52)
    $lblExcel.Size = [System.Drawing.Size]::new(550, 22)
    $lblExcel.Anchor = 'Top,Left,Right'

    $grpPdf.Controls.AddRange(@($btnPdf, $btnImportExcel, $btnResetToSharePoint, $lblPdf, $lblExcel))
    $panel.Controls.Add($grpPdf)

    $grpTreatment = [System.Windows.Forms.GroupBox]::new()
    $grpTreatment.Name = 'grpTreatment'
    $grpTreatment.Text = 'Traitement'
    $grpTreatment.Location = [System.Drawing.Point]::new(0, 318)
    $grpTreatment.Size = [System.Drawing.Size]::new(1100, 520)
    $grpTreatment.Anchor = 'Top,Bottom,Left,Right'
    $grpTreatment.Font = $script:PoliceTitre3

    $btnStop = [System.Windows.Forms.Button]::new()
    $btnStop.Name = 'btnStopPlanning'
    Set-BtnQuitterStyle -BtnQuitter $btnStop
    $btnStop.Text = 'ARRETER'
    $btnStop.Size = [System.Drawing.Size]::new(130, 40)
    $btnStop.Location = [System.Drawing.Point]::new(152, 28)
    $btnStop.Enabled = $false

    $btnLancer = [System.Windows.Forms.Button]::new()
    $btnLancer.Name = 'btnLancerPlanning'
    Set-BtnPlannerStyle -BtnPlanner $btnLancer
    $btnLancer.Text = '▶ Lancer'
    $btnLancer.Size = [System.Drawing.Size]::new(130, 40)
    $btnLancer.Location = [System.Drawing.Point]::new(12, 28)

    $lblStepProgress = [System.Windows.Forms.Label]::new()
    $lblStepProgress.Name = 'lblStepProgress'
    $lblStepProgress.Text = 'Importez PDF et Excel, puis cliquez sur Lancer.'
    $lblStepProgress.Font = $script:PoliceLabelSecondaireFenetre
    $lblStepProgress.ForeColor = $script:CouleurTexteSecondairePanel
    $lblStepProgress.Location = [System.Drawing.Point]::new(12, 76)
    $lblStepProgress.Size = [System.Drawing.Size]::new(900, 22)

    $lblPercent = [System.Windows.Forms.Label]::new()
    $lblPercent.Name = 'lblPercent'
    $lblPercent.Text = '0%'
    $lblPercent.Font = $script:PoliceLabelSecondaireFenetre
    $lblPercent.ForeColor = $script:CouleurTexteSecondairePanel
    $lblPercent.Location = [System.Drawing.Point]::new(1020, 76)
    $lblPercent.Size = [System.Drawing.Size]::new(70, 22)
    $lblPercent.TextAlign = 'MiddleRight'
    $lblPercent.Anchor = 'Top,Right'

    $progressBar = [System.Windows.Forms.ProgressBar]::new()
    $progressBar.Name = 'progressBar'
    $progressBar.Location = [System.Drawing.Point]::new(12, 102)
    $progressBar.Size = [System.Drawing.Size]::new(1076, 20)
    $progressBar.Style = 'Continuous'
    $progressBar.Minimum = 0
    $progressBar.Maximum = 100
    $progressBar.Value = 0
    $progressBar.Anchor = 'Top,Left,Right'

    $txtDebug = [System.Windows.Forms.RichTextBox]::new()
    $txtDebug.Name = 'txtDebug'
    $txtDebug.Multiline = $true
    $txtDebug.ScrollBars = 'Vertical'
    $txtDebug.ReadOnly = $true
    $txtDebug.HideSelection = $false
    $txtDebug.WordWrap = $false
    $txtDebug.Location = [System.Drawing.Point]::new(12, 130)
    $txtDebug.Size = [System.Drawing.Size]::new(1076, 340)
    $txtDebug.Anchor = 'Top,Bottom,Left,Right'

    $lblStep2Activity = [System.Windows.Forms.Label]::new()
    $lblStep2Activity.Name = 'lblStep2Activity'
    $lblStep2Activity.Text = ''
    $lblStep2Activity.Visible = $false
    $lblStep2Activity.AutoSize = $true
    $lblStep2Activity.Location = [System.Drawing.Point]::new(12, 478)
    $lblStep2Activity.Font = $script:PoliceLabelSecondaireFenetre
    $lblStep2Activity.ForeColor = $script:CouleurTexteSecondairePanel
    $lblStep2Activity.Anchor = 'Bottom,Left'
    $script:PlanningStep2ActivityLabel = $lblStep2Activity

    $lblOutputPdf = [System.Windows.Forms.Label]::new()
    $lblOutputPdf.Name = 'lblOutputPdf'
    $lblOutputPdf.Text = ''
    $lblOutputPdf.Font = $script:PoliceLabelSecondaireFenetre
    $lblOutputPdf.ForeColor = $script:CouleurVert
    $lblOutputPdf.Location = [System.Drawing.Point]::new(12, 478)
    $lblOutputPdf.Size = [System.Drawing.Size]::new(1076, 22)
    $lblOutputPdf.Anchor = 'Bottom,Left,Right'

    $grpTreatment.Controls.AddRange(@($btnLancer, $btnStop, $lblStepProgress, $lblPercent, $progressBar, $txtDebug, $lblStep2Activity, $lblOutputPdf))
    $panel.Controls.Add($grpTreatment)

    $script:PlanningRebuilderPanelContext.Ui = @{
        ProgressBar      = $progressBar
        TxtDebug         = $txtDebug
        LblStepProgress  = $lblStepProgress
        LblOutputPdf     = $lblOutputPdf
        LblPercent       = $lblPercent
        LblPdf               = $lblPdf
        LblExcel             = $lblExcel
        BtnPdf               = $btnPdf
        BtnImportExcel       = $btnImportExcel
        BtnResetToSharePoint = $btnResetToSharePoint
        BtnLancer            = $btnLancer
        BtnStop              = $btnStop
        LblStep2Activity = $lblStep2Activity
    }

    if (-not $script:PlanningFormClosingRegistered) {
        $panel.Add_ParentChanged({
            if ($script:PlanningFormClosingRegistered) { return }
            $frm = $this.FindForm()
            if ($null -eq $frm) { return }
            $script:PlanningFormClosingRegistered = $true
            $frm.Add_FormClosing({
                if ($script:PlanningRunning -or $script:PlanningRebuildUiBusy) {
                    Request-PlanningRebuildStop
                    Stop-PlanningRebuildJobIfRunning
                    Request-CnsSharePointConnectCancel
                    if ($null -ne $script:PlanningSharePointWorker -and $script:PlanningSharePointWorker.IsBusy) {
                        $script:PlanningSharePointWorker.CancelAsync()
                    }
                    Start-Sleep -Milliseconds 500
                }
            })
        })
    }

    function script:Get-PlanningCtrl {
        param(
            [System.Windows.Forms.Control]$Root,
            [string]$Name,
            [Type]$ExpectedType
        )
        if ($null -eq $Root) { return $null }
        $found = $null
        function script:Find-PlanningCtrlRecursive {
            param($Node, $TargetName, $Expected)
            if ($null -eq $Node) { return $null }
            if ([string]$Node.Name -eq $TargetName) {
                if ($null -eq $Expected -or $Node -is $Expected) { return $Node }
            }
            foreach ($child in @($Node.Controls)) {
                $hit = Find-PlanningCtrlRecursive -Node $child -TargetName $TargetName -Expected $Expected
                if ($null -ne $hit) { return $hit }
            }
            return $null
        }
        return (Find-PlanningCtrlRecursive -Node $Root -TargetName $Name -Expected $ExpectedType)
    }

    function script:Invoke-PlanningPanelUi {
        param([scriptblock]$Action)
        if ($null -eq $Action) { return }
        Safe-UpdateUIControl -Control $panel -UpdateAction $Action
    }

    $script:PlanningSharePointActionHandler = {
        param([string]$ActionId)
        switch ($ActionId) {
            'Refresh' {
                Start-PlanningSharePointSync -ForceRefresh -ShowConnecting
            }
            'Login' {
                Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
                Start-PlanningSharePointSync -ForceRefresh -InteractiveLogin -ShowConnecting
            }
            'Copy' {
                Copy-SharePointErrorToClipboard -State $script:PlanningSharePointState
                [System.Windows.Forms.MessageBox]::Show(
                    'Erreur copiee dans le presse-papier.',
                    'SharePoint',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
            }
        }
    }

    function script:Invoke-PlanningRebuildRun {
        if ($script:PlanningRebuildUiBusy) { return }

        $inputs = Test-PlanningRebuildInputPaths -ShowMessage
        if ($null -eq $inputs) { return }

        Set-PlanningRunningState -IsRunning $true
        Reset-PlanningRebuildStop
        Reset-PlanningRebuildProgressUiState
        $script:PlanningCurrentStepIndex = 0
        $script:PlanningProgressHadError = $false
        $script:PlanningStep2ActivityLabel = $script:PlanningRebuilderPanelContext.Ui.LblStep2Activity

        $rootPanel = $script:PlanningRebuilderPanelContext.Panel
        Safe-UpdateUIControl -Control $rootPanel -UpdateAction {
            $ui = $script:PlanningRebuilderPanelContext.Ui
            if ($ui.BtnPdf -is [System.Windows.Forms.Control]) { $ui.BtnPdf.Enabled = $false }
            if ($ui.BtnLancer -is [System.Windows.Forms.Control]) { $ui.BtnLancer.Enabled = $false }
            if ($ui.BtnStop -is [System.Windows.Forms.Control]) { $ui.BtnStop.Enabled = $true }
            Set-PlanningControlText -Control $ui.LblOutputPdf -Text ''
            Set-PlanningControlText -Control $ui.LblStepProgress -Text 'Demarrage du traitement...'
            Set-PlanningControlText -Control $ui.LblPercent -Text '0%'
            if ($ui.TxtDebug -is [System.Windows.Forms.Control]) { $ui.TxtDebug.Clear() }
            if ($ui.ProgressBar -is [System.Windows.Forms.Control]) { $ui.ProgressBar.Value = 0 }
        }

        Start-PlanningRebuildJob -PdfPath $inputs.PdfPath -ExcelPath $inputs.ExcelPath -RootPanel $rootPanel
    }

    $script:PlanningRebuilderPanelContext.SharePointActionHandler = $script:PlanningSharePointActionHandler
    if ($null -ne $spUi.Connect) {
        $spUi.Connect.Add_Click({
            if ($script:PlanningRebuildUiBusy) { return }
            if (Test-CnsSharePointAuthInProgress) {
                Write-Host 'Authentification Microsoft 365 deja en cours...' -ForegroundColor Yellow
                return
            }
            $connectTag = $null
            if ($null -ne $spUi.Connect.Tag) {
                $connectTag = [string]$spUi.Connect.Tag
            }
            if ($script:CurrentUIMode -eq 'SharePoint' -or $connectTag -eq 'Disconnect') {
                Switch-PlanningToLocalUIMode
                return
            }
            $script:PlanningSharePointConnectionStarted = $false
            Switch-PlanningToSharePointUIMode
            Start-SharePointConnectionBackground -InteractiveLogin -ForceRefresh
        })
    }
    $rebuildCmd = Get-Command Invoke-PlanningRebuildRun -ErrorAction SilentlyContinue
    if ($null -ne $rebuildCmd) {
        $script:PlanningRebuilderPanelContext.RebuildRunHandler = $rebuildCmd
    }

    $btnImportExcel.Add_Click({
        if ($script:PlanningRebuildUiBusy) { return }

        $ofd = [System.Windows.Forms.OpenFileDialog]::new()
        $ofd.Filter = 'Excel (*.xls;*.xlsx;*.xlsm)|*.xls;*.xlsx;*.xlsm|Tous les fichiers (*.*)|*.*'
        $ofd.Title = 'Selectionner le planning Excel'
        if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

        $script:ManualExcelPath = $ofd.FileName
        $script:ActiveExcelPath = $script:ManualExcelPath
        Update-PlanningExcelPathLabel
    })

    $btnResetToSharePoint.Add_Click({
        if ($script:PlanningRebuildUiBusy) { return }
        $script:PlanningSharePointConnectionStarted = $false
        Switch-PlanningToSharePointUIMode
        Start-SharePointConnectionBackground -InteractiveLogin -ForceRefresh
    })

    $btnLancer.Add_Click({
        if ($script:PlanningRebuildUiBusy) { return }
        $rebuildHandler = $script:PlanningRebuilderPanelContext.RebuildRunHandler
        if ($null -ne $rebuildHandler) {
            & $rebuildHandler
        }
    })

    $btnStop.Add_Click({
        Request-PlanningRebuildStop
        if ($null -ne $script:PlanningRebuildJob -and $script:PlanningRebuildJob.State -eq 'Running') {
            Stop-Job -Job $script:PlanningRebuildJob -ErrorAction SilentlyContinue
        }
        $ui = $script:PlanningRebuilderPanelContext.Ui
        if ($null -ne $ui -and $null -ne $ui.BtnStop -and $ui.BtnStop -is [System.Windows.Forms.Control]) { $ui.BtnStop.Enabled = $false }
        if ($null -ne $ui -and $null -ne $ui.LblStepProgress) { Set-PlanningControlText -Control $ui.LblStepProgress -Text 'Arret demande...' }
    })

    $btnPdf.Add_Click({
        if ($script:PlanningRebuildUiBusy) { return }
        $ofd = [System.Windows.Forms.OpenFileDialog]::new()
        $ofd.Filter = 'PDF (*.pdf)|*.pdf|Tous les fichiers (*.*)|*.*'
        if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

        $script:PlanningPdfPath = $ofd.FileName

        $pdfLabel = $null
        $outputLabel = $null
        $rootPanel = $null
        if ($null -ne $script:PlanningRebuilderPanelContext) {
            if ($null -ne $script:PlanningRebuilderPanelContext.Ui) {
                $pdfLabel = $script:PlanningRebuilderPanelContext.Ui.LblPdf
                $outputLabel = $script:PlanningRebuilderPanelContext.Ui.LblOutputPdf
            }
            $rootPanel = $script:PlanningRebuilderPanelContext.Panel
        }

        $pdfName = Split-Path -Leaf $script:PlanningPdfPath
        $updatePdfLabels = {
            Set-PlanningControlText -Control $pdfLabel -Text ('PDF : {0}' -f $pdfName)
            Set-PlanningControlText -Control $outputLabel -Text ''
        }
        if ($null -ne $rootPanel -and $rootPanel -is [System.Windows.Forms.Control]) {
            Safe-UpdateUIControl -Control $rootPanel -UpdateAction $updatePdfLabels
        }
        else {
            & $updatePdfLabels
        }
    })

    Update-PlanningExcelPathLabel
    Update-PlanningUIMode

    $panel.Add_HandleCreated({
        Update-PlanningSharePointUiState -State ([pscustomobject]@{
                Status  = 'Offline'
                Message = 'Connexion échouée – cliquez sur "Connexion" pour réessayer'
            })
        Start-SharePointConnectionBackground
    })

    # Diagnostic zone SharePoint (temporaire)
    Write-Host '=== DIAGNOSTIC SHAREPOINT ZONE ===' -ForegroundColor Cyan
    $spGroup = $spUi.GroupBox
    if ($null -ne $spGroup) {
        Write-Host "GroupBox trouve (grpSharePoint) : Visible=$($spGroup.Visible), Height=$($spGroup.Height), ClientSize=$($spGroup.ClientSize)"
        Write-Host "Contrôles enfants : $($spGroup.Controls.Count)"
        foreach ($ctrl in $spGroup.Controls) {
            Write-Host "  - $($ctrl.Name) : Visible=$($ctrl.Visible), Text='$($ctrl.Text)'"
        }
    }
    else {
        Write-Host "GroupBox grpSharePoint NON TROUVE"
    }
    Write-Host '=================================' -ForegroundColor Cyan

    return $panel
}

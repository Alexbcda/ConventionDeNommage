# Helpers UI pour l'onglet Edition planning (thread-safe, labels Excel).

function Safe-UpdateUIControl {
    param(
        [System.Windows.Forms.Control]$Control,
        [scriptblock]$UpdateAction
    )

    if ($null -eq $UpdateAction) { return }
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

function Show-PlanningStatusMessage {
    param(
        [System.Windows.Forms.Label]$StatusLabel,
        [Parameter(Mandatory = $true)][string]$Message,
        [System.Drawing.Color]$Color = [System.Drawing.Color]::Black
    )

    if ($null -eq $StatusLabel) {
        $ctx = $script:PlanningRebuilderPanelContext
        if ($null -ne $ctx -and $null -ne $ctx.SpUi -and $null -ne $ctx.SpUi.Status) {
            $StatusLabel = $ctx.SpUi.Status
        }
    }
    if ($null -eq $StatusLabel -or $StatusLabel -isnot [System.Windows.Forms.Control]) { return }

    Invoke-PlanningSafeUpdateUi -Control $StatusLabel -UpdateAction {
        $StatusLabel.Text = $Message
        $StatusLabel.ForeColor = $Color
        $StatusLabel.Refresh()
    }
}

function Invoke-PlanningSafeUpdateUi {
    param(
        [System.Windows.Forms.Control]$Control,
        [scriptblock]$UpdateAction
    )
    $cmd = $global:PlanningSafeUpdateUiCmd
    if ($null -ne $cmd) {
        & $cmd -Control $Control -UpdateAction $UpdateAction
        return
    }
    if (Get-Command -Name Safe-UpdateUIControl -ErrorAction SilentlyContinue) {
        $cmd = Get-Command -Name Safe-UpdateUIControl -ErrorAction Stop
        $global:PlanningSafeUpdateUiCmd = $cmd
        & $cmd -Control $Control -UpdateAction $UpdateAction
        return
    }
    # Secours inline : ne depend pas d'une commande nommee (handlers BackgroundWorker / scope isole).
    if ($null -eq $UpdateAction) { return }
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
        Write-Debug ("Invoke-PlanningSafeUpdateUi: {0}" -f $_.Exception.Message)
    }
}

function Import-PlanningRebuilderModule {
    param(
        [Parameter(Mandatory = $true)][string]$ModulePath
    )
    if (Get-Module -Name PlanningUILightImport -ErrorAction SilentlyContinue) {
        return
    }
    if (Get-Module -Name PlanningRebuilderImport -ErrorAction SilentlyContinue) {
        return
    }
    if (-not (Test-Path -LiteralPath $ModulePath)) {
        throw "Module planning introuvable : $ModulePath"
    }
    Import-Module -Name $ModulePath -Scope Global -Force -ErrorAction Stop
    if (-not (Get-Command Show-PlanningRebuilderPanel -ErrorAction SilentlyContinue)) {
        throw 'Show-PlanningRebuilderPanel introuvable apres Import-Module PlanningRebuilderImport.'
    }
}

# Export en scope Global (lazy load + handlers WinForms async).
# Noms avec tirets : utiliser Set-Item, pas ${function:Safe-UpdateUIControl} (erreur parseur PS).
foreach ($helperName in @(
        'Safe-UpdateUIControl',
        'Update-PlanningExcelPathLabel',
        'Set-PlanningControlText',
        'Show-PlanningStatusMessage',
        'Invoke-PlanningSafeUpdateUi'
    )) {
    $srcFn = Get-Item -Path "function:$helperName" -ErrorAction Stop
    Set-Item -Path "function:global:$helperName" -Value $srcFn
}
if (-not $global:PlanningSafeUpdateUiCmd) {
    $global:PlanningSafeUpdateUiCmd = Get-Command -Name Safe-UpdateUIControl -ErrorAction SilentlyContinue
}

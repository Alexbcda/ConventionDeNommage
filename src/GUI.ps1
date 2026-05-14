# GUI.ps1 - Version simplifiée

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Get-Command Convert-ToUiText -ErrorAction SilentlyContinue)) {
    . "$scriptDir\Common\TextEncoding.ps1"
    . "$scriptDir\Common\UiText.ps1"
}
. "$scriptDir\Common\Styles.ps1"

function Ensure-WinFormsInitialized {
    if (-not (Get-Command Initialize-ApplicationWinForms -ErrorAction SilentlyContinue)) {
        $_boot = Join-Path $PSScriptRoot 'Common\WinFormsBootstrap.ps1'
        if (Test-Path -LiteralPath $_boot) {
            . $_boot
        }
    }
    if (Get-Command Initialize-ApplicationWinForms -ErrorAction SilentlyContinue) {
        Initialize-ApplicationWinForms
    }
    else {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        [System.Windows.Forms.Application]::EnableVisualStyles()
        [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
        $global:WinFormsInitialized = $true
        $global:WinFormsApplicationInitialized = $true
    }
}

function Start-GUI {
    param([string]$FichierPDF)

    Ensure-WinFormsInitialized
    Initialize-WinFormsUiCultureFrFr

    . "$PSScriptRoot\Config.ps1"
    . "$scriptDir\ODM\PdfPlanningOptimizer\PlanningRebuilderPanel.ps1"
    . "$PSScriptRoot\ODM\ConventionNommage\ConventionNommage.ps1"
    . "$PSScriptRoot\ODM\Agents\AgentPanel.ps1"
    . "$PSScriptRoot\ODM\Vehicules\VehiculesPanel.ps1"

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = "Convention de nommage"
    $form.Size = [System.Drawing.Size]::new(1400, 800)
    $form.StartPosition = "CenterScreen"
    $form.MinimumSize = [System.Drawing.Size]::new(1000, 650)
    $form.Font = $script:PoliceNormal
    $form.BackColor = $script:CouleurGrisFond
    $null = $form.Add_Load({
        $null = [System.Text.Encoding]::Default
    })

    $tabControl = [System.Windows.Forms.TabControl]::new()
    $tabControl.Dock = "Fill"
    $tabControl.Font = $script:PoliceNormal
    $tabControl.Name = "MainTabControl"

    # ONGLET 1 : Convention de nommage
    $tabRename = [System.Windows.Forms.TabPage]::new()
    $tabRename.Name = "TabConventionNommage"
    $tabRename.Text = "Convention de nommage"
    $tabRename.BackColor = $script:CouleurGrisFond
    
    $panelResult = Show-ConventionNommagePanel -FichierPDF $FichierPDF
    $realPanel = $panelResult[-1]
    $tabRename.Controls.Add($realPanel)
    if ($realPanel) { $realPanel.Name = "ConventionNommageRootPanel" }
    $tabControl.TabPages.Add($tabRename)

    # ONGLET 2 : Agents
    $tabAgents = [System.Windows.Forms.TabPage]::new()
    $tabAgents.Text = "Données agents"
    $tabAgents.BackColor = $script:CouleurGrisFond
    
    $agentsPanel = Show-AgentsPanel
    if ($agentsPanel) {
        $agentsPanel.Dock = "Fill"
        $tabAgents.Controls.Add($agentsPanel)
    } else {
        $lblError = [System.Windows.Forms.Label]::new()
        $lblError.Text = "Erreur de chargement du panneau des agents"
        $lblError.Dock = "Fill"
        $lblError.TextAlign = "MiddleCenter"
        $lblError.ForeColor = [System.Drawing.Color]::Red
        $tabAgents.Controls.Add($lblError)
    }
    $tabControl.TabPages.Add($tabAgents)

    # ONGLET 3 : Vehicules
    $tabVehicules = [System.Windows.Forms.TabPage]::new()
    $tabVehicules.Text = "Données véhicules"
    $tabVehicules.BackColor = $script:CouleurGrisFond
    $vehiculesPanel = Show-VehiculesPanel
    if ($vehiculesPanel) {
        $vehiculesPanel.Dock = "Fill"
        $tabVehicules.Controls.Add($vehiculesPanel)
    }
    $tabControl.TabPages.Add($tabVehicules)

    # ONGLET 4 : Edition planning
    $tabPlanning = [System.Windows.Forms.TabPage]::new()
    $tabPlanning.Text = "Edition planning"
    $tabPlanning.BackColor = $script:CouleurGrisFond
    $planningPanel = Show-PlanningRebuilderPanel
    if ($planningPanel) {
        $planningPanel.Dock = "Fill"
        $tabPlanning.Controls.Add($planningPanel)
    }
    $tabControl.TabPages.Add($tabPlanning)

    $form.Controls.Add($tabControl)
    Update-WinFormsTreeUiTexts -RootControl $form

    $form.Add_Shown({
        param($sender, $e)
        Start-Sleep -Milliseconds 100
        $frm = $sender
        if ($null -eq $frm -or $frm -isnot [System.Windows.Forms.Form]) { return }
        $tabs = $frm.Controls["MainTabControl"]
        if ($null -eq $tabs -or $tabs -isnot [System.Windows.Forms.TabControl]) { return }
        $tab = $tabs.TabPages["TabConventionNommage"]
        if ($null -eq $tab) { return }
        $rootPanel = $tab.Controls["ConventionNommageRootPanel"]
        if ($null -ne $rootPanel) {
            $txtBox = $rootPanel.Controls | Where-Object { $_ -is [System.Windows.Forms.TextBox] }
            if ($txtBox) { $txtBox.Focus() }
        }
    })

    [System.Windows.Forms.Application]::Run($form)
}




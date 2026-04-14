# GUI.ps1 - Version simplifiée

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir\Framework\Components.ps1"
. "$scriptDir\Common\Styles.ps1"
. "$scriptDir\Core\Logger.ps1"

function Start-GUI {
    param([string]$FichierPDF)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    Write-Log "[GUI] Start-GUI" "INFO" @{ FichierPDF = $FichierPDF }

    . "$PSScriptRoot\Config.ps1"
    . "$PSScriptRoot\ODM\ConventionNommage\ConventionNommage.ps1"
    . "$PSScriptRoot\ODM\Agents\AgentPanel.ps1"
    . "$PSScriptRoot\ODM\Agents\AgentRepository.ps1"
    . "$PSScriptRoot\ODM\Vehicules\VehiculesPanel.ps1"
    . "$PSScriptRoot\ODM\Vehicules\VehiculesManager.ps1"
    . "$PSScriptRoot\ODM\Affectations\Date.ps1"
    . "$PSScriptRoot\ODM\Affectations\DatePanel.ps1"
    . "$PSScriptRoot\ODM\Affectations\AffectationNbTournees.ps1"
    . "$PSScriptRoot\ODM\Affectations\AffectationNbTourneesPanel.ps1"
        
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Convention de nommage"
    $form.Size = New-Object System.Drawing.Size(1400, 800)
    $form.StartPosition = "CenterScreen"
    $form.MinimumSize = New-Object System.Drawing.Size(1000, 650)
    $form.Font = $script:PoliceNormal
    $form.BackColor = $script:CouleurGrisFond

    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Dock = "Fill"
    $tabControl.Font = $script:PoliceNormal
    $tabControl.Name = "MainTabControl"

    # ONGLET 1 : Convention de nommage
    $tabRename = New-Object System.Windows.Forms.TabPage
    $tabRename.Text = "Convention de nommage"
    $tabRename.BackColor = $script:CouleurGrisFond
    
    $panelResult = Show-ConventionNommagePanel -FichierPDF $FichierPDF
    $realPanel = $panelResult[-1]
    $tabRename.Controls.Add($realPanel)
    $tabControl.TabPages.Add($tabRename)

    # ONGLET 2 : Affectation
    $tabAffectation = New-Object System.Windows.Forms.TabPage
    $tabAffectation.Text = "Affectation"
    $tabAffectation.BackColor = $script:CouleurGrisFond
    $affectationContainer = New-Object System.Windows.Forms.Panel
    $affectationContainer.Dock = "Fill"
    $affectationContainer.Name = "AffectationContainer"
    $panelDate = Show-DatePanel -NextPanel $null -CurrentPanel $null
    $panelDate.Dock = "Fill"
    $panelDate.Name = "DatePanel"
    $panelTournees = Show-AffectationNbTourneesPanel -NextPanel $null -CurrentPanel $null
    $panelTournees.Dock = "Fill"
    $panelTournees.Name = "TourneesPanel"
    $panelTournees.Visible = $false
    $affectationContainer.Controls.Add($panelDate)
    $affectationContainer.Controls.Add($panelTournees)
    $tabAffectation.Controls.Add($affectationContainer)
    $tabControl.TabPages.Add($tabAffectation)
    $form.Tag = $affectationContainer

    # ONGLET 3 : Agents
    $tabAgents = New-Object System.Windows.Forms.TabPage
    $tabAgents.Text = "Agents"
    $tabAgents.BackColor = $script:CouleurGrisFond
    
    $agentsPanelResult = Show-AgentsPanel
    $agentsPanel = $agentsPanelResult | Where-Object { $_ -is [System.Windows.Forms.Panel] } | Select-Object -Last 1
    if ($agentsPanel) {
        $agentsPanel.Dock = "Fill"
        $tabAgents.Controls.Add($agentsPanel)
        Write-Host "[GUI] Onglet Agents ajouté" -ForegroundColor Green
    } else {
        Write-Host "[GUI] Erreur: Show-AgentsPanel a retourné null" -ForegroundColor Red
        $lblError = New-Object System.Windows.Forms.Label
        $lblError.Text = "Erreur de chargement du panneau des agents"
        $lblError.Dock = "Fill"
        $lblError.TextAlign = "MiddleCenter"
        $lblError.ForeColor = [System.Drawing.Color]::Red
        $tabAgents.Controls.Add($lblError)
    }
    $tabControl.TabPages.Add($tabAgents)

    # ONGLET 4 : Vehicules
    $tabVehicules = New-Object System.Windows.Forms.TabPage
    $tabVehicules.Text = "Données véhicules"
    $tabVehicules.BackColor = $script:CouleurGrisFond
    $vehiculesPanel = Show-VehiculesPanel -Vehicules (Get-Vehicules)
    if ($vehiculesPanel) {
        $vehiculesPanel.Dock = "Fill"
        $tabVehicules.Controls.Add($vehiculesPanel)
    }
    $tabControl.TabPages.Add($tabVehicules)

    $form.Controls.Add($tabControl)

    $form.Add_Shown({
        Start-Sleep -Milliseconds 100
        if ($realPanel) {
            $txtBox = $realPanel.Controls | Where-Object { $_ -is [System.Windows.Forms.TextBox] }
            if ($txtBox) { $txtBox.Focus() }
        }
    })

    [System.Windows.Forms.Application]::Run($form)
}

function Show-PDFViewer {
    param([string]$FilePath, [string]$Title = "Visionneuse PDF")
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    if (-not (Test-Path $FilePath)) {
        [System.Windows.Forms.MessageBox]::Show("Fichier non trouve : $FilePath", "Erreur")
        return
    }
    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.Size = New-Object System.Drawing.Size(1000, 700)
    $form.StartPosition = "CenterScreen"
    $webBrowser = New-Object System.Windows.Forms.WebBrowser
    $webBrowser.Dock = "Fill"
    try { $webBrowser.Navigate($FilePath); $form.Controls.Add($webBrowser) }
    catch { Start-Process $FilePath }
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = "FERMER"
    $btnClose.Size = New-Object System.Drawing.Size(100, 40)
    $btnClose.Anchor = "Bottom,Right"
    $btnClose.Location = New-Object System.Drawing.Point($form.ClientSize.Width - 120, $form.ClientSize.Height - 50)
    $btnClose.BackColor = $script:CouleurOrange
    $btnClose.ForeColor = $script:CouleurBlanc
    $btnClose.FlatStyle = "Flat"
    $btnClose.Font = $script:PoliceBouton
    $btnClose.Add_Click({ $form.Close() })
    $form.Controls.Add($btnClose)
    $form.ShowDialog()
}


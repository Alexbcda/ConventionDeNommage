# GUI.ps1 - Interface graphique avec gestion des règles

function Start-GUI {
    param([string]$FichierPDF)
    
    . "$PSScriptRoot\Config.ps1"
    . "$PSScriptRoot\Core\Rename.ps1"
    . "$PSScriptRoot\Core\TemplateManager.ps1"
    . "$PSScriptRoot\Core\TemplateEditor.ps1"
    
    if (-not $FichierPDF -or -not (Test-Path $FichierPDF)) { exit }
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Convention de nommage - v2.0"
    $form.Size = New-Object System.Drawing.Size(700, 500)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.BackColor = $formBackColor
    $form.Font = $font
    $form.Topmost = $true
    
    # Onglets principaux
    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Dock = "Fill"
    $tabControl.Padding = New-Object System.Drawing.Point(10, 5)
    
    # Onglet 1 : Renommage
    $tabRename = New-Object System.Windows.Forms.TabPage
    $tabRename.Text = "🏷️ Renommage"
    
    # Onglet 2 : Gestion des règles
    $tabManage = New-Object System.Windows.Forms.TabPage
    $tabManage.Text = "⚙️ Gestion des règles"
    
    $tabControl.TabPages.Add($tabRename)
    $tabControl.TabPages.Add($tabManage)
    
    # ========== ONGLET RENOMMAGE ==========
    $panelRename = New-Object System.Windows.Forms.Panel
    $panelRename.Dock = "Fill"
    $panelRename.Padding = New-Object System.Windows.Forms.Padding(20, 10, 20, 10)
    
    $margeGauche = 35
    $largeurPlaceholder = 470
    
    # Champ texte avec placeholder dynamique
    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point($margeGauche, 40)
    $textBox.Size = New-Object System.Drawing.Size($largeurPlaceholder, 35)
    $textBox.Font = $font
    
    $placeholderLabel = New-Object System.Windows.Forms.Label
    $placeholderLabel.Text = "Chargement..."
    $placeholderLabel.Location = New-Object System.Drawing.Point($margeGauche + 5, 48)
    $placeholderLabel.Size = New-Object System.Drawing.Size($largeurPlaceholder - 10, 20)
    $placeholderLabel.ForeColor = [System.Drawing.Color]::Gray
    $placeholderLabel.Font = New-Object System.Drawing.Font("Arial", 9)
    $placeholderLabel.Visible = $false
    
    $panelRename.Controls.Add($textBox)
    $panelRename.Controls.Add($placeholderLabel)
    
    # Panel pour les boutons dynamiques
    $buttonsPanel = New-Object System.Windows.Forms.Panel
    $buttonsPanel.Location = New-Object System.Drawing.Point($margeGauche, 95)
    $buttonsPanel.Size = New-Object System.Drawing.Size(610, 120)
    $buttonsPanel.AutoScroll = $true
    $panelRename.Controls.Add($buttonsPanel)
    
    # Calendrier
    $calLabel = New-Object System.Windows.Forms.Label
    $calLabel.Text = "Forcer la date :"
    $calLabel.Location = New-Object System.Drawing.Point($margeGauche, 225)
    $calLabel.Size = New-Object System.Drawing.Size(120, 20)
    $calLabel.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $panelRename.Controls.Add($calLabel)
    
    $datePicker = New-Object System.Windows.Forms.DateTimePicker
    $datePicker.Location = New-Object System.Drawing.Point($margeGauche, 250)
    $datePicker.Size = New-Object System.Drawing.Size(220, 25)
    $datePicker.Format = "Short"
    $datePicker.Font = New-Object System.Drawing.Font("Arial", 9)
    
    function Get-DateParDefaut {
        $aujourdhui = Get-Date
        $jourSemaine = $aujourdhui.DayOfWeek
        if ($jourSemaine -eq "Monday") { return $aujourdhui.AddDays(-3) }
        else { return $aujourdhui.AddDays(-1) }
    }
    
    $dateParDefaut = Get-DateParDefaut
    $datePicker.Value = $dateParDefaut
    $panelRename.Controls.Add($datePicker)
    
    $forceLabel = New-Object System.Windows.Forms.Label
    $forceLabel.Location = New-Object System.Drawing.Point(($margeGauche + 230), 252)
    $forceLabel.Size = New-Object System.Drawing.Size(220, 20)
    $forceLabel.Font = New-Object System.Drawing.Font("Arial", 8, [System.Drawing.FontStyle]::Bold)
    $forceLabel.ForeColor = [System.Drawing.Color]::Red
    $forceLabel.Text = ""
    $panelRename.Controls.Add($forceLabel)
    
    $btnManageRules = New-Object System.Windows.Forms.Button
    $btnManageRules.Text = "⚙️ Gérer les règles"
    $btnManageRules.Location = New-Object System.Drawing.Point($margeGauche, 300)
    $btnManageRules.Size = New-Object System.Drawing.Size(200, 40)
    $btnManageRules.BackColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $btnManageRules.ForeColor = [System.Drawing.Color]::White
    $btnManageRules.FlatStyle = "Flat"
    $btnManageRules.Font = New-Object System.Drawing.Font("Arial", 10)
    $panelRename.Controls.Add($btnManageRules)
    
    $tabRename.Controls.Add($panelRename)
    
    # ========== ONGLET GESTION DES RÈGLES ==========
    $panelManage = New-Object System.Windows.Forms.Panel
    $panelManage.Dock = "Fill"
    $panelManage.Padding = New-Object System.Windows.Forms.Padding(20)
    
    $lblManageTitle = New-Object System.Windows.Forms.Label
    $lblManageTitle.Text = "Gestion des règles de nommage"
    $lblManageTitle.Location = New-Object System.Drawing.Point(20, 20)
    $lblManageTitle.Size = New-Object System.Drawing.Size(400, 30)
    $lblManageTitle.Font = New-Object System.Drawing.Font("Arial", 14, [System.Drawing.FontStyle]::Bold)
    
    $lblManageDesc = New-Object System.Windows.Forms.Label
    $lblManageDesc.Text = "Créez, modifiez ou supprimez vos règles personnalisées"
    $lblManageDesc.Location = New-Object System.Drawing.Point(20, 55)
    $lblManageDesc.Size = New-Object System.Drawing.Size(400, 20)
    $lblManageDesc.ForeColor = [System.Drawing.Color]::Gray
    
    $rulesListBox = New-Object System.Windows.Forms.ListBox
    $rulesListBox.Location = New-Object System.Drawing.Point(20, 90)
    $rulesListBox.Size = New-Object System.Drawing.Size(400, 300)
    $rulesListBox.Font = New-Object System.Drawing.Font("Arial", 10)
    
    $btnOpenEditor = New-Object System.Windows.Forms.Button
    $btnOpenEditor.Text = "📝 Ouvrir l'éditeur de règles"
    $btnOpenEditor.Location = New-Object System.Drawing.Point(440, 90)
    $btnOpenEditor.Size = New-Object System.Drawing.Size(200, 50)
    $btnOpenEditor.BackColor = [System.Drawing.Color]::FromArgb(27, 91, 74)
    $btnOpenEditor.ForeColor = [System.Drawing.Color]::White
    $btnOpenEditor.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $btnOpenEditor.FlatStyle = "Flat"
    
    $btnRefreshRules = New-Object System.Windows.Forms.Button
    $btnRefreshRules.Text = "🔄 Rafraîchir"
    $btnRefreshRules.Location = New-Object System.Drawing.Point(440, 150)
    $btnRefreshRules.Size = New-Object System.Drawing.Size(200, 40)
    $btnRefreshRules.BackColor = [System.Drawing.Color]::FromArgb(80, 171, 242)
    $btnRefreshRules.ForeColor = [System.Drawing.Color]::White
    $btnRefreshRules.FlatStyle = "Flat"
    
    $panelManage.Controls.Add($lblManageTitle)
    $panelManage.Controls.Add($lblManageDesc)
    $panelManage.Controls.Add($rulesListBox)
    $panelManage.Controls.Add($btnOpenEditor)
    $panelManage.Controls.Add($btnRefreshRules)
    
    $tabManage.Controls.Add($panelManage)
    
    $form.Controls.Add($tabControl)
    
    # Variables
    $script:estEnModePlaceholder = $true
    $script:texteUtilisateur = ""
    $script:formulaireCharge = $false
    $script:dateForcee = $false
    $script:dateSelectionnee = $datePicker.Value
    $script:currentPlaceholder = ""
    $script:templates = @()
    
    # Fonctions
    function Load-TemplatesAndButtons {
        try {
            $script:templates = Get-Templates | Where-Object { $_.enabled -eq $true }
            $buttonsPanel.Controls.Clear()
            
            $x = 0
            $y = 0
            $btnWidth = 146
            $btnHeight = 50
            $spacing = 15
            $maxPerRow = 4
            
            for ($i = 0; $i -lt $script:templates.Count; $i++) {
                $template = $script:templates[$i]
                
                $btn = New-Object System.Windows.Forms.Button
                $btn.Text = $template.name
                $btn.Location = New-Object System.Drawing.Point($x, $y)
                $btn.Size = New-Object System.Drawing.Size($btnWidth, $btnHeight)
                $btn.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
                $btn.FlatStyle = "Flat"
                $btn.FlatAppearance.BorderColor = [System.Drawing.ColorTranslator]::FromHtml($template.borderColor)
                $btn.FlatAppearance.BorderSize = 2
                $btn.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
                $btn.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
                $btn.TextAlign = "MiddleCenter"
                $btn.Tag = $template.id
                
                $btn.Add_MouseEnter({
                    $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200, 80, 80)
                    $this.BackColor = [System.Drawing.ColorTranslator]::FromHtml($($this.Tag | ForEach-Object { ($script:templates | Where-Object { $_.id -eq $_ }).buttonColor }))
                    $this.ForeColor = [System.Drawing.Color]::White
                })
                
                $btn.Add_MouseLeave({
                    $templateData = $script:templates | Where-Object { $_.id -eq $this.Tag }
                    $this.FlatAppearance.BorderColor = [System.Drawing.ColorTranslator]::FromHtml($templateData.borderColor)
                    $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
                    $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
                })
                
                $btn.Add_Click({
                    $templateId = $this.Tag
                    $template = $script:templates | Where-Object { $_.id -eq $templateId }
                    if ($template) {
                        Invoke-RenameAction -TemplateId $templateId -Template $template
                    }
                })
                
                $buttonsPanel.Controls.Add($btn)
                
                $x += $btnWidth + $spacing
                if (($i + 1) % $maxPerRow -eq 0) {
                    $x = 0
                    $y += $btnHeight + $spacing
                }
            }
            
            # Ajuster la hauteur du panel
            $buttonsPanel.Height = [Math]::Max(120, $y + $btnHeight + 20)
            
            # Mettre à jour le placeholder
            if ($script:templates.Count -gt 0) {
                $script:currentPlaceholder = $script:templates[0].placeholder
                $textBox.Tag = $script:currentPlaceholder
                if ($script:estEnModePlaceholder) {
                    $textBox.Text = $script:currentPlaceholder
                    $textBox.ForeColor = $placeholderColor
                }
            }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Erreur chargement templates : $_", "Erreur")
        }
    }
    
    function Update-RulesList {
        $rulesListBox.Items.Clear()
        $allTemplates = Get-Templates
        foreach ($t in $allTemplates) {
            $status = if ($t.enabled) { "✓" } else { "✗" }
            $rulesListBox.Items.Add("$status $($t.name) - $($t.description)")
            $rulesListBox.Items[$rulesListBox.Items.Count-1].Tag = $t.id
        }
    }
    
    function Set-PlaceholderMode {
        param($textBox, $activer)
        if ($activer) {
            $textBox.Text = $textBox.Tag
            $textBox.ForeColor = $placeholderColor
            $script:estEnModePlaceholder = $true
        } else {
            if ($script:texteUtilisateur -ne "") { $textBox.Text = $script:texteUtilisateur }
            else { $textBox.Text = "" }
            $textBox.ForeColor = $textBoxForeColor
            $script:estEnModePlaceholder = $false
        }
    }
    
    function Invoke-RenameAction {
        param($TemplateId, $Template)
        
        $nom = $textBox.Text.Trim()
        if ($nom -eq $script:currentPlaceholder) { $nom = "" }
        
        if ([string]::IsNullOrWhiteSpace($nom)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Veuillez renseigner " + $Template.placeholder,
                "Champ obligatoire",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            return
        }
        
        $dateUtilisee = if ($script:dateForcee) { $script:dateSelectionnee } else { $dateParDefaut }
        
        $ok = Rename-PDFDynamic -TemplateId $TemplateId -FichierPDF $FichierPDF -UserText $nom -DateSelectionnee $dateUtilisee
        
        if ($ok -eq $true) {
            $form.Close()
        }
    }
    
    # Événements
    $textBox.Add_Enter({
        if (-not $script:formulaireCharge) { return }
        if ($script:estEnModePlaceholder) {
            $this.Text = ""
            $this.ForeColor = $textBoxForeColor
            $script:estEnModePlaceholder = $false
        } else { $this.SelectAll() }
    })
    
    $textBox.Add_Leave({
        if (-not $script:formulaireCharge) { return }
        if (-not $script:estEnModePlaceholder) { $script:texteUtilisateur = $this.Text }
        if ([string]::IsNullOrWhiteSpace($this.Text)) {
            Set-PlaceholderMode -textBox $this -activer $true
            $script:texteUtilisateur = ""
        }
    })
    
    $textBox.Add_KeyUp({
        if ($_.KeyCode -eq "Enter" -and $script:formulaireCharge -and $script:templates.Count -gt 0) {
            $firstTemplate = $script:templates[0]
            Invoke-RenameAction -TemplateId $firstTemplate.id -Template $firstTemplate
        }
    })
    
    $datePicker.Add_ValueChanged({
        $script:dateSelectionnee = $this.Value
        if ($this.Value.Date -ne $dateParDefaut.Date) {
            $script:dateForcee = $true
            $forceLabel.Text = "Mode force: $($this.Value.ToString('dd/MM/yyyy'))"
        } else {
            $script:dateForcee = $false
            $forceLabel.Text = ""
        }
    })
    
    $btnManageRules.Add_Click({
        Show-TemplateEditor
        Load-TemplatesAndButtons
        Update-RulesList
    })
    
    $btnOpenEditor.Add_Click({
        Show-TemplateEditor
        Load-TemplatesAndButtons
        Update-RulesList
    })
    
    $btnRefreshRules.Add_Click({
        Update-RulesList
    })
    
    $form.Add_Shown({
        Load-TemplatesAndButtons
        Update-RulesList
        Set-PlaceholderMode -textBox $textBox -activer $true
        $form.BeginInvoke([Action]{
            Start-Sleep -Milliseconds 500
            $script:formulaireCharge = $true
            if ($buttonsPanel.Controls.Count -gt 0) {
                $buttonsPanel.Controls[0].Focus()
            }
        })
    })
    
    [System.Windows.Forms.Application]::EnableVisualStyles()
    [System.Windows.Forms.Application]::Run($form)
}

Export-ModuleMember -Function Start-GUI

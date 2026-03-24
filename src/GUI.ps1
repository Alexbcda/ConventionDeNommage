# GUI.ps1 - Interface graphique avec onglets

function Start-GUI {
    param([string]$FichierPDF)
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    . "$PSScriptRoot\Config.ps1"
    . "$PSScriptRoot\Core\TemplateManager.ps1"
    . "$PSScriptRoot\Core\Rename.ps1"
    . "$PSScriptRoot\Core\TemplateEditor.ps1"
    . "$PSScriptRoot\ODM\ODMViewer.ps1"
    
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Convention de nommage - v2.0"
    $form.Size = New-Object System.Drawing.Size(1200, 800)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.BackColor = $formBackColor
    $form.Font = $font
    $form.Topmost = $true
    
    # Onglets principaux
    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Dock = "Fill"
    $tabControl.Padding = New-Object System.Drawing.Point(10, 5)
    
    # ========== ONGLET 1 : CONVENTION DE NOMMAGE ==========
    $tabRename = New-Object System.Windows.Forms.TabPage
    $tabRename.Text = "🏷️ Convention de nommage"
    
    $panelRename = New-Object System.Windows.Forms.Panel
    $panelRename.Dock = "Fill"
    $panelRename.Padding = New-Object System.Windows.Forms.Padding(20, 10, 20, 10)
    
    $margeGauche = 35
    $largeurPlaceholder = 470
    
    # Champ texte
    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point($margeGauche, 40)
    $textBox.Size = New-Object System.Drawing.Size($largeurPlaceholder, 35)
    $textBox.Font = $font
    $panelRename.Controls.Add($textBox)
    
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
    
    $tabRename.Controls.Add($panelRename)
    
    # ========== ONGLET 2 : PLANNING (ODM) ==========
    $tabPlanning = New-Object System.Windows.Forms.TabPage
    $tabPlanning.Text = "📋 Planning (ODM)"
    
    # Appeler Show-ODMViewer
    $planningPanel = Show-ODMViewer
    $planningPanel.Dock = "Fill"
    $tabPlanning.Controls.Add($planningPanel)
    
    # Ajouter les onglets
    $tabControl.TabPages.Add($tabRename)
    $tabControl.TabPages.Add($tabPlanning)
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
                    $currentBtn = $this
                    $templateId = $currentBtn.Tag
                    $foundTemplate = $script:templates | Where-Object { $_.id -eq $templateId }
                    if ($foundTemplate) {
                        $borderHover = $foundTemplate.borderColor
                        if ($foundTemplate.name -eq "CERTIFICAT") { $borderHover = "#AF470B" }
                        elseif ($foundTemplate.name -eq "PLANNER") { $borderHover = "#1A6AA8" }
                        elseif ($foundTemplate.name -eq "FRANCE TRAVAIL") { $borderHover = "#1A9F7B" }
                        $currentBtn.FlatAppearance.BorderColor = [System.Drawing.ColorTranslator]::FromHtml($borderHover)
                        $currentBtn.BackColor = [System.Drawing.ColorTranslator]::FromHtml($foundTemplate.buttonColor)
                        $currentBtn.ForeColor = [System.Drawing.Color]::White
                    }
                })
                
                $btn.Add_MouseLeave({
                    $currentBtn = $this
                    $templateId = $currentBtn.Tag
                    $foundTemplate = $script:templates | Where-Object { $_.id -eq $templateId }
                    if ($foundTemplate) {
                        $currentBtn.FlatAppearance.BorderColor = [System.Drawing.ColorTranslator]::FromHtml($foundTemplate.borderColor)
                        $currentBtn.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
                        $currentBtn.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
                    }
                })
                
                $btn.Add_Click({
                    $clickedBtn = $this
                    $templateId = $clickedBtn.Tag
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
            
            $buttonsPanel.Height = [Math]::Max(120, $y + $btnHeight + 20)
            
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
            [System.Windows.Forms.MessageBox]::Show("Erreur chargement: $_", "Erreur")
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
    
    $form.Add_Shown({
        Load-TemplatesAndButtons
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

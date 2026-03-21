# TemplateEditor.ps1 - Interface complète de gestion des règles (CRUD)

function Show-TemplateEditor {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    . "$PSScriptRoot\TemplateManager.ps1"
    
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Gestion des règles de nommage - CRUD"
    $form.Size = New-Object System.Drawing.Size(950, 750)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $form.Topmost = $true
    
    # Variables
    $script:currentEditId = $null
    $script:selectedButtonColor = "#E26E2A"
    $script:selectedBorderColor = "#E26E2A"
    
    # Sélecteur de couleur
    $colorDialog = New-Object System.Windows.Forms.ColorDialog
    
    # Split container
    $splitContainer = New-Object System.Windows.Forms.SplitContainer
    $splitContainer.Dock = "Fill"
    $splitContainer.SplitterDistance = 350
    $splitContainer.Panel1.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
    $splitContainer.Panel2.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    
    # ========== PANEL GAUCHE - LISTE DES RÈGLES ==========
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "📋 Règles existantes"
    $lblTitle.Location = New-Object System.Drawing.Point(10, 10)
    $lblTitle.Size = New-Object System.Drawing.Size(320, 30)
    $lblTitle.Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)
    $splitContainer.Panel1.Controls.Add($lblTitle)
    
    $rulesListBox = New-Object System.Windows.Forms.ListBox
    $rulesListBox.Location = New-Object System.Drawing.Point(10, 45)
    $rulesListBox.Size = New-Object System.Drawing.Size(325, 550)
    $rulesListBox.Font = New-Object System.Drawing.Font("Arial", 10)
    $splitContainer.Panel1.Controls.Add($rulesListBox)
    
    $btnAdd = New-Object System.Windows.Forms.Button
    $btnAdd.Text = "➕ NOUVELLE RÈGLE"
    $btnAdd.Location = New-Object System.Drawing.Point(10, 610)
    $btnAdd.Size = New-Object System.Drawing.Size(325, 45)
    $btnAdd.BackColor = [System.Drawing.Color]::FromArgb(27, 91, 74)
    $btnAdd.ForeColor = [System.Drawing.Color]::White
    $btnAdd.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $btnAdd.FlatStyle = "Flat"
    $splitContainer.Panel1.Controls.Add($btnAdd)
    
    $btnDelete = New-Object System.Windows.Forms.Button
    $btnDelete.Text = "🗑️ SUPPRIMER"
    $btnDelete.Location = New-Object System.Drawing.Point(10, 660)
    $btnDelete.Size = New-Object System.Drawing.Size(325, 45)
    $btnDelete.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $btnDelete.ForeColor = [System.Drawing.Color]::White
    $btnDelete.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $btnDelete.FlatStyle = "Flat"
    $btnDelete.Enabled = $false
    $splitContainer.Panel1.Controls.Add($btnDelete)
    
    # ========== PANEL DROIT - ÉDITION ==========
    $panelEdit = New-Object System.Windows.Forms.Panel
    $panelEdit.Dock = "Fill"
    $panelEdit.Padding = New-Object System.Windows.Forms.Padding(15)
    $panelEdit.AutoScroll = $true
    $splitContainer.Panel2.Controls.Add($panelEdit)
    
    # Champs du formulaire avec placeholders
    $yPos = 10
    
    # Titre de la section
    $lblSectionTitle = New-Object System.Windows.Forms.Label
    $lblSectionTitle.Text = "✏️ INFORMATIONS GÉNÉRALES"
    $lblSectionTitle.Location = New-Object System.Drawing.Point(10, $yPos)
    $lblSectionTitle.Size = New-Object System.Drawing.Size(400, 25)
    $lblSectionTitle.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $lblSectionTitle.ForeColor = [System.Drawing.Color]::FromArgb(27, 91, 74)
    $panelEdit.Controls.Add($lblSectionTitle)
    
    $yPos += 35
    
    $lblName = New-Object System.Windows.Forms.Label
    $lblName.Text = "Nom de la règle :"
    $lblName.Location = New-Object System.Drawing.Point(10, $yPos)
    $lblName.Size = New-Object System.Drawing.Size(150, 25)
    $panelEdit.Controls.Add($lblName)
    
    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Location = New-Object System.Drawing.Point(170, $yPos)
    $txtName.Size = New-Object System.Drawing.Size(380, 25)
    $txtName.Text = ""
    # Placeholder
    $txtName.Tag = "ex: CERTIFICAT, PLANNER, FACTURE..."
    $txtName.Text = $txtName.Tag
    $txtName.ForeColor = [System.Drawing.Color]::Gray
    $panelEdit.Controls.Add($txtName)
    
    $yPos += 40
    
    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text = "Description :"
    $lblDesc.Location = New-Object System.Drawing.Point(10, $yPos)
    $lblDesc.Size = New-Object System.Drawing.Size(150, 25)
    $panelEdit.Controls.Add($lblDesc)
    
    $txtDesc = New-Object System.Windows.Forms.TextBox
    $txtDesc.Location = New-Object System.Drawing.Point(170, $yPos)
    $txtDesc.Size = New-Object System.Drawing.Size(380, 25)
    $txtDesc.Text = ""
    $txtDesc.Tag = "ex: Certificat de destruction pour déchets"
    $txtDesc.Text = $txtDesc.Tag
    $txtDesc.ForeColor = [System.Drawing.Color]::Gray
    $panelEdit.Controls.Add($txtDesc)
    
    $yPos += 45
    
    $lblSectionFormat = New-Object System.Windows.Forms.Label
    $lblSectionFormat.Text = "📝 FORMAT DE RENOMMAGE"
    $lblSectionFormat.Location = New-Object System.Drawing.Point(10, $yPos)
    $lblSectionFormat.Size = New-Object System.Drawing.Size(400, 25)
    $lblSectionFormat.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $lblSectionFormat.ForeColor = [System.Drawing.Color]::FromArgb(27, 91, 74)
    $panelEdit.Controls.Add($lblSectionFormat)
    
    $yPos += 35
    
    $lblFormat = New-Object System.Windows.Forms.Label
    $lblFormat.Text = "Format de renommage :"
    $lblFormat.Location = New-Object System.Drawing.Point(10, $yPos)
    $lblFormat.Size = New-Object System.Drawing.Size(150, 25)
    $panelEdit.Controls.Add($lblFormat)
    
    $txtFormat = New-Object System.Windows.Forms.TextBox
    $txtFormat.Location = New-Object System.Drawing.Point(170, $yPos)
    $txtFormat.Size = New-Object System.Drawing.Size(430, 25)
    $txtFormat.Text = ""
    $txtFormat.Tag = "{date}-{text}  ou  Certificat-{text}-du {date}"
    $txtFormat.Text = $txtFormat.Tag
    $txtFormat.ForeColor = [System.Drawing.Color]::Gray
    $panelEdit.Controls.Add($txtFormat)
    
    $yPos += 25
    
    $lblFormatHint = New-Object System.Windows.Forms.Label
    $lblFormatHint.Text = "💡 {text} = texte utilisateur | {date} = date"
    $lblFormatHint.Location = New-Object System.Drawing.Point(170, $yPos)
    $lblFormatHint.Size = New-Object System.Drawing.Size(430, 20)
    $lblFormatHint.Font = New-Object System.Drawing.Font("Arial", 8)
    $lblFormatHint.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $panelEdit.Controls.Add($lblFormatHint)
    
    $yPos += 40
    
    $lblDateFormat = New-Object System.Windows.Forms.Label
    $lblDateFormat.Text = "Format de date :"
    $lblDateFormat.Location = New-Object System.Drawing.Point(10, $yPos)
    $lblDateFormat.Size = New-Object System.Drawing.Size(150, 25)
    $panelEdit.Controls.Add($lblDateFormat)
    
    $cbDateFormat = New-Object System.Windows.Forms.ComboBox
    $cbDateFormat.Location = New-Object System.Drawing.Point(170, $yPos)
    $cbDateFormat.Size = New-Object System.Drawing.Size(150, 25)
    $cbDateFormat.Items.AddRange(@("dd.MM.yy", "yyyyMMdd", "dd-MM-yyyy", "MM/dd/yyyy", "yyyy-MM-dd", "dd/MM/yyyy"))
    $cbDateFormat.SelectedIndex = 0
    $panelEdit.Controls.Add($cbDateFormat)
    
    $yPos += 45
    
    $lblSectionUI = New-Object System.Windows.Forms.Label
    $lblSectionUI.Text = "🎨 INTERFACE UTILISATEUR"
    $lblSectionUI.Location = New-Object System.Drawing.Point(10, $yPos)
    $lblSectionUI.Size = New-Object System.Drawing.Size(400, 25)
    $lblSectionUI.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $lblSectionUI.ForeColor = [System.Drawing.Color]::FromArgb(27, 91, 74)
    $panelEdit.Controls.Add($lblSectionUI)
    
    $yPos += 35
    
    $lblPlaceholder = New-Object System.Windows.Forms.Label
    $lblPlaceholder.Text = "Placeholder :"
    $lblPlaceholder.Location = New-Object System.Drawing.Point(10, $yPos)
    $lblPlaceholder.Size = New-Object System.Drawing.Size(150, 25)
    $panelEdit.Controls.Add($lblPlaceholder)
    
    $txtPlaceholder = New-Object System.Windows.Forms.TextBox
    $txtPlaceholder.Location = New-Object System.Drawing.Point(170, $yPos)
    $txtPlaceholder.Size = New-Object System.Drawing.Size(380, 25)
    $txtPlaceholder.Text = ""
    $txtPlaceholder.Tag = "ex: Renseigner le point de collecte"
    $txtPlaceholder.Text = $txtPlaceholder.Tag
    $txtPlaceholder.ForeColor = [System.Drawing.Color]::Gray
    $panelEdit.Controls.Add($txtPlaceholder)
    
    $yPos += 40
    
    $chkEnabled = New-Object System.Windows.Forms.CheckBox
    $chkEnabled.Text = "✅ Règle active (apparaît dans l'écran principal)"
    $chkEnabled.Location = New-Object System.Drawing.Point(170, $yPos)
    $chkEnabled.Size = New-Object System.Drawing.Size(300, 25)
    $chkEnabled.Checked = $true
    $panelEdit.Controls.Add($chkEnabled)
    
    $yPos += 45
    
    $lblButtonColor = New-Object System.Windows.Forms.Label
    $lblButtonColor.Text = "Couleur du bouton :"
    $lblButtonColor.Location = New-Object System.Drawing.Point(10, $yPos)
    $lblButtonColor.Size = New-Object System.Drawing.Size(150, 30)
    $panelEdit.Controls.Add($lblButtonColor)
    
    $btnPickButtonColor = New-Object System.Windows.Forms.Button
    $btnPickButtonColor.Text = "🎨 Choisir"
    $btnPickButtonColor.Location = New-Object System.Drawing.Point(170, $yPos)
    $btnPickButtonColor.Size = New-Object System.Drawing.Size(80, 30)
    $btnPickButtonColor.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $btnPickButtonColor.FlatStyle = "Flat"
    $panelEdit.Controls.Add($btnPickButtonColor)
    
    $lblButtonColorPreview = New-Object System.Windows.Forms.Label
    $lblButtonColorPreview.Location = New-Object System.Drawing.Point(260, $yPos)
    $lblButtonColorPreview.Size = New-Object System.Drawing.Size(50, 30)
    $lblButtonColorPreview.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $lblButtonColorPreview.BorderStyle = "FixedSingle"
    $panelEdit.Controls.Add($lblButtonColorPreview)
    
    $yPos += 45
    
    $lblBorderColor = New-Object System.Windows.Forms.Label
    $lblBorderColor.Text = "Couleur bordure :"
    $lblBorderColor.Location = New-Object System.Drawing.Point(10, $yPos)
    $lblBorderColor.Size = New-Object System.Drawing.Size(150, 30)
    $panelEdit.Controls.Add($lblBorderColor)
    
    $btnPickBorderColor = New-Object System.Windows.Forms.Button
    $btnPickBorderColor.Text = "🎨 Choisir"
    $btnPickBorderColor.Location = New-Object System.Drawing.Point(170, $yPos)
    $btnPickBorderColor.Size = New-Object System.Drawing.Size(80, 30)
    $btnPickBorderColor.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $btnPickBorderColor.FlatStyle = "Flat"
    $panelEdit.Controls.Add($btnPickBorderColor)
    
    $lblBorderColorPreview = New-Object System.Windows.Forms.Label
    $lblBorderColorPreview.Location = New-Object System.Drawing.Point(260, $yPos)
    $lblBorderColorPreview.Size = New-Object System.Drawing.Size(50, 30)
    $lblBorderColorPreview.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $lblBorderColorPreview.BorderStyle = "FixedSingle"
    $panelEdit.Controls.Add($lblBorderColorPreview)
    
    $yPos += 55
    
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "💾 ENREGISTRER LA RÈGLE"
    $btnSave.Location = New-Object System.Drawing.Point(170, $yPos)
    $btnSave.Size = New-Object System.Drawing.Size(250, 45)
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(27, 91, 74)
    $btnSave.ForeColor = [System.Drawing.Color]::White
    $btnSave.Font = New-Object System.Drawing.Font("Arial", 11, [System.Drawing.FontStyle]::Bold)
    $btnSave.FlatStyle = "Flat"
    $panelEdit.Controls.Add($btnSave)
    
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "ANNULER"
    $btnCancel.Location = New-Object System.Drawing.Point(430, $yPos)
    $btnCancel.Size = New-Object System.Drawing.Size(120, 45)
    $btnCancel.BackColor = [System.Drawing.Color]::LightGray
    $btnCancel.FlatStyle = "Flat"
    $panelEdit.Controls.Add($btnCancel)
    
    $form.Controls.Add($splitContainer)
    
    # Gestion des placeholders
    function Add-Placeholder {
        param($textBox)
        $textBox.Add_GotFocus({
            if ($this.Text -eq $this.Tag) {
                $this.Text = ""
                $this.ForeColor = [System.Drawing.Color]::Black
            }
        })
        $textBox.Add_LostFocus({
            if ([string]::IsNullOrWhiteSpace($this.Text)) {
                $this.Text = $this.Tag
                $this.ForeColor = [System.Drawing.Color]::Gray
            }
        })
    }
    
    # Appliquer les placeholders
    Add-Placeholder $txtName
    Add-Placeholder $txtDesc
    Add-Placeholder $txtFormat
    Add-Placeholder $txtPlaceholder
    
    # Fonctions
    function Load-RulesList {
        $rulesListBox.Items.Clear()
        $allTemplates = Get-Templates
        foreach ($t in $allTemplates) {
            $status = if ($t.enabled) { "✓" } else { "✗" }
            $rulesListBox.Items.Add("$status $($t.name)")
            $rulesListBox.Items[$rulesListBox.Items.Count-1].Tag = $t.id
        }
    }
    
    function Clear-Form {
        $script:currentEditId = $null
        $txtName.Text = $txtName.Tag
        $txtName.ForeColor = [System.Drawing.Color]::Gray
        $txtDesc.Text = $txtDesc.Tag
        $txtDesc.ForeColor = [System.Drawing.Color]::Gray
        $txtFormat.Text = $txtFormat.Tag
        $txtFormat.ForeColor = [System.Drawing.Color]::Gray
        $txtPlaceholder.Text = $txtPlaceholder.Tag
        $txtPlaceholder.ForeColor = [System.Drawing.Color]::Gray
        $cbDateFormat.SelectedIndex = 0
        $chkEnabled.Checked = $true
        $script:selectedButtonColor = "#E26E2A"
        $script:selectedBorderColor = "#E26E2A"
        $btnPickButtonColor.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
        $lblButtonColorPreview.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
        $btnPickBorderColor.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
        $lblBorderColorPreview.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
        $btnDelete.Enabled = $false
    }
    
    function Load-TemplateToForm {
        param($Id)
        $template = Get-Templates | Where-Object { $_.id -eq $Id }
        if ($template) {
            $script:currentEditId = $template.id
            $txtName.Text = $template.name
            $txtName.ForeColor = [System.Drawing.Color]::Black
            $txtDesc.Text = $template.description
            $txtDesc.ForeColor = [System.Drawing.Color]::Black
            $txtFormat.Text = $template.format
            $txtFormat.ForeColor = [System.Drawing.Color]::Black
            $txtPlaceholder.Text = $template.placeholder
            $txtPlaceholder.ForeColor = [System.Drawing.Color]::Black
            $cbDateFormat.SelectedItem = $template.dateFormat
            $chkEnabled.Checked = $template.enabled
            $script:selectedButtonColor = $template.buttonColor
            $script:selectedBorderColor = $template.borderColor
            $btnPickButtonColor.BackColor = [System.Drawing.ColorTranslator]::FromHtml($template.buttonColor)
            $lblButtonColorPreview.BackColor = [System.Drawing.ColorTranslator]::FromHtml($template.buttonColor)
            $btnPickBorderColor.BackColor = [System.Drawing.ColorTranslator]::FromHtml($template.borderColor)
            $lblBorderColorPreview.BackColor = [System.Drawing.ColorTranslator]::FromHtml($template.borderColor)
            $btnDelete.Enabled = $true
        }
    }
    
    function Save-Template {
        # Vérifier si le champ nom a été modifié (pas le placeholder)
        $nameValue = if ($txtName.Text -eq $txtName.Tag) { "" } else { $txtName.Text }
        if ([string]::IsNullOrWhiteSpace($nameValue)) {
            [System.Windows.Forms.MessageBox]::Show("Le nom de la règle est obligatoire", "Erreur")
            return $false
        }
        
        $descValue = if ($txtDesc.Text -eq $txtDesc.Tag) { "" } else { $txtDesc.Text }
        $formatValue = if ($txtFormat.Text -eq $txtFormat.Tag) { "{date}-{text}" } else { $txtFormat.Text }
        $placeholderValue = if ($txtPlaceholder.Text -eq $txtPlaceholder.Tag) { "Renseigner le texte" } else { $txtPlaceholder.Text }
        
        $newTemplate = @{
            name = $txtName.Text
            description = $descValue
            format = $formatValue
            dateFormat = $cbDateFormat.SelectedItem
            timeFormat = ""
            includeTime = $false
            placeholder = $placeholderValue
            buttonColor = $script:selectedButtonColor
            borderColor = $script:selectedBorderColor
            enabled = $chkEnabled.Checked
        }
        
        if ($script:currentEditId) {
            Update-Template -Id $script:currentEditId -UpdatedTemplate $newTemplate
            [System.Windows.Forms.MessageBox]::Show("Règle modifiée avec succès", "Succès")
        } else {
            Add-Template -Template $newTemplate
            [System.Windows.Forms.MessageBox]::Show("Nouvelle règle ajoutée avec succès", "Succès")
        }
        
        Load-RulesList
        Clear-Form
        return $true
    }
    
    function Delete-Template {
        if ($rulesListBox.SelectedItem) {
            $result = [System.Windows.Forms.MessageBox]::Show("Supprimer cette règle ?", "Confirmation", [System.Windows.Forms.MessageBoxButtons]::YesNo)
            if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                $selectedId = $rulesListBox.SelectedItem.Tag
                Remove-Template -Id $selectedId
                [System.Windows.Forms.MessageBox]::Show("Règle supprimée", "Info")
                Load-RulesList
                Clear-Form
            }
        }
    }
    
    # Événements
    $btnAdd.Add_Click({
        Clear-Form
        $rulesListBox.SelectedIndex = -1
    })
    
    $btnDelete.Add_Click({
        Delete-Template
    })
    
    $btnSave.Add_Click({
        Save-Template
    })
    
    $btnCancel.Add_Click({
        Clear-Form
        $rulesListBox.SelectedIndex = -1
    })
    
    $rulesListBox.Add_SelectedIndexChanged({
        if ($rulesListBox.SelectedItem -and $rulesListBox.SelectedItem.Tag) {
            $selectedId = $rulesListBox.SelectedItem.Tag
            Load-TemplateToForm -Id $selectedId
        }
    })
    
    $btnPickButtonColor.Add_Click({
        if ($colorDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:selectedButtonColor = [System.Drawing.ColorTranslator]::ToHtml($colorDialog.Color)
            $btnPickButtonColor.BackColor = $colorDialog.Color
            $lblButtonColorPreview.BackColor = $colorDialog.Color
        }
    })
    
    $btnPickBorderColor.Add_Click({
        if ($colorDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:selectedBorderColor = [System.Drawing.ColorTranslator]::ToHtml($colorDialog.Color)
            $btnPickBorderColor.BackColor = $colorDialog.Color
            $lblBorderColorPreview.BackColor = $colorDialog.Color
        }
    })
    
    # Chargement initial
    Load-RulesList
    Clear-Form
    
    $form.ShowDialog() | Out-Null
}

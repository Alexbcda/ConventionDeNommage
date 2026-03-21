# TemplateEditor.ps1 - Interface de gestion des règles

function Show-TemplateEditor {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    . "$PSScriptRoot\TemplateManager.ps1"
    
    $templates = Get-Templates
    
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Gestion des règles de nommage"
    $form.Size = New-Object System.Drawing.Size(900, 650)
    $form.StartPosition = "CenterScreen"
    $form.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    
    # Onglets
    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Dock = "Fill"
    $tabControl.Padding = New-Object System.Drawing.Point(10, 5)
    
    # Onglet Liste des règles
    $tabList = New-Object System.Windows.Forms.TabPage
    $tabList.Text = "📋 Liste des règles"
    
    # Onglet Ajouter/Modifier
    $tabEdit = New-Object System.Windows.Forms.TabPage
    $tabEdit.Text = "✏️ Ajouter/Modifier une règle"
    $tabEdit.Enabled = $false
    
    $tabControl.TabPages.Add($tabList)
    $tabControl.TabPages.Add($tabEdit)
    
    # ========== ONGLET LISTE ==========
    $listBox = New-Object System.Windows.Forms.ListBox
    $listBox.Location = New-Object System.Drawing.Point(20, 20)
    $listBox.Size = New-Object System.Drawing.Size(400, 400)
    $listBox.Font = New-Object System.Drawing.Font("Arial", 10)
    
    # Remplir la liste
    foreach ($t in $templates) {
        $status = if ($t.enabled) { "✓" } else { "✗" }
        $listBox.Items.Add("$status $($t.name) - $($t.description)")
        $listBox.Items[$listBox.Items.Count-1].Tag = $t.id
    }
    
    $btnEdit = New-Object System.Windows.Forms.Button
    $btnEdit.Text = "Modifier"
    $btnEdit.Location = New-Object System.Drawing.Point(440, 20)
    $btnEdit.Size = New-Object System.Drawing.Size(100, 35)
    $btnEdit.BackColor = [System.Drawing.Color]::FromArgb(80, 171, 242)
    $btnEdit.ForeColor = [System.Drawing.Color]::White
    $btnEdit.FlatStyle = "Flat"
    
    $btnDelete = New-Object System.Windows.Forms.Button
    $btnDelete.Text = "Supprimer"
    $btnDelete.Location = New-Object System.Drawing.Point(440, 70)
    $btnDelete.Size = New-Object System.Drawing.Size(100, 35)
    $btnDelete.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $btnDelete.ForeColor = [System.Drawing.Color]::White
    $btnDelete.FlatStyle = "Flat"
    
    $btnEnableDisable = New-Object System.Windows.Forms.Button
    $btnEnableDisable.Text = "Activer/Désactiver"
    $btnEnableDisable.Location = New-Object System.Drawing.Point(440, 120)
    $btnEnableDisable.Size = New-Object System.Drawing.Size(100, 35)
    $btnEnableDisable.BackColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $btnEnableDisable.ForeColor = [System.Drawing.Color]::White
    $btnEnableDisable.FlatStyle = "Flat"
    
    $btnNew = New-Object System.Windows.Forms.Button
    $btnNew.Text = "➕ Nouvelle règle"
    $btnNew.Location = New-Object System.Drawing.Point(20, 440)
    $btnNew.Size = New-Object System.Drawing.Size(150, 40)
    $btnNew.BackColor = [System.Drawing.Color]::FromArgb(27, 91, 74)
    $btnNew.ForeColor = [System.Drawing.Color]::White
    $btnNew.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $btnNew.FlatStyle = "Flat"
    
    $tabList.Controls.Add($listBox)
    $tabList.Controls.Add($btnEdit)
    $tabList.Controls.Add($btnDelete)
    $tabList.Controls.Add($btnEnableDisable)
    $tabList.Controls.Add($btnNew)
    
    # ========== ONGLET ÉDITION ==========
    $panelEdit = New-Object System.Windows.Forms.Panel
    $panelEdit.Dock = "Fill"
    $panelEdit.Padding = New-Object System.Windows.Forms.Padding(20)
    
    $lblName = New-Object System.Windows.Forms.Label
    $lblName.Text = "Nom de la règle :"
    $lblName.Location = New-Object System.Drawing.Point(20, 20)
    $lblName.Size = New-Object System.Drawing.Size(150, 25)
    
    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Location = New-Object System.Drawing.Point(180, 20)
    $txtName.Size = New-Object System.Drawing.Size(300, 25)
    
    $lblDesc = New-Object System.Windows.Forms.Label
    $lblDesc.Text = "Description :"
    $lblDesc.Location = New-Object System.Drawing.Point(20, 60)
    $lblDesc.Size = New-Object System.Drawing.Size(150, 25)
    
    $txtDesc = New-Object System.Windows.Forms.TextBox
    $txtDesc.Location = New-Object System.Drawing.Point(180, 60)
    $txtDesc.Size = New-Object System.Drawing.Size(300, 25)
    
    $lblPlaceholder = New-Object System.Windows.Forms.Label
    $lblPlaceholder.Text = "Placeholder du champ :"
    $lblPlaceholder.Location = New-Object System.Drawing.Point(20, 100)
    $lblPlaceholder.Size = New-Object System.Drawing.Size(150, 25)
    
    $txtPlaceholder = New-Object System.Windows.Forms.TextBox
    $txtPlaceholder.Location = New-Object System.Drawing.Point(180, 100)
    $txtPlaceholder.Size = New-Object System.Drawing.Size(300, 25)
    $txtPlaceholder.Text = "Renseigner le texte"
    
    $lblFormat = New-Object System.Windows.Forms.Label
    $lblFormat.Text = "Format de renommage :"
    $lblFormat.Location = New-Object System.Drawing.Point(20, 140)
    $lblFormat.Size = New-Object System.Drawing.Size(150, 25)
    
    $txtFormat = New-Object System.Windows.Forms.TextBox
    $txtFormat.Location = New-Object System.Drawing.Point(180, 140)
    $txtFormat.Size = New-Object System.Drawing.Size(400, 25)
    $txtFormat.Text = "{date}-{text}"
    
    $lblFormatHint = New-Object System.Windows.Forms.Label
    $lblFormatHint.Text = "{text} = texte utilisateur | {date} = date"
    $lblFormatHint.Location = New-Object System.Drawing.Point(180, 170)
    $lblFormatHint.Size = New-Object System.Drawing.Size(400, 20)
    $lblFormatHint.Font = New-Object System.Drawing.Font("Arial", 8)
    $lblFormatHint.ForeColor = [System.Drawing.Color]::Gray
    
    $lblDateFormat = New-Object System.Windows.Forms.Label
    $lblDateFormat.Text = "Format de date :"
    $lblDateFormat.Location = New-Object System.Drawing.Point(20, 200)
    $lblDateFormat.Size = New-Object System.Drawing.Size(150, 25)
    
    $cbDateFormat = New-Object System.Windows.Forms.ComboBox
    $cbDateFormat.Location = New-Object System.Drawing.Point(180, 200)
    $cbDateFormat.Size = New-Object System.Drawing.Size(150, 25)
    $cbDateFormat.Items.AddRange(@("dd.MM.yy", "yyyyMMdd", "dd-MM-yyyy", "MM/dd/yyyy", "yyyy-MM-dd", "dd/MM/yyyy"))
    $cbDateFormat.SelectedIndex = 0
    
    $chkIncludeTime = New-Object System.Windows.Forms.CheckBox
    $chkIncludeTime.Text = "Inclure l'heure"
    $chkIncludeTime.Location = New-Object System.Drawing.Point(180, 240)
    $chkIncludeTime.Size = New-Object System.Drawing.Size(150, 25)
    
    $lblTimeFormat = New-Object System.Windows.Forms.Label
    $lblTimeFormat.Text = "Format heure :"
    $lblTimeFormat.Location = New-Object System.Drawing.Point(20, 270)
    $lblTimeFormat.Size = New-Object System.Drawing.Size(150, 25)
    $lblTimeFormat.Enabled = $false
    
    $cbTimeFormat = New-Object System.Windows.Forms.ComboBox
    $cbTimeFormat.Location = New-Object System.Drawing.Point(180, 270)
    $cbTimeFormat.Size = New-Object System.Drawing.Size(150, 25)
    $cbTimeFormat.Enabled = $false
    $cbTimeFormat.Items.AddRange(@("HHmm", "HH:mm", "hhmmtt"))
    
    $chkIncludeTime.Add_CheckedChanged({
        $lblTimeFormat.Enabled = $this.Checked
        $cbTimeFormat.Enabled = $this.Checked
    })
    
    $lblButtonColor = New-Object System.Windows.Forms.Label
    $lblButtonColor.Text = "Couleur du bouton :"
    $lblButtonColor.Location = New-Object System.Drawing.Point(20, 310)
    $lblButtonColor.Size = New-Object System.Drawing.Size(150, 25)
    
    $btnPickButtonColor = New-Object System.Windows.Forms.Button
    $btnPickButtonColor.Text = "Choisir"
    $btnPickButtonColor.Location = New-Object System.Drawing.Point(180, 310)
    $btnPickButtonColor.Size = New-Object System.Drawing.Size(80, 25)
    $btnPickButtonColor.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    
    $lblButtonColorPreview = New-Object System.Windows.Forms.Label
    $lblButtonColorPreview.Location = New-Object System.Drawing.Point(270, 310)
    $lblButtonColorPreview.Size = New-Object System.Drawing.Size(30, 25)
    $lblButtonColorPreview.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    
    $lblBorderColor = New-Object System.Windows.Forms.Label
    $lblBorderColor.Text = "Couleur bordure :"
    $lblBorderColor.Location = New-Object System.Drawing.Point(20, 350)
    $lblBorderColor.Size = New-Object System.Drawing.Size(150, 25)
    
    $btnPickBorderColor = New-Object System.Windows.Forms.Button
    $btnPickBorderColor.Text = "Choisir"
    $btnPickBorderColor.Location = New-Object System.Drawing.Point(180, 350)
    $btnPickBorderColor.Size = New-Object System.Drawing.Size(80, 25)
    $btnPickBorderColor.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    
    $lblBorderColorPreview = New-Object System.Windows.Forms.Label
    $lblBorderColorPreview.Location = New-Object System.Drawing.Point(270, 350)
    $lblBorderColorPreview.Size = New-Object System.Drawing.Size(30, 25)
    $lblBorderColorPreview.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    
    $btnSaveRule = New-Object System.Windows.Forms.Button
    $btnSaveRule.Text = "💾 Enregistrer la règle"
    $btnSaveRule.Location = New-Object System.Drawing.Point(180, 400)
    $btnSaveRule.Size = New-Object System.Drawing.Size(200, 40)
    $btnSaveRule.BackColor = [System.Drawing.Color]::FromArgb(27, 91, 74)
    $btnSaveRule.ForeColor = [System.Drawing.Color]::White
    $btnSaveRule.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $btnSaveRule.FlatStyle = "Flat"
    
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Annuler"
    $btnCancel.Location = New-Object System.Drawing.Point(400, 400)
    $btnCancel.Size = New-Object System.Drawing.Size(100, 40)
    $btnCancel.BackColor = [System.Drawing.Color]::LightGray
    $btnCancel.FlatStyle = "Flat"
    
    $panelEdit.Controls.Add($lblName)
    $panelEdit.Controls.Add($txtName)
    $panelEdit.Controls.Add($lblDesc)
    $panelEdit.Controls.Add($txtDesc)
    $panelEdit.Controls.Add($lblPlaceholder)
    $panelEdit.Controls.Add($txtPlaceholder)
    $panelEdit.Controls.Add($lblFormat)
    $panelEdit.Controls.Add($txtFormat)
    $panelEdit.Controls.Add($lblFormatHint)
    $panelEdit.Controls.Add($lblDateFormat)
    $panelEdit.Controls.Add($cbDateFormat)
    $panelEdit.Controls.Add($chkIncludeTime)
    $panelEdit.Controls.Add($lblTimeFormat)
    $panelEdit.Controls.Add($cbTimeFormat)
    $panelEdit.Controls.Add($lblButtonColor)
    $panelEdit.Controls.Add($btnPickButtonColor)
    $panelEdit.Controls.Add($lblButtonColorPreview)
    $panelEdit.Controls.Add($lblBorderColor)
    $panelEdit.Controls.Add($btnPickBorderColor)
    $panelEdit.Controls.Add($lblBorderColorPreview)
    $panelEdit.Controls.Add($btnSaveRule)
    $panelEdit.Controls.Add($btnCancel)
    
    $tabEdit.Controls.Add($panelEdit)
    
    # Variables pour l'édition
    $script:currentEditId = $null
    $script:selectedButtonColor = "#E26E2A"
    $script:selectedBorderColor = "#E26E2A"
    
    # Sélecteur de couleur
    $colorDialog = New-Object System.Windows.Forms.ColorDialog
    
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
    
    # Nouvelle règle
    $btnNew.Add_Click({
        $script:currentEditId = $null
        $txtName.Text = ""
        $txtDesc.Text = ""
        $txtPlaceholder.Text = "Renseigner le texte"
        $txtFormat.Text = "{date}-{text}"
        $cbDateFormat.SelectedIndex = 0
        $chkIncludeTime.Checked = $false
        $script:selectedButtonColor = "#E26E2A"
        $script:selectedBorderColor = "#E26E2A"
        $btnPickButtonColor.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
        $lblButtonColorPreview.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
        $btnPickBorderColor.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
        $lblBorderColorPreview.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
        $tabControl.SelectedTab = $tabEdit
        $tabEdit.Text = "✏️ Nouvelle règle"
    })
    
    # Modifier règle
    $btnEdit.Add_Click({
        if ($listBox.SelectedItem) {
            $selectedId = $listBox.SelectedItem.Tag
            $template = Get-Templates | Where-Object { $_.id -eq $selectedId }
            if ($template) {
                $script:currentEditId = $template.id
                $txtName.Text = $template.name
                $txtDesc.Text = $template.description
                $txtPlaceholder.Text = $template.placeholder
                $txtFormat.Text = $template.format
                $cbDateFormat.SelectedItem = $template.dateFormat
                $chkIncludeTime.Checked = $template.includeTime
                $script:selectedButtonColor = $template.buttonColor
                $script:selectedBorderColor = $template.borderColor
                $btnPickButtonColor.BackColor = [System.Drawing.ColorTranslator]::FromHtml($template.buttonColor)
                $lblButtonColorPreview.BackColor = [System.Drawing.ColorTranslator]::FromHtml($template.buttonColor)
                $btnPickBorderColor.BackColor = [System.Drawing.ColorTranslator]::FromHtml($template.borderColor)
                $lblBorderColorPreview.BackColor = [System.Drawing.ColorTranslator]::FromHtml($template.borderColor)
                $tabControl.SelectedTab = $tabEdit
                $tabEdit.Text = "✏️ Modifier : $($template.name)"
            }
        } else {
            [System.Windows.Forms.MessageBox]::Show("Veuillez sélectionner une règle", "Info")
        }
    })
    
    # Supprimer règle
    $btnDelete.Add_Click({
        if ($listBox.SelectedItem) {
            $result = [System.Windows.Forms.MessageBox]::Show("Supprimer cette règle ?", "Confirmation", "YesNo")
            if ($result -eq "Yes") {
                $selectedId = $listBox.SelectedItem.Tag
                Remove-Template -Id $selectedId
                [System.Windows.Forms.MessageBox]::Show("Règle supprimée", "Info")
                $form.Close()
                Show-TemplateEditor
            }
        }
    })
    
    # Activer/Désactiver
    $btnEnableDisable.Add_Click({
        if ($listBox.SelectedItem) {
            $selectedId = $listBox.SelectedItem.Tag
            $templates = Get-Templates
            $template = $templates | Where-Object { $_.id -eq $selectedId }
            if ($template) {
                $template.enabled = -not $template.enabled
                Save-Templates -Templates $templates
                $form.Close()
                Show-TemplateEditor
            }
        }
    })
    
    # Enregistrer règle
    $btnSaveRule.Add_Click({
        if ([string]::IsNullOrWhiteSpace($txtName.Text)) {
            [System.Windows.Forms.MessageBox]::Show("Le nom est obligatoire", "Erreur")
            return
        }
        
        $newTemplate = @{
            name = $txtName.Text
            description = $txtDesc.Text
            placeholder = $txtPlaceholder.Text
            format = $txtFormat.Text
            dateFormat = $cbDateFormat.SelectedItem
            timeFormat = if ($chkIncludeTime.Checked) { $cbTimeFormat.SelectedItem } else { "" }
            includeTime = $chkIncludeTime.Checked
            buttonColor = $script:selectedButtonColor
            borderColor = $script:selectedBorderColor
            enabled = $true
        }
        
        if ($script:currentEditId) {
            Update-Template -Id $script:currentEditId -UpdatedTemplate $newTemplate
        } else {
            Add-Template -Template $newTemplate
        }
        
        [System.Windows.Forms.MessageBox]::Show("Règle enregistrée", "Succès")
        $form.Close()
        Show-TemplateEditor
    })
    
    $btnCancel.Add_Click({
        $form.Close()
    })
    
    $form.Controls.Add($tabControl)
    $form.ShowDialog() | Out-Null
}

Export-ModuleMember -Function Show-TemplateEditor

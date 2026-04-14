# AgentForm.ps1 - Formulaire agent (envoie DateTime normal)

. "$PSScriptRoot\..\..\Database\Database.ps1"
. "$PSScriptRoot\..\..\Common\Styles.ps1"
. "$PSScriptRoot\..\..\Core\Logger.ps1"
. "$PSScriptRoot\..\..\Common\Validation.ps1"

function Show-AgentForm {
    param(
        [string]$Mode = "Ajouter",
        [pscustomobject]$Agent = $null,
        [System.Windows.Forms.IWin32Window]$Owner = $null
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$Mode un agent"
    $form.Size = New-Object System.Drawing.Size(650, 650)
    $form.StartPosition = "CenterParent"
    $form.BackColor = $script:CouleurGrisFond
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false

    $y = 20
    $left = 30
    $labelW = 150
    $fieldW = 350
    $errorColor = [System.Drawing.Color]::FromArgb(180, 0, 0)
    $errorFont = New-Object System.Drawing.Font("Arial", 8, [System.Drawing.FontStyle]::Regular)

    $script:__telUpdating = $false

    function Add-ErrorLabel {
        param([int]$x, [int]$yPos)
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.AutoSize = $false
        $lbl.Size = New-Object System.Drawing.Size($fieldW, 18)
        $lbl.Location = New-Object System.Drawing.Point($x, ($yPos + 24))
        $lbl.ForeColor = $errorColor
        $lbl.Font = $errorFont
        $lbl.Text = ""
        $form.Controls.Add($lbl)
        return $lbl
    }

    function Set-FieldError {
        param(
            [System.Windows.Forms.Label]$Label,
            [string]$Message
        )
        if (-not $Label) { return }
        $Label.Text = $Message
        $Label.Visible = -not [string]::IsNullOrWhiteSpace($Message)
    }

    function Get-TelError {
        param([string]$Text)
        $digits = Normalize-Telephone $Text
        if ([string]::IsNullOrWhiteSpace($digits)) { return "" } # tel optionnel
        if ($digits.Length -ne 10) { return "Téléphone invalide: 10 chiffres requis." }
        return ""
    }

    function Get-EmailError {
        param([string]$Text)
        if (Test-Email $Text) { return "" }
        return "Email invalide (ex: prenom.nom@domaine.fr)."
    }

    function Validate-All {
        param([switch]$FocusFirstInvalid)
        $hasError = $false

        # Nom / Prénom (strict)
        $nom = $txtNom.Text.Trim()
        $prenom = $txtPrenom.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($nom) -or $nom.Length -lt 2) {
            $hasError = $true
            if ($FocusFirstInvalid) { $txtNom.Focus() }
            return $false
        }
        if ([string]::IsNullOrWhiteSpace($prenom) -or $prenom.Length -lt 2) {
            $hasError = $true
            if ($FocusFirstInvalid) { $txtPrenom.Focus() }
            return $false
        }

        # Téléphone / Email
        Set-FieldError -Label $lblTelError -Message (Get-TelError $txtTel.Text)
        Set-FieldError -Label $lblEmailError -Message (Get-EmailError $txtEmail.Text)
        if ($lblTelError.Visible -or $lblEmailError.Visible) { $hasError = $true }

        if ($hasError -and $FocusFirstInvalid) {
            if ($lblTelError.Visible) { $txtTel.Focus(); return $false }
            if ($lblEmailError.Visible) { $txtEmail.Focus(); return $false }
        }

        return (-not $hasError)
    }

    function Add-Label($text) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $text
        $lbl.Location = New-Object System.Drawing.Point($left, $y)
        $lbl.Size = New-Object System.Drawing.Size($labelW, 25)
        $form.Controls.Add($lbl)
    }

    function Add-TextBox($value) {
        $txt = New-Object System.Windows.Forms.TextBox
        $txt.Location = New-Object System.Drawing.Point(($left + $labelW), $y)
        $txt.Size = New-Object System.Drawing.Size($fieldW, 25)
        $txt.Text = $value
        $form.Controls.Add($txt)
        return $txt
    }

    # NOM
    Add-Label "Nom * :"
    $txtNom = Add-TextBox $(if ($Agent -and $Agent.nom) { $Agent.nom } else { "" })
    $y += 40

    # PRENOM
    Add-Label "Prénom * :"
    $txtPrenom = Add-TextBox $(if ($Agent -and $Agent.prenom) { $Agent.prenom } else { "" })
    $y += 40

    # TEL
    Add-Label "Téléphone :"
    $txtTel = Add-TextBox $(if ($Agent -and $Agent.telephone) { $Agent.telephone } else { "" })
    $lblTelError = Add-ErrorLabel -x ($left + $labelW) -yPos $y
    $y += 40

    # EMAIL
    Add-Label "Email :"
    $txtEmail = Add-TextBox $(if ($Agent -and $Agent.email) { $Agent.email } else { "" })
    $lblEmailError = Add-ErrorLabel -x ($left + $labelW) -yPos $y
    $y += 40

    # CONTRAT
    Add-Label "Contrat :"
    $cmbContrat = New-Object System.Windows.Forms.ComboBox
    $cmbContrat.Location = New-Object System.Drawing.Point(($left + $labelW), $y)
    $cmbContrat.Size = New-Object System.Drawing.Size($fieldW, 25)
    $cmbContrat.DropDownStyle = "DropDownList"
    $cmbContrat.Items.AddRange(@("CDI","CDD","Interim","Apprentissage"))
    if ($Agent -and $Agent.type_contrat) {
        $cmbContrat.SelectedItem = $Agent.type_contrat
    } else {
        $cmbContrat.SelectedIndex = 0
    }
    $form.Controls.Add($cmbContrat)
    $y += 40

    # HEURES
    Add-Label "Heures/semaine :"
    $numHeures = New-Object System.Windows.Forms.NumericUpDown
    $numHeures.Location = New-Object System.Drawing.Point(($left + $labelW), $y)
    $numHeures.Minimum = 0
    $numHeures.Maximum = 60
    if ($Agent -and $Agent.base_heures_semaine) {
        $numHeures.Value = $Agent.base_heures_semaine
    } else {
        $numHeures.Value = 35
    }
    $form.Controls.Add($numHeures)
    $y += 40

    # POSTE
    Add-Label "Poste :"
    $cmbPoste = New-Object System.Windows.Forms.ComboBox
    $cmbPoste.Location = New-Object System.Drawing.Point(($left + $labelW), $y)
    $cmbPoste.Size = New-Object System.Drawing.Size($fieldW, 25)
    $cmbPoste.DropDownStyle = "DropDownList"
    $cmbPoste.Items.AddRange(@(Get-PostesListe))
    if ($Agent -and $Agent.poste) {
        $cmbPoste.SelectedItem = $Agent.poste
    } else {
        $cmbPoste.SelectedIndex = 0
    }
    $form.Controls.Add($cmbPoste)
    $y += 40

    # DATE ENTREE (objet DateTime normal)
    Add-Label "Date entrée :"
    $dtEntree = New-Object System.Windows.Forms.DateTimePicker
    $dtEntree.Location = New-Object System.Drawing.Point(($left + $labelW), $y)
    # Format explicite pour éviter les saisies ambiguës (ex: "01 avril 2026" peut être rejeté et revenir à aujourd'hui)
    $dtEntree.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
    $dtEntree.CustomFormat = "dd/MM/yyyy"
    if ($Agent -and $Agent.date_entree) {
        $dtEntree.Value = $Agent.date_entree
    }
    $form.Controls.Add($dtEntree)
    $y += 40

    # DATE SORTIE (objet DateTime normal)
    Add-Label "Date sortie :"
    $dtSortie = New-Object System.Windows.Forms.DateTimePicker
    $dtSortie.Location = New-Object System.Drawing.Point(($left + $labelW), $y)
    $dtSortie.Format = "Short"
    $dtSortie.ShowCheckBox = $true
    $dtSortie.Checked = $false
    if ($Agent -and $Agent.date_sortie) {
        $dtSortie.Checked = $true
        $dtSortie.Value = $Agent.date_sortie
    }
    $form.Controls.Add($dtSortie)
    $y += 60

    # BOUTONS
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "VALIDER"
    $btnOk.Location = New-Object System.Drawing.Point(($left + $labelW), $y)
    Set-BtnValiderStyle -BtnValider $btnOk
    $form.Controls.Add($btnOk)
    $form.AcceptButton = $btnOk

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "QUITTER"
    $btnCancel.Location = New-Object System.Drawing.Point(($left + $labelW + 120), $y)
    Set-BtnQuitterStyle -BtnQuitter $btnCancel
    $btnCancel.Add_Click({ $form.Close() })
    $form.Controls.Add($btnCancel)

    # Stocker le résultat sur le Form pour éviter les soucis de scope dans les handlers WinForms
    $form.Tag = $null

    $btnOk.Add_Click({
        try {
            $nom = $txtNom.Text.Trim()
            $prenom = $txtPrenom.Text.Trim()

            if ([string]::IsNullOrWhiteSpace($nom) -or $nom.Length -lt 2) {
                Write-Log "[AgentForm] Validation failed: nom" "WARN" @{ nom = $nom }
                [System.Windows.Forms.MessageBox]::Show("Nom obligatoire (min 2 caractères).", "Validation", "OK", "Warning") | Out-Null
                $txtNom.Focus()
                return
            }
            if ([string]::IsNullOrWhiteSpace($prenom) -or $prenom.Length -lt 2) {
                Write-Log "[AgentForm] Validation failed: prenom" "WARN" @{ prenom = $prenom }
                [System.Windows.Forms.MessageBox]::Show("Prénom obligatoire (min 2 caractères).", "Validation", "OK", "Warning") | Out-Null
                $txtPrenom.Focus()
                return
            }

            if (-not (Validate-All -FocusFirstInvalid)) {
                Write-Log "[AgentForm] Validation failed: tel/email" "WARN" @{
                    tel = $txtTel.Text; email = $txtEmail.Text
                }
                return
            }

            $telDigits = Normalize-Telephone $txtTel.Text
            if (-not [string]::IsNullOrWhiteSpace($telDigits) -and -not (Test-Telephone $telDigits)) {
                # Double safety (strict)
                Set-FieldError -Label $lblTelError -Message "Téléphone invalide: 10 chiffres requis."
                $txtTel.Focus()
                return
            }

            $result = [PSCustomObject]@{
                nom = $nom
                prenom = $prenom
                # Stockage nettoyé (digits-only) pour éviter les formats variables
                telephone = $telDigits
                email = (Normalize-Email $txtEmail.Text)
                type_contrat = $cmbContrat.SelectedItem.ToString()
                base_heures_semaine = [int]$numHeures.Value
                poste = $cmbPoste.SelectedItem.ToString()
                date_entree = $dtEntree.Value
                date_sortie = if ($dtSortie.Checked) { $dtSortie.Value } else { $null }
            }
            $form.Tag = $result
            Write-Log "[AgentForm] Submit OK" "INFO" $result
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
        } catch {
            Write-Log "[AgentForm] Submit failed (exception in click handler)" "ERROR" @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName }
            [System.Windows.Forms.MessageBox]::Show(
                ("Erreur dans le formulaire:`n`n{0}" -f $_.Exception.Message),
                "Erreur",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            return
        }
    })

    # ===== Validation temps réel =====

    $txtTel.Add_TextChanged({
        if ($script:__telUpdating) { return }
        try {
            $script:__telUpdating = $true

            $digits = Normalize-Telephone $txtTel.Text
            if ($digits.Length -gt 10) { $digits = $digits.Substring(0, 10) }

            $formatted = Format-Telephone $digits
            if ($txtTel.Text -ne $formatted) {
                $txtTel.Text = $formatted
                $txtTel.SelectionStart = $txtTel.Text.Length
            }

            Set-FieldError -Label $lblTelError -Message (Get-TelError $txtTel.Text)
        } finally {
            $script:__telUpdating = $false
        }
    })

    $txtTel.Add_Leave({
        # Normalise une dernière fois en sortie de champ
        $digits = Normalize-Telephone $txtTel.Text
        if ($digits.Length -gt 10) { $digits = $digits.Substring(0, 10) }
        $txtTel.Text = Format-Telephone $digits
        Set-FieldError -Label $lblTelError -Message (Get-TelError $txtTel.Text)
    })

    $txtEmail.Add_TextChanged({
        Set-FieldError -Label $lblEmailError -Message (Get-EmailError $txtEmail.Text)
    })

    if ($Owner) {
        $form.ShowDialog($Owner) | Out-Null
    } else {
        $form.ShowDialog() | Out-Null
    }
    
    if ($form.DialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        $out = $form.Tag
        Write-Log "[AgentForm] Returning result" "INFO" @{ mode = $Mode; ok = $true; isNull = ($null -eq $out) }
        return $out
    }

    Write-Log "[AgentForm] Returning null" "INFO" @{ mode = $Mode; ok = $false; dialogResult = $form.DialogResult.ToString() }
    return $null
}

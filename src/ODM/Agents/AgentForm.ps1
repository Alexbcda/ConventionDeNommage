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

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = "$Mode un agent"
    $form.Size = [System.Drawing.Size]::new(650, 650)
    $form.StartPosition = "CenterParent"
    $form.BackColor = $script:CouleurGrisFond
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false

    $y = 20
    $left = 30
    $labelW = 150
    $fieldW = 350
    $errorColor = [System.Drawing.Color]::FromArgb(180, 0, 0)
    $errorFont = [System.Drawing.Font]::new("Arial", 8, [System.Drawing.FontStyle]::Regular)

    $script:__telUpdating = $false
    $script:__telAllowFormatted = $false
    $script:__nomUpdating = $false
    $script:__prenomUpdating = $false

    function Add-ErrorLabel {
        param([int]$x, [int]$yPos)
        $lbl = [System.Windows.Forms.Label]::new()
        $lbl.AutoSize = $false
        $lbl.Size = [System.Drawing.Size]::new($fieldW, 18)
        $lbl.Location = [System.Drawing.Point]::new($x, ($yPos + 24))
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
        $formatted = Format-Telephone $Text
        if ($formatted -eq "") { return "" } # tel optionnel
        if ($null -eq $formatted) { return "Le numéro doit contenir 10 chiffres" }
        return ""
    }

    function Get-EmailError {
        param([string]$Text)
        if ([string]::IsNullOrWhiteSpace($Text)) { return "" } # optionnel
        if (Test-Email $Text) { return "" }
        return "Adresse email invalide"
    }

    function Get-SecurityError {
        param([string]$Text)
        if (Test-SecuriteInput $Text) { return "" }
        return "Caractères interdits détectés"
    }

    function Get-NomError {
        $sec = Get-SecurityError $txtNom.Text
        if ($sec) { return $sec }
        $n = $txtNom.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($n)) { return "Nom obligatoire" }
        if ($n.Length -lt 2) { return "Nom obligatoire (min 2 caractères)" }
        return ""
    }

    function Get-PrenomError {
        $sec = Get-SecurityError $txtPrenom.Text
        if ($sec) { return $sec }
        $p = $txtPrenom.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($p)) { return "Prénom obligatoire" }
        if ($p.Length -lt 2) { return "Prénom obligatoire (min 2 caractères)" }
        return ""
    }

    function Validate-All {
        param([switch]$FocusFirstInvalid)
        $hasError = $false

        # Nom / Prénom (strict)
        Set-FieldError -Label $lblNomError -Message (Get-NomError)
        Set-FieldError -Label $lblPrenomError -Message (Get-PrenomError)
        if ($lblNomError.Visible) {
            $hasError = $true
            if ($FocusFirstInvalid) { $txtNom.Focus() }
        }
        if ($lblPrenomError.Visible) {
            $hasError = $true
            if ($FocusFirstInvalid -and -not $lblNomError.Visible) { $txtPrenom.Focus() }
        }

        # Téléphone / Email
        Set-FieldError -Label $lblTelError -Message (Get-TelError $txtTel.Text)
        Set-FieldError -Label $lblEmailError -Message (Get-EmailError $txtEmail.Text)
        if ($lblNomError.Visible -or $lblPrenomError.Visible -or $lblTelError.Visible -or $lblEmailError.Visible) { $hasError = $true }

        if ($hasError -and $FocusFirstInvalid) {
            if ($lblNomError.Visible) { $txtNom.Focus(); return $false }
            if ($lblPrenomError.Visible) { $txtPrenom.Focus(); return $false }
            if ($lblTelError.Visible) { $txtTel.Focus(); return $false }
            if ($lblEmailError.Visible) { $txtEmail.Focus(); return $false }
        }

        return (-not $hasError)
    }

    function Update-SubmitState {
        # Désactiver VALIDER si une erreur existe (UX)
        $btnOk.Enabled = Validate-All
    }

    function Add-Label($text) {
        $lbl = [System.Windows.Forms.Label]::new()
        $lbl.Text = $text
        $lbl.Location = [System.Drawing.Point]::new($left, $y)
        $lbl.Size = [System.Drawing.Size]::new($labelW, 25)
        $form.Controls.Add($lbl)
    }

    function Add-TextBox($value) {
        $txt = [System.Windows.Forms.TextBox]::new()
        $txt.Location = [System.Drawing.Point]::new(($left + $labelW), $y)
        $txt.Size = [System.Drawing.Size]::new($fieldW, 25)
        $txt.Text = $value
        $form.Controls.Add($txt)
        return $txt
    }

    # NOM
    Add-Label "Nom * :"
    $txtNom = Add-TextBox $(if ($Agent -and $Agent.nom) { $Agent.nom } else { "" })
    $lblNomError = Add-ErrorLabel -x ($left + $labelW) -yPos $y
    $y += 40

    # PRENOM
    Add-Label "Prénom * :"
    $txtPrenom = Add-TextBox $(if ($Agent -and $Agent.prenom) { $Agent.prenom } else { "" })
    $lblPrenomError = Add-ErrorLabel -x ($left + $labelW) -yPos $y
    $y += 40

    # TEL
    Add-Label "Téléphone :"
    $txtTel = Add-TextBox $(if ($Agent -and $Agent.telephone) { $Agent.telephone } else { "" })
    $txtTel.MaxLength = 10
    $lblTelError = Add-ErrorLabel -x ($left + $labelW) -yPos $y
    $y += 40

    # EMAIL
    Add-Label "Email :"
    $txtEmail = Add-TextBox $(if ($Agent -and $Agent.email) { $Agent.email } else { "" })
    $lblEmailError = Add-ErrorLabel -x ($left + $labelW) -yPos $y
    $y += 40

    # CONTRAT
    Add-Label "Contrat :"
    $cmbContrat = [System.Windows.Forms.ComboBox]::new()
    $cmbContrat.Location = [System.Drawing.Point]::new(($left + $labelW), $y)
    $cmbContrat.Size = [System.Drawing.Size]::new($fieldW, 25)
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
    $numHeures = [System.Windows.Forms.NumericUpDown]::new()
    $numHeures.Location = [System.Drawing.Point]::new(($left + $labelW), $y)
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
    $cmbPoste = [System.Windows.Forms.ComboBox]::new()
    $cmbPoste.Location = [System.Drawing.Point]::new(($left + $labelW), $y)
    $cmbPoste.Size = [System.Drawing.Size]::new($fieldW, 25)
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
    $dtEntree = [System.Windows.Forms.DateTimePicker]::new()
    $dtEntree.Location = [System.Drawing.Point]::new(($left + $labelW), $y)
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
    $dtSortie = [System.Windows.Forms.DateTimePicker]::new()
    $dtSortie.Location = [System.Drawing.Point]::new(($left + $labelW), $y)
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
    $btnOk = [System.Windows.Forms.Button]::new()
    $btnOk.Text = "VALIDER"
    $btnOk.Location = [System.Drawing.Point]::new(($left + $labelW), $y)
    Set-BtnValiderStyle -BtnValider $btnOk
    $form.Controls.Add($btnOk)
    $form.AcceptButton = $btnOk

    $btnCancel = [System.Windows.Forms.Button]::new()
    $btnCancel.Text = "QUITTER"
    $btnCancel.Location = [System.Drawing.Point]::new(($left + $labelW + 120), $y)
    Set-BtnQuitterStyle -BtnQuitter $btnCancel
    $btnCancel.Add_Click({
        param($sender, $e)
        $frm = $sender.FindForm()
        if ($null -ne $frm) { $frm.Close() }
    })
    $form.Controls.Add($btnCancel)

    # Stocker le résultat sur le Form pour éviter les soucis de scope dans les handlers WinForms
    $form.Tag = $null

    $btnOk.Add_Click({
        try {
            # Sécurité: nettoyage UI supplémentaire
            $txtNom.Text = Sanitize-TextInput $txtNom.Text
            $txtPrenom.Text = Sanitize-TextInput $txtPrenom.Text
            $txtEmail.Text = Sanitize-TextInput $txtEmail.Text

            if (-not (Test-SecuriteInput $txtNom.Text) -or -not (Test-SecuriteInput $txtPrenom.Text) -or -not (Test-SecuriteInput $txtEmail.Text) -or -not (Test-SecuriteInput $txtTel.Text)) {
                Set-FieldError -Label $lblNomError -Message (Get-SecurityError $txtNom.Text)
                Set-FieldError -Label $lblPrenomError -Message (Get-SecurityError $txtPrenom.Text)
                Set-FieldError -Label $lblEmailError -Message (Get-SecurityError $txtEmail.Text)
                Set-FieldError -Label $lblTelError -Message (Get-SecurityError $txtTel.Text)
                return
            }

            # [AgentForm] Nom/Prenom normalization applied
            $nom = Format-Nom $txtNom.Text
            $prenom = Format-Prenom $txtPrenom.Text
            $txtNom.Text = $nom
            $txtPrenom.Text = $prenom

            if (-not (Validate-All -FocusFirstInvalid)) {
                Write-Log "[AgentForm] Validation failed: tel/email" "WARN" @{ fields = 'tel_email' }
                return
            }

            Write-Host "[AgentForm] Sécurité input OK"

            $telFormatted = Format-Telephone $txtTel.Text
            if ($null -eq $telFormatted) {
                Set-FieldError -Label $lblTelError -Message "Le numéro doit contenir 10 chiffres"
                $txtTel.Focus()
                return
            }
            if ($telFormatted -ne "") {
                $script:__telAllowFormatted = $true
                $txtTel.MaxLength = 14
                $txtTel.Text = $telFormatted
                Write-Host "[AgentForm] Validation téléphone OK"
                $script:__telAllowFormatted = $false
            }
            if (-not [string]::IsNullOrWhiteSpace($txtEmail.Text)) {
                Write-Host "[AgentForm] Validation email OK"
            }

            $result = [PSCustomObject]@{
                nom = $nom
                prenom = $prenom
                # Stockage au format standard "XX XX XX XX XX" (ou vide si optionnel)
                telephone = $telFormatted
                email = (Normalize-Email $txtEmail.Text)
                type_contrat = $cmbContrat.SelectedItem.ToString()
                base_heures_semaine = [int]$numHeures.Value
                poste = $cmbPoste.SelectedItem.ToString()
                date_entree = $dtEntree.Value
                date_sortie = if ($dtSortie.Checked) { $dtSortie.Value } else { $null }
            }
            $form.Tag = $result
            Write-Log "[AgentForm] Submit OK" "INFO" @{ ok = $true }
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

    $txtNom.Add_TextChanged({
        if ($script:__nomUpdating) { return }
        try {
            $script:__nomUpdating = $true
            $formatted = Format-Nom $txtNom.Text
            if ($txtNom.Text -ne $formatted) {
                $txtNom.Text = $formatted
                $txtNom.SelectionStart = $txtNom.Text.Length
            }
            Set-FieldError -Label $lblNomError -Message (Get-NomError)
            Update-SubmitState
        } finally {
            $script:__nomUpdating = $false
        }
    })

    $txtPrenom.Add_TextChanged({
        if ($script:__prenomUpdating) { return }
        try {
            $script:__prenomUpdating = $true
            $formatted = Format-Prenom $txtPrenom.Text
            if ($txtPrenom.Text -ne $formatted) {
                $txtPrenom.Text = $formatted
                $txtPrenom.SelectionStart = $txtPrenom.Text.Length
            }
            Set-FieldError -Label $lblPrenomError -Message (Get-PrenomError)
            Update-SubmitState
        } finally {
            $script:__prenomUpdating = $false
        }
    })

    # Téléphone: blocage de toute saisie non numérique (KeyPress) + validation temps réel
    $txtTel.Add_KeyPress({
        param($sender, $e)
        # Autoriser contrôles (Backspace, Ctrl+C/V, etc.)
        if ($e.Control) { return }
        if ($e.KeyChar -eq [char]8) { return } # backspace
        if (-not [char]::IsDigit($e.KeyChar)) {
            $e.Handled = $true
        }
    })

    $txtTel.Add_TextChanged({
        if ($script:__telAllowFormatted) { return }
        # Sécurité: s'assurer qu'il n'y a que des chiffres même si collage
        $digits = Normalize-Telephone $txtTel.Text
        if ($digits.Length -gt 10) { $digits = $digits.Substring(0,10) }
        if ($txtTel.Text -ne $digits) {
            $pos = $txtTel.SelectionStart
            $txtTel.Text = $digits
            $txtTel.SelectionStart = [Math]::Min($pos, $txtTel.Text.Length)
        }
        Set-FieldError -Label $lblTelError -Message (Get-TelError $txtTel.Text)
        Update-SubmitState
    })

    $txtEmail.Add_TextChanged({
        Set-FieldError -Label $lblEmailError -Message (Get-EmailError $txtEmail.Text)
        Update-SubmitState
    })

    # Etat initial du bouton
    Update-SubmitState

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

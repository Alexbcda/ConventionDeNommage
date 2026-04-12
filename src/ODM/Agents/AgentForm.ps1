# AgentForm.ps1 - Formulaire d'ajout/modification d'agent

. "$PSScriptRoot\..\..\Database\Database.ps1"
. "$PSScriptRoot\..\..\Common\Styles.ps1"

# Fonction pour nettoyer le téléphone (enlever espaces et caractères)
function Clean-Telephone {
    param($Telephone)
    if ([string]::IsNullOrWhiteSpace($Telephone)) { return "" }
    # Garde uniquement les chiffres et le +
    return ($Telephone -replace '[^0-9+]', '')
}

# Fonction pour valider le téléphone français (tous les indicatifs 01-09)
function Test-TelephoneFrancais {
    param($Telephone)
    
    if ([string]::IsNullOrWhiteSpace($Telephone)) { return $true } # Champ optionnel
    
    $clean = Clean-Telephone -Telephone $Telephone
    
    # Format 10 chiffres commençant par 0 (01,02,03,04,05,06,07,08,09)
    if ($clean -match '^0[1-9][0-9]{8}$') {
        return $true
    }
    
    # Format +33 suivi de 9 chiffres (commençant par 1-9)
    if ($clean -match '^\+33[1-9][0-9]{8}$') {
        return $true
    }
    
    return $false
}

# Fonction pour formater le téléphone pour stockage
function Format-TelephoneStockage {
    param($Telephone)
    
    if ([string]::IsNullOrWhiteSpace($Telephone)) { return $null }
    
    $clean = Clean-Telephone -Telephone $Telephone
    
    # Si format +33..., garder tel quel
    if ($clean -match '^\+33[1-9][0-9]{8}$') {
        return $clean
    }
    
    # Si format 0XXXXXXXXX, formater en XX XX XX XX XX
    if ($clean -match '^0([1-9])([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})$') {
        return "0$($Matches[1]) $($Matches[2]) $($Matches[3]) $($Matches[4]) $($Matches[5])"
    }
    
    return $clean
}

# Fonction pour formater l'affichage dans le champ texte
function Format-TelephoneAffichage {
    param($Telephone)
    
    if ([string]::IsNullOrWhiteSpace($Telephone)) { return "" }
    
    # Si c'est un format +33...
    if ($Telephone -match '^\+33[1-9][0-9]{8}$') {
        # Formater pour affichage: +33 X XX XX XX XX
        if ($Telephone -match '^\+33([1-9])([0-9]{2})([0-9]{2})([0-9]{2})([0-9]{2})$') {
            return "+33 $($Matches[1]) $($Matches[2]) $($Matches[3]) $($Matches[4]) $($Matches[5])"
        }
        return $Telephone
    }
    
    # Si c'est un format 0X XX XX XX XX
    if ($Telephone -match '^0[1-9] [0-9]{2} [0-9]{2} [0-9]{2} [0-9]{2}$') {
        return $Telephone
    }
    
    # Si c'est un format 0XXXXXXXXX compact
    if ($Telephone -match '^0[1-9][0-9]{8}$') {
        $num = $Telephone
        return "$($num.Substring(0,2)) $($num.Substring(2,2)) $($num.Substring(4,2)) $($num.Substring(6,2)) $($num.Substring(8,2))"
    }
    
    return $Telephone
}

function Show-AgentForm {
    param(
        [string]$Mode = "Ajouter",
        [hashtable]$Agent = $null
    )

    Write-Host "[FORM] ========== FORMULAIRE AGENT ==========" -ForegroundColor Magenta
    Write-Host "[FORM] Mode: $Mode" -ForegroundColor Magenta

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$Mode un agent"
    $form.Size = New-Object System.Drawing.Size(650, 650)
    $form.StartPosition = "CenterParent"
    $form.BackColor = $CouleurGrisFond
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $yPos = 20
    $labelWidth = 150
    $fieldWidth = 350
    $leftMargin = 30
    $fieldLeft = $leftMargin + $labelWidth

    # ============================================
    # NOM
    # ============================================
    $lblNom = New-Object System.Windows.Forms.Label
    $lblNom.Text = "Nom * :"
    $lblNom.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblNom.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblNom)

    $txtNom = New-Object System.Windows.Forms.TextBox
    $txtNom.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $txtNom.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    $txtNom.MaxLength = 50
    if ($Agent) { $txtNom.Text = $Agent.nom }
    $form.Controls.Add($txtNom)
    
    $lblNomError = New-Object System.Windows.Forms.Label
    $lblNomError.Text = ""
    $lblNomError.ForeColor = $CouleurOrange
    $lblNomError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblNomError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblNomError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblNomError)
    $yPos += 55

    # ============================================
    # PRÉNOM
    # ============================================
    $lblPrenom = New-Object System.Windows.Forms.Label
    $lblPrenom.Text = "Prénom * :"
    $lblPrenom.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblPrenom.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblPrenom)

    $txtPrenom = New-Object System.Windows.Forms.TextBox
    $txtPrenom.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $txtPrenom.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    $txtPrenom.MaxLength = 50
    if ($Agent) { $txtPrenom.Text = $Agent.prenom }
    $form.Controls.Add($txtPrenom)
    
    $lblPrenomError = New-Object System.Windows.Forms.Label
    $lblPrenomError.Text = ""
    $lblPrenomError.ForeColor = $CouleurOrange
    $lblPrenomError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblPrenomError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblPrenomError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblPrenomError)
    $yPos += 55

    # ============================================
    # TÉLÉPHONE
    # ============================================
    $lblTel = New-Object System.Windows.Forms.Label
    $lblTel.Text = "Téléphone :"
    $lblTel.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblTel.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblTel)

    $txtTel = New-Object System.Windows.Forms.TextBox
    $txtTel.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $txtTel.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    $txtTel.MaxLength = 25
    if ($Agent -and $Agent.telephone) { 
        $txtTel.Text = Format-TelephoneAffichage -Telephone $Agent.telephone
    }
    $form.Controls.Add($txtTel)
    
    $lblTelError = New-Object System.Windows.Forms.Label
    $lblTelError.Text = "Ex: 0123456789 ou 01 23 45 67 89 ou +33 1 23 45 67 89"
    $lblTelError.ForeColor = [System.Drawing.Color]::Gray
    $lblTelError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblTelError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblTelError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblTelError)
    $yPos += 55

    # ============================================
    # EMAIL
    # ============================================
    $lblEmail = New-Object System.Windows.Forms.Label
    $lblEmail.Text = "Email :"
    $lblEmail.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblEmail.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblEmail)

    $txtEmail = New-Object System.Windows.Forms.TextBox
    $txtEmail.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $txtEmail.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    $txtEmail.MaxLength = 100
    if ($Agent) { $txtEmail.Text = $Agent.email }
    $form.Controls.Add($txtEmail)
    
    $lblEmailError = New-Object System.Windows.Forms.Label
    $lblEmailError.Text = ""
    $lblEmailError.ForeColor = $CouleurOrange
    $lblEmailError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblEmailError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblEmailError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblEmailError)
    $yPos += 55

    # ============================================
    # DATE D'ENTRÉE
    # ============================================
    $lblDateEntree = New-Object System.Windows.Forms.Label
    $lblDateEntree.Text = "Date d'entrée * :"
    $lblDateEntree.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblDateEntree.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblDateEntree)

    $dtpDateEntree = New-Object System.Windows.Forms.DateTimePicker
    $dtpDateEntree.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $dtpDateEntree.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    $dtpDateEntree.Format = "Short"
    if ($Agent -and $Agent.date_entree) { 
        $dtpDateEntree.Value = [DateTime]::ParseExact($Agent.date_entree, "yyyy-MM-dd", $null)
    } else {
        $dtpDateEntree.Value = (Get-Date)
    }
    $form.Controls.Add($dtpDateEntree)
    $yPos += 55

    # ============================================
    # TYPE DE CONTRAT
    # ============================================
    $lblContrat = New-Object System.Windows.Forms.Label
    $lblContrat.Text = "Type de contrat * :"
    $lblContrat.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblContrat.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblContrat)

    $cmbContrat = New-Object System.Windows.Forms.ComboBox
    $cmbContrat.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $cmbContrat.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    $cmbContrat.DropDownStyle = "DropDownList"
    $cmbContrat.Items.AddRange(@("CDI", "CDD", "Interim", "Apprentissage"))
    if ($Agent -and $Agent.type_contrat) {
        $cmbContrat.SelectedItem = $Agent.type_contrat
    } else {
        $cmbContrat.SelectedIndex = 0
    }
    $form.Controls.Add($cmbContrat)
    $yPos += 55

    # ============================================
    # BASE HEURES SEMAINE
    # ============================================
    $lblHeures = New-Object System.Windows.Forms.Label
    $lblHeures.Text = "Base heures/semaine :"
    $lblHeures.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblHeures.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblHeures)

    $numHeures = New-Object System.Windows.Forms.NumericUpDown
    $numHeures.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $numHeures.Size = New-Object System.Drawing.Size(100, 25)
    $numHeures.Minimum = 0
    $numHeures.Maximum = 48
    $numHeures.Value = if ($Agent -and $Agent.base_heures_semaine) { $Agent.base_heures_semaine } else { 35 }
    $form.Controls.Add($numHeures)
    $yPos += 55

    # ============================================
    # POSTE
    # ============================================
    $lblPoste = New-Object System.Windows.Forms.Label
    $lblPoste.Text = "Poste * :"
    $lblPoste.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblPoste.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblPoste)

    $cmbPoste = New-Object System.Windows.Forms.ComboBox
    $cmbPoste.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $cmbPoste.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    $cmbPoste.DropDownStyle = "DropDownList"
    $cmbPoste.Items.AddRange(@(Get-PostesListe))
    if ($Agent -and $Agent.poste) {
        $cmbPoste.SelectedItem = $Agent.poste
    } else {
        $cmbPoste.SelectedIndex = 0
    }
    $form.Controls.Add($cmbPoste)
    $yPos += 55

    # ============================================
    # VÉHICULE ATTITRÉ
    # ============================================
    $lblVehicule = New-Object System.Windows.Forms.Label
    $lblVehicule.Text = "Véhicule attitré :"
    $lblVehicule.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblVehicule.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblVehicule)

    $cmbVehicule = New-Object System.Windows.Forms.ComboBox
    $cmbVehicule.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $cmbVehicule.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    $cmbVehicule.DropDownStyle = "DropDownList"
    $form.Controls.Add($cmbVehicule)
    $yPos += 85

    # ============================================
    # BOUTONS
    # ============================================
    $BtnValider = New-Object System.Windows.Forms.Button
    Set-BtnValiderStyle -BtnValider $BtnValider
    $BtnValider.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $form.Controls.Add($BtnValider)

    $BtnQuitter = New-Object System.Windows.Forms.Button
    Set-BtnQuitterStyle -BtnQuitter $BtnQuitter
    $BtnQuitter.Location = New-Object System.Drawing.Point(($fieldLeft + 120), $yPos)
    $BtnQuitter.Add_Click({ $form.Close() })
    $form.Controls.Add($BtnQuitter)

    # ============================================
    # REMPLIR LA LISTE DES VÉHICULES
    # ============================================
    function Load-VehiculesList {
        $tousVehicules = Get-Vehicules
        $cmbVehicule.Items.Clear()
        $cmbVehicule.Items.Add("(Aucun véhicule)") | Out-Null
        
        $script:vehiculeIds = @()
        $script:vehiculeIds += $null
        
        foreach ($v in $tousVehicules) {
            $displayText = "$($v.numero_parc) - $($v.immatriculation) - $($v.marque) $($v.modele)"
            $cmbVehicule.Items.Add($displayText) | Out-Null
            $script:vehiculeIds += $v.id
        }
        $cmbVehicule.SelectedIndex = 0
        
        if ($Agent -and $Agent.vehicule_id) {
            $index = [array]::IndexOf($script:vehiculeIds, $Agent.vehicule_id)
            if ($index -ge 0) { $cmbVehicule.SelectedIndex = $index }
        }
    }
    Load-VehiculesList

    # ============================================
    # VALIDATION EN TEMPS RÉEL
    # ============================================
    
    $txtTel.Add_TextChanged({
        $val = $txtTel.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblTelError.Text = "Optionnel - Ex: 0123456789 ou 01 23 45 67 89 ou +33 1 23 45 67 89"
            $lblTelError.ForeColor = [System.Drawing.Color]::Gray
        } elseif (Test-TelephoneFrancais -Telephone $val) {
            $lblTelError.Text = "✓ Numéro valide"
            $lblTelError.ForeColor = [System.Drawing.Color]::Green
        } else {
            $lblTelError.Text = "✗ Numéro invalide. 10 chiffres commençant par 0 ou +33"
            $lblTelError.ForeColor = $CouleurOrange
        }
    })

    $txtEmail.Add_TextChanged({
        $val = $txtEmail.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblEmailError.Text = ""
        } elseif ($val -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
            $lblEmailError.Text = "Format email invalide"
        } else {
            $lblEmailError.Text = "✓"
            $lblEmailError.ForeColor = [System.Drawing.Color]::Green
        }
    })

    # ============================================
    # VALIDATION FINALE
    # ============================================
    $BtnValider.Add_Click({
        $valid = $true
        
        # Nom
        $nom = $txtNom.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($nom)) {
            $lblNomError.Text = "Champ obligatoire"
            $valid = $false
        } elseif ($nom.Length -lt 2) {
            $lblNomError.Text = "Minimum 2 caractères"
            $valid = $false
        } else {
            $lblNomError.Text = ""
        }
        
        # Prénom
        $prenom = $txtPrenom.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($prenom)) {
            $lblPrenomError.Text = "Champ obligatoire"
            $valid = $false
        } elseif ($prenom.Length -lt 2) {
            $lblPrenomError.Text = "Minimum 2 caractères"
            $valid = $false
        } else {
            $lblPrenomError.Text = ""
        }
        
        # Téléphone
        $telephoneRaw = $txtTel.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($telephoneRaw)) {
            if (-not (Test-TelephoneFrancais -Telephone $telephoneRaw)) {
                $lblTelError.Text = "Numéro invalide"
                $valid = $false
            }
        }
        
        # Email
        $emailRaw = $txtEmail.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($emailRaw)) {
            if ($emailRaw -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
                $lblEmailError.Text = "Email invalide"
                $valid = $false
            }
        }
        
        if (-not $valid) {
            return
        }
        
        # Stocker le téléphone
        $telephoneFinal = $null
        if (-not [string]::IsNullOrWhiteSpace($telephoneRaw)) {
            $telephoneFinal = Format-TelephoneStockage -Telephone $telephoneRaw
        }
        
        $vehiculeId = $script:vehiculeIds[$cmbVehicule.SelectedIndex]
        if ($vehiculeId -eq $null) { $vehiculeId = 0 }
        
        $emailFinal = $txtEmail.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($emailFinal)) { $emailFinal = $null }
        
        $donnees = @{
            nom = $txtNom.Text.Trim()
            prenom = $txtPrenom.Text.Trim()
            telephone = $telephoneFinal
            email = $emailFinal
            date_entree = $dtpDateEntree.Value.ToString("yyyy-MM-dd")
            type_contrat = $cmbContrat.SelectedItem.ToString()
            base_heures_semaine = [int]$numHeures.Value
            poste = $cmbPoste.SelectedItem.ToString()
            vehicule_id = $vehiculeId
        }
        
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })

    $result = $form.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $donnees
    }
    return $null
}

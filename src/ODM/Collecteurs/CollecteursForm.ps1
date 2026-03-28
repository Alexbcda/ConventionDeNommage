# CollecteursForm.ps1 - Version avec coche verte à droite et alertes orange

. "$PSScriptRoot\..\..\Core\DataManager.ps1"

function Show-CollecteurForm {
    param(
        [string]$Mode = "Ajouter",
        [hashtable]$Collecteur = $null
    )

    Write-Host "[FORM] ========== FORMULAIRE OUVERT ==========" -ForegroundColor Magenta
    Write-Host "[FORM] Mode: $Mode" -ForegroundColor Magenta

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Couleur orange du bouton certificat
    $orange = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $orangeClair = [System.Drawing.Color]::FromArgb(255, 140, 60)
    $vert = [System.Drawing.Color]::FromArgb(27, 91, 74)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$Mode un collecteur"
    $form.Size = New-Object System.Drawing.Size(600, 620)
    $form.StartPosition = "CenterParent"
    $form.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $yPos = 20
    $labelWidth = 120
    $fieldWidth = 300
    $checkWidth = 30
    $leftMargin = 30
    $fieldLeft = $leftMargin + $labelWidth

    # ========== PRÉNOM ==========
    $lblPrenom = New-Object System.Windows.Forms.Label
    $lblPrenom.Text = "Prénom * :"
    $lblPrenom.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblPrenom.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblPrenom)

    $txtPrenom = New-Object System.Windows.Forms.TextBox
    $txtPrenom.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $txtPrenom.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    if ($Collecteur) { $txtPrenom.Text = $Collecteur.prenom }
    $form.Controls.Add($txtPrenom)
    
    # COCHE VERTE À DROITE
    $lblPrenomCheck = New-Object System.Windows.Forms.Label
    $lblPrenomCheck.Text = ""
    $lblPrenomCheck.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblPrenomCheck.Location = New-Object System.Drawing.Point(($fieldLeft + $fieldWidth + 5), $yPos)
    $lblPrenomCheck.Size = New-Object System.Drawing.Size($checkWidth, 25)
    $form.Controls.Add($lblPrenomCheck)
    
    # ALERTE ORANGE SOUS LE CHAMP
    $lblPrenomError = New-Object System.Windows.Forms.Label
    $lblPrenomError.Text = ""
    $lblPrenomError.ForeColor = $orange
    $lblPrenomError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblPrenomError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblPrenomError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblPrenomError)
    $yPos += 55

    # ========== NOM ==========
    $lblNom = New-Object System.Windows.Forms.Label
    $lblNom.Text = "Nom * :"
    $lblNom.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblNom.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblNom)

    $txtNom = New-Object System.Windows.Forms.TextBox
    $txtNom.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $txtNom.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    if ($Collecteur) { $txtNom.Text = $Collecteur.nom }
    $form.Controls.Add($txtNom)
    
    # COCHE VERTE À DROITE
    $lblNomCheck = New-Object System.Windows.Forms.Label
    $lblNomCheck.Text = ""
    $lblNomCheck.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblNomCheck.Location = New-Object System.Drawing.Point(($fieldLeft + $fieldWidth + 5), $yPos)
    $lblNomCheck.Size = New-Object System.Drawing.Size($checkWidth, 25)
    $form.Controls.Add($lblNomCheck)
    
    # ALERTE ORANGE SOUS LE CHAMP
    $lblNomError = New-Object System.Windows.Forms.Label
    $lblNomError.Text = ""
    $lblNomError.ForeColor = $orange
    $lblNomError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblNomError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblNomError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblNomError)
    $yPos += 55

    # ========== TÉLÉPHONE ==========
    $lblTelephone = New-Object System.Windows.Forms.Label
    $lblTelephone.Text = "Téléphone :"
    $lblTelephone.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblTelephone.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblTelephone)

    $txtTelephone = New-Object System.Windows.Forms.TextBox
    $txtTelephone.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $txtTelephone.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    if ($Collecteur) { $txtTelephone.Text = $Collecteur.telephone }
    $form.Controls.Add($txtTelephone)
    
    $txtTelephone.Add_KeyPress({
        $keyChar = $_.KeyChar
        if ($keyChar -match '[0-9]' -or $keyChar -eq '+' -or $keyChar -eq "`b") {
            $_.Handled = $false
        } else {
            $_.Handled = $true
        }
    })
    
    # COCHE VERTE À DROITE (optionnel)
    $lblTelephoneCheck = New-Object System.Windows.Forms.Label
    $lblTelephoneCheck.Text = ""
    $lblTelephoneCheck.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblTelephoneCheck.Location = New-Object System.Drawing.Point(($fieldLeft + $fieldWidth + 5), $yPos)
    $lblTelephoneCheck.Size = New-Object System.Drawing.Size($checkWidth, 25)
    $form.Controls.Add($lblTelephoneCheck)
    
    # ALERTE ORANGE SOUS LE CHAMP
    $lblTelephoneError = New-Object System.Windows.Forms.Label
    $lblTelephoneError.Text = "⭕ Optionnel - chiffres uniquement"
    $lblTelephoneError.ForeColor = $orangeClair
    $lblTelephoneError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblTelephoneError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblTelephoneError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblTelephoneError)
    $yPos += 55

    # ========== EMAIL ==========
    $lblEmail = New-Object System.Windows.Forms.Label
    $lblEmail.Text = "Email :"
    $lblEmail.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblEmail.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblEmail)

    $txtEmail = New-Object System.Windows.Forms.TextBox
    $txtEmail.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $txtEmail.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    if ($Collecteur) { $txtEmail.Text = $Collecteur.email }
    $form.Controls.Add($txtEmail)
    
    # COCHE VERTE À DROITE (optionnel)
    $lblEmailCheck = New-Object System.Windows.Forms.Label
    $lblEmailCheck.Text = ""
    $lblEmailCheck.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblEmailCheck.Location = New-Object System.Drawing.Point(($fieldLeft + $fieldWidth + 5), $yPos)
    $lblEmailCheck.Size = New-Object System.Drawing.Size($checkWidth, 25)
    $form.Controls.Add($lblEmailCheck)
    
    # ALERTE ORANGE SOUS LE CHAMP
    $lblEmailError = New-Object System.Windows.Forms.Label
    $lblEmailError.Text = "⭕ Optionnel - ex: nom@domaine.com"
    $lblEmailError.ForeColor = $orangeClair
    $lblEmailError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblEmailError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblEmailError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblEmailError)
    $yPos += 55

    # ========== VÉHICULE ==========
    $lblVehicule = New-Object System.Windows.Forms.Label
    $lblVehicule.Text = "Véhicule :"
    $lblVehicule.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblVehicule.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblVehicule)

    $cbVehicule = New-Object System.Windows.Forms.ComboBox
    $cbVehicule.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $cbVehicule.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    $cbVehicule.DropDownStyle = "DropDownList"
    $cbVehicule.Items.Add("-- Aucun --")
    
    $vehicules = Get-Vehicules
    foreach ($v in $vehicules) {
        $cbVehicule.Items.Add("$($v.immatriculation) - $($v.marque) $($v.modele)")
    }
    
    if ($Collecteur -and $Collecteur.vehiculeDefaut) {
        for ($i = 0; $i -lt $cbVehicule.Items.Count; $i++) {
            if ($cbVehicule.Items[$i] -like "$($Collecteur.vehiculeDefaut)*") {
                $cbVehicule.SelectedIndex = $i
                break
            }
        }
    } else {
        $cbVehicule.SelectedIndex = 0
    }
    $form.Controls.Add($cbVehicule)
    
    # COCHE VERTE À DROITE (optionnel)
    $lblVehiculeCheck = New-Object System.Windows.Forms.Label
    $lblVehiculeCheck.Text = ""
    $lblVehiculeCheck.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblVehiculeCheck.Location = New-Object System.Drawing.Point(($fieldLeft + $fieldWidth + 5), $yPos)
    $lblVehiculeCheck.Size = New-Object System.Drawing.Size($checkWidth, 25)
    $form.Controls.Add($lblVehiculeCheck)
    
    # ALERTE ORANGE SOUS LE CHAMP
    $lblVehiculeInfo = New-Object System.Windows.Forms.Label
    $lblVehiculeInfo.Text = ""
    $lblVehiculeInfo.ForeColor = $orange
    $lblVehiculeInfo.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblVehiculeInfo.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblVehiculeInfo.Size = New-Object System.Drawing.Size($fieldWidth, 20)
    $form.Controls.Add($lblVehiculeInfo)
    $yPos += 55

    # ========== BOUTONS ==========
        $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text = "VALIDER"
    $btnOK.Size = New-Object System.Drawing.Size(100, 40)
    $btnOK.Location = New-Object System.Drawing.Point(($fieldLeft), $yPos)
    $btnOK.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnOK.FlatStyle = "Flat"
    $btnOK.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $btnOK.FlatAppearance.BorderSize = 2
    $btnOK.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnOK.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnOK.Cursor = [System.Windows.Forms.Cursors]::Hand
    
    $btnOK.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(229, 90, 42)
        $this.BackColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $btnOK.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    $form.Controls.Add($btnOK)

            $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "QUITTER"
    $btnCancel.Size = New-Object System.Drawing.Size(100, 40)
    $btnCancel.Location = New-Object System.Drawing.Point(($fieldLeft + 120), $yPos)
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnCancel.FlatStyle = "Flat"
    $btnCancel.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnCancel.FlatAppearance.BorderSize = 2
    $btnCancel.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnCancel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnCancel.Cursor = [System.Windows.Forms.Cursors]::Hand
    
    $btnCancel.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
        $this.BackColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $btnCancel.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    $btnCancel.Add_Click({ 
        Write-Host "[FORM] Annulation" -ForegroundColor Yellow
        $form.Close() 
    })
    $form.Controls.Add($btnCancel)

    # ========== FONCTIONS ==========
    function Test-Email {
        param([string]$Email)
        if ([string]::IsNullOrWhiteSpace($Email)) { return $true }
        $Email = $Email.Trim()
        $pattern = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
        return $Email -match $pattern
    }

    function Test-Telephone {
        param([string]$Phone)
        if ([string]::IsNullOrWhiteSpace($Phone)) { return $true }
        $clean = $Phone -replace '[^0-9+]', ''
        return $clean -match '^(\+[0-9]{11,12}|0[0-9]{9})$'
    }

    function Format-Telephone {
        param([string]$Raw)
        if ([string]::IsNullOrWhiteSpace($Raw)) { return "" }
        
        $hasPlus = $false
        $digits = ""
        foreach ($c in $Raw.ToCharArray()) {
            if ($c -eq '+' -and -not $hasPlus) {
                $hasPlus = $true
                $digits += $c
            } elseif ($c -match '[0-9]') {
                $digits += $c
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($digits)) { return "" }
        
        if ($hasPlus) {
            $numbers = $digits -replace '^\+', ''
            $formatted = "+"
            $i = 0
            foreach ($d in $numbers.ToCharArray()) {
                if ($i -gt 0 -and $i % 2 -eq 0) { $formatted += " " }
                $formatted += $d
                $i++
            }
            return $formatted
        } else {
            $formatted = ""
            $i = 0
            foreach ($d in $digits.ToCharArray()) {
                if ($i -gt 0 -and $i % 2 -eq 0) { $formatted += " " }
                $formatted += $d
                $i++
            }
            return $formatted
        }
    }

    function Test-Doublon {
        param($Prenom, $Nom)
        $collecteursExistants = Get-Collecteurs
        $doublon = $collecteursExistants | Where-Object { 
            $_.prenom -eq $Prenom -and $_.nom -eq $Nom 
        }
        if ($Mode -eq "Modifier" -and $Collecteur) {
            $doublon = $doublon | Where-Object { $_.id -ne $Collecteur.id }
        }
        return ($doublon.Count -gt 0)
    }

    function Get-VehiculeAffectation {
        param($Immatriculation)
        if ([string]::IsNullOrWhiteSpace($Immatriculation)) { return $null }
        $collecteurs = Get-Collecteurs
        $affecte = $collecteurs | Where-Object { $_.vehiculeDefaut -eq $Immatriculation }
        if ($Mode -eq "Modifier" -and $Collecteur) {
            $affecte = $affecte | Where-Object { $_.id -ne $Collecteur.id }
        }
        return $affecte
    }

    # Mise à jour de la coche prénom
    $txtPrenom.Add_TextChanged({
        $val = $txtPrenom.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblPrenomCheck.Text = ""
            $lblPrenomError.Text = ""
        } elseif ($val.Length -lt 2) {
            $lblPrenomCheck.Text = ""
            $lblPrenomError.Text = "❌ Minimum 2 caractères"
        } else {
            $lblPrenomCheck.Text = "✅"
            $lblPrenomCheck.ForeColor = $vert
            $lblPrenomError.Text = ""
        }
    })

    # Mise à jour de la coche nom
    $txtNom.Add_TextChanged({
        $val = $txtNom.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblNomCheck.Text = ""
            $lblNomError.Text = ""
        } elseif ($val.Length -lt 2) {
            $lblNomCheck.Text = ""
            $lblNomError.Text = "❌ Minimum 2 caractères"
        } else {
            $lblNomCheck.Text = "✅"
            $lblNomCheck.ForeColor = $vert
            $lblNomError.Text = ""
        }
    })

    # Mise à jour de la coche téléphone
    $txtTelephone.Add_TextChanged({
        $val = $txtTelephone.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblTelephoneCheck.Text = ""
            $lblTelephoneError.Text = "⭕ Optionnel"
            $lblTelephoneError.ForeColor = $orangeClair
        } elseif (Test-Telephone $val) {
            $lblTelephoneCheck.Text = "✅"
            $lblTelephoneCheck.ForeColor = $vert
            $lblTelephoneError.Text = "✅ Valide"
            $lblTelephoneError.ForeColor = $vert
        } else {
            $lblTelephoneCheck.Text = ""
            $lblTelephoneError.Text = "❌ Format invalide"
            $lblTelephoneError.ForeColor = $orange
        }
    })

    # Mise à jour de la coche email
    $txtEmail.Add_TextChanged({
        $val = $txtEmail.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblEmailCheck.Text = ""
            $lblEmailError.Text = "⭕ Optionnel"
            $lblEmailError.ForeColor = $orangeClair
        } elseif (Test-Email $val) {
            $lblEmailCheck.Text = "✅"
            $lblEmailCheck.ForeColor = $vert
            $lblEmailError.Text = "✅ Valide"
            $lblEmailError.ForeColor = $vert
        } else {
            $lblEmailCheck.Text = ""
            $lblEmailError.Text = "❌ Format invalide (ex: nom@domaine.com)"
            $lblEmailError.ForeColor = $orange
        }
    })

    # Événement véhicule
    $cbVehicule.Add_SelectedIndexChanged({
        if ($cbVehicule.SelectedIndex -gt 0) {
            $selected = $cbVehicule.SelectedItem
            $immat = $selected.Split(' ')[0]
            $affecte = Get-VehiculeAffectation -Immatriculation $immat
            if ($affecte) {
                $lblVehiculeCheck.Text = ""
                $lblVehiculeInfo.Text = "⚠️ Déjà affecté à : $($affecte.prenom) $($affecte.nom)"
                $lblVehiculeInfo.ForeColor = $orange
            } else {
                $lblVehiculeCheck.Text = "✅"
                $lblVehiculeCheck.ForeColor = $vert
                $lblVehiculeInfo.Text = "✅ Véhicule disponible"
                $lblVehiculeInfo.ForeColor = $vert
            }
        } else {
            $lblVehiculeCheck.Text = ""
            $lblVehiculeInfo.Text = ""
        }
    })

    # Événement VALIDER (validation finale)
    $btnOK.Add_Click({
        Write-Host "[FORM] ========== VALIDATION FINALE ==========" -ForegroundColor Magenta
        
        $erreurs = @()
        $valid = $true
        
        # Prénom
        $prenom = $txtPrenom.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($prenom)) {
            $lblPrenomError.Text = "❌ Champ obligatoire"
            $erreurs += "Prénom"
            $valid = $false
        } elseif ($prenom.Length -lt 2) {
            $lblPrenomError.Text = "❌ Minimum 2 caractères"
            $erreurs += "Prénom"
            $valid = $false
        }
        
        # Nom
        $nom = $txtNom.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($nom)) {
            $lblNomError.Text = "❌ Champ obligatoire"
            $erreurs += "Nom"
            $valid = $false
        } elseif ($nom.Length -lt 2) {
            $lblNomError.Text = "❌ Minimum 2 caractères"
            $erreurs += "Nom"
            $valid = $false
        }
        
        # Doublon
        if ($valid) {
            if (Test-Doublon -Prenom $prenom -Nom $nom) {
                $lblNomError.Text = "❌ Ce collecteur existe déjà !"
                $erreurs += "Doublon"
                $valid = $false
            }
        }
        
        # Téléphone (si rempli)
        $telephoneRaw = $txtTelephone.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($telephoneRaw) -and -not (Test-Telephone $telephoneRaw)) {
            $lblTelephoneError.Text = "❌ Format invalide"
            $lblTelephoneError.ForeColor = $orange
            $erreurs += "Téléphone"
            $valid = $false
        }
        
        # Email (si rempli)
        $emailRaw = $txtEmail.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($emailRaw) -and -not (Test-Email $emailRaw)) {
            $lblEmailError.Text = "❌ Format invalide"
            $lblEmailError.ForeColor = $orange
            $erreurs += "Email"
            $valid = $false
        }
        
        # Véhicule (si sélectionné et déjà pris)
        if ($cbVehicule.SelectedIndex -gt 0) {
            $vehiculeValue = $cbVehicule.SelectedItem.Split(' ')[0]
            $affecte = Get-VehiculeAffectation -Immatriculation $vehiculeValue
            if ($affecte) {
                $lblVehiculeInfo.Text = "❌ Déjà affecté à $($affecte.prenom) $($affecte.nom)"
                $lblVehiculeInfo.ForeColor = $orange
                $erreurs += "Véhicule"
                $valid = $false
            }
        }
        
        if (-not $valid) {
            Write-Host "[FORM] ❌ Erreurs: $($erreurs -join ', ')" -ForegroundColor Red
            return
        }
        
        Write-Host "[FORM] ✅ Validation réussie" -ForegroundColor Green
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })

    $result = $form.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $telephoneFormate = Format-Telephone $txtTelephone.Text
        $vehiculeValue = ""
        if ($cbVehicule.SelectedIndex -gt 0) {
            $vehiculeValue = $cbVehicule.SelectedItem.Split(' ')[0]
        }
        
        return @{
            prenom = $txtPrenom.Text.Trim()
            nom = $txtNom.Text.Trim()
            telephone = $telephoneFormate
            email = $txtEmail.Text.Trim()
            vehiculeDefaut = $vehiculeValue
        }
    }
    return $null
}



# CollecteursForm.ps1 - Formulaire d'ajout/modification de collecteur

. "$PSScriptRoot\..\..\Core\DataManager.ps1"
. "$PSScriptRoot\..\..\Common\Styles.ps1"

function Show-CollecteurForm {
    param(
        [string]$Mode = "Ajouter",
        [hashtable]$Collecteur = $null
    )

    Write-Host "[FORM] ========== FORMULAIRE COLLECTEUR OUVERT ==========" -ForegroundColor Magenta
    Write-Host "[FORM] Mode: $Mode" -ForegroundColor Magenta

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$Mode un collecteur"
    $form.Size = New-Object System.Drawing.Size(600, 550)
    $form.StartPosition = "CenterParent"
    $form.BackColor = $CouleurGrisFond
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $yPos = 20
    $labelWidth = 100
    $fieldWidth = 350
    $checkWidth = 30
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
    if ($Collecteur) { $txtNom.Text = $Collecteur.nom }
    $form.Controls.Add($txtNom)
    
    $lblNomCheck = New-Object System.Windows.Forms.Label
    $lblNomCheck.Text = ""
    $lblNomCheck.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblNomCheck.Location = New-Object System.Drawing.Point(($fieldLeft + $fieldWidth + 5), $yPos)
    $lblNomCheck.Size = New-Object System.Drawing.Size($checkWidth, 25)
    $form.Controls.Add($lblNomCheck)
    
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
    if ($Collecteur) { $txtPrenom.Text = $Collecteur.prenom }
    $form.Controls.Add($txtPrenom)
    
    $lblPrenomCheck = New-Object System.Windows.Forms.Label
    $lblPrenomCheck.Text = ""
    $lblPrenomCheck.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblPrenomCheck.Location = New-Object System.Drawing.Point(($fieldLeft + $fieldWidth + 5), $yPos)
    $lblPrenomCheck.Size = New-Object System.Drawing.Size($checkWidth, 25)
    $form.Controls.Add($lblPrenomCheck)
    
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
    $txtTel.MaxLength = 14
    if ($Collecteur -and $Collecteur.telephone) { 
        $tel = $Collecteur.telephone
        if ($tel -match '^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$') {
            $txtTel.Text = "$1 $2 $3 $4 $5"
        } else {
            $txtTel.Text = $tel
        }
    }
    $form.Controls.Add($txtTel)
    
    $lblTelCheck = New-Object System.Windows.Forms.Label
    $lblTelCheck.Text = ""
    $lblTelCheck.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblTelCheck.Location = New-Object System.Drawing.Point(($fieldLeft + $fieldWidth + 5), $yPos)
    $lblTelCheck.Size = New-Object System.Drawing.Size($checkWidth, 25)
    $form.Controls.Add($lblTelCheck)
    
    $lblTelError = New-Object System.Windows.Forms.Label
    $lblTelError.Text = ""
    $lblTelError.ForeColor = $CouleurOrange
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
    if ($Collecteur) { $txtEmail.Text = $Collecteur.email }
    $form.Controls.Add($txtEmail)
    
    $lblEmailCheck = New-Object System.Windows.Forms.Label
    $lblEmailCheck.Text = ""
    $lblEmailCheck.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblEmailCheck.Location = New-Object System.Drawing.Point(($fieldLeft + $fieldWidth + 5), $yPos)
    $lblEmailCheck.Size = New-Object System.Drawing.Size($checkWidth, 25)
    $form.Controls.Add($lblEmailCheck)
    
    $lblEmailError = New-Object System.Windows.Forms.Label
    $lblEmailError.Text = ""
    $lblEmailError.ForeColor = $CouleurOrange
    $lblEmailError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblEmailError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblEmailError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblEmailError)
    $yPos += 55

    # ============================================
    # VÉHICULE
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

    $lblAlerteVehicule = New-Object System.Windows.Forms.Label
    $lblAlerteVehicule.Text = ""
    $lblAlerteVehicule.ForeColor = $CouleurOrange
    $lblAlerteVehicule.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $lblAlerteVehicule.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 30))
    $lblAlerteVehicule.Size = New-Object System.Drawing.Size($fieldWidth, 40)
    $lblAlerteVehicule.AutoSize = $false
    $form.Controls.Add($lblAlerteVehicule)
    $yPos += 85

    # ============================================
    # BOUTONS - STYLE CENTRALISÉ
    # ============================================
    
    # Bouton VALIDER
    $BtnValider = New-Object System.Windows.Forms.Button
    Set-BtnValiderStyle -BtnValider $BtnValider
    $BtnValider.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $form.Controls.Add($BtnValider)

    # Bouton QUITTER
    $BtnQuitter = New-Object System.Windows.Forms.Button
    Set-BtnQuitterStyle -BtnQuitter $BtnQuitter
    $BtnQuitter.Location = New-Object System.Drawing.Point(($fieldLeft + 120), $yPos)
    $BtnQuitter.Add_Click({ $form.Close() })
    $form.Controls.Add($BtnQuitter)

    # ============================================
    # FONCTIONS DE VALIDATION
    # ============================================
    function Test-DoublonEmail {
        param($Email)
        if ([string]::IsNullOrWhiteSpace($Email)) { return $false }
        $collecteursExistants = Get-Collecteurs
        $doublon = $collecteursExistants | Where-Object { $_.email -eq $Email.ToLower() }
        if ($Mode -eq "Modifier" -and $Collecteur) {
            $doublon = $doublon | Where-Object { $_.id -ne $Collecteur.id }
        }
        return ($doublon.Count -gt 0)
    }
    
    function Test-DoublonTel {
        param($Telephone)
        if ([string]::IsNullOrWhiteSpace($Telephone)) { return $false }
        $collecteursExistants = Get-Collecteurs
        $doublon = $collecteursExistants | Where-Object { $_.telephone -eq $Telephone }
        if ($Mode -eq "Modifier" -and $Collecteur) {
            $doublon = $doublon | Where-Object { $_.id -ne $Collecteur.id }
        }
        return ($doublon.Count -gt 0)
    }

    # ============================================
    # REMPLIR LA LISTE DES VÉHICULES
    # ============================================
    $tousVehicules = Get-Vehicules
    $cmbVehicule.Items.Clear()
    $cmbVehicule.Items.Add("(Aucun véhicule)") | Out-Null
    
    $script:vehiculeIds = @()
    $script:vehiculeIds += $null
    
    foreach ($v in $tousVehicules) {
        $displayText = "$($v.numeroParc)"
        $cmbVehicule.Items.Add($displayText) | Out-Null
        $script:vehiculeIds += $v.id
    }
    $cmbVehicule.SelectedIndex = 0
    
    if ($Collecteur -and $Collecteur.vehiculeId) {
        $index = [array]::IndexOf($script:vehiculeIds, $Collecteur.vehiculeId)
        if ($index -ge 0) { $cmbVehicule.SelectedIndex = $index }
    }

    # ============================================
    # VALIDATION EN TEMPS RÉEL
    # ============================================
    $txtNom.Add_TextChanged({
        $val = $txtNom.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblNomCheck.Text = ""
            $lblNomError.Text = ""
        } else {
            $lblNomCheck.Text = "✅"
            $lblNomCheck.ForeColor = [System.Drawing.Color]::FromArgb(27, 91, 74)
            $lblNomError.Text = ""
        }
    })

    $txtPrenom.Add_TextChanged({
        $val = $txtPrenom.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblPrenomCheck.Text = ""
            $lblPrenomError.Text = ""
        } else {
            $lblPrenomCheck.Text = "✅"
            $lblPrenomCheck.ForeColor = [System.Drawing.Color]::FromArgb(27, 91, 74)
            $lblPrenomError.Text = ""
        }
    })

    $txtTel.Add_TextChanged({
        $val = $txtTel.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblTelCheck.Text = ""
            $lblTelError.Text = ""
        } elseif (Test-DoublonTel -Telephone ($val -replace '[^0-9]', '')) {
            $lblTelCheck.Text = ""
            $lblTelError.Text = "Ce numéro de téléphone existe déjà !"
        } else {
            $lblTelCheck.Text = "✅"
            $lblTelCheck.ForeColor = [System.Drawing.Color]::FromArgb(27, 91, 74)
            $lblTelError.Text = ""
        }
    })

    $txtEmail.Add_TextChanged({
        $val = $txtEmail.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblEmailCheck.Text = ""
            $lblEmailError.Text = ""
        } elseif ($val -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
            $lblEmailCheck.Text = ""
            $lblEmailError.Text = "Format email invalide"
        } elseif (Test-DoublonEmail -Email $val) {
            $lblEmailCheck.Text = ""
            $lblEmailError.Text = "Cet email existe déjà !"
        } else {
            $lblEmailCheck.Text = "✅"
            $lblEmailCheck.ForeColor = [System.Drawing.Color]::FromArgb(27, 91, 74)
            $lblEmailError.Text = ""
        }
    })

    # ============================================
    # ÉVÉNEMENT VALIDER
    # ============================================
    $BtnValider.Add_Click({
        $erreurs = @()
        $valid = $true
        
        $nom = $txtNom.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($nom)) {
            $lblNomError.Text = "Champ obligatoire"
            $erreurs += "Nom"
            $valid = $false
        } elseif ($nom.Length -lt 2) {
            $lblNomError.Text = "Minimum 2 caractères"
            $erreurs += "Nom"
            $valid = $false
        } elseif ($nom.Length -gt 50) {
            $lblNomError.Text = "Maximum 50 caractères"
            $erreurs += "Nom"
            $valid = $false
        } else {
            $lblNomError.Text = ""
        }
        
        $prenom = $txtPrenom.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($prenom)) {
            $lblPrenomError.Text = "Champ obligatoire"
            $erreurs += "Prénom"
            $valid = $false
        } elseif ($prenom.Length -lt 2) {
            $lblPrenomError.Text = "Minimum 2 caractères"
            $erreurs += "Prénom"
            $valid = $false
        } elseif ($prenom.Length -gt 50) {
            $lblPrenomError.Text = "Maximum 50 caractères"
            $erreurs += "Prénom"
            $valid = $false
        } else {
            $lblPrenomError.Text = ""
        }
        
        $telephone = $txtTel.Text.Trim() -replace '[^0-9]', ''
        if (-not [string]::IsNullOrWhiteSpace($telephone)) {
            if ($telephone.Length -ne 10) {
                $lblTelError.Text = "10 chiffres requis"
                $erreurs += "Téléphone"
                $valid = $false
            } elseif (Test-DoublonTel -Telephone $telephone) {
                $lblTelError.Text = "Numéro déjà existant"
                $erreurs += "Téléphone"
                $valid = $false
            } else {
                $lblTelError.Text = ""
            }
        }
        
        $email = $txtEmail.Text.Trim().ToLower()
        if (-not [string]::IsNullOrWhiteSpace($email)) {
            if ($email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
                $lblEmailError.Text = "Format email invalide"
                $erreurs += "Email"
                $valid = $false
            } elseif (Test-DoublonEmail -Email $email) {
                $lblEmailError.Text = "Email déjà existant"
                $erreurs += "Email"
                $valid = $false
            } else {
                $lblEmailError.Text = ""
            }
        }
        
        $vehiculeId = $script:vehiculeIds[$cmbVehicule.SelectedIndex]
        
        if (-not $valid) {
            Write-Host "[FORM] Erreurs: $($erreurs -join ', ')" -ForegroundColor Red
            return
        }
        
        Write-Host "[FORM] Validation reussie" -ForegroundColor Green
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })

    # ============================================
    # AFFICHAGE DU FORMULAIRE
    # ============================================
    $result = $form.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $vehiculeId = $script:vehiculeIds[$cmbVehicule.SelectedIndex]
        
        $telephoneClean = $txtTel.Text.Trim() -replace '[^0-9]', ''
        if ([string]::IsNullOrWhiteSpace($telephoneClean)) { $telephoneClean = $null }
        
        $emailClean = $txtEmail.Text.Trim().ToLower()
        if ([string]::IsNullOrWhiteSpace($emailClean)) { $emailClean = $null }
        
        $donnees = @{
            nom = $txtNom.Text.Trim()
            prenom = $txtPrenom.Text.Trim()
            telephone = $telephoneClean
            email = $emailClean
            vehiculeId = $vehiculeId
        }
        
        Write-Host "[FORM] Donnees retournees: $($donnees | ConvertTo-Json -Compress)" -ForegroundColor Green
        Write-Host "[FORM] ========== FIN FORMULAIRE ==========" -ForegroundColor Magenta
        return $donnees
    }
    return $null
}

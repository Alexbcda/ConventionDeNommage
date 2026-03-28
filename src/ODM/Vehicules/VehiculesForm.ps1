# VehiculesForm.ps1 - Formulaire d'ajout/modification de véhicule

. "$PSScriptRoot\..\..\Core\DataManager.ps1"

function Show-VehiculeForm {
    param(
        [string]$Mode = "Ajouter",
        [hashtable]$Vehicule = $null
    )

    Write-Host "[FORM] ========== FORMULAIRE OUVERT ==========" -ForegroundColor Magenta
    Write-Host "[FORM] Mode: $Mode" -ForegroundColor Magenta

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $orange = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $orangeClair = [System.Drawing.Color]::FromArgb(255, 140, 60)
    $vert = [System.Drawing.Color]::FromArgb(27, 91, 74)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$Mode un véhicule"
    $form.Size = New-Object System.Drawing.Size(650, 750)
    $form.StartPosition = "CenterParent"
    $form.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $yPos = 20
    $labelWidth = 180
    $fieldWidth = 300
    $checkWidth = 30
    $leftMargin = 30
    $fieldLeft = $leftMargin + $labelWidth

    # ========== NUMÉRO DE PARC (OBLIGATOIRE) ==========
    $lblParc = New-Object System.Windows.Forms.Label
    $lblParc.Text = "Numéro de parc * :"
    $lblParc.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblParc.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblParc)

    $txtParc = New-Object System.Windows.Forms.TextBox
    $txtParc.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $txtParc.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    if ($Vehicule) { $txtParc.Text = $Vehicule.numeroParc }
    $form.Controls.Add($txtParc)
    
    $lblParcCheck = New-Object System.Windows.Forms.Label
    $lblParcCheck.Text = ""
    $lblParcCheck.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblParcCheck.Location = New-Object System.Drawing.Point(($fieldLeft + $fieldWidth + 5), $yPos)
    $lblParcCheck.Size = New-Object System.Drawing.Size($checkWidth, 25)
    $form.Controls.Add($lblParcCheck)
    
    $lblParcError = New-Object System.Windows.Forms.Label
    $lblParcError.Text = ""
    $lblParcError.ForeColor = $orange
    $lblParcError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblParcError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblParcError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblParcError)
    $yPos += 55

    # ========== IMMATRICULATION (OBLIGATOIRE) ==========
    $lblImmat = New-Object System.Windows.Forms.Label
    $lblImmat.Text = "Immatriculation * :"
    $lblImmat.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblImmat.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblImmat)

    $txtImmat = New-Object System.Windows.Forms.TextBox
    $txtImmat.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $txtImmat.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    if ($Vehicule) { $txtImmat.Text = $Vehicule.immatriculation }
    $form.Controls.Add($txtImmat)
    
    $lblImmatCheck = New-Object System.Windows.Forms.Label
    $lblImmatCheck.Text = ""
    $lblImmatCheck.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblImmatCheck.Location = New-Object System.Drawing.Point(($fieldLeft + $fieldWidth + 5), $yPos)
    $lblImmatCheck.Size = New-Object System.Drawing.Size($checkWidth, 25)
    $form.Controls.Add($lblImmatCheck)
    
    $lblImmatError = New-Object System.Windows.Forms.Label
    $lblImmatError.Text = ""
    $lblImmatError.ForeColor = $orange
    $lblImmatError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblImmatError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblImmatError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblImmatError)
    $yPos += 55

    # ========== NUMÉRO DE CHÂSSIS (VIN) (OBLIGATOIRE - 17 caractères) ==========
    $lblChassis = New-Object System.Windows.Forms.Label
    $lblChassis.Text = "Numéro de châssis (VIN) * :"
    $lblChassis.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblChassis.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblChassis)

    $txtChassis = New-Object System.Windows.Forms.TextBox
    $txtChassis.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $txtChassis.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    $txtChassis.MaxLength = 17
    $txtChassis.CharacterCasing = "Upper"
    if ($Vehicule) { $txtChassis.Text = $Vehicule.numeroChassis }
    $form.Controls.Add($txtChassis)
    
    # NE PAS INVERSER LE TEXTE - pas de traitement automatique
    
    $lblChassisCheck = New-Object System.Windows.Forms.Label
    $lblChassisCheck.Text = ""
    $lblChassisCheck.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblChassisCheck.Location = New-Object System.Drawing.Point(($fieldLeft + $fieldWidth + 5), $yPos)
    $lblChassisCheck.Size = New-Object System.Drawing.Size($checkWidth, 25)
    $form.Controls.Add($lblChassisCheck)
    
    $lblChassisError = New-Object System.Windows.Forms.Label
    $lblChassisError.Text = ""
    $lblChassisError.ForeColor = $orange
    $lblChassisError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblChassisError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblChassisError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblChassisError)
    $yPos += 55

    # ========== MARQUE (OPTIONNEL) ==========
    $lblMarque = New-Object System.Windows.Forms.Label
    $lblMarque.Text = "Marque :"
    $lblMarque.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblMarque.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblMarque)

    $txtMarque = New-Object System.Windows.Forms.TextBox
    $txtMarque.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $txtMarque.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    if ($Vehicule) { $txtMarque.Text = $Vehicule.marque }
    $form.Controls.Add($txtMarque)
    
    $lblMarqueInfo = New-Object System.Windows.Forms.Label
    $lblMarqueInfo.Text = "⭕ Optionnel"
    $lblMarqueInfo.ForeColor = $orangeClair
    $lblMarqueInfo.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblMarqueInfo.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblMarqueInfo.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblMarqueInfo)
    $yPos += 55

    # ========== MODÈLE (OPTIONNEL) ==========
    $lblModele = New-Object System.Windows.Forms.Label
    $lblModele.Text = "Modèle :"
    $lblModele.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblModele.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblModele)

    $txtModele = New-Object System.Windows.Forms.TextBox
    $txtModele.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $txtModele.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    if ($Vehicule) { $txtModele.Text = $Vehicule.modele }
    $form.Controls.Add($txtModele)
    
    $lblModeleInfo = New-Object System.Windows.Forms.Label
    $lblModeleInfo.Text = "⭕ Optionnel"
    $lblModeleInfo.ForeColor = $orangeClair
    $lblModeleInfo.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblModeleInfo.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblModeleInfo.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblModeleInfo)
    $yPos += 55

    # ========== DATE MISE EN CIRCULATION (OBLIGATOIRE - format texte) ==========
    $lblMiseCircu = New-Object System.Windows.Forms.Label
    $lblMiseCircu.Text = "Mise en circulation * :"
    $lblMiseCircu.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblMiseCircu.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblMiseCircu)

    $txtMiseCircu = New-Object System.Windows.Forms.TextBox
    $txtMiseCircu.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $txtMiseCircu.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    $txtMiseCircu.MaxLength = 10
    if ($Vehicule) { $txtMiseCircu.Text = $Vehicule.dateMiseCirculation }
    $form.Controls.Add($txtMiseCircu)
    
    $lblMiseCircuInfo = New-Object System.Windows.Forms.Label
    $lblMiseCircuInfo.Text = "Format: JJ/MM/AAAA"
    $lblMiseCircuInfo.ForeColor = $orangeClair
    $lblMiseCircuInfo.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblMiseCircuInfo.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblMiseCircuInfo.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblMiseCircuInfo)
    
    $lblMiseCircuError = New-Object System.Windows.Forms.Label
    $lblMiseCircuError.Text = ""
    $lblMiseCircuError.ForeColor = $orange
    $lblMiseCircuError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblMiseCircuError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 45))
    $lblMiseCircuError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblMiseCircuError)
    $yPos += 70

    # ========== FIN VALIDITÉ CONTRÔLE TECHNIQUE (OBLIGATOIRE - format texte) ==========
    $lblCtrl = New-Object System.Windows.Forms.Label
    $lblCtrl.Text = "Fin validité contrôle technique * :"
    $lblCtrl.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblCtrl.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblCtrl)

    $txtCtrl = New-Object System.Windows.Forms.TextBox
    $txtCtrl.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $txtCtrl.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    $txtCtrl.MaxLength = 10
    if ($Vehicule) { $txtCtrl.Text = $Vehicule.dateControle }
    $form.Controls.Add($txtCtrl)
    
    $lblCtrlInfo = New-Object System.Windows.Forms.Label
    $lblCtrlInfo.Text = "Format: JJ/MM/AAAA"
    $lblCtrlInfo.ForeColor = $orangeClair
    $lblCtrlInfo.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblCtrlInfo.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblCtrlInfo.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblCtrlInfo)
    
    $lblCtrlError = New-Object System.Windows.Forms.Label
    $lblCtrlError.Text = ""
    $lblCtrlError.ForeColor = $orange
    $lblCtrlError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblCtrlError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 45))
    $lblCtrlError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblCtrlError)
    $yPos += 70

    # ========== ALERTE (TEXTE LONG OPTIONNEL) ==========
    $lblAlerte = New-Object System.Windows.Forms.Label
    $lblAlerte.Text = "Alerte :"
    $lblAlerte.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblAlerte.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblAlerte)

    $txtAlerte = New-Object System.Windows.Forms.TextBox
    $txtAlerte.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $txtAlerte.Size = New-Object System.Drawing.Size($fieldWidth, 60)
    $txtAlerte.Multiline = $true
    $txtAlerte.ScrollBars = "Vertical"
    if ($Vehicule) { $txtAlerte.Text = $Vehicule.alerte }
    $form.Controls.Add($txtAlerte)
    
    $lblAlerteInfo = New-Object System.Windows.Forms.Label
    $lblAlerteInfo.Text = "⭕ Optionnel - information supplémentaire"
    $lblAlerteInfo.ForeColor = $orangeClair
    $lblAlerteInfo.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblAlerteInfo.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 65))
    $lblAlerteInfo.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblAlerteInfo)
    $yPos += 85

    # ========== DATE ALERTE (OPTIONNELLE - format texte) ==========
    $lblDateAlerte = New-Object System.Windows.Forms.Label
    $lblDateAlerte.Text = "Date alerte :"
    $lblDateAlerte.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblDateAlerte.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblDateAlerte)

    $txtDateAlerte = New-Object System.Windows.Forms.TextBox
    $txtDateAlerte.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $txtDateAlerte.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    $txtDateAlerte.MaxLength = 10
    if ($Vehicule) { $txtDateAlerte.Text = $Vehicule.dateAlerte }
    $form.Controls.Add($txtDateAlerte)
    
    $lblDateAlerteInfo = New-Object System.Windows.Forms.Label
    $lblDateAlerteInfo.Text = "Format: JJ/MM/AAAA (optionnel)"
    $lblDateAlerteInfo.ForeColor = $orangeClair
    $lblDateAlerteInfo.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblDateAlerteInfo.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblDateAlerteInfo.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblDateAlerteInfo)
    
    $lblDateAlerteError = New-Object System.Windows.Forms.Label
    $lblDateAlerteError.Text = ""
    $lblDateAlerteError.ForeColor = $orange
    $lblDateAlerteError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblDateAlerteError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 45))
    $lblDateAlerteError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblDateAlerteError)
    $yPos += 70

    # ========== BOUTONS ==========
    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text = "VALIDER"
    $btnOK.Size = New-Object System.Drawing.Size(100, 40)
    $btnOK.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $btnOK.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnOK.FlatStyle = "Flat"
    $btnOK.FlatAppearance.BorderColor = $orange
    $btnOK.FlatAppearance.BorderSize = 2
    $btnOK.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnOK.Cursor = [System.Windows.Forms.Cursors]::Hand
    
    $btnOK.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = $orangeClair
        $this.BackColor = $orange
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $btnOK.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = $orange
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

    # ========== FONCTIONS DE VALIDATION ==========
    function Test-DoublonParc {
        param($NumeroParc)
        $vehiculesExistants = Get-Vehicules
        $doublon = $vehiculesExistants | Where-Object { $_.numeroParc -eq $NumeroParc }
        if ($Mode -eq "Modifier" -and $Vehicule) {
            $doublon = $doublon | Where-Object { $_.id -ne $Vehicule.id }
        }
        return ($doublon.Count -gt 0)
    }
    
    function Test-DoublonImmat {
        param($Immatriculation)
        $vehiculesExistants = Get-Vehicules
        $doublon = $vehiculesExistants | Where-Object { $_.immatriculation -eq $Immatriculation }
        if ($Mode -eq "Modifier" -and $Vehicule) {
            $doublon = $doublon | Where-Object { $_.id -ne $Vehicule.id }
        }
        return ($doublon.Count -gt 0)
    }
    
    function Test-DoublonChassis {
        param($NumeroChassis)
        if ([string]::IsNullOrWhiteSpace($NumeroChassis)) { return $false }
        $vehiculesExistants = Get-Vehicules
        $doublon = $vehiculesExistants | Where-Object { $_.numeroChassis -eq $NumeroChassis }
        if ($Mode -eq "Modifier" -and $Vehicule) {
            $doublon = $doublon | Where-Object { $_.id -ne $Vehicule.id }
        }
        return ($doublon.Count -gt 0)
    }
    
    function Test-Date {
        param($DateStr)
        if ([string]::IsNullOrWhiteSpace($DateStr)) { return $false }
        $pattern = '^\d{2}/\d{2}/\d{4}$'
        if ($DateStr -notmatch $pattern) { return $false }
        try {
            $jour = [int]$DateStr.Substring(0,2)
            $mois = [int]$DateStr.Substring(3,2)
            $annee = [int]$DateStr.Substring(6,4)
            $date = Get-Date -Year $annee -Month $mois -Day $jour -ErrorAction Stop
            return $true
        } catch {
            return $false
        }
    }

    # Validation en temps réel
    $txtParc.Add_TextChanged({
        $val = $txtParc.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblParcCheck.Text = ""
            $lblParcError.Text = ""
        } elseif (Test-DoublonParc -NumeroParc $val) {
            $lblParcCheck.Text = ""
            $lblParcError.Text = "❌ Ce numéro de parc existe déjà !"
        } else {
            $lblParcCheck.Text = "✅"
            $lblParcCheck.ForeColor = $vert
            $lblParcError.Text = ""
        }
    })

    $txtImmat.Add_TextChanged({
        $val = $txtImmat.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblImmatCheck.Text = ""
            $lblImmatError.Text = ""
        } elseif (Test-DoublonImmat -Immatriculation $val) {
            $lblImmatCheck.Text = ""
            $lblImmatError.Text = "❌ Cette immatriculation existe déjà !"
        } else {
            $lblImmatCheck.Text = "✅"
            $lblImmatCheck.ForeColor = $vert
            $lblImmatError.Text = ""
        }
    })

    $txtChassis.Add_TextChanged({
        $val = $txtChassis.Text.Trim().ToUpper()
        $txtChassis.Text = $val
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblChassisCheck.Text = ""
            $lblChassisError.Text = ""
        } elseif ($val.Length -ne 17) {
            $lblChassisCheck.Text = ""
            $lblChassisError.Text = "❌ 17 caractères requis"
        } elseif (Test-DoublonChassis -NumeroChassis $val) {
            $lblChassisCheck.Text = ""
            $lblChassisError.Text = "❌ Ce numéro de châssis existe déjà !"
        } else {
            $lblChassisCheck.Text = "✅"
            $lblChassisCheck.ForeColor = $vert
            $lblChassisError.Text = ""
        }
    })

    $txtMiseCircu.Add_TextChanged({
        $val = $txtMiseCircu.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblMiseCircuError.Text = ""
        } elseif (-not (Test-Date $val)) {
            $lblMiseCircuError.Text = "❌ Format JJ/MM/AAAA invalide"
        } else {
            $lblMiseCircuError.Text = ""
        }
    })

    $txtCtrl.Add_TextChanged({
        $val = $txtCtrl.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblCtrlError.Text = ""
        } elseif (-not (Test-Date $val)) {
            $lblCtrlError.Text = "❌ Format JJ/MM/AAAA invalide"
        } else {
            $lblCtrlError.Text = ""
        }
    })

    $txtDateAlerte.Add_TextChanged({
        $val = $txtDateAlerte.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblDateAlerteError.Text = ""
        } elseif (-not (Test-Date $val)) {
            $lblDateAlerteError.Text = "❌ Format JJ/MM/AAAA invalide"
        } else {
            $lblDateAlerteError.Text = ""
        }
    })

    # Événement VALIDER
    $btnOK.Add_Click({
        Write-Host "[FORM] ========== VALIDATION FINALE ==========" -ForegroundColor Magenta
        
        $erreurs = @()
        $valid = $true
        
        # Numéro de parc
        $parc = $txtParc.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($parc)) {
            $lblParcError.Text = "❌ Champ obligatoire"
            $erreurs += "Numéro de parc"
            $valid = $false
        } elseif (Test-DoublonParc -NumeroParc $parc) {
            $lblParcError.Text = "❌ Ce numéro de parc existe déjà !"
            $erreurs += "Numéro de parc (doublon)"
            $valid = $false
        }
        
        # Immatriculation
        $immat = $txtImmat.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($immat)) {
            $lblImmatError.Text = "❌ Champ obligatoire"
            $erreurs += "Immatriculation"
            $valid = $false
        } elseif (Test-DoublonImmat -Immatriculation $immat) {
            $lblImmatError.Text = "❌ Cette immatriculation existe déjà !"
            $erreurs += "Immatriculation (doublon)"
            $valid = $false
        }
        
        # Numéro de châssis
        $chassis = $txtChassis.Text.Trim().ToUpper()
        if ([string]::IsNullOrWhiteSpace($chassis)) {
            $lblChassisError.Text = "❌ Champ obligatoire"
            $erreurs += "Numéro de châssis"
            $valid = $false
        } elseif ($chassis.Length -ne 17) {
            $lblChassisError.Text = "❌ 17 caractères requis"
            $erreurs += "Numéro de châssis (17 caractères)"
            $valid = $false
        } elseif (Test-DoublonChassis -NumeroChassis $chassis) {
            $lblChassisError.Text = "❌ Ce numéro de châssis existe déjà !"
            $erreurs += "Numéro de châssis (doublon)"
            $valid = $false
        }
        
        # Date mise en circulation
        $dateMise = $txtMiseCircu.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($dateMise)) {
            $lblMiseCircuError.Text = "❌ Champ obligatoire"
            $erreurs += "Date mise en circulation"
            $valid = $false
        } elseif (-not (Test-Date $dateMise)) {
            $lblMiseCircuError.Text = "❌ Format JJ/MM/AAAA invalide"
            $erreurs += "Date mise en circulation (format)"
            $valid = $false
        }
        
        # Date contrôle technique
        $dateCtrl = $txtCtrl.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($dateCtrl)) {
            $lblCtrlError.Text = "❌ Champ obligatoire"
            $erreurs += "Fin validité contrôle technique"
            $valid = $false
        } elseif (-not (Test-Date $dateCtrl)) {
            $lblCtrlError.Text = "❌ Format JJ/MM/AAAA invalide"
            $erreurs += "Fin validité contrôle technique (format)"
            $valid = $false
        }
        
        # Date alerte (optionnelle mais format valide si renseignée)
        $dateAlerte = $txtDateAlerte.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($dateAlerte) -and -not (Test-Date $dateAlerte)) {
            $lblDateAlerteError.Text = "❌ Format JJ/MM/AAAA invalide"
            $erreurs += "Date alerte (format)"
            $valid = $false
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
        $donnees = @{
            numeroParc = $txtParc.Text.Trim()
            immatriculation = $txtImmat.Text.Trim().ToUpper()
            numeroChassis = $txtChassis.Text.Trim().ToUpper()
            marque = $txtMarque.Text.Trim()
            modele = $txtModele.Text.Trim()
            dateMiseCirculation = $txtMiseCircu.Text.Trim()
            dateControle = $txtCtrl.Text.Trim()
            alerte = $txtAlerte.Text.Trim()
            dateAlerte = $txtDateAlerte.Text.Trim()
        }
        
        Write-Host "[FORM] Données retournées: $($donnees | ConvertTo-Json -Compress)" -ForegroundColor Green
        Write-Host "[FORM] ========== FIN FORMULAIRE ==========" -ForegroundColor Magenta
        return $donnees
    }
    return $null
}


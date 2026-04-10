# VehiculesForm.ps1 - Formulaire d'ajout/modification de véhicule

. "$PSScriptRoot\..\..\Core\DataManager.ps1"
. "$PSScriptRoot\..\..\Common\Styles.ps1"

function Show-VehiculeForm {
    param(
        [string]$Mode = "Ajouter",
        [hashtable]$Vehicule = $null
    )

    Write-Host "[FORM] ========== FORMULAIRE VEHICULE OUVERT ==========" -ForegroundColor Magenta
    Write-Host "[FORM] Mode: $Mode" -ForegroundColor Magenta

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$Mode un véhicule"
    $form.Size = New-Object System.Drawing.Size(600, 550)
    $form.StartPosition = "CenterParent"
    $form.BackColor = $CouleurGrisFond
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $yPos = 20
    $labelWidth = 150
    $fieldWidth = 300
    $leftMargin = 30
    $fieldLeft = $leftMargin + $labelWidth

    # ============================================
    # NUMÉRO DE PARC
    # ============================================
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
    
    $lblParcError = New-Object System.Windows.Forms.Label
    $lblParcError.Text = ""
    $lblParcError.ForeColor = $CouleurOrange
    $lblParcError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblParcError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblParcError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblParcError)
    $yPos += 55

    # ============================================
    # IMMATRICULATION
    # ============================================
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
    
    $lblImmatError = New-Object System.Windows.Forms.Label
    $lblImmatError.Text = ""
    $lblImmatError.ForeColor = $CouleurOrange
    $lblImmatError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblImmatError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblImmatError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblImmatError)
    $yPos += 55

    # ============================================
    # NUMÉRO DE CHÂSSIS
    # ============================================
    $lblChassis = New-Object System.Windows.Forms.Label
    $lblChassis.Text = "Numéro de châssis * :"
    $lblChassis.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblChassis.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblChassis)

    $txtChassis = New-Object System.Windows.Forms.TextBox
    $txtChassis.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $txtChassis.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    $txtChassis.MaxLength = 17
    if ($Vehicule) { $txtChassis.Text = $Vehicule.numeroChassis }
    $form.Controls.Add($txtChassis)
    
    $lblChassisError = New-Object System.Windows.Forms.Label
    $lblChassisError.Text = ""
    $lblChassisError.ForeColor = $CouleurOrange
    $lblChassisError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblChassisError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblChassisError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblChassisError)
    $yPos += 55

    # ============================================
    # MARQUE (OPTIONNEL)
    # ============================================
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
    $lblMarqueInfo.ForeColor = $CouleurOrangeClair
    $lblMarqueInfo.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblMarqueInfo.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblMarqueInfo.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblMarqueInfo)
    $yPos += 55

    # ============================================
    # MODÈLE (OPTIONNEL)
    # ============================================
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
    $lblModeleInfo.ForeColor = $CouleurOrangeClair
    $lblModeleInfo.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblModeleInfo.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblModeleInfo.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblModeleInfo)
    $yPos += 55

    # ============================================
    # DATE MISE EN CIRCULATION
    # ============================================
    $lblMise = New-Object System.Windows.Forms.Label
    $lblMise.Text = "Mise en circulation * :"
    $lblMise.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblMise.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblMise)

    $txtMise = New-Object System.Windows.Forms.TextBox
    $txtMise.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $txtMise.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    $txtMise.MaxLength = 10
    if ($Vehicule) { $txtMise.Text = $Vehicule.dateMiseCirculation }
    $form.Controls.Add($txtMise)
    
    $lblMiseError = New-Object System.Windows.Forms.Label
    $lblMiseError.Text = ""
    $lblMiseError.ForeColor = $CouleurOrange
    $lblMiseError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblMiseError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblMiseError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblMiseError)
    $yPos += 55

    # ============================================
    # DATE CONTRÔLE TECHNIQUE
    # ============================================
    $lblCtrl = New-Object System.Windows.Forms.Label
    $lblCtrl.Text = "Contrôle technique * :"
    $lblCtrl.Location = New-Object System.Drawing.Point($leftMargin, $yPos)
    $lblCtrl.Size = New-Object System.Drawing.Size($labelWidth, 25)
    $form.Controls.Add($lblCtrl)

    $txtCtrl = New-Object System.Windows.Forms.TextBox
    $txtCtrl.Location = New-Object System.Drawing.Point($fieldLeft, $yPos)
    $txtCtrl.Size = New-Object System.Drawing.Size($fieldWidth, 25)
    $txtCtrl.MaxLength = 10
    if ($Vehicule) { $txtCtrl.Text = $Vehicule.dateControle }
    $form.Controls.Add($txtCtrl)
    
    $lblCtrlError = New-Object System.Windows.Forms.Label
    $lblCtrlError.Text = ""
    $lblCtrlError.ForeColor = $CouleurOrange
    $lblCtrlError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblCtrlError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblCtrlError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblCtrlError)
    $yPos += 55

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
    # FONCTIONS DE VALIDATION
    # ============================================
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

    # ============================================
    # VALIDATION EN TEMPS RÉEL
    # ============================================
    $txtParc.Add_TextChanged({
        $val = $txtParc.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblParcError.Text = ""
        } elseif (Test-DoublonParc -NumeroParc $val) {
            $lblParcError.Text = "Ce numéro de parc existe déjà !"
        } else {
            $lblParcError.Text = ""
        }
    })

    $txtImmat.Add_TextChanged({
        $val = $txtImmat.Text.Trim().ToUpper()
        $txtImmat.Text = $val
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblImmatError.Text = ""
        } elseif (Test-DoublonImmat -Immatriculation $val) {
            $lblImmatError.Text = "Cette immatriculation existe déjà !"
        } else {
            $lblImmatError.Text = ""
        }
    })

    $txtChassis.Add_TextChanged({
        $val = $txtChassis.Text.Trim().ToUpper()
        $txtChassis.Text = $val
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblChassisError.Text = ""
        } elseif ($val.Length -ne 17) {
            $lblChassisError.Text = "17 caractères requis"
        } elseif (Test-DoublonChassis -NumeroChassis $val) {
            $lblChassisError.Text = "Ce numéro de châssis existe déjà !"
        } else {
            $lblChassisError.Text = ""
        }
    })

    $txtMise.Add_TextChanged({
        $val = $txtMise.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblMiseError.Text = ""
        } elseif (-not (Test-Date $val)) {
            $lblMiseError.Text = "Format JJ/MM/AAAA invalide"
        } else {
            $lblMiseError.Text = ""
        }
    })

    $txtCtrl.Add_TextChanged({
        $val = $txtCtrl.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            $lblCtrlError.Text = ""
        } elseif (-not (Test-Date $val)) {
            $lblCtrlError.Text = "Format JJ/MM/AAAA invalide"
        } else {
            $lblCtrlError.Text = ""
        }
    })

    # ============================================
    # ÉVÉNEMENT VALIDER
    # ============================================
    $BtnValider.Add_Click({
        $erreurs = @()
        $valid = $true
        
        $parc = $txtParc.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($parc)) {
            $lblParcError.Text = "Champ obligatoire"
            $erreurs += "Numéro de parc"
            $valid = $false
        } elseif (Test-DoublonParc -NumeroParc $parc) {
            $lblParcError.Text = "Ce numéro de parc existe déjà !"
            $erreurs += "Numéro de parc (doublon)"
            $valid = $false
        }
        
        $immat = $txtImmat.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($immat)) {
            $lblImmatError.Text = "Champ obligatoire"
            $erreurs += "Immatriculation"
            $valid = $false
        } elseif (Test-DoublonImmat -Immatriculation $immat) {
            $lblImmatError.Text = "Cette immatriculation existe déjà !"
            $erreurs += "Immatriculation (doublon)"
            $valid = $false
        }
        
        $chassis = $txtChassis.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($chassis)) {
            $lblChassisError.Text = "Champ obligatoire"
            $erreurs += "Numéro de châssis"
            $valid = $false
        } elseif ($chassis.Length -ne 17) {
            $lblChassisError.Text = "17 caractères requis"
            $erreurs += "Numéro de châssis (17 caractères)"
            $valid = $false
        } elseif (Test-DoublonChassis -NumeroChassis $chassis) {
            $lblChassisError.Text = "Ce numéro de châssis existe déjà !"
            $erreurs += "Numéro de châssis (doublon)"
            $valid = $false
        }
        
        $mise = $txtMise.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($mise)) {
            $lblMiseError.Text = "Champ obligatoire"
            $erreurs += "Date mise en circulation"
            $valid = $false
        } elseif (-not (Test-Date $mise)) {
            $lblMiseError.Text = "Format JJ/MM/AAAA invalide"
            $erreurs += "Date mise en circulation (format)"
            $valid = $false
        }
        
        $ctrl = $txtCtrl.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($ctrl)) {
            $lblCtrlError.Text = "Champ obligatoire"
            $erreurs += "Date contrôle technique"
            $valid = $false
        } elseif (-not (Test-Date $ctrl)) {
            $lblCtrlError.Text = "Format JJ/MM/AAAA invalide"
            $erreurs += "Date contrôle technique (format)"
            $valid = $false
        }
        
        if (-not $valid) {
            Write-Host "[FORM] Erreurs: $($erreurs -join ', ')" -ForegroundColor Red
            return
        }
        
        Write-Host "[FORM] Validation reussie" -ForegroundColor Green
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })

    # ============================================
    # AFFICHAGE
    # ============================================
    $result = $form.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $donnees = @{
            numeroParc = $txtParc.Text.Trim()
            immatriculation = $txtImmat.Text.Trim().ToUpper()
            numeroChassis = $txtChassis.Text.Trim().ToUpper()
            marque = $txtMarque.Text.Trim()
            modele = $txtModele.Text.Trim()
            dateMiseCirculation = $txtMise.Text.Trim()
            dateControle = $txtCtrl.Text.Trim()
            alerte = ""
            dateAlerte = ""
        }
        
        Write-Host "[FORM] Donnees retournees: $($donnees | ConvertTo-Json -Compress)" -ForegroundColor Green
        Write-Host "[FORM] ========== FIN FORMULAIRE ==========" -ForegroundColor Magenta
        return $donnees
    }
    return $null
}

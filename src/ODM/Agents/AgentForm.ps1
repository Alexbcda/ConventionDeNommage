# AgentForm.ps1 - Formulaire d'ajout/modification d'agent

. "$PSScriptRoot\..\..\Database\Database.ps1"
. "$PSScriptRoot\..\..\Common\Styles.ps1"

function Show-AgentForm {
    param(
        [string]$Mode = "Ajouter",
        [hashtable]$Agent = $null
    )

    Write-Host "[FORM] ========== FORMULAIRE AGENT OUVERT ==========" -ForegroundColor Magenta
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
    $txtTel.MaxLength = 14
    if ($Agent -and $Agent.telephone) { 
        $tel = $Agent.telephone
        if ($tel -match '^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$') {
            $txtTel.Text = "$1 $2 $3 $4 $5"
        } else {
            $txtTel.Text = $tel
        }
    }
    $form.Controls.Add($txtTel)
    
    $lblTelError = New-Object System.Windows.Forms.Label
    $lblTelError.Text = ""
    $lblTelError.ForeColor = $CouleurOrange
    $lblTelError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblTelError.Location = New-Object System.Drawing.Point($fieldLeft, ($yPos + 28))
    $lblTelError.Size = New-Object System.Drawing.Size($fieldWidth, 15)
    $form.Controls.Add($lblTelError)
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
            $displayText = "$($v.numero_parc) - $($v.immatriculation)"
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
    # VALIDATION DOUBLONS (SQLite)
    # ============================================
    function Test-DoublonEmail {
        param($Email)
        if ([string]::IsNullOrWhiteSpace($Email)) { return $false }
        
        $conn = Open-Connection
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT id_agent FROM Agent WHERE email = @email"
        $cmd.Parameters.AddWithValue("@email", $Email.ToLower()) | Out-Null
        $existing = $cmd.ExecuteScalar()
        $conn.Close()
        
        if ($Mode -eq "Modifier" -and $Agent -and $existing -eq $Agent.id) {
            return $false
        }
        return ($existing -ne $null)
    }
    
    function Test-DoublonTel {
        param($Telephone)
        if ([string]::IsNullOrWhiteSpace($Telephone)) { return $false }
        
        $conn = Open-Connection
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT id_agent FROM Agent WHERE telephone = @tel"
        $cmd.Parameters.AddWithValue("@tel", $Telephone) | Out-Null
        $existing = $cmd.ExecuteScalar()
        $conn.Close()
        
        if ($Mode -eq "Modifier" -and $Agent -and $existing -eq $Agent.id) {
            return $false
        }
        return ($existing -ne $null)
    }

    # ============================================
    # VALIDATION EN TEMPS RÉEL
    # ============================================
    $txtTel.Add_TextChanged({
        $val = $txtTel.Text.Trim() -replace '[^0-9]', ''
        if (-not [string]::IsNullOrWhiteSpace($val) -and $val.Length -ne 10) {
            $lblTelError.Text = "10 chiffres requis"
        } elseif (Test-DoublonTel -Telephone $val) {
            $lblTelError.Text = "Ce numéro existe déjà !"
        } else {
            $lblTelError.Text = ""
        }
    })

    $txtEmail.Add_TextChanged({
        $val = $txtEmail.Text.Trim()
        if (-not [string]::IsNullOrWhiteSpace($val)) {
            if ($val -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
                $lblEmailError.Text = "Format email invalide"
            } elseif (Test-DoublonEmail -Email $val) {
                $lblEmailError.Text = "Cet email existe déjà !"
            } else {
                $lblEmailError.Text = ""
            }
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
        } else {
            $lblPrenomError.Text = ""
        }
        
        $telephone = $txtTel.Text.Trim() -replace '[^0-9]', ''
        if (-not [string]::IsNullOrWhiteSpace($telephone) -and $telephone.Length -ne 10) {
            $lblTelError.Text = "10 chiffres requis"
            $erreurs += "Téléphone"
            $valid = $false
        } elseif (Test-DoublonTel -Telephone $telephone) {
            $lblTelError.Text = "Numéro déjà existant"
            $erreurs += "Téléphone"
            $valid = $false
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
    # AFFICHAGE
    # ============================================
    $result = $form.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $vehiculeId = $script:vehiculeIds[$cmbVehicule.SelectedIndex]
        if ($vehiculeId -eq $null) { $vehiculeId = 0 }
        
        $telephoneClean = $txtTel.Text.Trim() -replace '[^0-9]', ''
        if ([string]::IsNullOrWhiteSpace($telephoneClean)) { $telephoneClean = $null }
        
        $emailClean = $txtEmail.Text.Trim().ToLower()
        if ([string]::IsNullOrWhiteSpace($emailClean)) { $emailClean = $null }
        
        $donnees = @{
            nom = $txtNom.Text.Trim()
            prenom = $txtPrenom.Text.Trim()
            telephone = $telephoneClean
            email = $emailClean
            date_entree = $dtpDateEntree.Value.ToString("yyyy-MM-dd")
            type_contrat = $cmbContrat.SelectedItem.ToString()
            base_heures_semaine = [int]$numHeures.Value
            vehicule_id = $vehiculeId
        }
        
        Write-Host "[FORM] Donnees retournees: $($donnees | ConvertTo-Json -Compress)" -ForegroundColor Green
        Write-Host "[FORM] ========== FIN FORMULAIRE ==========" -ForegroundColor Magenta
        return $donnees
    }
    return $null
}

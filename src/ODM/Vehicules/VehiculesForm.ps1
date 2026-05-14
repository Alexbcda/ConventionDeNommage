# VehiculesForm.ps1 - Formulaire d'ajout/modification de véhicule

. "$PSScriptRoot\..\..\Services\VehiculeService.ps1"
. "$PSScriptRoot\..\..\Common\Styles.ps1"
. "$PSScriptRoot\..\..\Common\Validation.ps1"

function Show-VehiculeForm {
    param(
        [string]$Mode = "Ajouter",
        [hashtable]$Vehicule = $null,
        [System.Windows.Forms.IWin32Window]$Owner = $null
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    function Set-Error {
        param($Label, [string]$Message)
        $Label.Text = $Message
    }

    function Get-RequiredDateError {
        param([string]$Value, [string]$LabelText)
        if ([string]::IsNullOrWhiteSpace($Value)) { return "$LabelText obligatoire" }
        if (-not (Test-DateFr $Value)) { return "Format JJ/MM/AAAA invalide" }
        return ""
    }

    function Get-OptionalDateError {
        param([string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
        if (-not (Test-DateFr $Value)) { return "Format JJ/MM/AAAA invalide" }
        return ""
    }

    function Test-DoublonParc {
        param($NumeroParc)
        if ([string]::IsNullOrWhiteSpace($NumeroParc)) { return $false }
        $eid = if ($Mode -eq "Modifier" -and $Vehicule) { [int]$Vehicule.id } else { 0 }
        return (Test-VehiculeDoublonParc -NumeroParc $NumeroParc -ExcludeId $eid)
    }

    function Test-DoublonImmat {
        param($Immatriculation)
        if ([string]::IsNullOrWhiteSpace($Immatriculation)) { return $false }
        $eid = if ($Mode -eq "Modifier" -and $Vehicule) { [int]$Vehicule.id } else { 0 }
        return (Test-VehiculeDoublonImmat -Immatriculation $Immatriculation -ExcludeId $eid)
    }

    function Test-DoublonChassis {
        param($NumeroChassis)
        if ([string]::IsNullOrWhiteSpace($NumeroChassis)) { return $false }
        $eid = if ($Mode -eq "Modifier" -and $Vehicule) { [int]$Vehicule.id } else { 0 }
        return (Test-VehiculeDoublonChassis -NumeroChassis $NumeroChassis -ExcludeId $eid)
    }

    function Get-ImmatError {
        param([string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return "Champ obligatoire" }
        if ($Value -notmatch '^[A-Za-z0-9\- ]{1,20}$') { return "Format immatriculation invalide" }
        $normalized = (Sanitize-TextInput $Value).Trim().ToUpperInvariant()
        if (Test-DoublonImmat -Immatriculation $normalized) { return "Cette immatriculation existe déjà !" }
        return ""
    }

    function Get-ChassisError {
        param([string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return "Champ obligatoire" }
        if ($Value -notmatch '^[A-HJ-NPR-Z0-9]{17}$') { return "VIN invalide (17 caractères)" }
        if (Test-DoublonChassis -NumeroChassis $Value) { return "Ce numéro de châssis existe déjà !" }
        return ""
    }

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = "$Mode un véhicule"
    $form.Size = [System.Drawing.Size]::new(650, 760)
    $form.StartPosition = "CenterParent"
    $form.BackColor = $script:CouleurGrisFond
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $yPos = 20
    $labelWidth = 170
    $fieldWidth = 320
    $leftMargin = 30
    $fieldLeft = $leftMargin + $labelWidth
    $smallErrorFont = [System.Drawing.Font]::new("Segoe UI", 8)

    function Add-Field {
        param(
            [string]$LabelText,
            [string]$InitialValue = "",
            [bool]$Optional = $false,
            [int]$MaxLength = 0,
            [ref]$CurrentY
        )
        $lbl = [System.Windows.Forms.Label]::new()
        $lbl.Text = $LabelText
        $lbl.Location = [System.Drawing.Point]::new($leftMargin, $CurrentY.Value)
        $lbl.Size = [System.Drawing.Size]::new($labelWidth, 25)
        $form.Controls.Add($lbl)

        $txt = [System.Windows.Forms.TextBox]::new()
        $txt.Location = [System.Drawing.Point]::new($fieldLeft, $CurrentY.Value)
        $txt.Size = [System.Drawing.Size]::new($fieldWidth, 25)
        if ($MaxLength -gt 0) { $txt.MaxLength = $MaxLength }
        $txt.Text = $InitialValue
        $form.Controls.Add($txt)

        $info = [System.Windows.Forms.Label]::new()
        $info.Text = ""
        if ($Optional) { $info.Text = "Optionnel" }
        $info.ForeColor = if ($Optional) { $script:CouleurOrangeClair } else { $script:CouleurOrange }
        $info.Font = $smallErrorFont
        $info.Location = [System.Drawing.Point]::new($fieldLeft, ($CurrentY.Value + 28))
        $info.Size = [System.Drawing.Size]::new($fieldWidth, 15)
        $form.Controls.Add($info)

        $script:__vehicule_lastErrorLabel = $info
        $script:__vehicule_lastTextBox = $txt
        $CurrentY.Value += 55
    }

    Add-Field -LabelText "Numéro de parc * :" -InitialValue $(if ($Vehicule) { $Vehicule.numeroParc } else { "" }) -MaxLength 50 -CurrentY ([ref]$yPos)
    $txtParc = $script:__vehicule_lastTextBox
    $lblParcError = $script:__vehicule_lastErrorLabel

    Add-Field -LabelText "Immatriculation * :" -InitialValue $(if ($Vehicule) { $Vehicule.immatriculation } else { "" }) -CurrentY ([ref]$yPos)
    $txtImmat = $script:__vehicule_lastTextBox
    $lblImmatError = $script:__vehicule_lastErrorLabel

    Add-Field -LabelText "Numéro de châssis * :" -InitialValue $(if ($Vehicule) { $Vehicule.numeroChassis } else { "" }) -MaxLength 17 -CurrentY ([ref]$yPos)
    $txtChassis = $script:__vehicule_lastTextBox
    $lblChassisError = $script:__vehicule_lastErrorLabel

    Add-Field -LabelText "Marque :" -InitialValue $(if ($Vehicule) { $Vehicule.marque } else { "" }) -Optional $true -CurrentY ([ref]$yPos)
    $txtMarque = $script:__vehicule_lastTextBox
    $lblMarqueInfo = $script:__vehicule_lastErrorLabel

    Add-Field -LabelText "Modèle :" -InitialValue $(if ($Vehicule) { $Vehicule.modele } else { "" }) -Optional $true -CurrentY ([ref]$yPos)
    $txtModele = $script:__vehicule_lastTextBox
    $lblModeleInfo = $script:__vehicule_lastErrorLabel

    $lblMise = [System.Windows.Forms.Label]::new()
    $lblMise.Text = "Mise en circulation * :"
    $lblMise.Location = [System.Drawing.Point]::new($leftMargin, $yPos)
    $lblMise.Size = [System.Drawing.Size]::new($labelWidth, 25)
    $form.Controls.Add($lblMise)

    $dtMise = [System.Windows.Forms.DateTimePicker]::new()
    $dtMise.Location = [System.Drawing.Point]::new($fieldLeft, $yPos)
    $dtMise.Size = [System.Drawing.Size]::new($fieldWidth, 25)
    $dtMise.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
    $dtMise.CustomFormat = "dd/MM/yyyy"
    if ($Vehicule -and $Vehicule.dateMiseCirculation) {
        $parsedMise = Convert-DbToFrDate $Vehicule.dateMiseCirculation
        if (Test-DateFr $parsedMise) {
            $dtMise.Value = [datetime]::ParseExact($parsedMise, "dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)
        }
    }
    $form.Controls.Add($dtMise)

    $lblMiseError = [System.Windows.Forms.Label]::new()
    $lblMiseError.Text = ""
    $lblMiseError.ForeColor = $script:CouleurOrange
    $lblMiseError.Font = $smallErrorFont
    $lblMiseError.Location = [System.Drawing.Point]::new($fieldLeft, ($yPos + 28))
    $lblMiseError.Size = [System.Drawing.Size]::new($fieldWidth, 15)
    $form.Controls.Add($lblMiseError)
    $yPos += 55

    $lblDateEntree = [System.Windows.Forms.Label]::new()
    $lblDateEntree.Text = "Date d'entrée * :"
    $lblDateEntree.Location = [System.Drawing.Point]::new($leftMargin, $yPos)
    $lblDateEntree.Size = [System.Drawing.Size]::new($labelWidth, 25)
    $form.Controls.Add($lblDateEntree)

    $dtDateEntree = [System.Windows.Forms.DateTimePicker]::new()
    $dtDateEntree.Location = [System.Drawing.Point]::new($fieldLeft, $yPos)
    $dtDateEntree.Size = [System.Drawing.Size]::new($fieldWidth, 25)
    $dtDateEntree.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
    $dtDateEntree.CustomFormat = "dd/MM/yyyy"
    if ($Vehicule -and $Vehicule.dateEntree) {
        $parsedEntree = Convert-DbToFrDate $Vehicule.dateEntree
        if (Test-DateFr $parsedEntree) {
            $dtDateEntree.Value = [datetime]::ParseExact($parsedEntree, "dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)
        }
    }
    $form.Controls.Add($dtDateEntree)

    $lblDateEntreeError = [System.Windows.Forms.Label]::new()
    $lblDateEntreeError.Text = ""
    $lblDateEntreeError.ForeColor = $script:CouleurOrange
    $lblDateEntreeError.Font = $smallErrorFont
    $lblDateEntreeError.Location = [System.Drawing.Point]::new($fieldLeft, ($yPos + 28))
    $lblDateEntreeError.Size = [System.Drawing.Size]::new($fieldWidth, 15)
    $form.Controls.Add($lblDateEntreeError)
    $yPos += 55

    $lblSortie = [System.Windows.Forms.Label]::new()
    $lblSortie.Text = "Date de sortie :"
    $lblSortie.Location = [System.Drawing.Point]::new($leftMargin, $yPos)
    $lblSortie.Size = [System.Drawing.Size]::new($labelWidth, 25)
    $form.Controls.Add($lblSortie)

    $dtSortie = [System.Windows.Forms.DateTimePicker]::new()
    $dtSortie.Location = [System.Drawing.Point]::new($fieldLeft, $yPos)
    $dtSortie.Size = [System.Drawing.Size]::new($fieldWidth, 25)
    $dtSortie.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
    $dtSortie.CustomFormat = "dd/MM/yyyy"
    $dtSortie.ShowCheckBox = $true
    $dtSortie.Checked = $false
    if ($Vehicule -and $Vehicule.dateSortie) {
        $parsedSortie = Convert-DbToFrDate $Vehicule.dateSortie
        if (Test-DateFr $parsedSortie) {
            $dtSortie.Value = [datetime]::ParseExact($parsedSortie, "dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)
            $dtSortie.Checked = $true
        }
    }
    $form.Controls.Add($dtSortie)

    $lblDateSortieError = [System.Windows.Forms.Label]::new()
    $lblDateSortieError.Text = ""
    $lblDateSortieError.ForeColor = $script:CouleurOrange
    $lblDateSortieError.Font = $smallErrorFont
    $lblDateSortieError.Location = [System.Drawing.Point]::new($fieldLeft, ($yPos + 28))
    $lblDateSortieError.Size = [System.Drawing.Size]::new($fieldWidth, 15)
    $form.Controls.Add($lblDateSortieError)
    $yPos += 55

    $lblFinCtrl = [System.Windows.Forms.Label]::new()
    $lblFinCtrl.Text = "Contrôle technique (date limite) :"
    $lblFinCtrl.Location = [System.Drawing.Point]::new($leftMargin, $yPos)
    $lblFinCtrl.Size = [System.Drawing.Size]::new($labelWidth, 25)
    $form.Controls.Add($lblFinCtrl)

    $dtFinControleTechnique = [System.Windows.Forms.DateTimePicker]::new()
    $dtFinControleTechnique.Location = [System.Drawing.Point]::new($fieldLeft, $yPos)
    $dtFinControleTechnique.Size = [System.Drawing.Size]::new($fieldWidth, 25)
    $dtFinControleTechnique.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
    $dtFinControleTechnique.CustomFormat = "dd/MM/yyyy"
    $dtFinControleTechnique.ShowCheckBox = $true
    $dtFinControleTechnique.Checked = $false
    if ($Vehicule -and $Vehicule.dateFinControleTechnique) {
        $parsedFinCtrl = Convert-DbToFrDate $Vehicule.dateFinControleTechnique
        if (Test-DateFr $parsedFinCtrl) {
            $dtFinControleTechnique.Value = [datetime]::ParseExact($parsedFinCtrl, "dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture)
            $dtFinControleTechnique.Checked = $true
        }
    }
    $form.Controls.Add($dtFinControleTechnique)

    $lblFinControleTechniqueError = [System.Windows.Forms.Label]::new()
    $lblFinControleTechniqueError.Text = ""
    $lblFinControleTechniqueError.ForeColor = $script:CouleurOrangeClair
    $lblFinControleTechniqueError.Font = $smallErrorFont
    $lblFinControleTechniqueError.Location = [System.Drawing.Point]::new($fieldLeft, ($yPos + 28))
    $lblFinControleTechniqueError.Size = [System.Drawing.Size]::new($fieldWidth, 15)
    $form.Controls.Add($lblFinControleTechniqueError)
    $yPos += 55

    $btnOk = [System.Windows.Forms.Button]::new()
    Set-BtnValiderStyle -BtnValider $btnOk
    $btnOk.Location = [System.Drawing.Point]::new($fieldLeft, $yPos)
    $form.Controls.Add($btnOk)
    $form.AcceptButton = $btnOk

    $btnCancel = [System.Windows.Forms.Button]::new()
    Set-BtnQuitterStyle -BtnQuitter $btnCancel
    $btnCancel.Location = [System.Drawing.Point]::new(($fieldLeft + 120), $yPos)
    $btnCancel.Add_Click({
        param($sender, $e)
        $frm = $sender.FindForm()
        if ($null -ne $frm) { $frm.Close() }
    })
    $form.Controls.Add($btnCancel)

    $form.Tag = $null

    $txtParc.Add_Leave({
        $txtParc.Text = Normalize-Whitespace (Sanitize-TextInput $txtParc.Text)
        if (-not [string]::IsNullOrWhiteSpace($txtParc.Text)) {
            $err = Get-NumeroParcError $txtParc.Text
            if (-not $err -and (Test-DoublonParc -NumeroParc $txtParc.Text)) {
                $err = "Ce numéro de parc existe déjà !"
            }
            Set-Error -Label $lblParcError -Message $err
        }
    })

    # Pas de réécriture du Text pendant la saisie : validation seulement (évite curseur / mélange de texte).
    $txtParc.Add_TextChanged({
        $raw = $txtParc.Text
        if ([string]::IsNullOrWhiteSpace($raw)) {
            Set-Error -Label $lblParcError -Message ""
            return
        }
        $norm = Sanitize-TextInput (Normalize-Whitespace $raw)
        $err = Get-NumeroParcError $norm
        if ($err) {
            Set-Error -Label $lblParcError -Message $err
            return
        }
        Set-Error -Label $lblParcError -Message ""
    })

    $txtMarque.Add_Leave({
        $txtMarque.Text = Normalize-Whitespace (Sanitize-TextInput $txtMarque.Text)
    })

    $txtModele.Add_Leave({
        $txtModele.Text = Normalize-Whitespace (Sanitize-TextInput $txtModele.Text)
    })

    $txtImmat.Add_TextChanged({
        $msg = ""
        if (-not [string]::IsNullOrWhiteSpace($txtImmat.Text)) {
            if ($txtImmat.Text -notmatch '^[A-Za-z0-9\- ]{1,20}$') {
                $msg = "Format immatriculation invalide"
            }
        }
        Set-Error -Label $lblImmatError -Message $msg
    })

    $txtImmat.Add_Leave({
        if ([string]::IsNullOrWhiteSpace($txtImmat.Text)) { return }
        $txtImmat.Text = (Sanitize-TextInput $txtImmat.Text).Trim().ToUpperInvariant()
        Set-Error -Label $lblImmatError -Message (Get-ImmatError $txtImmat.Text)
    })

    $txtChassis.Add_TextChanged({
        $raw = $txtChassis.Text
        $msg = ""
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            if ($raw.Length -gt 17 -or $raw -notmatch '^[A-Za-z0-9]*$') {
                $msg = "VIN invalide (17 caractères)"
            }
        }
        Set-Error -Label $lblChassisError -Message $msg
    })

    $txtChassis.Add_Leave({
        if ([string]::IsNullOrWhiteSpace($txtChassis.Text)) { return }
        $txtChassis.Text = (Sanitize-TextInput $txtChassis.Text).Trim().ToUpperInvariant()
        Set-Error -Label $lblChassisError -Message (Get-ChassisError $txtChassis.Text)
    })

    $dtMise.Add_ValueChanged({ Set-Error -Label $lblMiseError -Message "" })
    $dtDateEntree.Add_ValueChanged({ Set-Error -Label $lblDateEntreeError -Message "" })
    $dtFinControleTechnique.Add_ValueChanged({ Set-Error -Label $lblFinControleTechniqueError -Message "" })
    $dtSortie.Add_ValueChanged({
        if ($dtSortie.Checked) {
            Set-Error -Label $lblDateSortieError -Message ""
        } else {
            Set-Error -Label $lblDateSortieError -Message ""
        }
    })

    $btnOk.Add_Click({
        try {
            $txtParc.Text = Normalize-Whitespace (Sanitize-TextInput $txtParc.Text)
            $txtMarque.Text = Normalize-Whitespace (Sanitize-TextInput $txtMarque.Text)
            $txtModele.Text = Normalize-Whitespace (Sanitize-TextInput $txtModele.Text)
            if (-not [string]::IsNullOrWhiteSpace($txtImmat.Text)) {
                $txtImmat.Text = (Sanitize-TextInput $txtImmat.Text).Trim().ToUpperInvariant()
            }
            if (-not [string]::IsNullOrWhiteSpace($txtChassis.Text)) {
                $txtChassis.Text = (Sanitize-TextInput $txtChassis.Text).Trim().ToUpperInvariant()
            }

            $securityValues = @($txtParc.Text, $txtImmat.Text, $txtChassis.Text, $txtMarque.Text, $txtModele.Text)
            foreach ($value in $securityValues) {
                if (-not (Test-SecuriteInput $value)) {
                    [System.Windows.Forms.MessageBox]::Show(
                        "Une entrée contient des caractères interdits.",
                        "Sécurité",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    ) | Out-Null
                    return
                }
            }

            $parcError = Get-NumeroParcError $txtParc.Text
            if ([string]::IsNullOrWhiteSpace($parcError) -and (Test-DoublonParc -NumeroParc $txtParc.Text)) {
                $parcError = "Ce numéro de parc existe déjà !"
            }

            $immatError = Get-ImmatError $txtImmat.Text
            $chassisError = Get-ChassisError $txtChassis.Text
            $miseError = ""
            $entreeError = ""
            $finCtrlError = ""

            Set-Error -Label $lblParcError -Message $parcError
            Set-Error -Label $lblImmatError -Message $immatError
            Set-Error -Label $lblChassisError -Message $chassisError
            Set-Error -Label $lblMiseError -Message $miseError
            Set-Error -Label $lblDateEntreeError -Message $entreeError
            Set-Error -Label $lblFinControleTechniqueError -Message $finCtrlError
            Set-Error -Label $lblDateSortieError -Message ""

            if ($dtSortie.Checked -and ($dtSortie.Value -lt [datetime]::ParseExact("01/01/1900", "dd/MM/yyyy", [System.Globalization.CultureInfo]::InvariantCulture))) {
                Set-Error -Label $lblDateSortieError -Message "Date de sortie invalide"
            }

            $errors = @(
                $lblParcError.Text,
                $lblImmatError.Text,
                $lblChassisError.Text,
                $lblMiseError.Text,
                $lblDateEntreeError.Text,
                $lblDateSortieError.Text,
                $lblFinControleTechniqueError.Text
            ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

            if ($errors.Count -gt 0) { return }

            $result = [PSCustomObject]@{
                numeroParc = $txtParc.Text
                immatriculation = $txtImmat.Text
                numeroChassis = $txtChassis.Text
                marque = $txtMarque.Text
                modele = $txtModele.Text
                dateMiseCirculation = $dtMise.Value.ToString("yyyy-MM-dd")
                # Compatibilité backend: on alimente aussi date_controle avec la fin de contrôle technique.
                dateControle = if ($dtFinControleTechnique.Checked) { $dtFinControleTechnique.Value.ToString("yyyy-MM-dd") } else { $null }
                dateEntree = $dtDateEntree.Value.ToString("yyyy-MM-dd")
                dateSortie = if ($dtSortie.Checked) { $dtSortie.Value.ToString("yyyy-MM-dd") } else { $null }
                dateFinControleTechnique = if ($dtFinControleTechnique.Checked) { $dtFinControleTechnique.Value.ToString("yyyy-MM-dd") } else { $null }
            }

            $form.Tag = $result
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                ("Erreur dans le formulaire véhicule:`n`n{0}" -f $_.Exception.Message),
                "Erreur",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })

    if ($Owner) {
        $form.ShowDialog($Owner) | Out-Null
    } else {
        $form.ShowDialog() | Out-Null
    }

    if ($form.DialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        return $form.Tag
    }
    return $null
}

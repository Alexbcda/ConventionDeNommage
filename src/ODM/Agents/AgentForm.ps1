# AgentForm.ps1 - Formulaire agent (envoie DateTime normal)

. "$PSScriptRoot\..\..\Database\Database.ps1"
. "$PSScriptRoot\..\..\Common\Styles.ps1"

function Show-AgentForm {
    param(
        [string]$Mode = "Ajouter",
        [pscustomobject]$Agent = $null
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$Mode un agent"
    $form.Size = New-Object System.Drawing.Size(650, 650)
    $form.StartPosition = "CenterParent"
    $form.BackColor = $CouleurGrisFond
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false

    $y = 20
    $left = 30
    $labelW = 150
    $fieldW = 350

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
    $y += 40

    # EMAIL
    Add-Label "Email :"
    $txtEmail = Add-TextBox $(if ($Agent -and $Agent.email) { $Agent.email } else { "" })
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
    $dtEntree.Format = "Short"
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
    if ($Agent -and $Agent.date_sortie) {
        $dtSortie.Checked = $true
        $dtSortie.Value = $Agent.date_sortie
    }
    $form.Controls.Add($dtSortie)
    $y += 60

    # BOUTONS
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "OK"
    $btnOk.Location = New-Object System.Drawing.Point(($left + $labelW), $y)
    $btnOk.BackColor = $CouleurCertificat
    $btnOk.ForeColor = $CouleurBlanc
    $btnOk.FlatStyle = "Flat"
    $form.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Annuler"
    $btnCancel.Location = New-Object System.Drawing.Point(($left + $labelW + 120), $y)
    $btnCancel.BackColor = $CouleurGrisFonce
    $btnCancel.ForeColor = $CouleurBlanc
    $btnCancel.FlatStyle = "Flat"
    $btnCancel.Add_Click({ $form.Close() })
    $form.Controls.Add($btnCancel)

    $result = $null

    $btnOk.Add_Click({
        $result = [PSCustomObject]@{
            nom = $txtNom.Text.Trim()
            prenom = $txtPrenom.Text.Trim()
            telephone = $txtTel.Text.Trim()
            email = $txtEmail.Text.Trim()
            type_contrat = $cmbContrat.SelectedItem.ToString()
            base_heures_semaine = [int]$numHeures.Value
            poste = $cmbPoste.SelectedItem.ToString()
            date_entree = $dtEntree.Value
            date_sortie = if ($dtSortie.Checked) { $dtSortie.Value } else { $null }
        }
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })

    $form.ShowDialog() | Out-Null
    
    if ($form.DialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
        return $result
    }
    return $null
}

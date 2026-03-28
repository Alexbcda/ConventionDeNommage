# CollecteursForm.ps1 - Formulaire d'ajout/modification avec logs

function Show-CollecteurForm {
    param(
        [string]$Mode = "Ajouter",
        [hashtable]$Collecteur = $null
    )

    Write-Host "[FORM] ========== FORMULAIRE OUVERT ==========" -ForegroundColor Magenta
    Write-Host "[FORM] Mode: $Mode" -ForegroundColor Magenta
    if ($Collecteur) {
        Write-Host "[FORM] Collecteur existant: $($Collecteur.prenom) $($Collecteur.nom)" -ForegroundColor Gray
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "$Mode un collecteur"
    $form.Size = New-Object System.Drawing.Size(450, 400)
    $form.StartPosition = "CenterParent"
    $form.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $yPos = 20

    # Prénom
    $lblPrenom = New-Object System.Windows.Forms.Label
    $lblPrenom.Text = "Prénom * :"
    $lblPrenom.Location = New-Object System.Drawing.Point(30, $yPos)
    $lblPrenom.Size = New-Object System.Drawing.Size(100, 25)
    $form.Controls.Add($lblPrenom)

    $txtPrenom = New-Object System.Windows.Forms.TextBox
    $txtPrenom.Location = New-Object System.Drawing.Point(140, $yPos)
    $txtPrenom.Size = New-Object System.Drawing.Size(250, 25)
    if ($Collecteur) { $txtPrenom.Text = $Collecteur.prenom }
    $form.Controls.Add($txtPrenom)
    $yPos += 40

    # Nom
    $lblNom = New-Object System.Windows.Forms.Label
    $lblNom.Text = "Nom * :"
    $lblNom.Location = New-Object System.Drawing.Point(30, $yPos)
    $lblNom.Size = New-Object System.Drawing.Size(100, 25)
    $form.Controls.Add($lblNom)

    $txtNom = New-Object System.Windows.Forms.TextBox
    $txtNom.Location = New-Object System.Drawing.Point(140, $yPos)
    $txtNom.Size = New-Object System.Drawing.Size(250, 25)
    if ($Collecteur) { $txtNom.Text = $Collecteur.nom }
    $form.Controls.Add($txtNom)
    $yPos += 40

    # Téléphone (optionnel)
    $lblTelephone = New-Object System.Windows.Forms.Label
    $lblTelephone.Text = "Téléphone :"
    $lblTelephone.Location = New-Object System.Drawing.Point(30, $yPos)
    $lblTelephone.Size = New-Object System.Drawing.Size(100, 25)
    $form.Controls.Add($lblTelephone)

    $txtTelephone = New-Object System.Windows.Forms.TextBox
    $txtTelephone.Location = New-Object System.Drawing.Point(140, $yPos)
    $txtTelephone.Size = New-Object System.Drawing.Size(250, 25)
    if ($Collecteur) { $txtTelephone.Text = $Collecteur.telephone }
    $form.Controls.Add($txtTelephone)
    $yPos += 40

    # Email (optionnel)
    $lblEmail = New-Object System.Windows.Forms.Label
    $lblEmail.Text = "Email :"
    $lblEmail.Location = New-Object System.Drawing.Point(30, $yPos)
    $lblEmail.Size = New-Object System.Drawing.Size(100, 25)
    $form.Controls.Add($lblEmail)

    $txtEmail = New-Object System.Windows.Forms.TextBox
    $txtEmail.Location = New-Object System.Drawing.Point(140, $yPos)
    $txtEmail.Size = New-Object System.Drawing.Size(250, 25)
    if ($Collecteur) { $txtEmail.Text = $Collecteur.email }
    $form.Controls.Add($txtEmail)
    $yPos += 40

    # Véhicule par défaut (optionnel)
    $lblVehicule = New-Object System.Windows.Forms.Label
    $lblVehicule.Text = "Véhicule :"
    $lblVehicule.Location = New-Object System.Drawing.Point(30, $yPos)
    $lblVehicule.Size = New-Object System.Drawing.Size(100, 25)
    $form.Controls.Add($lblVehicule)

    $txtVehicule = New-Object System.Windows.Forms.TextBox
    $txtVehicule.Location = New-Object System.Drawing.Point(140, $yPos)
    $txtVehicule.Size = New-Object System.Drawing.Size(250, 25)
    if ($Collecteur) { $txtVehicule.Text = $Collecteur.vehiculeDefaut }
    $form.Controls.Add($txtVehicule)
    $yPos += 60

    # Boutons
    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text = "VALIDER"
    $btnOK.Size = New-Object System.Drawing.Size(100, 35)
    $btnOK.Location = New-Object System.Drawing.Point(100, $yPos)
    $btnOK.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnOK.FlatStyle = "Flat"
    $btnOK.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $btnOK.FlatAppearance.BorderSize = 2
    $btnOK.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

    $btnOK.Add_Click({
        Write-Host "[FORM] ========== CLIC SUR VALIDER ==========" -ForegroundColor Green
        Write-Host "[FORM] Prénom saisi: '$($txtPrenom.Text)'" -ForegroundColor White
        Write-Host "[FORM] Nom saisi: '$($txtNom.Text)'" -ForegroundColor White
        Write-Host "[FORM] Téléphone saisi: '$($txtTelephone.Text)'" -ForegroundColor White
        Write-Host "[FORM] Email saisi: '$($txtEmail.Text)'" -ForegroundColor White
        Write-Host "[FORM] Véhicule saisi: '$($txtVehicule.Text)'" -ForegroundColor White
        
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
        Write-Host "[FORM] Formulaire fermé avec OK" -ForegroundColor Green
    })
    $form.Controls.Add($btnOK)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "ANNULER"
    $btnCancel.Size = New-Object System.Drawing.Size(100, 35)
    $btnCancel.Location = New-Object System.Drawing.Point(220, $yPos)
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnCancel.FlatStyle = "Flat"
    $btnCancel.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnCancel.FlatAppearance.BorderSize = 2
    $btnCancel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnCancel.Add_Click({ 
        Write-Host "[FORM] Annulation" -ForegroundColor Yellow
        $form.Close() 
    })
    $form.Controls.Add($btnCancel)

    $result = $form.ShowDialog()
    Write-Host "[FORM] Résultat du formulaire: $result" -ForegroundColor Cyan

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $donnees = @{
            prenom = $txtPrenom.Text
            nom = $txtNom.Text
            telephone = $txtTelephone.Text
            email = $txtEmail.Text
            vehiculeDefaut = $txtVehicule.Text
        }
        Write-Host "[FORM] Données retournées: $($donnees | ConvertTo-Json -Compress)" -ForegroundColor Green
        Write-Host "[FORM] ========== FIN FORMULAIRE ==========" -ForegroundColor Magenta
        return $donnees
    }
    
    Write-Host "[FORM] ========== FORMULAIRE ANNULE ==========" -ForegroundColor Yellow
    return $null
}

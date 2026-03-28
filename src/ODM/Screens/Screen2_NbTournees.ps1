# Screen2_NbTournees.ps1 - Version avec éléments alignés sur la même ligne

function Show-Screen2_NbTournees {
    param(
        $NbTournees,
        $Screen1,
        $Screen3,
        $Collecteurs,
        $Vehicules
    )
    
    Write-Host "[DEBUG] ========== SCREEN2 DÉMARRAGE ==========" -ForegroundColor Cyan
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $configPath = "C:\Users\alexa\Documents\ConventionDeNommage\src\Data\odm_config.json"
    $savedValue = $null
    $savedCheckbox = $false
    $newValue = $null
    
    # Lire la sauvegarde existante
    if (Test-Path $configPath) {
        try {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            if ($config.savedNbTournees) { $savedValue = $config.savedNbTournees }
            if ($config.saveCheckbox) { $savedCheckbox = $config.saveCheckbox }
            Write-Host "[DEBUG] Valeur sauvegardée: $savedValue, case=$savedCheckbox" -ForegroundColor Green
        } catch {
            Write-Host "[DEBUG] Erreur lecture config" -ForegroundColor Red
        }
    }
    
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Top"
    $panel.Height = 170
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    
    # Label "Nombre de tournées :"
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Nombre de tournées :"
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $lbl.Location = New-Object System.Drawing.Point(35, 28)
    $lbl.Size = New-Object System.Drawing.Size(150, 25)
    $panel.Controls.Add($lbl)
    
    # Champ de saisie (à côté du label)
    $txtTournees = New-Object System.Windows.Forms.TextBox
    $txtTournees.Size = New-Object System.Drawing.Size(80, 25)
    $txtTournees.Location = New-Object System.Drawing.Point(195, 26)
    $txtTournees.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $txtTournees.TextAlign = "Center"
    $panel.Controls.Add($txtTournees)
    
    # Bouton Valider (à côté du champ)
    $btnValider = New-Object System.Windows.Forms.Button
    $btnValider.Text = "VALIDER"
    $btnValider.Size = New-Object System.Drawing.Size(146, 45)
    $btnValider.Location = New-Object System.Drawing.Point(290, 18)
    $btnValider.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnValider.FlatStyle = "Flat"
    $btnValider.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $btnValider.FlatAppearance.BorderSize = 2
    $btnValider.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnValider.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnValider.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnValider.TabStop = $false
    
    $btnValider.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(229, 90, 42)
        $this.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $btnValider.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    $panel.Controls.Add($btnValider)
    
    # Case à cocher (en dessous)
    $chkSauvegarder = New-Object System.Windows.Forms.CheckBox
    $chkSauvegarder.Text = "Sauvegarder cette valeur"
    $chkSauvegarder.Location = New-Object System.Drawing.Point(35, 70)
    $chkSauvegarder.Size = New-Object System.Drawing.Size(200, 25)
    $chkSauvegarder.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $chkSauvegarder.Checked = $savedCheckbox
    if ($savedCheckbox) {
        $chkSauvegarder.ForeColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    } else {
        $chkSauvegarder.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    }
    $panel.Controls.Add($chkSauvegarder)
    
    # Label erreur
    $lblError = New-Object System.Windows.Forms.Label
    $lblError.Text = ""
    $lblError.ForeColor = [System.Drawing.Color]::Red
    $lblError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblError.Location = New-Object System.Drawing.Point(35, 100)
    $lblError.Size = New-Object System.Drawing.Size(400, 20)
    $panel.Controls.Add($lblError)
    
    # Variables script
    $script:txtTournees = $txtTournees
    $script:chkSauvegarder = $chkSauvegarder
    $script:savedValue = $savedValue
    $script:newValue = $null
    $script:lblError = $lblError
    $script:screen2Panel = $panel
    $script:targetScreen3 = $Screen3
    $script:targetScreen1 = $Screen1
    $script:collecteursRef = $Collecteurs
    $script:vehiculesRef = $Vehicules
    $script:configPath = $configPath
    
    # Mise à jour de l'affichage du champ
    $script:UpdateTextBox = {
        if ($script:chkSauvegarder.Checked) {
            $valueToUse = if ($script:newValue) { $script:newValue } else { $script:savedValue }
            if ($valueToUse) {
                $script:txtTournees.Text = $valueToUse.ToString()
                $script:txtTournees.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
                $script:txtTournees.ForeColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
                $script:txtTournees.ReadOnly = $true
            } else {
                $script:txtTournees.Text = ""
                $script:txtTournees.ReadOnly = $false
            }
        } else {
            $script:txtTournees.Text = ""
            $script:txtTournees.Font = New-Object System.Drawing.Font("Segoe UI", 10)
            $script:txtTournees.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
            $script:txtTournees.ReadOnly = $false
        }
    }
    
    & $script:UpdateTextBox
    
    # Événement case à cocher
    $chkSauvegarder.Add_CheckedChanged({
        if ($this.Checked) {
            $this.ForeColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
        } else {
            $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
        }
        & $script:UpdateTextBox
    })
    
    # Événement saisie
    $txtTournees.Add_TextChanged({
        if (-not $txtTournees.ReadOnly) {
            $valText = $txtTournees.Text.Trim()
            if ($valText -match '^\d+$') {
                $script:newValue = [int]$valText
            } else {
                $script:newValue = $null
            }
        }
    })
    
    # Validation : uniquement chiffres
    $txtTournees.Add_KeyPress({
        if (-not $txtTournees.ReadOnly) {
            if ($_.KeyChar -match "[^0-9]" -and $_.KeyChar -notmatch "`b") { 
                $_.Handled = $true
            }
        }
    })
    
    $btnValider.Add_Click({
        if ($script:chkSauvegarder.Checked) {
            if ($script:newValue) {
                $val = $script:newValue
            } elseif ($script:savedValue) {
                $val = $script:savedValue
            } else {
                $script:lblError.Text = "❌ Aucune valeur disponible"
                return
            }
        } else {
            $valText = $script:txtTournees.Text.Trim()
            
            if ([string]::IsNullOrWhiteSpace($valText)) {
                $script:lblError.Text = "❌ Veuillez saisir un nombre (1 à 20)"
                return
            }
            if (-not ($valText -match '^\d+$')) {
                $script:lblError.Text = "❌ Saisissez un nombre entier"
                return
            }
            $val = [int]$valText
            if ($val -lt 1 -or $val -gt 20) { 
                $script:lblError.Text = "❌ Nombre entre 1 et 20"
                return 
            }
        }
        
        if ($script:chkSauvegarder.Checked) {
            $config = @{ savedNbTournees = $val; saveCheckbox = $true }
            $config | ConvertTo-Json | Out-File -FilePath $script:configPath -Encoding utf8
            $script:savedValue = $val
            $script:newValue = $null
        } else {
            if (Test-Path $script:configPath) {
                Remove-Item $script:configPath -Force -ErrorAction SilentlyContinue
            }
        }
        
        $script:screen2Panel.Visible = $false
        if ($script:targetScreen3) {
            $script:targetScreen3.Visible = $true
            . "$PSScriptRoot\Screen3_Affectation.ps1"
            Show-Screen3_Affectation -NbTournees $val -Panel $script:targetScreen3 -Collecteurs $script:collecteursRef -Vehicules $script:vehiculesRef
        }
    })
    
    $spacer = New-Object System.Windows.Forms.Panel
    $spacer.Dock = "Fill"
    $spacer.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $panel.Controls.Add($spacer)
    
    # Boutons bas
    $bottomPanel = New-Object System.Windows.Forms.Panel
    $bottomPanel.Dock = "Bottom"
    $bottomPanel.Height = 60
    $bottomPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    
    $btnRetour = New-Object System.Windows.Forms.Button
    $btnRetour.Text = "RETOUR"
    $btnRetour.Size = New-Object System.Drawing.Size(140, 40)
    $btnRetour.Location = New-Object System.Drawing.Point(35, 10)
    $btnRetour.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnRetour.FlatStyle = "Flat"
    $btnRetour.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnRetour.FlatAppearance.BorderSize = 2
    $btnRetour.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnRetour.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnRetour.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnRetour.TabStop = $false
    
    $btnRetour.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
        $this.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $btnRetour.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    
    $btnRetour.Add_Click({
        $script:screen2Panel.Visible = $false
        if ($script:targetScreen1) { 
            $script:targetScreen1.Visible = $true
        }
    })
    $bottomPanel.Controls.Add($btnRetour)
    
    $btnQuitter = New-Object System.Windows.Forms.Button
    $btnQuitter.Text = "QUITTER"
    $btnQuitter.Size = New-Object System.Drawing.Size(140, 40)
    $btnQuitter.Location = New-Object System.Drawing.Point(195, 10)
    $btnQuitter.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnQuitter.FlatStyle = "Flat"
    $btnQuitter.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnQuitter.FlatAppearance.BorderSize = 2
    $btnQuitter.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnQuitter.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnQuitter.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnQuitter.TabStop = $false
    
    $btnQuitter.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
        $this.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $btnQuitter.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    
    $btnQuitter.Add_Click({ 
        [System.Windows.Forms.Application]::Exit() 
    })
    $bottomPanel.Controls.Add($btnQuitter)
    
    $panel.Controls.Add($bottomPanel)
    
    return $panel
}














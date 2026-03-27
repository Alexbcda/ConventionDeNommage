# Screen2_NbTournees.ps1 - Écran pour saisir le nombre de tournees avec logs

function Show-Screen2_NbTournees {
    param(
        $NbTournees,
        $Screen1,
        $Screen3,
        $Collecteurs,
        $Vehicules
    )
    
    Write-Host "[DEBUG] ========== SCREEN2 DÉMARRAGE ==========" -ForegroundColor Cyan
    Write-Host "[DEBUG] Screen1 reçu: $($Screen1 -ne $null)" -ForegroundColor Yellow
    Write-Host "[DEBUG] Screen3 reçu: $($Screen3 -ne $null)" -ForegroundColor Yellow
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $configPath = "C:\Users\alexa\Documents\ConventionDeNommage\src\Data\odm_config.json"
    $savedValue = $null
    $savedCheckbox = $false
    
    if (Test-Path $configPath) {
        try {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            if ($config.savedNbTournees) { $savedValue = $config.savedNbTournees }
            if ($config.saveCheckbox) { $savedCheckbox = $config.saveCheckbox }
            Write-Host "[DEBUG] Config chargée: valeur=$savedValue, checkbox=$savedCheckbox" -ForegroundColor Green
        } catch { Write-Host "[DEBUG] Erreur lecture config" -ForegroundColor Red }
    } else {
        Write-Host "[DEBUG] Aucun fichier de sauvegarde" -ForegroundColor Yellow
    }
    
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Top"
    $panel.Height = 200
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Nombre de tournées :"
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lbl.Location = New-Object System.Drawing.Point(35, 25)
    $lbl.Size = New-Object System.Drawing.Size(150, 25)
    $panel.Controls.Add($lbl)
    
    $txtTournees = New-Object System.Windows.Forms.TextBox
    $txtTournees.Size = New-Object System.Drawing.Size(80, 25)
    $txtTournees.Location = New-Object System.Drawing.Point(195, 23)
    $txtTournees.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $txtTournees.Text = ""
    $txtTournees.TextAlign = "Center"
    $panel.Controls.Add($txtTournees)
    
    $chkSauvegarder = New-Object System.Windows.Forms.CheckBox
    $chkSauvegarder.Text = "Sauvegarder cette valeur"
    $chkSauvegarder.Location = New-Object System.Drawing.Point(35, 70)
    $chkSauvegarder.Size = New-Object System.Drawing.Size(200, 25)
    $chkSauvegarder.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $chkSauvegarder.Checked = $savedCheckbox
    $panel.Controls.Add($chkSauvegarder)
    
    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Text = ""
    $lblInfo.ForeColor = [System.Drawing.Color]::FromArgb(27, 91, 74)
    $lblInfo.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblInfo.Location = New-Object System.Drawing.Point(35, 100)
    $lblInfo.Size = New-Object System.Drawing.Size(400, 20)
    $panel.Controls.Add($lblInfo)
    
    $lblError = New-Object System.Windows.Forms.Label
    $lblError.Text = ""
    $lblError.ForeColor = [System.Drawing.Color]::Red
    $lblError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblError.Location = New-Object System.Drawing.Point(35, 125)
    $lblError.Size = New-Object System.Drawing.Size(400, 20)
    $panel.Controls.Add($lblError)
    
    if ($savedCheckbox -and $savedValue) {
        $txtTournees.Text = $savedValue.ToString()
        $txtTournees.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Italic)
        $txtTournees.ForeColor = [System.Drawing.Color]::Gray
        $lblInfo.Text = "💾 Valeur sauvegardée: $savedValue tournée(s)"
        Write-Host "[DEBUG] Valeur sauvegardée affichée: $savedValue" -ForegroundColor Green
    } else {
        $txtTournees.Text = ""
        $lblInfo.Text = "⏳ Champ vide - saisissez un nombre"
        Write-Host "[DEBUG] Champ vide" -ForegroundColor Gray
    }
    
    $script:screen2Panel = $panel
    $script:targetScreen3 = $Screen3
    $script:targetScreen1 = $Screen1
    $script:collecteursRef = $Collecteurs
    $script:vehiculesRef = $Vehicules
    $script:txtTourneesRef = $txtTournees
    $script:chkSauvegarderRef = $chkSauvegarder
    $script:lblErrorRef = $lblError
    $script:lblInfoRef = $lblInfo
    $script:configPath = $configPath
    
    Write-Host "[DEBUG] targetScreen1 = $($targetScreen1 -ne $null)" -ForegroundColor Yellow
    Write-Host "[DEBUG] targetScreen3 = $($targetScreen3 -ne $null)" -ForegroundColor Yellow
    
    # Événement FOCUS
    $txtTournees.Add_GotFocus({
        if ($this.Text -and $this.Font.Italic) {
            $this.Text = ""
            $this.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)
            $this.ForeColor = [System.Drawing.Color]::Black
            $script:lblInfoRef.Text = "✏️ Nouvelle saisie en cours"
            Write-Host "[DEBUG] Focus: valeur italique effacée" -ForegroundColor Gray
        }
        $script:lblErrorRef.Text = ""
    })
    
    $txtTournees.Add_KeyPress({
        if ($_.KeyChar -match "[^0-9]" -and $_.KeyChar -notmatch "`b") { 
            $_.Handled = $true
            Write-Host "[DEBUG] Caractère non numérique bloqué: '$($_.KeyChar)'" -ForegroundColor Red
        }
    })
    
    # Bouton Valider
    $btnValider = New-Object System.Windows.Forms.Button
    $btnValider.Text = "VALIDER"
    $btnValider.Size = New-Object System.Drawing.Size(146, 45)
    $btnValider.Location = New-Object System.Drawing.Point(260, 60)
    $btnValider.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnValider.FlatStyle = "Flat"
    $btnValider.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $btnValider.FlatAppearance.BorderSize = 2
    $btnValider.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnValider.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnValider.Cursor = [System.Windows.Forms.Cursors]::Hand
    
    $btnValider.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(229, 90, 42)
        $this.BackColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $btnValider.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    
    $btnValider.Add_Click({
        Write-Host "[DEBUG] ========== BOUTON VALIDER (SCREEN2) ==========" -ForegroundColor Green
        $valText = $script:txtTourneesRef.Text.Trim()
        Write-Host "[DEBUG] Valeur saisie: '$valText'" -ForegroundColor Yellow
        
        if ([string]::IsNullOrWhiteSpace($valText)) {
            $script:lblErrorRef.Text = "❌ Veuillez saisir un nombre (1 à 20)"
            Write-Host "[DEBUG] Champ vide" -ForegroundColor Red
            return
        }
        if (-not ($valText -match '^\d+$')) {
            $script:lblErrorRef.Text = "❌ Saisissez un nombre entier"
            Write-Host "[DEBUG] Format invalide" -ForegroundColor Red
            return
        }
        
        $val = [int]$valText
        if ($val -lt 1) { 
            $script:lblErrorRef.Text = "❌ Minimum 1"
            Write-Host "[DEBUG] Valeur < 1" -ForegroundColor Red
            return 
        }
        if ($val -gt 20) { 
            $script:lblErrorRef.Text = "❌ Maximum 20"
            Write-Host "[DEBUG] Valeur > 20" -ForegroundColor Red
            return 
        }
        
        Write-Host "[DEBUG] ✅ Nombre valide: $val" -ForegroundColor Green
        
        if ($script:chkSauvegarderRef.Checked) {
            $config = @{ savedNbTournees = $val; saveCheckbox = $true }
            $config | ConvertTo-Json | Out-File -FilePath $script:configPath -Encoding utf8
            $script:lblInfoRef.Text = "💾 Sauvegardé: $val"
            Write-Host "[DEBUG] ✅ Sauvegardé: $val" -ForegroundColor Green
        } else {
            $script:lblInfoRef.Text = "⏳ Temporaire: $val"
            Write-Host "[DEBUG] ⏳ Temporaire: $val" -ForegroundColor Yellow
        }
        
        Write-Host "[DEBUG] Transition vers Screen3 avec $val tournée(s)" -ForegroundColor Cyan
        $script:screen2Panel.Visible = $false
        if ($script:targetScreen3) {
            $script:targetScreen3.Visible = $true
            Write-Host "[DEBUG] Screen3 affiché" -ForegroundColor Green
            . "$PSScriptRoot\Screen3_Affectation.ps1"
            Show-Screen3_Affectation -NbTournees $val -Panel $script:targetScreen3 -Collecteurs $script:collecteursRef -Vehicules $script:vehiculesRef
        } else {
            Write-Host "[DEBUG] ❌ targetScreen3 est null" -ForegroundColor Red
        }
    })
    $panel.Controls.Add($btnValider)
    
    $spacer = New-Object System.Windows.Forms.Panel
    $spacer.Dock = "Fill"
    $spacer.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $panel.Controls.Add($spacer)
    
    # Boutons bas
    $bottomPanel = New-Object System.Windows.Forms.Panel
    $bottomPanel.Dock = "Bottom"
    $bottomPanel.Height = 60
    $bottomPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    
    # Bouton RETOUR (vers Screen1)
    $btnRetour = New-Object System.Windows.Forms.Button
    $btnRetour.Text = "RETOUR"
    $btnRetour.Size = New-Object System.Drawing.Size(140, 40)
    $btnRetour.Location = New-Object System.Drawing.Point(35, 10)
    $btnRetour.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnRetour.FlatStyle = "Flat"
    $btnRetour.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $btnRetour.FlatAppearance.BorderSize = 2
    $btnRetour.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnRetour.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    
    $btnRetour.Add_Click({
        Write-Host "[DEBUG] ========== RETOUR (SCREEN2 -> SCREEN1) ==========" -ForegroundColor Yellow
        Write-Host "[DEBUG] targetScreen1 = $($script:targetScreen1 -ne $null)" -ForegroundColor Yellow
        
        $script:screen2Panel.Visible = $false
        if ($script:targetScreen1) { 
            $script:targetScreen1.Visible = $true
            Write-Host "[DEBUG] Screen1 affiché" -ForegroundColor Green
        } else {
            Write-Host "[DEBUG] ❌ targetScreen1 est null" -ForegroundColor Red
        }
    })
    $bottomPanel.Controls.Add($btnRetour)
    
    # Bouton QUITTER
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
    
    $btnQuitter.Add_Click({ 
        Write-Host "[DEBUG] QUITTER" -ForegroundColor Red
        [System.Windows.Forms.Application]::Exit() 
    })
    $bottomPanel.Controls.Add($btnQuitter)
    
    $panel.Controls.Add($bottomPanel)
    
    Write-Host "[DEBUG] ========== SCREEN2 TERMINÉ ==========" -ForegroundColor Cyan
    return $panel
}

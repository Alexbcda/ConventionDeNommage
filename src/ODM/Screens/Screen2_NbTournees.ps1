# Screen2_NbTournees.ps1 - Écran pour saisir le nombre de tournees

function Show-Screen2_NbTournees {
    param(
        $NbTournees,
        $Screen1,
        $Screen3,
        $Collecteurs,
        $Vehicules
    )
    
    Write-Host "`n[DEBUG] ==================== SCREEN2 - DÉMARRAGE ====================" -ForegroundColor Cyan
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $configPath = "C:\Users\alexa\Documents\ConventionDeNommage\src\Data\odm_config.json"
    
    # Initialisation
    $savedValue = $null
    $savedCheckbox = $false
    
    # Lire la configuration sauvegardée avec gestion d'erreur
    if (Test-Path $configPath) {
        try {
            $content = Get-Content $configPath -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($content)) {
                $config = $content | ConvertFrom-Json -ErrorAction Stop
                if ($config.savedNbTournees -ne $null) { $savedValue = $config.savedNbTournees }
                if ($config.saveCheckbox -ne $null) { $savedCheckbox = $config.saveCheckbox }
                Write-Host "[LOG][CONFIG] Chargé: valeur=$savedValue, checkbox=$savedCheckbox" -ForegroundColor Green
            }
        } catch {
            Write-Host "[LOG][CONFIG] Erreur lecture fichier, utilisation valeurs par défaut" -ForegroundColor Yellow
            $savedValue = $null
            $savedCheckbox = $false
        }
    } else {
        Write-Host "[LOG][CONFIG] Aucun fichier de sauvegarde" -ForegroundColor Yellow
    }
    
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Top"
    $panel.Height = 200
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    
    # Label
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Nombre de tournées :"
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lbl.Location = New-Object System.Drawing.Point(35, 25)
    $lbl.Size = New-Object System.Drawing.Size(150, 25)
    $panel.Controls.Add($lbl)
    
    # Champ de saisie
    $txtTournees = New-Object System.Windows.Forms.TextBox
    $txtTournees.Size = New-Object System.Drawing.Size(80, 25)
    $txtTournees.Location = New-Object System.Drawing.Point(195, 23)
    $txtTournees.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $txtTournees.Text = ""
    $txtTournees.TextAlign = "Center"
    $panel.Controls.Add($txtTournees)
    
    # Case à cocher
    $chkSauvegarder = New-Object System.Windows.Forms.CheckBox
    $chkSauvegarder.Text = "Sauvegarder cette valeur"
    $chkSauvegarder.Location = New-Object System.Drawing.Point(35, 70)
    $chkSauvegarder.Size = New-Object System.Drawing.Size(200, 25)
    $chkSauvegarder.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $chkSauvegarder.Checked = $savedCheckbox
    $panel.Controls.Add($chkSauvegarder)
    
    # Label info
    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Text = ""
    $lblInfo.ForeColor = [System.Drawing.Color]::FromArgb(27, 91, 74)
    $lblInfo.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Italic)
    $lblInfo.Location = New-Object System.Drawing.Point(35, 100)
    $lblInfo.Size = New-Object System.Drawing.Size(400, 20)
    $panel.Controls.Add($lblInfo)
    
    # Label erreur
    $lblError = New-Object System.Windows.Forms.Label
    $lblError.Text = ""
    $lblError.ForeColor = [System.Drawing.Color]::Red
    $lblError.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblError.Location = New-Object System.Drawing.Point(35, 125)
    $lblError.Size = New-Object System.Drawing.Size(400, 20)
    $panel.Controls.Add($lblError)
    
    # Appliquer l'affichage initial (si sauvegarde valide)
    if ($savedValue -and $savedCheckbox) {
        $txtTournees.Text = $savedValue.ToString()
        $txtTournees.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Italic)
        $txtTournees.ForeColor = [System.Drawing.Color]::Gray
        $lblInfo.Text = "💾 Valeur sauvegardée: $savedValue tournée(s)"
        Write-Host "[LOG][AFFICHAGE] Valeur sauvegardée affichée: $savedValue" -ForegroundColor Green
    } else {
        $txtTournees.Text = ""
        $lblInfo.Text = "⏳ Champ vide - saisissez un nombre"
        Write-Host "[LOG][AFFICHAGE] Champ vide" -ForegroundColor Green
    }
    
    # Sauvegarder les références
    $script:lblErrorRef = $lblError
    $script:lblInfoRef = $lblInfo
    $script:txtTourneesRef = $txtTournees
    $script:chkSauvegarderRef = $chkSauvegarder
    $script:configPath = $configPath
    
    # Événement FOCUS
    $txtTournees.Add_GotFocus({
        if ($this.Text -and $this.Font.Italic) {
            $this.Text = ""
            $this.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)
            $this.ForeColor = [System.Drawing.Color]::Black
            $script:lblInfoRef.Text = "✏️ Nouvelle saisie en cours"
        }
        $script:lblErrorRef.Text = ""
    })
    
    # Validation chiffres
    $txtTournees.Add_KeyPress({
        if ($_.KeyChar -match "[^0-9]" -and $_.KeyChar -notmatch "`b") { 
            $_.Handled = $true
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
    
    # Variables navigation
    $script:screen2Panel = $panel
    $script:targetScreen3 = $Screen3
    $script:targetScreen1 = $Screen1
    $script:collecteursRef = $Collecteurs
    $script:vehiculesRef = $Vehicules
    
    $btnValider.Add_Click({
        $valText = $script:txtTourneesRef.Text.Trim()
        
        if ([string]::IsNullOrWhiteSpace($valText)) {
            $script:lblErrorRef.Text = "❌ Veuillez saisir un nombre (1 à 20)"
            return
        }
        
        if (-not ($valText -match '^\d+$')) {
            $script:lblErrorRef.Text = "❌ Saisissez un nombre entier"
            return
        }
        
        $val = [int]$valText
        
        if ($val -lt 1) { 
            $script:lblErrorRef.Text = "❌ Minimum 1"
            return 
        }
        if ($val -gt 20) { 
            $script:lblErrorRef.Text = "❌ Maximum 20"
            return 
        }
        
        Write-Host "[LOG] ✅ Nombre valide: $val" -ForegroundColor Green
        
        if ($script:chkSauvegarderRef.Checked) {
            $config = @{ savedNbTournees = $val; saveCheckbox = $true }
            $config | ConvertTo-Json | Out-File -FilePath $script:configPath -Encoding utf8
            $script:lblInfoRef.Text = "💾 Sauvegardé: $val"
            Write-Host "[LOG] ✅ Sauvegardé: $val" -ForegroundColor Green
        } else {
            $script:lblInfoRef.Text = "⏳ Temporaire: $val"
            Write-Host "[LOG] ⏳ Temporaire: $val" -ForegroundColor Yellow
        }
        
        $script:screen2Panel.Visible = $false
        if ($script:targetScreen3) {
            $script:targetScreen3.Visible = $true
            . "$PSScriptRoot\Screen3_Affectation.ps1"
            Show-Screen3_Affectation -NbTournees $val -Panel $script:targetScreen3 -Collecteurs $script:collecteursRef -Vehicules $script:vehiculesRef
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
    $btnRetour.Cursor = [System.Windows.Forms.Cursors]::Hand
    
    $btnRetour.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(229, 90, 42)
        $this.BackColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $btnRetour.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    
    $btnRetour.Add_Click({
        $script:txtTourneesRef.Text = ""
        $script:txtTourneesRef.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)
        $script:txtTourneesRef.ForeColor = [System.Drawing.Color]::Black
        $script:screen2Panel.Visible = $false
        if ($script:targetScreen1) { $script:targetScreen1.Visible = $true }
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
    
    $btnQuitter.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
        $this.BackColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $btnQuitter.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    $btnQuitter.Add_Click({ [System.Windows.Forms.Application]::Exit() })
    $bottomPanel.Controls.Add($btnQuitter)
    
    $panel.Controls.Add($bottomPanel)
    
    return $panel
}

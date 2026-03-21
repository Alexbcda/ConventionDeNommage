# Interface graphique avec calendrier
function Start-GUI {
    param([string]$FichierPDF)
    
    . "$PSScriptRoot\Config.ps1"
    . "$PSScriptRoot\Functions\Rename.ps1"
    
    if (-not $FichierPDF -or -not (Test-Path $FichierPDF)) { exit }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Convention de nommage"
    $form.Size = New-Object System.Drawing.Size(560, 300)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.BackColor = $formBackColor
    $form.Font = $font
    $form.Topmost = $true

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.Padding = New-Object System.Windows.Forms.Padding(20, 10, 20, 10)
    $form.Controls.Add($panel)

    $margeGauche = 35
    $largeurPlaceholder = 470

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point($margeGauche, 40)
    $textBox.Size = New-Object System.Drawing.Size($largeurPlaceholder, 35)
    $textBox.Font = $font
    $textBox.Text = $placeholder
    $textBox.ForeColor = $placeholderColor
    $textBox.Tag = $placeholder
    $panel.Controls.Add($textBox)

    $script:estEnModePlaceholder = $true
    $script:texteUtilisateur = ""
    $script:formulaireCharge = $false
    $script:dateForcee = $false
    $script:dateSelectionnee = Get-Date

    function Get-DateParDefaut {
        $aujourdhui = Get-Date
        $jourSemaine = $aujourdhui.DayOfWeek
        if ($jourSemaine -eq "Monday") { return $aujourdhui.AddDays(-3) }
        else { return $aujourdhui.AddDays(-1) }
    }

    function Set-PlaceholderMode {
        param($textBox, $activer)
        if ($activer) {
            $textBox.Text = $textBox.Tag
            $textBox.ForeColor = $placeholderColor
            $script:estEnModePlaceholder = $true
        } else {
            if ($script:texteUtilisateur -ne "") { $textBox.Text = $script:texteUtilisateur }
            else { $textBox.Text = "" }
            $textBox.ForeColor = $textBoxForeColor
            $script:estEnModePlaceholder = $false
        }
    }

    $textBox.Add_Enter({
        if (-not $script:formulaireCharge) { return }
        if ($script:estEnModePlaceholder) {
            $this.Text = ""
            $this.ForeColor = $textBoxForeColor
            $script:estEnModePlaceholder = $false
        } else { $this.SelectAll() }
    })

    $textBox.Add_Leave({
        if (-not $script:formulaireCharge) { return }
        if (-not $script:estEnModePlaceholder) { $script:texteUtilisateur = $this.Text }
        if ([string]::IsNullOrWhiteSpace($this.Text)) {
            Set-PlaceholderMode -textBox $this -activer $true
            $script:texteUtilisateur = ""
        }
    })

    $boldFont = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)

    # Définition des couleurs
    $couleurFond = [System.Drawing.ColorTranslator]::FromHtml("#FAF9F7")
    $couleurTexte = [System.Drawing.ColorTranslator]::FromHtml("#272727")
    $couleurTexteSurvol = [System.Drawing.Color]::White

    # Couleurs CERTIFICAT
    $couleurBordureCertif = [System.Drawing.ColorTranslator]::FromHtml("#E26E2A")
    $couleurBordureSurvolCertif = [System.Drawing.ColorTranslator]::FromHtml("#AF470B")
    $couleurFondSurvolCertif = [System.Drawing.ColorTranslator]::FromHtml("#E26E2A")

    # Couleurs PLANNER
    $couleurBordurePlanner = [System.Drawing.ColorTranslator]::FromHtml("#50ABF2")
    $couleurBordureSurvolPlanner = [System.Drawing.ColorTranslator]::FromHtml("#1A6AA8")
    $couleurFondSurvolPlanner = [System.Drawing.ColorTranslator]::FromHtml("#50ABF2")

    # Couleurs FRANCE TRAVAIL
    $couleurBordureFT = [System.Drawing.ColorTranslator]::FromHtml("#1B5B4A")
    $couleurBordureSurvolFT = [System.Drawing.ColorTranslator]::FromHtml("#1A9F7B")
    $couleurFondSurvolFT = [System.Drawing.ColorTranslator]::FromHtml("#1B5B4A")

    # --- BOUTON CERTIFICAT ---
    $btnCertif = New-Object System.Windows.Forms.Button
    $btnCertif.Text = "CERTIFICAT"
    $btnCertif.Location = New-Object System.Drawing.Point($margeGauche, 90)
    $btnCertif.Size = New-Object System.Drawing.Size(146, 50)
    $btnCertif.BackColor = $couleurFond
    $btnCertif.FlatStyle = "Flat"
    $btnCertif.FlatAppearance.BorderColor = $couleurBordureCertif
    $btnCertif.FlatAppearance.BorderSize = 2
    $btnCertif.ForeColor = $couleurTexte
    $btnCertif.Font = $boldFont
    $btnCertif.TextAlign = "MiddleCenter"
    $panel.Controls.Add($btnCertif)

    # --- BOUTON PLANNER ---
    $btnPlanner = New-Object System.Windows.Forms.Button
    $btnPlanner.Text = "PLANNER"
    $btnPlanner.Location = New-Object System.Drawing.Point(($margeGauche + 146 + 15), 90)
    $btnPlanner.Size = New-Object System.Drawing.Size(146, 50)
    $btnPlanner.BackColor = $couleurFond
    $btnPlanner.FlatStyle = "Flat"
    $btnPlanner.FlatAppearance.BorderColor = $couleurBordurePlanner
    $btnPlanner.FlatAppearance.BorderSize = 2
    $btnPlanner.ForeColor = $couleurTexte
    $btnPlanner.Font = $boldFont
    $btnPlanner.TextAlign = "MiddleCenter"
    $panel.Controls.Add($btnPlanner)

    # --- BOUTON FRANCE TRAVAIL ---
    $btnFranceTravail = New-Object System.Windows.Forms.Button
    $btnFranceTravail.Text = "FRANCE TRAVAIL"
    $btnFranceTravail.Location = New-Object System.Drawing.Point(($margeGauche + 2*(146 + 15)), 90)
    $btnFranceTravail.Size = New-Object System.Drawing.Size(146, 50)
    $btnFranceTravail.BackColor = $couleurFond
    $btnFranceTravail.FlatStyle = "Flat"
    $btnFranceTravail.FlatAppearance.BorderColor = $couleurBordureFT
    $btnFranceTravail.FlatAppearance.BorderSize = 2
    $btnFranceTravail.ForeColor = $couleurTexte
    $btnFranceTravail.Font = $boldFont
    $btnFranceTravail.TextAlign = "MiddleCenter"
    $panel.Controls.Add($btnFranceTravail)

    # --- EFFETS DE SURVOL ---
    $btnCertif.Add_MouseEnter({ 
        $this.FlatAppearance.BorderColor = $couleurBordureSurvolCertif
        $this.BackColor = $couleurFondSurvolCertif
        $this.ForeColor = $couleurTexteSurvol
    })
    $btnCertif.Add_MouseLeave({ 
        $this.FlatAppearance.BorderColor = $couleurBordureCertif
        $this.BackColor = $couleurFond
        $this.ForeColor = $couleurTexte
    })

    $btnPlanner.Add_MouseEnter({ 
        $this.FlatAppearance.BorderColor = $couleurBordureSurvolPlanner
        $this.BackColor = $couleurFondSurvolPlanner
        $this.ForeColor = $couleurTexteSurvol
    })
    $btnPlanner.Add_MouseLeave({ 
        $this.FlatAppearance.BorderColor = $couleurBordurePlanner
        $this.BackColor = $couleurFond
        $this.ForeColor = $couleurTexte
    })

    $btnFranceTravail.Add_MouseEnter({ 
        $this.FlatAppearance.BorderColor = $couleurBordureSurvolFT
        $this.BackColor = $couleurFondSurvolFT
        $this.ForeColor = $couleurTexteSurvol
    })
    $btnFranceTravail.Add_MouseLeave({ 
        $this.FlatAppearance.BorderColor = $couleurBordureFT
        $this.BackColor = $couleurFond
        $this.ForeColor = $couleurTexte
    })

    # --- CALENDRIER ---
    $calLabel = New-Object System.Windows.Forms.Label
    $calLabel.Text = "Forcer la date :"
    $calLabel.Location = New-Object System.Drawing.Point($margeGauche, 165)
    $calLabel.Size = New-Object System.Drawing.Size(120, 20)
    $calLabel.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $panel.Controls.Add($calLabel)

    $datePicker = New-Object System.Windows.Forms.DateTimePicker
    $datePicker.Location = New-Object System.Drawing.Point($margeGauche, 190)
    $datePicker.Size = New-Object System.Drawing.Size(220, 25)
    $datePicker.Format = "Short"
    $datePicker.Font = New-Object System.Drawing.Font("Arial", 9)
    $dateParDefaut = Get-DateParDefaut
    $datePicker.Value = $dateParDefaut
    $panel.Controls.Add($datePicker)

    $forceLabel = New-Object System.Windows.Forms.Label
    $forceLabel.Location = New-Object System.Drawing.Point(($margeGauche + 230), 192)
    $forceLabel.Size = New-Object System.Drawing.Size(220, 20)
    $forceLabel.Font = New-Object System.Drawing.Font("Arial", 8, [System.Drawing.FontStyle]::Bold)
    $forceLabel.ForeColor = [System.Drawing.Color]::Red
    $forceLabel.Text = ""
    $panel.Controls.Add($forceLabel)

    $script:dateSelectionnee = $datePicker.Value

    $datePicker.Add_ValueChanged({
        $script:dateSelectionnee = $this.Value
        if ($this.Value.Date -ne $dateParDefaut.Date) {
            $script:dateForcee = $true
            $forceLabel.Text = "Mode force: $($this.Value.ToString('dd/MM/yyyy'))"
        } else {
            $script:dateForcee = $false
            $forceLabel.Text = ""
        }
    })

    # --- FONCTION DE RENOMMAGE LOCALE ---
    function Invoke-RenameAction {
        param([string]$Type)
        
        $nom = $textBox.Text.Trim()
        if ($nom -eq $placeholder) { $nom = "" }
        
        if ([string]::IsNullOrWhiteSpace($nom)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Veuillez renseigner le point de collecte", 
                "Champ obligatoire", 
                [System.Windows.Forms.MessageBoxButtons]::OK, 
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            return
        }
        
        $dateUtilisee = if ($script:dateForcee) { $script:dateSelectionnee } else { $dateParDefaut }
        $ok = Rename-PDF -Type $Type -FichierPDF $FichierPDF -TextBox $textBox -Placeholder $placeholder -DateSelectionnee $dateUtilisee -EstModePlaceholder $false
        
        if ($ok -eq $true) {
            $form.Close()
        }
    }

    # --- ACTIONS DES BOUTONS ---
    $btnCertif.Add_Click({ Invoke-RenameAction -Type "certificat" })
    $btnPlanner.Add_Click({ Invoke-RenameAction -Type "planner" })
    $btnFranceTravail.Add_Click({ Invoke-RenameAction -Type "francetravail" })

    $textBox.Add_KeyUp({
        if ($_.KeyCode -eq "Enter" -and $script:formulaireCharge) {
            Invoke-RenameAction -Type "certificat"
        }
    })

    # --- SHOWN : Initialisation et focus sur le bouton ---
    $form.Add_Shown({
        Set-PlaceholderMode -textBox $textBox -activer $true
        $form.BeginInvoke([Action]{
            Start-Sleep -Milliseconds 500
            $script:formulaireCharge = $true
            $btnCertif.Focus()
        })
    })

    [System.Windows.Forms.Application]::EnableVisualStyles()
    [System.Windows.Forms.Application]::Run($form)
}
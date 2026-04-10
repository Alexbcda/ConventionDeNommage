# Orchestrateur.ps1 - Gestion des tournées

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ============================================================
# STYLES
# ============================================================

$CouleurOrange = [System.Drawing.Color]::FromArgb(226, 110, 42)
$CouleurBlanc = [System.Drawing.Color]::FromArgb(255, 255, 255)
$CouleurGrisFonce = [System.Drawing.Color]::FromArgb(39, 39, 39)
$CouleurGrisFond = [System.Drawing.Color]::FromArgb(248, 249, 250)

$PoliceTitre = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$PoliceNormal = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Regular)
$PoliceBouton = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

# ============================================================
# VARIABLES GLOBALES
# ============================================================

$script:DateAffectation = $null
$script:NbTournees = 5
$script:form = $null
$script:datePanel = $null
$script:tourneesPanel = $null

# ============================================================
# FONCTIONS METIER
# ============================================================

function Save-DateAffectation {
    param([string]$Date)
    $script:DateAffectation = $Date
    Write-Host "[METIER-Date] Date sauvegardée: $Date" -ForegroundColor Green
}

function Save-NbTournees {
    param([int]$NbTournees)
    $script:NbTournees = $NbTournees
    Write-Host "[METIER-NbTournees] Nombre de tournées sauvegardé: $NbTournees" -ForegroundColor Green
}

# ============================================================
# CREATION DU PANEL DATE
# ============================================================

function CreateDatePanel {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = $CouleurGrisFond
    $panel.Name = "DatePanel"
    
    # Titre
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Affectation des tournées"
    $lblTitle.Font = $PoliceTitre
    $lblTitle.ForeColor = $CouleurOrange
    $lblTitle.Location = New-Object System.Drawing.Point(50, 30)
    $lblTitle.Size = New-Object System.Drawing.Size(400, 40)
    $panel.Controls.Add($lblTitle)
    
    # Bouton Quitter
    $btnQuitter = New-Object System.Windows.Forms.Button
    $btnQuitter.Text = "QUITTER"
    $btnQuitter.Size = New-Object System.Drawing.Size(100, 40)
    $btnQuitter.Location = New-Object System.Drawing.Point(480, 30)
    $btnQuitter.BackColor = $CouleurBlanc
    $btnQuitter.FlatStyle = "Flat"
    $btnQuitter.FlatAppearance.BorderColor = $CouleurGrisFonce
    $btnQuitter.FlatAppearance.BorderSize = 2
    $btnQuitter.ForeColor = $CouleurGrisFonce
    $btnQuitter.Font = $PoliceBouton
    $btnQuitter.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnQuitter.Add_Click({
        [System.Windows.Forms.Application]::Exit()
    })
    $panel.Controls.Add($btnQuitter)
    
    # Label
    $lblChoisir = New-Object System.Windows.Forms.Label
    $lblChoisir.Text = "Choisir une date :"
    $lblChoisir.Font = $PoliceNormal
    $lblChoisir.ForeColor = $CouleurGrisFonce
    $lblChoisir.Location = New-Object System.Drawing.Point(50, 90)
    $lblChoisir.Size = New-Object System.Drawing.Size(150, 35)
    $panel.Controls.Add($lblChoisir)
    
    # DateTimePicker
    $datePicker = New-Object System.Windows.Forms.DateTimePicker
    $datePicker.Format = "Short"
    $datePicker.Value = Get-Date
    $datePicker.Size = New-Object System.Drawing.Size(150, 35)
    $datePicker.Location = New-Object System.Drawing.Point(200, 90)
    $datePicker.Font = $PoliceNormal
    $panel.Controls.Add($datePicker)
    
    # Bouton Valider
    $btnValider = New-Object System.Windows.Forms.Button
    $btnValider.Text = "VALIDER"
    $btnValider.Size = New-Object System.Drawing.Size(100, 40)
    $btnValider.Location = New-Object System.Drawing.Point(480, 90)
    $btnValider.BackColor = $CouleurBlanc
    $btnValider.FlatStyle = "Flat"
    $btnValider.FlatAppearance.BorderColor = $CouleurOrange
    $btnValider.FlatAppearance.BorderSize = 2
    $btnValider.ForeColor = $CouleurGrisFonce
    $btnValider.Font = $PoliceBouton
    $btnValider.Cursor = [System.Windows.Forms.Cursors]::Hand
    
    $btnValider.Add_Click({
        $selectedDate = $datePicker.Value.ToShortDateString()
        Save-DateAffectation -Date $selectedDate
        Write-Host "[UI-Date] Date validée: $selectedDate" -ForegroundColor Green
        
        # Navigation vers le panel tournees
        $form = $this.FindForm()
        $form.Controls["DatePanel"].Visible = $false
        $form.Controls["TourneesPanel"].Visible = $true
    })
    
    $panel.Controls.Add($btnValider)
    
    return $panel
}

# ============================================================
# CREATION DU PANEL TOURNEES
# ============================================================

function CreateTourneesPanel {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = $CouleurGrisFond
    $panel.Name = "TourneesPanel"
    
    # Titre
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Affectation des tournées"
    $lblTitle.Font = $PoliceTitre
    $lblTitle.ForeColor = $CouleurOrange
    $lblTitle.Location = New-Object System.Drawing.Point(50, 30)
    $lblTitle.Size = New-Object System.Drawing.Size(400, 40)
    $panel.Controls.Add($lblTitle)
    
    # Bouton RETOUR
    $btnRetour = New-Object System.Windows.Forms.Button
    $btnRetour.Text = "RETOUR"
    $btnRetour.Size = New-Object System.Drawing.Size(100, 40)
    $btnRetour.Location = New-Object System.Drawing.Point(370, 30)
    $btnRetour.BackColor = $CouleurBlanc
    $btnRetour.FlatStyle = "Flat"
    $btnRetour.FlatAppearance.BorderColor = $CouleurGrisFonce
    $btnRetour.FlatAppearance.BorderSize = 2
    $btnRetour.ForeColor = $CouleurGrisFonce
    $btnRetour.Font = $PoliceBouton
    $btnRetour.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnRetour.Add_Click({
        $form = $this.FindForm()
        $form.Controls["TourneesPanel"].Visible = $false
        $form.Controls["DatePanel"].Visible = $true
    })
    $panel.Controls.Add($btnRetour)
    
    # Bouton QUITTER
    $btnQuitter = New-Object System.Windows.Forms.Button
    $btnQuitter.Text = "QUITTER"
    $btnQuitter.Size = New-Object System.Drawing.Size(100, 40)
    $btnQuitter.Location = New-Object System.Drawing.Point(480, 30)
    $btnQuitter.BackColor = $CouleurBlanc
    $btnQuitter.FlatStyle = "Flat"
    $btnQuitter.FlatAppearance.BorderColor = $CouleurGrisFonce
    $btnQuitter.FlatAppearance.BorderSize = 2
    $btnQuitter.ForeColor = $CouleurGrisFonce
    $btnQuitter.Font = $PoliceBouton
    $btnQuitter.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnQuitter.Add_Click({
        [System.Windows.Forms.Application]::Exit()
    })
    $panel.Controls.Add($btnQuitter)
    
    # Label
    $lblInstruction = New-Object System.Windows.Forms.Label
    $lblInstruction.Text = "Indiquer le nombre de tournées :"
    $lblInstruction.Font = $PoliceNormal
    $lblInstruction.ForeColor = $CouleurGrisFonce
    $lblInstruction.Location = New-Object System.Drawing.Point(50, 90)
    $lblInstruction.Size = New-Object System.Drawing.Size(250, 35)
    $panel.Controls.Add($lblInstruction)
    
    # NumericUpDown
    $numTournees = New-Object System.Windows.Forms.NumericUpDown
    $numTournees.Minimum = 1
    $numTournees.Maximum = 50
    $numTournees.Value = 5
    $numTournees.Size = New-Object System.Drawing.Size(80, 35)
    $numTournees.Location = New-Object System.Drawing.Point(300, 90)
    $numTournees.Font = $PoliceNormal
    $numTournees.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center
    $panel.Controls.Add($numTournees)
    
    # Bouton VALIDER
    $btnValider = New-Object System.Windows.Forms.Button
    $btnValider.Text = "VALIDER"
    $btnValider.Size = New-Object System.Drawing.Size(100, 40)
    $btnValider.Location = New-Object System.Drawing.Point(480, 90)
    $btnValider.BackColor = $CouleurBlanc
    $btnValider.FlatStyle = "Flat"
    $btnValider.FlatAppearance.BorderColor = $CouleurOrange
    $btnValider.FlatAppearance.BorderSize = 2
    $btnValider.ForeColor = $CouleurGrisFonce
    $btnValider.Font = $PoliceBouton
    $btnValider.Cursor = [System.Windows.Forms.Cursors]::Hand
    
    $btnValider.Add_Click({
        $nbTournees = $numTournees.Value
        Save-NbTournees -NbTournees $nbTournees
        Write-Host "[UI-Tournees] Nombre de tournées: $nbTournees" -ForegroundColor Green
        [System.Windows.Forms.MessageBox]::Show("Nombre de tournées sauvegardé : $nbTournees", "Succès")
    })
    
    $panel.Controls.Add($btnValider)
    
    return $panel
}

# ============================================================
# MAIN
# ============================================================

# Création du formulaire
$form = New-Object System.Windows.Forms.Form
$form.Text = "Gestion des tournées"
$form.Size = New-Object System.Drawing.Size(650, 400)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

# Création des panels
$datePanel = CreateDatePanel
$tourneesPanel = CreateTourneesPanel

# Ajout des panels au formulaire
$form.Controls.Add($datePanel)
$form.Controls.Add($tourneesPanel)

# Affichage initial
$datePanel.Visible = $true
$tourneesPanel.Visible = $false

# Affichage du formulaire
$form.ShowDialog()
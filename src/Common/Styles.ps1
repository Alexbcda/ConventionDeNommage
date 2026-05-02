# ============================================
# STYLES.PS1 - VERSION CORRIGEE
# ============================================

# COULEURS
$script:CouleurOrange = [System.Drawing.Color]::FromArgb(226, 110, 42)
$script:CouleurOrangeClair = [System.Drawing.Color]::FromArgb(255, 140, 60)
$script:CouleurOrangeFonce = [System.Drawing.Color]::FromArgb(229, 90, 42)
$script:CouleurCertificat = [System.Drawing.Color]::FromArgb(175, 71, 11)
$script:CouleurCertificatClair = [System.Drawing.Color]::FromArgb(200, 100, 50)
$script:CouleurBleu = [System.Drawing.Color]::FromArgb(26, 106, 168)
$script:CouleurVert = [System.Drawing.Color]::FromArgb(26, 159, 123)
$script:CouleurBlanc = [System.Drawing.Color]::FromArgb(255, 255, 255)
$script:CouleurGrisClair = [System.Drawing.Color]::FromArgb(245, 245, 245)
$script:CouleurGrisFonce = [System.Drawing.Color]::FromArgb(39, 39, 39)
$script:CouleurGrisFond = [System.Drawing.Color]::FromArgb(248, 249, 250)
$script:CouleurLigneAlternee = [System.Drawing.Color]::FromArgb(255, 245, 235)
$script:CouleurSelection = [System.Drawing.Color]::FromArgb(229, 90, 42)

# POLICES
$script:PoliceTitre1 = [System.Drawing.Font]::new("Arial", 20, [System.Drawing.FontStyle]::Bold)
$script:PoliceTitre2 = [System.Drawing.Font]::new("Arial", 16, [System.Drawing.FontStyle]::Bold)
$script:PoliceTitre3 = [System.Drawing.Font]::new("Arial", 12, [System.Drawing.FontStyle]::Bold)
$script:PoliceNormal = [System.Drawing.Font]::new("Arial", 10, [System.Drawing.FontStyle]::Regular)
$script:PoliceBouton = [System.Drawing.Font]::new("Arial", 10, [System.Drawing.FontStyle]::Bold)

# Titres / textes secondaires des panneaux de gestion (Agents, Véhicules) — source unique
$script:PoliceTitreGestionFenetre = [System.Drawing.Font]::new("Arial", 18, [System.Drawing.FontStyle]::Bold)
$script:PoliceLabelSecondaireFenetre = [System.Drawing.Font]::new("Arial", 10, [System.Drawing.FontStyle]::Regular)
$script:CouleurTexteSecondairePanel = [System.Drawing.Color]::FromArgb(60, 60, 60)
if (Get-Command Convert-ToUiText -ErrorAction SilentlyContinue) {
    $script:TitrePanelAgents = Convert-ToUiText -Text 'Gestion des agents'
    $script:TitrePanelVehicules = Convert-ToUiText -Text 'Gestion des véhicules'
}
else {
    $script:TitrePanelAgents = 'Gestion des agents'
    $script:TitrePanelVehicules = 'Gestion des véhicules'
}

# FONCTION BOUTON AVEC BORDURE (CORRIGEE)
function Set-BtnBorderStyle {
    param(
        $Button,
        [string]$Text,
        $BorderColor,
        [int]$Width = 100,
        [int]$Height = 40
    )
    
    # Valeur par défaut si BorderColor est null
    if ($BorderColor -eq $null) {
        $BorderColor = $script:CouleurOrange
    }
    
    if (Get-Command Convert-ToUiText -ErrorAction SilentlyContinue) {
        $Button.Text = Convert-ToUiText -Text $Text
    }
    else {
        $Button.Text = $Text
    }
    $Button.Size = [System.Drawing.Size]::new($Width, $Height)
    $Button.BackColor = $script:CouleurBlanc
    $Button.FlatStyle = "Flat"
    $Button.FlatAppearance.BorderColor = $BorderColor
    $Button.FlatAppearance.BorderSize = 2
    $Button.FlatAppearance.MouseOverBackColor = $BorderColor
    $Button.FlatAppearance.MouseDownBackColor = $BorderColor
    $Button.ForeColor = $script:CouleurGrisFonce
    $Button.Font = $script:PoliceBouton
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand

    # ✅ STOCKAGE SAFE
    $Button.AccessibleDescription = "CN_BORDER_COLOR"
    $Button.Tag = $BorderColor

    # ✅ EVENTS SAFE
    $Button.Add_MouseEnter({
        if ($this.Tag -is [System.Drawing.Color]) {
            $this.BackColor = $this.Tag
        }
        elseif ($this.FlatAppearance.BorderColor -is [System.Drawing.Color]) {
            $this.BackColor = $this.FlatAppearance.BorderColor
        }
        elseif ($this.Tag -is [string]) {
            Write-Warning "[BUG] BackColor guard: Tag contient une string non-couleur sur control '$($this.Name)'"
        }
        $this.ForeColor = $script:CouleurBlanc
    })

    $Button.Add_MouseLeave({
        $this.BackColor = $script:CouleurBlanc
        $this.ForeColor = $script:CouleurGrisFonce
    })
}

# BOUTONS SPECIFIQUES
function Set-BtnValiderStyle {
    param($BtnValider)
    Set-BtnBorderStyle -Button $BtnValider -Text "VALIDER" -BorderColor $script:CouleurCertificat -Width 100 -Height 40
}

function Set-BtnRetourStyle {
    param($BtnRetour)
    Set-BtnBorderStyle -Button $BtnRetour -Text "← RETOUR" -BorderColor $script:CouleurCertificat -Width 100 -Height 40
}

function Set-BtnQuitterStyle {
    param($BtnQuitter)
    Set-BtnBorderStyle -Button $BtnQuitter -Text "✖ QUITTER" -BorderColor $script:CouleurGrisFonce -Width 100 -Height 40
}

function Set-BtnCertificatStyle {
    param($BtnCertificat)
    Set-BtnBorderStyle -Button $BtnCertificat -Text "CERTIFICAT" -BorderColor $script:CouleurCertificat -Width 130 -Height 45
}

function Set-BtnPlannerStyle {
    param($BtnPlanner)
    Set-BtnBorderStyle -Button $BtnPlanner -Text "PLANNER" -BorderColor $script:CouleurBleu -Width 130 -Height 45
}

function Set-BtnFranceTravailStyle {
    param($BtnFranceTravail)
    Set-BtnBorderStyle -Button $BtnFranceTravail -Text "FRANCE TRAVAIL" -BorderColor $script:CouleurVert -Width 140 -Height 45
}

function Set-BtnAjouterStyle {
    param($BtnAjouter)
    Set-BtnBorderStyle -Button $BtnAjouter -Text "➕ AJOUTER" -BorderColor $script:CouleurCertificat -Width 180 -Height 45
}

# GRILLE
function Set-GridStyle {
    param($Grid)
    $Grid.BackgroundColor = $script:CouleurBlanc
    $Grid.BorderStyle = "FixedSingle"
    $Grid.AllowUserToAddRows = $false
    $Grid.AllowUserToDeleteRows = $false
    $Grid.RowHeadersVisible = $false
    $Grid.SelectionMode = "FullRowSelect"
    $Grid.DefaultCellStyle.SelectionBackColor = $script:CouleurSelection
    $Grid.DefaultCellStyle.SelectionForeColor = $script:CouleurBlanc
}

function Apply-AlternateRowColor {
    param($Grid, $RowIndex, $Row)
    if ($RowIndex % 2 -eq 1) {
        $Grid.Rows[$Row].DefaultCellStyle.BackColor = $script:CouleurLigneAlternee
    }
}

# CONSTANTES DE LAYOUT
$script:LayoutMargin = 12
$script:LayoutPadding = 50
$script:LayoutSpacingSmall = 5
$script:LayoutSpacingNormal = 10
$script:LayoutSpacingLarge = 20

$script:LayoutTitleX = 0
$script:LayoutTitleY = 0
$script:LayoutInfoY = 60
$script:LayoutFieldY = 110
$script:LayoutButtonsY = 170
$script:LayoutCalendarY = 240

# CONSTANTES FENETRE
$script:TailleFenetreLargeur = 1400
$script:TailleFenetreHauteur = 800
$script:TailleFenetreMiniLargeur = 1000
$script:TailleFenetreMiniHauteur = 650

Write-Host "[STYLES] Version corrigee" -ForegroundColor Green


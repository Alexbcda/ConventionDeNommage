# ============================================
# UIHelpers.ps1 - Fonctions utilitaires UI
# ============================================

# ============================================
# CONSTANTES DE LAYOUT
# ============================================
$script:LayoutMargin = 12
$script:LayoutPadding = 50
$script:LayoutSpacingSmall = 5
$script:LayoutSpacingNormal = 10
$script:LayoutSpacingLarge = 20

# Positions standard
$script:LayoutTitleX = 0
$script:LayoutTitleY = 0
$script:LayoutInfoY = 60
$script:LayoutFieldY = 110
$script:LayoutButtonsY = 170
$script:LayoutCalendarY = 240

# ============================================
# AJOUTER UN TITRE DE SECTION
# ============================================
function Add-SectionTitle {
    param(
        [System.Windows.Forms.Panel]$Container,
        [string]$Text,
        [int]$Y,
        [int]$X = 0
    )
    
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Font = $script:PoliceTitre2
    $label.ForeColor = $script:CouleurGrisFonce
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size(400, 35)
    $Container.Controls.Add($label)
    
    return $Y + 45
}

# ============================================
# AJOUTER UNE LIGNE DE SEPARATION
# ============================================
function Add-SeparatorLine {
    param(
        [System.Windows.Forms.Panel]$Container,
        [int]$Y,
        [int]$Width = 600,
        [int]$X = 0
    )
    
    $line = New-Object System.Windows.Forms.Label
    $line.Text = ""
    $line.BorderStyle = "Fixed3D"
    $line.Location = New-Object System.Drawing.Point($X, $Y)
    $line.Size = New-Object System.Drawing.Size($Width, 2)
    $Container.Controls.Add($line)
    
    return $Y + 10
}

# ============================================
# AJOUTER UNE INFO BULLE
# ============================================
function Add-Tooltip {
    param(
        [System.Windows.Forms.Control]$Control,
        [string]$Text
    )
    
    $tooltip = New-Object System.Windows.Forms.ToolTip
    $tooltip.SetToolTip($Control, $Text)
    $tooltip.InitialDelay = 500
    $tooltip.ReshowDelay = 100
    
    return $tooltip
}

# ============================================
# AJOUTER UN PANEL AVEC BORDURE
# ============================================
function Add-BorderedPanel {
    param(
        [System.Windows.Forms.Panel]$Container,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [string]$Title = ""
    )
    
    $groupBox = New-Object System.Windows.Forms.GroupBox
    $groupBox.Text = $Title
    $groupBox.Location = New-Object System.Drawing.Point($X, $Y)
    $groupBox.Size = New-Object System.Drawing.Size($Width, $Height)
    $groupBox.Font = $script:PoliceTitre3
    $groupBox.ForeColor = $script:CouleurGrisFonce
    $Container.Controls.Add($groupBox)
    
    return $groupBox
}

# ============================================
# CENTRER UN FORMULAIRE
# ============================================
function Center-Form {
    param([System.Windows.Forms.Form]$Form)
    
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $Form.StartPosition = "Manual"
    $Form.Location = New-Object System.Drawing.Point(
        ($screen.Width - $Form.Width) / 2,
        ($screen.Height - $Form.Height) / 2
    )
}

# ============================================
# AJOUTER UNE GRILLE AVEC STYLE
# ============================================
function Add-StyledGridView {
    param(
        [System.Windows.Forms.Panel]$Container,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height,
        [ref]$OutputVariable
    )
    
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Location = New-Object System.Drawing.Point($X, $Y)
    $grid.Size = New-Object System.Drawing.Size($Width, $Height)
    $grid.BackgroundColor = $script:CouleurBlanc
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.RowHeadersVisible = $false
    $grid.SelectionMode = "FullRowSelect"
    $grid.BorderStyle = "FixedSingle"
    
    $grid.DefaultCellStyle.SelectionBackColor = $script:CouleurSelection
    $grid.DefaultCellStyle.SelectionForeColor = $script:CouleurBlanc
    
    $Container.Controls.Add($grid)
    $OutputVariable.Value = $grid
    
    return $grid
}

Write-Host "[UIHELPERS] Utilitaires UI charges" -ForegroundColor Green

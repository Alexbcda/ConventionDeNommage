<#
WinFormsHelpers.ps1 - Helpers UI reutilisables pour panels CRUD WinForms.

- Fonctions pures UI (aucun acces DB, aucune logique metier)
- Extraites de la duplication entre AgentPanel.ps1 et VehiculesPanel.ps1
#>

function New-CrudDataGrid {
    <#
    .SYNOPSIS
        Cree un DataGridView preconfigure avec le style standard du projet.
    .PARAMETER Name
        Nom du controle (ex: "AgentsGrid", "VehiculesGrid").
    .PARAMETER ColumnDefs
        Tableau de hashtables : @( @{ Name='Nom'; Header='Nom'; Width=150 }, ... )
        Les colonnes "Edit" et "Delete" sont automatiquement centrees.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [array]$ColumnDefs
    )

    $grid = [System.Windows.Forms.DataGridView]::new()
    $grid.Name = $Name
    $grid.Location = [System.Drawing.Point]::new(20, 110)
    $grid.Size = [System.Drawing.Size]::new(1100, 560)
    $grid.Anchor = "Top,Bottom,Left,Right"
    $grid.AllowUserToAddRows = $false
    $grid.RowHeadersVisible = $false
    $grid.BackgroundColor = [System.Drawing.Color]::White
    $grid.SelectionMode = "FullRowSelect"
    $grid.BorderStyle = "FixedSingle"
    $grid.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $grid.AutoSizeColumnsMode = "None"
    $grid.AutoGenerateColumns = $false
    $grid.AllowUserToResizeColumns = $true

    if (Get-Command Set-GridStyle -ErrorAction SilentlyContinue) {
        Set-GridStyle -Grid $grid
    }

    try {
        $prop = $grid.GetType().GetProperty(
            "DoubleBuffered",
            [System.Reflection.BindingFlags] "Instance,NonPublic"
        )
        if ($prop) { $prop.SetValue($grid, $true, $null) }
    } catch {}

    $grid.DefaultCellStyle.BackColor = $script:CouleurGrisClair
    $grid.AlternatingRowsDefaultCellStyle.BackColor = $script:CouleurLigneAlternee
    $grid.DefaultCellStyle.SelectionBackColor = $script:CouleurSelection
    $grid.DefaultCellStyle.SelectionForeColor = $script:CouleurBlanc
    $grid.ColumnHeadersHeightSizeMode = "AutoSize"
    $grid.ColumnHeadersDefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::False

    $grid.Columns.Clear()
    foreach ($col in $ColumnDefs) {
        $null = $grid.Columns.Add($col.Name, $col.Header)
        $grid.Columns[$col.Name].Width = $col.Width
        if ($col.Name -in @("Edit", "Delete")) {
            $grid.Columns[$col.Name].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleCenter
        }
    }

    return $grid
}

function Test-CellClickGuards {
    <#
    .SYNOPSIS
        Valide les parametres d'un evenement CellClick/CellDoubleClick.
        Retourne la DataGridViewRow si valide, $null sinon.
    #>
    param(
        $Sender,
        $EventArgs
    )

    if (-not $Sender) { return $null }
    if (-not $EventArgs) { return $null }
    if ($EventArgs.RowIndex -lt 0) { return $null }
    if ($EventArgs.ColumnIndex -lt 0) { return $null }
    if ($EventArgs.RowIndex -ge $Sender.Rows.Count) { return $null }

    $row = $Sender.Rows[$EventArgs.RowIndex]
    if (-not $row) { return $null }
    if ($null -eq $row.Tag) { return $null }

    return $row
}

function Show-CrudErrorDialog {
    <#
    .SYNOPSIS
        Affiche une MessageBox d'erreur standardisee pour les operations CRUD.
    .PARAMETER OperationLabel
        Description de l'operation (ex: "l'ajout de l'agent", "la modification du vehicule").
    .PARAMETER ErrorMessage
        Message d'exception.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$OperationLabel,
        [Parameter(Mandatory)]
        [string]$ErrorMessage
    )

    [System.Windows.Forms.MessageBox]::Show(
        ("Erreur lors de {0}:`n`n{1}" -f $OperationLabel, $ErrorMessage),
        "Erreur",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

function New-CrudPanelHeader {
    <#
    .SYNOPSIS
        Cree le header standard d'un panel CRUD : titre + label historique + checkbox + bouton Ajouter.
        Retourne un hashtable avec les controles crees.
    .PARAMETER Title
        Texte du titre (ex: $script:TitrePanelAgents).
    .PARAMETER HistoriqueLabel
        Texte du label historique (ex: "Afficher l'historique des agents").
    .PARAMETER CheckboxName
        Nom du controle checkbox (ex: "chkHistoriqueAgents").
    .PARAMETER ButtonText
        Texte du bouton Ajouter (ex: "+ AJOUTER UN AGENT").
    .PARAMETER ButtonWidth
        Largeur du bouton (defaut 200).
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Title,
        [Parameter(Mandatory)]
        [string]$HistoriqueLabel,
        [Parameter(Mandatory)]
        [string]$CheckboxName,
        [Parameter(Mandatory)]
        [string]$ButtonText,
        [int]$ButtonWidth = 200
    )

    $mainPanel = [System.Windows.Forms.Panel]::new()
    $mainPanel.Dock = "Fill"
    $mainPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $mainPanel.Padding = [System.Windows.Forms.Padding]::new(20)

    $lblTitle = [System.Windows.Forms.Label]::new()
    $lblTitle.Text = $Title
    $lblTitle.Font = $script:PoliceTitreGestionFenetre
    $lblTitle.ForeColor = $script:CouleurOrange
    $lblTitle.Location = [System.Drawing.Point]::new(20, 20)
    $lblTitle.Size = [System.Drawing.Size]::new(400, 50)
    $mainPanel.Controls.Add($lblTitle)

    $lblHist = [System.Windows.Forms.Label]::new()
    $lblHist.Text = $HistoriqueLabel
    $lblHist.Font = $script:PoliceLabelSecondaireFenetre
    $lblHist.ForeColor = $script:CouleurTexteSecondairePanel
    $lblHist.Location = [System.Drawing.Point]::new(20, 77)
    $lblHist.Size = [System.Drawing.Size]::new(260, 20)
    $mainPanel.Controls.Add($lblHist)

    $chk = [System.Windows.Forms.CheckBox]::new()
    $chk.Name = $CheckboxName
    $chk.Location = [System.Drawing.Point]::new(285, 78)
    $chk.Size = [System.Drawing.Size]::new(20, 20)
    $chk.Checked = $false
    $chk.Cursor = [System.Windows.Forms.Cursors]::Hand
    $mainPanel.Controls.Add($chk)

    $btn = [System.Windows.Forms.Button]::new()
    $btn.Text = $ButtonText
    $btn.Location = [System.Drawing.Point]::new(900, 20)
    $btn.Size = [System.Drawing.Size]::new($ButtonWidth, 45)
    if (Get-Command Set-BtnAjouterStyle -ErrorAction SilentlyContinue) {
        Set-BtnAjouterStyle -BtnAjouter $btn
    }
    $btn.Text = $ButtonText
    $btn.Size = [System.Drawing.Size]::new($ButtonWidth, 45)
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $mainPanel.Controls.Add($btn)

    return @{
        Panel    = $mainPanel
        Checkbox = $chk
        Button   = $btn
    }
}

function Set-CrudGridRowStyle {
    <#
    .SYNOPSIS
        Applique le style actif/inactif standard sur une ligne de grille.
    #>
    param(
        [Parameter(Mandatory)] $Grid,
        [Parameter(Mandatory)] [int]$RowIndex,
        [Parameter(Mandatory)] [bool]$IsActif,
        [System.Drawing.Font]$NormalFont = $null
    )

    if (-not $NormalFont) {
        $baseFont = $script:PoliceNormal
        if (-not $baseFont) {
            $baseFont = if ($Grid.DefaultCellStyle.Font) { $Grid.DefaultCellStyle.Font } else { $Grid.Font }
        }
        $NormalFont = [System.Drawing.Font]::new($baseFont, ([System.Drawing.FontStyle]::Regular))
    }

    $Grid.Rows[$RowIndex].DefaultCellStyle.Font = $NormalFont
    if (-not $IsActif) {
        $Grid.Rows[$RowIndex].DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 150)
    }

    try { Apply-AlternateRowColor -Grid $Grid -RowIndex $RowIndex -Row $RowIndex } catch {}
}

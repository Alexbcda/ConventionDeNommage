# AboutPanel.ps1 — Onglet « À propos » (attribution + BUILDINFO)

. (Join-Path $PSScriptRoot '..\..\Common\Styles.ps1')

function script:Get-AboutInstallRoot {
    # ...\src\ODM\Outils -> install root (parent de src)
    $srcRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    return (Split-Path -Parent $srcRoot)
}

function script:Get-AboutAppVersion {
    if (Get-Command Get-CurrentVersion -ErrorAction SilentlyContinue) {
        $v = Get-CurrentVersion
        if (-not [string]::IsNullOrWhiteSpace($v) -and $v -ne '0.0.0') { return $v.Trim() }
    }
    $vf = Join-Path (Get-AboutInstallRoot) 'version.txt'
    if (Test-Path -LiteralPath $vf) {
        return (Get-Content -LiteralPath $vf -Raw).Trim()
    }
    return 'n/a'
}

function script:Get-AboutBuildInfoText {
    $path = Join-Path (Get-AboutInstallRoot) 'BUILDINFO.txt'
    if (-not (Test-Path -LiteralPath $path)) {
        return "BUILDINFO.txt introuvable ($path)."
    }
    return (Get-Content -LiteralPath $path -Raw).Trim()
}

function Show-AboutPanel {
    $um = Join-Path $PSScriptRoot '..\..\Core\UpdateManager.ps1'
    if (-not (Get-Command Get-CurrentVersion -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $um)) {
        . $um
    }

    $panel = [System.Windows.Forms.Panel]::new()
    $panel.Dock = 'Fill'
    $panel.BackColor = $script:CouleurGrisFond
    $panel.Padding = [System.Windows.Forms.Padding]::new(20)
    $panel.AutoScroll = $true

    $version = Get-AboutAppVersion
    $body = @"
ASSISTANT
Conception et développement : Alexandre Breso
Version : $version

Logiciel conçu et développé à titre personnel.
Mis à disposition pour un usage professionnel interne sous licence / autorisation d'utilisation.
© 2026 Alexandre Breso. Tous droits réservés.
"@

    $lblTitle = [System.Windows.Forms.Label]::new()
    $lblTitle.Text = 'À propos'
    $lblTitle.Font = $script:PoliceTitreGestionFenetre
    $lblTitle.ForeColor = $script:CouleurOrange
    $lblTitle.Location = [System.Drawing.Point]::new(0, 0)
    $lblTitle.Size = [System.Drawing.Size]::new(700, 40)
    $panel.Controls.Add($lblTitle)

    $lblBody = [System.Windows.Forms.Label]::new()
    $lblBody.Text = $body.Trim()
    $lblBody.Font = $script:PoliceNormal
    $lblBody.ForeColor = $script:CouleurTexteSecondairePanel
    $lblBody.Location = [System.Drawing.Point]::new(0, 50)
    $lblBody.Size = [System.Drawing.Size]::new(720, 160)
    $panel.Controls.Add($lblBody)

    $lblBuildTitle = [System.Windows.Forms.Label]::new()
    $lblBuildTitle.Text = 'Informations de build (BUILDINFO)'
    $lblBuildTitle.Font = $script:PoliceTitre3
    $lblBuildTitle.ForeColor = $script:CouleurOrange
    $lblBuildTitle.Location = [System.Drawing.Point]::new(0, 230)
    $lblBuildTitle.Size = [System.Drawing.Size]::new(700, 28)
    $panel.Controls.Add($lblBuildTitle)

    $txtBuild = [System.Windows.Forms.TextBox]::new()
    $txtBuild.Multiline = $true
    $txtBuild.ReadOnly = $true
    $txtBuild.ScrollBars = 'Vertical'
    $txtBuild.Font = [System.Drawing.Font]::new('Consolas', 9)
    $txtBuild.Location = [System.Drawing.Point]::new(0, 265)
    $txtBuild.Size = [System.Drawing.Size]::new(720, 120)
    $txtBuild.Text = Get-AboutBuildInfoText
    $panel.Controls.Add($txtBuild)

    return $panel
}
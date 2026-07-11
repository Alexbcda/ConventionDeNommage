# Audit headless du bouton Connexion SharePoint (sans lancer Main.ps1)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
$srcRoot = Join-Path $repoRoot 'src'
. (Join-Path $srcRoot 'Common\CnsSharePointUI.ps1')

function Test-ConnectButtonAudit {
    param(
        [string]$Status,
        [string]$Message = 'test audit'
    )

    $form = [System.Windows.Forms.Form]::new()
    $form.Size = [System.Drawing.Size]::new(1200, 200)
    $panel = [System.Windows.Forms.Panel]::new()
    $panel.Dock = 'Fill'
    $panel.Padding = [System.Windows.Forms.Padding]::new(20)
    $form.Controls.Add($panel)

    $spUi = New-SharePointStatusControls -Parent $panel -Location ([System.Drawing.Point]::new(0, 0)) -Size ([System.Drawing.Size]::new(1100, 96))
    $form.CreateControl()
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()

    Update-SharePointUI -State $Status -Labels @{
        FileNameLabel = $spUi.FileName
        StatusLabel   = $spUi.Status
        DateLabel     = $spUi.Date
        Icon          = $spUi.Icon
        StatusDot     = $spUi.StatusDot
        LocalMode     = $spUi.LocalMode
        Connect       = $spUi.Connect
    } -Buttons $spUi.Buttons -Message $Message

    $grp = $spUi.GroupBox
    $btn = $spUi.Connect
    $showExpected = $Status -in @('Expired', 'Offline', 'Denied', 'Error', 'WamBlocked', 'Connecting')
    $rightEdge = $btn.Location.X + $btn.Width
    $inBounds = ($btn.Location.X -ge 0) -and ($btn.Location.Y -ge 0) -and ($rightEdge -le $grp.ClientSize.Width)

    [pscustomobject]@{
        Status            = $Status
        VisibleAttendu    = $showExpected
        BtnVisible        = $btn.Visible
        BtnEnabled        = $btn.Enabled
        GrpVisible        = $grp.Visible
        GrpEnabled        = $grp.Enabled
        BtnLocation       = "$($btn.Location.X),$($btn.Location.Y)"
        BtnSize           = "$($btn.Width)x$($btn.Height)"
        GrpClientSize     = "$($grp.ClientSize.Width)x$($grp.ClientSize.Height)"
        InBounds          = $inBounds
        ForeColor         = $btn.ForeColor.Name
        BackColor         = $btn.BackColor.Name
        WhiteOnWhite      = ($btn.ForeColor -eq $script:CouleurBlanc -and $btn.BackColor -eq $script:CouleurBlanc)
    }

    $form.Dispose()
}

Write-Host "`n=== AUDIT BOUTON CONNEXION (headless) ===" -ForegroundColor Cyan
$results = @()
foreach ($st in @('Offline', 'Connecting', 'Connected', 'Error', 'Expired', 'Denied')) {
    $results += Test-ConnectButtonAudit -Status $st
}

$results | Format-Table -AutoSize

$offline = $results | Where-Object Status -eq 'Offline'
Write-Host "`n--- Reponses aux questions audit ---" -ForegroundColor Yellow
Write-Host "1. GroupBox visible/enabled (Offline): $($offline.GrpVisible) / $($offline.GrpEnabled)"
Write-Host "2. Bouton dans limites parent (Offline): $($offline.InBounds) @ $($offline.BtnLocation) client=$($offline.GrpClientSize)"
Write-Host "3. Couleurs (Offline): Fore=$($offline.ForeColor) Back=$($offline.BackColor) blanc-sur-blanc=$($offline.WhiteOnWhite)"
Write-Host "4. Enabled (Offline): $($offline.BtnEnabled)"
Write-Host "5. Visible attendu vs reel (Offline): attendu=$($offline.VisibleAttendu) reel=$($offline.BtnVisible)"

$connecting = $results | Where-Object Status -eq 'Connecting'
Write-Host "`nNOTE: Etat Connecting au demarrage -> Visible=$($connecting.BtnVisible) (bouton masque volontairement)" -ForegroundColor Magenta

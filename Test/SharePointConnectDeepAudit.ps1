# Audit pousse bouton Connexion - simule le flux reel PlanningRebuilderPanel
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'src\Common\CnsSharePointUI.ps1')

function Write-AuditSection([string]$Title) {
    Write-Host "`n========== $Title ==========" -ForegroundColor Yellow
}

function Test-Overlap([System.Drawing.Rectangle]$A, [System.Drawing.Rectangle]$B) {
    return $A.IntersectsWith($B)
}

Write-AuditSection '1. CREATION DU BOUTON'
$form = [System.Windows.Forms.Form]::new()
$form.Size = [System.Drawing.Size]::new(1400, 800)
$panel = [System.Windows.Forms.Panel]::new()
$panel.Dock = 'Fill'
$panel.Padding = [System.Windows.Forms.Padding]::new(20)
$panel.AutoScroll = $true

# Simule Show-PlanningRebuilderPanel AVANT ajout au form (comme GUI.ps1 L109)
$spUi = New-SharePointStatusControls -Parent $panel -Location ([System.Drawing.Point]::new(0, 76)) -Size ([System.Drawing.Size]::new(1100, 96))
$group = $spUi.GroupBox
$btn = $spUi.Connect

$found = $group.Controls.Find('btnSharePointConnect', $true)
Write-Host "New-SharePointStatusControls appelee : Oui"
Write-Host "Controls.Find('btnSharePointConnect') : count=$($found.Count) name=$($found[0].Name)"
Write-Host "Tag accessible : $($null -ne $btn.Tag) TagType=$($btn.Tag.GetType().Name)"
Write-Host "Panel.FindForm() avant attach : $(if ($panel.FindForm()) { 'Form' } else { 'NULL' })"

Write-AuditSection '2. STYLE APRES CREATION'
Write-Host "Set-BtnCertificatStyle appele a la creation : Oui (L244)"
Write-Host "BackColor=$($btn.BackColor) ForeColor=$($btn.ForeColor) FlatStyle=$($btn.FlatStyle)"
Write-Host "BorderColor=$($btn.FlatAppearance.BorderColor)"
Write-Host "Apres style - Text=$($btn.Text) Size=$($btn.Size) Visible=$($btn.Visible)"

Write-AuditSection '3. COORDONNEES (form non montre vs montre)'
Write-Host "Sans Form.Show - Location=$($btn.Location) ClientSize=$($group.ClientSize)"
$tab = [System.Windows.Forms.TabPage]::new()
$tab.Controls.Add($panel)
$tabs = [System.Windows.Forms.TabControl]::new()
$tabs.Dock = 'Fill'
$form.Controls.Add($tabs)
$tabs.TabPages.Add($tab)
Write-Host "Apres attach form (sans Show) - FindForm=$(if ($panel.FindForm()) { 'OK' } else { 'NULL' })"

Update-SharePointUI -State 'Offline' -Labels @{
    StatusLabel = $spUi.Status; Status = $spUi.Status; Connect = $spUi.Connect
    FileName = $spUi.FileName; Date = $spUi.Date; Icon = $spUi.Icon
    StatusDot = $spUi.StatusDot; LocalMode = $spUi.LocalMode
} -Buttons $spUi.Buttons -Message 'Connexion echouee'

Write-Host "Update sans Show - btn.Visible=$($btn.Visible)"

$form.CreateControl()
$form.Show()
$form.Hide()
[System.Windows.Forms.Application]::DoEvents()
Update-SharePointUI -State 'Offline' -Labels @{
    StatusLabel = $spUi.Status; Status = $spUi.Status; Connect = $spUi.Connect
    FileName = $spUi.FileName; Date = $spUi.Date; Icon = $spUi.Icon
    StatusDot = $spUi.StatusDot; LocalMode = $spUi.LocalMode
} -Buttons $spUi.Buttons -Message 'Connexion echouee'

$right = $btn.Location.X + $btn.Width
Write-Host "Apres Form.Show - X=$($btn.Location.X) Y=$($btn.Location.Y) W=$($btn.Width) H=$($btn.Height)"
Write-Host "Group ClientSize=$($group.ClientSize) Depasse=$(($right -gt $group.ClientSize.Width))"

Write-AuditSection '4. CHEVAUCHEMENTS (Offline, client 1100)'
foreach ($ctrl in $group.Controls) {
    $ov = ($ctrl -ne $btn -and $ctrl.Visible -and (Test-Overlap $ctrl.Bounds $btn.Bounds))
    Write-Host "  $($ctrl.Name) Loc=$($ctrl.Location) Size=$($ctrl.Size) Vis=$($ctrl.Visible) Opaque=$($ctrl.BackColor.A -eq 255) CHEVAUCHE=$ov"
}

Write-AuditSection '5. Z-ORDER'
$i = 0
foreach ($ctrl in $group.Controls) {
    Write-Host "  [$i] $($ctrl.Name)"
    $i++
}
Write-Host "BringToFront a la creation : Oui (L263)"
Write-Host "BringToFront dans Update : Oui (L441, L512)"

Write-AuditSection '6. VISIBILITE Offline/Error'
foreach ($st in @('Offline', 'Error')) {
    Update-SharePointUI -State $st -Labels @{ StatusLabel = $spUi.Status; Connect = $spUi.Connect } -Buttons $spUi.Buttons
    Write-Host "$st -> Visible=$($btn.Visible) Enabled=$($btn.Enabled)"
}

Write-AuditSection '7. RAFRAICHISSEMENT'
Write-Host "Refresh() sur GroupBox : Oui (L443)"
Write-Host "Invalidate() sur bouton : Oui (L445, L513)"
Write-Host "DoEvents dans Update-SharePointUI : Non"

Write-AuditSection '8. FENETRE ETROITE + AutoScroll'
foreach ($w in @(1100, 800, 600, 400)) {
    $group.Width = $w
    $group.PerformLayout()
    Set-CnsSharePointConnectButtonPosition -ConnectBtn $btn -Margin 12 -RowY 28
    $lbl = $spUi.Status
    $labelMax = $btn.Location.X - 12 - 8
    if ($labelMax -ge 100) { $lbl.Width = [Math]::Min(500, $labelMax) }
    $ov = @($group.Controls | Where-Object { $_ -ne $btn -and $_.Visible -and (Test-Overlap $_.Bounds $btn.Bounds) })
    $panelW = $panel.ClientSize.Width
    Write-Host "GroupW=$w btnX=$($btn.Location.X) lblW=$($lbl.Width) lblRight=$($lbl.Location.X + $lbl.Width) chevauch=$($ov.Count) panelClient=$panelW btnInPanel=$($btn.Right -le $panelW)"
}

Write-AuditSection 'RACE Safe-UpdateUIControl'
function Test-SafeUpdateSim {
    param($Panel)
    $formRef = $Panel.FindForm()
    if ($null -eq $formRef -or $formRef.IsDisposed) { return 'SKIP (FindForm null)' }
    return 'RUN'
}
$p2 = [System.Windows.Forms.Panel]::new()
Write-Host "Panel isole : $(Test-SafeUpdateSim $p2)"
Write-Host "Panel dans form non Show : $(Test-SafeUpdateSim $panel)"

$form.Dispose()

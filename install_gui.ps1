# install_gui.ps1 - Installateur graphique ASSISTANT (double-clic via INSTALL.bat)
# Choix du centre en fenetre WinForms, installation sans ligne de commande.

param(
    [string]$InstallDir = "$env:LOCALAPPDATA\ASSISTANT",
    [switch]$Launch
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[void][System.Windows.Forms.Application]::EnableVisualStyles()

$scriptRoot = $PSScriptRoot
$centresJson = Join-Path $scriptRoot 'config\centres.json'
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Test-InstallPackageComplete {
    param([string]$Root)
    $missing = @(
        'INSTALL.bat',
        'install_gui.ps1',
        'install_assistant.ps1',
        'ASSISTANT.bat',
        'src\Main.ps1',
        'config\centres.json',
        'lib\System.Data.SQLite.dll'
    ) | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Root $_)) }
    return $missing
}

function Show-InstallError {
    param([string]$Message)
    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        'ASSISTANT - Erreur installation',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    )
}

function Show-InstallSuccess {
    param([string]$Message)
    $answer = [System.Windows.Forms.MessageBox]::Show(
        ($Message + "`n`nVoulez-vous lancer ASSISTANT maintenant ?"),
        'ASSISTANT - Installation terminee',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
    return ($answer -eq [System.Windows.Forms.DialogResult]::Yes)
}

if (-not (Test-Path -LiteralPath $centresJson)) {
    Show-InstallError @"
Package incomplet : config\centres.json introuvable.

Copiez TOUT le dossier package sur la cle USB
(ASSISTANT.bat, install_assistant.ps1, src\, config\, lib\, Data\).
"@
    exit 1
}

$missingFiles = Test-InstallPackageComplete -Root $scriptRoot
if ($missingFiles.Count -gt 0) {
    Show-InstallError @"
Package incomplet sur la cle USB.

Fichiers manquants :
$($missingFiles -join "`n")

Copiez tout le dossier package (pas seulement INSTALL.bat).
"@
    exit 1
}

if (-not (Test-Path -LiteralPath $psExe)) {
    Show-InstallError @"
PowerShell introuvable :
$psExe

Contactez le support informatique.
"@
    exit 1
}

$centres = @((Get-Content -LiteralPath $centresJson -Raw -Encoding UTF8 | ConvertFrom-Json).centres)
if ($centres.Count -eq 0) {
    Show-InstallError 'Aucun centre defini dans config\centres.json'
    exit 1
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Installation ASSISTANT - Elise Alpes'
$form.Size = New-Object System.Drawing.Size(480, 220)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false

$lbl = New-Object System.Windows.Forms.Label
$lbl.Text = 'Selectionnez votre centre :'
$lbl.Location = New-Object System.Drawing.Point(20, 20)
$lbl.Size = New-Object System.Drawing.Size(420, 24)

$combo = New-Object System.Windows.Forms.ComboBox
$combo.DropDownStyle = 'DropDownList'
$combo.Location = New-Object System.Drawing.Point(20, 50)
$combo.Size = New-Object System.Drawing.Size(420, 28)
foreach ($c in $centres) {
    [void]$combo.Items.Add($c.name)
}
$combo.SelectedIndex = -1

$lblInfo = New-Object System.Windows.Forms.Label
$lblInfo.Text = "Installation dans : $InstallDir"
$lblInfo.Location = New-Object System.Drawing.Point(20, 85)
$lblInfo.Size = New-Object System.Drawing.Size(420, 40)
$lblInfo.ForeColor = [System.Drawing.Color]::DarkGray

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = 'Installer'
$btnInstall.Location = New-Object System.Drawing.Point(220, 130)
$btnInstall.Size = New-Object System.Drawing.Size(100, 32)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = 'Annuler'
$btnCancel.Location = New-Object System.Drawing.Point(330, 130)
$btnCancel.Size = New-Object System.Drawing.Size(100, 32)

$script:PickedCentre = $null

$btnInstall.Add_Click({
    if ($combo.SelectedIndex -lt 0) {
        [void][System.Windows.Forms.MessageBox]::Show(
            'Veuillez selectionner un centre.',
            'ASSISTANT',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }
    $script:PickedCentre = $centres[$combo.SelectedIndex]
    $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Close()
})

$btnCancel.Add_Click({
    $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Close()
})

$form.Controls.AddRange(@($lbl, $combo, $lblInfo, $btnInstall, $btnCancel))
$dialogResult = $form.ShowDialog()
$form.Dispose()

if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK -or -not $script:PickedCentre) {
    exit 0
}

$selected = $script:PickedCentre

$progress = New-Object System.Windows.Forms.Form
$progress.Text = 'Installation ASSISTANT'
$progress.Size = New-Object System.Drawing.Size(450, 120)
$progress.StartPosition = 'CenterScreen'
$progress.FormBorderStyle = 'FixedDialog'
$progress.ControlBox = $false
$lblProg = New-Object System.Windows.Forms.Label
$lblProg.Text = "Installation de $($selected.name) en cours...`nPatientez 1 a 2 minutes."
$lblProg.Location = New-Object System.Drawing.Point(20, 25)
$lblProg.Size = New-Object System.Drawing.Size(400, 50)
$progress.Controls.Add($lblProg)
$progress.Show()
[void]$progress.Refresh()
[System.Windows.Forms.Application]::DoEvents()

try {
    $installScript = Join-Path $scriptRoot 'install_assistant.ps1'
    if (-not (Test-Path -LiteralPath $installScript)) {
        throw "Script install_assistant.ps1 introuvable dans $scriptRoot"
    }

    & $installScript `
        -Centre $selected.id `
        -Quiet `
        -InstallDir $InstallDir `
        -SourceRoot $scriptRoot `
        -Fresh `
        -DesktopShortcut `
        -Launch:$Launch.IsPresent

    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "Installation echouee (code $LASTEXITCODE)"
    }

    $requiredInstalled = @(
        (Join-Path $InstallDir 'src\Main.ps1'),
        (Join-Path $InstallDir 'lib\System.Data.SQLite.dll'),
        (Join-Path $InstallDir 'config\centres.json'),
        (Join-Path $InstallDir 'ASSISTANT.bat')
    )
    $missingInstalled = $requiredInstalled | Where-Object { -not (Test-Path -LiteralPath $_) }
    if ($missingInstalled.Count -gt 0) {
        throw @"
Installation incomplete - fichiers manquants :
$($missingInstalled -join "`n")
"@
    }

    $progress.Close()
    $progress.Dispose()

    $launchNow = Show-InstallSuccess @"
ASSISTANT a ete installe avec succes.

Centre : $($selected.name)
Dossier : $InstallDir

Un raccourci a ete cree sur le bureau et dans le menu Demarrer.
"@

    if ($launchNow) {
        $mainScript = Join-Path $InstallDir 'src\Main.ps1'
        if (Test-Path -LiteralPath $mainScript) {
            Start-Process -FilePath $psExe `
                -ArgumentList "-WindowStyle Hidden -STA -ExecutionPolicy Bypass -File `"$mainScript`"" `
                -WorkingDirectory $InstallDir
        }
    }
}
catch {
    try { $progress.Close(); $progress.Dispose() } catch {}
    Show-InstallError @"
L installation a echoue :

$($_.Exception.Message)

Causes frequentes :
- Cle USB : copiez tout le dossier (pas seulement install_assistant.ps1)
- Antivirus : fichier bloque pendant la copie
- Espace disque insuffisant

Reessayez ou contactez le support informatique.
"@
    exit 1
}

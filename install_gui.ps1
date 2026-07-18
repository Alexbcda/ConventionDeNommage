# install_gui.ps1 - Installateur graphique ASSISTANT (double-clic via INSTALL.bat)
# Pop-up de selection du centre, puis installation via install_assistant.ps1.

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

# Ordre d'affichage demande a l'installation (centres absents de centres.json ignores).
$script:PreferredCentreIds = @(
    'argonay',
    'bourg-en-bresse',
    'fontaine',
    'valence'
)

function Test-InstallPackageComplete {
    param([string]$Root)
    $missing = @(
        'INSTALL.bat',
        'install_gui.ps1',
        'install_assistant.ps1',
        'ASSISTANT.bat',
        'src\Main.ps1',
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

function Get-InstallCentresFallback {
    return @(
        [PSCustomObject]@{ id = 'argonay'; name = 'Argonay'; planningFileName = 'Planning ARGONAY 2026.xlsm' },
        [PSCustomObject]@{ id = 'bourg-en-bresse'; name = 'Bourg-en-Bresse'; planningFileName = 'Planning BOURG 2026.xlsm' },
        [PSCustomObject]@{ id = 'fontaine'; name = 'Fontaine'; planningFileName = 'Planning FONTAINE 2026.xlsm' },
        [PSCustomObject]@{ id = 'valence'; name = 'Valence'; planningFileName = 'Planning VALENCE 2026.xlsm' }
    )
}

function Get-InstallCentresFromConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        Write-Warning "Fichier centres.json introuvable : $ConfigPath"
        return (Get-InstallCentresFallback)
    }

    try {
        $json = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $json -or $null -eq $json.centres) {
            Write-Warning "Structure centres.json invalide (propriete 'centres' manquante) : $ConfigPath"
            return (Get-InstallCentresFallback)
        }

        $rawCentres = @($json.centres)
        if ($rawCentres.Count -eq 0) {
            Write-Warning "Aucun centre dans centres.json : $ConfigPath"
            return (Get-InstallCentresFallback)
        }

        $byId = @{}
        foreach ($centre in $rawCentres) {
            if ($null -eq $centre) { continue }
            $id = [string]$centre.id
            if (-not [string]::IsNullOrWhiteSpace($id)) {
                $byId[$id.Trim().ToLowerInvariant()] = $centre
            }
        }

        if ($byId.Count -eq 0) {
            Write-Warning "Aucun centre valide dans centres.json : $ConfigPath"
            return (Get-InstallCentresFallback)
        }

        $ordered = New-Object System.Collections.ArrayList
        foreach ($preferredId in $script:PreferredCentreIds) {
            if ($byId.ContainsKey($preferredId)) {
                [void]$ordered.Add($byId[$preferredId])
                $byId.Remove($preferredId) | Out-Null
            }
        }
        foreach ($remaining in ($byId.Values | Sort-Object { [string]$_.name })) {
            [void]$ordered.Add($remaining)
        }
        return @($ordered.ToArray())
    }
    catch {
        Write-Warning "Erreur lecture centres.json : $($_.Exception.Message)"
        return (Get-InstallCentresFallback)
    }
}

function Show-InstallCentreSelectionDialog {
    param(
        [Parameter(Mandatory = $true)][array]$Centres,
        [Parameter(Mandatory = $true)][string]$TargetInstallDir
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Configuration du centre'
    $form.Size = New-Object System.Drawing.Size(500, 260)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = 'Selectionnez le centre de cette installation :'
    $lbl.Location = New-Object System.Drawing.Point(20, 20)
    $lbl.Size = New-Object System.Drawing.Size(450, 24)

    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.DropDownStyle = 'DropDownList'
    $combo.Location = New-Object System.Drawing.Point(20, 50)
    $combo.Size = New-Object System.Drawing.Size(450, 28)
    foreach ($centre in $Centres) {
        [void]$combo.Items.Add([string]$centre.name)
    }
    if ($combo.Items.Count -gt 0) {
        $combo.SelectedIndex = 0
    }

    $lblDetail = New-Object System.Windows.Forms.Label
    $lblDetail.Location = New-Object System.Drawing.Point(20, 88)
    $lblDetail.Size = New-Object System.Drawing.Size(450, 48)
    $lblDetail.ForeColor = [System.Drawing.Color]::DarkSlateGray

    $updateDetail = {
        if ($combo.SelectedIndex -lt 0 -or $combo.SelectedIndex -ge $Centres.Count) {
            $lblDetail.Text = ''
            return
        }
        $picked = $Centres[$combo.SelectedIndex]
        $planning = [string]$picked.planningFileName
        if ([string]::IsNullOrWhiteSpace($planning)) {
            $planning = '(planning non specifie)'
        }
        $lblDetail.Text = @(
            "Centre : $($picked.name)"
            "Planning : $planning"
            "L'URL SharePoint sera configuree automatiquement."
        ) -join [Environment]::NewLine
    }

    $combo.Add_SelectedIndexChanged({ & $updateDetail })
    & $updateDetail

    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.Text = "Installation dans : $TargetInstallDir"
    $lblInfo.Location = New-Object System.Drawing.Point(20, 145)
    $lblInfo.Size = New-Object System.Drawing.Size(450, 20)
    $lblInfo.ForeColor = [System.Drawing.Color]::Gray

    $btnInstall = New-Object System.Windows.Forms.Button
    $btnInstall.Text = 'Installer'
    $btnInstall.Location = New-Object System.Drawing.Point(260, 175)
    $btnInstall.Size = New-Object System.Drawing.Size(100, 32)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = 'Annuler'
    $btnCancel.Location = New-Object System.Drawing.Point(370, 175)
    $btnCancel.Size = New-Object System.Drawing.Size(100, 32)

    $script:PickedCentre = $null

    $btnInstall.Add_Click({
        if ($combo.SelectedIndex -lt 0) {
            [void][System.Windows.Forms.MessageBox]::Show(
                'Veuillez selectionner un centre.',
                'Configuration du centre',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            return
        }
        $script:PickedCentre = $Centres[$combo.SelectedIndex]
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })

    $btnCancel.Add_Click({
        $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Close()
    })

    $form.AcceptButton = $btnInstall
    $form.CancelButton = $btnCancel
    $form.Controls.AddRange(@($lbl, $combo, $lblDetail, $lblInfo, $btnInstall, $btnCancel))

    $dialogResult = $form.ShowDialog()
    $form.Dispose()

    if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }
    return $script:PickedCentre
}

if (-not (Test-Path -LiteralPath $centresJson)) {
    [void][System.Windows.Forms.MessageBox]::Show(
        @"
config\centres.json est introuvable dans le package.

La liste des centres par defaut sera utilisee.
L'installation peut echouer si install_assistant.ps1 ne trouve pas config\centres.json.
"@,
        'ASSISTANT - Configuration centre',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
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

$centres = Get-InstallCentresFromConfig -ConfigPath $centresJson
if ($centres.Count -eq 0) {
    $centres = Get-InstallCentresFallback
    [void][System.Windows.Forms.MessageBox]::Show(
        'Aucun centre disponible — liste par defaut appliquee.',
        'ASSISTANT - Configuration centre',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
}

$selected = Show-InstallCentreSelectionDialog -Centres $centres -TargetInstallDir $InstallDir
if (-not $selected) {
    exit 0
}

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
Le centre sera reconnu automatiquement au premier lancement.
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

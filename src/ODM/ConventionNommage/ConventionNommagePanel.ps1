# ConventionNommagePanel.ps1 - VERSION FINALE

function Show-ConventionNommagePanel {
    param([string]$FichierPDF)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = $script:CouleurGrisFond
    $panel.Padding = New-Object System.Windows.Forms.Padding(50)
    # Données pour les gestionnaires d'événements : le CLR n'exécute pas les handlers dans la portée locale de cette fonction.
    $panel.Tag = @{ FichierPDF = $FichierPDF }

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Renommer un PDF"
    $lblTitle.Font = $script:PoliceTitre1
    $lblTitle.ForeColor = $script:CouleurOrange
    $lblTitle.Location = New-Object System.Drawing.Point(0, 0)
    $lblTitle.Size = New-Object System.Drawing.Size(500, 50)
    $panel.Controls.Add($lblTitle)

    $txtCollecte = New-Object System.Windows.Forms.TextBox
    $txtCollecte.Name = "txtCollecte"
    $txtCollecte.Location = New-Object System.Drawing.Point(0, 110)
    $txtCollecte.Size = New-Object System.Drawing.Size(550, 35)
    $txtCollecte.Font = $script:PoliceNormal
    $txtCollecte.PlaceholderText = "Renseigner le point de collecte"
    $panel.Controls.Add($txtCollecte)

    $btnCert = New-Object System.Windows.Forms.Button
    Set-BtnCertificatStyle -BtnCertificat $btnCert
    $btnCert.Location = New-Object System.Drawing.Point(0, 170)
    $panel.Controls.Add($btnCert)

    $btnPlan = New-Object System.Windows.Forms.Button
    Set-BtnPlannerStyle -BtnPlanner $btnPlan
    $btnPlan.Location = New-Object System.Drawing.Point(145, 170)
    $panel.Controls.Add($btnPlan)

    $btnFT = New-Object System.Windows.Forms.Button
    Set-BtnFranceTravailStyle -BtnFranceTravail $btnFT
    $btnFT.Location = New-Object System.Drawing.Point(290, 170)
    $panel.Controls.Add($btnFT)

    $lblDate = New-Object System.Windows.Forms.Label
    $lblDate.Text = "Date :"
    $lblDate.Font = $script:PoliceNormal
    $lblDate.Location = New-Object System.Drawing.Point(0, 240)
    $lblDate.Size = New-Object System.Drawing.Size(50, 30)
    $panel.Controls.Add($lblDate)

    $datePicker = New-Object System.Windows.Forms.DateTimePicker
    $datePicker.Name = "datePicker"
    $datePicker.Location = New-Object System.Drawing.Point(60, 240)
    $datePicker.Size = New-Object System.Drawing.Size(180, 30)
    $datePicker.Format = [System.Windows.Forms.DateTimePickerFormat]::Short
    $datePicker.Font = $script:PoliceNormal
    # Utiliser DateTime .NET pour éviter toute collision avec la fonction métier Get-Date.
    $datePicker.Value = [datetime]::Now.AddDays(-1)
    $panel.Controls.Add($datePicker)

    # Mode forcé - label avec Name pour le retrouver
    $lblModeForce = New-Object System.Windows.Forms.Label
    $lblModeForce.Name = "lblModeForce"
    $lblModeForce.Text = ""
    $lblModeForce.Font = $script:PoliceNormal
    $lblModeForce.ForeColor = $script:CouleurOrange
    $lblModeForce.Location = New-Object System.Drawing.Point(260, 245)
    $lblModeForce.Size = New-Object System.Drawing.Size(250, 25)
    $lblModeForce.Visible = $false
    $panel.Controls.Add($lblModeForce)

    # Handlers : utiliser $sender.Parent + Name — les variables locales ne sont pas visibles depuis le délégué CLR.
    $datePicker.Add_ValueChanged({
        param($sender, $e)
        $p = $sender.Parent
        $label = $p.Controls["lblModeForce"]
        if ($label) {
            $label.Text = "Mode forcé : " + $sender.Value.ToString("dd/MM/yyyy")
            $label.Visible = $true
        }
    })

    $null = $btnCert.Add_Click({
        param($sender, $e)
        $p = [System.Windows.Forms.Panel]$sender.Parent
        $txt = [System.Windows.Forms.TextBox]$p.Controls["txtCollecte"]
        $dt = [System.Windows.Forms.DateTimePicker]$p.Controls["datePicker"]
        if (-not $txt) { Write-Host "[DEBUG] txtCollecte NULL" -ForegroundColor Yellow; return }
        if (-not $dt) { Write-Host "[DEBUG] datePicker NULL" -ForegroundColor Yellow; return }
        $pdf = [string]$p.Tag.FichierPDF
        $c = $txt.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($c)) {
            [System.Windows.Forms.MessageBox]::Show("Veuillez saisir le point de collecte")
            return
        }
        $d = $dt.Value
        $n = "Certificat de Destruction-$c-du $($d.ToString('dd.MM.yyyy')).pdf"
        Rename-Item -Path $pdf -NewName $n -Force
        [System.Windows.Forms.MessageBox]::Show("✅ Fichier renommé : $n")
        $p.FindForm().Close()
    })

    $null = $btnPlan.Add_Click({
        param($sender, $e)
        $p = [System.Windows.Forms.Panel]$sender.Parent
        $txt = [System.Windows.Forms.TextBox]$p.Controls["txtCollecte"]
        $dt = [System.Windows.Forms.DateTimePicker]$p.Controls["datePicker"]
        if (-not $txt) { Write-Host "[DEBUG] txtCollecte NULL" -ForegroundColor Yellow; return }
        if (-not $dt) { Write-Host "[DEBUG] datePicker NULL" -ForegroundColor Yellow; return }
        $pdf = [string]$p.Tag.FichierPDF
        $c = $txt.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($c)) {
            [System.Windows.Forms.MessageBox]::Show("Veuillez saisir le point de collecte")
            return
        }
        $d = $dt.Value
        $n = "$($d.ToString('yyyyMMdd'))-$c.pdf"
        Rename-Item -Path $pdf -NewName $n -Force
        [System.Windows.Forms.MessageBox]::Show("✅ Fichier renommé : $n")
        $p.FindForm().Close()
    })

    $null = $btnFT.Add_Click({
        param($sender, $e)
        $p = [System.Windows.Forms.Panel]$sender.Parent
        $txt = [System.Windows.Forms.TextBox]$p.Controls["txtCollecte"]
        $dt = [System.Windows.Forms.DateTimePicker]$p.Controls["datePicker"]
        if (-not $txt) { Write-Host "[DEBUG] txtCollecte NULL" -ForegroundColor Yellow; return }
        if (-not $dt) { Write-Host "[DEBUG] datePicker NULL" -ForegroundColor Yellow; return }
        $pdf = [string]$p.Tag.FichierPDF
        $c = $txt.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($c)) {
            [System.Windows.Forms.MessageBox]::Show("Veuillez saisir le point de collecte")
            return
        }
        $d = $dt.Value
        $n = "$c-du $($d.ToString('dd.MM.yyyy')).pdf"
        Rename-Item -Path $pdf -NewName $n -Force
        [System.Windows.Forms.MessageBox]::Show("✅ Fichier renommé : $n")
        $p.FindForm().Close()
    })

    $txtCollecte.Select()
    $txtCollecte.Focus()

    return ,$panel
}

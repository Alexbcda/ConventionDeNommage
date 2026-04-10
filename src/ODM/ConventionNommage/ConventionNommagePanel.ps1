# ConventionNommagePanel.ps1 - VERSION FINALE

function Show-ConventionNommagePanel {
    param([string]$FichierPDF)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = $script:CouleurGrisFond
    $panel.Padding = New-Object System.Windows.Forms.Padding(50)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Renommer un PDF"
    $lblTitle.Font = $script:PoliceTitre1
    $lblTitle.ForeColor = $script:CouleurOrange
    $lblTitle.Location = New-Object System.Drawing.Point(0, 0)
    $lblTitle.Size = New-Object System.Drawing.Size(500, 50)
    $panel.Controls.Add($lblTitle)

    $txtCollecte = New-Object System.Windows.Forms.TextBox
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
    $datePicker.Location = New-Object System.Drawing.Point(60, 240)
    $datePicker.Size = New-Object System.Drawing.Size(180, 30)
    $datePicker.Format = "Short"
    $datePicker.Font = $script:PoliceNormal
    $datePicker.Value = (Get-Date).AddDays(-1)
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

    # Événement fiable avec $this.Parent.Controls
    $datePicker.Add_ValueChanged({
        $label = $this.Parent.Controls | Where-Object { $_.Name -eq "lblModeForce" }
        if ($label) {
            $label.Text = "Mode forcé : " + $this.Value.ToString("dd/MM/yyyy")
            $label.Visible = $true
        }
    })

    $null = $btnCert.Add_Click({
        $c = $txtCollecte.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($c)) { 
            [System.Windows.Forms.MessageBox]::Show("Veuillez saisir le point de collecte")
            return 
        }
        $d = $datePicker.Value
        $n = "Certificat de Destruction-$c-du $($d.ToString('dd.MM.yyyy')).pdf"
        Rename-Item -Path $FichierPDF -NewName $n -Force
        [System.Windows.Forms.MessageBox]::Show("✅ Fichier renommé : $n")
        $panel.FindForm().Close()
    })

    $null = $btnPlan.Add_Click({
        $c = $txtCollecte.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($c)) { 
            [System.Windows.Forms.MessageBox]::Show("Veuillez saisir le point de collecte")
            return 
        }
        $d = $datePicker.Value
        $n = "$($d.ToString('yyyyMMdd'))-$c.pdf"
        Rename-Item -Path $FichierPDF -NewName $n -Force
        [System.Windows.Forms.MessageBox]::Show("✅ Fichier renommé : $n")
        $panel.FindForm().Close()
    })

    $null = $btnFT.Add_Click({
        $c = $txtCollecte.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($c)) { 
            [System.Windows.Forms.MessageBox]::Show("Veuillez saisir le point de collecte")
            return 
        }
        $d = $datePicker.Value
        $n = "$c-du $($d.ToString('dd.MM.yyyy')).pdf"
        Rename-Item -Path $FichierPDF -NewName $n -Force
        [System.Windows.Forms.MessageBox]::Show("✅ Fichier renommé : $n")
        $panel.FindForm().Close()
    })

    $txtCollecte.Select()
    $txtCollecte.Focus()

    return ,$panel
}

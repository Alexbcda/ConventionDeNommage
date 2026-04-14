# ConventionNommagePanel.ps1 - VERSION ULTRA SIMPLIFIEE

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
    $lblDate.Text = "Date (JJ/MM/AAAA) :"
    $lblDate.Font = $script:PoliceNormal
    $lblDate.Location = New-Object System.Drawing.Point(0, 240)
    $lblDate.Size = New-Object System.Drawing.Size(150, 30)
    $panel.Controls.Add($lblDate)

    $dtDate = New-Object System.Windows.Forms.DateTimePicker
    $dtDate.Location = New-Object System.Drawing.Point(160, 240)
    $dtDate.Size = New-Object System.Drawing.Size(170, 30)
    $dtDate.Font = $script:PoliceNormal
    $dtDate.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
    $dtDate.CustomFormat = "dd.MM.yyyy"
    # Ne pas utiliser Get-Date ici: une fonction Get-Date du projet peut masquer la cmdlet.
    $dtDate.Value = [datetime]::Now
    $panel.Controls.Add($dtDate)

    $btnCert.Add_Click({
        $c = $txtCollecte.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($c)) { 
            [System.Windows.Forms.MessageBox]::Show("Veuillez saisir le point de collecte")
            return 
        }
        $d = $dtDate.Value.ToString("dd.MM.yyyy")
        $n = "Certificat de Destruction-$c-du $d.pdf"
        Rename-Item -Path $FichierPDF -NewName $n -Force
        [System.Windows.Forms.MessageBox]::Show("✅ Fichier renommé : $n")
        $panel.FindForm().Close()
    })

    $btnPlan.Add_Click({
        $c = $txtCollecte.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($c)) { 
            [System.Windows.Forms.MessageBox]::Show("Veuillez saisir le point de collecte")
            return 
        }
        $dateFormatted = $dtDate.Value.ToString("yyyyMMdd")
        $n = "$dateFormatted-$c.pdf"
        Rename-Item -Path $FichierPDF -NewName $n -Force
        [System.Windows.Forms.MessageBox]::Show("✅ Fichier renommé : $n")
        $panel.FindForm().Close()
    })

    $btnFT.Add_Click({
        $c = $txtCollecte.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($c)) { 
            [System.Windows.Forms.MessageBox]::Show("Veuillez saisir le point de collecte")
            return 
        }
        $d = $dtDate.Value.ToString("dd.MM.yyyy")
        $n = "$c-du $d.pdf"
        Rename-Item -Path $FichierPDF -NewName $n -Force
        [System.Windows.Forms.MessageBox]::Show("✅ Fichier renommé : $n")
        $panel.FindForm().Close()
    })

    $txtCollecte.Select()
    $txtCollecte.Focus()

    return $panel
}
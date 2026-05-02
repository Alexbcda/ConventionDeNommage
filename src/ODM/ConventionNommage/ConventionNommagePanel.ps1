# ConventionNommagePanel.ps1 — UI uniquement (handlers : ConventionNommageHandlers.ps1)

function Show-ConventionNommagePanel {
    param([string]$FichierPDF)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $null = [System.Text.Encoding]::Default
    if (Get-Command Initialize-WinFormsUiCultureFrFr -ErrorAction SilentlyContinue) {
        Initialize-WinFormsUiCultureFrFr
    }

    $panel = [System.Windows.Forms.Panel]::new()
    $panel.Name = 'panelConventionNommage'
    $panel.Dock = "Fill"
    $panel.BackColor = $script:CouleurGrisFond
    $panel.Padding = [System.Windows.Forms.Padding]::new(50)

    $refDate = Get-ConventionNomReferenceDate
    $panel.Tag = @{
        FichierPDF  = $FichierPDF
        RefDate     = $refDate
        RenamingNow = $false
    }

    $lblTitle = [System.Windows.Forms.Label]::new()
    $lblTitle.Text = "Renommer un PDF"
    $lblTitle.Font = $script:PoliceTitre1
    $lblTitle.ForeColor = $script:CouleurOrange
    $lblTitle.Location = [System.Drawing.Point]::new(0, 0)
    $lblTitle.Size = [System.Drawing.Size]::new(500, 50)
    $panel.Controls.Add($lblTitle)

    # Libellé explicite (PS 5.1 : ne pas s'appuyer sur PlaceholderText seul).
    $lblCollecte = [System.Windows.Forms.Label]::new()
    $lblCollecte.Text = 'Point de collecte :'
    $lblCollecte.Font = $script:PoliceNormal
    $lblCollecte.Location = [System.Drawing.Point]::new(0, 78)
    $lblCollecte.Size = [System.Drawing.Size]::new(400, 22)
    $panel.Controls.Add($lblCollecte)

    $txtCollecte = [System.Windows.Forms.TextBox]::new()
    $txtCollecte.Name = "txtCollecte"
    $txtCollecte.Location = [System.Drawing.Point]::new(0, 105)
    $txtCollecte.Size = [System.Drawing.Size]::new(550, 35)
    $txtCollecte.Font = $script:PoliceNormal
    # Limite UI alignée anti-DoS (traitement complet côté Sanitize-PointDeCollecte / brut max 4096 dans la logique)
    $txtCollecte.MaxLength = 100
    $panel.Controls.Add($txtCollecte)
    Set-WinFormsPlaceholder -TextBox $txtCollecte -Placeholder 'Renseigner le point de collecte'

    $btnCert = [System.Windows.Forms.Button]::new()
    Set-BtnCertificatStyle -BtnCertificat $btnCert
    $btnCert.Name = 'btnCert'
    $btnCert.Location = [System.Drawing.Point]::new(0, 170)
    $panel.Controls.Add($btnCert)

    $btnPlan = [System.Windows.Forms.Button]::new()
    Set-BtnPlannerStyle -BtnPlanner $btnPlan
    $btnPlan.Name = 'btnPlan'
    $btnPlan.Location = [System.Drawing.Point]::new(145, 170)
    $panel.Controls.Add($btnPlan)

    $btnFT = [System.Windows.Forms.Button]::new()
    Set-BtnFranceTravailStyle -BtnFranceTravail $btnFT
    $btnFT.Name = 'btnFT'
    $btnFT.Location = [System.Drawing.Point]::new(290, 170)
    $panel.Controls.Add($btnFT)

    $lblDate = [System.Windows.Forms.Label]::new()
    $lblDate.Text = "Date :"
    $lblDate.Font = $script:PoliceNormal
    $lblDate.Location = [System.Drawing.Point]::new(0, 240)
    $lblDate.Size = [System.Drawing.Size]::new(50, 30)
    $panel.Controls.Add($lblDate)

    $datePicker = [System.Windows.Forms.DateTimePicker]::new()
    $datePicker.Name = "datePicker"
    $datePicker.Location = [System.Drawing.Point]::new(60, 240)
    $datePicker.Size = [System.Drawing.Size]::new(180, 30)
    $datePicker.Format = [System.Windows.Forms.DateTimePickerFormat]::Short
    $datePicker.Font = $script:PoliceNormal
    $datePicker.Value = $refDate
    $panel.Controls.Add($datePicker)

    $lblModeForce = [System.Windows.Forms.Label]::new()
    $lblModeForce.Name = "lblModeForce"
    $lblModeForce.Text = "Date en mode forcée"
    $lblModeForce.Font = $script:PoliceNormal
    $lblModeForce.ForeColor = $script:CouleurOrange
    $lblModeForce.Location = [System.Drawing.Point]::new(260, 245)
    $lblModeForce.Size = [System.Drawing.Size]::new(280, 25)
    $lblModeForce.Visible = $false
    $panel.Controls.Add($lblModeForce)

    $datePicker.Add_ValueChanged({
        param($sender, $e)
        try {
            Update-ForcedDateLabel -Picker $sender
        }
        catch {
            [void][System.Windows.Forms.MessageBox]::Show(
                "Erreur (date) : $($_.Exception.Message)",
                'Convention de nommage',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    })

    # Liaison des clics après création complète des contrôles ; $sender = bouton réel (évite pièges de closure PS).
    $null = $btnCert.Add_Click({
        param($sender, $e)
        try {
            Invoke-CNConventionRenameClick -Sender ([System.Windows.Forms.Button]$sender) -TemplateId 'certificat'
        }
        catch {
            Invoke-CNConventionNommageUserMessage -Text "Erreur dans le gestionnaire Certificat : $($_.Exception.Message)" -Caption 'Convention de nommage' -Icon Error
        }
    })
    $null = $btnPlan.Add_Click({
        param($sender, $e)
        try {
            Invoke-CNConventionRenameClick -Sender ([System.Windows.Forms.Button]$sender) -TemplateId 'planner'
        }
        catch {
            Invoke-CNConventionNommageUserMessage -Text "Erreur dans le gestionnaire Planner : $($_.Exception.Message)" -Caption 'Convention de nommage' -Icon Error
        }
    })
    $null = $btnFT.Add_Click({
        param($sender, $e)
        try {
            Invoke-CNConventionRenameClick -Sender ([System.Windows.Forms.Button]$sender) -TemplateId 'france-travail'
        }
        catch {
            Invoke-CNConventionNommageUserMessage -Text "Erreur dans le gestionnaire France Travail : $($_.Exception.Message)" -Caption 'Convention de nommage' -Icon Error
        }
    })

    # Vérification réflexive : événement Click réellement abonné (API .GetField, pas [Type]::GetField en PS 5.1).
    $attachCert = Test-CNButtonClickHandlerAttached -Control $btnCert
    $attachPlan = Test-CNButtonClickHandlerAttached -Control $btnPlan
    $attachFT = Test-CNButtonClickHandlerAttached -Control $btnFT
    $lineAttach = "EVENT ATTACHED: btnCert=$attachCert / btnPlan=$attachPlan / btnFT=$attachFT"
    $panel.Tag['EventAttachLog'] = $lineAttach
    Write-Host $lineAttach -ForegroundColor $(if ($attachCert -and $attachPlan -and $attachFT) { 'Green' } else { 'Yellow' })

    if (-not ($attachCert -and $attachPlan -and $attachFT)) {
        Write-Host '[CN-WARN] Au moins un bouton sans handler Click détecté par réflexion — liaison à vérifier.' -ForegroundColor Yellow
    }

    $txtCollecte.Select()
    $null = $txtCollecte.Focus()

   

    return ,$panel
}

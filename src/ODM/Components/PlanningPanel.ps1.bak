# PlanningPanel.ps1 - Version finale

function Show-PlanningPanel {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Collecteurs,
        [Parameter(Mandatory=$true)]
        [array]$Vehicules,
        [ref]$PlanningData
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    Write-Host "=== Show-PlanningPanel démarré ===" -ForegroundColor Cyan
    
    # Créer le panel principal
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = [System.Drawing.Color]::White
    $panel.Padding = New-Object System.Windows.Forms.Padding(20)
    $panel.AutoScroll = $true
    
    # En-tête
    $headerPanel = New-Object System.Windows.Forms.Panel
    $headerPanel.Dock = "Top"
    $headerPanel.Height = 80
    $headerPanel.BackColor = [System.Drawing.Color]::FromArgb(27, 91, 74)
    
    $title = New-Object System.Windows.Forms.Label
    $title.Text = "📋 PLANNING DES TOURNÉES"
    $title.Font = New-Object System.Drawing.Font("Arial", 14, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::White
    $title.Location = New-Object System.Drawing.Point(20, 15)
    $title.Size = New-Object System.Drawing.Size(300, 30)
    $headerPanel.Controls.Add($title)
    
    $lblDate = New-Object System.Windows.Forms.Label
    $lblDate.Text = "📅 Date :"
    $lblDate.ForeColor = [System.Drawing.Color]::White
    $lblDate.Font = New-Object System.Drawing.Font("Arial", 10)
    $lblDate.Location = New-Object System.Drawing.Point(20, 50)
    $lblDate.Size = New-Object System.Drawing.Size(60, 25)
    $headerPanel.Controls.Add($lblDate)
    
    $datePicker = New-Object System.Windows.Forms.DateTimePicker
    $datePicker.Format = "Short"
    $datePicker.Value = (Get-Date)
    $datePicker.Location = New-Object System.Drawing.Point(90, 47)
    $datePicker.Size = New-Object System.Drawing.Size(140, 25)
    $headerPanel.Controls.Add($datePicker)
    
    $panel.Controls.Add($headerPanel)
    
    # Zone des tournées
    $lblTournees = New-Object System.Windows.Forms.Label
    $lblTournees.Text = "🚌 TOURNÉES DU JOUR"
    $lblTournees.Font = New-Object System.Drawing.Font("Arial", 11, [System.Drawing.FontStyle]::Bold)
    $lblTournees.Location = New-Object System.Drawing.Point(20, 100)
    $lblTournees.Size = New-Object System.Drawing.Size(300, 25)
    $panel.Controls.Add($lblTournees)
    
    # Conteneur des lignes
    $rowsContainer = New-Object System.Windows.Forms.Panel
    $rowsContainer.Location = New-Object System.Drawing.Point(20, 130)
    $rowsContainer.Size = New-Object System.Drawing.Size(900, 400)
    $rowsContainer.AutoScroll = $true
    $rowsContainer.BackColor = [System.Drawing.Color]::White
    $rowsContainer.BorderStyle = "FixedSingle"
    
    # Créer les listes
    $collecteursList = New-Object System.Collections.ArrayList
    $collecteursList.Add("-- Sélectionner --") | Out-Null
    foreach ($c in $Collecteurs) {
        $null = $collecteursList.Add("$($c.nom) $($c.prenom)")
    }
    
    $vehiculesList = New-Object System.Collections.ArrayList
    $vehiculesList.Add("-- Sélectionner --") | Out-Null
    foreach ($v in $Vehicules) {
        $null = $vehiculesList.Add("$($v.immatriculation) - $($v.marque) $($v.modele)")
    }
    
    # Stocker les lignes
    $script:tourneeRows = @()
    $yPos = 10
    $testCount = 10
    
    # Créer la fonction comme scriptblock global
    $script:VerifierDoublons = {
        Write-Host "=== Vérification des doublons ===" -ForegroundColor Cyan
        
        $collecteurCount = @{}
        $vehiculeCount = @{}
        
        foreach ($row in $script:tourneeRows) {
            $c = $row.cbCollecteur.SelectedItem
            $v = $row.cbVehicule.SelectedItem
            
            if ($c -and $c -ne "-- Sélectionner --") {
                $collecteurCount[$c] = ($collecteurCount[$c] + 1)
            }
            if ($v -and $v -ne "-- Sélectionner --") {
                $vehiculeCount[$v] = ($vehiculeCount[$v] + 1)
            }
        }
        
        foreach ($row in $script:tourneeRows) {
            $c = $row.cbCollecteur.SelectedItem
            $v = $row.cbVehicule.SelectedItem
            
            $cCount = if ($c -and $c -ne "-- Sélectionner --") { $collecteurCount[$c] } else { 0 }
            $vCount = if ($v -and $v -ne "-- Sélectionner --") { $vehiculeCount[$v] } else { 0 }
            
            if ($cCount -gt 1) {
                $row.lblStatus.Text = "⚠️ Doublon collecteur!"
                $row.lblStatus.ForeColor = [System.Drawing.Color]::Red
                $row.panel.BackColor = [System.Drawing.Color]::FromArgb(255, 200, 200)
            } elseif ($vCount -gt 1) {
                $row.lblStatus.Text = "⚠️ Doublon véhicule!"
                $row.lblStatus.ForeColor = [System.Drawing.Color]::Red
                $row.panel.BackColor = [System.Drawing.Color]::FromArgb(255, 200, 200)
            } elseif ($c -and $c -ne "-- Sélectionner --" -and $v -and $v -ne "-- Sélectionner --") {
                $row.lblStatus.Text = "✓"
                $row.lblStatus.ForeColor = [System.Drawing.Color]::Green
                $row.panel.BackColor = [System.Drawing.Color]::FromArgb(220, 255, 220)
            } elseif ($c -and $c -ne "-- Sélectionner --" -or $v -and $v -ne "-- Sélectionner --") {
                $row.lblStatus.Text = "⚠️ Incomplet"
                $row.lblStatus.ForeColor = [System.Drawing.Color]::Orange
                $row.panel.BackColor = [System.Drawing.Color]::FromArgb(255, 255, 200)
            } else {
                $row.lblStatus.Text = ""
                $row.panel.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
            }
        }
        
        Write-Host "Vérification terminée" -ForegroundColor Green
    }
    
    # Créer les lignes
    for ($i = 1; $i -le $testCount; $i++) {
        Write-Host "Création ligne $i" -ForegroundColor Gray
        
        $rowPanel = New-Object System.Windows.Forms.Panel
        $rowPanel.Location = New-Object System.Drawing.Point(5, $yPos)
        $rowPanel.Size = New-Object System.Drawing.Size(880, 55)
        $rowPanel.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
        $rowPanel.BorderStyle = "FixedSingle"
        
        # Numéro
        $lblNum = New-Object System.Windows.Forms.Label
        $lblNum.Text = "Tournée $i"
        $lblNum.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
        $lblNum.Location = New-Object System.Drawing.Point(10, 17)
        $lblNum.Size = New-Object System.Drawing.Size(80, 25)
        $rowPanel.Controls.Add($lblNum)
        
        # ComboBox Collecteur
        $cbCollecteur = New-Object System.Windows.Forms.ComboBox
        $cbCollecteur.Location = New-Object System.Drawing.Point(100, 14)
        $cbCollecteur.Size = New-Object System.Drawing.Size(250, 25)
        $cbCollecteur.DropDownStyle = "DropDownList"
        foreach ($item in $collecteursList) {
            $cbCollecteur.Items.Add($item)
        }
        $cbCollecteur.SelectedIndex = 0
        $rowPanel.Controls.Add($cbCollecteur)
        
        # ComboBox Véhicule
        $cbVehicule = New-Object System.Windows.Forms.ComboBox
        $cbVehicule.Location = New-Object System.Drawing.Point(370, 14)
        $cbVehicule.Size = New-Object System.Drawing.Size(350, 25)
        $cbVehicule.DropDownStyle = "DropDownList"
        foreach ($item in $vehiculesList) {
            $cbVehicule.Items.Add($item)
        }
        $cbVehicule.SelectedIndex = 0
        $rowPanel.Controls.Add($cbVehicule)
        
        # Label de statut
        $lblStatus = New-Object System.Windows.Forms.Label
        $lblStatus.Location = New-Object System.Drawing.Point(740, 12)
        $lblStatus.Size = New-Object System.Drawing.Size(130, 30)
        $lblStatus.Font = New-Object System.Drawing.Font("Arial", 8)
        $lblStatus.TextAlign = "MiddleLeft"
        $rowPanel.Controls.Add($lblStatus)
        
        $rowsContainer.Controls.Add($rowPanel)
        
        $rowData = @{
            num = $i
            cbCollecteur = $cbCollecteur
            cbVehicule = $cbVehicule
            panel = $rowPanel
            lblStatus = $lblStatus
        }
        
        $cbCollecteur.Tag = $rowData
        $cbVehicule.Tag = $rowData
        
        $cbCollecteur.Add_SelectedIndexChanged({
            $row = $this.Tag
            Write-Host "Collecteur ligne $($row.num) -> '$($this.SelectedItem)'" -ForegroundColor Magenta
            & $script:VerifierDoublons
        })
        
        $cbVehicule.Add_SelectedIndexChanged({
            $row = $this.Tag
            Write-Host "Véhicule ligne $($row.num) -> '$($this.SelectedItem)'" -ForegroundColor Magenta
            & $script:VerifierDoublons
        })
        
        $script:tourneeRows += $rowData
        $yPos += 60
    }
    
    $rowsContainer.Height = $yPos + 10
    $panel.Controls.Add($rowsContainer)
    
    # Panel du bas
    $bottomPanel = New-Object System.Windows.Forms.Panel
    $bottomPanel.Dock = "Bottom"
    $bottomPanel.Height = 60
    $bottomPanel.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
    
    $btnValider = New-Object System.Windows.Forms.Button
    $btnValider.Text = "✓ VALIDER"
    $btnValider.Size = New-Object System.Drawing.Size(180, 40)
    $btnValider.Location = New-Object System.Drawing.Point(20, 10)
    $btnValider.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $btnValider.ForeColor = [System.Drawing.Color]::White
    $btnValider.FlatStyle = "Flat"
    $bottomPanel.Controls.Add($btnValider)
    
    $panel.Controls.Add($bottomPanel)
    
    # Initialiser
    & $script:VerifierDoublons
    
    # Événement du bouton Valider
    $btnValider.Add_Click({
        & $script:VerifierDoublons
        
        $hasError = $false
        foreach ($row in $script:tourneeRows) {
            if ($row.lblStatus.Text -like "*doublon*") {
                $hasError = $true
            }
        }
        
        if ($hasError) {
            [System.Windows.Forms.MessageBox]::Show("Erreur: Des doublons détectés !", "Erreur")
            return
        }
        
        $data = @{
            date = $datePicker.Value.ToString("dd/MM/yyyy")
            tournees = @()
        }
        
        foreach ($row in $script:tourneeRows) {
            $c = $row.cbCollecteur.SelectedItem
            $v = $row.cbVehicule.SelectedItem
            if ($c -and $c -ne "-- Sélectionner --" -and $v -and $v -ne "-- Sélectionner --") {
                $data.tournees += @{
                    numero = $row.num
                    collecteur = $c
                    vehicule = $v
                }
            }
        }
        
        $PlanningData.Value = $data
        [System.Windows.Forms.MessageBox]::Show("Planning validé !", "Succès")
    })
    
    Write-Host "=== Show-PlanningPanel terminé ===" -ForegroundColor Green
    return ,$panel
}

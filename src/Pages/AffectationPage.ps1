# Pages/AffectationPage.ps1

function New-AffectationPage {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $panel.AutoScroll = $true
    
    $title = New-Object System.Windows.Forms.Label
    $title.Text = "👥 Étape 3/3 - Affectation agents & véhicules"
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $title.Location = New-Object System.Drawing.Point(50, 30)
    $title.Size = New-Object System.Drawing.Size(600, 50)
    $panel.Controls.Add($title)
    
    $btnBack = New-Button -Text "← Retour" -X 50 -Y 0 -Width 100 -Type "secondary" -OnClick { Navigate-Back }
    $panel.Controls.Add($btnBack)
    
    $btnQuit = New-Button -Text "Quitter" -X 800 -Y 0 -Width 100 -Type "secondary" -OnClick {
        if (Show-Confirm -Message "Voulez-vous vraiment quitter ?") { [System.Windows.Forms.Application]::Exit() }
    }
    $panel.Controls.Add($btnQuit)
    
    $dynamicContainer = New-Object System.Windows.Forms.Panel
    $dynamicContainer.Location = New-Object System.Drawing.Point(50, 100)
    $dynamicContainer.Size = New-Object System.Drawing.Size(800, 500)
    $dynamicContainer.AutoScroll = $true
    $panel.Controls.Add($dynamicContainer)
    
    $refreshUI = {
        $dynamicContainer.Controls.Clear()
        $nbTournees = Get-NbTournees
        
        if ($nbTournees -eq 0) {
            $lblEmpty = New-Object System.Windows.Forms.Label
            $lblEmpty.Text = "⚠️ Aucune tournée définie. Retournez à l'étape précédente."
            $lblEmpty.ForeColor = [System.Drawing.Color]::Red
            $lblEmpty.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
            $lblEmpty.Location = New-Object System.Drawing.Point(20, 20)
            $lblEmpty.Size = New-Object System.Drawing.Size(500, 40)
            $dynamicContainer.Controls.Add($lblEmpty)
            return
        }
        
        $agents = Get-agentsList
        $vehicules = Get-VehiculesList
        $affectations = Get-Affectations
        $yPos = 10
        
        for ($i = 1; $i -le $nbTournees; $i++) {
            $card = New-Object System.Windows.Forms.GroupBox
            $card.Text = "Tournée n°$i"
            $card.Location = New-Object System.Drawing.Point(10, $yPos)
            $card.Size = New-Object System.Drawing.Size(750, 100)
            $card.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
            
            $lblColl = New-Object System.Windows.Forms.Label
            $lblColl.Text = "Agent :"
            $lblColl.Location = New-Object System.Drawing.Point(20, 35)
            $lblColl.Size = New-Object System.Drawing.Size(80, 25)
            $card.Controls.Add($lblColl)
            
            $cmbColl = New-Object System.Windows.Forms.ComboBox
            $cmbColl.Location = New-Object System.Drawing.Point(110, 33)
            $cmbColl.Size = New-Object System.Drawing.Size(250, 25)
            $cmbColl.DropDownStyle = "DropDownList"
            foreach ($c in $agents) { $cmbColl.Items.Add($c) }
            if ($cmbColl.Items.Count -gt 0) { $cmbColl.SelectedIndex = 0 }
            $card.Controls.Add($cmbColl)
            
            $lblVeh = New-Object System.Windows.Forms.Label
            $lblVeh.Text = "Véhicule :"
            $lblVeh.Location = New-Object System.Drawing.Point(20, 65)
            $lblVeh.Size = New-Object System.Drawing.Size(80, 25)
            $card.Controls.Add($lblVeh)
            
            $cmbVeh = New-Object System.Windows.Forms.ComboBox
            $cmbVeh.Location = New-Object System.Drawing.Point(110, 63)
            $cmbVeh.Size = New-Object System.Drawing.Size(250, 25)
            $cmbVeh.DropDownStyle = "DropDownList"
            foreach ($v in $vehicules) { $cmbVeh.Items.Add($v) }
            if ($cmbVeh.Items.Count -gt 0) { $cmbVeh.SelectedIndex = 0 }
            $card.Controls.Add($cmbVeh)
            
            $saved = $affectations[$i]
            if ($saved -and $saved.Agent) {
                $idx = $cmbColl.Items.IndexOf($saved.Agent)
                if ($idx -ge 0) { $cmbColl.SelectedIndex = $idx }
            }
            if ($saved -and $saved.Vehicule) {
                $idx = $cmbVeh.Items.IndexOf($saved.Vehicule)
                if ($idx -ge 0) { $cmbVeh.SelectedIndex = $idx }
            }
            
            $cmbColl.Add_SelectedIndexChanged({
                $box = $this.Parent
                $num = [int]($box.Text -replace 'Tournée n°', '')
                $vehBox = $box.Controls | Where-Object { $_ -is [System.Windows.Forms.ComboBox] -and $_ -ne $this }
                Set-Affectation -TourneeId $num -Agent $this.SelectedItem -Vehicule $vehBox.SelectedItem
            }.GetNewClosure())
            
            $cmbVeh.Add_SelectedIndexChanged({
                $box = $this.Parent
                $num = [int]($box.Text -replace 'Tournée n°', '')
                $collBox = $box.Controls | Where-Object { $_ -is [System.Windows.Forms.ComboBox] -and $_ -ne $this }
                Set-Affectation -TourneeId $num -Agent $collBox.SelectedItem -Vehicule $this.SelectedItem
            }.GetNewClosure())
            
            $dynamicContainer.Controls.Add($card)
            $yPos += 110
        }
        
        $btnValidate = New-Button -Text "✓ VALIDER TOUTES LES AFFECTATIONS" -X 250 -Y ($yPos + 10) -Width 280 -Height 45 -Type "primary" -OnClick {
            $affectations = Get-Affectations
            $count = ($affectations.Keys | Where-Object { $affectations[$_].Agent }).Count
            $date = Get-Date
            Show-Modal -Title "Succès" -Message "✅ $count affectations sauvegardées pour le $date"
        }
        $dynamicContainer.Controls.Add($btnValidate)
    }
    
    & $refreshUI
    $panel.Tag = @{ RefreshData = $refreshUI }
    return $panel
}

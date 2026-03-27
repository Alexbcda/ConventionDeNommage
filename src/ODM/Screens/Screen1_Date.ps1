# Screen1_Date.ps1 - Écran de choix de la date

function Show-Screen1_Date {
    param(
        $DateSelectionnee,
        $NextScreen
    )
    
    Write-Host "[DEBUG] Show-Screen1_Date appelée" -ForegroundColor Cyan
    Write-Host "[DEBUG] NextScreen reçu = $($NextScreen)" -ForegroundColor Yellow
    
    if ($NextScreen) {
        Write-Host "[DEBUG] NextScreen existe, type: $($NextScreen.GetType())" -ForegroundColor Green
    } else {
        Write-Host "[DEBUG] NextScreen est NULL !!!" -ForegroundColor Red
    }
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Top"
    $panel.Height = 70
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    
    # Sauvegarder dans des variables de script
    $script:currentPanel = $panel
    $script:nextScreen = $NextScreen
    $script:datePickerRef = $null
    
    Write-Host "[DEBUG] script:nextScreen après affectation = $($script:nextScreen)" -ForegroundColor Yellow
    
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Choisir une date"
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $lbl.Location = New-Object System.Drawing.Point(35, 22)
    $lbl.Size = New-Object System.Drawing.Size(130, 25)
    $panel.Controls.Add($lbl)
    
    $datePicker = New-Object System.Windows.Forms.DateTimePicker
    $datePicker.Format = "Short"
    $datePicker.Value = (Get-Date)
    $datePicker.Size = New-Object System.Drawing.Size(120, 25)
    $datePicker.Location = New-Object System.Drawing.Point(180, 20)
    $panel.Controls.Add($datePicker)
    $script:datePickerRef = $datePicker
    
    $btnValider = New-Object System.Windows.Forms.Button
    $btnValider.Text = "VALIDER"
    $btnValider.Size = New-Object System.Drawing.Size(146, 45)
    $btnValider.Location = New-Object System.Drawing.Point(315, 15)
    $btnValider.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $btnValider.FlatStyle = "Flat"
    $btnValider.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $btnValider.FlatAppearance.BorderSize = 2
    $btnValider.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $btnValider.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btnValider.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnValider.TabStop = $false
    
    $btnValider.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(229, 90, 42)
        $this.BackColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $btnValider.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
    
    $btnValider.Add_Click({
        Write-Host "`n=== BOUTON VALIDER CLIQUÉ ===" -ForegroundColor Green
        Write-Host "Date: $($script:datePickerRef.Value)" -ForegroundColor Yellow
        Write-Host "[DEBUG] Au moment du clic - script:nextScreen = $($script:nextScreen)" -ForegroundColor Red
        
        if ($script:nextScreen) {
            Write-Host "[DEBUG] script:nextScreen existe, type: $($script:nextScreen.GetType())" -ForegroundColor Green
        } else {
            Write-Host "[DEBUG] script:nextScreen est NULL - problème détecté !" -ForegroundColor Red
            Write-Host "[DEBUG] script:currentPanel = $($script:currentPanel)" -ForegroundColor Gray
            Write-Host "[DEBUG] script:currentPanel.Tag = $($script:currentPanel.Tag)" -ForegroundColor Gray
        }
        
        # Cacher le panel courant
        $script:currentPanel.Visible = $false
        Write-Host "[DEBUG] Panel courant caché" -ForegroundColor Gray
        
        # Afficher l'écran suivant
        if ($script:nextScreen) {
            $script:nextScreen.Visible = $true
            Write-Host "✅ Écran suivant affiché" -ForegroundColor Green
        } else {
            Write-Host "❌ ERREUR: nextScreen est null" -ForegroundColor Red
        }
    })
    $panel.Controls.Add($btnValider)
    
    Write-Host "[DEBUG] Show-Screen1_Date retourne le panel" -ForegroundColor Cyan
    return $panel
}
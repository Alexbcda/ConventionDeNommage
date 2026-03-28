# Screen1_Date.ps1 - Écran de choix de la date avec logs

function Show-Screen1_Date {
    param(
        $DateSelectionnee,
        $NextScreen
    )
    
    Write-Host "[DEBUG] ========== SCREEN1_DATE DÉMARRAGE ==========" -ForegroundColor Cyan
    Write-Host "[DEBUG] NextScreen reçu = $($NextScreen)" -ForegroundColor Yellow
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Top"
    $panel.Height = 70
    $panel.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    
    # Sauvegarder dans des variables
    $script:currentPanelDate = $panel
    $script:nextScreenDate = $NextScreen
    $script:datePickerRef = $null
    
    Write-Host "[DEBUG] script:nextScreenDate = $($script:nextScreenDate)" -ForegroundColor Yellow
    
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Choisir une date"
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
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
        Write-Host "[DEBUG] ========== BOUTON VALIDER (SCREEN1) ==========" -ForegroundColor Green
        Write-Host "[DEBUG] Date: $($script:datePickerRef.Value)" -ForegroundColor Yellow
        Write-Host "[DEBUG] script:nextScreenDate = $($script:nextScreenDate)" -ForegroundColor Yellow
        
        # Cacher le panel courant
        $script:currentPanelDate.Visible = $false
        Write-Host "[DEBUG] Panel date caché" -ForegroundColor Gray
        
        # Afficher l'écran suivant
        if ($script:nextScreenDate) {
            $script:nextScreenDate.Visible = $true
            Write-Host "[DEBUG] ✅ Écran suivant (Screen2) affiché" -ForegroundColor Green
        } else {
            Write-Host "[DEBUG] ❌ ERREUR: nextScreenDate est null" -ForegroundColor Red
        }
    })
    $panel.Controls.Add($btnValider)
    
    Write-Host "[DEBUG] ========== SCREEN1_DATE TERMINÉ ==========" -ForegroundColor Cyan
    return $panel
}


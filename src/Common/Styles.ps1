# Styles.ps1 - Styles communs (bouton CERTIFICAT)

function Apply-CertificatStyle {
    param($Button)
    
    $Button.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $Button.FlatStyle = "Flat"
    $Button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
    $Button.FlatAppearance.BorderSize = 2
    $Button.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $Button.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Button.TabStop = $false
    
    $Button.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(229, 90, 42)
        $this.BackColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $Button.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(255, 107, 53)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
}

function Apply-QuitterStyle {
    param($Button)
    
    $Button.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
    $Button.FlatStyle = "Flat"
    $Button.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $Button.FlatAppearance.BorderSize = 2
    $Button.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    $Button.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Button.TabStop = $false
    
    $Button.Add_MouseEnter({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
        $this.BackColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
        $this.ForeColor = [System.Drawing.Color]::White
    })
    $Button.Add_MouseLeave({
        $this.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
        $this.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
        $this.ForeColor = [System.Drawing.Color]::FromArgb(39, 39, 39)
    })
}

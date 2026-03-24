# ODMViewer.ps1 - Version qui fonctionne

function Show-ODMViewer {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $p = New-Object System.Windows.Forms.Panel
    $p.BackColor = [System.Drawing.Color]::FromArgb(27, 91, 74)
    $p.Dock = "Fill"
    
    $l = New-Object System.Windows.Forms.Label
    $l.Text = "PLANNING ODM`n`nInterface en cours de développement`n`nLes fonctionnalités seront ajoutées progressivement"
    $l.Font = New-Object System.Drawing.Font("Arial", 14, [System.Drawing.FontStyle]::Bold)
    $l.ForeColor = [System.Drawing.Color]::White
    $l.TextAlign = "MiddleCenter"
    $l.Dock = "Fill"
    $p.Controls.Add($l)
    
    return $p
}

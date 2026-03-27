# Affectation.ps1 - Version test

function Show-Affectation {
    param(
        [int]$nbTournees,
        [System.Windows.Forms.Panel]$panel,
        [array]$collecteurs,
        [array]$vehicules,
        [ref]$affectations
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $panel.Controls.Clear()
    
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "TEST - $nbTournees tournees"
    $lbl.Location = New-Object System.Drawing.Point(35, 20)
    $lbl.Size = New-Object System.Drawing.Size(300, 30)
    $panel.Controls.Add($lbl)
    
    return @()
}

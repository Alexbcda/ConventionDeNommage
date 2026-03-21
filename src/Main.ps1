[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

. "$scriptPath\Config.ps1"
. "$scriptPath\Core\Rename.ps1"
. "$scriptPath\Core\TemplateManager.ps1"
. "$scriptPath\Core\TemplateEditor.ps1"
. "$scriptPath\GUI.ps1"

function Find-PDFFile {
    param([string]$Path)
    
    if ($Path -and (Test-Path $Path)) { return $Path }
    
    if ($Path) {
        $dossier = Split-Path $Path -Parent
        if ($dossier -and (Test-Path $dossier)) {
            $fichiers = Get-ChildItem $dossier -Filter "*.pdf" -File
            if ($fichiers) { return $fichiers[0].FullName }
        }
    }
    
    $fichiers = Get-ChildItem (Get-Location) -Filter "*.pdf" -File
    if ($fichiers) { return $fichiers[0].FullName }
    
    return $null
}

if ($args.Count -gt 0) {
    $fichierPDF = $args[0] -replace '^"|"$', '' -replace "'", ''
    $fichierTrouve = Find-PDFFile $fichierPDF
    if ($fichierTrouve) {
        Start-GUI -FichierPDF $fichierTrouve
    } else {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "Aucun fichier PDF trouvé dans le dossier courant.`n`nVeuillez sélectionner un fichier PDF.", 
            "Erreur", 
            [System.Windows.Forms.MessageBoxButtons]::OK, 
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
} else {
    Add-Type -AssemblyName System.Windows.Forms
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Filter = "Fichiers PDF (*.pdf)|*.pdf"
    $openFileDialog.Title = "Sélectionner un fichier PDF à renommer"
    
    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Start-GUI -FichierPDF $openFileDialog.FileName
    }
}

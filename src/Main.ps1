[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

. "$scriptPath\Config.ps1"
. "$scriptPath\Core\TemplateManager.ps1"
. "$scriptPath\Core\Rename.ps1"
. "$scriptPath\Core\TemplateEditor.ps1"
. "$scriptPath\ODM\ODMViewer.ps1"
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

# Lancer l'interface avec onglets
# Si un fichier est passé en paramètre, on l'utilise pour l'onglet Convention de nommage
if ($args.Count -gt 0) {
    $fichierPDF = $args[0] -replace '^"|"$', '' -replace "'", ''
    $fichierTrouve = Find-PDFFile $fichierPDF
    if ($fichierTrouve) {
        Start-GUI -FichierPDF $fichierTrouve
    } else {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "Aucun fichier PDF trouvé dans le dossier courant.`n`nL'interface va s'ouvrir sans fichier sélectionné.", 
            "Information", 
            [System.Windows.Forms.MessageBoxButtons]::OK, 
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        Start-GUI -FichierPDF $null
    }
} else {
    # Si pas de fichier en paramètre, on lance quand même l'interface
    Start-GUI -FichierPDF $null
}

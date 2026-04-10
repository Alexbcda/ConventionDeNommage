param([string]$FilePDF)

# Lancer l'application simple
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$scriptPath\RenommerPDF.ps1" -FichierPDF $FilePDF

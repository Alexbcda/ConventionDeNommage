# Rename.ps1 - Fonction de renommage dynamique

function Rename-PDFDynamic {
    param(
        [string]$TemplateId,
        [string]$FichierPDF,
        [string]$UserText,
        [datetime]$DateSelectionnee
    )
    
    . "$PSScriptRoot\TemplateManager.ps1"
    
    $templates = Get-Templates
    $template = $templates | Where-Object { $_.id -eq $TemplateId }
    
    if (-not $template) {
        throw "Template non trouvé : $TemplateId"
    }
    
    $cleanText = $UserText -replace '[\\/:*?"<>|]', '_'
    $formattedDate = $DateSelectionnee.ToString($template.dateFormat)
    $nouveauNom = $template.format -replace '{text}', $cleanText -replace '{date}', $formattedDate
    
    if ($template.includeTime -and $template.timeFormat) {
        $formattedTime = Get-Date -Format $template.timeFormat
        $nouveauNom = $nouveauNom -replace '{time}', $formattedTime
    }
    
    if (-not $nouveauNom.EndsWith(".pdf")) {
        $nouveauNom = $nouveauNom + ".pdf"
    }
    
    try {
        $dossier = Split-Path $FichierPDF -Parent
        $nouveauChemin = Join-Path $dossier $nouveauNom

        if (Test-Path $nouveauChemin) {
            Add-Type -AssemblyName System.Windows.Forms
            $result = [System.Windows.Forms.MessageBox]::Show(
                "Le fichier '$nouveauNom' existe déjà. Voulez-vous le remplacer ?",
                "Fichier existant",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            if ($result -eq [System.Windows.Forms.DialogResult]::No) {
                return $false
            }
        }

        Rename-Item -Path $FichierPDF -NewName $nouveauNom -ErrorAction Stop
        return $true
    }
    catch {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "Erreur lors du renommage : $($_.Exception.Message)", 
            "Erreur", 
            [System.Windows.Forms.MessageBoxButtons]::OK, 
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return $false
    }
}

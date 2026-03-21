function Rename-PDFDynamic {
    param(
        [string]$TemplateId,
        [string]$FichierPDF,
        [string]$UserText,
        [datetime]$DateSelectionnee
    )
    
    $templatesPath = Join-Path $PSScriptRoot "..\Data\templates.json"
    $templatesData = Get-Content $templatesPath -Raw | ConvertFrom-Json
    $template = $templatesData.templates | Where-Object { $_.id -eq $TemplateId }
    
    if (-not $template) {
        throw "Template non trouvé : $TemplateId"
    }
    
    $cleanText = $UserText -replace '[\\/:*?"<>|]', '_'
    $formattedDate = $DateSelectionnee.ToString($template.dateFormat)
    $nouveauNom = $template.format -replace '{text}', $cleanText -replace '{date}', $formattedDate
    
    if (-not $nouveauNom.EndsWith(".pdf")) {
        $nouveauNom = $nouveauNom + ".pdf"
    }
    
    try {
        $dossier = Split-Path $FichierPDF -Parent
        $nouveauChemin = Join-Path $dossier $nouveauNom

        if (Test-Path $nouveauChemin) {
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
        [System.Windows.Forms.MessageBox]::Show(
            "Erreur lors du renommage : $($_.Exception.Message)", 
            "Erreur", 
            [System.Windows.Forms.MessageBoxButtons]::OK, 
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return $false
    }
}

Export-ModuleMember -Function Rename-PDFDynamic

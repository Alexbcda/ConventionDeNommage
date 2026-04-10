# ConventionNommageLogic.ps1 - Logique métier

function Invoke-CNRenameAction {
    param(
        [string]$TemplateId, 
        [string]$FichierPDF, 
        [string]$UserText, 
        [datetime]$DateSelectionnee
    )

    $templatePath = Join-Path $PSScriptRoot "..\..\..\Data\templates.json"
    
    if (-not (Test-Path $templatePath)) {
        Write-Host "[CN-Logic] templates.json non trouvé à: $templatePath" -ForegroundColor Red
        throw "Fichier templates.json non trouvé"
    }
    
    $templates = (Get-Content $templatePath -Raw | ConvertFrom-Json).templates
    $template = $templates | Where-Object { $_.id -eq $TemplateId }

    if (-not $template) {
        throw "Template non trouvé : $TemplateId"
    }

    $cleanText = $UserText -replace '[\\/:*?"<>|]', '_'
    $formattedDate = $DateSelectionnee.ToString($template.dateFormat)
    $nouveauNom = $template.format -replace '{text}', $cleanText -replace '{date}', $formattedDate
    
    if (-not $nouveauNom.EndsWith(".pdf")) { 
        $nouveauNom += ".pdf" 
    }

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

    Rename-Item -Path $FichierPDF -NewName $nouveauNom -Force
    return $true
}

Write-Host "[CN-Logic] Chargé" -ForegroundColor Cyan

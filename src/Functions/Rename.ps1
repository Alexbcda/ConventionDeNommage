# Fonction pour renommer les PDF selon le type
function Rename-PDF {
    param(
        [string]$Type,
        [string]$FichierPDF,
        [System.Windows.Forms.TextBox]$TextBox,
        [string]$Placeholder,
        [datetime]$DateSelectionnee,
        [bool]$EstModePlaceholder
    )

    # Récupérer le texte saisi
    $nomSaisi = $TextBox.Text.Trim()
    
    # Si c'est le placeholder, on vide
    if ($nomSaisi -eq $Placeholder) {
        $nomSaisi = ""
    }
    
    # Vérifier si le champ n'est pas vide
    if ([string]::IsNullOrWhiteSpace($nomSaisi)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Veuillez renseigner le point de collecte", 
            "Champ obligatoire", 
            [System.Windows.Forms.MessageBoxButtons]::OK, 
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return $false
    }

    # Nettoyer le nom saisi
    $nomSaisi = $nomSaisi -replace '[\\/:*?"<>|]', '_'
    
    # Formater la date selon le type
    $nouveauNom = ""
    
    switch ($Type) {
        "certificat" {
            $dateFormatee = $DateSelectionnee.ToString("dd.MM.yyyy")
            $nouveauNom = "Certificat de Destruction-$nomSaisi-du $dateFormatee.pdf"
        }
        "planner" {
            $dateFormatee = $DateSelectionnee.ToString("yyyyMMdd")
            $nouveauNom = "$dateFormatee-$nomSaisi.pdf"
        }
        "francetravail" {
            $dateFormatee = $DateSelectionnee.ToString("yyyyMMdd")
            $nouveauNom = "$dateFormatee-$nomSaisi.pdf"
        }
        default {
            [System.Windows.Forms.MessageBox]::Show(
                "Type de document inconnu", 
                "Erreur", 
                [System.Windows.Forms.MessageBoxButtons]::OK, 
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            return $false
        }
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

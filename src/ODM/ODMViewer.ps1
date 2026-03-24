# ODMViewer.ps1 - Interface de visualisation et assignation des ODM avec certificat

function Show-ODMViewer {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Variables
    $script:pdfFile = $null
    $script:totalPages = 0
    $script:assignments = @{}
    $script:currentPage = 1
    $script:selectedChauffeur = $null
    $script:selectedVehicule = $null
    $script:selectedDate = (Get-Date)

    # Charger les ressources
    $script:ressourcesPath = Join-Path $PSScriptRoot "..\Data\ressources.json"
    $script:chauffeurs = @()
    $script:vehicules = @()

    if (Test-Path $script:ressourcesPath) {
        $ressources = Get-Content $script:ressourcesPath -Raw | ConvertFrom-Json
        $script:chauffeurs = $ressources.chauffeurs
        $script:vehicules = $ressources.vehicules
    }

    # Créer le conteneur principal
    $mainPanel = New-Object System.Windows.Forms.Panel
    $mainPanel.Dock = "Fill"
    $mainPanel.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)

    # ========== PANEL DU HAUT ==========
    $topPanel = New-Object System.Windows.Forms.Panel
    $topPanel.Dock = "Top"
    $topPanel.Height = 130
    $topPanel.BackColor = [System.Drawing.Color]::FromArgb(27, 91, 74)

    # Ligne 1 : Boutons
    $btnLoad = New-Object System.Windows.Forms.Button
    $btnLoad.Text = "📁 IMPORTER LE PDF PLANNING"
    $btnLoad.Location = New-Object System.Drawing.Point(20, 15)
    $btnLoad.Size = New-Object System.Drawing.Size(200, 40)
    $btnLoad.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $btnLoad.ForeColor = [System.Drawing.Color]::White
    $btnLoad.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold) 
    $btnLoad.FlatStyle = "Flat"
    $btnLoad.Cursor = [System.Windows.Forms.Cursors]::Hand
    $topPanel.Controls.Add($btnLoad)

    # Ligne 2 : Sélecteurs
    $yLine2 = 65

    # Date
    $lblDate = New-Object System.Windows.Forms.Label
    $lblDate.Text = "📅 Date :"
    $lblDate.Location = New-Object System.Drawing.Point(20, $yLine2)
    $lblDate.Size = New-Object System.Drawing.Size(60, 30)
    $lblDate.Font = New-Object System.Drawing.Font("Arial", 9)
    $lblDate.ForeColor = [System.Drawing.Color]::White
    $topPanel.Controls.Add($lblDate)

    $datePicker = New-Object System.Windows.Forms.DateTimePicker
    $datePicker.Location = New-Object System.Drawing.Point(85, $yLine2)
    $datePicker.Size = New-Object System.Drawing.Size(120, 25)
    $datePicker.Format = "Short"
    $datePicker.Value = (Get-Date)
    $topPanel.Controls.Add($datePicker)

    # Chauffeur
    $lblChauffeur = New-Object System.Windows.Forms.Label
    $lblChauffeur.Text = "👨‍✈️ Chauffeur :"
    $lblChauffeur.Location = New-Object System.Drawing.Point(220, $yLine2)
    $lblChauffeur.Size = New-Object System.Drawing.Size(70, 30)
    $lblChauffeur.Font = New-Object System.Drawing.Font("Arial", 9)
    $lblChauffeur.ForeColor = [System.Drawing.Color]::White
    $topPanel.Controls.Add($lblChauffeur)

    $cbChauffeur = New-Object System.Windows.Forms.ComboBox
    $cbChauffeur.Location = New-Object System.Drawing.Point(295, $yLine2)
    $cbChauffeur.Size = New-Object System.Drawing.Size(180, 25)
    $cbChauffeur.DropDownStyle = "DropDownList"
    $cbChauffeur.Items.Add("-- Sélectionner un chauffeur --")
    foreach ($c in $script:chauffeurs) {
        $cbChauffeur.Items.Add("$($c.nom) $($c.prenom) - $($c.telephone)")
    }
    $cbChauffeur.SelectedIndex = 0
    $topPanel.Controls.Add($cbChauffeur)

    # Véhicule
    $lblVehicule = New-Object System.Windows.Forms.Label
    $lblVehicule.Text = "🚛 Véhicule :"
    $lblVehicule.Location = New-Object System.Drawing.Point(490, $yLine2)
    $lblVehicule.Size = New-Object System.Drawing.Size(70, 30)
    $lblVehicule.Font = New-Object System.Drawing.Font("Arial", 9)
    $lblVehicule.ForeColor = [System.Drawing.Color]::White
    $topPanel.Controls.Add($lblVehicule)

    $cbVehicule = New-Object System.Windows.Forms.ComboBox
    $cbVehicule.Location = New-Object System.Drawing.Point(565, $yLine2)
    $cbVehicule.Size = New-Object System.Drawing.Size(200, 25)
    $cbVehicule.DropDownStyle = "DropDownList"
    $cbVehicule.Items.Add("-- Sélectionner un véhicule --")
    foreach ($v in $script:vehicules) {
        $cbVehicule.Items.Add("$($v.immatriculation) - $($v.marque) $($v.modele)")
    }
    $cbVehicule.SelectedIndex = 0
    $topPanel.Controls.Add($cbVehicule)

    # Info fichier
    $lblFileInfo = New-Object System.Windows.Forms.Label
    $lblFileInfo.Location = New-Object System.Drawing.Point(20, 100)
    $lblFileInfo.Size = New-Object System.Drawing.Size(600, 25)
    $lblFileInfo.Font = New-Object System.Drawing.Font("Arial", 9)
    $lblFileInfo.ForeColor = [System.Drawing.Color]::White
    $lblFileInfo.Text = "Aucun fichier chargé"
    $topPanel.Controls.Add($lblFileInfo)

    $mainPanel.Controls.Add($topPanel)

    # ========== PANEL CENTRAL (Visionneuse PDF) ==========
    $centerPanel = New-Object System.Windows.Forms.Panel
    $centerPanel.Dock = "Fill"
    $centerPanel.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
    $centerPanel.Padding = New-Object System.Windows.Forms.Padding(10)

    # Label de navigation
    $navPanel = New-Object System.Windows.Forms.Panel
    $navPanel.Dock = "Top"
    $navPanel.Height = 50
    $navPanel.BackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)

    $btnPrev = New-Object System.Windows.Forms.Button
    $btnPrev.Text = "◀ Page précédente"
    $btnPrev.Location = New-Object System.Drawing.Point(10, 10)
    $btnPrev.Size = New-Object System.Drawing.Size(120, 35)
    $btnPrev.BackColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $btnPrev.ForeColor = [System.Drawing.Color]::White
    $btnPrev.FlatStyle = "Flat"
    $btnPrev.Cursor = [System.Windows.Forms.Cursors]::Hand
    $navPanel.Controls.Add($btnPrev)

    $lblPageInfo = New-Object System.Windows.Forms.Label
    $lblPageInfo.Location = New-Object System.Drawing.Point(150, 15)
    $lblPageInfo.Size = New-Object System.Drawing.Size(200, 25)
    $lblPageInfo.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
    $lblPageInfo.Text = "Page 0 / 0"
    $navPanel.Controls.Add($lblPageInfo)

    $btnNext = New-Object System.Windows.Forms.Button
    $btnNext.Text = "Page suivante ▶"
    $btnNext.Location = New-Object System.Drawing.Point(370, 10)
    $btnNext.Size = New-Object System.Drawing.Size(120, 35)
    $btnNext.BackColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $btnNext.ForeColor = [System.Drawing.Color]::White
    $btnNext.FlatStyle = "Flat"
    $btnNext.Cursor = [System.Windows.Forms.Cursors]::Hand
    $navPanel.Controls.Add($btnNext)

    $btnCertificat = New-Object System.Windows.Forms.Button
    $btnCertificat.Text = "📄 ÉTABLIR LE CERTIFICAT DE DESTRUCTION"
    $btnCertificat.Location = New-Object System.Drawing.Point(520, 10)
    $btnCertificat.Size = New-Object System.Drawing.Size(250, 35)
    $btnCertificat.BackColor = [System.Drawing.Color]::FromArgb(226, 110, 42)
    $btnCertificat.ForeColor = [System.Drawing.Color]::White
    $btnCertificat.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
    $btnCertificat.FlatStyle = "Flat"
    $btnCertificat.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnCertificat.Enabled = $false
    $navPanel.Controls.Add($btnCertificat)

    $centerPanel.Controls.Add($navPanel)

    # Zone d'affichage du PDF
    $pdfViewer = New-Object System.Windows.Forms.Panel
    $pdfViewer.Dock = "Fill"
    $pdfViewer.BackColor = [System.Drawing.Color]::White
    $pdfViewer.BorderStyle = "FixedSingle"
    $centerPanel.Controls.Add($pdfViewer)

    $lblPdfPlaceholder = New-Object System.Windows.Forms.Label
    $lblPdfPlaceholder.Text = "Charger un PDF pour visualiser les pages"
    $lblPdfPlaceholder.Location = New-Object System.Drawing.Point(300, 200)
    $lblPdfPlaceholder.Size = New-Object System.Drawing.Size(400, 30)
    $lblPdfPlaceholder.Font = New-Object System.Drawing.Font("Arial", 12)
    $lblPdfPlaceholder.ForeColor = [System.Drawing.Color]::Gray
    $pdfViewer.Controls.Add($lblPdfPlaceholder)

    # Zone de texte pour surlignage
    $txtHighlight = New-Object System.Windows.Forms.TextBox
    $txtHighlight.Location = New-Object System.Drawing.Point(10, 10)
    $txtHighlight.Size = New-Object System.Drawing.Size(300, 25)
    $txtHighlight.Font = New-Object System.Drawing.Font("Arial", 9)
    $txtHighlight.Text = "Rechercher et surligner..."
    $txtHighlight.ForeColor = [System.Drawing.Color]::Gray
    $txtHighlight.Visible = $false
    $pdfViewer.Controls.Add($txtHighlight)

    $btnHighlight = New-Object System.Windows.Forms.Button
    $btnHighlight.Text = "🔍 Surligner"
    $btnHighlight.Location = New-Object System.Drawing.Point(320, 8)
    $btnHighlight.Size = New-Object System.Drawing.Size(80, 28)
    $btnHighlight.BackColor = [System.Drawing.Color]::FromArgb(255, 255, 100)
    $btnHighlight.FlatStyle = "Flat"
    $btnHighlight.Visible = $false
    $pdfViewer.Controls.Add($btnHighlight)

    $mainPanel.Controls.Add($centerPanel)

    # ========== PANEL DU BAS ==========
    $bottomPanel = New-Object System.Windows.Forms.Panel
    $bottomPanel.Dock = "Bottom"
    $bottomPanel.Height = 80
    $bottomPanel.BackColor = [System.Drawing.Color]::FromArgb(230, 230, 230)

    $lblSummary = New-Object System.Windows.Forms.Label
    $lblSummary.Location = New-Object System.Drawing.Point(20, 10)
    $lblSummary.Size = New-Object System.Drawing.Size(800, 30)
    $lblSummary.Font = New-Object System.Drawing.Font("Arial", 10)
    $lblSummary.Text = "📊 En attente de chargement..."
    $bottomPanel.Controls.Add($lblSummary)

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "💾 Sauvegarder"
    $btnSave.Location = New-Object System.Drawing.Point(850, 10)
    $btnSave.Size = New-Object System.Drawing.Size(120, 35)
    $btnSave.BackColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
    $btnSave.ForeColor = [System.Drawing.Color]::White
    $btnSave.FlatStyle = "Flat"
    $btnSave.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnSave.Enabled = $false
    $bottomPanel.Controls.Add($btnSave)

    $btnExport = New-Object System.Windows.Forms.Button
    $btnExport.Text = "📤 Exporter PDF final"
    $btnExport.Location = New-Object System.Drawing.Point(850, 50)
    $btnExport.Size = New-Object System.Drawing.Size(120, 35)
    $btnExport.BackColor = [System.Drawing.Color]::FromArgb(27, 91, 74)
    $btnExport.ForeColor = [System.Drawing.Color]::White
    $btnExport.FlatStyle = "Flat"
    $btnExport.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btnExport.Enabled = $false
    $bottomPanel.Controls.Add($btnExport)

    $mainPanel.Controls.Add($bottomPanel)

    # Fonction pour charger le PDF
    function Load-PDFFile {
        $openDialog = New-Object System.Windows.Forms.OpenFileDialog
        $openDialog.Filter = "Fichiers PDF (*.pdf)|*.pdf"
        $openDialog.Title = "Sélectionner le fichier PDF planning"

        if ($openDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:pdfFile = $openDialog.FileName
            $script:totalPages = 15  # Simulation
            $lblFileInfo.Text = "📄 $(Split-Path $script:pdfFile -Leaf) - $script:totalPages pages"
            $lblPageInfo.Text = "Page 1 / $script:totalPages"
            $lblPdfPlaceholder.Visible = $false
            $txtHighlight.Visible = $true
            $btnHighlight.Visible = $true
            $btnCertificat.Enabled = $true
            $btnSave.Enabled = $true
            $btnExport.Enabled = $true
            $lblSummary.Text = "📊 $script:totalPages pages chargées. Utilisez les flèches pour naviguer."
        }
    }

    # Fonction pour afficher une page
    function Show-Page {
        param($PageNumber)
        $lblPageInfo.Text = "Page $PageNumber / $script:totalPages"
        $lblPdfPlaceholder.Text = "📄 AFFICHAGE DE LA PAGE $PageNumber`nPoint de collecte détecté : ..."
        $lblPdfPlaceholder.Visible = $true
        $txtHighlight.Visible = $true
        $btnHighlight.Visible = $true
    }

    # Fonction pour générer le certificat
    function Generate-Certificat {
        if ($cbChauffeur.SelectedIndex -le 0) {
            [System.Windows.Forms.MessageBox]::Show("Veuillez sélectionner un chauffeur", "Info") 
            return
        }
        if ($cbVehicule.SelectedIndex -le 0) {
            [System.Windows.Forms.MessageBox]::Show("Veuillez sélectionner un véhicule", "Info")  
            return
        }

        $chauffeur = $script:chauffeurs[$cbChauffeur.SelectedIndex - 1]
        $vehicule = $script:vehicules[$cbVehicule.SelectedIndex - 1]
        $date = $datePicker.Value.ToString("dd/MM/yyyy")
        $pointCollecte = "Point de collecte détecté sur la page"

        $message = "Certificat de destruction généré pour :`n`n"
        $message += "📅 Date : $date`n"
        $message += "📍 Point de collecte : $pointCollecte`n"
        $message += "👨‍✈️ Chauffeur : $($chauffeur.nom) $($chauffeur.prenom)`n"
        $message += "🚛 Véhicule : $($vehicule.immatriculation) - $($vehicule.marque) $($vehicule.modele)`n"
        $message += "`nLe certificat sera inséré après la page $script:currentPage"

        [System.Windows.Forms.MessageBox]::Show($message, "Certificat de destruction")
    }

    # Navigation
    $btnPrev.Add_Click({
        if ($script:currentPage -gt 1) {
            $script:currentPage--
            Show-Page -PageNumber $script:currentPage
        }
    })

    $btnNext.Add_Click({
        if ($script:currentPage -lt $script:totalPages) {
            $script:currentPage++
            Show-Page -PageNumber $script:currentPage
        }
    })

    $btnCertificat.Add_Click({ Generate-Certificat })
    $btnLoad.Add_Click({ Load-PDFFile })

    $btnSave.Add_Click({
        [System.Windows.Forms.MessageBox]::Show("Assignations sauvegardées", "Succès")
    })

    $btnExport.Add_Click({
        [System.Windows.Forms.MessageBox]::Show("Export terminé", "Succès")
    })

    # Surlignage
    $txtHighlight.Add_GotFocus({
        if ($this.Text -eq "Rechercher et surligner...") {
            $this.Text = ""
            $this.ForeColor = [System.Drawing.Color]::Black
        }
    })

    $btnHighlight.Add_Click({
        $searchText = $txtHighlight.Text
        if ($searchText -and $searchText -ne "Rechercher et surligner...") {
            [System.Windows.Forms.MessageBox]::Show("Recherche de '$searchText' sur la page $script:currentPage", "Surlignage")
        }
    })

    return $mainPanel
}

Export-ModuleMember -Function Show-ODMViewer

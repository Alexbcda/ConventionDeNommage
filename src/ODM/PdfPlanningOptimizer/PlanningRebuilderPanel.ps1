. "$PSScriptRoot\Services\PlanningRebuilder.ps1"
. "$PSScriptRoot\..\..\Common\Styles.ps1"

function Show-PlanningRebuilderPanel {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $script:PlanningPdfPath = $null
    $script:PlanningExcelPath = $null

    $panel = [System.Windows.Forms.Panel]::new()
    $panel.Name = "PlanningRebuilderPanel"
    $panel.Dock = "Fill"
    $panel.BackColor = $script:CouleurGrisFond
    $panel.Padding = [System.Windows.Forms.Padding]::new(20)

    $lblTitle = [System.Windows.Forms.Label]::new()
    $lblTitle.Text = "Edition du planning"
    $lblTitle.Font = $script:PoliceTitreGestionFenetre
    $lblTitle.ForeColor = $script:CouleurOrange
    $lblTitle.Location = [System.Drawing.Point]::new(20, 20)
    $lblTitle.Size = [System.Drawing.Size]::new(500, 50)
    $panel.Controls.Add($lblTitle)

    $lblPdf = [System.Windows.Forms.Label]::new()
    $lblPdf.Name = "lblPdf"
    $lblPdf.Text = "PDF: non selectionne"
    $lblPdf.Font = $script:PoliceLabelSecondaireFenetre
    $lblPdf.ForeColor = $script:CouleurTexteSecondairePanel
    $lblPdf.Location = [System.Drawing.Point]::new(20, 80)
    $lblPdf.Size = [System.Drawing.Size]::new(1100, 22)
    $panel.Controls.Add($lblPdf)

    $lblExcel = [System.Windows.Forms.Label]::new()
    $lblExcel.Name = "lblExcel"
    $lblExcel.Text = "Excel: non selectionne"
    $lblExcel.Font = $script:PoliceLabelSecondaireFenetre
    $lblExcel.ForeColor = $script:CouleurTexteSecondairePanel
    $lblExcel.Location = [System.Drawing.Point]::new(20, 105)
    $lblExcel.Size = [System.Drawing.Size]::new(1100, 22)
    $panel.Controls.Add($lblExcel)

    $btnPdf = [System.Windows.Forms.Button]::new()
    Set-BtnBorderStyle -Button $btnPdf -Text "Importer PDF" -BorderColor $script:CouleurBleu -Width 170 -Height 45
    $btnPdf.Location = [System.Drawing.Point]::new(20, 140)
    $panel.Controls.Add($btnPdf)

    $btnExcel = [System.Windows.Forms.Button]::new()
    Set-BtnBorderStyle -Button $btnExcel -Text "Importer Excel" -BorderColor $script:CouleurVert -Width 170 -Height 45
    $btnExcel.Location = [System.Drawing.Point]::new(200, 140)
    $panel.Controls.Add($btnExcel)

    $btnRun = [System.Windows.Forms.Button]::new()
    $btnRun.Name = 'btnRunPlanning'
    Set-BtnBorderStyle -Button $btnRun -Text "Lancer le traitement" -BorderColor $script:CouleurCertificat -Width 220 -Height 45
    $btnRun.Location = [System.Drawing.Point]::new(380, 140)
    $panel.Controls.Add($btnRun)

    $listResult = [System.Windows.Forms.ListBox]::new()
    $listResult.Name = "listResult"
    $listResult.Location = [System.Drawing.Point]::new(20, 200)
    $listResult.Size = [System.Drawing.Size]::new(1100, 220)
    $listResult.Anchor = "Top,Left,Right"
    $panel.Controls.Add($listResult)

    $txtDebug = [System.Windows.Forms.TextBox]::new()
    $txtDebug.Name = "txtDebug"
    $txtDebug.Multiline = $true
    $txtDebug.ScrollBars = "Vertical"
    $txtDebug.ReadOnly = $true
    $txtDebug.Location = [System.Drawing.Point]::new(20, 435)
    $txtDebug.Size = [System.Drawing.Size]::new(1100, 230)
    $txtDebug.Anchor = "Top,Bottom,Left,Right"
    $panel.Controls.Add($txtDebug)

    function script:Get-PlanningCtrl {
        param(
            [System.Windows.Forms.Control]$Root,
            [string]$Name,
            [Type]$ExpectedType
        )
        if ($null -eq $Root) { return $null }
        $ctrl = $Root.Controls[$Name]
        if ($null -eq $ctrl) { return $null }
        if ($null -ne $ExpectedType -and $ctrl -isnot $ExpectedType) { return $null }
        return $ctrl
    }

    $btnPdf.Add_Click({
        $ofd = [System.Windows.Forms.OpenFileDialog]::new()
        $ofd.Filter = "PDF (*.pdf)|*.pdf|Tous les fichiers (*.*)|*.*"
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:PlanningPdfPath = $ofd.FileName
            $root = $this.Parent
            $lbl = Get-PlanningCtrl -Root $root -Name "lblPdf" -ExpectedType ([System.Windows.Forms.Label])
            if ($null -ne $lbl) {
                $lbl.Text = "PDF: $($script:PlanningPdfPath)"
            }
        }
    })

    $btnExcel.Add_Click({
        $ofd = [System.Windows.Forms.OpenFileDialog]::new()
        $ofd.Filter = "Excel (*.xlsx;*.xlsm;*.xls)|*.xlsx;*.xlsm;*.xls|Tous les fichiers (*.*)|*.*"
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:PlanningExcelPath = $ofd.FileName
            $root = $this.Parent
            $lbl = Get-PlanningCtrl -Root $root -Name "lblExcel" -ExpectedType ([System.Windows.Forms.Label])
            if ($null -ne $lbl) {
                $lbl.Text = "Excel: $($script:PlanningExcelPath)"
            }
        }
    })

    $onRunPlanning = {
        param($sender, $e)
        $__dbg = ($env:CN_DEBUG_PLANNING_UI -in @('1', 'true')) -or ($env:CN_DEBUG_PIPELINE -in @('1', 'true'))
        if ($__dbg) { Write-Host '[DEBUG] CLICK btnRunPlanning' -ForegroundColor Magenta }
        if ($script:PlanningRebuildUiBusy) {
            if ($__dbg) { Write-Host '[DEBUG] IGNORE: double run / deja en cours' -ForegroundColor DarkYellow }
            return
        }

        $root = $this.Parent
        $list = Get-PlanningCtrl -Root $root -Name "listResult" -ExpectedType ([System.Windows.Forms.ListBox])
        $dbg = Get-PlanningCtrl -Root $root -Name "txtDebug" -ExpectedType ([System.Windows.Forms.TextBox])
        if ([string]::IsNullOrWhiteSpace($script:PlanningPdfPath) -or [string]::IsNullOrWhiteSpace($script:PlanningExcelPath)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Selectionnez d'abord un PDF et un Excel.",
                "Edition planning",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            return
        }

        $script:PlanningRebuildUiBusy = $true
        try {
            if ($__dbg) { Write-Host '[DEBUG] ENTER Start-PlanningRebuild (UI)' -ForegroundColor Magenta }
            if ($null -ne $list) { $list.Items.Clear() }
            if ($null -ne $dbg) { $dbg.Clear() }
            $result = Start-PlanningRebuild -PdfPath $script:PlanningPdfPath -ExcelPath $script:PlanningExcelPath

            if ($null -eq $result) {
                if ($null -ne $list) { $list.Items.Add("Echec : pipeline interrompu (extraction, dates, ou autre arret) — consulter la sortie console.") | Out-Null }
                if ($null -ne $dbg) { $dbg.AppendText("Resultat nul (pipeline arrete).`n") }
                return
            }

            if ($null -ne $list) { $list.Items.Add("Planning final :") | Out-Null }
            foreach ($line in @($result.ReorderedPlanning)) {
                if ($null -ne $list) { $list.Items.Add(("{0} -> {1} [{2}]" -f $line.FinalOrder, $line.ClientName, $line.MatchScore)) | Out-Null }
            }

            if ($null -ne $dbg) { $dbg.AppendText(("Colonne detectee: onglet={0}; colonne={1}; header={2}" -f $result.ExcelColumn.SheetName, $result.ExcelColumn.ColumnIndex, $result.ExcelColumn.HeaderText) + [Environment]::NewLine) }
            if ($null -ne $dbg) { $dbg.AppendText(("Non matches: {0}" -f @($result.MatchResult.Missing).Count) + [Environment]::NewLine) }
            if ($null -ne $dbg) { $dbg.AppendText(("Doublons: {0}" -f @($result.MatchResult.Duplicates).Count) + [Environment]::NewLine) }
            foreach ($m in @($result.MatchResult.Missing)) {
                if ($null -ne $dbg) { $dbg.AppendText(("[MISS 0] {0}" -f $m.Label) + [Environment]::NewLine) }
            }
            foreach ($d in @($result.MatchResult.Duplicates)) {
                if ($null -ne $dbg) { $dbg.AppendText(("[DUP] Excel#{0} page={1} label={2}" -f $d.ExcelOrder, $d.PageNumber, $d.Label) + [Environment]::NewLine) }
            }
        }
        catch {
            if ($null -ne $dbg) { $dbg.AppendText(("ERREUR: {0}" -f $_.Exception.Message) + [Environment]::NewLine) }
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                "Echec traitement planning",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
        finally {
            $script:PlanningRebuildUiBusy = $false
        }
    }

    if ($null -eq $script:PlanningRunHandlerRegistry) {
        $script:PlanningRunHandlerRegistry = @{}
    }
    $btnKey = [string]([System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($btnRun))
    if (-not $script:PlanningRunHandlerRegistry.ContainsKey($btnKey)) {
        $null = $btnRun.add_Click($onRunPlanning)
        $script:PlanningRunHandlerRegistry[$btnKey] = $true
    }

    return $panel
}

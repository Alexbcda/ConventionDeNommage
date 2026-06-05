# ============================================================
# ExcelLoader.ps1
# Rôle : Lire le planning (Excel) sans Microsoft Excel installé.
# Moteur : module ImportExcel (EPPlus) — com.net Office COM supprimé.
# ============================================================

function script:Ensure-ImportExcelModule {
    <#
    .SYNOPSIS
        Charge le module ImportExcel ; message explicite si absent.
    #>
    if (-not (Get-Module -Name ImportExcel -ListAvailable -ErrorAction SilentlyContinue)) {
        $msg = @"
[ExcelLoader] Le module « ImportExcel » est requis pour lire les fichiers .xlsx / .xlsm / .xltx sans Excel installé.

Installez-le une fois (compte utilisateur) :
  Install-Module -Name ImportExcel -Scope CurrentUser -Force

Remarques :
- PowerShell 5.1 et 7+ sont en général pris en charge. Les fichiers protégés par mot de passe peuvent
  exiger d’ouvrir le fichier via Open-ExcelPackage -Password '...' (voir documentation ImportExcel).
- Si l’ouverture échoue (fichier verrouillé, copie ouverte ailleurs), copiez le fichier ailleurs puis réessayez.
"@
        throw $msg
    }
    $null = Import-Module ImportExcel -ErrorAction Stop
    if (-not (Get-Command Open-ExcelPackage -ErrorAction SilentlyContinue)) {
        throw "[ExcelLoader] La commande Open-ExcelPackage est introuvable après import du module. Mettez à jour : Update-Module ImportExcel"
    }
}

function script:Get-CellDisplayText {
    param($Cell)
    if ($null -eq $Cell) { return '' }
    try {
        if ($null -ne $Cell.Text -and -not [string]::IsNullOrEmpty([string]$Cell.Text)) {
            return ([string]$Cell.Text).Trim()
        }
    }
    catch { }
    if ($null -ne $Cell.Value) { return $Cell.Value.ToString().Trim() }
    return ''
}

function Test-ExcelFileIntegrity {
    <#
    .SYNOPSIS
        Validation binaire d'un fichier .xlsx/.xlsm : magic bytes (PK/ZIP), structure ZIP lisible,
        presence d'au moins un worksheet dans xl/worksheets/. Ne charge pas EPPlus/ImportExcel.
    .OUTPUTS
        PSCustomObject avec MagicBytesOk, ZipStructureOk, HasWorksheets, IsValid, Error.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $result = [pscustomobject]@{
        Path           = $Path
        MagicBytesOk   = $false
        ZipStructureOk = $false
        HasWorksheets  = $false
        IsValid        = $false
        FileSizeBytes  = 0
        Error          = $null
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $result.Error = "Fichier introuvable: $Path"
        return $result
    }
    try {
        $fi = Get-Item -LiteralPath $Path
        $result.FileSizeBytes = $fi.Length
        if ($fi.Length -lt 22) {
            $result.Error = "Fichier trop petit pour un ZIP valide ($($fi.Length) octets)"
            return $result
        }

        $fs = [System.IO.File]::OpenRead($fi.FullName)
        try {
            $header = [byte[]]::new(4)
            [void]$fs.Read($header, 0, 4)
        }
        finally { $fs.Dispose() }

        $result.MagicBytesOk = ($header[0] -eq 0x50 -and $header[1] -eq 0x4B -and $header[2] -eq 0x03 -and $header[3] -eq 0x04)
        if (-not $result.MagicBytesOk) {
            $result.Error = ("Signature invalide: {0} (attendu: 50-4B-03-04 / PK)" -f [BitConverter]::ToString($header))
            return $result
        }

        $zip = [System.IO.Compression.ZipFile]::OpenRead($fi.FullName)
        try {
            $result.ZipStructureOk = $true
            $wsEntries = @($zip.Entries | Where-Object { $_.FullName -like 'xl/worksheets/*' -and $_.FullName -notlike '*/' })
            $result.HasWorksheets = ($wsEntries.Count -gt 0)
        }
        finally { $zip.Dispose() }

        $result.IsValid = $result.MagicBytesOk -and $result.ZipStructureOk -and $result.HasWorksheets
        if (-not $result.HasWorksheets) {
            $result.Error = "Archive ZIP valide mais aucun worksheet dans xl/worksheets/"
        }
    }
    catch {
        $result.Error = $_.Exception.Message
    }
    return $result
}

function script:Write-PlanningExcelLoadUiLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    if (Get-Command Write-PlanningRebuildUiLog -ErrorAction SilentlyContinue) {
        Write-PlanningRebuildUiLog $Message
    }
    else {
        Write-Host $Message -ForegroundColor DarkGray
    }
}

function script:Import-ExcelWorkbookToGrids {
    <#
    .SYNOPSIS
        Ouvre le classeur via ImportExcel/EPPlus et retourne la même forme qu’ex-Excel COM :
        { Path, Sheets = @( { Name, RowCount, ColCount, Grid = string[][] } ) }
        Index Grid : 0-based lignes / colonnes (chaînes).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$Password = $null,
        [scriptblock]$ReportProgress = $null
    )
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not (Test-Path -LiteralPath $resolved)) { throw "Fichier introuvable: $Path" }
    $ext = [System.IO.Path]::GetExtension($resolved).ToLowerInvariant()
    if ($ext -eq '.xls' -or $ext -eq '.xlsb') {
        throw "[ExcelLoader] Le format binaire '$ext' n'est pas géré. Enregistrez le fichier au format .xlsx ou .xlsm, ou utilisez un export CSV en secours."
    }

    script:Write-PlanningExcelLoadUiLog '[EXCEL] Decompression du fichier Excel...'
    if ($null -ne $ReportProgress) {
        & $ReportProgress 0.07 'Decompression du fichier...'
    }

    $package = $null
    try {
        if ([string]::IsNullOrEmpty($Password)) {
            $package = Open-ExcelPackage -Path $resolved
        }
        else {
            $package = Open-ExcelPackage -Path $resolved -Password $Password
        }
    }
    catch {
        $detail = $_.Exception.Message
        if ($detail -match 'password|protected|chiff' -or $detail -match 'InvalidData|cannot open') {
            $detail += " — Les mots de passe de classeur peuvent necessiter -Password sur Open-ExcelPackage, ou l'environnement Windows PowerShell 5.1 (voir module ImportExcel / EPPlus)."
        }
        throw "[ExcelLoader] Impossible d'ouvrir le classeur: $detail"
    }

    if ($null -eq $package) {
        throw "[ExcelLoader] Open-ExcelPackage a retourné une valeur nulle. Le fichier est-il un classeur .xlsx/.xlsm valide ?"
    }

    try {
        $sheets = [System.Collections.Generic.List[object]]::new()
        $totalSheets = @($package.Workbook.Worksheets).Count
        if ($totalSheets -lt 1) { $totalSheets = 1 }
        $sheetIndex = 0
        script:Write-PlanningExcelLoadUiLog ("[EXCEL] Analyse des feuilles ({0} feuille(s))..." -f $totalSheets)
        if ($null -ne $ReportProgress) {
            & $ReportProgress 0.075 ("Analyse des feuilles ({0} feuille(s))..." -f $totalSheets)
        }

        foreach ($ws in $package.Workbook.Worksheets) {
            $sheetIndex++
            $name = [string]$ws.Name
            $sheetDetail = ("Lecture feuille {0}/{1} : '{2}'" -f $sheetIndex, $totalSheets, $name)
            $sheetSubRatio = 0.08 + (($sheetIndex / [double]$totalSheets) * 0.10)
            script:Write-PlanningExcelLoadUiLog ("[EXCEL] Lecture de la feuille {0}/{1} : '{2}'" -f $sheetIndex, $totalSheets, $name)
            if ($null -ne $ReportProgress) {
                & $ReportProgress $sheetSubRatio $sheetDetail
            }

            $dim = $ws.Dimension
            if ($null -eq $dim) {
                [void]$sheets.Add([pscustomobject]@{
                    Name     = $name
                    RowCount = 0
                    ColCount = 0
                    Grid     = @()
                })
                continue
            }
            $sheetGrid = script:Import-ExcelWorksheetToGrid -Worksheet $ws
            [void]$sheets.Add($sheetGrid)
        }
        return [pscustomobject]@{
            Path   = $Path
            Sheets = @($sheets.ToArray())
        }
    }
    finally {
        if ($null -ne $package) {
            try {
                if (Get-Command Close-ExcelPackage -ErrorAction SilentlyContinue) {
                    & Close-ExcelPackage -NoSave $package
                }
            }
            catch { }
        }
    }
}

function script:Import-PlanningFromCsv {
    <#
    .SYNOPSIS
        Secours : construit un pseudo-classeur à une feuille à partir d'un CSV.
    #>
    param([string]$Path)
    try {
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $data = Import-Csv -LiteralPath $Path -Encoding utf8
        }
        else {
            $data = Import-Csv -LiteralPath $Path
        }
    }
    catch { throw "[ExcelLoader] Lecture CSV échouée: $($_.Exception.Message)" }

    if ($null -eq $data -or $data.Count -eq 0) {
        return [pscustomobject]@{
            Path   = $Path
            Sheets = @([pscustomobject]@{
                Name     = 'CSV'
                RowCount = 0
                ColCount = 0
                Grid     = @()
            })
        }
    }
    $cols = @($data[0].PSObject.Properties | ForEach-Object { $_.Name })
    $colCount = $cols.Count
    $rowsList = [System.Collections.Generic.List[object[]]]::new()
    $headerRow = @($cols | ForEach-Object { [string]$_ })
    [void]$rowsList.Add($headerRow)
    foreach ($row in $data) {
        $lineList = [System.Collections.Generic.List[string]]::new()
        foreach ($colN in $cols) {
            $v = $row.$colN
            if ($null -eq $v) { [void]$lineList.Add('') } else { [void]$lineList.Add([string]$v) }
        }
        while ($lineList.Count -lt $colCount) { [void]$lineList.Add('') }
        [void]$rowsList.Add($lineList.ToArray())
    }
    $grid = $rowsList.ToArray()
    $nRow = $grid.Count
    return [pscustomobject]@{
        Path   = $Path
        Sheets = @([pscustomobject]@{
            Name     = 'CSV'
            RowCount = $nRow
            ColCount = $colCount
            Grid     = $grid
        })
    }
}

function Get-ExcelSheetNames {
    <#
    .SYNOPSIS
        Liste les noms de feuilles sans charger les cellules (ouverture rapide EPPlus).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExcelPath,
        [string]$Password = $null
    )
    if (-not (Test-Path -LiteralPath $ExcelPath)) {
        throw "Get-ExcelSheetNames: fichier introuvable: $ExcelPath"
    }
    $ext = [System.IO.Path]::GetExtension($ExcelPath).ToLowerInvariant()
    if ($ext -in @('.csv', '.tsv', '.txt')) {
        return @('CSV')
    }

    script:Ensure-ImportExcelModule
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ExcelPath)
    $package = $null
    try {
        if ([string]::IsNullOrEmpty($Password)) {
            $package = Open-ExcelPackage -Path $resolved
        }
        else {
            $package = Open-ExcelPackage -Path $resolved -Password $Password
        }
        if ($null -eq $package) {
            throw '[ExcelLoader] Open-ExcelPackage a retourne une valeur nulle.'
        }
        return @($package.Workbook.Worksheets | ForEach-Object { [string]$_.Name })
    }
    finally {
        if ($null -ne $package) {
            try {
                if (Get-Command Close-ExcelPackage -ErrorAction SilentlyContinue) {
                    Close-ExcelPackage -NoSave $package
                }
            }
            catch { }
        }
    }
}

function script:Import-ExcelWorksheetToGrid {
    param(
        [Parameter(Mandatory = $true)]$Worksheet
    )
    $name = [string]$Worksheet.Name
    $dim = $Worksheet.Dimension
    if ($null -eq $dim) {
        return [pscustomobject]@{
            Name     = $name
            RowCount = 0
            ColCount = 0
            Grid     = @()
        }
    }
    $endRow = [int]$dim.End.Row
    $endCol = [int]$dim.End.Column
    $grid = [System.Collections.Generic.List[object[]]]::new()
    for ($r = 1; $r -le $endRow; $r++) {
        $rowValues = [System.Collections.Generic.List[string]]::new()
        for ($c = 1; $c -le $endCol; $c++) {
            $cell = $Worksheet.Cells[$r, $c]
            [void]$rowValues.Add((script:Get-CellDisplayText -Cell $cell))
        }
        [void]$grid.Add($rowValues.ToArray())
    }
    return [pscustomobject]@{
        Name     = $name
        RowCount = $endRow
        ColCount = $endCol
        Grid     = @($grid.ToArray())
    }
}

function Import-PlanningExcelSheet {
    <#
    .SYNOPSIS
        Charge une seule feuille d’un planning au format Grille (0-based).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExcelPath,
        [Parameter(Mandatory = $true)]
        [string]$SheetName,
        [string]$Password = $null
    )
    if (-not (Test-Path -LiteralPath $ExcelPath)) {
        throw "Import-PlanningExcelSheet: fichier introuvable: $ExcelPath"
    }

    $reportExcelOpenProgress = {
        param([double]$SubRatio, [string]$Detail)
        if (Get-Command Update-PlanningRebuildStepProgress -ErrorAction SilentlyContinue) {
            Update-PlanningRebuildStepProgress -StepIndex 2 -StepCount 5 -Label 'Lecture Excel + matching' `
                -Status 'Running' -Detail $Detail -SubRatio $SubRatio
        }
        if (Get-Command Write-PlanningExcelSubStep -ErrorAction SilentlyContinue) {
            Write-PlanningExcelSubStep -SubStepIndex 2 -Status 'SubStepProgress' -Detail $Detail -SubRatio $SubRatio
        }
    }

    $ext = [System.IO.Path]::GetExtension($ExcelPath).ToLowerInvariant()
    if ($ext -in @('.csv', '.tsv', '.txt')) {
        return (Import-PlanningExcel -ExcelPath $ExcelPath -Password $Password)
    }

    $integrity = Test-ExcelFileIntegrity -Path $ExcelPath
    if (-not $integrity.IsValid) {
        $detail = if ($null -ne $integrity.Error) { $integrity.Error } else { 'verification echouee' }
        throw "[ExcelLoader] Fichier structurellement invalide: $detail"
    }

    script:Ensure-ImportExcelModule
    & $reportExcelOpenProgress 0.07 ("Ouverture de la feuille '{0}'..." -f $SheetName)
    script:Write-PlanningExcelLoadUiLog ("[EXCEL] Chargement feuille unique : '{0}'" -f $SheetName)

    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ExcelPath)
    $package = $null
    try {
        if ([string]::IsNullOrEmpty($Password)) {
            $package = Open-ExcelPackage -Path $resolved
        }
        else {
            $package = Open-ExcelPackage -Path $resolved -Password $Password
        }
        if ($null -eq $package) {
            throw '[ExcelLoader] Open-ExcelPackage a retourne une valeur nulle.'
        }
        $ws = $package.Workbook.Worksheets[$SheetName]
        if ($null -eq $ws) {
            throw "Import-PlanningExcelSheet: feuille '$SheetName' introuvable."
        }
        & $reportExcelOpenProgress 0.09 ("Lecture feuille '{0}'..." -f $SheetName)
        $sheetGrid = script:Import-ExcelWorksheetToGrid -Worksheet $ws
        & $reportExcelOpenProgress 0.10 'Traitement des donnees termine'
        return [pscustomobject]@{
            Path   = $ExcelPath
            Sheets = @($sheetGrid)
        }
    }
    finally {
        if ($null -ne $package) {
            try {
                if (Get-Command Close-ExcelPackage -ErrorAction SilentlyContinue) {
                    Close-ExcelPackage -NoSave $package
                }
            }
            catch { }
        }
    }
}

function Import-PlanningExcel {
    <#
    .SYNOPSIS
        Charge toutes les feuilles d’un planning au format Grille (0-based), identique à l’ex-code COM.
    .PARAMETER ExcelPath
        Chemin absolu ou relatif ( .xlsx, .xlsm, .xltx, ou .csv en secours ).
    .PARAMETER Password
        Mot de passe de classeur (optionnel) — pris en charge par ImportExcel quand le fichier le requiert.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExcelPath,
        [string]$Password = $null
    )
    if (-not (Test-Path -LiteralPath $ExcelPath)) {
        throw "Import-PlanningExcel: fichier introuvable: $ExcelPath"
    }

    $reportExcelOpenProgress = {
        param([double]$SubRatio, [string]$Detail)
        if (Get-Command Update-PlanningRebuildStepProgress -ErrorAction SilentlyContinue) {
            Update-PlanningRebuildStepProgress -StepIndex 2 -StepCount 5 -Label 'Lecture Excel + matching' `
                -Status 'Running' -Detail $Detail -SubRatio $SubRatio
        }
        if (Get-Command Write-PlanningExcelSubStep -ErrorAction SilentlyContinue) {
            Write-PlanningExcelSubStep -SubStepIndex 2 -Status 'SubStepProgress' -Detail $Detail -SubRatio $SubRatio
        }
    }
    & $reportExcelOpenProgress 0.06 'Ouverture du fichier Excel...'

    $ext = [System.IO.Path]::GetExtension($ExcelPath).ToLowerInvariant()
    if ($ext -in @('.csv', '.tsv', '.txt')) {
        if ($ext -eq '.tsv' -or $ext -eq '.txt') { Write-Warning "[ExcelLoader] Fichier texte/TSV: traitement en CSV simple (délimiteur détecté par Import-Csv)." }
        $csvData = Import-PlanningFromCsv -Path $ExcelPath
        & $reportExcelOpenProgress 0.10 'Fichier charge — lecture des donnees...'
        return $csvData
    }

    $integrity = Test-ExcelFileIntegrity -Path $ExcelPath
    if (-not $integrity.IsValid) {
        $detail = if ($null -ne $integrity.Error) { $integrity.Error } else { 'verification echouee' }
        Write-Host ("[EXCEL-INTEGRITY-CHECK] FAIL — {0} (Size={1})" -f $detail, $integrity.FileSizeBytes) -ForegroundColor Red
        throw "[ExcelLoader] Fichier structurellement invalide (pas un classeur OOXML valide): $detail"
    }
    Write-Host ("[EXCEL-INTEGRITY-CHECK] OK — MagicBytes=PK ZIP=OK Worksheets=OK Size={0}" -f $integrity.FileSizeBytes) -ForegroundColor DarkGray

    script:Write-PlanningExcelLoadUiLog '[EXCEL] Chargement du module ImportExcel...'
    & $reportExcelOpenProgress 0.065 'Chargement du module ImportExcel...'
    Ensure-ImportExcelModule
    $workbook = $null
    if ($PSBoundParameters.ContainsKey('Password') -and -not [string]::IsNullOrEmpty($Password)) {
        $workbook = Import-ExcelWorkbookToGrids -Path $ExcelPath -Password $Password -ReportProgress $reportExcelOpenProgress
    }
    else {
        $workbook = Import-ExcelWorkbookToGrids -Path $ExcelPath -ReportProgress $reportExcelOpenProgress
    }
    & $reportExcelOpenProgress 0.10 'Traitement des donnees termine'
    return $workbook
}

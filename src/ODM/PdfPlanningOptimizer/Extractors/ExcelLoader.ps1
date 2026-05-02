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
        [string]$Password = $null
    )
    $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not (Test-Path -LiteralPath $resolved)) { throw "Fichier introuvable: $Path" }
    $ext = [System.IO.Path]::GetExtension($resolved).ToLowerInvariant()
    if ($ext -eq '.xls' -or $ext -eq '.xlsb') {
        throw "[ExcelLoader] Le format binaire '$ext' n'est pas géré. Enregistrez le fichier au format .xlsx ou .xlsm, ou utilisez un export CSV en secours."
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
        foreach ($ws in $package.Workbook.Worksheets) {
            $name = [string]$ws.Name
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
            $endRow = [int]$dim.End.Row
            $endCol = [int]$dim.End.Column
            $rowCount = $endRow
            $colCount = $endCol
            $grid = [System.Collections.Generic.List[object[]]]::new()
            for ($r = 1; $r -le $endRow; $r++) {
                $rowValues = [System.Collections.Generic.List[string]]::new()
                for ($c = 1; $c -le $endCol; $c++) {
                    $cell = $ws.Cells[$r, $c]
                    [void]$rowValues.Add((Get-CellDisplayText -Cell $cell))
                }
                [void]$grid.Add($rowValues.ToArray())
            }
            [void]$sheets.Add([pscustomobject]@{
                Name     = $name
                RowCount = $rowCount
                ColCount = $colCount
                Grid     = @($grid.ToArray())
            })
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

    $ext = [System.IO.Path]::GetExtension($ExcelPath).ToLowerInvariant()
    if ($ext -in @('.csv', '.tsv', '.txt')) {
        if ($ext -eq '.tsv' -or $ext -eq '.txt') { Write-Warning "[ExcelLoader] Fichier texte/TSV: traitement en CSV simple (délimiteur détecté par Import-Csv)." }
        return (Import-PlanningFromCsv -Path $ExcelPath)
    }

    Ensure-ImportExcelModule
    if ($PSBoundParameters.ContainsKey('Password') -and -not [string]::IsNullOrEmpty($Password)) {
        return (Import-ExcelWorkbookToGrids -Path $ExcelPath -Password $Password)
    }
    return (Import-ExcelWorkbookToGrids -Path $ExcelPath)
}

function Import-PlanningExcelData {
    <#
    .SYNOPSIS
        Alias sémantique (pipelines orchestre / tests) : même contenu qu’Import-PlanningExcel.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExcelPath
    )
    return (Import-PlanningExcel -ExcelPath $ExcelPath)
}

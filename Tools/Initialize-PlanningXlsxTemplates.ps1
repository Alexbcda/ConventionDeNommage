# Cree des templates XLSX minimaux (OpenXML) sans ImportExcel.
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function New-CnsMinimalXlsx {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][hashtable]$CellPlaceholders
    )
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force
    }

    $rows = New-Object System.Collections.Generic.List[string]
    $rowNums = @($CellPlaceholders.Keys | ForEach-Object {
            if ($_ -match '^([A-Z]+)(\d+)$') { [int]$Matches[2] }
        } | Sort-Object -Unique)
    foreach ($rn in $rowNums) {
        $cells = New-Object System.Collections.Generic.List[string]
        foreach ($cellRef in @($CellPlaceholders.Keys)) {
            if ($cellRef -notmatch '^([A-Z]+)(\d+)$') { continue }
            if ([int]$Matches[2] -ne $rn) { continue }
            $key = $CellPlaceholders[$cellRef]
            $val = '{{' + $key + '}}'
            $escaped = [System.Security.SecurityElement]::Escape($val)
            [void]$cells.Add(('<c r="{0}" t="inlineStr"><is><t>{1}</t></is></c>' -f $cellRef, $escaped))
        }
        [void]$rows.Add(('<row r="{0}">{1}</row>' -f $rn, ($cells -join '')))
    }
    $sheetData = '<sheetData>' + ($rows -join '') + '</sheetData>'
    $sheetXml = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
$sheetData
</worksheet>
"@
    $workbookXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Feuille1" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>
'@
    $contentTypes = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>
'@
    $relsRoot = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
'@
    $workbookRels = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>
'@

    $zipPath = $Path + '.tmp.zip'
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    $zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        function Add-ZipEntry([System.IO.Compression.ZipArchive]$Archive, [string]$Name, [string]$Content) {
            $e = $Archive.CreateEntry($Name)
            $sw = New-Object System.IO.StreamWriter($e.Open())
            $sw.Write($Content)
            $sw.Close()
        }
        Add-ZipEntry $zip '[Content_Types].xml' $contentTypes
        Add-ZipEntry $zip '_rels/.rels' $relsRoot
        Add-ZipEntry $zip 'xl/workbook.xml' $workbookXml
        Add-ZipEntry $zip 'xl/_rels/workbook.xml.rels' $workbookRels
        Add-ZipEntry $zip 'xl/worksheets/sheet1.xml' $sheetXml
    }
    finally {
        $zip.Dispose()
    }
    Move-Item -LiteralPath $zipPath -Destination $Path -Force
}

$templates = @{
    (Join-Path $RepoRoot 'templates\CertificatDeDestruction.xlsx') = @{
        'B2'  = 'Date_Collecte'
        'B3'  = 'Date_FinDestruction'
        'B4'  = 'Client_ID'
        'B5'  = 'Client_Nom'
        'B6'  = 'Client_Adresse'
        'B7'  = 'Client_CP'
        'B8'  = 'Client_Ville'
        'B9'  = 'Collecteur_Nom'
        'B10' = 'Collecteur_Prenom'
        'B11' = 'Vehicule_Immat'
        'B12' = 'ODM_Numero'
        'B13' = 'Trieur_Nom'
        'B14' = 'Trieur_Prenom'
    }
    (Join-Path $RepoRoot 'templates\BilanDeCollecte.xlsx') = @{
        'B2' = 'Date_Collecte'
        'B3' = 'Collecteur_Nom'
        'B4' = 'Collecteur_Prenom'
    }
    (Join-Path $RepoRoot 'templates\CeaPointsDeCollectes.xlsx') = @{
        'B2'  = 'Date_Collecte'
        'B3'  = 'Client_ID'
        'B4'  = 'Client_Nom'
        'B5'  = 'Client_Adresse'
        'B6'  = 'Client_CP'
        'B7'  = 'Client_Ville'
        'B8'  = 'ODM_Numero'
        'B9'  = 'Collecteur_Nom'
        'B10' = 'Collecteur_Prenom'
        'B11' = 'Point_Collecte_Description'
    }
}

foreach ($entry in $templates.GetEnumerator()) {
    New-CnsMinimalXlsx -Path $entry.Key -CellPlaceholders $entry.Value
    Write-Host ("Template cree : {0}" -f $entry.Key) -ForegroundColor Green
}

Write-Host 'Templates XLSX planning initialises.' -ForegroundColor Cyan

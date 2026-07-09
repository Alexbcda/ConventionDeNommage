# Moteur generique templates XLSX : placeholders EPPlus + conversion PDF (LibreOffice / Excel COM).

$script:CnsExcelLoaderPath = Join-Path $PSScriptRoot '..\Extractors\ExcelLoader.ps1'
if (Test-Path -LiteralPath $script:CnsExcelLoaderPath) {
    . $script:CnsExcelLoaderPath
}

$script:CnsMicrosoftExcelAvailableCache = $null

function Get-CnsLibreOfficeSofficePath {
    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:CN_LIBREOFFICE_SOFFICE)) {
        [void]$candidates.Add($env:CN_LIBREOFFICE_SOFFICE.Trim())
    }
    [void]$candidates.Add('C:\Program Files\LibreOffice\program\soffice.exe')
    [void]$candidates.Add('C:\Program Files (x86)\LibreOffice\program\soffice.exe')
    foreach ($p in @($candidates)) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            return ([System.IO.Path]::GetFullPath($p))
        }
    }
    return $null
}

function Get-CnsMicrosoftExcelExecutablePath {
    if (-not [string]::IsNullOrWhiteSpace($env:CN_EXCEL_APP)) {
        $p = $env:CN_EXCEL_APP.Trim().Trim('"')
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            return ([System.IO.Path]::GetFullPath($p))
        }
    }
    foreach ($regPath in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\excel.exe',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\excel.exe'
        )) {
        try {
            $item = Get-ItemProperty -LiteralPath $regPath -ErrorAction Stop
            $exe = [string]$item.'(default)'
            if (-not [string]::IsNullOrWhiteSpace($exe) -and (Test-Path -LiteralPath $exe.Trim().Trim('"') -PathType Leaf)) {
                return ([System.IO.Path]::GetFullPath($exe.Trim().Trim('"')))
            }
        }
        catch { }
    }
    return $null
}

function Test-CnsMicrosoftExcelAvailable {
    if ($null -ne $script:CnsMicrosoftExcelAvailableCache) {
        return [bool]$script:CnsMicrosoftExcelAvailableCache
    }
    if ($null -ne (Get-CnsMicrosoftExcelExecutablePath)) {
        $script:CnsMicrosoftExcelAvailableCache = $true
        return $true
    }
    $excel = $null
    try {
        $excel = New-Object -ComObject Excel.Application -ErrorAction Stop
        $script:CnsMicrosoftExcelAvailableCache = ($null -ne $excel)
    }
    catch {
        $script:CnsMicrosoftExcelAvailableCache = $false
    }
    finally {
        if ($null -ne $excel) {
            try { $excel.DisplayAlerts = $false } catch { }
            try { $excel.Quit() } catch { }
            try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) } catch { }
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
        }
    }
    return [bool]$script:CnsMicrosoftExcelAvailableCache
}

function script:Release-CnsExcelComObject {
    param([object]$ComObject)
    if ($null -eq $ComObject) { return }
    try { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($ComObject) } catch { }
}

function Get-CnsXlsxToPdfConverterMode {
    $raw = [string]$env:CN_PDF_CONVERTER
    if ([string]::IsNullOrWhiteSpace($raw)) { return 'AUTO' }
    $m = $raw.Trim().ToUpperInvariant()
    switch ($m) {
        'AUTO' { return 'AUTO' }
        'LIBREOFFICE' { return 'LIBREOFFICE' }
        'WORD' { return 'WORD' }
        'EXCEL' { return 'WORD' }
        'NONE' { return 'NONE' }
        default {
            Write-Warning ("[XLSX-PDF] CN_PDF_CONVERTER valeur inconnue « {0} » — mode AUTO." -f $raw.Trim())
            return 'AUTO'
        }
    }
}

function Resolve-CnsXlsxToPdfEngine {
    param([Parameter(Mandatory = $true)][string]$Mode)
    if ($Mode -eq 'NONE') {
        Write-Warning '[XLSX-PDF] Conversion desactivee (CN_PDF_CONVERTER=NONE).'
        return $null
    }
    $loOk = -not [string]::IsNullOrWhiteSpace((Get-CnsLibreOfficeSofficePath))
    $excelOk = Test-CnsMicrosoftExcelAvailable
    switch ($Mode) {
        'LIBREOFFICE' {
            if ($loOk) { return 'LibreOffice' }
            Write-Warning '[XLSX-PDF] CN_PDF_CONVERTER=LIBREOFFICE mais soffice.exe introuvable.'
            return $null
        }
        'WORD' {
            if ($excelOk) { return 'Excel' }
            Write-Warning '[XLSX-PDF] CN_PDF_CONVERTER=WORD/EXCEL mais Microsoft Excel est indisponible.'
            return $null
        }
        default {
            if ($loOk) { return 'LibreOffice' }
            if ($excelOk) { return 'Excel' }
            Write-Warning '[XLSX-PDF] Aucun convertisseur XLSX vers PDF (LibreOffice ou Excel). CN_PDF_CONVERTER : AUTO, LIBREOFFICE, WORD, NONE.'
            return $null
        }
    }
}

function script:Write-CnsXlsxToPdfLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Level = 'INFO',
        $Data = $null
    )
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log ("[XLSX-PDF] " + $Message) $Level $Data
        return
    }
    $color = switch ($Level) {
        'WARN' { 'Yellow' }
        'ERROR' { 'Red' }
        default { 'DarkGray' }
    }
    Write-Host ("[XLSX-PDF] {0}" -f $Message) -ForegroundColor $color
}

function Get-XlsxCellReference {
    param(
        [Parameter(Mandatory = $true)][int]$Row,
        [Parameter(Mandatory = $true)][int]$Column
    )
    if ($Column -lt 1 -or $Row -lt 1) { return '' }
    $colLetters = ''
    $c = $Column
    while ($c -gt 0) {
        $rem = ($c - 1) % 26
        $colLetters = ([char](65 + $rem)).ToString() + $colLetters
        $c = [int][Math]::Floor(($c - 1) / 26)
    }
    return ('{0}{1}' -f $colLetters, $Row)
}

function script:Get-CnsXlsxCellDisplayText {
    param($Cell)
    if ($null -eq $Cell) { return '' }
    if (Get-Command script:Get-CellDisplayText -ErrorAction SilentlyContinue) {
        return (script:Get-CellDisplayText -Cell $Cell)
    }
    try {
        if ($null -ne $Cell.Text -and -not [string]::IsNullOrEmpty([string]$Cell.Text)) {
            return ([string]$Cell.Text).Trim()
        }
    }
    catch { }
    if ($null -ne $Cell.Value) { return $Cell.Value.ToString().Trim() }
    return ''
}

function Find-XlsxPlaceholders {
    <#
    .SYNOPSIS
        Scanne les cellules utilisees et retourne les balises {{Key}} trouvees.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$XlsxPath,
        [string]$WorksheetName
    )
    if (Get-Command script:Ensure-ImportExcelModule -ErrorAction SilentlyContinue) {
        script:Ensure-ImportExcelModule
    }
    elseif (-not (Get-Module -Name ImportExcel -ListAvailable -ErrorAction SilentlyContinue)) {
        throw '[XLSX] Module ImportExcel requis.'
    }
    else {
        Import-Module ImportExcel -ErrorAction Stop
    }

    $package = Open-ExcelPackage -Path $XlsxPath
    try {
        $ws = if ([string]::IsNullOrWhiteSpace($WorksheetName)) {
            $package.Workbook.Worksheets[0]
        }
        else {
            $package.Workbook.Worksheets[$WorksheetName]
        }
        if ($null -eq $ws) { return @() }

        $found = New-Object System.Collections.Generic.List[object]
        $dim = $ws.Dimension
        if ($null -eq $dim) { return @() }

        for ($r = $dim.Start.Row; $r -le $dim.End.Row; $r++) {
            for ($c = $dim.Start.Column; $c -le $dim.End.Column; $c++) {
                $cell = $ws.Cells[$r, $c]
                $text = script:Get-CnsXlsxCellDisplayText -Cell $cell
                if ([string]::IsNullOrWhiteSpace($text)) { continue }
                if ($text -notmatch '\{\{') { continue }
                $matches = [regex]::Matches($text, '\{\{([^{}]+)\}\}')
                foreach ($m in @($matches)) {
                    $key = $m.Groups[1].Value.Trim()
                    if ([string]::IsNullOrWhiteSpace($key)) { continue }
                    [void]$found.Add([PSCustomObject]@{
                            CellRef = (Get-XlsxCellReference -Row $r -Column $c)
                            Row     = $r
                            Column  = $c
                            Key     = $key
                            RawText = $text
                        })
                }
            }
        }
        return @($found)
    }
    finally {
        if (Get-Command Close-ExcelPackage -ErrorAction SilentlyContinue) {
            Close-ExcelPackage $package -NoSave
        }
    }
}

function script:Replace-CnsPlaceholderTokensInText {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][hashtable]$Placeholders
    )
    $result = [string]$Text
    $keys = @(
        $Placeholders.Keys |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object { $_.Length } -Descending
    )
    foreach ($key in $keys) {
        $needle = '{{' + $key + '}}'
        $val = if ($null -eq $Placeholders[$key]) { '' } else { [string]$Placeholders[$key] }
        $result = $result.Replace($needle, $val)
    }
    return $result
}

function Set-CnsXlsxTemplatePlaceholders {
    param(
        [Parameter(Mandatory = $true)]
        [string]$XlsxPath,
        [Parameter(Mandatory = $true)]
        [hashtable]$Placeholders
    )
    if (-not (Test-Path -LiteralPath $XlsxPath)) { return $false }
    if ($Placeholders.Count -lt 1) {
        Write-Warning '[XLSX] Hashtable placeholders vide.'
        return $false
    }

    if (Get-Command script:Ensure-ImportExcelModule -ErrorAction SilentlyContinue) {
        script:Ensure-ImportExcelModule
    }
    else {
        Import-Module ImportExcel -ErrorAction Stop
    }

    $totalReplaced = 0
    $package = Open-ExcelPackage -Path $XlsxPath
    try {
        foreach ($ws in @($package.Workbook.Worksheets)) {
            if ($null -eq $ws) { continue }
            $dim = $ws.Dimension
            if ($null -eq $dim) { continue }
            for ($r = $dim.Start.Row; $r -le $dim.End.Row; $r++) {
                for ($c = $dim.Start.Column; $c -le $dim.End.Column; $c++) {
                    $cell = $ws.Cells[$r, $c]
                    $text = script:Get-CnsXlsxCellDisplayText -Cell $cell
                    if ([string]::IsNullOrWhiteSpace($text) -or $text -notmatch '\{\{') { continue }
                    $newText = script:Replace-CnsPlaceholderTokensInText -Text $text -Placeholders $Placeholders
                    if ($newText -ne $text) {
                        $cell.Value = $newText
                        $totalReplaced++
                    }
                }
            }
        }
        if ($totalReplaced -lt 1) {
            Write-Warning '[XLSX] Aucun placeholder remplace (verifier template / balises {{KEY}}).'
            return $false
        }
        Close-ExcelPackage $package
        $package = $null
        return $true
    }
    catch {
        Write-Warning ("[XLSX] Remplacement placeholders echoue : {0}" -f $_.Exception.Message)
        return $false
    }
    finally {
        if ($null -ne $package) {
            try { Close-ExcelPackage $package -NoSave } catch { }
        }
    }
}

function Convert-XlsxToPdfUsingLibreOffice {
    param(
        [Parameter(Mandatory = $true)][string]$XlsxPath,
        [Parameter(Mandatory = $true)][string]$PdfPath
    )
    $soffice = Get-CnsLibreOfficeSofficePath
    if ([string]::IsNullOrWhiteSpace($soffice)) {
        Write-Warning '[XLSX-PDF] LibreOffice introuvable (soffice.exe).'
        return $false
    }
    if (-not (Test-Path -LiteralPath $XlsxPath -PathType Leaf)) {
        Write-Warning ("[XLSX-PDF] XLSX source introuvable : {0}" -f $XlsxPath)
        return $false
    }

    $xlsxAbs = [System.IO.Path]::GetFullPath($XlsxPath)
    $pdfAbs = [System.IO.Path]::GetFullPath($PdfPath)
    $outDir = [System.IO.Path]::GetDirectoryName($pdfAbs)
    if (-not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop
    }

    $loArgs = @(
        '--headless', '--nologo', '--nofirststartwizard',
        '--convert-to', 'pdf',
        '--outdir', $outDir,
        $xlsxAbs
    )

    $outFile = Join-Path $env:TEMP ("cn_soffice_out_{0}.txt" -f [Guid]::NewGuid().ToString('N'))
    $errFile = Join-Path $env:TEMP ("cn_soffice_err_{0}.txt" -f [Guid]::NewGuid().ToString('N'))

    try {
        try {
            $proc = Start-Process -FilePath $soffice -ArgumentList $loArgs -Wait -PassThru -NoNewWindow -ErrorAction Stop `
                -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        }
        catch {
            Write-Warning ("[XLSX-PDF] LibreOffice echoue : {0}" -f $_.Exception.Message)
            return $false
        }

        if ($null -eq $proc -or $proc.ExitCode -ne 0) {
            Write-Warning ("[XLSX-PDF] LibreOffice code {0}." -f $(if ($null -eq $proc) { 'null' } else { $proc.ExitCode }))
            return $false
        }

        $produced = Join-Path $outDir ([System.IO.Path]::GetFileNameWithoutExtension($xlsxAbs) + '.pdf')
        if (-not (Test-Path -LiteralPath $produced)) {
            Write-Warning '[XLSX-PDF] PDF non produit apres conversion LibreOffice.'
            return $false
        }
        if (-not ($produced.Equals($pdfAbs, [System.StringComparison]::OrdinalIgnoreCase))) {
            if (Test-Path -LiteralPath $pdfAbs) {
                Remove-Item -LiteralPath $pdfAbs -Force -ErrorAction SilentlyContinue
            }
            Move-Item -LiteralPath $produced -Destination $pdfAbs -Force
        }

        return (Test-Path -LiteralPath $pdfAbs)
    }
    finally {
        if (Test-Path -LiteralPath $outFile) { Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $errFile) { Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue }
    }
}

function Convert-XlsxToPdfViaExcel {
    param(
        [Parameter(Mandatory = $true)][string]$XlsxPath,
        [Parameter(Mandatory = $true)][string]$PdfPath
    )
    if (-not (Test-CnsMicrosoftExcelAvailable)) {
        Write-Warning '[XLSX-PDF] Microsoft Excel indisponible pour la conversion.'
        return $false
    }
    if (-not (Test-Path -LiteralPath $XlsxPath -PathType Leaf)) {
        return $false
    }

    $xlsxAbs = [System.IO.Path]::GetFullPath($XlsxPath)
    $pdfAbs = [System.IO.Path]::GetFullPath($PdfPath)
    $outDir = [System.IO.Path]::GetDirectoryName($pdfAbs)
    if (-not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop
    }

    $xlFixedFormatTypePDF = 0
    $excel = $null
    $wb = $null
    try {
        $excel = New-Object -ComObject Excel.Application -ErrorAction Stop
        $excel.Visible = $false
        $excel.DisplayAlerts = $false
        $wb = $excel.Workbooks.Open($xlsxAbs, 0, $true)
        if ($null -eq $wb) {
            Write-Warning '[XLSX-PDF] Excel n''a pas ouvert le classeur.'
            return $false
        }
        $wb.ExportAsFixedFormat($xlFixedFormatTypePDF, $pdfAbs)
    }
    catch {
        Write-Warning ("[XLSX-PDF] Conversion Excel echouee : {0}" -f $_.Exception.Message)
        return $false
    }
    finally {
        if ($null -ne $wb) {
            try { $wb.Close($false) } catch { }
            script:Release-CnsExcelComObject -ComObject $wb
            $wb = $null
        }
        if ($null -ne $excel) {
            try { $excel.Quit() } catch { }
            script:Release-CnsExcelComObject -ComObject $excel
            $excel = $null
        }
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }

    return (Test-Path -LiteralPath $pdfAbs)
}

function Convert-XlsxToPdf {
    param(
        [Parameter(Mandatory = $true)][string]$XlsxPath,
        [Parameter(Mandatory = $true)][string]$PdfPath
    )
    $mode = Get-CnsXlsxToPdfConverterMode
    $engine = Resolve-CnsXlsxToPdfEngine -Mode $mode
    if ([string]::IsNullOrWhiteSpace($engine)) { return $false }

    script:Write-CnsXlsxToPdfLog -Message ("Moteur selectionne : {0} (mode={1})" -f $engine, $mode) -Level 'INFO'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = $false
    $engineUsed = $engine
    if ($engine -eq 'LibreOffice') {
        $ok = Convert-XlsxToPdfUsingLibreOffice -XlsxPath $XlsxPath -PdfPath $PdfPath
        if (-not $ok -and $mode -eq 'AUTO' -and (Test-CnsMicrosoftExcelAvailable)) {
            script:Write-CnsXlsxToPdfLog -Message 'LibreOffice echoue, fallback vers Excel (mode AUTO).' -Level 'WARN'
            $ok = Convert-XlsxToPdfViaExcel -XlsxPath $XlsxPath -PdfPath $PdfPath
            if ($ok) { $engineUsed = 'Excel' }
        }
    }
    else {
        $ok = Convert-XlsxToPdfViaExcel -XlsxPath $XlsxPath -PdfPath $PdfPath
    }
    $sw.Stop()
    if ($ok) {
        script:Write-CnsXlsxToPdfLog -Message ("Conversion reussie via {0} en {1} ms" -f $engineUsed, $sw.ElapsedMilliseconds) -Level 'INFO'
    }
    else {
        script:Write-CnsXlsxToPdfLog -Message ("Conversion echouee via {0} apres {1} ms" -f $engineUsed, $sw.ElapsedMilliseconds) -Level 'WARN'
    }
    return $ok
}

function New-CnsFilledXlsxPdfFromTemplate {
    <#
    .SYNOPSIS
        Copie template XLSX, remplace placeholders, convertit en PDF. Retourne chemin PDF ou $null.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$TemplatePath,
        [Parameter(Mandatory = $true)][string]$OutPdfPath,
        [Parameter(Mandatory = $true)][hashtable]$Placeholders,
        [string]$TempFilePrefix = 'cn_xlsx_tpl',
        [string]$KeepFilledXlsxEnvVar
    )
    if ([string]::IsNullOrWhiteSpace($TemplatePath) -or -not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
        return $null
    }

    $outAbs = [System.IO.Path]::GetFullPath($OutPdfPath)
    $outDir = Split-Path -Parent $outAbs
    if (-not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop
    }

    $runId = [Guid]::NewGuid().ToString('N')
    $workXlsx = Join-Path $env:TEMP ("{0}_{1}.xlsx" -f $TempFilePrefix, $runId)
    Copy-Item -LiteralPath $TemplatePath -Destination $workXlsx -Force

    try {
        if (-not (Set-CnsXlsxTemplatePlaceholders -XlsxPath $workXlsx -Placeholders $Placeholders)) {
            return $null
        }
        if (-not (Convert-XlsxToPdf -XlsxPath $workXlsx -PdfPath $outAbs)) {
            return $null
        }
    }
    finally {
        if (Test-Path -LiteralPath $workXlsx) {
            if (-not [string]::IsNullOrWhiteSpace($KeepFilledXlsxEnvVar) -and -not [string]::IsNullOrWhiteSpace((Get-Item Env:$KeepFilledXlsxEnvVar -ErrorAction SilentlyContinue).Value)) {
                Write-Host ("[XLSX] Fichier conserve ({0}) : {1}" -f $KeepFilledXlsxEnvVar, $workXlsx) -ForegroundColor DarkYellow
            }
            else {
                Remove-Item -LiteralPath $workXlsx -Force -ErrorAction SilentlyContinue
            }
        }
        $loSide = Join-Path $env:TEMP ([System.IO.Path]::GetFileNameWithoutExtension($workXlsx) + '.pdf')
        if (Test-Path -LiteralPath $loSide) {
            Remove-Item -LiteralPath $loSide -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not (Test-Path -LiteralPath $outAbs)) { return $null }
    return $outAbs
}

# Moteur templates ODS (OpenDocument Spreadsheet) : remplacement balises + conversion PDF LibreOffice.

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

function script:Escape-CnsOdsXmlText {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    return [System.Security.SecurityElement]::Escape([string]$Text)
}

function script:Replace-CnsOdsPlaceholderTokensInText {
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
        $val = if ($null -eq $Placeholders[$key]) { '' } else { script:Escape-CnsOdsXmlText -Text ([string]$Placeholders[$key]) }
        $result = $result.Replace($needle, $val)
    }
    return $result
}

function Find-OdsPlaceholders {
    param(
        [Parameter(Mandatory = $true)][string]$OdsPath
    )
    if (-not (Test-Path -LiteralPath $OdsPath -PathType Leaf)) { return @() }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $found = New-Object System.Collections.Generic.List[object]
    $zip = [System.IO.Compression.ZipFile]::OpenRead([System.IO.Path]::GetFullPath($OdsPath))
    try {
        $entry = $zip.GetEntry('content.xml')
        if ($null -eq $entry) { return @() }
        $sr = New-Object System.IO.StreamReader($entry.Open(), [System.Text.UTF8Encoding]::new($false))
        $xml = $sr.ReadToEnd()
        $sr.Close()
        $matches = [regex]::Matches($xml, '\{\{([^{}]+)\}\}')
        foreach ($m in @($matches)) {
            $key = $m.Groups[1].Value.Trim()
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            [void]$found.Add([PSCustomObject]@{
                    Key     = $key
                    RawText = $m.Value
                })
        }
        return @($found)
    }
    finally {
        $zip.Dispose()
    }
}

function Set-OdsTemplatePlaceholders {
    <#
    .SYNOPSIS
        Remplace les balises {{Key}} dans content.xml sans repackager tout le ODS (mise en page preservee).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$OdsPath,
        [Parameter(Mandatory = $true)][hashtable]$Placeholders,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )
    if (-not (Test-Path -LiteralPath $OdsPath -PathType Leaf)) { return $false }
    if ($Placeholders.Count -lt 1) {
        Write-Warning '[ODS] Hashtable placeholders vide.'
        return $false
    }

    $outDir = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop
    }
    Copy-Item -LiteralPath $OdsPath -Destination $OutputPath -Force

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $totalReplaced = 0
    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::Open(
            [System.IO.Path]::GetFullPath($OutputPath),
            [System.IO.Compression.ZipArchiveMode]::Update
        )
        $entry = $zip.GetEntry('content.xml')
        if ($null -eq $entry) {
            Write-Warning '[ODS] content.xml introuvable dans le fichier ODS.'
            return $false
        }

        $sr = New-Object System.IO.StreamReader($entry.Open(), [System.Text.UTF8Encoding]::new($false))
        $xml = $sr.ReadToEnd()
        $sr.Close()
        $sr.Dispose()

        $newXml = script:Replace-CnsOdsPlaceholderTokensInText -Text $xml -Placeholders $Placeholders
        if ($newXml -eq $xml) {
            Write-Warning '[ODS] Aucun placeholder remplace (verifier template / balises {{KEY}}).'
            return $false
        }

        $beforeCount = ([regex]::Matches($xml, '\{\{([^{}]+)\}\}')).Count
        $afterCount = ([regex]::Matches($newXml, '\{\{([^{}]+)\}\}')).Count
        $totalReplaced = $beforeCount - $afterCount
        if ($totalReplaced -lt 1) {
            Write-Warning '[ODS] Aucun placeholder remplace.'
            return $false
        }

        $entry.Delete()
        $newEntry = $zip.CreateEntry('content.xml', [System.IO.Compression.CompressionLevel]::Optimal)
        $sw = New-Object System.IO.StreamWriter($newEntry.Open(), [System.Text.UTF8Encoding]::new($false))
        $sw.Write($newXml)
        $sw.Flush()
        $sw.Close()
        $sw.Dispose()
        return $true
    }
    catch {
        Write-Warning ("[ODS] Remplacement placeholders echoue : {0}" -f $_.Exception.Message)
        return $false
    }
    finally {
        if ($null -ne $zip) { $zip.Dispose() }
    }
}

function Convert-OdsToPdf {
    param(
        [Parameter(Mandatory = $true)][string]$OdsPath,
        [Parameter(Mandatory = $true)][string]$PdfPath
    )
    $soffice = Get-CnsLibreOfficeSofficePath
    if ([string]::IsNullOrWhiteSpace($soffice)) {
        Write-Warning '[ODS-PDF] LibreOffice introuvable (soffice.exe).'
        return $false
    }
    if (-not (Test-Path -LiteralPath $OdsPath -PathType Leaf)) {
        Write-Warning ("[ODS-PDF] ODS source introuvable : {0}" -f $OdsPath)
        return $false
    }

    $odsAbs = [System.IO.Path]::GetFullPath($OdsPath)
    $pdfAbs = [System.IO.Path]::GetFullPath($PdfPath)
    $outDir = [System.IO.Path]::GetDirectoryName($pdfAbs)
    if (-not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop
    }

    $loArgs = @(
        '--headless', '--nologo', '--nofirststartwizard',
        '--convert-to', 'pdf',
        '--outdir', $outDir,
        $odsAbs
    )
    try {
        $proc = Start-Process -FilePath $soffice -ArgumentList $loArgs -Wait -PassThru -NoNewWindow -ErrorAction Stop
        if ($null -eq $proc -or $proc.ExitCode -ne 0) {
            Write-Warning ("[ODS-PDF] LibreOffice code {0}." -f $(if ($null -eq $proc) { 'null' } else { $proc.ExitCode }))
            return $false
        }
    }
    catch {
        Write-Warning ("[ODS-PDF] LibreOffice echoue : {0}" -f $_.Exception.Message)
        return $false
    }

    $produced = Join-Path $outDir ([System.IO.Path]::GetFileNameWithoutExtension($odsAbs) + '.pdf')
    if (-not (Test-Path -LiteralPath $produced)) {
        Write-Warning '[ODS-PDF] PDF non produit apres conversion LibreOffice.'
        return $false
    }
    if ($produced.ToLowerInvariant() -ne $pdfAbs.ToLowerInvariant()) {
        if (Test-Path -LiteralPath $pdfAbs) {
            Remove-Item -LiteralPath $pdfAbs -Force -ErrorAction SilentlyContinue
        }
        Move-Item -LiteralPath $produced -Destination $pdfAbs -Force
    }
    return (Test-Path -LiteralPath $pdfAbs)
}

function New-CnsFilledOdsPdfFromTemplate {
    <#
    .SYNOPSIS
        Copie template ODS, remplace placeholders, convertit en PDF via LibreOffice. Retourne chemin PDF ou $null.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$TemplatePath,
        [Parameter(Mandatory = $true)][string]$OutPdfPath,
        [Parameter(Mandatory = $true)][hashtable]$Placeholders,
        [string]$TempFilePrefix = 'cn_ods_tpl',
        [string]$KeepFilledOdsEnvVar
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
    $workOds = Join-Path $env:TEMP ("{0}_{1}.ods" -f $TempFilePrefix, $runId)

    try {
        if (-not (Set-OdsTemplatePlaceholders -OdsPath $TemplatePath -Placeholders $Placeholders -OutputPath $workOds)) {
            return $null
        }
        if (-not (Convert-OdsToPdf -OdsPath $workOds -PdfPath $outAbs)) {
            return $null
        }
    }
    finally {
        if (Test-Path -LiteralPath $workOds) {
            if (-not [string]::IsNullOrWhiteSpace($KeepFilledOdsEnvVar) -and -not [string]::IsNullOrWhiteSpace((Get-Item Env:$KeepFilledOdsEnvVar -ErrorAction SilentlyContinue).Value)) {
                if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                    Write-Log ("[ODS] Fichier conserve ({0}) : {1}" -f $KeepFilledOdsEnvVar, $workOds) 'INFO'
                }
                else {
                    Write-Host ("[ODS] Fichier conserve ({0}) : {1}" -f $KeepFilledOdsEnvVar, $workOds) -ForegroundColor DarkYellow
                }
            }
            else {
                Remove-Item -LiteralPath $workOds -Force -ErrorAction SilentlyContinue
            }
        }
        $loSide = Join-Path $env:TEMP ([System.IO.Path]::GetFileNameWithoutExtension($workOds) + '.pdf')
        if (Test-Path -LiteralPath $loSide) {
            Remove-Item -LiteralPath $loSide -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not (Test-Path -LiteralPath $outAbs)) { return $null }
    return $outAbs
}

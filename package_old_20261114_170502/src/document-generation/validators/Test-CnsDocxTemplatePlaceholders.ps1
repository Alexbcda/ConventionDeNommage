# Validation placeholders DOCX — détection fragmentation OOXML et écarts schéma JSON.

function Get-CnsDocxXmlPartsForTemplateScan {
    param([Parameter(Mandatory = $true)][string]$ExtractDir)
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($rel in @('word', 'docProps')) {
        $base = Join-Path $ExtractDir $rel
        if (-not (Test-Path -LiteralPath $base)) { continue }
        Get-ChildItem -LiteralPath $base -Recurse -File -Filter '*.xml' -ErrorAction SilentlyContinue |
            ForEach-Object { [void]$parts.Add($_.FullName) }
    }
    return @($parts)
}

function Get-CnsDocxPlaceholderScanFromXml {
    param([Parameter(Mandatory = $true)][string]$XmlContent)
    $contiguous = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($m in [regex]::Matches($XmlContent, '\{\{[A-Za-z0-9_]+\}\}')) {
        [void]$contiguous.Add($m.Value.Substring(2, $m.Value.Length - 4))
    }
    $joined = ([regex]::Matches($XmlContent, '<w:t[^>]*>([^<]*)</w:t>') |
        ForEach-Object { $_.Groups[1].Value }) -join ''
    $logical = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($m in [regex]::Matches($joined, '\{\{([A-Za-z0-9_]+)\}\}')) {
        [void]$logical.Add($m.Groups[1].Value)
    }
    $fragmented = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($joined, '\{\{([A-Za-z0-9_]+)')) {
        $name = $m.Groups[1].Value
        if (-not $contiguous.Contains($name)) {
            [void]$fragmented.Add($name)
        }
    }
    $openBraces = ([regex]::Matches($XmlContent, '\{\{(?![^<]{0,400}\}\})')).Count
    return [pscustomobject]@{
        ContiguousNames  = @($contiguous | Sort-Object)
        LogicalNames   = @($logical | Sort-Object)
        FragmentedNames = @($fragmented | Select-Object -Unique | Sort-Object)
        OpenBraceFragments = $openBraces
    }
}

function Get-CnsDocxLayoutMetrics {
    param([Parameter(Mandatory = $true)][string]$DocumentXmlPath)
    if (-not (Test-Path -LiteralPath $DocumentXmlPath)) {
        return [pscustomobject]@{ Tables = 0; Drawings = 0; Anchors = 0; AlternateContent = 0; DocumentXmlBytes = 0 }
    }
    $raw = [System.IO.File]::ReadAllText($DocumentXmlPath)
    return [pscustomobject]@{
        Tables            = ([regex]::Matches($raw, '<w:tbl')).Count
        Drawings          = ([regex]::Matches($raw, '<w:drawing')).Count
        Anchors           = ([regex]::Matches($raw, 'wp:anchor')).Count
        AlternateContent  = ([regex]::Matches($raw, 'mc:AlternateContent')).Count
        DocumentXmlBytes  = $raw.Length
    }
}

function Test-CnsDocxTemplatePlaceholders {
    <#
    .SYNOPSIS
        Valide un DOCX contre un schéma placeholders JSON (contiguïté + clés connues).
    .OUTPUTS
        PSCustomObject avec IsValid, erreurs et métriques layout.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DocxPath,
        [Parameter(Mandatory = $true)][string]$SchemaPath
    )
    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]

    if (-not (Test-Path -LiteralPath $DocxPath)) {
        return [pscustomobject]@{ IsValid = $false; Errors = @('DOCX introuvable'); Warnings = @() }
    }
    if (-not (Test-Path -LiteralPath $SchemaPath)) {
        return [pscustomobject]@{ IsValid = $false; Errors = @('Schema JSON introuvable'); Warnings = @() }
    }

    $schema = Get-Content -LiteralPath $SchemaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $expected = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $required = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($ph in @($schema.placeholders)) {
        [void]$expected.Add([string]$ph.name)
        if ($ph.required) { [void]$required.Add([string]$ph.name) }
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $workDir = Join-Path $env:TEMP ('cn_tpl_val_' + [Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $workDir -Force
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory([System.IO.Path]::GetFullPath($DocxPath), $workDir)
        $allContiguous = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        $allLogical = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        $allFragmented = New-Object System.Collections.Generic.List[string]
        $layout = [pscustomobject]@{ Tables = 0; Drawings = 0; Anchors = 0; AlternateContent = 0; DocumentXmlBytes = 0 }

        foreach ($xmlPath in @(Get-CnsDocxXmlPartsForTemplateScan -ExtractDir $workDir)) {
            $scan = Get-CnsDocxPlaceholderScanFromXml -XmlContent ([System.IO.File]::ReadAllText($xmlPath))
            foreach ($n in @($scan.ContiguousNames)) { [void]$allContiguous.Add($n) }
            foreach ($n in @($scan.LogicalNames)) { [void]$allLogical.Add($n) }
            foreach ($n in @($scan.FragmentedNames)) { [void]$allFragmented.Add($n) }
        }

        $docXml = Join-Path $workDir 'word\document.xml'
        $layout = Get-CnsDocxLayoutMetrics -DocumentXmlPath $docXml

        foreach ($name in @($allFragmented | Select-Object -Unique)) {
            [void]$errors.Add("Placeholder fragmente (non contigu dans OOXML) : $name")
        }
        foreach ($req in @($required)) {
            if (-not $allContiguous.Contains($req)) {
                [void]$errors.Add("Placeholder obligatoire absent ou non contigu : $req")
            }
        }
        foreach ($found in @($allContiguous)) {
            if (-not $expected.Contains($found)) {
                [void]$warnings.Add("Placeholder inconnu du schema : $found")
            }
        }
        foreach ($exp in @($expected)) {
            if ($allLogical.Contains($exp) -and -not $allContiguous.Contains($exp)) {
                if (-not ($allFragmented -contains $exp)) {
                    [void]$errors.Add("Placeholder visible mais non injectable : $exp")
                }
            }
        }

        if ($layout.Drawings -gt 0 -or $layout.Anchors -gt 0) {
            [void]$warnings.Add("Layout riche pour LibreOffice : drawings=$($layout.Drawings) anchors=$($layout.Anchors)")
        }
        if ($layout.Tables -gt 15) {
            [void]$warnings.Add("Nombre eleve de tableaux ($($layout.Tables)) — risque export LO")
        }
        if ($schema.libreOfficeProfile.risk -eq 'high') {
            [void]$warnings.Add('Schema marque risque LibreOffice eleve.')
        }
    }
    finally {
        if (Test-Path -LiteralPath $workDir) {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $isValid = ($errors.Count -eq 0)
    return [pscustomobject]@{
        TemplateFile     = [System.IO.Path]::GetFileName($DocxPath)
        SchemaId         = $schema.templateId
        IsValid          = $isValid
        Errors           = @($errors)
        Warnings         = @($warnings)
        ContiguousFound  = @($allContiguous | Sort-Object)
        LogicalFound     = @($allLogical | Sort-Object)
        FragmentedFound  = @($allFragmented | Select-Object -Unique | Sort-Object)
        Layout           = $layout
    }
}

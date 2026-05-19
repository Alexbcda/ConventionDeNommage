# Certificat de destruction : template DOCX -> PDF (LibreOffice headless, sans Microsoft Word).

function Get-CnsDestructionCertificateTemplatePath {
    $candidates = New-Object System.Collections.Generic.List[string]
    try {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
        [void]$candidates.Add((Join-Path $repoRoot 'templates\planning\destruction\CertificatDeDestruction.docx'))
        [void]$candidates.Add((Join-Path $repoRoot 'templates\CertificatDeDestruction.docx'))
    }
    catch { }
    if (-not [string]::IsNullOrWhiteSpace($env:CN_DESTRUCTION_CERT_TEMPLATE)) {
        [void]$candidates.Insert(0, $env:CN_DESTRUCTION_CERT_TEMPLATE.Trim())
    }
    foreach ($p in @($candidates)) {
        if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path -LiteralPath $p -PathType Leaf)) {
            return ([System.IO.Path]::GetFullPath($p))
        }
    }
    return $null
}

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

function Convert-DocxToPdfUsingLibreOffice {
    <#
    .SYNOPSIS
        Convertit un DOCX en PDF via soffice.exe (LibreOffice headless).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$DocxPath,
        [Parameter(Mandatory = $true)]
        [string]$PdfPath
    )
    $soffice = Get-CnsLibreOfficeSofficePath
    if ([string]::IsNullOrWhiteSpace($soffice)) {
        Write-Warning '[DESTRUCTION-CERT] LibreOffice introuvable (soffice.exe). Installez LibreOffice ou definissez CN_LIBREOFFICE_SOFFICE.'
        return $false
    }

    if (-not (Test-Path -LiteralPath $DocxPath -PathType Leaf)) {
        Write-Warning ("[DESTRUCTION-CERT] DOCX source introuvable : {0}" -f $DocxPath)
        return $false
    }

    $docxAbs = [System.IO.Path]::GetFullPath($DocxPath)
    $pdfAbs = [System.IO.Path]::GetFullPath($PdfPath)
    $outDir = [System.IO.Path]::GetDirectoryName($pdfAbs)
    if (-not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop
    }

    $loArgs = @(
        '--headless',
        '--nologo',
        '--nofirststartwizard',
        '--convert-to', 'pdf',
        '--outdir', $outDir,
        $docxAbs
    )

    try {
        $proc = Start-Process -FilePath $soffice -ArgumentList $loArgs -Wait -PassThru -NoNewWindow -ErrorAction Stop
        if ($null -eq $proc -or $proc.ExitCode -ne 0) {
            Write-Warning ("[DESTRUCTION-CERT] LibreOffice a retourne le code {0}." -f $(if ($null -eq $proc) { 'null' } else { $proc.ExitCode }))
            return $false
        }
    }
    catch {
        Write-Warning ("[DESTRUCTION-CERT] LibreOffice echoue : {0}" -f $_.Exception.Message)
        return $false
    }

    $produced = Join-Path $outDir ([System.IO.Path]::GetFileNameWithoutExtension($docxAbs) + '.pdf')
    if (-not (Test-Path -LiteralPath $produced)) {
        Write-Warning '[DESTRUCTION-CERT] PDF non produit apres conversion LibreOffice.'
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

function ConvertTo-CnsDocxPlaceholderXmlSafe {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    $s = [string]$Text
    return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
}

function Set-CnsDocxTemplatePlaceholders {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DocxPath,
        [Parameter(Mandatory = $true)]
        [hashtable]$Placeholders
    )
    if (-not (Test-Path -LiteralPath $DocxPath)) { return $false }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $docxAbs = [System.IO.Path]::GetFullPath($DocxPath)
    $workDir = Join-Path $env:TEMP ('cn_docx_unzip_' + [Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $workDir -Force

    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($docxAbs, $workDir)

        $xmlFiles = @(Get-ChildItem -LiteralPath $workDir -Recurse -File -Filter '*.xml' -ErrorAction SilentlyContinue)
        foreach ($xmlFile in $xmlFiles) {
            $rel = $xmlFile.FullName.Substring($workDir.Length).TrimStart('\', '/')
            if ($rel -notmatch '^(word/|docProps/)') { continue }

            $content = [System.IO.File]::ReadAllText($xmlFile.FullName, [System.Text.UTF8Encoding]::new($false))
            $changed = $false
            foreach ($entry in $Placeholders.GetEnumerator()) {
                $needle = '{{{0}}}' -f [string]$entry.Key
                if ($content.IndexOf($needle, [System.StringComparison]::Ordinal) -lt 0) { continue }
                $val = ConvertTo-CnsDestructionCertificatePlaceholderValue -Value ([string]$entry.Value)
                $repl = ConvertTo-CnsDocxPlaceholderXmlSafe -Text $val
                $content = $content.Replace($needle, $repl)
                $changed = $true
            }
            if ($changed) {
                [System.IO.File]::WriteAllText($xmlFile.FullName, $content, [System.Text.UTF8Encoding]::new($false))
            }
        }

        Remove-Item -LiteralPath $docxAbs -Force -ErrorAction Stop
        [System.IO.Compression.ZipFile]::CreateFromDirectory($workDir, $docxAbs)
        return $true
    }
    catch {
        Write-Warning ("[DESTRUCTION-CERT] Remplacement placeholders DOCX echoue : {0}" -f $_.Exception.Message)
        return $false
    }
    finally {
        if (Test-Path -LiteralPath $workDir) {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function ConvertTo-CnsDestructionCertificatePlaceholderValue {
    <#
    .SYNOPSIS
        Valeur pour le DOCX : donnée réelle ou chaîne vide (jamais de texte de remplacement type "À compléter").
    #>
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '' }
    $t = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($t)) { return '' }
    $norm = $t.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $norm.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    $plain = $sb.ToString().ToUpperInvariant()
    $sentinels = @(
        '-', '--', '—', '?', 'N/A', 'NA', 'ND', 'INCONNU', 'NON SPECIFIE', 'NON SPECIFIE',
        'A COMPLETER', 'A RENSEIGNER', 'NON RENSEIGNE', 'NON RENSEIGNEE', 'VIDE', 'TBD'
    )
    foreach ($s in $sentinels) {
        if ($plain -eq $s) { return '' }
    }
    if ($plain -match '^(A|A)\s*COMPL') { return '' }
    if ($plain -match 'COMPLETER') { return '' }
    return $t
}

function Split-CnsCollecteurNomPrenom {
    param([AllowNull()][AllowEmptyString()][string]$CollecteurText)
    $t = ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $CollecteurText
    if ([string]::IsNullOrWhiteSpace($t)) {
        return @{ Nom = ''; Prenom = '' }
    }
    $parts = @(
        ($t -split '\s+') |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($parts.Count -lt 2) {
        return @{ Nom = $parts[0]; Prenom = '' }
    }
    return @{
        Prenom = $parts[0]
        Nom    = (($parts | Select-Object -Skip 1) -join ' ')
    }
}

function Get-CnsDestructionCertificatePlaceholders {
    param(
        [Parameter(Mandatory = $true)]
        $WorkOrderEntity,
        [AllowNull()]
        $SegmentMeta,
        [Parameter(Mandatory = $true)]
        [datetime]$VisitDate
    )
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    [string]$dateCollecte = $VisitDate.ToString('dd/MM/yyyy', $inv)

    [string]$clientId = ''
    [string]$clientNom = ''
    [string]$street = ''
    [string]$cp = ''
    [string]$ville = ''
    [string]$odmNum = ''
    try { $clientId = [string]$WorkOrderEntity.ClientID } catch { }
    try { $clientNom = [string]$WorkOrderEntity.ClientName } catch { }
    try { $odmNum = [string]$WorkOrderEntity.WorkOrder } catch { }
    if ([string]::IsNullOrWhiteSpace($odmNum)) {
        foreach ($svc in @($WorkOrderEntity.Services)) {
            if ($null -eq $svc) { continue }
            try {
                $od = [string]$svc.ODM
                if (-not [string]::IsNullOrWhiteSpace($od)) { $odmNum = $od.Trim(); break }
            }
            catch { }
        }
    }
    if ($null -ne $WorkOrderEntity.Address) {
        try { $street = [string]$WorkOrderEntity.Address.Street } catch { }
        try { $cp = [string]$WorkOrderEntity.Address.PostalCode } catch { }
        try { $ville = [string]$WorkOrderEntity.Address.City } catch { }
    }

    [string]$collecteurRaw = ''
    [string]$vehicule = ''
    if ($null -ne $SegmentMeta) {
        try { $collecteurRaw = [string]$SegmentMeta.Collecteur } catch { }
        try { $vehicule = [string]$SegmentMeta.Vehicule } catch { }
    }
    $np = Split-CnsCollecteurNomPrenom -CollecteurText $collecteurRaw

    return [ordered]@{
        Date_Collecte     = $dateCollecte
        Client_ID         = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $clientId)
        Client_Nom        = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $clientNom)
        Client_Adresse    = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $street)
        Client_CP         = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $cp)
        Client_Ville      = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $ville)
        Collecteur_Nom    = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value ([string]$np.Nom))
        Collecteur_Prenom = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value ([string]$np.Prenom))
        Vehicule_Immat    = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $vehicule)
        ODM_Numero        = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value $odmNum)
    }
}

function New-CnsDestructionCertificatePdfFromWordTemplate {
    <#
    .SYNOPSIS
        Remplit le template DOCX (placeholders) et exporte un PDF via LibreOffice. Retourne le chemin PDF ou $null.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutPdfPath,
        [Parameter(Mandatory = $true)]
        [hashtable]$Placeholders,
        [string]$TemplatePath
    )
    if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
        $TemplatePath = Get-CnsDestructionCertificateTemplatePath
    }
    if ([string]::IsNullOrWhiteSpace($TemplatePath) -or -not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
        Write-Warning '[DESTRUCTION-CERT] Template DOCX introuvable (templates\CertificatDeDestruction.docx ou CN_DESTRUCTION_CERT_TEMPLATE).'
        return $null
    }

    if (-not (Get-CnsLibreOfficeSofficePath)) {
        Write-Warning '[DESTRUCTION-CERT] LibreOffice introuvable'
        return $null
    }

    $outAbs = [System.IO.Path]::GetFullPath($OutPdfPath)
    $outDir = Split-Path -Parent $outAbs
    if (-not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop
    }

    $runId = [Guid]::NewGuid().ToString('N')
    $workDocx = Join-Path $env:TEMP ("cn_destr_cert_{0}.docx" -f $runId)
    Copy-Item -LiteralPath $TemplatePath -Destination $workDocx -Force

    try {
        if (-not (Set-CnsDocxTemplatePlaceholders -DocxPath $workDocx -Placeholders $Placeholders)) {
            return $null
        }
        if (-not (Convert-DocxToPdfUsingLibreOffice -DocxPath $workDocx -PdfPath $outAbs)) {
            return $null
        }
    }
    finally {
        if (Test-Path -LiteralPath $workDocx) {
            Remove-Item -LiteralPath $workDocx -Force -ErrorAction SilentlyContinue
        }
        $loPdfSide = Join-Path $env:TEMP ([System.IO.Path]::GetFileNameWithoutExtension($workDocx) + '.pdf')
        if (Test-Path -LiteralPath $loPdfSide) {
            Remove-Item -LiteralPath $loPdfSide -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not (Test-Path -LiteralPath $outAbs)) {
        Write-Warning '[DESTRUCTION-CERT] PDF non produit apres conversion LibreOffice.'
        return $null
    }
    return $outAbs
}

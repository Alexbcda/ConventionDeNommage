# Bilan de collecte : template DOCX -> PDF (LibreOffice headless, sans Microsoft Word).
# Reutilise le moteur w:t safe et la conversion LibreOffice du certificat destruction.

. (Join-Path $PSScriptRoot 'CnsDestructionCertificateWord.ps1')

function Get-CnsBilanCollecteTemplatePath {
    $candidates = New-Object System.Collections.Generic.List[string]
    try {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
        [void]$candidates.Add((Join-Path $repoRoot 'templates\planning\collecte\BilanDeCollecte.docx'))
        [void]$candidates.Add((Join-Path $repoRoot 'templates\BilanDeCollecte.docx'))
    }
    catch { }
    if (-not [string]::IsNullOrWhiteSpace($env:CN_BILAN_COLLECTE_TEMPLATE)) {
        [void]$candidates.Insert(0, $env:CN_BILAN_COLLECTE_TEMPLATE.Trim())
    }
    foreach ($p in @($candidates)) {
        if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path -LiteralPath $p -PathType Leaf)) {
            return ([System.IO.Path]::GetFullPath($p))
        }
    }
    return $null
}

function Get-CnsBilanCollectePlaceholders {
    <#
    .SYNOPSIS
        Placeholders BilanDeCollecte.docx : Date_Collecte, Collecteur_Prenom, Collecteur_Nom.
    #>
    param(
        [AllowNull()]
        $SegmentMeta,
        [Parameter(Mandatory = $true)]
        [datetime]$VisitDate
    )
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    [string]$dateCollecte = $VisitDate.ToString('dd/MM/yyyy', $inv)

    [string]$collecteurRaw = ''
    if ($null -ne $SegmentMeta) {
        try {
            $dj = [string]$SegmentMeta.DisplayDateJM
            if (-not [string]::IsNullOrWhiteSpace($dj)) {
                $dateCollecte = $dj.Trim()
            }
            elseif ($null -ne $SegmentMeta.TourDate) {
                $dateCollecte = ([datetime]$SegmentMeta.TourDate).ToString('dd/MM/yyyy', $inv)
            }
        }
        catch { }
        try { $collecteurRaw = [string]$SegmentMeta.Collecteur } catch { }
    }

    $collecteurResolved = Resolve-CnsCollecteurFieldsForCertificate -CollecteurExcelRaw $collecteurRaw

    return [ordered]@{
        Date_Collecte     = $dateCollecte
        Collecteur_Nom    = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value ([string]$collecteurResolved.Nom))
        Collecteur_Prenom = (ConvertTo-CnsDestructionCertificatePlaceholderValue -Value ([string]$collecteurResolved.Prenom))
    }
}

function New-CnsBilanCollectePdfFromWordTemplate {
    <#
    .SYNOPSIS
        Remplit BilanDeCollecte.docx et exporte un PDF via LibreOffice. Retourne le chemin PDF ou $null.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutPdfPath,
        [Parameter(Mandatory = $true)]
        [hashtable]$Placeholders,
        [string]$TemplatePath
    )
    if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
        $TemplatePath = Get-CnsBilanCollecteTemplatePath
    }
    if ([string]::IsNullOrWhiteSpace($TemplatePath) -or -not (Test-Path -LiteralPath $TemplatePath -PathType Leaf)) {
        Write-Warning '[BILAN-COLLECTE] Template DOCX introuvable (templates\BilanDeCollecte.docx ou CN_BILAN_COLLECTE_TEMPLATE).'
        return $null
    }

    if (-not (Get-CnsLibreOfficeSofficePath)) {
        Write-Warning '[BILAN-COLLECTE] LibreOffice introuvable (soffice.exe).'
        return $null
    }

    $outAbs = [System.IO.Path]::GetFullPath($OutPdfPath)
    $outDir = Split-Path -Parent $outAbs
    if (-not (Test-Path -LiteralPath $outDir)) {
        $null = New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop
    }

    $runId = [Guid]::NewGuid().ToString('N')
    $workDocx = Join-Path $env:TEMP ("cn_bilan_collecte_{0}.docx" -f $runId)
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
            if (-not [string]::IsNullOrWhiteSpace($env:CN_KEEP_BILAN_COLLECTE_DOCX)) {
                Write-Host ("[BILAN-COLLECTE] DOCX conserve (CN_KEEP_BILAN_COLLECTE_DOCX) : {0}" -f $workDocx) -ForegroundColor DarkYellow
            }
            else {
                Remove-Item -LiteralPath $workDocx -Force -ErrorAction SilentlyContinue
            }
        }
        $loPdfSide = Join-Path $env:TEMP ([System.IO.Path]::GetFileNameWithoutExtension($workDocx) + '.pdf')
        if (Test-Path -LiteralPath $loPdfSide) {
            Remove-Item -LiteralPath $loPdfSide -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not (Test-Path -LiteralPath $outAbs)) {
        Write-Warning '[BILAN-COLLECTE] PDF non produit apres conversion LibreOffice.'
        return $null
    }
    return $outAbs
}

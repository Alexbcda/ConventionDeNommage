# PDFReorganizer.ps1 - Réorganisation de PDF
. (Join-Path $PSScriptRoot 'GhostscriptResolve.ps1')
$_scalarGuard = Join-Path $PSScriptRoot '..\Common\ScalarGuard.ps1'
if (Test-Path -LiteralPath $_scalarGuard) { . $_scalarGuard }
$_sortSafe = Join-Path $PSScriptRoot '..\Common\SortSafe.ps1'
if (Test-Path -LiteralPath $_sortSafe) { . $_sortSafe }

function Test-PlausibleGeneratedPdf {
    <#
    .SYNOPSIS
        Vérifie qu'un chemin pointe vers un PDF probablement valide (en-tête %PDF- et taille minimale).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [int]$MinBytes = 200
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $i = Get-Item -LiteralPath $Path
    if ($i.Length -lt $MinBytes) { return $false }
    $fs = $null
    try {
        $fs = [System.IO.File]::OpenRead($i.FullName)
        $b = [byte[]]::new(5)
        $n = $fs.Read($b, 0, 5)
        if ($n -lt 5) { return $false }
        $s = [System.Text.Encoding]::ASCII.GetString($b)
        return ($s -eq '%PDF-')
    }
    finally { if ($null -ne $fs) { $fs.Dispose() } }
}

function Reorganiser-PDF {
    param(
        [string]$SourcePDF, 
        [string]$OutputPDF, 
        [hashtable]$Mapping,
        [int[]]$OrderedPhysicalPages = @(),
        [int]$SourcePdfPageCountHint = 0
    )
    
    Write-Host "`n[PDF] === DEBUT REORGANISATION ===" -ForegroundColor Cyan
    Write-Host "[PDF] Source : $(Split-Path $SourcePDF -Leaf)" -ForegroundColor Gray
    Write-Host "[PDF] Destination : $(Split-Path $OutputPDF -Leaf)" -ForegroundColor Gray
    
    $useOrderedSequence = @($OrderedPhysicalPages).Count -gt 0
    if ($useOrderedSequence) {
        Write-Host ("[PDF] Ordre explicite (OrderedPhysicalPages) : {0} occurrence(s)" -f @($OrderedPhysicalPages).Count) -ForegroundColor Gray
    }
    else {
        Write-Host "[PDF] Pages configurées (mapping clé par page) : $($Mapping.Count)" -ForegroundColor Gray
    }
    
    # Ordre des pages : séquence explicite (doublons autorisés) OU tri depuis le mapping (une entrée par numéro de page)
    $pageNumbers = @()
    if ($useOrderedSequence) {
        $pageNumbers = @($OrderedPhysicalPages | ForEach-Object { [int]$_ })
    }
    else {
        $pagesOrder = @()
        foreach ($key in $Mapping.Keys) {
            $row = $Mapping[$key]
            $tRaw = if ($null -ne $row) { $row.Tournee } else { 0 }
            $rRaw = if ($null -ne $row) { $row.Rang } else { 0 }
            if (Get-Command ConvertTo-SafeInt -ErrorAction SilentlyContinue) {
                $tNum = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $tRaw -Name "pdf.Tournee") -Name "pdf.Tournee")
                $rNum = (ConvertTo-SafeInt -Value (Normalize-Scalar -Value $rRaw -Name "pdf.Rang") -Name "pdf.Rang")
            } else {
                $tNum = [int]($tRaw)
                $rNum = [int]($rRaw)
            }
            $pagesOrder += [PSCustomObject]@{
                PageNum = [int]$key
                Tournee = $tNum
                Rang    = $rNum
            }
        }
        $pagesOrder = Sort-SafeTripleInt -InputObject $pagesOrder -P1 Tournee -P2 Rang -P3 PageNum
        $pageNumbers = @($pagesOrder | ForEach-Object { [int]$_.PageNum })
    }
    $pageRange = $pageNumbers -join ','

    Write-Host ("[GS-PREP] pageList.Count={0}" -f $pageNumbers.Count) -ForegroundColor Cyan
    if ($pageNumbers.Count -le 200) {
        Write-Host ("[GS-PREP] pageList.Full={0}" -f $pageRange) -ForegroundColor DarkCyan
    }
    else {
        $headCh = (($pageNumbers[0..199] | ForEach-Object { "$_" }) -join ',')
        Write-Host ("[GS-PREP] pageList.preview(200premiers)={0},..." -f $headCh) -ForegroundColor DarkCyan
    }

    Write-Host "[PDF] Ordre des pages : $pageRange" -ForegroundColor Green

    if (-not (Test-Path -LiteralPath $SourcePDF -PathType Leaf)) {
        Write-Warning "PDFReorganizer: source introuvable : $SourcePDF"
        return $false
    }
    if (-not $useOrderedSequence -and ($null -eq $Mapping -or $Mapping.Count -eq 0)) {
        Write-Warning "PDFReorganizer: mapping vide."
        return $false
    }
    $outDir = Split-Path -Parent -Path $OutputPDF
    if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -LiteralPath $outDir)) {
        try {
            $null = New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop
        } catch {
            Write-Warning "PDFReorganizer: impossible de créer le dossier cible : $outDir"
            return $false
        }
    }

    $gsPath = Get-ResolvedGhostscriptPath
    if ($gsPath) {
        Write-Host "[PDF] Ghostscript (exécution) : $gsPath" -ForegroundColor Green
        if (-not (Test-Path -LiteralPath $gsPath -PathType Leaf)) {
            Write-Warning "PDFReorganizer: binaire GS résolu introuvable : $gsPath"
            return $false
        }

        $resolvedSource = (Resolve-Path -LiteralPath $SourcePDF).Path
        $outAbs = [System.IO.Path]::GetFullPath($OutputPDF)

        if ($pageNumbers.Count -lt 1) {
            Write-Host "[ERROR] Ghostscript : liste des pages vide (aucune page à écrire)." -ForegroundColor Red
            return $false
        }

        if ($SourcePdfPageCountHint -gt 1 -and $pageNumbers.Count -eq 1) {
            Write-Host ("[ERROR] Troncature suspecte du pipeline : hint pages source={0} mais sequence GS={1}. Verifier sanitize / mapping Hashtable (cles dupliquées)." -f $SourcePdfPageCountHint, $pageNumbers.Count) -ForegroundColor Red
            return $false
        }

        # Une seule paire -dFirstPage/-dLastPage est prise en compte par invocation : plusieurs paires écrase la précédente
        # → extraction 1 page / fichier temp puis fusion multi -f en une deuxième passe.
        $errFile = Join-Path $env:TEMP ("cn_gs_err_{0}.txt" -f [Guid]::NewGuid().ToString('N'))
        if (Test-Path -LiteralPath $errFile) { Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue }

        $runGuid = [Guid]::NewGuid().ToString('N')
        $tempSingles = [System.Collections.Generic.List[string]]::new()
        $process = $null
        $stderr = ''
        try {
            if ($pageNumbers.Count -eq 1) {
                $only = [int]$pageNumbers[0]
                Write-Host "[GS-PREP] single-page shortcut FirstPage=$only" -ForegroundColor DarkCyan
                $gsArgsSingle = @(
                    '-dNOPAUSE', '-dBATCH', '-sDEVICE=pdfwrite',
                    ("-sOutputFile=$outAbs"),
                    ("-dFirstPage=$only"), ("-dLastPage=$only"),
                    $resolvedSource
                )
                $cmdChars = 0
                foreach ($_a in $gsArgsSingle) { $cmdChars += $_a.Length + 1 }
                Write-Host "[GS-PREP] singlePass approxArgChars=$cmdChars" -ForegroundColor DarkGray
                $process = Start-Process -FilePath $gsPath -ArgumentList $gsArgsSingle -NoNewWindow -Wait -PassThru -RedirectStandardError $errFile
            }
            else {
                $pi = 0
                foreach ($pageNum in $pageNumbers) {
                    $pnI = [int]$pageNum
                    $sliceOut = Join-Path $env:TEMP ("cn_gs_slice_{0}_{1:D5}.pdf" -f $runGuid, $pi)
                    $pi++
                    $argSlice = @(
                        '-dNOPAUSE', '-dBATCH', '-sDEVICE=pdfwrite',
                        ("-sOutputFile=$sliceOut"),
                        ("-dFirstPage=$pnI"), ("-dLastPage=$pnI"),
                        $resolvedSource
                    )
                    if ($pi -eq 1 -or ($pi % 50 -eq 0)) {
                        Write-Host ("[PDF] Ghostscript extraction page {0}/{1}" -f $pi, $pageNumbers.Count) -ForegroundColor Gray
                    }
                    $prSlice = Start-Process -FilePath $gsPath -ArgumentList $argSlice -NoNewWindow -Wait -PassThru -RedirectStandardError $errFile
                    if ($null -eq $prSlice -or $prSlice.ExitCode -ne 0) {
                        $ec = if ($null -eq $prSlice) { '(null)' } else { "$($prSlice.ExitCode)" }
                        Write-Host "[ERROR] Ghostscript extraction echouee : page=$pnI ExitCode=$ec" -ForegroundColor Red
                        if (Test-Path -LiteralPath $errFile) {
                            Write-Host ([string](Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue)) -ForegroundColor DarkRed
                        }
                        return $false
                    }
                    if (-not (Test-Path -LiteralPath $sliceOut)) {
                        Write-Host "[ERROR] Fichier page extrait absent : $sliceOut" -ForegroundColor Red
                        return $false
                    }
                    [void]$tempSingles.Add($sliceOut)
                }

                $mergeArgs = [System.Collections.Generic.List[string]]::new()
                [void]$mergeArgs.AddRange([string[]]@('-dNOPAUSE', '-dBATCH', '-sDEVICE=pdfwrite', ("-sOutputFile=$outAbs")))
                foreach ($tp in $tempSingles) {
                    [void]$mergeArgs.Add('-f')
                    [void]$mergeArgs.Add($tp)
                }
                $argLenEst = 0
                foreach ($part in @($mergeArgs)) { $argLenEst += ($part.Length + 1) }
                Write-Host ("[GS-PREP] merge pass partCount=$($mergeArgs.Count) approxArgChars=$argLenEst") -ForegroundColor DarkCyan
                $useRsp = ($argLenEst -gt 28000 -or $tempSingles.Count -gt 50)
                if ($useRsp) {
                    $rspPath = Join-Path $env:TEMP ("cn_gs_merge_{0}.rsp" -f $runGuid)
                    $rspBody = New-Object System.Collections.Generic.List[string]
                    foreach ($tp in @($tempSingles)) {
                        [void]$rspBody.Add('-f')
                        [void]$rspBody.Add("`"$tp`"")
                    }
                    [System.IO.File]::WriteAllLines($rspPath, $rspBody.ToArray())
                    Write-Host "[GS-PREP] merge utilise fichier arguments (liste longue ou >50 fichiers)" -ForegroundColor DarkYellow
                    $atMerge = "@$rspPath"
                    $mergeArgsRsp = @('-dNOPAUSE', '-dBATCH', '-sDEVICE=pdfwrite', ("-sOutputFile=$outAbs"), $atMerge )
                    $process = Start-Process -FilePath $gsPath -ArgumentList $mergeArgsRsp -NoNewWindow -Wait -PassThru -RedirectStandardError $errFile
                    if (Test-Path -LiteralPath $rspPath) {
                        Remove-Item -LiteralPath $rspPath -Force -ErrorAction SilentlyContinue
                    }
                }
                else {
                    $process = Start-Process -FilePath $gsPath -ArgumentList @($mergeArgs.ToArray()) -NoNewWindow -Wait -PassThru -RedirectStandardError $errFile
                }
            }
        } catch {
            Write-Host "[ERROR] Ghostscript pipeline : $_" -ForegroundColor Red
            return $false
        } finally {
            foreach ($ts in @($tempSingles)) {
                if (Test-Path -LiteralPath $ts) {
                    Remove-Item -LiteralPath $ts -Force -ErrorAction SilentlyContinue
                }
            }
            if (Test-Path -LiteralPath $errFile) {
                $stderr = [string](Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue)
                Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
            }
        }

        Write-Host "[PDF] Fusion / ecriture Ghostscript terminee (stderr agrégée si erreur)." -ForegroundColor Gray

        if ($null -eq $process) {
            Write-Host "[ERROR] Processus Ghostscript non démarré." -ForegroundColor Red
            if (-not [string]::IsNullOrWhiteSpace($stderr)) { Write-Host $stderr -ForegroundColor DarkRed }
            return $false
        }

        if ($process.ExitCode -ne 0) {
            Write-Host "[ERROR] Ghostscript a échoué (code: $($process.ExitCode))" -ForegroundColor Red
            if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                Write-Host "[ERROR] Sortie d'erreur Ghostscript (stderr) :" -ForegroundColor DarkRed
                Write-Host $stderr -ForegroundColor DarkRed
            } else { Write-Host "[ERROR] (stderr vide ; vérifier chemins, droits, argument -sOutputFile.)" -ForegroundColor DarkRed }
            return $false
        }

        if (-not (Test-PlausibleGeneratedPdf -Path $outAbs)) {
            Write-Host "[ERROR] Fichier de sortie absent ou n'est pas un PDF valide (en-tête %PDF- / taille minimale)." -ForegroundColor Red
            if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                Write-Host "[ERROR] Sortie stderr Ghostscript (aide diagnostic) :" -ForegroundColor DarkRed
                Write-Host $stderr -ForegroundColor DarkRed
            }
            if (Test-Path -LiteralPath $outAbs) {
                $len = (Get-Item -LiteralPath $outAbs).Length
                Write-Host ("[ERROR] Fichier trouvé : {0} octet(s)" -f $len) -ForegroundColor DarkRed
            }
            return $false
        }

        if (-not [string]::IsNullOrWhiteSpace($stderr) -and $stderr -match '(?i)error|fatal|invalid|cannot|failed') {
            Write-Host "[WARN] Ghostscript (code 0) mais message suspect sur stderr : voir ci-dessous" -ForegroundColor Yellow
            Write-Host $stderr -ForegroundColor DarkYellow
        }

        $sz = (Get-Item -LiteralPath $outAbs).Length
        Write-Host ("[PDF] OK — sortie vérifiée (en-tête %PDF- + {0} octet(s))" -f $sz) -ForegroundColor Green
        return $true
    } else {
        Write-Warning "Ghostscript (gswin64c) introuvable : pas de génération PDF automatique. Définir GHOSTSCRIPT_EXE vers l'exécutable, ou ajouter gswin64c au PATH, ou installer Ghostscript (ex. https://ghostscript.com/releases/gsdnld.html) — le binaire PDF24 est souvent sous Program Files\PDF24\gs\bin\."
        Write-Host "[PDF] Ghostscript non détecté (voir avertissement ci-dessus)" -ForegroundColor Yellow

        # Alternative : Utiliser l'impression Windows
        Add-Type -AssemblyName System.Windows.Forms

        $message = @"
Aucun exécutable Ghostscript détecté (hors emplacements connus, PATH, GHOSTSCRIPT_EXE).

1. Téléchargez Ghostscript : https://ghostscript.com/releases/gsdnld.html
   (ou indiquez le chemin complet dans la variable d'environnement GHOSTSCRIPT_EXE)
2. Installez-le
3. Réessayez

OU procédez manuellement imprimable :

1. Le PDF source va s'ouvrir
2. Ctrl+P
3. « Microsoft Print to PDF »
4. Pages : $pageRange
5. Enregistrez vers : $OutputPDF
"@
        
        $result = [System.Windows.Forms.MessageBox]::Show(
            $message,
            "Réorganisation PDF",
            [System.Windows.Forms.MessageBoxButtons]::OKCancel,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            Start-Process $SourcePDF
        }
        Write-Warning "Aucun PDF n'a été généré automatiquement (Ghostscript manquant) ; pas de succès allégé côté application."
        return $false
    }
}

function Get-PDFPageCount {
    param([string]$FichierPDF)
    
    if (-not (Test-Path $FichierPDF)) {
        return 0
    }
    
    $gsPath = Get-ResolvedGhostscriptPath
    if ($gsPath) {
        try {
            $psPath = $FichierPDF -replace '\\', '/'
            $output = & $gsPath -dNODISPLAY -q -c "($psPath) (r) file runpdfbegin pdfpagecount = quit" 2>&1
            $joined = if ($output -is [array]) { $output -join "`n" } else { [string]$output }
            if ($joined -match '(\d+)') {
                return [int]$Matches[1]
            }
        } catch { }
    }
    
    # Fallback : compter via COM
    try {
        $pdfDoc = New-Object -ComObject "AcroExch.PDDoc"
        $pdfDoc.Open($FichierPDF)
        $count = $pdfDoc.GetNumPages()
        $pdfDoc.Close()
        return $count
    } catch {
        return 1
    }
}

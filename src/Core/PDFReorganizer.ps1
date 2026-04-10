# PDFReorganizer.ps1 - Réorganisation de PDF

function Reorganiser-PDF {
    param(
        [string]$SourcePDF, 
        [string]$OutputPDF, 
        [hashtable]$Mapping
    )
    
    Write-Host "`n[PDF] === DEBUT REORGANISATION ===" -ForegroundColor Cyan
    Write-Host "[PDF] Source : $(Split-Path $SourcePDF -Leaf)" -ForegroundColor Gray
    Write-Host "[PDF] Destination : $(Split-Path $OutputPDF -Leaf)" -ForegroundColor Gray
    Write-Host "[PDF] Pages configurées : $($Mapping.Count)" -ForegroundColor Gray
    
    # Calculer l'ordre des pages
    $pagesOrder = @()
    foreach ($key in $Mapping.Keys) {
        $pagesOrder += [PSCustomObject]@{
            PageNum = [int]$key
            Tournee = $Mapping[$key].Tournee
            Rang = $Mapping[$key].Rang
        }
    }
    $pagesOrder = $pagesOrder | Sort-Object Tournee, Rang, PageNum
    $pageNumbers = $pagesOrder | ForEach-Object { $_.PageNum }
    $pageRange = $pageNumbers -join ','
    
    Write-Host "[PDF] Ordre des pages : $pageRange" -ForegroundColor Green
    
    # Vérifier si Ghostscript est installé
    $gsPaths = @(
        "C:\Program Files\gs\gs10.01.1\bin\gswin64c.exe",
        "C:\Program Files\gs\gs10.00.0\bin\gswin64c.exe",
        "C:\Program Files\gs\gs9.56.1\bin\gswin64c.exe",
        "C:\Program Files\gs\gs9.55.0\bin\gswin64c.exe",
        "C:\Program Files\Ghostscript\bin\gswin64c.exe"
    )
    
    $gsPath = $null
    foreach ($path in $gsPaths) {
        if (Test-Path $path) {
            $gsPath = $path
            break
        }
    }
    
    if ($gsPath) {
        Write-Host "[PDF] Ghostscript trouvé : $gsPath" -ForegroundColor Green
        
        try {
            # Construire la commande Ghostscript
            $gsArgs = @(
                "-dNOPAUSE",
                "-dBATCH",
                "-sDEVICE=pdfwrite",
                "-sOutputFile=`"$OutputPDF`""
            )
            
            # Ajouter chaque page individuellement
            foreach ($pageNum in $pageNumbers) {
                $gsArgs += "-dFirstPage=$pageNum"
                $gsArgs += "-dLastPage=$pageNum"
            }
            
            $gsArgs += "`"$SourcePDF`""
            
            Write-Host "[PDF] Exécution de Ghostscript..." -ForegroundColor Gray
            $process = Start-Process -FilePath $gsPath -ArgumentList $gsArgs -NoNewWindow -Wait -PassThru
            
            if ($process.ExitCode -eq 0 -and (Test-Path $OutputPDF)) {
                Write-Host "[PDF] ✅ PDF créé avec succès !" -ForegroundColor Green
                return $true
            } else {
                Write-Host "[PDF] ❌ Ghostscript a échoué (code: $($process.ExitCode))" -ForegroundColor Red
                return $false
            }
        } catch {
            Write-Host "[PDF] ❌ Erreur Ghostscript : $_" -ForegroundColor Red
            return $false
        }
    } else {
        Write-Host "[PDF] Ghostscript non trouvé" -ForegroundColor Yellow
        
        # Alternative : Utiliser l'impression Windows
        Add-Type -AssemblyName System.Windows.Forms
        
        $message = @"
Ghostscript n'est pas installé. Pour réorganiser le PDF :

1. Téléchargez Ghostscript : https://ghostscript.com/releases/gsdnld.html
2. Installez-le
3. Réessayez

OU utilisez cette méthode manuelle :

1. Le PDF va s'ouvrir
2. Appuyez sur Ctrl+P
3. Sélectionnez "Microsoft Print to PDF"
4. Dans "Pages", entrez : $pageRange
5. Imprimez vers : $OutputPDF
"@
        
        $result = [System.Windows.Forms.MessageBox]::Show(
            $message,
            "Réorganisation PDF",
            [System.Windows.Forms.MessageBoxButtons]::OKCancel,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            Start-Process $SourcePDF
            return $true  # On considère que l'utilisateur va le faire manuellement
        }
        return $false
    }
}

function Get-PDFPageCount {
    param([string]$FichierPDF)
    
    if (-not (Test-Path $FichierPDF)) {
        return 0
    }
    
    # Utiliser Ghostscript pour compter les pages
    $gsPaths = @(
        "C:\Program Files\gs\gs10.01.1\bin\gswin64c.exe",
        "C:\Program Files\gs\gs10.00.0\bin\gswin64c.exe"
    )
    
    foreach ($gsPath in $gsPaths) {
        if (Test-Path $gsPath) {
            try {
                $output = & $gsPath -dNODISPLAY -q -c "($FichierPDF) (r) file runpdfbegin pdfpagecount = quit" 2>&1
                if ($output -match '\d+') {
                    return [int]$matches[0]
                }
            } catch {}
        }
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

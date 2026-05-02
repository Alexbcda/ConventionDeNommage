# ============================================================
# PdfPlanningOptimizer.ps1
# Point d'entree unique : toute l'orchestration PDF+Excel+sortie
# repose sur Start-PlanningRebuild (Services\PlanningRebuilder.ps1).
# ============================================================

. (Join-Path $PSScriptRoot "Services\PlanningRebuilder.ps1")

function Invoke-PdfPlanningOptimizer {
    <#
    .SYNOPSIS
        Delegation vers le pipeline reelle (Start-PlanningRebuild) avec chemin de sortie optionnel.
    .PARAMETER SourcePdfPath
        Chemin du PDF source (alias semantique de -PdfPath).
    .PARAMETER ExcelPath
        Chemin du fichier de planning.
    .PARAMETER OutputPdfPath
        Chemin souhaite pour le PDF reordonne : si differents du generé a cote du source,
        le fichier est copie vers cette destination.
    .OUTPUTS
        Meme objet que Start-PlanningRebuild (ou $null).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePdfPath,

        [Parameter(Mandatory = $true)]
        [string]$ExcelPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPdfPath
    )

    $r = Start-PlanningRebuild -PdfPath $SourcePdfPath -ExcelPath $ExcelPath
    if ($null -eq $r) { return $null }
    if ([string]::IsNullOrWhiteSpace($OutputPdfPath) -or [string]::IsNullOrWhiteSpace($r.OutputPdf)) {
        return $r
    }
    if (-not (Test-Path -LiteralPath $r.OutputPdf -PathType Leaf)) {
        return $r
    }
    $want = [System.IO.Path]::GetFullPath($OutputPdfPath)
    $have = [System.IO.Path]::GetFullPath($r.OutputPdf)
    if ($want -cne $have) {
        $dir = Split-Path -Parent -Path $want
        if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
            $null = New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue
        }
        try {
            Copy-Item -LiteralPath $r.OutputPdf -Destination $OutputPdfPath -Force
            $r | Add-Member -NotePropertyName OutputPdf -NotePropertyValue $OutputPdfPath -Force
        } catch { }
    }
    return $r
}

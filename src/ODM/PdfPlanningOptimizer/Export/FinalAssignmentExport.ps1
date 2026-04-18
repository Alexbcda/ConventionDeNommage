# ============================================================
# FinalAssignmentExport.ps1
# Export métier (CSV ou classeur Excel) à partir de FinalAssignment[].
# Aucune modification du matching ni des traces : lecture seule des propriétés existantes.
# ============================================================

. (Join-Path $PSScriptRoot "..\Models\MatchResult.ps1")
. (Join-Path $PSScriptRoot "..\Models\FinalAssignment.ps1")

function script:Get-DecisionReasonBusinessLabel {
    param([string]$DecisionReason)
    switch ($DecisionReason) {
        'WIN_SCORE' { return 'Selection par meilleur score' }
        'WIN_TIEBREAK' { return 'Selection apres egalite (priorite champs)' }
        'REJECTED_CONFLICT' { return 'Rejet (conflit)' }
        default {
            if ([string]::IsNullOrWhiteSpace($DecisionReason)) { return '' }
            return $DecisionReason
        }
    }
}

function script:Get-ConcurrentSummaryBusinessText {
    param(
        [FinalAssignment]$Assignment,
        [int]$MaxEntries = 12
    )
    if ($null -eq $Assignment -or $null -eq $Assignment.Trace) { return '' }
    $candidates = @($Assignment.Trace.CompetingCandidates | Where-Object { $null -ne $_ })
    if ($candidates.Count -eq 0) { return '' }

    $n = $candidates.Count
    $parts = [System.Collections.Generic.List[string]]::new()
    $i = 0
    foreach ($c in $candidates) {
        if ($i -ge $MaxEntries) { break }
        $parts.Add(("Commande {0}, ligne {1}, score {2}" -f @($c.WorkOrder, [string]$c.ExcelRowId, $c.MatchScore)))
        $i++
    }
    $suffix = if ($n -gt $MaxEntries) { " (+{0} autre(s))" -f ($n - $MaxEntries) } else { '' }
    return ("{0} autre(s) candidature(s) : {1}{2}" -f $n, ($parts -join ' | '), $suffix)
}

function script:Build-FinalAssignmentExportRecords {
    param(
        [FinalAssignment[]]$FinalAssignments,
        [bool]$IncludeConcurrentSummary,
        [bool]$UseTechnicalHeaders
    )
    $rows = [System.Collections.Generic.List[object]]::new()

    if ($UseTechnicalHeaders) {
        $hCommande = 'WorkOrder'
        $hLigne = 'ExcelRowId'
        $hScore = 'FinalScore'
        $hDecision = 'DecisionReason'
        $hConflit = 'ConflictResolved'
        $hResume = 'ConcurrentSummary'
    }
    else {
        $hCommande = 'Commande'
        $hLigne = 'Reference_ligne_planification'
        $hScore = 'Score_final'
        $hDecision = 'Motif_selection'
        $hConflit = 'Conflit_regle'
        $hResume = 'Synthese_concurrents'
    }

    foreach ($fa in @($FinalAssignments | Where-Object { $null -ne $_ })) {
        $reasonRaw = $null
        if ($null -ne $fa.Trace) {
            $reasonRaw = $fa.Trace.DecisionReason
        }
        $decisionLabel = Get-DecisionReasonBusinessLabel -DecisionReason $reasonRaw

        $resume = ''
        if ($IncludeConcurrentSummary) {
            $resume = Get-ConcurrentSummaryBusinessText -Assignment $fa
        }

        $row = [ordered]@{}
        $row[$hCommande] = if ([string]::IsNullOrWhiteSpace($fa.WorkOrder)) { '' } else { $fa.WorkOrder }
        $row[$hLigne] = if ($null -eq $fa.ExcelRowId) { '' } else { [string]$fa.ExcelRowId }
        $row[$hScore] = $fa.FinalScore
        if ($UseTechnicalHeaders) {
            $row[$hDecision] = if ([string]::IsNullOrWhiteSpace($reasonRaw)) { '' } else { $reasonRaw }
            $row[$hConflit] = if ($fa.ConflictResolved) { 'True' } else { 'False' }
        }
        else {
            $row[$hDecision] = $decisionLabel
            $row[$hConflit] = if ($fa.ConflictResolved) { 'Oui' } else { 'Non' }
        }
        if ($IncludeConcurrentSummary) {
            $row[$hResume] = $resume
        }

        $rows.Add([pscustomobject]$row)
    }

    return @($rows.ToArray())
}

function Export-FinalAssignmentReport {
    <#
    .SYNOPSIS
    Exporte les affectations finales vers un fichier CSV ou Excel (lisible métier).

    .DESCRIPTION
    Colonnes par défaut (libellés métier) : Commande, Reference_ligne_planification, Score_final,
    Motif_selection, Conflit_regle (Oui/Non), Synthese_concurrents (optionnel).
    Format Excel : via Excel COM (Windows + Excel installé) ; en cas d’échec, bascule CSV avec avertissement.

    .PARAMETER FinalAssignments
    Sortie de Resolve-WorkOrderExcelFinalAssignments.

    .PARAMETER OutputPath
    Chemin du fichier de sortie (.csv ou .xlsx selon -Format).

    .PARAMETER Format
    Csv (défaut, UTF-8 avec BOM si disponible) ou Excel (COM).

    .PARAMETER IncludeConcurrentSummary
    Remplit la synthèse des concurrents (texte court). Par défaut : désactivé (export plus léger).

    .PARAMETER UseTechnicalHeaders
    Utilise les en-têtes techniques (WorkOrder, ExcelRowId, …) au lieu des libellés métier.

    .OUTPUTS
    System.IO.FileInfo ou chemin du fichier écrit.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [FinalAssignment[]]$FinalAssignments,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Csv', 'Excel')]
        [string]$Format = 'Csv',

        [switch]$IncludeConcurrentSummary,

        [switch]$UseTechnicalHeaders
    )

    $includeSummary = [bool]$IncludeConcurrentSummary
    $tech = [bool]$UseTechnicalHeaders
    $records = @(Build-FinalAssignmentExportRecords -FinalAssignments $FinalAssignments -IncludeConcurrentSummary $includeSummary -UseTechnicalHeaders $tech)

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    $dir = Split-Path -Path $resolvedPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if ($Format -eq 'Csv') {
        $csvPath = if ($resolvedPath -like '*.csv') { $resolvedPath } else { "$resolvedPath.csv" }
        if ($csvPath -cne $resolvedPath) {
            Write-Verbose "Extension .csv ajoutée : $csvPath"
        }

        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $records | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8BOM -Delimiter ';'
        }
        else {
            $records | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
            $bytes = [System.IO.File]::ReadAllBytes($csvPath)
            $bom = [byte[]](0xEF, 0xBB, 0xBF)
            if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
                [System.IO.File]::WriteAllBytes($csvPath, ($bom + $bytes))
            }
        }

        Write-Verbose "Export CSV : $csvPath ($($records.Count) ligne(s))"
        return (Get-Item -LiteralPath $csvPath)
    }

    # Excel via COM
    $xlsxPath = if ($resolvedPath -like '*.xlsx') { $resolvedPath } else { "$resolvedPath.xlsx" }
    try {
        $excel = New-Object -ComObject Excel.Application
    }
    catch {
        Write-Warning "Excel COM indisponible ($($_.Exception.Message)). Export CSV de secours."
        $fallback = [System.IO.Path]::ChangeExtension($xlsxPath, 'csv')
        return (Export-FinalAssignmentReport -FinalAssignments $FinalAssignments -OutputPath $fallback -Format Csv -IncludeConcurrentSummary:$includeSummary -UseTechnicalHeaders:$tech)
    }

    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $wb = $excel.Workbooks.Add()
    $ws = $wb.Worksheets.Item(1)
    $ws.Name = 'Affectations'

    if ($records.Count -eq 0) {
        $headers = @('Commande', 'Reference_ligne_planification', 'Score_final', 'Motif_selection', 'Conflit_regle', 'Synthese_concurrents')
        if ($tech) {
            $headers = @('WorkOrder', 'ExcelRowId', 'FinalScore', 'DecisionReason', 'ConflictResolved', 'ConcurrentSummary')
        }
        if (-not $includeSummary) {
            $headers = $headers | Where-Object { $_ -notin @('Synthese_concurrents', 'ConcurrentSummary') }
        }
        $col = 1
        foreach ($h in $headers) {
            $ws.Cells.Item(1, $col) = $h
            $col++
        }
    }
    else {
        $props = @($records[0].PSObject.Properties.Name)
        $col = 1
        foreach ($h in $props) {
            $ws.Cells.Item(1, $col) = $h
            $col++
        }
        $rowIdx = 2
        foreach ($r in $records) {
            $col = 1
            foreach ($h in $props) {
                $ws.Cells.Item($rowIdx, $col) = [string]$r.$h
                $col++
            }
            $rowIdx++
        }
    }

    $xlOpenXMLWorkbook = 51
    if (Test-Path -LiteralPath $xlsxPath) {
        Remove-Item -LiteralPath $xlsxPath -Force
    }
    $wb.SaveAs($xlsxPath, $xlOpenXMLWorkbook)
    $wb.Close($false)
    $excel.Quit()

    [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($ws)
    [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($wb)
    [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($excel)
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()

    Write-Verbose "Export Excel : $xlsxPath ($($records.Count) ligne(s))"
    return (Get-Item -LiteralPath $xlsxPath)
}

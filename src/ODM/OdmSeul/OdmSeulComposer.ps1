# OdmSeulComposer.ps1 — Orchestrateur génération ODM Seul (étape 3)
# Réutilise les générateurs / fusion existants sans les modifier.
# Ordre fixe : CEA → Entête → Bilan → Certificat → DAC → FT → ODM source.

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

# Ancrage dossier (même logique que le panel)
if ([string]::IsNullOrWhiteSpace([string]$script:OdmSeulPanelDir)) {
    $script:OdmSeulPanelDir = $PSScriptRoot
}

function Ensure-OdmSeulGenerationDependencies {
    <#
    .SYNOPSIS
        Charge extracteurs, détection métier, prérequis STEP5, cover composer (templates Excel + merge).
    #>
    if (-not (Get-Command Import-OdmSeulPs1ToScriptScope -ErrorAction SilentlyContinue)) {
        throw 'Import-OdmSeulPs1ToScriptScope introuvable — charger OdmSeulPanel.ps1 avant le composer.'
    }
    if (-not (Get-Command Ensure-OdmSeulPdfPipelineLoaded -ErrorAction SilentlyContinue)) {
        throw 'Ensure-OdmSeulPdfPipelineLoaded introuvable.'
    }
    if (-not (Ensure-OdmSeulPdfPipelineLoaded)) {
        throw 'Pipeline PDF / détection métier introuvable.'
    }

    $services = [System.IO.Path]::GetFullPath((Join-Path $script:OdmSeulPanelDir '..\PdfPlanningOptimizer\Services'))
    $prereq = Join-Path $services 'PlanningStep5Prerequisites.ps1'
    $cover = Join-Path $services 'PdfTourneeCoverComposer.ps1'

    if (-not (Get-Command Test-PlanningStep5Environment -ErrorAction SilentlyContinue)) {
        if (-not (Import-OdmSeulPs1ToScriptScope -LiteralPath $prereq)) {
            throw ("Impossible de charger PlanningStep5Prerequisites.ps1 : {0}" -f $prereq)
        }
    }
    if (-not (Get-Command New-CnsTourneeHeaderCoverPdf -ErrorAction SilentlyContinue) -or
        -not (Get-Command Merge-CnsPdfFilesForStep5TourneeComposition -ErrorAction SilentlyContinue) -or
        -not (Get-Command New-CnsCeaPointsDeCollectesPdfFromExcelTemplate -ErrorAction SilentlyContinue)) {
        if (-not (Import-OdmSeulPs1ToScriptScope -LiteralPath $cover)) {
            throw ("Impossible de charger PdfTourneeCoverComposer.ps1 : {0}" -f $cover)
        }
    }

    $missing = @()
    foreach ($n in @(
            'Test-PlanningStep5Environment',
            'New-CnsTourneeHeaderCoverPdf',
            'Merge-CnsPdfFilesForStep5TourneeComposition',
            'New-CnsCeaPointsDeCollectesPdfFromExcelTemplate',
            'New-CnsBilanCollectePdfFromExcelTemplate',
            'New-CnsDestructionCertificatePdfFromExcelTemplate',
            'New-CnsDacPdfFromExcelTemplate',
            'New-CnsFtPdfFromExcelTemplate'
        )) {
        if (-not (Get-Command $n -ErrorAction SilentlyContinue)) { $missing += $n }
    }
    if ($missing.Count -gt 0) {
        throw ("Fonctions génération manquantes : {0}" -f ($missing -join ', '))
    }
    return $true
}

function Get-OdmSeulWorkContextFromPdf {
    <#
    .SYNOPSIS
        Extraction légère PDF → PageEntity / WorkOrder / VisitDate / lignes brutes.
    #>
    param([Parameter(Mandatory = $true)][string]$OdmPdfPath)

    $pdfData = Invoke-PdfExtraction -PdfPath $OdmPdfPath
    if ($null -eq $pdfData -or $null -eq $pdfData.Pages -or @($pdfData.Pages).Count -lt 1) {
        throw 'Extraction PDF : aucune page.'
    }
    if ($pdfData.PdfTextUnusable -and $pdfData.UserAbortMessage) {
        throw [string]$pdfData.UserAbortMessage
    }

    $page = @($pdfData.Pages)[0]
    $pn = 1
    try { $pn = [int]$page.PageNumber } catch { $pn = 1 }

    $cnLines = @()
    if ($null -ne $page.PSObject.Properties['ClientNameLines'] -and $null -ne $page.ClientNameLines) {
        $cnLines = @($page.ClientNameLines)
    }
    $pageEntity = ConvertTo-PageEntity -PageNumber $pn -Lines @($page.Lines) -ClientNameLines $cnLines
    if ($null -eq $pageEntity) {
        throw 'ConvertTo-PageEntity a retourné $null.'
    }

    $wo = $null
    if (Get-Command Resolve-CnsWorkOrderEntityFromPdfPage -ErrorAction SilentlyContinue) {
        $wo = Resolve-CnsWorkOrderEntityFromPdfPage -RawPageNumOneBased $pn -WorkOrders @() -PdfEntities @($pageEntity)
    }
    if ($null -eq $wo) {
        $wo = $pageEntity
    }

    $visitDate = $null
    try {
        if ($null -ne $pageEntity.VisitDate) { $visitDate = [datetime]$pageEntity.VisitDate }
    }
    catch { }
    if ($null -eq $visitDate) {
        $visitDate = [datetime]::Today
    }

    $rawLines = @()
    if ($null -ne $page.PSObject.Properties['RawLines'] -and $null -ne $page.RawLines) {
        $rawLines = @($page.RawLines)
    }
    elseif ($null -ne $page.PSObject.Properties['Lines'] -and $null -ne $page.Lines) {
        $rawLines = @($page.Lines)
    }

    $odmNum = ''
    try { $odmNum = [string]$wo.WorkOrder } catch { }
    if ([string]::IsNullOrWhiteSpace($odmNum)) {
        foreach ($svc in @($wo.Services)) {
            if ($null -eq $svc) { continue }
            try {
                $od = [string]$svc.ODM
                if (-not [string]::IsNullOrWhiteSpace($od)) { $odmNum = $od.Trim(); break }
            }
            catch { }
        }
    }

    return [pscustomobject]@{
        PageEntity    = $pageEntity
        WorkOrder     = $wo
        VisitDate     = $visitDate
        RawLines      = $rawLines
        OdmNumero     = $odmNum
        PageNumber    = $pn
    }
}

function Get-OdmSeulCoverMemoLines {
    param(
        $PageEntity,
        $WorkOrderEntity,
        [bool]$IncludeDac = $false
    )
    $out = New-Object System.Collections.Generic.List[string]
    if (-not (Get-Command Get-CnsPdfPageMetierAnalysis -ErrorAction SilentlyContinue)) {
        return @($out)
    }
    $analysis = Get-CnsPdfPageMetierAnalysis -PageEntity $PageEntity -WorkOrderEntity $WorkOrderEntity
    $client = ''
    try {
        if (-not [string]::IsNullOrWhiteSpace([string]$analysis.DestructionMemoClient)) {
            $client = [string]$analysis.DestructionMemoClient
        }
    }
    catch { }
    if ([string]::IsNullOrWhiteSpace($client) -and $null -ne $WorkOrderEntity) {
        try { $client = [string]$WorkOrderEntity.ClientName } catch { }
    }
    if ([string]::IsNullOrWhiteSpace($client) -and $null -ne $PageEntity) {
        try { $client = [string]$PageEntity.ClientName } catch { }
    }
    if ([string]::IsNullOrWhiteSpace($client)) { $client = 'Non specifie' }

    $indent = '    '
    $hasBody = $false
    $body = New-Object System.Collections.Generic.List[string]

    foreach ($tr in @($analysis.TrackDechetEntries)) {
        if ($null -eq $tr) { continue }
        $det = [string]$tr.Detail
        if ([string]::IsNullOrWhiteSpace($det)) { continue }
        if (Get-Command Get-CnsCoverGardeTrackDechetCollecteFragment -ErrorAction SilentlyContinue) {
            try { $det = Get-CnsCoverGardeTrackDechetCollecteFragment -Detail $det } catch { }
        }
        if (-not [string]::IsNullOrWhiteSpace($det)) {
            [void]$body.Add(('{0}{1} => BSD' -f $indent, $det.Trim()))
            $hasBody = $true
        }
    }
    foreach ($pp in @($analysis.PonctuellePrestationEntries)) {
        if ($null -eq $pp) { continue }
        $det = [string]$pp.Detail
        if ([string]::IsNullOrWhiteSpace($det)) { continue }
        [void]$body.Add(('{0}{1}' -f $indent, $det.Trim()))
        $hasBody = $true
    }
    if ($analysis.RequiresDestructionCertificate) {
        [void]$body.Add(('{0}Certificat de destruction' -f $indent))
        $hasBody = $true
    }
    if (Get-Command Test-CnsFtCollectionPointLabelEligible -ErrorAction SilentlyContinue) {
        $ftLabel = $null
        if (Get-Command Get-CnsStep5FragSliceFtCollectionPointLabel -ErrorAction SilentlyContinue) {
            $peLines = @()
            if ($null -ne $PageEntity -and $null -ne $PageEntity.Lines) { $peLines = @($PageEntity.Lines) }
            $ftLabel = Get-CnsStep5FragSliceFtCollectionPointLabel `
                -FragSlicePdfPath $null -PdfRawLines $peLines -RawPageNumOneBased 1 `
                -PageEntity $PageEntity -WorkOrderEntity $WorkOrderEntity
        }
        if (Test-CnsFtCollectionPointLabelEligible -Label $ftLabel) {
            [void]$body.Add(('{0}Faire inventaire' -f $indent))
            $hasBody = $true
            if ([string]::IsNullOrWhiteSpace($client) -or $client -eq 'Non specifie') {
                $client = [string]$ftLabel
            }
        }
    }
    if ($IncludeDac -and (Get-Command Get-CnsDacBioCoverInstructionText -ErrorAction SilentlyContinue)) {
        [void]$body.Add(('{0}{1}' -f $indent, (Get-CnsDacBioCoverInstructionText)))
        $hasBody = $true
    }

    if ($hasBody) {
        [void]$out.Add($client.Trim())
        foreach ($b in $body) { [void]$out.Add($b) }
    }
    return @($out)
}

function Merge-OdmSeulPdfFilesOrdered {
    <#
    .SYNOPSIS
        Wrapper local autour de Merge-CnsPdfFilesForStep5TourneeComposition.
    #>
    param(
        [Parameter(Mandatory = $true)][string[]]$InputPdfsOrdered,
        [Parameter(Mandatory = $true)][string]$DestinationPdfPath
    )
    $ok = Merge-CnsPdfFilesForStep5TourneeComposition -InputPdfsOrdered @($InputPdfsOrdered) -DestinationPdfPath $DestinationPdfPath
    if (-not $ok -or -not (Test-Path -LiteralPath $DestinationPdfPath -PathType Leaf)) {
        throw ("Fusion PDF échouée vers : {0}" -f $DestinationPdfPath)
    }
    return $DestinationPdfPath
}

function Get-OdmSeulDownloadsDirectory {
    $candidates = @(
        (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'),
        (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Téléchargements'),
        [Environment]::GetFolderPath('MyDocuments')
    )
    foreach ($c in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path -LiteralPath $c -PathType Container)) {
            return $c
        }
    }
    $fallback = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
    if (-not (Test-Path -LiteralPath $fallback)) {
        $null = New-Item -ItemType Directory -Path $fallback -Force
    }
    return $fallback
}

function Get-OdmSeulDacQuantityFromLines {
    <#
    .SYNOPSIS
        Même logique STEP5 (PdfTourneeCoverComposer) : Get-CnsBioDechetsTheoreticalQuantityFromLines
        + exclusion CEA SLE ; si non exclu et qty &lt; 1 → 1.
        Si exclu → 0 (l'appelant decide : case cochee DAC → forcer 1 pour ne pas bloquer).
    #>
    param([AllowEmptyCollection()][string[]]$RawLines = @())
    $bioExcluded = $false
    if (Get-Command Test-CnsBioDechetsDacExcludedFromLines -ErrorAction SilentlyContinue) {
        $bioExcluded = [bool](Test-CnsBioDechetsDacExcludedFromLines -Lines @($RawLines))
    }
    if ($bioExcluded) { return 0 }

    $bioQty = 0
    if (Get-Command Get-CnsBioDechetsTheoreticalQuantityFromLines -ErrorAction SilentlyContinue) {
        try { $bioQty = [int](Get-CnsBioDechetsTheoreticalQuantityFromLines -Lines @($RawLines)) } catch { $bioQty = 0 }
    }
    if ($bioQty -lt 1) { $bioQty = 1 }
    return $bioQty
}

function Get-OdmSeulSafeMetaString {
    <#
    .SYNOPSIS
        Jamais $null pour les générateurs de garde / Excel — chaîne vide si absent.
    #>
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return '' }
    try {
        return ([string]$Value).Trim()
    }
    catch {
        return ''
    }
}

function New-OdmSeulCoverVehicleDayPairing {
    <#
    .SYNOPSIS
        Disposition garde ODM Seul (meme structure que STEP5 VehicleDayPairing) :
        droite = « Prenom | Début HH » / Camion / plaque / « Après-midi : Libre ».
        Ne modifie pas PdfTourneeCoverComposer — objet consomme par -VehicleDayPairing.
    #>
    param(
        [AllowNull()][AllowEmptyString()][string]$Collecteur = '',
        [AllowNull()][AllowEmptyString()][string]$VehiculeNumeroParc = '',
        [AllowNull()][AllowEmptyString()][string]$VehiculeImmatriculation = '',
        [AllowNull()][AllowEmptyString()][string]$HeurePriseService = ''
    )

    $prenom = ''
    if (Get-Command Get-CnsTourneeCoverCollecteurPrenomDisplay -ErrorAction SilentlyContinue) {
        $prenom = Get-CnsTourneeCoverCollecteurPrenomDisplay -Collecteur $Collecteur
    }
    if ([string]::IsNullOrWhiteSpace($prenom) -and -not [string]::IsNullOrWhiteSpace($Collecteur)) {
        $parts = @(($Collecteur.Trim() -split '\s+') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($parts.Count -ge 1) { $prenom = [string]$parts[0] }
    }

    $debutHour = $null
    $debutMinute = 0
    if (-not [string]::IsNullOrWhiteSpace($HeurePriseService)) {
        $hText = $HeurePriseService.Trim()
        if ($hText -match '^(\d{1,2})\s*[:hH]\s*(\d{1,2})?') {
            $debutHour = [int]$Matches[1]
            if ($Matches[2]) { $debutMinute = [int]$Matches[2] }
        }
        elseif ($hText -match '^(\d{1,2})$') {
            $debutHour = [int]$Matches[1]
        }
    }

    $titleLine = ''
    if (-not [string]::IsNullOrWhiteSpace($prenom) -and $null -ne $debutHour) {
        if ($debutMinute -gt 0) {
            $titleLine = ('{0} | Début {1}H{2}' -f $prenom, $debutHour, $debutMinute.ToString('00'))
        }
        else {
            $titleLine = ('{0} | Début {1}H' -f $prenom, $debutHour)
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($prenom)) {
        $titleLine = $prenom
    }
    elseif ($null -ne $debutHour) {
        if ($debutMinute -gt 0) {
            $titleLine = ('Prise de service : {0}:{1}' -f $debutHour.ToString('00'), $debutMinute.ToString('00'))
        }
        else {
            $titleLine = ('Prise de service : {0}H' -f $debutHour)
        }
    }

    $parc = Get-OdmSeulSafeMetaString -Value $VehiculeNumeroParc
    $plaque = Get-OdmSeulSafeMetaString -Value $VehiculeImmatriculation
    if ($parc -match '(?i)^(NON\s+SPECIFIE|INCONNU|-)$') { $parc = '' }
    if ($plaque -match '(?i)^(NON\s+SPECIFIE|INCONNU|-)$') { $plaque = '' }
    # Si le « parc » ressemble a une plaque, basculer.
    if ([string]::IsNullOrWhiteSpace($plaque) -and $parc -match '(?i)[A-Z]{1,3}-?\d{2,4}-?[A-Z]{1,3}') {
        $plaque = $parc
        $parc = ''
    }

    $camionLine = ''
    if (-not [string]::IsNullOrWhiteSpace($parc)) {
        if ($parc -match '^(?i)camion\b') { $camionLine = $parc }
        else { $camionLine = ('Camion {0}' -f $parc) }
    }

    $serviceDetailLine = 'Après-midi : Libre'

    return [pscustomobject]@{
        Perspective           = 'Matin'
        MorningCollecteur     = $Collecteur
        AfternoonCollecteur   = ''
        MorningDebutHour      = $debutHour
        AfternoonDebutHour    = $null
        MorningIsFree         = [string]::IsNullOrWhiteSpace($prenom)
        AfternoonIsFree       = $true
        Plaque                = $plaque
        NumeroParc            = $parc
        TitleLine             = $titleLine
        SubtitleLine          = $serviceDetailLine
        ServiceDetailLine     = $serviceDetailLine
        SubtitleIsFree        = $true
        CamionLine            = $camionLine
    }
}

function Invoke-OdmSeulProgress {
    <#
    .SYNOPSIS
        Callback UI sécurisé : @{ Percent = 0..100; Message = '...' }. Try/catch silencieux.
    #>
    param(
        [AllowNull()][scriptblock]$Callback = $null,
        [int]$Percent = 0,
        [AllowNull()][AllowEmptyString()][string]$Message = ''
    )
    if ($null -eq $Callback) { return }
    $pct = [Math]::Min(100, [Math]::Max(0, $Percent))
    try {
        & $Callback @{
            Percent = $pct
            Message = $Message
        }
    }
    catch { }
}

function Get-OdmSeulWorkStepPercent {
    <#
    .SYNOPSIS
        Répartit 15..85 selon l'index d'étape métier active (0-based).
    #>
    param(
        [int]$StepIndex = 0,
        [int]$StepCount = 1
    )
    if ($StepCount -lt 1) { return 50 }
    $idx = [Math]::Max(0, $StepIndex)
    $pct = [int][Math]::Round(15.0 + ($idx * 70.0 / $StepCount))
    return [Math]::Min(85, [Math]::Max(15, $pct))
}

function Invoke-OdmSeulGeneration {
    <#
    .SYNOPSIS
        Génère un PDF unique selon l'ordre métier ODM Seul, enregistré dans Téléchargements.
    .NOTES
        Ordre :
          Entête?
          → DAC(s)?
          → FT? (uniquement si FT est la seule fiche métier, avant ODM)
          → ODM source
          → CEA?
          → Certificat?
          → FT? (si combiné avec d'autres prestations, après ODM)
          → Bilan?
        -OnProgress : scriptblock recevant @{ Percent; Message } (thread UI + DoEvents côté Panel).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$OdmPdfPath,
        [Parameter(Mandatory = $true)]$Options,
        [Parameter(Mandatory = $true)]$SegmentMeta,
        [AllowNull()][scriptblock]$OnProgress = $null
    )

    $result = [pscustomobject]@{
        Ok           = $false
        OutputPath   = $null
        ErrorMessage = $null
    }

    $tmpDir = $null
    $frag = New-Object System.Collections.Generic.List[string]

    try {
        if ([string]::IsNullOrWhiteSpace($OdmPdfPath) -or -not (Test-Path -LiteralPath $OdmPdfPath -PathType Leaf)) {
            throw ("PDF ODM introuvable : {0}" -f $OdmPdfPath)
        }

        $optCea = [bool]$Options.Cea
        $optCert = [bool]$Options.Certificat
        $optDac = [bool]$Options.Dac
        $optFt = [bool]$Options.Ft
        $optEntete = [bool]$Options.Entete
        $optBilan = [bool]$Options.Bilan
        if (-not ($optCea -or $optCert -or $optDac -or $optFt -or $optEntete -or $optBilan)) {
            throw 'Aucune fiche / option cochée.'
        }

        # Étapes métier actives (pour % dynamique 15..85)
        $workStepCount = 0
        if ($optEntete) { $workStepCount++ }
        if ($optDac) { $workStepCount++ }
        if ($optCea) { $workStepCount++ }
        if ($optCert) { $workStepCount++ }
        if ($optFt) { $workStepCount++ }
        if ($optBilan) { $workStepCount++ }
        $workStepIndex = 0

        Invoke-OdmSeulProgress -Callback $OnProgress -Percent 0 -Message 'Vérification des prérequis...'
        Ensure-OdmSeulGenerationDependencies

        $envCheck = Test-PlanningStep5Environment
        if (-not $envCheck.Ok) {
            $issues = @($envCheck.Issues) -join ' | '
            throw ("Prérequis STEP5 non satisfaits : {0}" -f $issues)
        }

        Invoke-OdmSeulProgress -Callback $OnProgress -Percent 10 -Message 'Lecture ODM...'
        $ctx = Get-OdmSeulWorkContextFromPdf -OdmPdfPath $OdmPdfPath
        $visitDate = [datetime]$ctx.VisitDate
        $wo = $ctx.WorkOrder
        $pe = $ctx.PageEntity
        $rawLines = @($ctx.RawLines)

        $seg = $SegmentMeta
        if ($null -eq $seg) { throw 'SegmentMeta requis.' }

        # Jamais $null sur les champs texte (évite crash New-CnsTourneeHeaderCoverPdf / Excel).
        foreach ($propName in @(
                'Collecteur', 'CollecteurPrenom', 'CollecteurNom',
                'Vehicule', 'VehiculeNumeroParc', 'VehiculeImmatriculation', 'NumeroParc', 'Plaque',
                'HeurePriseService', 'ODMNumero', 'ServiceLabel'
            )) {
            $cur = $null
            try {
                if ($null -ne $seg.PSObject.Properties[$propName]) { $cur = $seg.$propName }
            }
            catch { $cur = $null }
            $safe = Get-OdmSeulSafeMetaString -Value $cur
            try { $seg | Add-Member -NotePropertyName $propName -NotePropertyValue $safe -Force } catch { }
        }

        if ([string]::IsNullOrWhiteSpace([string]$seg.ODMNumero) -and -not [string]::IsNullOrWhiteSpace([string]$ctx.OdmNumero)) {
            try { $seg | Add-Member -NotePropertyName ODMNumero -NotePropertyValue $ctx.OdmNumero -Force } catch { }
        }
        if ([string]::IsNullOrWhiteSpace([string]$seg.Collecteur)) {
            $prenom = Get-OdmSeulSafeMetaString -Value $seg.CollecteurPrenom
            $nom = Get-OdmSeulSafeMetaString -Value $seg.CollecteurNom
            $joined = ('{0} {1}' -f $prenom, $nom).Trim()
            try { $seg | Add-Member -NotePropertyName Collecteur -NotePropertyValue $joined -Force } catch { }
        }
        if ([string]::IsNullOrWhiteSpace([string]$seg.Vehicule)) {
            $parc = Get-OdmSeulSafeMetaString -Value $seg.VehiculeNumeroParc
            if ([string]::IsNullOrWhiteSpace($parc)) { $parc = Get-OdmSeulSafeMetaString -Value $seg.NumeroParc }
            $immat = Get-OdmSeulSafeMetaString -Value $seg.VehiculeImmatriculation
            if ([string]::IsNullOrWhiteSpace($immat)) { $immat = Get-OdmSeulSafeMetaString -Value $seg.Plaque }
            $veh = if (-not [string]::IsNullOrWhiteSpace($immat)) { $immat } elseif (-not [string]::IsNullOrWhiteSpace($parc)) { $parc } else { '' }
            try { $seg | Add-Member -NotePropertyName Vehicule -NotePropertyValue $veh -Force } catch { }
        }

        $tmpDir = Join-Path $env:TEMP ('odm_seul_' + [Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $tmpDir -Force

        # --- Générateurs unitaires (chemins temporaires) ---
        $pathEntete = $null
        $pathCea = $null
        $pathCert = $null
        $pathFt = $null
        $pathBilan = $null
        $pathsDac = @()

        if ($optEntete) {
            Invoke-OdmSeulProgress -Callback $OnProgress `
                -Percent (Get-OdmSeulWorkStepPercent -StepIndex $workStepIndex -StepCount $workStepCount) `
                -Message 'Génération page de garde...'
            $workStepIndex++
            $coverOut = Join-Path $tmpDir 'entete.pdf'
            $jj = $visitDate.ToString('dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
            # Chaînes vides OK : New-CnsTourneeHeaderCoverPdf substitue INCONNU / NON SPECIFIE ;
            # la disposition visuelle passe par VehicleDayPairing (pas de CenteredText qui écrase les mémos).
            $collecteur = Get-OdmSeulSafeMetaString -Value $seg.Collecteur
            $vehiculeParc = Get-OdmSeulSafeMetaString -Value $seg.VehiculeNumeroParc
            if ([string]::IsNullOrWhiteSpace($vehiculeParc)) {
                $vehiculeParc = Get-OdmSeulSafeMetaString -Value $seg.NumeroParc
            }
            $vehiculeImmat = Get-OdmSeulSafeMetaString -Value $seg.VehiculeImmatriculation
            if ([string]::IsNullOrWhiteSpace($vehiculeImmat)) {
                $vehiculeImmat = Get-OdmSeulSafeMetaString -Value $seg.Plaque
            }
            $heure = Get-OdmSeulSafeMetaString -Value $seg.HeurePriseService
            $memos = @(Get-OdmSeulCoverMemoLines -PageEntity $pe -WorkOrderEntity $wo -IncludeDac:$optDac)
            $pairing = New-OdmSeulCoverVehicleDayPairing `
                -Collecteur $collecteur `
                -VehiculeNumeroParc $vehiculeParc `
                -VehiculeImmatriculation $vehiculeImmat `
                -HeurePriseService $heure
            # Jamais $null / jamais chaîne vide brute (Mandatory [string] côté générateur).
            $coverCollecteur = if ([string]::IsNullOrWhiteSpace($collecteur)) { 'INCONNU' } else { $collecteur }
            $coverVehicule = if ([string]::IsNullOrWhiteSpace($vehiculeParc)) { 'NON SPECIFIE' } else { $vehiculeParc }
            $okCover = New-CnsTourneeHeaderCoverPdf -OutPdfPath $coverOut -DateJJMMAAAA $jj `
                -Collecteur $coverCollecteur -Vehicule $coverVehicule -VehiculeImmatriculation $vehiculeImmat `
                -TourneeIncomplete:$false -MetierMemoLines $memos -CenteredText $null `
                -VehicleDayPairing $pairing
            if (-not $okCover -or -not (Test-Path -LiteralPath $coverOut)) {
                throw 'Échec génération page de garde (entête).'
            }
            $pathEntete = $coverOut
        }

        if ($optDac) {
            Invoke-OdmSeulProgress -Callback $OnProgress `
                -Percent (Get-OdmSeulWorkStepPercent -StepIndex $workStepIndex -StepCount $workStepCount) `
                -Message 'Génération DAC...'
            $workStepIndex++
            $dacVisit = $visitDate
            try {
                if ($null -ne $seg.DateDepotDac) { $dacVisit = [datetime]$seg.DateDepotDac }
            }
            catch { }
            # STEP5 qty ; si 0 (exclusion ou détection vide) mais case DAC cochée → forcer 1 (ne pas bloquer).
            $qty = Get-OdmSeulDacQuantityFromLines -RawLines $rawLines
            if ($qty -lt 1) { $qty = 1 }
            $dacDir = Join-Path $tmpDir 'dac'
            $null = New-Item -ItemType Directory -Path $dacDir -Force
            $dacPdfs = @(New-CnsDacPdfFromExcelTemplate `
                    -WorkOrderEntity $wo `
                    -TheoreticalQuantity $qty `
                    -ExcelData $null `
                    -VisitDate $dacVisit `
                    -OutDirectory $dacDir `
                    -SegmentMeta $seg `
                    -PageEntity $pe)
            if ($dacPdfs.Count -lt 1) {
                throw 'Échec génération DAC (aucun PDF produit).'
            }
            foreach ($d in $dacPdfs) {
                if (-not (Test-Path -LiteralPath $d)) {
                    throw ("Échec génération DAC — fichier manquant : {0}" -f $d)
                }
            }
            $pathsDac = @($dacPdfs)
        }

        if ($optCea) {
            Invoke-OdmSeulProgress -Callback $OnProgress `
                -Percent (Get-OdmSeulWorkStepPercent -StepIndex $workStepIndex -StepCount $workStepCount) `
                -Message 'Génération CEA...'
            $workStepIndex++
            $ceaOut = Join-Path $tmpDir 'cea.pdf'
            $phCea = @{}
            foreach ($entry in (Get-CnsCeaPointsDeCollectePlaceholders -WorkOrderEntity $wo -PageEntity $pe -SegmentMeta $seg -VisitDate $visitDate -FragSlicePdfPath $OdmPdfPath).GetEnumerator()) {
                $phCea[[string]$entry.Key] = [string]$entry.Value
            }
            $ceaPdf = New-CnsCeaPointsDeCollectesPdfFromExcelTemplate -OutPdfPath $ceaOut -Placeholders $phCea
            if ([string]::IsNullOrWhiteSpace($ceaPdf) -or -not (Test-Path -LiteralPath $ceaPdf)) {
                throw 'Échec génération CEA Points de Collecte.'
            }
            $pathCea = $ceaPdf
        }

        if ($optCert) {
            Invoke-OdmSeulProgress -Callback $OnProgress `
                -Percent (Get-OdmSeulWorkStepPercent -StepIndex $workStepIndex -StepCount $workStepCount) `
                -Message 'Génération Certificat...'
            $workStepIndex++
            $certOut = Join-Path $tmpDir 'certificat.pdf'
            $phCert = @{}
            foreach ($entry in (Get-CnsDestructionCertificatePlaceholders -WorkOrderEntity $wo -SegmentMeta $seg -VisitDate $visitDate).GetEnumerator()) {
                $phCert[[string]$entry.Key] = [string]$entry.Value
            }
            $certPdf = New-CnsDestructionCertificatePdfFromExcelTemplate -OutPdfPath $certOut -Placeholders $phCert
            if ([string]::IsNullOrWhiteSpace($certPdf) -or -not (Test-Path -LiteralPath $certPdf)) {
                throw 'Échec génération Certificat de destruction.'
            }
            $pathCert = $certPdf
        }

        if ($optFt) {
            Invoke-OdmSeulProgress -Callback $OnProgress `
                -Percent (Get-OdmSeulWorkStepPercent -StepIndex $workStepIndex -StepCount $workStepCount) `
                -Message 'Génération Fiche FT...'
            $workStepIndex++
            $ftOut = Join-Path $tmpDir 'ft.pdf'
            $pointLabel = ''
            if (Get-Command Get-CnsStep5FragSliceFtCollectionPointLabel -ErrorAction SilentlyContinue) {
                $pointLabel = Get-CnsStep5FragSliceFtCollectionPointLabel `
                    -FragSlicePdfPath $OdmPdfPath `
                    -PdfRawLines $rawLines `
                    -RawPageNumOneBased ([int]$ctx.PageNumber) `
                    -PageEntity $pe `
                    -WorkOrderEntity $wo
            }
            if ([string]::IsNullOrWhiteSpace($pointLabel) -and $null -ne $wo) {
                try { $pointLabel = [string]$wo.ClientName } catch { }
            }
            $phFt = @{}
            foreach ($entry in (Get-CnsFtPlaceholders -WorkOrderEntity $wo -PageEntity $pe -SegmentMeta $seg -VisitDate $visitDate -PointCollecte ([string]$pointLabel)).GetEnumerator()) {
                $phFt[[string]$entry.Key] = [string]$entry.Value
            }
            $ftPdf = New-CnsFtPdfFromExcelTemplate -OutPdfPath $ftOut -Placeholders $phFt
            if ([string]::IsNullOrWhiteSpace($ftPdf) -or -not (Test-Path -LiteralPath $ftPdf)) {
                throw 'Échec génération Fiche Inventaire France Travail.'
            }
            $pathFt = $ftPdf
        }

        if ($optBilan) {
            Invoke-OdmSeulProgress -Callback $OnProgress `
                -Percent (Get-OdmSeulWorkStepPercent -StepIndex $workStepIndex -StepCount $workStepCount) `
                -Message 'Génération Bilan...'
            $workStepIndex++
            $bilanOut = Join-Path $tmpDir 'bilan.pdf'
            $phBilan = @{}
            foreach ($entry in (Get-CnsBilanCollectePlaceholders -SegmentMeta $seg -VisitDate $visitDate).GetEnumerator()) {
                $phBilan[[string]$entry.Key] = [string]$entry.Value
            }
            $bilanPdf = New-CnsBilanCollectePdfFromExcelTemplate -OutPdfPath $bilanOut -Placeholders $phBilan
            if ([string]::IsNullOrWhiteSpace($bilanPdf) -or -not (Test-Path -LiteralPath $bilanPdf)) {
                throw 'Échec génération Bilan de collecte.'
            }
            $pathBilan = $bilanPdf
        }

        # --- Assemblage ordre métier ---
        # FT seul (sans CEA/Cert/DAC) → avant ODM ; sinon FT après ODM (cas combinés).
        $ftAloneBeforeOdm = $optFt -and -not $optCea -and -not $optCert -and -not $optDac

        if ($optEntete -and $pathEntete) { [void]$frag.Add($pathEntete) }
        foreach ($d in @($pathsDac)) { [void]$frag.Add($d) }
        if ($ftAloneBeforeOdm -and $pathFt) { [void]$frag.Add($pathFt) }

        [void]$frag.Add((Resolve-Path -LiteralPath $OdmPdfPath).Path)

        if ($optCea -and $pathCea) { [void]$frag.Add($pathCea) }
        if ($optCert -and $pathCert) { [void]$frag.Add($pathCert) }
        if ($optFt -and -not $ftAloneBeforeOdm -and $pathFt) { [void]$frag.Add($pathFt) }
        if ($optBilan -and $pathBilan) { [void]$frag.Add($pathBilan) }

        if ($frag.Count -lt 1) {
            throw 'Aucune page à fusionner.'
        }

        Invoke-OdmSeulProgress -Callback $OnProgress -Percent 90 -Message 'Assemblage des documents...'
        $downloads = Get-OdmSeulDownloadsDirectory
        $srcLeaf = [System.IO.Path]::GetFileNameWithoutExtension($OdmPdfPath)
        $stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
        $outName = ('ODM_{0}_{1}.pdf' -f $srcLeaf, $stamp)
        $outAbs = [System.IO.Path]::GetFullPath((Join-Path $downloads $outName))

        Merge-OdmSeulPdfFilesOrdered -InputPdfsOrdered @($frag.ToArray()) -DestinationPdfPath $outAbs

        Invoke-OdmSeulProgress -Callback $OnProgress -Percent 100 -Message 'Terminé.'
        $result.Ok = $true
        $result.OutputPath = $outAbs
        return $result
    }
    catch {
        $result.Ok = $false
        $result.ErrorMessage = $_.Exception.Message
        return $result
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace($tmpDir) -and (Test-Path -LiteralPath $tmpDir)) {
            try {
                Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            catch { }
        }
    }
}

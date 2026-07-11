# ExportImport.ps1 - Export/import des données pour supervision multi-sites

. (Join-Path $PSScriptRoot 'Database.ps1')
. (Join-Path $PSScriptRoot '..\Core\Logger.ps1')

$script:CenterExportVersion = '1.0'

function Initialize-CenterExportImportUi {
    if (-not ('System.Windows.Forms.MessageBox' -as [type])) {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    }
}

function Format-CenterExportAgentDate {
    param($Date)
    if ($null -eq $Date) { return $null }
    if ($Date -is [datetime]) { return $Date.ToString('o') }
    if ([string]::IsNullOrWhiteSpace([string]$Date)) { return $null }
    return [string]$Date
}

function Get-CenterImportSqlValue {
    param($Value)
    if ($null -eq $Value -or [System.DBNull]::Value.Equals($Value)) { return [DBNull]::Value }
    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) { return [DBNull]::Value }
    return $Value
}

function Export-CenterData {
    <#
    .SYNOPSIS
        Exporte les données du centre (agents, véhicules, configuration optionnelle) au format JSON.
    .OUTPUTS
        [string] Chemin du fichier exporté, ou $null en cas d'échec/annulation.
    #>
    param(
        [string]$DestinationPath,
        [switch]$IncludeAppConfig,
        [string]$SourceCenter = ''
    )

    if ([string]::IsNullOrWhiteSpace($DestinationPath)) {
        Initialize-CenterExportImportUi
        $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveDialog.Title = 'Exporter les données du centre'
        $saveDialog.Filter = 'Fichiers JSON (*.json)|*.json|Tous les fichiers (*.*)|*.*'
        $saveDialog.DefaultExt = 'json'
        $saveDialog.FileName = ('centre_export_{0}.json' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        if ($saveDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log '[Export] Export annulé par l utilisateur' 'INFO' @{}
            }
            return $null
        }
        $DestinationPath = $saveDialog.FileName
    }

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log '[Export] Début export' 'INFO' @{ destination = $DestinationPath }
    }

    try {
        $vehicules = @(Get-Vehicules -IncludeInactive)
        $agents = @(Get-Agents -IncludeInactive)

        $vehiculesClean = @($vehicules | ForEach-Object {
            [PSCustomObject]@{
                id                        = $_.id
                numero_parc               = $_.numero_parc
                immatriculation           = $_.immatriculation
                numero_chassis            = $_.numero_chassis
                marque                    = $_.marque
                modele                    = $_.modele
                date_mise_circulation     = $_.date_mise_circulation
                date_controle             = $_.date_controle
                date_entree               = $_.date_entree
                date_sortie               = $_.date_sortie
                date_fin_controle_technique = $_.date_fin_controle_technique
                capacite                  = $_.capacite
                conducteur_id             = $_.conducteur_id
                actif                     = $_.actif
            }
        })

        $agentsClean = @($agents | ForEach-Object {
            [PSCustomObject]@{
                id                  = $_.id
                nom                 = $_.nom
                prenom              = $_.prenom
                telephone           = $_.telephone
                email               = $_.email
                date_entree         = (Format-CenterExportAgentDate -Date $_.date_entree)
                date_sortie         = (Format-CenterExportAgentDate -Date $_.date_sortie)
                type_contrat        = $_.type_contrat
                base_heures_semaine = $_.base_heures_semaine
                vehicule_id         = $_.vehicule_id
                poste               = $_.poste
                actif               = $_.actif
            }
        })

        $appConfig = $null
        if ($IncludeAppConfig) {
            $sharePointUrl = Get-AppConfig -Key 'SharePointApiUrl'
            if (-not [string]::IsNullOrWhiteSpace($sharePointUrl)) {
                $appConfig = [PSCustomObject]@{
                    SharePointApiUrl = $sharePointUrl
                }
            }
        }

        $exportObj = [PSCustomObject]@{
            exportVersion = $script:CenterExportVersion
            exportedAt    = (Get-Date).ToString('o')
            sourceCenter  = $SourceCenter
            vehicules     = $vehiculesClean
            agents        = $agentsClean
            appConfig     = $appConfig
        }

        $json = $exportObj | ConvertTo-Json -Depth 6
        [System.IO.File]::WriteAllText($DestinationPath, $json, [System.Text.UTF8Encoding]::new($false))

        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[Export] Export réussi' 'INFO' @{
                vehicules = $vehicules.Count
                agents    = $agents.Count
            }
        }

        Initialize-CenterExportImportUi
        if (-not $PSBoundParameters.ContainsKey('DestinationPath')) {
            [System.Windows.Forms.MessageBox]::Show(
                ("Export réussi !`n`n{0} véhicules`n{1} agents`n`nFichier : {2}" -f $vehicules.Count, $agents.Count, $DestinationPath),
                'Export terminé',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }

        return $DestinationPath
    }
    catch {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[Export] Erreur' 'ERROR' @{ message = $_.Exception.Message }
        }
        if (-not $PSBoundParameters.ContainsKey('DestinationPath')) {
            Initialize-CenterExportImportUi
            [System.Windows.Forms.MessageBox]::Show(
                ("Erreur lors de l'export :`n`n{0}" -f $_.Exception.Message),
                'Erreur d''export',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
        return $null
    }
}

function Import-CenterData {
    <#
    .SYNOPSIS
        Importe des données depuis un fichier JSON exporté par Export-CenterData.
    .OUTPUTS
        [bool] True si l'import a réussi, False sinon.
    #>
    param(
        [string]$SourcePath,
        [switch]$DryRun
    )

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        Initialize-CenterExportImportUi
        $openDialog = New-Object System.Windows.Forms.OpenFileDialog
        $openDialog.Title = 'Importer les données du centre'
        $openDialog.Filter = 'Fichiers JSON (*.json)|*.json|Tous les fichiers (*.*)|*.*'
        if ($openDialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log '[Import] Import annulé par l utilisateur' 'INFO' @{}
            }
            return $false
        }
        $SourcePath = $openDialog.FileName
    }

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[Import] Fichier introuvable' 'ERROR' @{ path = $SourcePath }
        }
        Initialize-CenterExportImportUi
        [System.Windows.Forms.MessageBox]::Show(
            ("Fichier introuvable : {0}" -f $SourcePath),
            'Erreur',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return $false
    }

    if (-not $DryRun -and -not $PSBoundParameters.ContainsKey('SourcePath')) {
        Initialize-CenterExportImportUi
        $confirmResult = [System.Windows.Forms.MessageBox]::Show(
            "ATTENTION : Cette opération va MODIFIER les données existantes (agents, véhicules, configuration).`n`nSouhaitez-vous continuer ?",
            'Confirmation d''import',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirmResult -ne [System.Windows.Forms.DialogResult]::Yes) {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log '[Import] Import annulé par l utilisateur' 'INFO' @{}
            }
            return $false
        }
    }

    $dbPath = $script:DbPath
    $backupPath = $null
    if (-not $DryRun -and (Test-Path -LiteralPath $dbPath)) {
        $backupPath = Join-Path (Split-Path -Parent $dbPath) ('gestion.db.bak_{0}' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        Copy-Item -LiteralPath $dbPath -Destination $backupPath -Force
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[Import] Backup créé' 'INFO' @{ backup = $backupPath }
        }
    }

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log '[Import] Début import' 'INFO' @{ source = $SourcePath; dryRun = [bool]$DryRun }
    }

    try {
        $jsonContent = Get-Content -LiteralPath $SourcePath -Raw -Encoding UTF8
        $importData = $jsonContent | ConvertFrom-Json

        if ($null -eq $importData.exportVersion -or [string]$importData.exportVersion -ne $script:CenterExportVersion) {
            throw 'Format d''export incompatible (attendu version 1.0)'
        }

        $vehicules = @($importData.vehicules)
        $agents = @($importData.agents)
        if ($vehicules.Count -eq 0 -and $agents.Count -eq 0) {
            throw 'Structure JSON invalide : aucun véhicule ni agent'
        }

        if ($DryRun) {
            $conflicts = [System.Collections.Generic.List[string]]::new()
            foreach ($veh in $vehicules) {
                if (Test-VehiculeRecordExistsByColumn -ColumnName 'immatriculation' -Value ([string]$veh.immatriculation)) {
                    [void]$conflicts.Add(("Véhicule déjà existant (immat) : {0}" -f $veh.immatriculation))
                }
                if (Test-VehiculeRecordExistsByColumn -ColumnName 'numero_parc' -Value ([string]$veh.numero_parc)) {
                    [void]$conflicts.Add(("Numéro de parc déjà existant : {0}" -f $veh.numero_parc))
                }
            }
            if ($conflicts.Count -gt 0) {
                if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                    Write-Log '[Import] Conflits détectés (DryRun)' 'WARN' @{ count = $conflicts.Count }
                    foreach ($c in $conflicts) { Write-Log '[Import] Conflit' 'WARN' @{ detail = $c } }
                }
            }
            else {
                if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                    Write-Log '[Import] Aucun conflit détecté (DryRun)' 'INFO' @{}
                }
            }
            return $true
        }

        $conn = Open-Connection
        $trans = $null
        try {
            $trans = $conn.BeginTransaction()
            $oldToNewVehiculeId = @{}

            foreach ($veh in $vehicules) {
                $oldVehId = [int]$veh.id
                $cmdFind = $conn.CreateCommand()
                $cmdFind.Transaction = $trans
                $cmdFind.CommandText = 'SELECT id_vehicule FROM Vehicule WHERE immatriculation = @immat LIMIT 1'
                $null = $cmdFind.Parameters.AddWithValue('@immat', [string]$veh.immatriculation)
                $existingIdRaw = $cmdFind.ExecuteScalar()

                if ($null -ne $existingIdRaw -and -not [System.DBNull]::Value.Equals($existingIdRaw)) {
                    $existingId = [int]$existingIdRaw
                    $updateCmd = $conn.CreateCommand()
                    $updateCmd.Transaction = $trans
                    $updateCmd.CommandText = @"
UPDATE Vehicule SET
    numero_parc = @parc,
    numero_chassis = @chassis,
    marque = @marque,
    modele = @modele,
    date_mise_circulation = @date_mise,
    date_controle = @date_ctrl,
    date_entree = @date_entree,
    date_sortie = @date_sortie,
    date_fin_controle_technique = @date_fin,
    actif = @actif
WHERE id_vehicule = @id
"@
                    $null = $updateCmd.Parameters.AddWithValue('@id', $existingId)
                    $null = $updateCmd.Parameters.AddWithValue('@parc', [string]$veh.numero_parc)
                    $null = $updateCmd.Parameters.AddWithValue('@chassis', (Get-CenterImportSqlValue -Value $veh.numero_chassis))
                    $null = $updateCmd.Parameters.AddWithValue('@marque', (Get-CenterImportSqlValue -Value $veh.marque))
                    $null = $updateCmd.Parameters.AddWithValue('@modele', (Get-CenterImportSqlValue -Value $veh.modele))
                    $null = $updateCmd.Parameters.AddWithValue('@date_mise', (Get-CenterImportSqlValue -Value $veh.date_mise_circulation))
                    $null = $updateCmd.Parameters.AddWithValue('@date_ctrl', (Get-CenterImportSqlValue -Value $veh.date_controle))
                    $null = $updateCmd.Parameters.AddWithValue('@date_entree', (Get-CenterImportSqlValue -Value $veh.date_entree))
                    $null = $updateCmd.Parameters.AddWithValue('@date_sortie', (Get-CenterImportSqlValue -Value $veh.date_sortie))
                    $null = $updateCmd.Parameters.AddWithValue('@date_fin', (Get-CenterImportSqlValue -Value $veh.date_fin_controle_technique))
                    $null = $updateCmd.Parameters.AddWithValue('@actif', [int]$veh.actif)
                    $null = $updateCmd.ExecuteNonQuery()
                    $oldToNewVehiculeId[$oldVehId] = $existingId
                }
                else {
                    $insertCmd = $conn.CreateCommand()
                    $insertCmd.Transaction = $trans
                    $insertCmd.CommandText = @"
INSERT INTO Vehicule (
    numero_parc, immatriculation, numero_chassis, marque, modele,
    date_mise_circulation, date_controle, date_entree, date_sortie,
    date_fin_controle_technique, actif
) VALUES (
    @parc, @immat, @chassis, @marque, @modele,
    @date_mise, @date_ctrl, @date_entree, @date_sortie,
    @date_fin, @actif
)
"@
                    $null = $insertCmd.Parameters.AddWithValue('@parc', [string]$veh.numero_parc)
                    $null = $insertCmd.Parameters.AddWithValue('@immat', [string]$veh.immatriculation)
                    $null = $insertCmd.Parameters.AddWithValue('@chassis', (Get-CenterImportSqlValue -Value $veh.numero_chassis))
                    $null = $insertCmd.Parameters.AddWithValue('@marque', (Get-CenterImportSqlValue -Value $veh.marque))
                    $null = $insertCmd.Parameters.AddWithValue('@modele', (Get-CenterImportSqlValue -Value $veh.modele))
                    $null = $insertCmd.Parameters.AddWithValue('@date_mise', (Get-CenterImportSqlValue -Value $veh.date_mise_circulation))
                    $null = $insertCmd.Parameters.AddWithValue('@date_ctrl', (Get-CenterImportSqlValue -Value $veh.date_controle))
                    $null = $insertCmd.Parameters.AddWithValue('@date_entree', (Get-CenterImportSqlValue -Value $veh.date_entree))
                    $null = $insertCmd.Parameters.AddWithValue('@date_sortie', (Get-CenterImportSqlValue -Value $veh.date_sortie))
                    $null = $insertCmd.Parameters.AddWithValue('@date_fin', (Get-CenterImportSqlValue -Value $veh.date_fin_controle_technique))
                    $null = $insertCmd.Parameters.AddWithValue('@actif', [int]$veh.actif)
                    $null = $insertCmd.ExecuteNonQuery()
                    $newId = [int](Get-SqliteLastInsertRowId -Command $insertCmd)
                    $oldToNewVehiculeId[$oldVehId] = $newId
                }
            }

            foreach ($agent in $agents) {
                $newVehiculeId = [DBNull]::Value
                if ($null -ne $agent.vehicule_id -and -not [string]::IsNullOrWhiteSpace([string]$agent.vehicule_id)) {
                    $oldVid = [int]$agent.vehicule_id
                    if ($oldToNewVehiculeId.ContainsKey($oldVid)) {
                        $newVehiculeId = $oldToNewVehiculeId[$oldVid]
                    }
                }

                $deTs = ToDbDate $agent.date_entree
                $dsTs = ToDbDate $agent.date_sortie

                $checkCmd = $conn.CreateCommand()
                $checkCmd.Transaction = $trans
                $checkCmd.CommandText = @"
SELECT id_agent FROM Agent
WHERE (email IS NOT NULL AND TRIM(email) <> '' AND email = @email)
   OR (nom = @nom AND prenom = @prenom)
LIMIT 1
"@
                $null = $checkCmd.Parameters.AddWithValue('@email', (Get-CenterImportSqlValue -Value $agent.email))
                $null = $checkCmd.Parameters.AddWithValue('@nom', [string]$agent.nom)
                $null = $checkCmd.Parameters.AddWithValue('@prenom', [string]$agent.prenom)
                $existingAgentRaw = $checkCmd.ExecuteScalar()

                if ($null -ne $existingAgentRaw -and -not [System.DBNull]::Value.Equals($existingAgentRaw)) {
                    $existingAgentId = [int]$existingAgentRaw
                    $updateCmd = $conn.CreateCommand()
                    $updateCmd.Transaction = $trans
                    $updateCmd.CommandText = @"
UPDATE Agent SET
    nom = @nom,
    prenom = @prenom,
    telephone = @tel,
    email = @email,
    date_entree = @de,
    date_sortie = @ds,
    type_contrat = @tc,
    base_heures_semaine = @bh,
    vehicule_id = @vid,
    poste = @poste,
    actif = @actif
WHERE id_agent = @id
"@
                    $null = $updateCmd.Parameters.AddWithValue('@id', $existingAgentId)
                    $null = $updateCmd.Parameters.AddWithValue('@nom', [string]$agent.nom)
                    $null = $updateCmd.Parameters.AddWithValue('@prenom', [string]$agent.prenom)
                    $null = $updateCmd.Parameters.AddWithValue('@tel', (Get-CenterImportSqlValue -Value $agent.telephone))
                    $null = $updateCmd.Parameters.AddWithValue('@email', (Get-CenterImportSqlValue -Value $agent.email))
                    $null = $updateCmd.Parameters.AddWithValue('@de', (Get-CenterImportSqlValue -Value $deTs))
                    $null = $updateCmd.Parameters.AddWithValue('@ds', (Get-CenterImportSqlValue -Value $dsTs))
                    $null = $updateCmd.Parameters.AddWithValue('@tc', [string]$agent.type_contrat)
                    $null = $updateCmd.Parameters.AddWithValue('@bh', [int]$agent.base_heures_semaine)
                    $null = $updateCmd.Parameters.AddWithValue('@vid', $newVehiculeId)
                    $null = $updateCmd.Parameters.AddWithValue('@poste', [string]$agent.poste)
                    $null = $updateCmd.Parameters.AddWithValue('@actif', [int]$agent.actif)
                    $null = $updateCmd.ExecuteNonQuery()
                }
                else {
                    $insertCmd = $conn.CreateCommand()
                    $insertCmd.Transaction = $trans
                    $insertCmd.CommandText = @"
INSERT INTO Agent (
    nom, prenom, telephone, email, date_entree, date_sortie,
    type_contrat, base_heures_semaine, vehicule_id, poste, actif
) VALUES (
    @nom, @prenom, @tel, @email, @de, @ds,
    @tc, @bh, @vid, @poste, @actif
)
"@
                    $null = $insertCmd.Parameters.AddWithValue('@nom', [string]$agent.nom)
                    $null = $insertCmd.Parameters.AddWithValue('@prenom', [string]$agent.prenom)
                    $null = $insertCmd.Parameters.AddWithValue('@tel', (Get-CenterImportSqlValue -Value $agent.telephone))
                    $null = $insertCmd.Parameters.AddWithValue('@email', (Get-CenterImportSqlValue -Value $agent.email))
                    $null = $insertCmd.Parameters.AddWithValue('@de', (Get-CenterImportSqlValue -Value $deTs))
                    $null = $insertCmd.Parameters.AddWithValue('@ds', (Get-CenterImportSqlValue -Value $dsTs))
                    $null = $insertCmd.Parameters.AddWithValue('@tc', [string]$agent.type_contrat)
                    $null = $insertCmd.Parameters.AddWithValue('@bh', [int]$agent.base_heures_semaine)
                    $null = $insertCmd.Parameters.AddWithValue('@vid', $newVehiculeId)
                    $null = $insertCmd.Parameters.AddWithValue('@poste', [string]$agent.poste)
                    $null = $insertCmd.Parameters.AddWithValue('@actif', [int]$agent.actif)
                    $null = $insertCmd.ExecuteNonQuery()
                }
            }

            $trans.Commit()
            $trans = $null

            if ($null -ne $importData.appConfig -and -not [string]::IsNullOrWhiteSpace([string]$importData.appConfig.SharePointApiUrl)) {
                Set-AppConfig -Key 'SharePointApiUrl' -Value ([string]$importData.appConfig.SharePointApiUrl)
            }

            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log '[Import] Import réussi' 'INFO' @{
                    vehicules = $vehicules.Count
                    agents    = $agents.Count
                }
            }

            $backupMsg = if ($backupPath) { "`n`nUn backup a été créé : $backupPath" } else { '' }
            if (-not $PSBoundParameters.ContainsKey('SourcePath')) {
                Initialize-CenterExportImportUi
                [System.Windows.Forms.MessageBox]::Show(
                    ("Import réussi !`n`n{0} véhicules`n{1} agents{2}" -f $vehicules.Count, $agents.Count, $backupMsg),
                    'Import terminé',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
            }

            return $true
        }
        catch {
            if ($null -ne $trans) {
                try { $trans.Rollback() } catch { }
            }
            throw
        }
        finally {
            Close-Connection $conn
        }
    }
    catch {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log '[Import] Erreur' 'ERROR' @{ message = $_.Exception.Message }
        }
        $backupMsg = if ($backupPath) { "`n`nUn backup a été créé : $backupPath" } else { '' }
        if (-not $PSBoundParameters.ContainsKey('SourcePath')) {
            Initialize-CenterExportImportUi
            [System.Windows.Forms.MessageBox]::Show(
                ("Erreur lors de l'import :`n`n{0}{1}" -f $_.Exception.Message, $backupMsg),
                'Erreur d''import',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
        return $false
    }
}

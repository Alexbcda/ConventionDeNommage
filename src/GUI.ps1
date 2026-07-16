# GUI.ps1 - Version simplifiée

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Get-Command Write-AppHost -ErrorAction SilentlyContinue)) {
    $quiet = Join-Path $scriptDir 'Common\QuietConsole.ps1'
    if (Test-Path -LiteralPath $quiet) { . $quiet }
}
if (-not (Get-Command Convert-ToUiText -ErrorAction SilentlyContinue)) {
    . "$scriptDir\Common\TextEncoding.ps1"
    . "$scriptDir\Common\UiText.ps1"
}
. "$scriptDir\Common\Styles.ps1"
# Helpers CRUD WinForms au niveau script (survit au lazy load des onglets).
. (Join-Path $scriptDir 'Common\WinFormsHelpers.ps1')
# SharePoint : charge UNIQUEMENT en mode normal, dans Start-GUI (hors sous-fonction)
# pour rester visible dans la portee appelante (bug scope si . dans function Ensure-*).

# Classes PowerShell (PageEntity, etc.) : MUST etre chargees au scope SCRIPT.
# Un . Models\*.ps1 dans Import-AssistantLazyScriptsToScriptScope (fonction) les perd au return
# → ECHEC : Type [PageEntity] introuvable a l'edition planning.
function Import-AssistantPlanningModelTypes {
    if ($script:AssistantPlanningModelsLoaded) { return }
    $modelsDir = Join-Path $scriptDir 'ODM\PdfPlanningOptimizer\Models'
    if (-not (Test-Path -LiteralPath $modelsDir)) { return }
    # Ordre : MatchResult avant FinalAssignment (dependance de type).
    $ordered = @(
        'PageEntity.ps1',
        'WorkOrderEntity.ps1',
        'MatchResult.ps1',
        'FinalAssignment.ps1'
    )
    foreach ($name in $ordered) {
        $path = Join-Path $modelsDir $name
        if (Test-Path -LiteralPath $path) {
            . $path
        }
    }
    Get-ChildItem -LiteralPath $modelsDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
        Where-Object { $ordered -notcontains $_.Name } |
        ForEach-Object { . $_.FullName }
    $script:AssistantPlanningModelsLoaded = $true
}
# Dot-source de la fonction = corps execute au scope script (classes visibles session UI).
. Import-AssistantPlanningModelTypes

# Extractors planning (Normalize-PdfNoiseText, ConvertTo-PageEntity, ...) au scope SCRIPT.
# Preferer: `. Import-AssistantPlanningExtractorScripts` (Main / tests). Si appele via &,
# promotion explicite des fonctions vers script: (les classes Models restent via Import-AssistantPlanningModelTypes).
function Import-AssistantPlanningExtractorScripts {
    if ($script:AssistantPlanningExtractorsLoaded) { return }
    $extractorsDir = Join-Path $scriptDir 'ODM\PdfPlanningOptimizer\Extractors'
    if (-not (Test-Path -LiteralPath $extractorsDir)) { return }
    $loaded = New-Object System.Collections.Generic.List[string]
    foreach ($name in @(
            'PdfTextNormalizer.ps1',
            'PdfExtractor.ps1',
            'EntityExtractor.ps1',
            'ExcelLoader.ps1'
        )) {
        $path = Join-Path $extractorsDir $name
        if (Test-Path -LiteralPath $path) {
            . $path
            [void]$loaded.Add($path)
        }
    }
    $funcNames = Get-AssistantFunctionNamesFromPs1Files -LiteralPath @($loaded)
    foreach ($n in $funcNames) {
        if ([string]::IsNullOrWhiteSpace($n) -or $n -eq 'script') { continue }
        $cmd = Get-Command -Name $n -CommandType Function -ErrorAction SilentlyContinue
        if ($null -eq $cmd) { continue }
        try {
            Set-Item -Path ("function:script:{0}" -f $n) -Value $cmd.ScriptBlock -Force
        }
        catch { }
    }
    $script:AssistantPlanningExtractorsLoaded = $true
}

function Publish-AssistantCommandToScriptScope {
    param(
        [Parameter(Mandatory = $true)][string[]]$Name
    )
    foreach ($n in $Name) {
        if ([string]::IsNullOrWhiteSpace($n)) { continue }
        $cmd = Get-Command -Name $n -CommandType Function -ErrorAction SilentlyContinue
        if ($null -eq $cmd) { continue }
        Set-Item -Path ("function:script:{0}" -f $n) -Value $cmd.ScriptBlock -Force
    }
}

# Dot-source + promotion AUTO des fonctions des scripts charges (et de leur graphe . ps1).
# Snapshot Get-Command global evite (trop lent avec Microsoft.Graph) : on parse les fichiers charges.
function Get-AssistantPs1DotSourceClosure {
    param([Parameter(Mandatory = $true)][string[]]$EntryPath)
    $visited = @{}
    $queue = New-Object System.Collections.Generic.Queue[string]
    foreach ($e in $EntryPath) {
        if ([string]::IsNullOrWhiteSpace($e)) { continue }
        if (-not (Test-Path -LiteralPath $e)) { continue }
        $queue.Enqueue((Resolve-Path -LiteralPath $e).Path)
    }
    while ($queue.Count -gt 0) {
        $file = $queue.Dequeue()
        if ($visited.ContainsKey($file)) { continue }
        $visited[$file] = $true
        $dir = Split-Path -Parent $file
        foreach ($line in Get-Content -LiteralPath $file -ErrorAction SilentlyContinue) {
            $rel = $null
            # Patterns via [regex]::Escape pour matcher le texte source $PSScriptRoot (sans expansion).
            if ($line -match ('^\s*\.\s+"' + [regex]::Escape('$PSScriptRoot\') + '([^"]+)"')) {
                $rel = $Matches[1]
            }
            elseif ($line -match ("^\s*\.\s+'" + [regex]::Escape('$PSScriptRoot\') + "([^']+)'")) {
                $rel = $Matches[1]
            }
            elseif ($line -match ('Join-Path\s+' + [regex]::Escape('$PSScriptRoot') + "\s+'([^']+\.ps1)'")) {
                $rel = $Matches[1]
            }
            elseif ($line -match ('Join-Path\s+' + [regex]::Escape('$PSScriptRoot') + '\s+"([^"]+\.ps1)"')) {
                $rel = $Matches[1]
            }
            if ([string]::IsNullOrWhiteSpace($rel)) { continue }
            try {
                $cand = [System.IO.Path]::GetFullPath((Join-Path $dir $rel))
            }
            catch { continue }
            # Ne pas expanser la fermeture vers infra deja chargee au demarrage (bruit / cout).
            $leaf = [System.IO.Path]::GetFileName($cand)
            if ($leaf -in @('Database.ps1', 'Styles.ps1', 'Logger.ps1', 'QuietConsole.ps1', 'WinFormsHelpers.ps1', 'TextEncoding.ps1', 'UiText.ps1')) {
                continue
            }
            if ((Test-Path -LiteralPath $cand) -and -not $visited.ContainsKey($cand)) {
                $queue.Enqueue($cand)
            }
        }
    }
    return @($visited.Keys)
}

function Get-AssistantFunctionNamesFromPs1Files {
    param([Parameter(Mandatory = $true)][string[]]$LiteralPath)
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($p in $LiteralPath) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        foreach ($line in Get-Content -LiteralPath $p -ErrorAction SilentlyContinue) {
            if ($line -match '^\s*function\s+script:([\w-]+)') {
                [void]$names.Add($Matches[1])
            }
            elseif ($line -match '^\s*function\s+([\w-]+)') {
                [void]$names.Add($Matches[1])
            }
        }
    }
    return @($names | Select-Object -Unique)
}

function Import-AssistantLazyScriptsToScriptScope {
    param(
        [Parameter(Mandatory = $true)][string[]]$LiteralPath
    )
    $paths = @()
    foreach ($p in $LiteralPath) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (-not (Test-Path -LiteralPath $p)) {
            throw ("Fichier introuvable pour lazy load : {0}" -f $p)
        }
        $paths += (Resolve-Path -LiteralPath $p).Path
        . $p
    }

    # Aplatir la fermeture (eviter tableau imbrique si un return "," remonte encore).
    $closure = New-Object System.Collections.Generic.List[string]
    foreach ($item in @(Get-AssistantPs1DotSourceClosure -EntryPath $paths)) {
        if ($null -eq $item) { continue }
        if (($item -is [System.Collections.IEnumerable]) -and -not ($item -is [string])) {
            foreach ($inner in $item) {
                if ([string]::IsNullOrWhiteSpace([string]$inner)) { continue }
                $resolved = Resolve-Path -LiteralPath ([string]$inner) -ErrorAction SilentlyContinue
                if ($resolved) { [void]$closure.Add($resolved.Path) }
            }
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$item)) {
            $resolved = Resolve-Path -LiteralPath ([string]$item) -ErrorAction SilentlyContinue
            if ($resolved) { [void]$closure.Add($resolved.Path) }
        }
    }
    foreach ($p in $paths) {
        if (-not ($closure -contains $p)) { [void]$closure.Add($p) }
    }

    # Planning : inclure TOUT Extractors/ (PdfTextNormalizer charge via Resolve-* dynamique, hors parse statique).
    $isPlanning = $false
    foreach ($p in $paths) {
        if ($p -like '*PlanningRebuilderPanel*' -or $p -like '*PdfPlanningOptimizer*') {
            $isPlanning = $true
            break
        }
    }
    if ($isPlanning) {
        $optRoot = Join-Path $scriptDir 'ODM\PdfPlanningOptimizer'
        foreach ($sub in @('Extractors', 'Models', 'Services', 'Monitoring')) {
            $d = Join-Path $optRoot $sub
            if (-not (Test-Path -LiteralPath $d)) { continue }
            Get-ChildItem -LiteralPath $d -Filter '*.ps1' -File -ErrorAction SilentlyContinue | ForEach-Object {
                if (-not ($closure -contains $_.FullName)) {
                    [void]$closure.Add($_.FullName)
                }
            }
        }
    }

    $funcNames = Get-AssistantFunctionNamesFromPs1Files -LiteralPath @($closure)
    $promoted = New-Object System.Collections.Generic.List[string]
    foreach ($n in $funcNames) {
        if ([string]::IsNullOrWhiteSpace($n)) { continue }
        if ($n -eq 'script') { continue }
        $cmd = Get-Command -Name $n -CommandType Function -ErrorAction SilentlyContinue
        if ($null -eq $cmd) { continue }
        try {
            Set-Item -Path ("function:script:{0}" -f $n) -Value $cmd.ScriptBlock -Force
            [void]$promoted.Add($n)
        }
        catch { }
    }
    return @($promoted)
}

function Write-AssistantRenameOnlyGuiLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    $line = "[RenameOnly] $Message"
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log $line 'INFO'
    }
    if (Get-Command Write-AppHost -ErrorAction SilentlyContinue) {
        Write-AppHost $line -ForegroundColor Cyan
    }
}

function Write-AssistantNormalGuiLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    $line = "[Normal] $Message"
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log $line 'INFO'
    }
    if (Get-Command Write-AppHost -ErrorAction SilentlyContinue) {
        Write-AppHost $line -ForegroundColor DarkGreen
    }
}

function Ensure-WinFormsInitialized {
    if (-not (Get-Command Initialize-ApplicationWinForms -ErrorAction SilentlyContinue)) {
        $_boot = Join-Path $PSScriptRoot 'Common\WinFormsBootstrap.ps1'
        if (Test-Path -LiteralPath $_boot) {
            . $_boot
        }
    }
    if (Get-Command Initialize-ApplicationWinForms -ErrorAction SilentlyContinue) {
        Initialize-ApplicationWinForms
    }
    else {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        [System.Windows.Forms.Application]::EnableVisualStyles()
        [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
        $global:WinFormsInitialized = $true
        $global:WinFormsApplicationInitialized = $true
    }
}

function Start-GUI {
    param(
        [string]$FichierPDF,
        [switch]$RenameOnly
    )

    if (-not $script:AssistantStartupSw) {
        $script:AssistantStartupSw = [System.Diagnostics.Stopwatch]::StartNew()
        $script:AssistantStartupLastMs = 0L
    }
    if (-not (Get-Command Write-AssistantStartupMark -ErrorAction SilentlyContinue)) {
        function Write-AssistantStartupMark {
            param([Parameter(Mandatory = $true)][string]$Phase, [string]$Detail = $null)
            if (-not $script:AssistantStartupSw) { return }
            $elapsed = $script:AssistantStartupSw.ElapsedMilliseconds
            $delta = $elapsed - $script:AssistantStartupLastMs
            $script:AssistantStartupLastMs = $elapsed
            $deltaText = " (+${delta}ms)"
            $detailText = if ([string]::IsNullOrWhiteSpace($Detail)) { '' } else { " — $Detail" }
            $line = "[TIMING] {0}={1}ms{2}{3}" -f $Phase, $elapsed, $deltaText, $detailText
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) { Write-Log $line 'INFO' }
        }
    }

    $resolvedPdf = $null
    if (-not [string]::IsNullOrWhiteSpace($FichierPDF)) {
        if (Get-Command Resolve-AssistantInputPdfPath -ErrorAction SilentlyContinue) {
            $resolvedPdf = Resolve-AssistantInputPdfPath -RawArgument $FichierPDF
        }
        elseif (Test-Path -LiteralPath $FichierPDF -PathType Leaf) {
            try { $resolvedPdf = (Resolve-Path -LiteralPath $FichierPDF).Path } catch { $resolvedPdf = $FichierPDF }
        }
    }
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        if ($resolvedPdf) {
            Write-Log '[GUI] FichierPDF valide pour Convention de nommage' 'INFO' @{ path = $resolvedPdf; renameOnly = [bool]$RenameOnly }
        }
        else {
            Write-Log '[GUI] FichierPDF absent ou invalide' 'WARN' @{ raw = [string]$FichierPDF; renameOnly = [bool]$RenameOnly }
        }
    }

    # ---------- Mode RenameOnly (clic droit PDF) : Convention seule, pas de BDD/SharePoint/onglets ----------
    if ($RenameOnly) {
        if ([string]::IsNullOrWhiteSpace($resolvedPdf)) {
            Write-AssistantRenameOnlyGuiLog 'PDF invalide — abandon du mode leger'
            [System.Windows.Forms.MessageBox]::Show(
                "Aucun fichier PDF valide n'a ete fourni pour le renommage.",
                'ASSISTANT - Renommage PDF',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            return
        }

        Write-AssistantRenameOnlyGuiLog 'Demarrage UI legere (Convention uniquement)'
        Ensure-WinFormsInitialized
        Initialize-WinFormsUiCultureFrFr
        Write-AssistantStartupMark -Phase 'winforms_init'

        if (-not (Get-Command Show-ConventionNommagePanel -ErrorAction SilentlyContinue)) {
            . "$PSScriptRoot\ODM\ConventionNommage\ConventionNommage.ps1"
        }
        Write-AssistantStartupMark -Phase 'convention_scripts_loaded'

        $form = [System.Windows.Forms.Form]::new()
        $form.Text = 'ASSISTANT - Renommage PDF'
        $form.Size = [System.Drawing.Size]::new(900, 480)
        $form.StartPosition = 'CenterScreen'
        $form.MinimumSize = [System.Drawing.Size]::new(700, 420)
        $form.Font = $script:PoliceNormal
        $form.BackColor = $script:CouleurGrisFond
        $appRoot = Split-Path -Parent $PSScriptRoot
        $iconPath = Join-Path $appRoot 'ASSISTANT.ico'
        if (Test-Path -LiteralPath $iconPath) {
            try {
                $form.Icon = [System.Drawing.Icon]::new($iconPath)
            }
            catch { }
        }

        $panelResult = Show-ConventionNommagePanel -FichierPDF $resolvedPdf
        $realPanel = $panelResult[-1]
        if ($realPanel) {
            $realPanel.Dock = 'Fill'
            $realPanel.Name = 'ConventionNommageRootPanel'
            $form.Controls.Add($realPanel)
        }
        if (Get-Command Update-WinFormsTreeUiTexts -ErrorAction SilentlyContinue) {
            Update-WinFormsTreeUiTexts -RootControl $form
        }
        Write-AssistantStartupMark -Phase 'gui_built'
        Write-AssistantRenameOnlyGuiLog 'Forme prete — Application.Run'

        $form.Add_Shown({
            param($sender, $e)
            Write-AssistantStartupMark -Phase 'gui_shown'
            Write-AssistantRenameOnlyGuiLog ("Fenetre visible — elapsed={0}ms" -f $script:AssistantStartupSw.ElapsedMilliseconds)
            $frm = $sender
            if ($null -eq $frm -or $frm -isnot [System.Windows.Forms.Form]) { return }
            $rootPanel = $frm.Controls['ConventionNommageRootPanel']
            if ($null -eq $rootPanel) { return }
            $txtBox = $rootPanel.Controls['txtCollecte']
            if ($null -ne $txtBox) {
                $txtBox.Focus()
            }
        })

        [System.Windows.Forms.Application]::Run($form)
        Write-AssistantRenameOnlyGuiLog 'Application terminee'
        return
    }

    # ---------- Mode normal : onglets + SharePoint + lazy load ----------
    Write-AssistantNormalGuiLog 'Demarrage UI complete (onglets + SharePoint)'
    Ensure-WinFormsInitialized
    Initialize-WinFormsUiCultureFrFr
    Write-AssistantStartupMark -Phase 'winforms_init'

    # Dot-source ICI (portee Start-GUI), PAS dans une sous-fonction — sinon Get-SharePointPlanningUrl
    # est cree en local et disparait au return (crash lancement bureau / menu Demarrer).
    $spRoot = $scriptDir
    if ([string]::IsNullOrWhiteSpace($spRoot)) { $spRoot = $PSScriptRoot }
    if (-not $script:AssistantSharePointUiLoaded) {
        . (Join-Path $spRoot 'Common\CnsSharePointConnector.ps1')
        . (Join-Path $spRoot 'Common\CnsSharePointUI.ps1')
        $script:AssistantSharePointUiLoaded = $true
        Write-AssistantNormalGuiLog 'SharePoint UI charge (portee Start-GUI)'
    }
    if (-not (Get-Command Get-SharePointPlanningUrl -ErrorAction SilentlyContinue)) {
        throw 'Get-SharePointPlanningUrl introuvable apres chargement SharePoint — verifier CnsSharePointConnector.ps1'
    }

    $existingUrl = Get-SharePointPlanningUrl
    if ([string]::IsNullOrWhiteSpace($existingUrl)) {
        Write-AppHost '[CONFIG] Aucune URL SharePoint configurée. Lancement de l''assistant...' -ForegroundColor Yellow
        $configured = Show-FirstLaunchConfig
        if (-not $configured) {
            Write-AppHost '[CONFIG] Configuration annulée. Arrêt de l''application.' -ForegroundColor Red
            [System.Windows.Forms.MessageBox]::Show(
                "L'application va se fermer car aucune URL SharePoint n'a été configurée.",
                'Configuration requise',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            [Environment]::Exit(0)
            return
        }
        Write-AppHost '[CONFIG] Configuration enregistrée avec succès !' -ForegroundColor Green
    }
    Write-AssistantStartupMark -Phase 'sharepoint_config'
    Write-AssistantNormalGuiLog 'Configuration SharePoint OK'

    $updateManagerScript = Join-Path $PSScriptRoot 'Core\UpdateManager.ps1'
    if (Test-Path -LiteralPath $updateManagerScript) {
        . $updateManagerScript
    }

    if (-not (Get-Command Get-PlanningRebuildSetting -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\Config.ps1"
    }
    # Convention uniquement au demarrage — Agents / Vehicules / Planning / Outils en lazy load.
    if (-not (Get-Command Show-ConventionNommagePanel -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\ODM\ConventionNommage\ConventionNommage.ps1"
    }
    Write-AssistantStartupMark -Phase 'convention_scripts_loaded'

    $configManagerScript = Join-Path $PSScriptRoot 'Core\ConfigManager.ps1'
    if (Test-Path -LiteralPath $configManagerScript) {
        if (-not (Get-Command Get-CurrentCentre -ErrorAction SilentlyContinue)) {
            . $configManagerScript
        }
    }

    $script:GuiScriptDir = $scriptDir
    $script:GuiOutilsPanel = $null

    function script:Write-AssistantLazyLog {
        param([Parameter(Mandatory = $true)][string]$Message)
        $line = "[Lazy] $Message"
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log $line 'INFO'
        }
        if (Get-Command Write-AppHost -ErrorAction SilentlyContinue) {
            Write-AppHost $line -ForegroundColor DarkCyan
        }
    }

    function script:Add-AssistantLazyPlaceholder {
        param(
            [Parameter(Mandatory = $true)][System.Windows.Forms.TabPage]$Tab,
            [Parameter(Mandatory = $true)][string]$Message
        )
        $lbl = [System.Windows.Forms.Label]::new()
        $lbl.Name = 'LazyLoadPlaceholder'
        $lbl.Text = $Message
        $lbl.Dock = 'Fill'
        $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $lbl.ForeColor = [System.Drawing.Color]::DimGray
        if ($script:PoliceNormal) { $lbl.Font = $script:PoliceNormal }
        $Tab.Controls.Add($lbl)
    }

    function script:Initialize-AssistantLazyTabPage {
        param([Parameter(Mandatory = $true)][System.Windows.Forms.TabPage]$Tab)
        if ($null -eq $Tab) { return }
        if ($Tab.Tag -eq $true) { return }

        $tabName = [string]$Tab.Name
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $root = $script:GuiScriptDir
        if ([string]::IsNullOrWhiteSpace($root)) {
            $root = $PSScriptRoot
        }

        try {
            switch ($tabName) {
                'TabAgents' {
                    if (-not (Get-Command Show-AgentsPanel -ErrorAction SilentlyContinue)) {
                        $promoted = Import-AssistantLazyScriptsToScriptScope -LiteralPath @(
                            (Join-Path $root 'ODM\Agents\AgentPanel.ps1'),
                            (Join-Path $root 'ODM\Agents\AgentRepository.ps1')
                        )
                        script:Write-AssistantLazyLog ("Agents : {0} fonction(s) promu(es) au scope script" -f @($promoted).Count)
                    }
                    $Tab.Controls.Clear()
                    $agentsPanel = Show-AgentsPanel
                    if ($agentsPanel) {
                        $agentsPanel.Dock = 'Fill'
                        $Tab.Controls.Add($agentsPanel)
                    }
                    else {
                        $lblError = [System.Windows.Forms.Label]::new()
                        $lblError.Text = 'Erreur de chargement du panneau des agents'
                        $lblError.Dock = 'Fill'
                        $lblError.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
                        $lblError.ForeColor = [System.Drawing.Color]::Red
                        $Tab.Controls.Add($lblError)
                    }
                    $Tab.Tag = $true
                    script:Write-AssistantLazyLog ("Onglet Agents charge en {0}ms" -f $sw.ElapsedMilliseconds)
                }
                'TabVehicules' {
                    if (-not (Get-Command Show-VehiculesPanel -ErrorAction SilentlyContinue)) {
                        $vehPaths = @(Join-Path $root 'ODM\Vehicules\VehiculesPanel.ps1')
                        if (-not (Get-Command Get-Vehicules -ErrorAction SilentlyContinue)) {
                            $vehPaths += (Join-Path $root 'ODM\Vehicules\VehiculesRepository.ps1')
                        }
                        $promoted = Import-AssistantLazyScriptsToScriptScope -LiteralPath $vehPaths
                        script:Write-AssistantLazyLog ("Vehicules : {0} fonction(s) promu(es) au scope script" -f @($promoted).Count)
                    }
                    $Tab.Controls.Clear()
                    $vehiculesPanel = Show-VehiculesPanel -Vehicules (Get-Vehicules)
                    if ($vehiculesPanel) {
                        $vehiculesPanel.Dock = 'Fill'
                        $Tab.Controls.Add($vehiculesPanel)
                    }
                    $Tab.Tag = $true
                    script:Write-AssistantLazyLog ("Onglet Vehicules charge en {0}ms" -f $sw.ElapsedMilliseconds)
                }
                'TabPlanning' {
                    Import-AssistantPlanningModelTypes
                    Import-AssistantPlanningExtractorScripts
                    if (-not (Get-Command Show-PlanningRebuilderPanel -ErrorAction SilentlyContinue)) {
                        $promoted = Import-AssistantLazyScriptsToScriptScope -LiteralPath @(
                            (Join-Path $root 'ODM\PdfPlanningOptimizer\PlanningRebuilderPanel.ps1')
                        )
                        script:Write-AssistantLazyLog ("Planning : {0} fonction(s) promu(es) au scope script" -f @($promoted).Count)
                        if (Get-Command Safe-UpdateUIControl -ErrorAction SilentlyContinue) {
                            $script:PlanningSafeUpdateUiCmd = Get-Command Safe-UpdateUIControl -ErrorAction SilentlyContinue
                        }
                    }
                    $Tab.Controls.Clear()
                    $planningPanel = Show-PlanningRebuilderPanel
                    if ($planningPanel) {
                        $planningPanel.Dock = 'Fill'
                        $Tab.Controls.Add($planningPanel)
                    }
                    $Tab.Tag = $true
                    script:Write-AssistantLazyLog ("Onglet Planning charge en {0}ms" -f $sw.ElapsedMilliseconds)
                }
                'TabOutils' {
                    $outilsScript = Join-Path $root 'ODM\Outils\OutilsPanel.ps1'
                    if (-not (Test-Path -LiteralPath $outilsScript)) {
                        throw ("OutilsPanel.ps1 introuvable : {0}" -f $outilsScript)
                    }
                    if (-not (Get-Command Show-OutilsPanel -ErrorAction SilentlyContinue)) {
                        $promoted = Import-AssistantLazyScriptsToScriptScope -LiteralPath @($outilsScript)
                        script:Write-AssistantLazyLog ("Outils : {0} fonction(s) promu(es) au scope script" -f @($promoted).Count)
                    }
                    $Tab.Controls.Clear()
                    $outilsPanel = Show-OutilsPanel
                    if ($outilsPanel) {
                        $outilsPanel.Dock = 'Fill'
                        $Tab.Controls.Add($outilsPanel)
                    }
                    $script:GuiOutilsPanel = $outilsPanel
                    $Tab.Tag = $true
                    script:Write-AssistantLazyLog ("Onglet Outils charge en {0}ms" -f $sw.ElapsedMilliseconds)
                }
            }
        }
        catch {
            $Tab.Controls.Clear()
            $lblError = [System.Windows.Forms.Label]::new()
            $lblError.Text = ("Erreur de chargement : {0}" -f $_.Exception.Message)
            $lblError.Dock = 'Fill'
            $lblError.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $lblError.ForeColor = [System.Drawing.Color]::Red
            $Tab.Controls.Add($lblError)
            $Tab.Tag = $true
            script:Write-AssistantLazyLog ("Echec chargement {0} : {1}" -f $tabName, $_.Exception.Message)
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log '[Lazy] Exception chargement onglet' 'ERROR' @{
                    tab = $tabName
                    message = $_.Exception.Message
                }
            }
        }
    }

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'ASSISTANT'
    $currentCentre = $null
    if (Get-Command Get-CurrentCentre -ErrorAction SilentlyContinue) {
        $currentCentre = Get-CurrentCentre
    }
    elseif ($null -ne $script:ActiveCentre) {
        $currentCentre = $script:ActiveCentre
    }
    if ($currentCentre -and -not [string]::IsNullOrWhiteSpace([string]$currentCentre.name)) {
        if ([string]$currentCentre.id -eq 'custom') {
            $form.Text = ('ASSISTANT - {0}' -f (Get-CnsUnrecognizedCentreDisplayName))
        }
        else {
            $form.Text = ('ASSISTANT - {0}' -f $currentCentre.name)
        }
        Write-AppHost ("[Centre] Configuration : {0}" -f $currentCentre.name) -ForegroundColor Green
    }
    $form.Size = [System.Drawing.Size]::new(1400, 800)
    $form.StartPosition = "CenterScreen"
    $form.MinimumSize = [System.Drawing.Size]::new(1000, 650)
    $form.Font = $script:PoliceNormal
    $form.BackColor = $script:CouleurGrisFond
    $appRoot = Split-Path -Parent $PSScriptRoot
    $iconPath = Join-Path $appRoot 'ASSISTANT.ico'
    if (Test-Path -LiteralPath $iconPath) {
        try {
            $form.Icon = [System.Drawing.Icon]::new($iconPath)
        }
        catch {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log '[Start-GUI] Icone ASSISTANT.ico non chargee' 'WARN' @{ message = $_.Exception.Message }
            }
        }
    }
    $null = $form.Add_Load({
        $null = [System.Text.Encoding]::Default
    })

    $tabControl = [System.Windows.Forms.TabControl]::new()
    $tabControl.Dock = "Fill"
    $tabControl.Font = $script:PoliceNormal
    $tabControl.Name = "MainTabControl"

    # ONGLET 1 : Convention de nommage (seul onglet charge au demarrage)
    $tabRename = [System.Windows.Forms.TabPage]::new()
    $tabRename.Name = "TabConventionNommage"
    $tabRename.Text = "Convention de nommage"
    $tabRename.BackColor = $script:CouleurGrisFond
    $tabRename.Tag = $true

    $panelResult = Show-ConventionNommagePanel -FichierPDF $resolvedPdf
    $realPanel = $panelResult[-1]
    $tabRename.Controls.Add($realPanel)
    if ($realPanel) { $realPanel.Name = "ConventionNommageRootPanel" }
    $tabControl.TabPages.Add($tabRename)
    Write-AssistantStartupMark -Phase 'convention_panel_loaded'
    script:Write-AssistantLazyLog 'Onglet Convention de nommage pret (demarrage)'

    # ONGLET 2-5 : stubs — contenu charge au premier clic
    $tabAgents = [System.Windows.Forms.TabPage]::new()
    $tabAgents.Name = 'TabAgents'
    $tabAgents.Text = 'Données agents'
    $tabAgents.BackColor = $script:CouleurGrisFond
    $tabAgents.Tag = $false
    script:Add-AssistantLazyPlaceholder -Tab $tabAgents -Message 'Chargement des agents au premier affichage...'
    $tabControl.TabPages.Add($tabAgents)

    $tabVehicules = [System.Windows.Forms.TabPage]::new()
    $tabVehicules.Name = 'TabVehicules'
    $tabVehicules.Text = 'Données véhicules'
    $tabVehicules.BackColor = $script:CouleurGrisFond
    $tabVehicules.Tag = $false
    script:Add-AssistantLazyPlaceholder -Tab $tabVehicules -Message 'Chargement des véhicules au premier affichage...'
    $tabControl.TabPages.Add($tabVehicules)

    $tabPlanning = [System.Windows.Forms.TabPage]::new()
    $tabPlanning.Name = 'TabPlanning'
    $tabPlanning.Text = 'Edition planning'
    $tabPlanning.BackColor = $script:CouleurGrisFond
    $tabPlanning.Tag = $false
    script:Add-AssistantLazyPlaceholder -Tab $tabPlanning -Message 'Chargement de l''edition planning au premier affichage...'
    $tabControl.TabPages.Add($tabPlanning)

    $tabOutils = [System.Windows.Forms.TabPage]::new()
    $tabOutils.Name = 'TabOutils'
    $tabOutils.Text = 'Outils'
    $tabOutils.BackColor = $script:CouleurGrisFond
    $tabOutils.Tag = $false
    script:Add-AssistantLazyPlaceholder -Tab $tabOutils -Message 'Chargement des outils au premier affichage...'
    $tabControl.TabPages.Add($tabOutils)

    $script:GuiPreviousTabName = if ($tabControl.SelectedTab) { [string]$tabControl.SelectedTab.Name } else { $null }
    $tabControl.Add_SelectedIndexChanged({
        param($sender, $e)
        $tabs = $sender
        if ($null -eq $tabs -or $tabs -isnot [System.Windows.Forms.TabControl]) { return }
        $newTab = $tabs.SelectedTab
        $newName = if ($null -ne $newTab) { [string]$newTab.Name } else { $null }

        if ($script:GuiPreviousTabName -eq 'TabOutils' -and $newName -ne 'TabOutils') {
            $outilsPanel = $script:GuiOutilsPanel
            if ($null -ne $outilsPanel -and $null -ne $outilsPanel.Tag -and (Get-Command Save-OutilsPlanningRebuildSettings -ErrorAction SilentlyContinue)) {
                $ctx = $outilsPanel.Tag
                if ($null -ne $ctx.ChkPlayVideo -and $null -ne $ctx.TxtVideoPath -and $null -ne $ctx.NumDelay) {
                    Save-OutilsPlanningRebuildSettings `
                        -ChkPlayVideo $ctx.ChkPlayVideo `
                        -TxtVideoPath $ctx.TxtVideoPath `
                        -NumDelay $ctx.NumDelay `
                        -Reason 'changement_onglet' | Out-Null
                }
            }
        }

        if ($null -ne $newTab -and $newName -ne 'TabConventionNommage' -and $newTab.Tag -ne $true) {
            script:Initialize-AssistantLazyTabPage -Tab $newTab
        }

        $script:GuiPreviousTabName = $newName
    })

    $form.Controls.Add($tabControl)
    Update-WinFormsTreeUiTexts -RootControl $form
    Write-AssistantStartupMark -Phase 'gui_built'

    $form.Add_Shown({
        param($sender, $e)
        Write-AssistantStartupMark -Phase 'gui_shown'
        if (Get-Command Check-ForUpdates -ErrorAction SilentlyContinue) {
            $updateTimer = [System.Windows.Forms.Timer]::new()
            $updateTimer.Interval = 250
            $updateTimer.Add_Tick({
                param($s, $ev)
                $s.Stop()
                $s.Dispose()
                try {
                    Check-ForUpdates
                }
                catch {
                    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                        Write-Log '[Start-GUI] Erreur verification mises a jour (differee)' 'WARN' @{ message = $_.Exception.Message }
                    }
                }
            })
            $updateTimer.Start()
        }
        Start-Sleep -Milliseconds 100
        $frm = $sender
        if ($null -eq $frm -or $frm -isnot [System.Windows.Forms.Form]) { return }
        $tabs = $frm.Controls["MainTabControl"]
        if ($null -eq $tabs -or $tabs -isnot [System.Windows.Forms.TabControl]) { return }
        $tab = $tabs.TabPages["TabConventionNommage"]
        if ($null -eq $tab) { return }
        $rootPanel = $tab.Controls["ConventionNommageRootPanel"]
        if ($null -ne $rootPanel) {
            $txtBox = $rootPanel.Controls | Where-Object { $_ -is [System.Windows.Forms.TextBox] }
            if ($txtBox) { $txtBox.Focus() }
        }
    })

    [System.Windows.Forms.Application]::Run($form)
}

function Show-PDFViewer {
    param([string]$FilePath, [string]$Title = "Visionneuse PDF")
    Ensure-WinFormsInitialized
    if (-not (Get-Command Convert-ToUiText -ErrorAction SilentlyContinue)) {
        $sd = Split-Path -Parent $MyInvocation.MyCommand.Path
        . (Join-Path $sd 'Common\TextEncoding.ps1')
        . (Join-Path $sd 'Common\UiText.ps1')
    }
    Initialize-WinFormsUiCultureFrFr
    if (-not (Test-Path $FilePath)) {
        $msg = Convert-ToUiText -Text ("Fichier non trouvé : $FilePath")
        $cap = Convert-ToUiText -Text 'Erreur'
        [System.Windows.Forms.MessageBox]::Show($msg, $cap)
        return
    }
    $form = [System.Windows.Forms.Form]::new()
    $null = $form.Add_Load({ $null = [System.Text.Encoding]::Default })
    $form.Text = Convert-ToUiText -Text $Title
    $form.Size = [System.Drawing.Size]::new(1000, 700)
    $form.StartPosition = "CenterScreen"
    $webBrowser = [System.Windows.Forms.WebBrowser]::new()
    $webBrowser.Dock = "Fill"
    try { $webBrowser.Navigate($FilePath); $form.Controls.Add($webBrowser) }
    catch { Start-Process $FilePath }
    $btnClose = [System.Windows.Forms.Button]::new()
    $btnClose.Text = Convert-ToUiText -Text 'FERMER'
    $btnClose.Size = [System.Drawing.Size]::new(100, 40)
    $btnClose.Anchor = "Bottom,Right"
    $btnClose.Location = [System.Drawing.Point]::new($form.ClientSize.Width - 120, $form.ClientSize.Height - 50)
    $btnClose.BackColor = $script:CouleurOrange
    $btnClose.ForeColor = $script:CouleurBlanc
    $btnClose.FlatStyle = "Flat"
    $btnClose.Font = $script:PoliceBouton
    $btnClose.Add_Click({
        param($sender, $e)
        $frm = $sender.FindForm()
        if ($null -ne $frm) { $frm.Close() }
    })
    $form.Controls.Add($btnClose)
    $form.ShowDialog()
}


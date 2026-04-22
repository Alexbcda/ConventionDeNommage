#Requires -Version 5.1
<#
.SYNOPSIS
  Tests UI (handlers WinForms sans MessageBox modal), sécurité saisie, PDFTOTEXT_PATH, rate limit, logs.

.NOTES
  Invoke-Pester -Path .\Test\ConventionNommage.UiAndSecurity.Tests.ps1
  Ne charge pas Config.ps1 (STA / relance processus) : chargement minimal Styles + module CN.
#>

[CmdletBinding()]
param()

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:StylesPath = Join-Path $script:RepoRoot 'src\Common\Styles.ps1'
$script:PlaceholderPath = Join-Path $script:RepoRoot 'src\Common\WinFormsPlaceholder.ps1'
$script:LogicPath = Join-Path $script:RepoRoot 'src\ODM\ConventionNommage\ConventionNommageLogic.ps1'
$script:HandlersPath = Join-Path $script:RepoRoot 'src\ODM\ConventionNommage\ConventionNommageHandlers.ps1'
$script:PanelPath = Join-Path $script:RepoRoot 'src\ODM\ConventionNommage\ConventionNommagePanel.ps1'
$script:PdfExtractorPath = Join-Path $script:RepoRoot 'src\ODM\PdfPlanningOptimizer\Extractors\PdfExtractor.ps1'
$script:DesktopSecurityPath = Join-Path $script:RepoRoot 'src\Common\DesktopSecurity.ps1'
$script:DatabasePath = Join-Path $script:RepoRoot 'src\Database\Database.ps1'

function Get-CNTestPanel {
    param([string]$FichierPDF)
    $raw = Show-ConventionNommagePanel -FichierPDF $FichierPDF
    return @($raw)[0]
}

function Get-CNButtonFromPanel {
    param($Panel, [string]$Name)
    return @($Panel.Controls) | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
}

Describe 'ConventionNommage — UI handlers (capture sans MessageBox)' {

    BeforeAll {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        [System.Windows.Forms.Application]::EnableVisualStyles()
        [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
        . $script:StylesPath
        . $script:PlaceholderPath
        . $script:LogicPath
        . $script:HandlersPath
        . $script:PanelPath
    }

    AfterEach {
        Clear-CNConventionNommageUiTestCapture
    }

    It 'CAS 1 — collecte vide : Certificat / Planner / France Travail → message unique attendu' {
        Start-CNConventionNommageUiTestCapture
        $panel = Get-CNTestPanel -FichierPDF ''
        $form = New-Object System.Windows.Forms.Form
        $form.Controls.Add($panel)
        foreach ($btnName in @('btnCert', 'btnPlan', 'btnFT')) {
            $btn = Get-CNButtonFromPanel -Panel $panel -Name $btnName
            $btn | Should Not Be $null
            Invoke-CNConventionRenameClick -Sender $btn -TemplateId $(switch ($btnName) {
                    'btnCert' { 'certificat' }
                    'btnPlan' { 'planner' }
                    default { 'france-travail' }
                })
        }
        $script:CN_UITestMessages.Count | Should Be 3
        foreach ($m in $script:CN_UITestMessages) {
            $m.Text | Should Be 'Renseigner le point de collecte.'
            $m.Caption | Should Be 'Convention de nommage'
        }
    }

    It 'CAS 2 — collecte remplie, aucun PDF : message PDF attendu' {
        Start-CNConventionNommageUiTestCapture
        $panel = Get-CNTestPanel -FichierPDF ''
        $txt = @($panel.Controls) | Where-Object { $_.Name -eq 'txtCollecte' } | Select-Object -First 1
        $txt.Text = 'Lyon'
        $txt.ForeColor = [System.Drawing.SystemColors]::WindowText
        if ($txt.Tag -is [hashtable]) { $txt.Tag['CN_PlaceholderActive'] = $false }
        $form = New-Object System.Windows.Forms.Form
        $form.Controls.Add($panel)
        $btn = Get-CNButtonFromPanel -Panel $panel -Name 'btnPlan'
        Invoke-CNConventionRenameClick -Sender $btn -TemplateId 'planner'
        $script:CN_UITestMessages.Count | Should Be 1
        $script:CN_UITestMessages[0].Text | Should Be "Aucun fichier PDF valide n'est associé à cette fenêtre."
    }

    It 'CAS 3 — collecte + PDF valides : renommage + trace Invoke-CNRenameAction' {
        Start-CNConventionNommageUiTestCapture
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('cn_ui_' + [Guid]::NewGuid().ToString('n'))
        New-Item -Path $tmp -ItemType Directory -Force | Out-Null
        try {
            $pdf = Join-Path $tmp 'source.pdf'
            'PDF' | Out-File -LiteralPath $pdf -Encoding ascii -NoNewline
            $panel = Get-CNTestPanel -FichierPDF $pdf
            $txt = @($panel.Controls) | Where-Object { $_.Name -eq 'txtCollecte' } | Select-Object -First 1
            $txt.Text = 'Lyon'
            $txt.ForeColor = [System.Drawing.SystemColors]::WindowText
            if ($txt.Tag -is [hashtable]) { $txt.Tag['CN_PlaceholderActive'] = $false }
            $dtCtl = @($panel.Controls) | Where-Object { $_.Name -eq 'datePicker' } | Select-Object -First 1
            $d = $dtCtl.Value
            $expectedName = ('{0}-Lyon.pdf' -f $d.ToString('yyyyMMdd'))
            $expected = Join-Path $tmp $expectedName
            $form = New-Object System.Windows.Forms.Form
            $form.Controls.Add($panel)
            $btn = Get-CNButtonFromPanel -Panel $panel -Name 'btnPlan'
            Invoke-CNConventionRenameClick -Sender $btn -TemplateId 'planner'
            if (-not (Test-Path -LiteralPath $expected)) {
                $any = Get-ChildItem -LiteralPath $tmp -Filter '*.pdf' -ErrorAction SilentlyContinue
                throw "Renommage attendu introuvable ($expectedName). Fichiers: $($any.Name -join ', ')"
            }
            $traces = @($script:CN_ClickTraceTestLog)
            ($traces -join "`n") | Should Match 'Action=Invoke-CNRenameAction'
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Note : PerformClick() sans Application.Run ne déclenche souvent pas les abonnements WinForms ;
    # le CAS 1 appelle Invoke-CNConventionRenameClick (même corps que les handlers Add_Click) — équivalent fonctionnel au clic.
}

Describe 'ConventionNommage — sécurité saisie (sanitization)' {

    BeforeAll {
        . $script:LogicPath
    }

    $injections = @(
        '../../test',
        '..\..\Windows\System32',
        'DROP TABLE users',
        '$(Start-Process calc)',
        '| cmd.exe',
        '&& shutdown'
    )

    foreach ($sample in $injections) {
        $label = if ($sample.Length -gt 24) { $sample.Substring(0, 24) + '…' } else { $sample }
        It "injection-like : traitement sans exception fatale ($label)" {
            $threw = $false
            $out = $null
            $exMsg = ''
            try {
                $out = Sanitize-PointDeCollecte -Text $sample
            }
            catch {
                $threw = $true
                $exMsg = $_.Exception.Message
            }
            if (-not $threw) {
                ($out -match '[\\/]') | Should Be $false
                ($out -match '\$\(') | Should Be $false
            }
            else {
                ($exMsg -match 'Start-Process') | Should Be $false
            }
        }
    }

    It 'unicode / bypass : combinaisons et RLE' {
        $r1 = Sanitize-PointDeCollecte -Text ('aaaa{0}exe' -f [char]0x202E)
        ($r1.IndexOf([char]0x202E) -ge 0) | Should Be $false
        $comb = -join @([char]'a', [char]0x0301, [char]'a', [char]0x0301, [char]'a', [char]0x0301)
        $r2 = Sanitize-PointDeCollecte -Text $comb
        [string]::IsNullOrWhiteSpace($r2) | Should Be $false
    }
}

Describe 'ConventionNommage — PDFTOTEXT_PATH (bloque notepad.exe)' {

    BeforeAll {
        . $script:PdfExtractorPath
    }

    It 'refuse PDFTOTEXT_PATH vers un exe autre que pdftotext.exe' {
        (Test-Path -LiteralPath 'C:\Windows\System32\notepad.exe') | Should Be $true
        $saved = $env:PDFTOTEXT_PATH
        try {
            $env:PDFTOTEXT_PATH = 'C:\Windows\System32\notepad.exe'
            $threw = $false
            $msg = ''
            try {
                $null = Resolve-PdfTotextPath
            }
            catch {
                $threw = $true
                $msg = $_.Exception.Message
            }
            $threw | Should Be $true
            ($msg -match 'PDFTOTEXT_PATH|pdftotext') | Should Be $true
        }
        finally {
            $env:PDFTOTEXT_PATH = $saved
        }
    }
}

Describe 'ConventionNommage — rate limiting' {

    BeforeAll {
        . $script:DesktopSecurityPath
        . $script:LogicPath
    }

    It '51e appel Test-CNRateLimit lève Trop d actions' {
        Reset-CNRateLimitForTests
        1..50 | ForEach-Object { Test-CNRateLimit }
        { Test-CNRateLimit } | Should Throw "Trop d'actions. Veuillez patienter."
    }

    It '51e renommage Invoke-CNRenameAction lève (fenêtre métier)' {
        Reset-CNRateLimitForTests
        . $script:PlaceholderPath
        . $script:HandlersPath
        . $script:PanelPath
        . $script:StylesPath
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('cn_rl_' + [Guid]::NewGuid().ToString('n'))
        New-Item -Path $tmp -ItemType Directory -Force | Out-Null
        try {
            for ($i = 1; $i -le 50; $i++) {
                $pdf = Join-Path $tmp ("s$i.pdf")
                'P' | Out-File -LiteralPath $pdf -Encoding ascii -NoNewline
                $null = Invoke-CNRenameAction -TemplateId 'planner' -FichierPDF $pdf -UserText 'X' -DateSelectionnee ([datetime]::new(2026, 6, 1))
            }
            $pdf51 = Join-Path $tmp 's51.pdf'
            'P' | Out-File -LiteralPath $pdf51 -Encoding ascii -NoNewline
            { Invoke-CNRenameAction -TemplateId 'planner' -FichierPDF $pdf51 -UserText 'X' -DateSelectionnee ([datetime]::new(2026, 6, 1)) } |
                Should Throw "Trop d'actions. Veuillez patienter."
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'ConventionNommage — logs (rotation + anonymisation code)' {

    It 'Rotate-LogIfNeeded déplace le fichier au-delà de 10 Mo' {
        . $script:DesktopSecurityPath
        $log = Join-Path ([System.IO.Path]::GetTempPath()) ('cn_rot_' + [Guid]::NewGuid().ToString('n') + '.log')
        $fs = [System.IO.File]::Open($log, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
        try {
            $chunk = New-Object byte[] (1048576)
            1..11 | ForEach-Object { $fs.Write($chunk, 0, $chunk.Length) }
        }
        finally {
            $fs.Close()
        }
        try {
            (Get-Item -LiteralPath $log).Length -gt 10MB | Should Be $true
            Rotate-LogIfNeeded -LogFile $log
            (Test-Path -LiteralPath "$log.old") | Should Be $true
            (Test-Path -LiteralPath $log) | Should Be $false
        }
        finally {
            Remove-Item -LiteralPath "$log.old" -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
        }
    }

    It 'Database.ps1 : bloc Write-Log Add-Agent begin sans nom prenom telephone email (hors SQL)' {
        $dbSrc = Get-Content -LiteralPath $script:DatabasePath -Raw
        $m = [regex]::Match(
            $dbSrc,
            'Write-Log\s+"\[DB\]\s+Add-Agent begin"\s+"INFO"\s+@\{(.*?)\}',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
        $m.Success | Should Be $true
        $body = $m.Groups[1].Value
        ($body -match '\bnom\s*=') | Should Be $false
        ($body -match '\bprenom\s*=') | Should Be $false
        ($body -match '\btelephone\s*=') | Should Be $false
        ($body -match '\bemail\s*=') | Should Be $false
    }
}

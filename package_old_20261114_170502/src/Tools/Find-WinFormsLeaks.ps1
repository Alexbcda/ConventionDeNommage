<#
.SYNOPSIS
    Scanner statique : usages WinForms / Drawing suspects dans les scripts .ps1.
.DESCRIPTION
    Détecte notamment :
      - New-Object System.Windows.Forms.*
      - New-Object System.Drawing.*
      - [System.Windows.Forms.*]::new( ... ) et [System.Drawing.*]::new(
      - Add-Type -AssemblyName System.Windows.Forms (optionnellement exclure Bootstrap.ps1)
      - $global:x = New-Object System.Windows.Forms.*
.PARAMETER Root
    Racine à parcourir (défaut : racine du dépôt au-dessus de src\Tools).
.PARAMETER ExcludeBootstrapAddType
    Si vrai, n'affiche pas les correspondances Add-Type ... Windows.Forms dans src\Bootstrap.ps1.
.PARAMETER FailOnHigh
    Si vrai, code de sortie 1 lorsqu'au moins une alerte Severity High est trouvée (CI).
#>
[CmdletBinding()]
param(
    [string]$Root,
    [switch]$ExcludeBootstrapAddType,
    [switch]$FailOnHigh
)

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..') -ErrorAction Stop).Path
}

$ErrorActionPreference = 'Stop'
$patterns = @(
    @{ Name = 'New-Object WinForms';       Regex = 'New-Object\s+System\.Windows\.Forms\.';           Severity = 'High' }
    @{ Name = 'New-Object Drawing';      Regex = 'New-Object\s+System\.Drawing\.';                  Severity = 'Medium' }
    @{ Name = 'Typed ctor WinForms';     Regex = '\[\s*System\.Windows\.Forms\.[^\]]+\]\s*::\s*new\s*\('; Severity = 'High' }
    @{ Name = 'Typed ctor Drawing';      Regex = '\[\s*System\.Drawing\.[^\]]+\]\s*::\s*new\s*\(';   Severity = 'Medium' }
    @{ Name = 'Add-Type WinForms asm';   Regex = 'Add-Type\s+-AssemblyName\s+System\.Windows\.Forms'; Severity = 'High' }
    @{ Name = 'Global New-Object WinForms'; Regex = '\$global:\w+\s*=\s*New-Object\s+System\.Windows\.Forms\.'; Severity = 'High' }
)

$excludeDirs = @('\.git', '\\.git\\', 'node_modules', '\\obj\\', '\\bin\\')
$files = Get-ChildItem -LiteralPath $Root -Recurse -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
    Where-Object {
        $p = $_.FullName
        if ($p -like '*\Tools\Find-WinFormsLeaks.ps1' -or $p -like '*/Tools/Find-WinFormsLeaks.ps1') {
            return $false
        }
        foreach ($ex in $excludeDirs) {
            if ($p -match $ex) { return $false }
        }
        $true
    }

$hits = [System.Collections.Generic.List[object]]::new()

foreach ($file in $files) {
    $rel = $file.FullName
    if ($rel.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)) {
        $rel = $rel.Substring($Root.Length).TrimStart('\', '/')
    }
    if ([string]::IsNullOrWhiteSpace($rel)) { $rel = $file.Name }

    foreach ($rule in $patterns) {
        if ($ExcludeBootstrapAddType -and $rule.Name -eq 'Add-Type WinForms asm') {
            if ($file.Name -ieq 'Bootstrap.ps1') { continue }
        }

        $m = Select-String -LiteralPath $file.FullName -Pattern $rule.Regex -AllMatches -ErrorAction SilentlyContinue
        foreach ($line in @($m)) {
            [void]$hits.Add([pscustomobject]@{
                Severity = $rule.Severity
                Pattern  = $rule.Name
                File     = $rel
                Line     = $line.LineNumber
                LineText = $line.Line.Trim()
            })
        }
    }
}

$hits | Sort-Object Severity, File, Line | Format-Table -AutoSize

$summary = $hits | Group-Object Severity | ForEach-Object { "$($_.Name)=$($_.Count)" }
Write-Host ("[Find-WinFormsLeaks] Fichiers scannés: {0} | Hits: {1} | {2}" -f @($files).Count, $hits.Count, ($summary -join ' ')) -ForegroundColor Cyan

if ($FailOnHigh -and ($hits | Where-Object { $_.Severity -eq 'High' })) {
    exit 1
}
exit 0

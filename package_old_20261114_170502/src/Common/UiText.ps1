# UiText.ps1 - Culture fr-FR + normalisation texte UI (WinForms PS 5.1) + arbre de controles.
# Dependance : TextEncoding.ps1 (Fix-Encoding / Test-TextLikelyUtf8Mojibake) charge avant ce fichier.

$_cnUiTextDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$_cnTextEnc = Join-Path $_cnUiTextDir 'TextEncoding.ps1'
if (-not (Get-Command Fix-Encoding -ErrorAction SilentlyContinue)) {
    if (Test-Path -LiteralPath $_cnTextEnc) {
        . $_cnTextEnc
    }
}

function Initialize-WinFormsUiCultureFrFr {
    $fr = [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    [System.Threading.Thread]::CurrentThread.CurrentUICulture = $fr
    [System.Threading.Thread]::CurrentThread.CurrentCulture = $fr
    try {
        [System.Windows.Forms.Application]::CurrentCulture = $fr
    }
    catch {
        # Certaines versions / contextes sans Application host.
    }
}

function Convert-ToUiText {
    <#
    .SYNOPSIS
        Normalise les chaines affichees (mojibake UTF-8 lu comme Latin-1, symboles degre, etc.).
    .NOTES
        Implementation ASCII-safe : motifs en \uXXXX ; sorties via [char].
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Text
    )

    if ($null -eq $Text) {
        return $null
    }
    if ($Text.Length -eq 0) {
        return $Text
    }

    $t = $Text

    $deg = ([char]0x00B0).ToString()
    $pairs = @(
        @{ Pattern = 'N\u253C\u00B0'; Replacement = 'N' + $deg }
        @{ Pattern = 'n\u253C\u00B0'; Replacement = 'N' + $deg }
        @{ Pattern = 'N\u00C2\u00B0'; Replacement = 'N' + $deg }
        @{ Pattern = 'n\u00C2\u00B0'; Replacement = 'N' + $deg }
        @{ Pattern = '\u253C\u00B0'; Replacement = $deg }
        @{ Pattern = '\u00C2\u00B0'; Replacement = $deg }
        @{ Pattern = '\u00C3\u00A9'; Replacement = ([char]0x00E9).ToString() }
        @{ Pattern = '\u00C3\u00A8'; Replacement = ([char]0x00E8).ToString() }
        @{ Pattern = '\u00C3\u00A0'; Replacement = ([char]0x00E0).ToString() }
        @{ Pattern = '\u00C3\u00B9'; Replacement = ([char]0x00F9).ToString() }
        @{ Pattern = '\u00C3\u00A7'; Replacement = ([char]0x00E7).ToString() }
        @{ Pattern = '\u00C3\u00AA'; Replacement = ([char]0x00EA).ToString() }
        @{ Pattern = '\u00C3\u00AE'; Replacement = ([char]0x00EE).ToString() }
        @{ Pattern = '\u00C3\u00B4'; Replacement = ([char]0x00F4).ToString() }
    )
    foreach ($p in $pairs) {
        $t = [regex]::Replace($t, $p.Pattern, $p.Replacement)
    }

    if (Get-Command Test-TextLikelyUtf8Mojibake -ErrorAction SilentlyContinue) {
        if (Test-TextLikelyUtf8Mojibake -Text $t) {
            try {
                $t = Fix-Encoding -text $t
            }
            catch { }
        }
    }

    return $t
}

function Update-WinFormsTreeUiTexts {
    <#
    .SYNOPSIS
        Applique Convert-ToUiText sur Text de Label, Button, TabPage, Form, CheckBox, etc.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $RootControl
    )
    if ($null -eq $RootControl) {
        return
    }
    if ($RootControl.PSObject.Properties['Text']) {
        try {
            if (-not [string]::IsNullOrEmpty([string]$RootControl.Text)) {
                $RootControl.Text = Convert-ToUiText -Text ([string]$RootControl.Text)
            }
        }
        catch { }
    }
    $typesWithText = @(
        [System.Windows.Forms.Label],
        [System.Windows.Forms.Button],
        [System.Windows.Forms.TabPage],
        [System.Windows.Forms.Form],
        [System.Windows.Forms.CheckBox],
        [System.Windows.Forms.RadioButton],
        [System.Windows.Forms.GroupBox]
    )
    foreach ($c in @($RootControl.Controls)) {
        if ($null -eq $c) {
            continue
        }
        $isTextCtl = $false
        foreach ($t in $typesWithText) {
            if ($c -is $t) {
                $isTextCtl = $true
                break
            }
        }
        if ($isTextCtl -and $c.PSObject.Properties['Text']) {
            try {
                if (-not [string]::IsNullOrEmpty([string]$c.Text)) {
                    $c.Text = Convert-ToUiText -Text ([string]$c.Text)
                }
            }
            catch { }
        }
        if ($c.Controls -and $c.Controls.Count -gt 0) {
            Update-WinFormsTreeUiTexts -RootControl $c
        }
    }
}

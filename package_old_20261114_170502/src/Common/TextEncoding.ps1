# TextEncoding.ps1 - UTF-8 console + mojibake helper (UTF-8 read as Latin-1 / CP1252).
# Dot-source from Main.ps1 before other scripts. This file is ASCII-only (safe PS 5.1 parse without BOM).

function Initialize-ConventionAppConsoleUtf8 {
    $enc = [System.Text.Encoding]::UTF8

    # Proteger les appels Console (echouent dans exe PS2EXE sans console)
    try {
        [Console]::OutputEncoding = $enc
        [Console]::InputEncoding = $enc
    }
    catch {
        Write-Verbose "Console non disponible: $($_.Exception.Message)"
    }
}

function Test-TextLikelyUtf8Mojibake {
    <#
    .SYNOPSIS
        True if text looks like UTF-8 bytes mis-decoded as ISO-8859-1 (mojibake).
    .NOTES
        Pattern uses only \uXXXX in the regex string (ASCII in this .ps1) so the parser never sees embedded quotes.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$Text
    )
    if ([string]::IsNullOrEmpty($Text)) {
        return $false
    }
    # U+00C3 / U+00C2: common first byte of UTF-8 multibyte char misread as Latin-1.
    # U+00E2 U+20AC: start of UTF-8 punctuation misread (e.g. smart quotes / dash).
    # U+253C U+00B0 or U+2510 U+00B0: broken "degree" / ordinals in some PDF paths.
    $pat = '(\u00C3.)|(\u00C2.)|(\u00E2\u20AC.)|(\u253C\u00B0)|(\u2510\u00B0)'
    return [regex]::IsMatch($Text, $pat)
}

function Fix-Encoding {
    <#
    .SYNOPSIS
        Repair string assumed to be UTF-8 wrongly interpreted as ISO-8859-1 (code page 28591).
        Use only on legacy data; do not apply blindly.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$text
    )

    if ([string]::IsNullOrEmpty($text)) {
        return $text
    }

    return [System.Text.Encoding]::UTF8.GetString(
        [System.Text.Encoding]::GetEncoding(28591).GetBytes($text)
    )
}

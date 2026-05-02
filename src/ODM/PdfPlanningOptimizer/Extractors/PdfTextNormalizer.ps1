# ============================================================
# PdfTextNormalizer.ps1
# Couche minimale : bruit pdftotext (mojibake, espaces, tirets)
# avant EntityExtractor. Deterministe, sans fuzzy matching.
# ============================================================

function Normalize-PdfNoiseText {
    <#
    .SYNOPSIS
        Normalise les lignes texte issues de pdftotext (mojibake UTF-8, espaces, tirets, paires numeriques).

    .PARAMETER Lines
        Tableau de lignes brutes (une entree par ligne logique).

    .OUTPUTS
        [string[]] Une ligne normalisee par entree d'entree.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Lines
    )

    if ($null -eq $Lines) {
        return @()
    }

    $mojiPairs = @(
        @('N┬░', 'N°'),
        @('n┬░', 'N°'),
        @('A├®', 'Aé'),
        @('ÔÇó', '•'),
        @('Ã©', 'é'),
        @('Ã¨', 'è'),
        @('Ã´', 'ô'),
        @('Ã»', 'û'),
        @('Ã§', 'ç'),
        @('Ã‰', 'É'),
        @('Ã€', 'À'),
        @('Ãˆ', 'È'),
        @('ÃŠ', 'Ê'),
        @('ÃŽ', 'Î'),
        @('Ã–', 'Ö'),
        @('Ãœ', 'Ü'),
        @('Ã¹', 'ù'),
        @('Ãº', 'ú'),
        @('Ã¼', 'ü'),
        @('Ã¿', 'ÿ'),
        @('Ã¢', 'â'),
        @('Ã®', 'î'),
        @('Ã¯', 'ï'),
        @('Ã±', 'ñ'),
        @('Ã³', 'ó'),
        @('Â°', '°'),
        @('┬░', '°')
    )
    $mojiSorted = @($mojiPairs | Sort-Object { -($_[0].Length) })

    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $Lines) {
        if ($null -eq $line) {
            $out.Add('')
            continue
        }

        $t = [string]$line

        $t = $t -replace "`r", ''
        $t = $t -replace [char]0xFEFF, ''
        $t = $t -replace [char]0x200B, ''
        $t = $t -replace [char]0x200C, ''
        $t = $t -replace [char]0x2060, ''

        foreach ($pair in $mojiSorted) {
            $from = $pair[0]
            $to = $pair[1]
            if ($from.Length -gt 0) {
                $t = $t.Replace($from, $to)
            }
        }

        # « Nº » (ordinal U+00BA) et signe NUMERO « № » (U+2116) : pdftotext les utilise souvent à la place de N°
        $t = [regex]::Replace($t, '(?i)N\s*\u00BA\s*', 'N°')
        $t = [regex]::Replace($t, '(?i)\u2116\s*', 'N°')

        $t = $t -replace [char]0x00A0, ' '
        $t = $t -replace [char]0x202F, ' '
        $t = $t -replace [char]0x2007, ' '
        $t = $t -replace [char]0x2008, ' '
        $t = $t -replace [char]0x2009, ' '
        $t = $t -replace [char]0x200A, ' '
        $t = $t -replace [char]0x3000, ' '

        $t = [regex]::Replace($t, '\p{Pd}', '-')

        $t = [regex]::Replace($t, '\b(\d{4,})\s+-\s+(\d{2,})\b', '$1-$2')
        $t = [regex]::Replace($t, '\b(\d{3})\s+(\d{4})\b', '$1$2')
        $t = [regex]::Replace($t, '\b(\d{4})\s+(\d{3})\b', '$1$2')

        if ($t -match '^[\d\s]+$') {
            $collapsedDigits = $t -replace '\s+', ''
            if ($collapsedDigits.Length -ge 7) {
                $t = $collapsedDigits
            }
        }

        $t = [regex]::Replace($t, '[ \t]+', ' ', [System.Text.RegularExpressions.RegexOptions]::None)
        $out.Add($t.Trim())
    }
    return $out.ToArray()
}

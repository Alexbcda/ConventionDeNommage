# Module textLoader : lecture .txt brute et normalisation legere (sans autre logique).

function Get-TextLoaderRawString {
    <#
    .SYNOPSIS
        Lit un fichier .txt et retourne le contenu brut (string).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Fichier introuvable : $Path"
    }
    $ext = [System.IO.Path]::GetExtension($Path)
    if ([string]::Compare($ext, '.txt', [System.StringComparison]::OrdinalIgnoreCase) -ne 0) {
        throw "Extension attendue : .txt ($Path)"
    }

    $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    return [System.IO.File]::ReadAllText($resolved, $utf8)
}

function Normalize-TextLoaderText {
    <#
    .SYNOPSIS
        Supprime des artefacts d'encodage courants, reduit les espaces horizontaux par ligne, conserve les sauts de ligne.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

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
    $sorted = @($mojiPairs | Sort-Object { -($_[0].Length) })

    $t = $Text
    foreach ($pair in $sorted) {
        if ($pair[0].Length -gt 0) {
            $t = $t.Replace($pair[0], $pair[1])
        }
    }

    $t = $t -replace "`r`n", "`n"
    $t = $t -replace "`r", "`n"
    $lines = $t.Split([char]0x0A)
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        $line = [regex]::Replace($line, '[ \t]+', ' ')
        [void]$out.Add($line)
    }
    return ($out -join "`n")
}

Set-Alias -Name normalizeText -Value Normalize-TextLoaderText -Scope Script

Export-ModuleMember -Function Get-TextLoaderRawString, Normalize-TextLoaderText -Alias normalizeText

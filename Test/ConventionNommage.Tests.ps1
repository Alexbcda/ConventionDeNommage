#Requires -Version 5.1
<#
.SYNOPSIS
    Tests Pester — sanitization, collisions (anti-race), nommage, chemins longs.

.NOTES
    Compatible Pester 3.x / 4.x / 5.x.

    Invoke-Pester -Path .\Test\ConventionNommage.Tests.ps1
#>

[CmdletBinding()]
param()

$script:CNLogicFile = Join-Path $PSScriptRoot '..\src\ODM\ConventionNommage\ConventionNommageLogic.ps1'
. $script:CNLogicFile

Describe 'Sanitize-PointDeCollecte' {
    It 'rejette une chaîne vide ou blanche' {
        $threw = $false
        try { Sanitize-PointDeCollecte -Text '' } catch { $threw = $true }
        $threw | Should Be $true
        $threw = $false
        try { Sanitize-PointDeCollecte -Text '   ' } catch { $threw = $true }
        $threw | Should Be $true
    }

    It 'supprime les caractères interdits Windows' {
        $r = Sanitize-PointDeCollecte -Text 'Site\A:B*X?Y"Z<a>|b'
        $r | Should Be 'SiteABXYZab'
    }

    It 'neutralise le path traversal ..' {
        $r = Sanitize-PointDeCollecte -Text 'foo..bar..baz'
        $r | Should Be 'foobarbaz'
    }

    It 'supprime les séquences type injection PowerShell' {
        $r = Sanitize-PointDeCollecte -Text 'a`$(Remove-Item x)b'
        $r | Should Be 'aRemove-Item xb'
    }

    It 'tronque à 100 caractères max' {
        $long = 'A' * 300
        $r = Sanitize-PointDeCollecte -Text $long
        $r.Length | Should Be 100
    }

    It 'normalise les accents (NFD)' {
        $r = Sanitize-PointDeCollecte -Text 'Cité Préfecture'
        $r | Should Be 'Cite Prefecture'
    }

    It 'évite les noms réservés Windows (CON) par préfixe sûr' {
        $r = Sanitize-PointDeCollecte -Text 'CON'
        $r | Should Be 'X-CON'
    }

    It 'rejette une entrée brute trop longue (DoS)' {
        $huge = 'X' * 5000
        $threw = $false
        try { Sanitize-PointDeCollecte -Text $huge } catch { $threw = $true }
        $threw | Should Be $true
    }

    It 'supprime les caractères Unicode invisibles (Cf)' {
        $zw = [char]0x200B
        $r = Sanitize-PointDeCollecte -Text ("Paris${zw}Lyon")
        $r | Should Be 'ParisLyon'
    }

    It 'est idempotent' {
        $once = Sanitize-PointDeCollecte -Text '  Cité--Test  '
        $twice = Sanitize-PointDeCollecte -Text $once
        $once | Should Be $twice
    }

    It 'supprime les points en début et fin' {
        $r = Sanitize-PointDeCollecte -Text '...Lyon...'
        $r | Should Be 'Lyon'
    }
}

Describe 'Resolve-FileNameCollision' {
    It 'renomme fichier.pdf existant en fichier(1).pdf' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cn_test_" + [Guid]::NewGuid().ToString('n'))
        New-Item -Path $tmp -ItemType Directory -Force | Out-Null
        try {
            $f = Join-Path $tmp 'fichier.pdf'
            'a' | Out-File -LiteralPath $f -Encoding ascii -NoNewline
            Resolve-FileNameCollision -LiteralPath $f
            $bumped = Join-Path $tmp 'fichier(1).pdf'
            (Test-Path -LiteralPath $bumped) | Should Be $true
            (Test-Path -LiteralPath $f) | Should Be $false
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'choisit fichier(2).pdf si fichier(1).pdf existe déjà' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cn_test_" + [Guid]::NewGuid().ToString('n'))
        New-Item -Path $tmp -ItemType Directory -Force | Out-Null
        try {
            $f = Join-Path $tmp 'doc.pdf'
            'a' | Out-File -LiteralPath $f -Encoding ascii -NoNewline
            'b' | Out-File -LiteralPath (Join-Path $tmp 'doc(1).pdf') -Encoding ascii -NoNewline
            Resolve-FileNameCollision -LiteralPath $f
            (Test-Path -LiteralPath (Join-Path $tmp 'doc(2).pdf')) | Should Be $true
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'gère les noms avec espaces' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cn_test_" + [Guid]::NewGuid().ToString('n'))
        New-Item -Path $tmp -ItemType Directory -Force | Out-Null
        try {
            $f = Join-Path $tmp 'mon fichier.pdf'
            'a' | Out-File -LiteralPath $f -Encoding ascii -NoNewline
            Resolve-FileNameCollision -LiteralPath $f
            (Test-Path -LiteralPath (Join-Path $tmp 'mon fichier(1).pdf')) | Should Be $true
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'gère un nom de fichier Unicode' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cn_test_" + [Guid]::NewGuid().ToString('n'))
        New-Item -Path $tmp -ItemType Directory -Force | Out-Null
        try {
            $f = Join-Path $tmp 'café résumé.pdf'
            'a' | Out-File -LiteralPath $f -Encoding utf8 -NoNewline
            Resolve-FileNameCollision -LiteralPath $f
            $c1 = Get-ChildItem -LiteralPath $tmp -Filter '*.pdf' | Where-Object { $_.Name -like '*(*)*' }
            ($null -ne $c1) | Should Be $true
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'incrémente si beaucoup de fichiers (1) à (100) existent' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cn_test_" + [Guid]::NewGuid().ToString('n'))
        New-Item -Path $tmp -ItemType Directory -Force | Out-Null
        try {
            $f = Join-Path $tmp 'pile.pdf'
            'x' | Out-File -LiteralPath $f -Encoding ascii -NoNewline
            foreach ($n in 1..100) {
                'y' | Out-File -LiteralPath (Join-Path $tmp "pile($n).pdf") -Encoding ascii -NoNewline
            }
            Resolve-FileNameCollision -LiteralPath $f
            (Test-Path -LiteralPath (Join-Path $tmp 'pile(101).pdf')) | Should Be $true
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Invoke-CNRenameAction (nommage)' {
    It 'produit un nom CERTIFICAT conforme au template' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cn_pdf_" + [Guid]::NewGuid().ToString('n'))
        New-Item -Path $tmp -ItemType Directory -Force | Out-Null
        try {
            $pdf = Join-Path $tmp 'source.pdf'
            'PDF' | Out-File -LiteralPath $pdf -Encoding ascii
            $d = [datetime]::new(2026, 4, 15)
            Invoke-CNRenameAction -TemplateId 'certificat' -FichierPDF $pdf -UserText 'Lyon' -DateSelectionnee $d
            $expected = Join-Path $tmp 'Certificat de Destruction-Lyon-du 15.04.2026.pdf'
            (Test-Path -LiteralPath $expected) | Should Be $true
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'produit un nom PLANNER yyyyMMdd-texte' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cn_pdf_" + [Guid]::NewGuid().ToString('n'))
        New-Item -Path $tmp -ItemType Directory -Force | Out-Null
        try {
            $pdf = Join-Path $tmp 'a.pdf'
            'PDF' | Out-File -LiteralPath $pdf -Encoding ascii
            $d = [datetime]::new(2026, 1, 8)
            Invoke-CNRenameAction -TemplateId 'planner' -FichierPDF $pdf -UserText 'Paris' -DateSelectionnee $d
            (Test-Path -LiteralPath (Join-Path $tmp '20260108-Paris.pdf')) | Should Be $true
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'produit un nom FRANCE TRAVAIL identique au format PLANNER' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cn_pdf_" + [Guid]::NewGuid().ToString('n'))
        New-Item -Path $tmp -ItemType Directory -Force | Out-Null
        try {
            $pdf = Join-Path $tmp 'x.pdf'
            'PDF' | Out-File -LiteralPath $pdf -Encoding ascii
            $d = [datetime]::new(2026, 2, 1)
            Invoke-CNRenameAction -TemplateId 'france-travail' -FichierPDF $pdf -UserText 'Marseille' -DateSelectionnee $d
            (Test-Path -LiteralPath (Join-Path $tmp '20260201-Marseille.pdf')) | Should Be $true
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'déplace un fichier existant avec le même nom puis renomme la source' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cn_pdf_" + [Guid]::NewGuid().ToString('n'))
        New-Item -Path $tmp -ItemType Directory -Force | Out-Null
        try {
            $src = Join-Path $tmp 'nouveau.pdf'
            'NEW' | Out-File -LiteralPath $src -Encoding ascii
            $d = [datetime]::new(2026, 3, 1)
            $targetName = '20260301-Dup.pdf'
            $existing = Join-Path $tmp $targetName
            'OLD' | Out-File -LiteralPath $existing -Encoding ascii

            Invoke-CNRenameAction -TemplateId 'planner' -FichierPDF $src -UserText 'Dup' -DateSelectionnee $d

            (Test-Path -LiteralPath (Join-Path $tmp '20260301-Dup(1).pdf')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $tmp '20260301-Dup.pdf')) | Should Be $true
            ((Get-Content -LiteralPath (Join-Path $tmp '20260301-Dup(1).pdf') -Raw).Trim()) | Should Be 'OLD'
            ((Get-Content -LiteralPath (Join-Path $tmp '20260301-Dup.pdf') -Raw).Trim()) | Should Be 'NEW'
        }
        finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Chemins longs (Windows)' {
    It 'renomme via logique longue si le chemin complet dépasse 260 caractères' {
        $base = Join-Path ([System.IO.Path]::GetTempPath()) ("cn_long_" + [Guid]::NewGuid().ToString('n'))
        $deep = $base
        $seg = 'd'
        while ($deep.Length -lt 220) {
            $deep = Join-Path $deep ($seg * 40)
        }
        try {
            New-Item -Path $deep -ItemType Directory -Force | Out-Null
            $pdf = Join-Path $deep 's.pdf'
            'PDF' | Out-File -LiteralPath $pdf -Encoding ascii
            $d = [datetime]::new(2026, 5, 1)
            Invoke-CNRenameAction -TemplateId 'planner' -FichierPDF $pdf -UserText 'L' -DateSelectionnee $d
            $leaf = '20260501-L.pdf'
            $expected = Join-Path $deep $leaf
            (Test-Path -LiteralPath $expected) | Should Be $true
        }
        finally {
            Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Convert-ToUiText (UI normalization)' {
    It 'repairs degree and e-acute mojibake fragments' {
        . (Join-Path $PSScriptRoot '..\src\Common\TextEncoding.ps1')
        . (Join-Path $PSScriptRoot '..\src\Common\UiText.ps1')
        $degBroken = 'N' + ([char]0x253C) + ([char]0x00B0)
        (Convert-ToUiText -Text $degBroken) | Should Be ('N' + ([char]0x00B0))
        $mojE = ([string][char]0x00C3) + ([string][char]0x00A9)
        (Convert-ToUiText -Text $mojE) | Should Be ([string][char]0x00E9)
    }
}

Describe 'TextEncoding (Fix-Encoding, mojibake)' {
    It 'Fix-Encoding maps Latin-1 mojibake back to UTF-8 code points' {
        . (Join-Path $PSScriptRoot '..\src\Common\TextEncoding.ps1')
        $mojE = ([string][char]0x00C3) + ([string][char]0x00A9)
        $mojDeg = ([string][char]0x00C2) + ([string][char]0x00B0)
        (Fix-Encoding -text $mojE) | Should Be ([string][char]0x00E9)
        (Fix-Encoding -text $mojDeg) | Should Be ([string][char]0x00B0)
    }

    It 'Test-TextLikelyUtf8Mojibake detects typical patterns' {
        . (Join-Path $PSScriptRoot '..\src\Common\TextEncoding.ps1')
        $sample = 'AEROPORT N' + ([string][char]0x00C3) + ([string][char]0x00A9)
        (Test-TextLikelyUtf8Mojibake -Text $sample) | Should Be $true
        (Test-TextLikelyUtf8Mojibake -Text 'ASCII only') | Should Be $false
    }
}

Describe 'Get-CNValidatedTemplates' {
    It 'rejette un format avec accolades non autorisées' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cn_bad_" + [Guid]::NewGuid().ToString('n') + '.json')
        try {
            @'
{"templates":[{"id":"certificat","format":"Bad-{text}-{date}-{x}","dateFormat":"dd.MM.yyyy","enabled":true},{"id":"planner","format":"{date}-{text}","dateFormat":"yyyyMMdd","enabled":true},{"id":"france-travail","format":"{date}-{text}","dateFormat":"yyyyMMdd","enabled":true}]}
'@ | Out-File -LiteralPath $tmp -Encoding utf8
            $threw = $false
            try { Get-CNValidatedTemplates -TemplatePath $tmp | Out-Null } catch { $threw = $true }
            $threw | Should Be $true
        }
        finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejette un dateFormat invalide (HHmm)' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cn_bad_df_" + [Guid]::NewGuid().ToString('n') + '.json')
        try {
            @'
{"templates":[{"id":"certificat","format":"Certificat de Destruction-{text}-du {date}","dateFormat":"dd.MM.yyyy","enabled":true},{"id":"planner","format":"{date}-{text}","dateFormat":"HHmmss","enabled":true},{"id":"france-travail","format":"{date}-{text}","dateFormat":"yyyyMMdd","enabled":true}]}
'@ | Out-File -LiteralPath $tmp -Encoding utf8
            $threw = $false
            try { Get-CNValidatedTemplates -TemplatePath $tmp | Out-Null } catch { $threw = $true }
            $threw | Should Be $true
        }
        finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    It 'accepte un JSON UTF-8 mal décodé (mojibake) après réparation' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cn_moj_" + [Guid]::NewGuid().ToString('n') + '.json')
        try {
            $moj = ([string][char]0x00C3) + ([string][char]0x00A9)
            $fmt = 'Certificat de Destruction-' + $moj + '-{text}-du {date}'
            $obj = @{
                templates = @(
                    @{ id = 'certificat'; format = $fmt; dateFormat = 'dd.MM.yyyy'; enabled = $true },
                    @{ id = 'planner'; format = '{date}-{text}'; dateFormat = 'yyyyMMdd'; enabled = $true },
                    @{ id = 'france-travail'; format = '{date}-{text}'; dateFormat = 'yyyyMMdd'; enabled = $true }
                )
            }
            $obj | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tmp -Encoding UTF8
            $threw = $false
            try { Get-CNValidatedTemplates -TemplatePath $tmp | Out-Null } catch { $threw = $true }
            $threw | Should Be $false
        }
        finally {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Test-CNDateFormat' {
    It 'accepte yyyyMMdd et dd.MM.yyyy' {
        (Test-CNDateFormat -DateFormat 'yyyyMMdd') | Should Be $true
        (Test-CNDateFormat -DateFormat 'dd.MM.yyyy') | Should Be $true
    }

    It 'refuse HHmm et les motifs hors yyyy MM dd' {
        (Test-CNDateFormat -DateFormat 'HHmmss') | Should Be $false
        (Test-CNDateFormat -DateFormat 'yyyy-MM') | Should Be $false
    }
}

Describe 'Classification IOException (Win32)' {
    It 'Test-IsFileCollisionException est vrai pour ERROR_FILE_EXISTS (80)' {
        $e = [System.ComponentModel.Win32Exception]::new(80)
        (Test-IsFileCollisionException -Exception $e) | Should Be $true
    }

    It 'Test-IsFatalSystemIOException est vrai pour ERROR_DISK_FULL (112)' {
        $e = [System.ComponentModel.Win32Exception]::new(112)
        (Test-IsFatalSystemIOException -Exception $e) | Should Be $true
    }
}

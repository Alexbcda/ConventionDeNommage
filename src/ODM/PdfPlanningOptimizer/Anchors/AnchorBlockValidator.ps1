# ============================================================
# AnchorBlockValidator.ps1
# Validation structurelle des blocs client (sans extraction métier).
# Chargement : . (Join-Path $PSScriptRoot 'Anchors\AnchorBlockValidator.ps1')
# ============================================================

function Validate-AnchorBlocks {
    <#
    .SYNOPSIS
        Valide et score les blocs produits par Build-AnchorBlocks (ancres + RawTextBlock).

    .PARAMETER Blocks
        Tableau d’objets ClientBlockId, StartIndex, EndIndex, Anchors, RawTextBlock.

    .PARAMETER Text
        Texte normalisé complet (référence ; le bloc utilise surtout RawTextBlock).

    .OUTPUTS
        [pscustomobject] ClientBlockId, IsValid, IsSuspicious, NoiseScore, Reason
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Blocks,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    Write-Verbose 'Validate-AnchorBlocks: début.'

    $results = [System.Collections.Generic.List[object]]::new()
    $validCount = 0
    $suspiciousCount = 0
    $rejectedCount = 0

    if ($null -eq $Blocks -or $Blocks.Count -eq 0) {
        Write-Verbose 'Validate-AnchorBlocks: aucun bloc — 0 valide, 0 suspect, 0 rejeté.'
        return @()
    }

    $noisePatterns = @(
        '(?i)\bcontrat\b',
        '(?i)\bfacture\b',
        '(?i)\bchorus\b',
        '(?i)\brejetée\b',
        '(?i)\brejetee\b'
    )

    foreach ($block in $Blocks) {
        if ($null -eq $block) { continue }

        $cid = [int]$block.ClientBlockId
        $raw = [string]$block.RawTextBlock
        if ([string]::IsNullOrEmpty($raw) -and $null -ne $block.PSObject.Properties['StartIndex'] -and $null -ne $block.PSObject.Properties['EndIndex']) {
            $si = [int]$block.StartIndex
            $ei = [int]$block.EndIndex
            if ($ei -ge $si -and $null -ne $Text -and $Text.Length -gt 0) {
                $eiCap = [Math]::Min($ei, $Text.Length - 1)
                if ($eiCap -ge $si) {
                    $raw = $Text.Substring($si, $eiCap - $si + 1)
                }
            }
        }

        $anchors = @($block.Anchors)
        $woCount = @($anchors | Where-Object { $null -ne $_ -and [string]$_.Name -ceq 'WORKORDER_LINE' }).Count
        $usefulNames = @('ADDRESS_BLOCK', 'DATE_BLOCK', 'WORKORDER_LINE')
        $usefulCount = @($anchors | Where-Object {
                $null -ne $_ -and ($usefulNames -contains [string]$_.Name)
            }).Count

        $reasons = [System.Collections.Generic.List[string]]::new()
        $isValid = $true

        if ($cid -ne 0) {
            if ($woCount -lt 1) {
                $isValid = $false
                [void]$reasons.Add('Aucune ancre WORKORDER_LINE.')
            }
            if ($usefulCount -lt 1) {
                $isValid = $false
                [void]$reasons.Add('Moins de 1 ancre utile (ADDRESS_BLOCK, DATE_BLOCK ou WORKORDER_LINE).')
            }
        }

        $nDegree = ([regex]::Matches($raw, 'N°', [System.Text.RegularExpressions.RegexOptions]::None)).Count
        $isSuspicious = $nDegree -gt 2
        if ($isSuspicious) {
            [void]$reasons.Add("Suspect: $nDegree occurrence(s) de « N° » (> 2).")
        }

        $noiseScore = 0
        foreach ($line in ($raw -split "`n", [System.StringSplitOptions]::None)) {
            foreach ($rx in $noisePatterns) {
                if ($line -match $rx) {
                    $noiseScore++
                    break
                }
            }
        }
        if ($noiseScore -gt 0) {
            [void]$reasons.Add("Bruit ADV: $noiseScore ligne(s) avec motif contrat/facture/chorus/rejetée.")
        }

        if ($isValid) { $validCount++ }
        else { $rejectedCount++ }
        if ($isSuspicious) { $suspiciousCount++ }

        $reasonOut = if ($reasons.Count -gt 0) {
            ($reasons.ToArray() -join ' ')
        }
        else {
            'OK'
        }

        $results.Add([pscustomobject]@{
            ClientBlockId  = $cid
            IsValid        = $isValid
            IsSuspicious   = $isSuspicious
            NoiseScore     = $noiseScore
            Reason         = $reasonOut
        })
    }

    Write-Verbose "Validate-AnchorBlocks: blocs valides = $validCount."
    Write-Verbose "Validate-AnchorBlocks: blocs suspects = $suspiciousCount."
    Write-Verbose "Validate-AnchorBlocks: blocs rejetés = $rejectedCount."
    Write-Verbose 'Validate-AnchorBlocks: fin.'

    return $results.ToArray()
}

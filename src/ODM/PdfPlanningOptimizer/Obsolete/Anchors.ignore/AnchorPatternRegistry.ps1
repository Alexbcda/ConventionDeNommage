# ============================================================
# AnchorPatternRegistry.ps1
# Registre central des motifs (regex / marqueurs) pour l’extraction anchor-based.
# Aligné sur AnchorEntityExtractor.ps1 — modifier ici sans toucher à la logique métier.
# Chargement : . (Join-Path $PSScriptRoot 'Anchors\AnchorPatternRegistry.ps1')
# ============================================================

$script:__AnchorPatterns = @{
    # Marqueur pour le nom client : texte avant cette séquence sur la ligne (IndexOf / sous-chaîne).
    ClientNamePattern = 'N°'
    # Premier groupe = identifiant client.
    ClientIdPattern   = 'N°\s*(\d{5,6})\b'
    # Premier groupe = paire ordre de mission / ODM.
    WorkOrderPattern  = '\b(\d{7,8}-\d{8,9})\b'
    # Code postal FR sur une ligne d’adresse.
    AddressPattern    = '\b\d{5}\b'
    # Ligne date : libellé « Date de passage » (reste de ligne optionnel).
    DatePattern       = '(?i)Date\s+de\s+passage\s*:?.*'
}

function script:Write-AnchorPatternRegistryStartupLog {
    Write-Verbose 'AnchorPatternRegistry: démarrage — liste des patterns enregistrés.'
    foreach ($key in ($script:__AnchorPatterns.Keys | Sort-Object)) {
        Write-Verbose "AnchorPatternRegistry:   [$key] = '$($script:__AnchorPatterns[$key])'"
    }
    Write-Verbose 'AnchorPatternRegistry: chargement terminé.'
}

function Get-AnchorPattern {
    <#
    .SYNOPSIS
        Retourne la chaîne de motif enregistrée pour le type demandé (regex ou marqueur).

    .PARAMETER Type
        ClientNamePattern | ClientIdPattern | WorkOrderPattern | AddressPattern | DatePattern
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'ClientNamePattern',
            'ClientIdPattern',
            'WorkOrderPattern',
            'AddressPattern',
            'DatePattern'
        )]
        [string]$Type
    )

    $pattern = $script:__AnchorPatterns[$Type]
    Write-Verbose "AnchorPatternRegistry: utilisation du pattern '$Type' → '$pattern'"
    return $pattern
}

Write-AnchorPatternRegistryStartupLog

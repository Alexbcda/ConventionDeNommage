# ConventionNommage.ps1 - Module principal
# Ordre : encodage UI commun → Logic → helpers WinForms → Handlers → Panel
# (ConventionNommageHandlers.ps1 recharge Logic/placeholder si besoin quand dot-sourcé seul.)
#
# Diagnostic clics WinForms (avant ShowDialog / après chargement module) :
#   $script:CN_DebugClickMode = $true
#   $script:CN_ClickTestStopMode = $true   # flux UI complet puis STOP avant Invoke-CNRenameAction
# Renommage réel : les deux à $false (valeur par défaut après 1er chargement des handlers).

$script:CNCommonRoot = Join-Path $PSScriptRoot '..\..\Common'
if (-not (Get-Command Convert-ToUiText -ErrorAction SilentlyContinue)) {
    . (Join-Path $script:CNCommonRoot 'TextEncoding.ps1')
    . (Join-Path $script:CNCommonRoot 'UiText.ps1')
}

. "$PSScriptRoot\ConventionNommageLogic.ps1"
. "$PSScriptRoot\..\..\Common\WinFormsPlaceholder.ps1"
. "$PSScriptRoot\ConventionNommageHandlers.ps1"
. "$PSScriptRoot\ConventionNommagePanel.ps1"

Write-Verbose "[CN-Module] Module ConventionNommage chargé"


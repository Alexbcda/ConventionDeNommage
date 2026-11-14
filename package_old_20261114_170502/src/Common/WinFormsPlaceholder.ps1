# WinFormsPlaceholder.ps1 — Placeholder TextBox compatible .NET Framework (PS 5.1 / PS 7+)
# TextBox.PlaceholderText n'existe pas sur WinForms classique ; on simule avec Enter/Leave.

<#
.SYNOPSIS
  Affiche un texte indicatif grisé ; au focus, le champ se vide pour la saisie réelle.
.NOTES
  Utilise TextBox.Tag (hashtable) : ne pas réutiliser Tag sur le même contrôle pour autre chose.
#>
function Set-WinFormsPlaceholder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.TextBox]$TextBox,

        [Parameter(Mandatory = $true)]
        [string]$Placeholder,

        [System.Drawing.Color]$PlaceholderColor = [System.Drawing.SystemColors]::GrayText
    )

    $userColor = $TextBox.ForeColor
    $ph = $Placeholder
    if (Get-Command Convert-ToUiText -ErrorAction SilentlyContinue) {
        $ph = Convert-ToUiText -Text $Placeholder
    }

    $TextBox.Tag = @{
        CN_Placeholder       = $ph
        CN_UserForeColor     = $userColor
        CN_PlaceholderColor  = $PlaceholderColor
        CN_PlaceholderActive = $true
    }

    $TextBox.Text = $ph
    $TextBox.ForeColor = $PlaceholderColor

    $null = $TextBox.Add_Enter({
        param($sender, $e)
        $tag = $sender.Tag
        if ($null -eq $tag -or $tag -isnot [hashtable]) { return }
        $ph = [string]$tag.CN_Placeholder
        if ([string]::IsNullOrEmpty($ph)) { return }
        if ($sender.Text -eq $ph) {
            $sender.Text = ''
            $sender.ForeColor = $tag.CN_UserForeColor
            $tag.CN_PlaceholderActive = $false
        }
    })

    $null = $TextBox.Add_Leave({
        param($sender, $e)
        $tag = $sender.Tag
        if ($null -eq $tag -or $tag -isnot [hashtable]) { return }
        $ph = [string]$tag.CN_Placeholder
        if ([string]::IsNullOrWhiteSpace($sender.Text)) {
            $sender.Text = $ph
            $sender.ForeColor = $tag.CN_PlaceholderColor
            $tag.CN_PlaceholderActive = $true
        }
    })
}

<#
.SYNOPSIS
  Retourne le texte saisi par l'utilisateur, ou chaîne vide si le placeholder est encore affiché.
#>
function Get-WinFormsTextBoxUserText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Windows.Forms.TextBox]$TextBox
    )

    if ($null -eq $TextBox) { return '' }
    $t = $TextBox.Text
    if ($TextBox.Tag -is [hashtable]) {
        $tag = [hashtable]$TextBox.Tag
        $ph = $tag.CN_Placeholder
        if (-not [string]::IsNullOrEmpty($ph) -and $t -eq $ph) {
            return ''
        }
    }
    return $t
}

# Framework/Router.ps1
$script:Routes = @{}
$script:History = @()

function Register-Route {
    param([string]$Path, [ScriptBlock]$Component)
    $script:Routes[$Path] = $Component
    Write-Host "[ROUTER] Route: $Path" -ForegroundColor Green
}

function Navigate {
    param([string]$Path)
    
    Write-Host "[ROUTER] Navigation: $Path" -ForegroundColor Cyan
    
    if (-not $script:Routes.ContainsKey($Path)) {
        Write-Host "[ROUTER] Route inconnue: $Path" -ForegroundColor Red
        return
    }
    
    $current = Get-State -Key "CurrentRoute"
    if ($current) { $script:History += $current }
    Set-State -Key "CurrentRoute" -Value $Path
    
    $form = [System.Windows.Forms.Application]::OpenForms[0]
    if (-not $form) {
        Write-Host "[ROUTER] Formulaire non trouvé" -ForegroundColor Red
        return
    }
    
    $container = $null
    if ($form.Tag -and $form.Tag.AffectationContainer) {
        $container = $form.Tag.AffectationContainer
    } elseif ($form.Controls.Find("AffectationContainer", $true)) {
        $container = $form.Controls.Find("AffectationContainer", $true)[0]
    }
    
    if (-not $container) {
        Write-Host "[ROUTER] Conteneur non trouvé" -ForegroundColor Red
        return
    }
    
    $container.Controls.Clear()
    $page = & $script:Routes[$Path]
    if ($page) {
        $container.Controls.Add($page)
        Write-Host "[ROUTER] OK -> $Path" -ForegroundColor Green
    }
}

function Navigate-Back {
    if ($script:History.Count -eq 0) { 
        Write-Host "[ROUTER] Déjà au début" -ForegroundColor Yellow
        return
    }
    $previous = $script:History[-1]
    $script:History = $script:History[0..($script:History.Count-2)]
    Navigate -Path $previous
}

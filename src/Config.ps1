if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
    powershell -STA -File $PSCommandPath $args
    exit
}

# WinForms : Main.ps1 charge Bootstrap.ps1 en premier ; repli si Config.ps1 est dot-source seul.
$_cnBootstrap = Join-Path $PSScriptRoot 'Bootstrap.ps1'
if (-not $global:WinFormsInitialized -and (Test-Path -LiteralPath $_cnBootstrap)) {
    . $_cnBootstrap
}
elseif (-not $global:WinFormsInitialized) {
    $global:FirstWinFormsCreationStack = $null
    if ($env:CN_WINFORMS_STRICT -eq '0') {
        $global:WinFormsStrictMode = $false
    }
    else {
        $global:WinFormsStrictMode = $true
    }
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $global:WinFormsInitialized = $true
    [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
    $global:WinFormsApplicationInitialized = $true
}

# Tous les styles sont dans Styles.ps1

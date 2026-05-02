# Bootstrap.ps1 — premier chargement WinForms (depuis Main.ps1 avant Config / Styles / métier).
# Ne pas instancier de Form/Control ici : uniquement Application + assemblies.

if (-not (Get-Variable -Name FirstWinFormsCreationStack -Scope Global -ErrorAction SilentlyContinue)) {
    $global:FirstWinFormsCreationStack = $null
}
else {
    $global:FirstWinFormsCreationStack = $null
}

if ($env:CN_WINFORMS_STRICT -eq '0') {
    $global:WinFormsStrictMode = $false
}
else {
    $global:WinFormsStrictMode = $true
}

if (-not (Get-Variable -Name WinFormsInitialized -Scope Global -ErrorAction SilentlyContinue)) {
    $global:WinFormsInitialized = $false
}

Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue

[System.Windows.Forms.Application]::EnableVisualStyles()

if (-not $global:WinFormsInitialized) {
    $global:WinFormsInitialized = $true
    [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
}

# Synchroniser avec WinFormsBootstrap.ps1 / Ensure-WinFormsInitialized (idempotence).
$global:WinFormsApplicationInitialized = $true

#Requires -Version 5.1
param([string]$InstallDir = 'C:\ASSISTANT')
$repo = 'c:\Users\alexa\Documents\ConventionDeNommage'
Copy-Item (Join-Path $repo 'src\GUI.ps1') (Join-Path $InstallDir 'src\GUI.ps1') -Force
'1.0.18-hotfix6' | Set-Content (Join-Path $InstallDir 'version.txt') -Encoding UTF8
Write-Host 'hotfix6 deploye : prechargement planning en arriere-plan apres affichage fenetre' -ForegroundColor Green

# TemplateManager.ps1 - Gestion des règles de nommage (sans module)

function Get-TemplatesPath {
    return Join-Path $PSScriptRoot "..\Data\templates.json"
}

function Get-Templates {
    try {
        $templatesPath = Get-TemplatesPath
        
        if (-not (Test-Path $templatesPath)) {
            Write-Host "Fichier templates.json non trouvé, création d'un fichier par défaut..." -ForegroundColor Yellow
            
            $defaultTemplates = @{
                templates = @(
                    @{
                        id = "certificat"
                        name = "CERTIFICAT"
                        description = "Certificat de destruction"
                        format = "Certificat de Destruction-{text}-du {date}"
                        dateFormat = "dd.MM.yy"
                        timeFormat = ""
                        includeTime = $false
                        placeholder = "Renseigner le point de collecte"
                        buttonColor = "#E26E2A"
                        borderColor = "#E26E2A"
                        enabled = $true
                    }
                )
            }
            
            $defaultJson = $defaultTemplates | ConvertTo-Json -Depth 10
            $defaultJson | Out-File -FilePath $templatesPath -Encoding utf8
        }
        
        $templatesData = Get-Content $templatesPath -Raw -ErrorAction Stop
        $templates = $templatesData | ConvertFrom-Json -ErrorAction Stop
        return $templates.templates
    }
    catch {
        Write-Host "Erreur lors du chargement des templates: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

function Save-Templates {
    param($Templates)
    
    try {
        $templatesPath = Get-TemplatesPath
        $data = @{ templates = $Templates } | ConvertTo-Json -Depth 10
        $data | Out-File -FilePath $templatesPath -Encoding utf8 -ErrorAction Stop
        return $true
    }
    catch {
        Write-Host "Erreur lors de la sauvegarde: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Add-Template {
    param($Template)
    
    try {
        $templates = Get-Templates
        $newId = [guid]::NewGuid().ToString().Substring(0, 8)
        $Template.id = $newId
        $templates += $Template
        Save-Templates -Templates $templates
        return $newId
    }
    catch {
        return $null
    }
}

function Update-Template {
    param($Id, $UpdatedTemplate)
    
    try {
        $templates = Get-Templates
        $index = -1
        for ($i = 0; $i -lt $templates.Count; $i++) {
            if ($templates[$i].id -eq $Id) {
                $index = $i
                break
            }
        }
        
        if ($index -ge 0) {
            $UpdatedTemplate.id = $Id
            $templates[$index] = $UpdatedTemplate
            Save-Templates -Templates $templates
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

function Remove-Template {
    param($Id)
    
    try {
        $templates = Get-Templates
        $newTemplates = $templates | Where-Object { $_.id -ne $Id }
        Save-Templates -Templates $newTemplates
        return $true
    }
    catch {
        return $false
    }
}

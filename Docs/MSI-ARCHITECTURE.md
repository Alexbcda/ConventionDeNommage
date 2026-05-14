# MSI Architecture - Convention de Nommage

## Document de conception - Phase 5 (Design Only)

---

## 1. Choix du framework : Inno Setup (Option 1 - Recommandee)

### Justification

| Critere                  | Inno Setup        | WiX Toolset       | Advanced Installer |
|--------------------------|-------------------|--------------------|--------------------|
| Cout                     | Gratuit (OSS)     | Gratuit (OSS)      | Payant             |
| Complexite               | Faible            | Elevee (XML)       | Faible (GUI)       |
| Support PowerShell       | Natif             | Via Custom Actions  | Limite             |
| Install silencieux       | /VERYSILENT       | /quiet             | /quiet             |
| Uninstall propre         | Natif             | Natif              | Natif              |
| Intune compatible        | .intunewin wrap   | .msi natif          | .msi natif         |
| SCCM compatible          | Oui (EXE + flags) | Oui (MSI natif)     | Oui                |
| GPO compatible           | Non (EXE)         | Oui (MSI natif)     | Oui                |
| Temps de mise en oeuvre   | 1-2 jours         | 3-5 jours          | 1-2 jours          |

**Decision** : Inno Setup est le meilleur compromis pour ce projet car :
- Le code source est 100% PowerShell (pas de compilation .NET)
- L'installation consiste a copier des fichiers + configurer
- Le support Intune/SCCM est assure via `.intunewin` wrapping
- La courbe d'apprentissage est minimale

**Note GPO** : Si GPO est un prerequis strict (`.msi` obligatoire), Inno Setup peut generer un `.msi` via le module `ispack` ou on peut migrer vers WiX.

---

## 2. Structure d'installation cible

### 2.1 Arborescence installee

```
C:\Program Files\ConventionDeNommage\          <- INSTALLDIR (read-only)
    Launcher.cmd                                <- Point d'entree
    src\                                        <- Code applicatif (60 .ps1)
        Main.ps1
        Bootstrap.ps1
        Config.ps1
        GUI.ps1
        Common\
        Core\
        Database\
        ODM\
        Services\
        Tools\
    lib\                                        <- DLLs SQLite
        System.Data.SQLite.dll
        SQLite.Interop.dll
        System.Data.SQLite.dll.config
        (+ EF6, Linq, Designer)
    Resources\                                  <- Assets visuels
        EliseE.ico
        *.svg
    runtime\                                    <- Outils PDF (bundled)
        ghostscript\
            bin\gswin64c.exe
        poppler\
            bin\pdftotext.exe
    install\                                    <- Script de validation
        Install.ps1

C:\ProgramData\ConventionDeNommage\            <- DATADIR (writable)
    config\
        runtime.json                            <- Configuration (modifiable)
    Data\
        gestion.db                              <- Base SQLite
        templates.json                          <- Templates metier
    Logs\
        app.log                                 <- Logs applicatifs
```

### 2.2 Separation Read-Only vs Writable

| Dossier                       | Emplacement       | Permissions           | Contenu                    |
|-------------------------------|-------------------|-----------------------|----------------------------|
| Code applicatif (src/)         | Program Files     | Read + Execute        | Scripts PowerShell         |
| Librairies (lib/)              | Program Files     | Read                  | DLLs SQLite                |
| Runtime tools (runtime/)       | Program Files     | Read + Execute        | Ghostscript, Poppler       |
| Resources (Resources/)         | Program Files     | Read                  | ICO, SVG                   |
| Configuration (config/)        | ProgramData       | Read + Write (Users)  | runtime.json               |
| Base de donnees (Data/)        | ProgramData       | Read + Write (Users)  | gestion.db, templates.json |
| Logs (Logs/)                   | ProgramData       | Write (Users)         | app.log                    |

### 2.3 Pourquoi ProgramData et pas AppData

- **ProgramData** = donnees partagees entre tous les utilisateurs du poste
- La base `gestion.db` est une base applicative commune (pas per-user)
- Les logs sont centralises
- La configuration runtime est commune a l'installation

---

## 3. Impact code existant (modifications requises pour Step 6)

Le code actuel utilise des chemins relatifs au script (`$PSScriptRoot`). L'installation dans Program Files + ProgramData necessite des adaptations mineures.

### 3.1 Fichiers a modifier

| Fichier                    | Modification                                           |
|----------------------------|--------------------------------------------------------|
| `src/Core/Logger.ps1`      | Resoudre logFile vers ProgramData si installe          |
| `src/Database/Database.ps1` | Resoudre DB path vers ProgramData si installe          |
| `src/Core/DependencyCheck.ps1` | Resoudre config vers ProgramData si installe       |
| `src/Core/GhostscriptResolve.ps1` | Ajouter lookup ProgramData pour config         |
| `src/ODM/.../PdfExtractor.ps1`     | Ajouter lookup ProgramData pour config         |

### 3.2 Strategie de resolution de chemin

```
function Get-AppDataRoot {
    # Priorite 1 : variable d'environnement (positionnee par l'installeur)
    $envPath = $env:CN_DATA_ROOT
    if (-not [string]::IsNullOrWhiteSpace($envPath) -and (Test-Path $envPath)) {
        return $envPath
    }

    # Priorite 2 : ProgramData (installation machine-wide)
    $pdPath = Join-Path $env:ProgramData 'ConventionDeNommage'
    if (Test-Path $pdPath) {
        return $pdPath
    }

    # Priorite 3 : relatif au script (mode developpement)
    $scriptRoot = $PSScriptRoot
    for ($i = 0; $i -lt 2; $i++) { $scriptRoot = Split-Path -Parent $scriptRoot }
    return $scriptRoot
}
```

Cette fonction permet au code de fonctionner dans les deux modes :
- **Mode dev** : chemins relatifs (comportement actuel, zero changement)
- **Mode installe** : ProgramData (active par l'installeur via CN_DATA_ROOT ou detection ProgramData)

---

## 4. Script Inno Setup - Specification

### 4.1 Metadata

```
[Setup]
AppName=Convention de Nommage
AppVersion=1.0.0
AppPublisher=Organisation
DefaultDirName={autopf}\ConventionDeNommage
DefaultGroupName=Convention de Nommage
OutputBaseFilename=ConventionDeNommage-Setup-1.0.0
Compression=lzma2/ultra64
SolidCompression=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\Resources\EliseE.ico
SetupIconFile=Resources\EliseE.ico
```

### 4.2 Fichiers a inclure

```
[Files]
; Code applicatif
Source: "src\*"; DestDir: "{app}\src"; Flags: recursesubdirs

; Librairies
Source: "lib\*"; DestDir: "{app}\lib"

; Resources
Source: "Resources\*"; DestDir: "{app}\Resources"

; Launcher
Source: "Launcher.cmd"; DestDir: "{app}"

; Install script
Source: "install\Install.ps1"; DestDir: "{app}\install"

; Schema SQL (reference)
Source: "src\Database\Schema.sql"; DestDir: "{app}\src\Database"

; Runtime Ghostscript (si bundle)
Source: "runtime\ghostscript\*"; DestDir: "{app}\runtime\ghostscript"; \
    Flags: recursesubdirs; Check: ShouldBundleGhostscript

; Runtime Poppler (si bundle)
Source: "runtime\poppler\*"; DestDir: "{app}\runtime\poppler"; \
    Flags: recursesubdirs; Check: ShouldBundlePoppler
```

### 4.3 Dossiers ProgramData (post-install)

```
[Dirs]
Name: "{commonappdata}\ConventionDeNommage\config"; Permissions: users-modify
Name: "{commonappdata}\ConventionDeNommage\Data"; Permissions: users-modify
Name: "{commonappdata}\ConventionDeNommage\Logs"; Permissions: users-modify
```

### 4.4 Configuration post-install

```
[Run]
; Generer runtime.json avec les chemins corrects
Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy RemoteSigned -Command ""& '{app}\install\PostInstall.ps1' -InstallDir '{app}' -DataDir '{commonappdata}\ConventionDeNommage'"""; \
    StatusMsg: "Configuration de l'application..."; \
    Flags: runhidden waituntilterminated
```

### 4.5 Raccourcis

```
[Icons]
; Menu Demarrer
Name: "{group}\Convention de Nommage"; \
    Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy RemoteSigned -File ""{app}\src\Main.ps1"""; \
    IconFilename: "{app}\Resources\EliseE.ico"; \
    WorkingDir: "{app}"

; Bureau (optionnel)
Name: "{commondesktop}\Convention de Nommage"; \
    Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy RemoteSigned -File ""{app}\src\Main.ps1"""; \
    IconFilename: "{app}\Resources\EliseE.ico"; \
    WorkingDir: "{app}"; \
    Tasks: desktopicon
```

### 4.6 Uninstall

```
[UninstallDelete]
; Fichiers generes au runtime
Type: filesandordirs; Name: "{commonappdata}\ConventionDeNommage\Logs"

[UninstallRun]
; Nettoyage optionnel ProgramData
Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy RemoteSigned -Command ""Remove-Item '{commonappdata}\ConventionDeNommage' -Recurse -Force -ErrorAction SilentlyContinue"""; \
    Flags: runhidden waituntilterminated; \
    RunOnceId: "CleanProgramData"
```

---

## 5. Runtime bundling - Strategie

### 5.1 Deux modes d'installation

| Mode              | Ghostscript                 | Poppler                     | Taille installer |
|-------------------|-----------------------------|-----------------------------|------------------|
| **Lite**          | Detecte sur le systeme      | Detecte sur le systeme      | ~3 MB            |
| **Full (bundle)** | Inclus dans runtime/        | Inclus dans runtime/        | ~50-80 MB        |

### 5.2 Logique de detection (install time)

```pascal
// Inno Setup Pascal Script
function IsGhostscriptInstalled: Boolean;
var
  gsPath: String;
begin
  Result := False;
  // Check Program Files
  if FileExists(ExpandConstant('{autopf}\gs\gs10.04.0\bin\gswin64c.exe')) then
    Result := True
  else if FileExists(ExpandConstant('{autopf}\PDF24\gs\bin\gswin64c.exe')) then
    Result := True
  else if RegQueryStringValue(HKLM, 'SOFTWARE\GPL Ghostscript', 'GS_DLL', gsPath) then
    Result := True;
end;

function ShouldBundleGhostscript: Boolean;
begin
  Result := not IsGhostscriptInstalled;
end;
```

### 5.3 Post-install : mise a jour runtime.json

Le script `PostInstall.ps1` genere `config/runtime.json` avec les chemins corrects :

```powershell
param(
    [string]$InstallDir,
    [string]$DataDir
)

$config = @{
    version        = "1.0"
    ghostscriptPath = ""
    popplerPath    = ""
    logLevel       = "INFO"
    installDir     = $InstallDir
    dataDir        = $DataDir
    deploymentMode = "installed"
}

# Detecter Ghostscript
$gsPath = Join-Path $InstallDir 'runtime\ghostscript\bin\gswin64c.exe'
if (Test-Path $gsPath) { $config.ghostscriptPath = $gsPath }

# Detecter Poppler
$ppPath = Join-Path $InstallDir 'runtime\poppler\bin\pdftotext.exe'
if (Test-Path $ppPath) { $config.popplerPath = $ppPath }

$cfgDir = Join-Path $DataDir 'config'
if (-not (Test-Path $cfgDir)) { New-Item $cfgDir -ItemType Directory -Force | Out-Null }
$config | ConvertTo-Json -Depth 2 | Set-Content (Join-Path $cfgDir 'runtime.json') -Encoding UTF8
```

---

## 6. Deploiement entreprise

### 6.1 Intune (Win32 App)

```
# Packaging
IntuneWinAppUtil.exe -c .\output -s ConventionDeNommage-Setup-1.0.0.exe -o .\intune

# Commande d'installation
ConventionDeNommage-Setup-1.0.0.exe /VERYSILENT /NORESTART /LOG="C:\Windows\Temp\CN-install.log"

# Commande de desinstallation
"{autopf}\ConventionDeNommage\unins000.exe" /VERYSILENT /NORESTART

# Detection rule
Path  : C:\Program Files\ConventionDeNommage\src\Main.ps1
Type  : File exists
```

### 6.2 SCCM / MECM

```
# Application model
Name             : Convention de Nommage 1.0
Content location : \\server\share\ConventionDeNommage\
Install program  : ConventionDeNommage-Setup-1.0.0.exe /VERYSILENT /NORESTART /LOG="%TEMP%\CN-install.log"
Uninstall        : "%ProgramFiles%\ConventionDeNommage\unins000.exe" /VERYSILENT
Detection method : File - C:\Program Files\ConventionDeNommage\src\Main.ps1 exists
User experience  : Install for system, whether or not user is logged on
```

### 6.3 GPO (si MSI necessaire)

Si GPO est un prerequis strict, deux options :
1. Convertir l'EXE Inno Setup en MSI via `exemsi.com` ou `InstEd`
2. Migrer vers WiX Toolset (effort supplementaire, cf. Section 9)

---

## 7. Mode silencieux - Parametres

| Parametre     | Effet                                      |
|---------------|---------------------------------------------|
| `/SILENT`     | Install avec barre de progression, pas de prompts |
| `/VERYSILENT` | Install completement invisible               |
| `/NORESTART`  | Pas de redemarrage automatique               |
| `/LOG=path`   | Journaliser l'installation                   |
| `/DIR=path`   | Changer le repertoire d'installation         |
| `/NOICONS`    | Ne pas creer de raccourcis                   |

### Commande d'installation complete (entreprise)

```cmd
ConventionDeNommage-Setup-1.0.0.exe /VERYSILENT /NORESTART /LOG="C:\Windows\Temp\CN-install.log" /SUPPRESSMSGBOXES
```

### Commande de desinstallation complete

```cmd
"C:\Program Files\ConventionDeNommage\unins000.exe" /VERYSILENT /NORESTART
```

---

## 8. Uninstall - Specification

### 8.1 Elements supprimes automatiquement

| Element                                 | Action                |
|-----------------------------------------|-----------------------|
| `C:\Program Files\ConventionDeNommage\` | Suppression complete  |
| Raccourcis Menu Demarrer                 | Suppression           |
| Raccourci Bureau                         | Suppression           |
| Registre (Uninstall key)                 | Suppression           |

### 8.2 Elements supprimes optionnellement

| Element                                     | Action                   |
|---------------------------------------------|--------------------------|
| `C:\ProgramData\ConventionDeNommage\Logs\`  | Suppression (RunOnceId)  |
| `C:\ProgramData\ConventionDeNommage\`       | Suppression si vide      |

### 8.3 Elements preserves intentionnellement

| Element                                     | Raison                   |
|---------------------------------------------|--------------------------|
| `C:\ProgramData\ConventionDeNommage\Data\`  | Base de donnees utilisateur |
| `C:\ProgramData\ConventionDeNommage\config\`| Configuration personnalisee |

> La base `gestion.db` contient des donnees metier. La suppression
> a l'uninstall est un choix de l'administrateur, pas de l'installeur.
> Un flag `/PURGE` pourrait etre ajoute pour un nettoyage total.

---

## 9. Alternative WiX (si MSI natif requis)

Si le deploiement GPO est un prerequis strict, le projet WiX suivrait cette structure :

```
installer/
    ConventionDeNommage.wxs         <- Produit principal
    Components/
        AppFiles.wxs                <- Fichiers applicatifs
        RuntimeFiles.wxs            <- Ghostscript + Poppler
        DataDirs.wxs                <- ProgramData structure
    Transforms/
        NoRuntime.mst               <- Transform pour skip runtime bundle
```

Effort supplementaire estime : 3-5 jours vs 1-2 jours pour Inno Setup.

---

## 10. Fichiers a creer (Step 6 - Implementation)

| Fichier                         | Role                                        |
|---------------------------------|---------------------------------------------|
| `installer/ConventionDeNommage.iss` | Script Inno Setup principal             |
| `installer/PostInstall.ps1`     | Configuration post-installation             |
| `installer/build-installer.cmd` | Script de build de l'installeur             |
| `src/Core/AppPaths.ps1`        | Resolution des chemins (dev vs installe)     |

### Prerequis pour le build

| Outil               | Version   | Role                              |
|----------------------|-----------|-----------------------------------|
| Inno Setup           | >= 6.2    | Compilation de l'installeur       |
| IntuneWinAppUtil.exe | Derniere  | Packaging Intune (optionnel)      |

---

## 11. Matrice de compatibilite

| Environnement                | Compatible | Notes                           |
|------------------------------|------------|---------------------------------|
| Windows 10 22H2 Enterprise   | Oui        | PowerShell 5.1 pre-installe     |
| Windows 11 23H2 Enterprise   | Oui        | PowerShell 5.1 pre-installe     |
| Windows 11 24H2 Enterprise   | Oui        | PowerShell 5.1 pre-installe     |
| Intune Win32 App             | Oui        | Via .intunewin                   |
| SCCM / MECM                  | Oui        | Via EXE silent install           |
| GPO Software Install         | Partiel    | Necessite conversion MSI ou WiX  |
| Poste sans admin local       | Oui        | Install machine-wide par IT      |
| Poste avec AppLocker          | Oui        | Scripts signes recommandes       |
| Poste avec WDAC               | Attention  | Necessite policy PowerShell      |

---

## 12. Diagramme d'installation

```
Installeur (EXE/MSI)
    |
    +-- Copie fichiers read-only --> C:\Program Files\ConventionDeNommage\
    |       src\, lib\, Resources\, runtime\, Launcher.cmd
    |
    +-- Cree structure writable --> C:\ProgramData\ConventionDeNommage\
    |       config\, Data\, Logs\
    |
    +-- Execute PostInstall.ps1
    |       Detecte runtime (GS, Poppler)
    |       Genere config\runtime.json avec chemins resolus
    |       Copie templates.json si premier install
    |
    +-- Cree raccourcis
    |       Menu Demarrer -> powershell.exe -File Main.ps1
    |       Bureau (optionnel)
    |
    +-- Registre
            HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ConventionDeNommage
```

```
Application au lancement
    |
    +-- Launcher.cmd
    |       powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File src\Main.ps1
    |
    +-- Main.ps1
    |       Get-AppDataRoot -> C:\ProgramData\ConventionDeNommage\
    |       DependencyCheck -> config\runtime.json (ProgramData)
    |       Initialize-Database -> Data\gestion.db (ProgramData)
    |       Logger -> Logs\app.log (ProgramData)
    |
    +-- GUI
            Fonctionnement normal
```

---

## 13. Checklist pre-implementation (Step 6)

- [ ] Creer `src/Core/AppPaths.ps1` (resolution dev vs installe)
- [ ] Modifier `Logger.ps1` pour utiliser AppPaths
- [ ] Modifier `Database.ps1` pour utiliser AppPaths
- [ ] Modifier `DependencyCheck.ps1` pour utiliser AppPaths
- [ ] Modifier `GhostscriptResolve.ps1` pour utiliser AppPaths
- [ ] Modifier `PdfExtractor.ps1` pour utiliser AppPaths
- [ ] Creer `installer/ConventionDeNommage.iss`
- [ ] Creer `installer/PostInstall.ps1`
- [ ] Creer `installer/build-installer.cmd`
- [ ] Tester install silencieux
- [ ] Tester uninstall propre
- [ ] Tester sur poste Windows standard (non-dev)
- [ ] Packager pour Intune (.intunewin)
- [ ] Documenter procedure SCCM

---

*Document genere le 2026-05-14 - Phase 5 Design Only*
*Implementation prevue en Step 6*

# Guide de deploiement IT - Convention de Nommage v1.0.0

## Architecture d'installation

```
C:\Program Files\ConventionDeNommage\       (read-only, code + runtime)
C:\ProgramData\ConventionDeNommage\         (writable, data + config + logs)
HKLM\SOFTWARE\ConventionDeNommage           (version, paths)
```

---

## 1. Commandes d'installation

### Installation silencieuse

```cmd
ConventionDeNommage-Setup-1.0.0.exe /VERYSILENT /NORESTART /LOG="%TEMP%\CN-install.log" /SUPPRESSMSGBOXES
```

### Desinstallation silencieuse

```cmd
"%ProgramFiles%\ConventionDeNommage\unins000.exe" /VERYSILENT /NORESTART
```

### Parametres optionnels

| Parametre        | Effet                                    |
|------------------|------------------------------------------|
| `/SILENT`        | Install avec barre de progression        |
| `/VERYSILENT`    | Install completement invisible           |
| `/NORESTART`     | Pas de redemarrage automatique           |
| `/LOG=path`      | Log d'installation dans le fichier       |
| `/DIR=path`      | Repertoire d'installation personnalise   |
| `/NOICONS`       | Pas de raccourcis                        |
| `/SUPPRESSMSGBOXES` | Pas de popups (mode entreprise)      |

---

## 2. Detection Rules

### Option A : Fichier (simple)

| Champ            | Valeur                                        |
|------------------|-----------------------------------------------|
| Path             | `C:\Program Files\ConventionDeNommage`        |
| File             | `Launcher.cmd`                                |
| Method           | File or folder exists                         |

### Option B : Registre (avec version)

| Champ            | Valeur                                              |
|------------------|-----------------------------------------------------|
| Hive             | HKEY_LOCAL_MACHINE                                  |
| Key              | `SOFTWARE\ConventionDeNommage`                      |
| Value            | `Version`                                           |
| Comparison       | String equals `1.0.0`                               |

Valeurs registre disponibles :

| ValueName     | Type   | Exemple                              |
|---------------|--------|--------------------------------------|
| Version       | String | `1.0.0`                              |
| InstallDir    | String | `C:\Program Files\ConventionDeNommage` |
| InstallPath   | String | `C:\Program Files\ConventionDeNommage` |
| DataDir       | String | `C:\ProgramData\ConventionDeNommage` |
| InstallDate   | String | `2026-05-14 22:30:00`                |

### Option C : Script PowerShell (recommande Intune)

Fichier : `deploy/intune/Detect-App.ps1`
- Verifie Launcher.cmd + Main.ps1 + registre
- Exit 0 + stdout = installe
- Exit 1 = non installe

---

## 3. Upgrade Strategy

### In-place upgrade (recommande)

L'installeur utilise un `AppId` fixe (`ConventionDeNommage`).
Inno Setup detecte automatiquement l'installation existante et la met a jour.

- Les fichiers `Program Files` sont ecrases
- Les donnees `ProgramData\Data\` sont preservees (jamais ecrasees par l'installeur)
- La cle registre `Version` est mise a jour
- `PostInstall.ps1` regenere `runtime.json` avec les chemins a jour

### Detection de l'ancienne version

Pour Intune supersedence ou SCCM requirements :

```powershell
$reg = Get-ItemProperty 'HKLM:\SOFTWARE\ConventionDeNommage' -ErrorAction SilentlyContinue
if ($reg.Version -lt '1.1.0') { exit 0 }   # Upgrade needed
exit 1                                       # Already up to date
```

### Forcer une reinstallation complete

```cmd
"%ProgramFiles%\ConventionDeNommage\unins000.exe" /VERYSILENT /NORESTART
timeout /t 5 /nobreak
ConventionDeNommage-Setup-1.1.0.exe /VERYSILENT /NORESTART /SUPPRESSMSGBOXES
```

---

## 4. Logging

| Type                | Emplacement                                       |
|---------------------|---------------------------------------------------|
| Installation        | `%TEMP%\CN-install.log` (parametre /LOG)          |
| Application runtime | `C:\ProgramData\ConventionDeNommage\Logs\app.log` |
| Intune agent        | `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\` |
| SCCM client         | `C:\Windows\CCM\Logs\AppEnforce.log`              |
| Health check        | stdout JSON (voir section 5)                      |

---

## 5. Health Check

Script : `deploy/Test-AppHealth.ps1`

```cmd
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "deploy\Test-AppHealth.ps1"
```

Verifie :
- Fichiers critiques (Launcher.cmd, Main.ps1, SQLite DLL)
- Structure ProgramData (config, Data, Logs)
- Configuration runtime.json
- Registre
- Ghostscript (optionnel)
- Poppler/pdftotext (optionnel)
- Permissions d'ecriture ProgramData

Sortie : JSON structure.

| Exit code | Signification              |
|-----------|----------------------------|
| 0         | HEALTHY                    |
| 1         | CRITICAL (erreur bloquante)|
| 2         | WARNING (non-bloquant)     |

Log fichier optionnel :
```cmd
powershell.exe -NoProfile -File Test-AppHealth.ps1 -LogFile "C:\ProgramData\ConventionDeNommage\Logs\healthcheck.log"
```

---

## 6. Deploiement Intune

Voir `deploy/intune/README-INTUNE.md` pour le guide detaille.

Resume rapide :
1. Builder l'installeur : `installer\build-installer.cmd`
2. Packager : `IntuneWinAppUtil.exe -c source -s ConventionDeNommage-Setup-1.0.0.exe -o output`
3. Uploader dans Intune > Apps > Windows > Win32
4. Configurer install/uninstall/detection (voir README)
5. Assigner aux groupes d'appareils

---

## 7. Deploiement SCCM / MECM

Voir `deploy/sccm/README-SCCM.md` pour le guide detaille.

Resume rapide :
1. Copier l'installeur dans le share reseau
2. Creer Application > Deployment Type > Script Installer
3. Configurer detection method (fichier ou registre)
4. Deployer sur la collection cible

---

## 8. GPO (optionnel)

GPO Software Installation requiert un `.msi` natif.
Deux approches :

1. **EXE via startup script** : Creer un script GPO qui execute l'installeur silencieusement
2. **Conversion MSI** : Utiliser un outil tiers pour wrapper l'EXE en MSI

### Script GPO startup

```cmd
@echo off
if exist "%ProgramFiles%\ConventionDeNommage\Launcher.cmd" exit /b 0
"\\server\share$\ConventionDeNommage-Setup-1.0.0.exe" /VERYSILENT /NORESTART /SUPPRESSMSGBOXES /LOG="%TEMP%\CN-gpo-install.log"
```

Configurer dans : Computer Configuration > Policies > Windows Settings > Scripts > Startup

---

## 9. Prerequis systeme

| Element           | Requis                   |
|-------------------|--------------------------|
| OS                | Windows 10/11 64-bit     |
| PowerShell        | 5.1 (pre-installe)      |
| .NET Framework    | 4.7.2+ (pre-installe)   |
| Espace disque     | 100 MB (Lite), 200 MB (Full) |
| Droits admin      | Oui (installation uniquement) |
| Acces internet    | Non requis               |

---

## 10. Contacts et support

Pour tout probleme de deploiement :
1. Verifier les logs d'installation (`%TEMP%\CN-install.log`)
2. Executer le health check (`Test-AppHealth.ps1`)
3. Verifier les logs applicatifs (`ProgramData\ConventionDeNommage\Logs\app.log`)

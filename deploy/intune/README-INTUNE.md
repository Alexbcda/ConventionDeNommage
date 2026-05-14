# Deploiement Intune - Convention de Nommage

## Prerequis

- Microsoft Win32 Content Prep Tool (`IntuneWinAppUtil.exe`)
  - Telechargement : https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool
- Installateur `ConventionDeNommage-Setup-1.0.0.exe` (genere par `installer\build-installer.cmd`)

## 1. Creer le package .intunewin

```cmd
IntuneWinAppUtil.exe ^
    -c ".\source" ^
    -s "ConventionDeNommage-Setup-1.0.0.exe" ^
    -o ".\output" ^
    -q
```

Ou :
- `-c` : dossier contenant l'installeur
- `-s` : nom du fichier source
- `-o` : dossier de sortie
- `-q` : mode silencieux

## 2. Configuration dans Intune

### App Information

| Champ       | Valeur                         |
|-------------|--------------------------------|
| Name        | Convention de Nommage          |
| Publisher   | Organisation                   |
| Version     | 1.0.0                          |
| Category    | Business                       |

### Program

| Champ              | Valeur                                                                                           |
|--------------------|--------------------------------------------------------------------------------------------------|
| Install command    | `ConventionDeNommage-Setup-1.0.0.exe /VERYSILENT /NORESTART /LOG="%TEMP%\CN-install.log" /SUPPRESSMSGBOXES` |
| Uninstall command  | `"%ProgramFiles%\ConventionDeNommage\unins000.exe" /VERYSILENT /NORESTART`                       |
| Install behavior   | System                                                                                           |
| Device restart     | No action                                                                                        |

### Requirements

| Champ                   | Valeur             |
|-------------------------|--------------------|
| OS architecture         | 64-bit             |
| Minimum OS              | Windows 10 1903    |
| Disk space (MB)         | 100                |
| Additional requirements | PowerShell 5.1     |

### Detection Rules

**Option A : Script (recommande)**

Utiliser `Detect-App.ps1` fourni dans ce dossier.
- Script type : PowerShell
- Enforce signature check : No
- Run script in 64-bit context : Yes

**Option B : File detection**

| Champ            | Valeur                                        |
|------------------|-----------------------------------------------|
| Path             | `C:\Program Files\ConventionDeNommage`        |
| File or folder   | `Launcher.cmd`                                |
| Detection method | File or folder exists                         |

**Option C : Registry detection**

| Champ            | Valeur                                        |
|------------------|-----------------------------------------------|
| Key path         | `HKEY_LOCAL_MACHINE\SOFTWARE\ConventionDeNommage` |
| Value name       | `Version`                                     |
| Detection method | String comparison / Equals                    |
| Value            | `1.0.0`                                       |

### Return Codes

| Code | Type    | Signification           |
|------|---------|-------------------------|
| 0    | Success | Installation reussie    |
| 1707 | Success | Installation reussie    |
| 3010 | Soft reboot | Redemarrage conseille |
| 1603 | Failed  | Echec installation      |
| 1618 | Retry   | Autre install en cours  |

## 3. Upgrade Strategy

L'installeur Inno Setup gere nativement les mises a jour :
- Meme `AppId` = upgrade in-place (ecrase les fichiers)
- ProgramData preserve (la base gestion.db n'est jamais ecrasee)
- La cle de registre `Version` est mise a jour automatiquement

Pour forcer une reinstallation complete :
```
ConventionDeNommage-Setup-1.0.0.exe /VERYSILENT /NORESTART /SUPPRESSMSGBOXES
```

## 4. Logs

| Log                          | Emplacement                              |
|------------------------------|------------------------------------------|
| Install log                  | `%TEMP%\CN-install.log`                  |
| App runtime log              | `C:\ProgramData\ConventionDeNommage\Logs\app.log` |
| Intune management extension  | `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\` |

## 5. Scripts additionnels fournis

### Install-Wrapper.ps1

Wrapper PowerShell pour install/uninstall avec logging dans ProgramData :
```
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File Install-Wrapper.ps1 -Action install
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File Install-Wrapper.ps1 -Action uninstall
```
Logs ecrits dans `C:\ProgramData\ConventionDeNommage\Logs\install-*.log`

### Check-Upgrade.ps1

Verifie si une mise a jour est necessaire (requirement rule) :
```
powershell.exe -NoProfile -File Check-Upgrade.ps1 -TargetVersion "1.1.0"
```
Exit 0 = upgrade necessaire, Exit 1 = deja a jour.

## 6. Health Check

Executer `Test-AppHealth.ps1` (dans `deploy/`) :
```powershell
powershell.exe -NoProfile -File Test-AppHealth.ps1 -LogFile "C:\ProgramData\ConventionDeNommage\Logs\healthcheck.log"
```

| Exit code | Signification |
|-----------|---------------|
| 0         | HEALTHY       |
| 1         | CRITICAL (blocking) |
| 2         | WARNING (non-blocking) |

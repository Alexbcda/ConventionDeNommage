# Deploiement SCCM / MECM - Convention de Nommage

## 1. Application Model

### General

| Champ              | Valeur                        |
|--------------------|-------------------------------|
| Name               | Convention de Nommage         |
| Publisher          | Organisation                  |
| Software version   | 1.0.0                         |
| Administrative category | Business Applications    |

### Deployment Type : Script Installer

| Champ                      | Valeur                                                                                           |
|----------------------------|--------------------------------------------------------------------------------------------------|
| Content location           | `\\server\share$\Software\ConventionDeNommage\`                                                 |
| Installation program       | `ConventionDeNommage-Setup-1.0.0.exe /VERYSILENT /NORESTART /LOG="%TEMP%\CN-install.log" /SUPPRESSMSGBOXES` |
| Uninstall program          | `"%ProgramFiles%\ConventionDeNommage\unins000.exe" /VERYSILENT /NORESTART`                       |
| Installation behavior      | Install for system                                                                               |
| Logon requirement          | Whether or not a user is logged on                                                               |
| Installation time (max)    | 15 minutes                                                                                       |
| Allow user interaction     | No                                                                                               |

### Detection Method

**Methode 1 : File system (recommande)**

| Champ     | Valeur                                        |
|-----------|-----------------------------------------------|
| Type      | File System                                   |
| Path      | `%ProgramFiles%\ConventionDeNommage`          |
| File name | `Launcher.cmd`                                |
| Property  | File or folder exists                         |

**Methode 2 : Registry**

| Champ          | Valeur                                              |
|----------------|-----------------------------------------------------|
| Hive           | HKEY_LOCAL_MACHINE                                  |
| Key            | `SOFTWARE\ConventionDeNommage`                      |
| Value          | `Version`                                           |
| Data type      | String                                              |
| Operator       | Equals                                              |
| Value          | `1.0.0`                                             |

### Requirements

| Champ                   | Valeur                 |
|-------------------------|------------------------|
| Operating system        | Windows 10 (64-bit), Windows 11 (64-bit) |
| Disk space              | 100 MB                 |
| Primary device          | No                     |

### Return Codes

| Code | Name             | Type    |
|------|------------------|---------|
| 0    | Success          | Success |
| 1707 | Success          | Success |
| 3010 | Soft Reboot      | Soft Reboot |
| 1603 | Fatal Error      | Failure |
| 1618 | Already Running  | Fast Retry |

## 2. Distribution Point

Copier dans le share reseau :
```
\\server\share$\Software\ConventionDeNommage\
    ConventionDeNommage-Setup-1.0.0.exe
```

## 3. Collection Targeting

| Type          | Cible recommandee                    |
|---------------|--------------------------------------|
| Device        | All Windows 10/11 Workstations       |
| User          | (non recommande - install per-machine) |
| Pilot         | Collection pilote IT                  |

## 4. Deployment Settings

| Champ              | Valeur             |
|--------------------|--------------------|
| Action             | Install             |
| Purpose            | Required            |
| Pre-deploy behavior | Close running apps |
| Deadline behavior   | Schedule ASAP      |

## 5. Upgrade Strategy

- Meme `AppId` Inno Setup = upgrade automatique (in-place)
- Detection rule par version registre : changer de `1.0.0` a `1.1.0`
- Supersedence : creer la v1.1.0 qui supersede la v1.0.0

## 6. Logs

| Log                          | Emplacement                              |
|------------------------------|------------------------------------------|
| Install log                  | `%TEMP%\CN-install.log`                  |
| SCCM client log              | `C:\Windows\CCM\Logs\AppEnforce.log`    |
| App runtime log              | `C:\ProgramData\ConventionDeNommage\Logs\app.log` |

## 7. Compliance / Health Check

Utiliser `Test-AppHealth.ps1` comme Configuration Baseline :
- Type : Script
- Execution context : System
- Expected exit code : 0
- Remediation : re-deploy

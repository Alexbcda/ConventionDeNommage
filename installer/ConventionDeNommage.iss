; =============================================================================
; ConventionDeNommage.iss - Inno Setup Script
; Installateur entreprise pour Convention de Nommage
;
; Build : iscc.exe ConventionDeNommage.iss
; Modes : Lite (sans runtime) ou Full (avec Ghostscript + Poppler)
;
; Pour builder en mode Full, definir BUNDLE_RUNTIME :
;   iscc.exe /DBUNDLE_RUNTIME ConventionDeNommage.iss
; =============================================================================

#define MyAppName "Convention de Nommage"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Organisation"
#define MyAppExeName "Launcher.cmd"
#define MyAppId "ConventionDeNommage"
#define MySourceDir ".."

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppSupportURL=
DefaultDirName={autopf}\ConventionDeNommage
DefaultGroupName={#MyAppName}
OutputDir={#MySourceDir}\output
OutputBaseFilename=ConventionDeNommage-Setup-{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\Resources\EliseE.ico
SetupIconFile={#MySourceDir}\Resources\EliseE.ico
WizardStyle=modern
MinVersion=10.0
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Creer un raccourci sur le Bureau"; GroupDescription: "Raccourcis :"; Flags: unchecked

; =============================================================================
; FILES - Code applicatif (read-only dans Program Files)
; =============================================================================
[Files]
; Point d'entree
Source: "{#MySourceDir}\Launcher.cmd"; DestDir: "{app}"; Flags: ignoreversion

; Code PowerShell
Source: "{#MySourceDir}\src\*"; DestDir: "{app}\src"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.old,Logs\*"

; Librairies SQLite
Source: "{#MySourceDir}\lib\System.Data.SQLite.dll"; DestDir: "{app}\lib"; Flags: ignoreversion
Source: "{#MySourceDir}\lib\SQLite.Interop.dll"; DestDir: "{app}\lib"; Flags: ignoreversion
Source: "{#MySourceDir}\lib\System.Data.SQLite.dll.config"; DestDir: "{app}\lib"; Flags: ignoreversion
Source: "{#MySourceDir}\lib\System.Data.SQLite.EF6.dll"; DestDir: "{app}\lib"; Flags: ignoreversion
Source: "{#MySourceDir}\lib\System.Data.SQLite.Linq.dll"; DestDir: "{app}\lib"; Flags: ignoreversion

; Resources (icone, SVG)
Source: "{#MySourceDir}\Resources\*"; DestDir: "{app}\Resources"; Flags: ignoreversion

; Script de validation / diagnostic
Source: "{#MySourceDir}\install\Install.ps1"; DestDir: "{app}\install"; Flags: ignoreversion

; Post-installation script
Source: "{#MySourceDir}\installer\PostInstall.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion

; Configuration template (copie initiale dans ProgramData via PostInstall)
Source: "{#MySourceDir}\config\runtime.json"; DestDir: "{app}\config"; Flags: ignoreversion

; Templates metier
Source: "{#MySourceDir}\Data\templates.json"; DestDir: "{app}\Data"; Flags: ignoreversion

; Schema SQL (reference)
Source: "{#MySourceDir}\src\Database\Schema.sql"; DestDir: "{app}\src\Database"; Flags: ignoreversion

; --- Runtime Ghostscript (mode Full uniquement) ---
#ifdef BUNDLE_RUNTIME
Source: "{#MySourceDir}\runtime\ghostscript\*"; DestDir: "{app}\runtime\ghostscript"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: ".gitkeep"
Source: "{#MySourceDir}\runtime\poppler\*"; DestDir: "{app}\runtime\poppler"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: ".gitkeep"
#endif

; =============================================================================
; DIRS - Structure ProgramData (writable par les utilisateurs)
; =============================================================================
[Dirs]
Name: "{commonappdata}\ConventionDeNommage"; Permissions: users-modify
Name: "{commonappdata}\ConventionDeNommage\config"; Permissions: users-modify
Name: "{commonappdata}\ConventionDeNommage\Data"; Permissions: users-modify
Name: "{commonappdata}\ConventionDeNommage\Logs"; Permissions: users-modify
Name: "{commonappdata}\ConventionDeNommage\Cache"; Permissions: users-modify

; =============================================================================
; ICONS - Raccourcis
; =============================================================================
[Icons]
; Menu Demarrer
Name: "{group}\{#MyAppName}"; \
    Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File ""{app}\src\Main.ps1"""; \
    IconFilename: "{app}\Resources\EliseE.ico"; \
    WorkingDir: "{app}"; \
    Comment: "Lancer Convention de Nommage"

; Bureau (optionnel)
Name: "{commondesktop}\{#MyAppName}"; \
    Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File ""{app}\src\Main.ps1"""; \
    IconFilename: "{app}\Resources\EliseE.ico"; \
    WorkingDir: "{app}"; \
    Tasks: desktopicon; \
    Comment: "Lancer Convention de Nommage"

; Desinstallation dans le menu
Name: "{group}\Desinstaller {#MyAppName}"; \
    Filename: "{uninstallexe}"; \
    IconFilename: "{app}\Resources\EliseE.ico"

; =============================================================================
; RUN - Post-installation
; =============================================================================
[Run]
Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy RemoteSigned -File ""{app}\installer\PostInstall.ps1"" -InstallDir ""{app}"" -DataDir ""{commonappdata}\ConventionDeNommage"""; \
    StatusMsg: "Configuration de l'application..."; \
    Flags: runhidden waituntilterminated

; Lancer l'application apres installation (optionnel)
Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File ""{app}\src\Main.ps1"""; \
    Description: "Lancer Convention de Nommage"; \
    Flags: nowait postinstall skipifsilent unchecked; \
    WorkingDir: "{app}"

; =============================================================================
; UNINSTALL - Nettoyage
; =============================================================================
[UninstallDelete]
; Logs (toujours supprimes)
Type: filesandordirs; Name: "{commonappdata}\ConventionDeNommage\Logs"
; Cache (toujours supprime)
Type: filesandordirs; Name: "{commonappdata}\ConventionDeNommage\Cache"

[UninstallRun]
; Nettoyage ProgramData (supprime config + structure, preserve Data)
Filename: "powershell.exe"; \
    Parameters: "-NoProfile -ExecutionPolicy RemoteSigned -Command ""$root = '{commonappdata}\ConventionDeNommage'; Remove-Item (Join-Path $root 'config') -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item (Join-Path $root 'Cache') -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item (Join-Path $root 'Logs') -Recurse -Force -ErrorAction SilentlyContinue; if ((Get-ChildItem $root -Force -ErrorAction SilentlyContinue | Where-Object Name -ne 'Data' | Measure-Object).Count -eq 0 -and -not (Test-Path (Join-Path $root 'Data\gestion.db'))) { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }"""; \
    Flags: runhidden waituntilterminated; \
    RunOnceId: "CleanProgramData"

; =============================================================================
; REGISTRY - Metadata d'installation
; =============================================================================
[Registry]
Root: HKLM; Subkey: "SOFTWARE\{#MyAppId}"; ValueType: string; ValueName: "InstallDir"; ValueData: "{app}"; Flags: uninsdeletekey
Root: HKLM; Subkey: "SOFTWARE\{#MyAppId}"; ValueType: string; ValueName: "InstallPath"; ValueData: "{app}"; Flags: uninsdeletekey
Root: HKLM; Subkey: "SOFTWARE\{#MyAppId}"; ValueType: string; ValueName: "DataDir"; ValueData: "{commonappdata}\ConventionDeNommage"; Flags: uninsdeletekey
Root: HKLM; Subkey: "SOFTWARE\{#MyAppId}"; ValueType: string; ValueName: "Version"; ValueData: "{#MyAppVersion}"; Flags: uninsdeletekey
Root: HKLM; Subkey: "SOFTWARE\{#MyAppId}"; ValueType: string; ValueName: "InstallDate"; ValueData: "{code:GetInstallDate}"; Flags: uninsdeletekey

; =============================================================================
; CODE - Validations Pascal Script
; =============================================================================
[Code]

function GetInstallDate(Param: String): String;
begin
  Result := GetDateTimeString('yyyy-MM-dd HH:mm:ss', '-', ':');
end;

function InitializeSetup: Boolean;
begin
  Result := True;
  if not FileExists(ExpandConstant('{#MySourceDir}\src\Main.ps1')) then
  begin
    MsgBox('ERREUR : src\Main.ps1 introuvable.' + #13#10 + 'L''installateur est incomplet.', mbCriticalError, MB_OK);
    Result := False;
    Exit;
  end;
  if not FileExists(ExpandConstant('{#MySourceDir}\Launcher.cmd')) then
  begin
    MsgBox('ERREUR : Launcher.cmd introuvable.' + #13#10 + 'L''installateur est incomplet.', mbCriticalError, MB_OK);
    Result := False;
    Exit;
  end;
  if not FileExists(ExpandConstant('{#MySourceDir}\config\runtime.json')) then
  begin
    MsgBox('ERREUR : config\runtime.json introuvable.' + #13#10 + 'L''installateur est incomplet.', mbCriticalError, MB_OK);
    Result := False;
    Exit;
  end;
end;

function IsGhostscriptDetected: Boolean;
var
  gsPath: String;
begin
  Result := False;
  if FileExists(ExpandConstant('{autopf}\PDF24\gs\bin\gswin64c.exe')) then
    Result := True
  else if FileExists(ExpandConstant('{autopf}\Ghostscript\bin\gswin64c.exe')) then
    Result := True
  else if RegQueryStringValue(HKLM, 'SOFTWARE\GPL Ghostscript', 'GS_DLL', gsPath) then
  begin
    if gsPath <> '' then
      Result := True;
  end;
  if not Result then
  begin
    if DirExists(ExpandConstant('{autopf}\gs')) then
      Result := True;
  end;
end;

function IsPopplerDetected: Boolean;
begin
  Result := FileExists(ExpandConstant('{autopf}\Xpdf\pdftotext.exe'));
  if not Result then
    Result := FileExists(ExpandConstant('{localappdata}\Microsoft\WinGet\Links\pdftotext.exe'));
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  msg: String;
begin
  if CurStep = ssPostInstall then
  begin
    msg := '';
    if not IsGhostscriptDetected then
    begin
      #ifdef BUNDLE_RUNTIME
      if not FileExists(ExpandConstant('{app}\runtime\ghostscript\bin\gswin64c.exe')) then
        msg := msg + '- Ghostscript non disponible (fusion PDF desactivee)' + #13#10;
      #else
        msg := msg + '- Ghostscript non detecte sur le systeme (fusion PDF desactivee)' + #13#10;
      #endif
    end;
    if not IsPopplerDetected then
    begin
      #ifdef BUNDLE_RUNTIME
      if not FileExists(ExpandConstant('{app}\runtime\poppler\bin\pdftotext.exe')) then
        msg := msg + '- pdftotext non disponible (extraction PDF desactivee)' + #13#10;
      #else
        msg := msg + '- pdftotext non detecte sur le systeme (extraction PDF desactivee)' + #13#10;
      #endif
    end;
    if msg <> '' then
    begin
      if not WizardSilent then
        MsgBox('Avertissement :'#13#10#13#10 + msg + #13#10 + 'Les fonctionnalites PDF seront limitees.' + #13#10 + 'Vous pouvez placer les outils dans le dossier runtime\ apres installation.', mbInformation, MB_OK);
    end;
  end;
end;

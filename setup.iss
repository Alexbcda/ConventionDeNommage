[Setup]
AppName=Convention de nommage
AppVersion=1.0
VersionInfoCompany=Alex
AppPublisher=Alex
DefaultDirName={localappdata}\ConventionDeNommage
OutputBaseFilename=ConventionDeNommageSetup
OutputDir=Output
Compression=lzma
SolidCompression=yes
PrivilegesRequired=lowest
SetupIconFile=Resources\EliseE.ico
AppId={{8E2F8E2F-8E2F-8E2F-8E2F-8E2F8E2F8E2F}}
UninstallDisplayIcon={app}\Resources\EliseE.ico
VersionInfoVersion=1.0.0.0
VersionInfoDescription=Outil de convention de nommage pour fichiers PDF

; Définir la langue française par défaut
ShowLanguageDialog=yes

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Dirs]
Name: "{app}\src"
Name: "{app}\src\Functions"
Name: "{app}\Resources"

[Files]
Source: "Launcher.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "src\Main.ps1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "src\Config.ps1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "src\GUI.ps1"; DestDir: "{app}\src"; Flags: ignoreversion
Source: "src\Functions\*.ps1"; DestDir: "{app}\src\Functions"; Flags: recursesubdirs ignoreversion
Source: "Resources\*"; DestDir: "{app}\Resources"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{autoprograms}\Convention de nommage"; Filename: "wscript.exe"; Parameters: """{app}\Launcher.vbs"""; IconFilename: "{app}\Resources\EliseE.ico"; Comment: "Outil de renommage de fichiers PDF"
Name: "{autodesktop}\Convention de nommage"; Filename: "wscript.exe"; Parameters: """{app}\Launcher.vbs"""; IconFilename: "{app}\Resources\EliseE.ico"
Name: "{autoprograms}\Désinstaller Convention de nommage"; Filename: "{uninstallexe}"

[Registry]
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.pdf\shell\ConventionNom"; ValueType: string; ValueName: "MUIVerb"; ValueData: "Convention de nommage"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.pdf\shell\ConventionNom"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\Resources\EliseE.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.pdf\shell\ConventionNom\command"; ValueType: string; ValueData: """wscript.exe"" ""{app}\Launcher.vbs"" ""%1"""; Flags: uninsdeletekey

[UninstallDelete]
Type: files; Name: "{app}\*.tmp"
Type: dirifempty; Name: "{app}\src\Functions"
Type: dirifempty; Name: "{app}\src"
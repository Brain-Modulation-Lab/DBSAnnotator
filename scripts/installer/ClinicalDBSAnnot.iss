; Inno Setup script for ClinicalDBSAnnot
; Build step: python scripts\build_windows.py --onedir

#define AppName "Clinical DBS Annotator"
#define AppId "ClinicalDBSAnnot"
#define AppVersion "0.1"
#define AppPublisher "BML"
#define AppExeName "ClinicalDBSAnnot_v0_1.exe"
#define BuildDir "dist\\ClinicalDBSAnnot_v0_1"

[Setup]
AppId={{#AppId}}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\\{#AppId}
DefaultGroupName={#AppName}
OutputDir=dist\\installer
OutputBaseFilename=ClinicalDBSAnnot_Setup_{#AppVersion}
SetupIconFile=icons\\logoneutral.ico
UninstallDisplayIcon={app}\\{#AppExeName}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
; Copy PyInstaller onedir build
Source: "{#BuildDir}\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\\{#AppName}"; Filename: "{app}\\{#AppExeName}"
Name: "{commondesktop}\\{#AppName}"; Filename: "{app}\\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

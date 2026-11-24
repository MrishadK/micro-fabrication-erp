; Script generated for Inno Setup 6
; Single-file Professional Installer and Updater for MICRO Manager (Windows Desktop)
; Full Code Obfuscation & Secure Release

#define MyAppName "MICRO Manager"
#define MyAppVersion "0.2.3"
#define MyAppPublisher "MICRO Fabrication ERP"
#define MyAppExeName "micro.exe"

[Setup]
; Unique GUID for version upgrades, in-place updates, and uninstallation
AppId={{8B91D245-7E3B-426B-94F5-19AC43DF9A42}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} v{#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\MICRO Manager
DefaultGroupName={#MyAppName}
AllowNoIcons=yes

; In-place updater & directory settings: allow user to browse and change destination
DisableDirPage=no
AlwaysShowDirOnReadyPage=yes
UsePreviousAppDir=yes
UsePreviousGroup=yes
UsePreviousTasks=yes

; Gracefully close running app during update to prevent file locks
CloseApplications=force
CloseApplicationsFilter={#MyAppExeName}
RestartApplications=no

; Output configuration
OutputDir=..\dist
OutputBaseFilename=MICRO_Manager_Setup_v0.2.3
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

; Highest possible compression for minimal single .exe file size
Compression=lzma2/ultra64
SolidCompression=yes

; Modern Windows installer styling
WizardStyle=modern
WizardSizePercent=100
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible

; Require Administrator privileges for Program Files write access and file replacement
PrivilegesRequired=admin
DisableProgramGroupPage=yes

; Windows Explorer File Metadata & Properties (Publishable Signature Info)
VersionInfoVersion=0.2.3.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Setup & Updater
VersionInfoProductName={#MyAppName}
VersionInfoCopyright=Copyright (C) 2026 {#MyAppPublisher}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Package all compiled release binaries, assets, dlls, and data from Release folder
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; IconFilename: "{app}\{#MyAppExeName}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent


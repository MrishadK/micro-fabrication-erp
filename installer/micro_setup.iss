; Script generated for Inno Setup 6
; Single-file Professional Installer for MICRO Manager (Windows Desktop)
; Obfuscated & Secured Release

#define MyAppName "MICRO Manager"
#define MyAppVersion "0.2.3"
#define MyAppPublisher "MICRO Fabrication ERP"
#define MyAppExeName "micro.exe"

[Setup]
; Unique GUID for version upgrades and uninstallation
AppId={{8B91D245-7E3B-426B-94F5-19AC43DF9A42}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} v{#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\MICRO Manager
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
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
; Privilege elevation: install for current user or all users cleanly
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DisableProgramGroupPage=yes
CloseApplications=yes
RestartApplications=no

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

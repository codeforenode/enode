; eNode Windows installer. Compiled by tool\package_windows.ps1 -Installer (do not run ISCC by hand).
[Setup]
AppId=AF02C4E9-BE51-48EA-8635-36C2DCB3B54A
AppName=eNode
AppVersion={#AppVersion}
AppPublisher=eNode
DefaultDirName={autopf}\eNode
DefaultGroupName=eNode
DisableProgramGroupPage=yes
OutputDir={#OutDir}
OutputBaseFilename=eNode-{#AppVersion}-win-x64-setup
SetupIconFile={#IcoFile}
UninstallDisplayIcon={app}\eNode.exe
Compression=lzma2/max
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\eNode"; Filename: "{app}\eNode.exe"
Name: "{group}\Uninstall eNode"; Filename: "{uninstallexe}"
Name: "{autodesktop}\eNode"; Filename: "{app}\eNode.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\eNode.exe"; Description: "{cm:LaunchProgram,eNode}"; Flags: nowait postinstall skipifsilent

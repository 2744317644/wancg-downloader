; wnacg 下载器 Windows installer (Inno Setup 6)
; Build: ISCC.exe /DMyAppVersion=1.0.4 wnacg.iss
; Expects the published app in ..\dist\WnacgDownloader-win-x64\

#define MyAppName "wnacg 下载器"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.4"
#endif
#define MyAppPublisher "wnacg"
#define MyAppExeName "WnacgDownloader.exe"
#define MyAppId "{{8F4C2B5E-2D3A-4C7B-9F1A-6B8D0E2C4A31}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\wnacg
DefaultGroupName=wnacg
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\dist
OutputBaseFilename=WnacgDownloader-Setup-{#MyAppVersion}
SetupIconFile=..\WnacgDownloader\Assets\app.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
CloseApplications=yes
SetupLogging=yes
VersionInfoVersion={#MyAppVersion}
VersionInfoDescription=wnacg 下载器安装程序
VersionInfoProductName={#MyAppName}
VersionInfoCompany={#MyAppPublisher}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\dist\WnacgDownloader-win-x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\wnacg 下载器"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\wnacg 下载器"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 wnacg 下载器"; Flags: nowait postinstall skipifsilent

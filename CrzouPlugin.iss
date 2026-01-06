; Crzou Plugin Installer (Inno Setup 5)
; Installs:
; - cdr-plugin.cpg -> <CorelDraw>\Draw\Plugins64\
; - cut-tool.exe   -> <CorelDraw>\Draw\Plugins64\Crzou Files\
;
; Inno Setup path on your machine: D:\Program Files (x86)\Inno Setup 5

[Setup]
AppName=Crzou Plugin
AppVersion=1.0.0
DefaultDirName={code:GetPlugins64Dir}
DisableDirPage=yes
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename=CrzouPluginSetup
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
LanguageDetectionMethod=uilanguage
SetupIconFile=..\cdr-plugin\res\crzouplay.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "portuguese"; MessagesFile: "compiler:Languages\Portuguese.isl"

[Files]
; 注意：Source 路径是相对本 .iss 文件的位置
Source: "..\cdr-plugin\bin\x64\Release\cdr-plugin.cpg"; DestDir: "{code:GetPlugins64Dir}"; Flags: ignoreversion
Source: "..\cdr-plugin\bin\x64\Release\cut-tool.exe";   DestDir: "{code:GetCrzouFilesDir}"; Flags: ignoreversion
Source: "..\cdr-plugin\bin\x64\Release\uninstaller.exe"; DestDir: "{code:GetPlugins64Dir}"; Flags: ignoreversion

[Dirs]
Name: "{code:GetCrzouFilesDir}"

[Code]
var
  DetectedDrawDir: string;
  VersionSelectionPage: TWizardPage;
  VersionCheckBoxes: array of TCheckBox;
  CorelDrawVersions: TStringList;  // 存储显示文本（仅版本名，不包含路径）
  CorelDrawPaths: TStringList;     // 存储对应的路径
  SelectedDrawDirs: TStringList;   // 存储用户选择的多个路径

// 根据当前语言获取多语言文本
function GetLocalizedString(const EnglishText, ChineseText, PortugueseText: string): string;
begin
  if ActiveLanguage = 'chinesesimplified' then
    Result := ChineseText
  else if ActiveLanguage = 'portuguese' then
    Result := PortugueseText
  else
    Result := EnglishText;
end;

function EnsureTrailingBackslash(const S: string): string;
begin
  Result := S;
  if (Result <> '') and (Result[Length(Result)] <> '\') then
    Result := Result + '\';
end;

function RemoveTrailingBackslash(const S: string): string;
begin
  Result := S;
  while (Length(Result) > 0) and (Result[Length(Result)] = '\') do
    Delete(Result, Length(Result), 1);
end;

function NormalizeToDrawDir(const InstallDir: string): string;
var
  S: string;
  LowerS: string;
  Programs64Pos: Integer;
begin
  S := InstallDir;
  StringChangeEx(S, '/', '\', True);
  S := RemoveTrailingBackslash(S);
  LowerS := Lowercase(S);

  // 常见情况：InstallDir 指向 ...\Programs64 或 ...\Draw
  Programs64Pos := Pos('\programs64', LowerS);
  if Programs64Pos > 0 then
  begin
    // ...\Programs64 -> ...\Draw
    S := Copy(S, 1, Programs64Pos - 1);
    S := S + '\Draw';
    LowerS := Lowercase(S);
  end;

  // 如果路径不以 \Draw 结尾，但存在 Draw 子目录，则添加 \Draw
  if (Pos('\draw', LowerS) = 0) or (Pos('\draw', LowerS) <> Length(LowerS) - 4) then
  begin
    if DirExists(S + '\Draw') then
    begin
      S := S + '\Draw';
    end;
  end;

  Result := S;
end;

function TryGetCorelInstallDirFromReg(const Key: string; const Value: string; var OutDir: string): Boolean;
var
  S: string;
begin
  Result := False;
  { Inno Setup 6：通过 HKLM64/HKLM32/HKCU64/HKCU32 查询 64/32 位视图 }
  if RegQueryStringValue(HKLM64, Key, Value, S) then begin OutDir := S; Result := True; exit; end;
  if RegQueryStringValue(HKLM32, Key, Value, S) then begin OutDir := S; Result := True; exit; end;
  if RegQueryStringValue(HKCU64, Key, Value, S) then begin OutDir := S; Result := True; exit; end;
  if RegQueryStringValue(HKCU32, Key, Value, S) then begin OutDir := S; Result := True; exit; end;

  { 兜底：当前视图 }
  if RegQueryStringValue(HKLM, Key, Value, S) then begin OutDir := S; Result := True; exit; end;
  if RegQueryStringValue(HKCU, Key, Value, S) then begin OutDir := S; Result := True; exit; end;
end;

function TryGetCorelExeFromAppPaths(var ExePath: string): Boolean;
var
  S: string;
  Key: string;
begin
  Result := False;
  Key := 'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\CorelDRW.exe';

  if RegQueryStringValue(HKLM64, Key, '', S) then begin ExePath := S; Result := True; exit; end;
  if RegQueryStringValue(HKLM32, Key, '', S) then begin ExePath := S; Result := True; exit; end;
  if RegQueryStringValue(HKCU64, Key, '', S) then begin ExePath := S; Result := True; exit; end;
  if RegQueryStringValue(HKCU32, Key, '', S) then begin ExePath := S; Result := True; exit; end;

  if RegQueryStringValue(HKLM, Key, '', S) then begin ExePath := S; Result := True; exit; end;
  if RegQueryStringValue(HKCU, Key, '', S) then begin ExePath := S; Result := True; exit; end;
end;

// 辅助函数：尝试添加一个检测到的版本
procedure TryAddVersion(var VersionList: TStringList; var PathList: TStringList; 
  const installDir: string; const key: string; const defaultVersionName: string);
var
  drawDir: string;
  versionName: string;
  displayText: string;
  regValue: string;
begin
  if installDir = '' then
    exit;
    
  drawDir := NormalizeToDrawDir(installDir);
  if not DirExists(drawDir) then
    exit;
    
  // 检查是否已存在（避免重复）
  if PathList.IndexOf(drawDir) >= 0 then
    exit;
    
  // 尝试从注册表获取版本名称
  versionName := defaultVersionName;
  if (key <> '') and TryGetCorelInstallDirFromReg(key, 'DisplayName', regValue) and (regValue <> '') then
    versionName := regValue
  else if (key <> '') and TryGetCorelInstallDirFromReg(key, 'Version', regValue) and (regValue <> '') then
    versionName := 'CorelDRAW ' + regValue
  else if (key <> '') and TryGetCorelInstallDirFromReg(key, 'ProductName', regValue) and (regValue <> '') then
    versionName := regValue;
    
  // 只显示版本名，不显示路径
  displayText := versionName;
  VersionList.Add(displayText);
  PathList.Add(drawDir);
end;

// 从 Uninstall 注册表项检测 CorelDRAW 版本
procedure DetectFromUninstallKeys(var VersionList: TStringList; var PathList: TStringList);
var
  uninstallKeys: TArrayOfString;
  i: Integer;
  key: string;
  displayName: string;
  installLocation: string;
  installDir: string;
  publisher: string;
begin
  // 检查 HKLM64\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
  if RegGetSubkeyNames(HKLM64, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', uninstallKeys) then
  begin
    for i := 0 to GetArrayLength(uninstallKeys) - 1 do
    begin
      key := 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + uninstallKeys[i];
      
      // 检查是否是 CorelDRAW 相关产品
      displayName := '';
      installLocation := '';
      installDir := '';
      publisher := '';
      
      if RegQueryStringValue(HKLM64, key, 'DisplayName', displayName) and
         (Pos('CorelDRAW', displayName) > 0) then
      begin
        // 获取安装位置
        if RegQueryStringValue(HKLM64, key, 'InstallLocation', installLocation) and (installLocation <> '') then
          installDir := installLocation
        else if RegQueryStringValue(HKLM64, key, 'InstallDir', installDir) and (installDir <> '') then
          installDir := installDir
        else if RegQueryStringValue(HKLM64, key, 'InstallPath', installDir) and (installDir <> '') then
          installDir := installDir;
          
        if installDir <> '' then
        begin
          TryAddVersion(VersionList, PathList, installDir, key, displayName);
        end;
      end;
    end;
  end;
  
  // 检查 HKLM32\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall
  if RegGetSubkeyNames(HKLM32, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', uninstallKeys) then
  begin
    for i := 0 to GetArrayLength(uninstallKeys) - 1 do
    begin
      key := 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + uninstallKeys[i];
      
      displayName := '';
      installLocation := '';
      installDir := '';
      
      if RegQueryStringValue(HKLM32, key, 'DisplayName', displayName) and
         (Pos('CorelDRAW', displayName) > 0) then
      begin
        if RegQueryStringValue(HKLM32, key, 'InstallLocation', installLocation) and (installLocation <> '') then
          installDir := installLocation
        else if RegQueryStringValue(HKLM32, key, 'InstallDir', installDir) and (installDir <> '') then
          installDir := installDir
        else if RegQueryStringValue(HKLM32, key, 'InstallPath', installDir) and (installDir <> '') then
          installDir := installDir;
          
        if installDir <> '' then
        begin
          TryAddVersion(VersionList, PathList, installDir, key, displayName);
        end;
      end;
    end;
  end;
  
  // 检查 WOW6432Node (32位程序在64位系统上)
  if RegGetSubkeyNames(HKLM64, 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', uninstallKeys) then
  begin
    for i := 0 to GetArrayLength(uninstallKeys) - 1 do
    begin
      key := 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\' + uninstallKeys[i];
      
      displayName := '';
      installLocation := '';
      installDir := '';
      
      if RegQueryStringValue(HKLM64, key, 'DisplayName', displayName) and
         (Pos('CorelDRAW', displayName) > 0) then
      begin
        if RegQueryStringValue(HKLM64, key, 'InstallLocation', installLocation) and (installLocation <> '') then
          installDir := installLocation
        else if RegQueryStringValue(HKLM64, key, 'InstallDir', installDir) and (installDir <> '') then
          installDir := installDir
        else if RegQueryStringValue(HKLM64, key, 'InstallPath', installDir) and (installDir <> '') then
          installDir := installDir;
          
        if installDir <> '' then
        begin
          TryAddVersion(VersionList, PathList, installDir, key, displayName);
        end;
      end;
    end;
  end;
end;

procedure DetectAllCorelDrawDirs(var VersionList: TStringList; var PathList: TStringList);
var
  v: Integer;
  installDir: string;
  key: string;
  exePath: string;
  drawDir: string;
  versionName: string;
  displayText: string;
  testPath: string;
begin
  VersionList := TStringList.Create;
  PathList := TStringList.Create;
  VersionList.Duplicates := dupIgnore;
  PathList.Duplicates := dupIgnore;

  { 方法1：从 Uninstall 注册表项检测（最可靠，所有安装的程序都会在这里注册） }
  DetectFromUninstallKeys(VersionList, PathList);

  { 方法2：从 App Paths 检测 }
  exePath := '';
  if TryGetCorelExeFromAppPaths(exePath) then
  begin
    if exePath <> '' then
    begin
      drawDir := NormalizeToDrawDir(ExtractFileDir(exePath));
      if DirExists(drawDir) then
      begin
        versionName := ExtractFileName(ExtractFileDir(ExtractFileDir(drawDir)));
        if versionName = '' then
          versionName := 'CorelDRAW (App Paths)';
        // 只显示版本名，不显示路径
        displayText := versionName;
        if PathList.IndexOf(drawDir) < 0 then
        begin
          VersionList.Add(displayText);
          PathList.Add(drawDir);
        end;
      end;
    end;
  end;

  { 方法3：从 Corel 注册表键检测（兜底） }
  for v := 30 downto 10 do
  begin
    installDir := '';
    key := 'SOFTWARE\Corel\CorelDRAW\' + IntToStr(v) + '.0';
    if TryGetCorelInstallDirFromReg(key, 'InstallDir', installDir) or
       TryGetCorelInstallDirFromReg(key, 'Path', installDir) or
       TryGetCorelInstallDirFromReg(key, 'RootDir', installDir) or
       TryGetCorelInstallDirFromReg(key, 'InstallPath', installDir) then
    begin
      TryAddVersion(VersionList, PathList, installDir, key, 'CorelDRAW ' + IntToStr(v) + '.0');
    end;

    installDir := '';
    key := 'SOFTWARE\Corel\CorelDRAW\' + IntToStr(v);
    if TryGetCorelInstallDirFromReg(key, 'InstallDir', installDir) or
       TryGetCorelInstallDirFromReg(key, 'Path', installDir) or
       TryGetCorelInstallDirFromReg(key, 'RootDir', installDir) or
       TryGetCorelInstallDirFromReg(key, 'InstallPath', installDir) then
    begin
      TryAddVersion(VersionList, PathList, installDir, key, 'CorelDRAW ' + IntToStr(v));
    end;
  end;

  { 方法4：扫描文件系统（最后兜底） }
  if DirExists('C:\Program Files\Corel') then
  begin
    for v := 30 downto 10 do
    begin
      testPath := 'C:\Program Files\Corel\CorelDRAW Graphics Suite ' + IntToStr(v) + '\Draw';
      if DirExists(testPath) then
      begin
        TryAddVersion(VersionList, PathList, testPath, '', 'CorelDRAW Graphics Suite ' + IntToStr(v));
      end;
      
      testPath := 'C:\Program Files\Corel\CorelDRAW ' + IntToStr(v) + '\Draw';
      if DirExists(testPath) then
      begin
        TryAddVersion(VersionList, PathList, testPath, '', 'CorelDRAW ' + IntToStr(v));
      end;
    end;
  end;
  
  if DirExists('C:\Program Files (x86)\Corel') then
  begin
    for v := 30 downto 10 do
    begin
      testPath := 'C:\Program Files (x86)\Corel\CorelDRAW Graphics Suite ' + IntToStr(v) + '\Draw';
      if DirExists(testPath) then
      begin
        TryAddVersion(VersionList, PathList, testPath, '', 'CorelDRAW Graphics Suite ' + IntToStr(v));
      end;
      
      testPath := 'C:\Program Files (x86)\Corel\CorelDRAW ' + IntToStr(v) + '\Draw';
      if DirExists(testPath) then
      begin
        TryAddVersion(VersionList, PathList, testPath, '', 'CorelDRAW ' + IntToStr(v));
      end;
    end;
  end;
end;

function DetectCorelDrawDir(): string;
var
  versions: TStringList;
  paths: TStringList;
begin
  Result := '';
  versions := nil;
  paths := nil;
  DetectAllCorelDrawDirs(versions, paths);
  try
    if Assigned(paths) and (paths.Count > 0) then
      Result := paths[0];
  finally
    if Assigned(versions) then versions.Free;
    if Assigned(paths) then paths.Free;
  end;
end;

function GetPlugins64Dir(Param: string): string;
begin
  if DetectedDrawDir = '' then
    DetectedDrawDir := DetectCorelDrawDir();

  Result := EnsureTrailingBackslash(DetectedDrawDir) + 'Plugins64';
end;

function GetCrzouFilesDir(Param: string): string;
begin
  Result := EnsureTrailingBackslash(GetPlugins64Dir('')) + 'Crzou Files';
end;

procedure InitializeWizard();
var
  i: Integer;
  PageDescriptionLabel: TLabel;
  TopPos: Integer;
begin
  CorelDrawPaths := nil;
  SelectedDrawDirs := TStringList.Create;
  DetectAllCorelDrawDirs(CorelDrawVersions, CorelDrawPaths);
  
  // 检查是否检测到多个版本
  if Assigned(CorelDrawVersions) and Assigned(CorelDrawPaths) and (CorelDrawVersions.Count > 1) then
  begin
    // 创建版本选择页面（使用 CreateCustomPage）
    VersionSelectionPage := CreateCustomPage(wpWelcome,
      GetLocalizedString('Select CorelDRAW Version', '选择 CorelDRAW 版本', 'Selecionar Versão do CorelDRAW'),
      GetLocalizedString('Multiple CorelDRAW versions detected. Please select the versions to install the plugin (multiple selection allowed):', 
        '检测到多个 CorelDRAW 版本，请选择要安装插件的版本（可多选）：',
        'Múltiplas versões do CorelDRAW detectadas. Selecione as versões para instalar o plugin (seleção múltipla permitida):'));
    
    // 创建描述标签
    PageDescriptionLabel := TLabel.Create(VersionSelectionPage);
    PageDescriptionLabel.Parent := VersionSelectionPage.Surface;
    PageDescriptionLabel.Caption := GetLocalizedString(
      'Please check the CorelDRAW versions to install the plugin (multiple selection allowed), then click "Next".',
      '请勾选要安装插件的 CorelDRAW 版本（可多选），然后单击"下一步"。',
      'Marque as versões do CorelDRAW para instalar o plugin (seleção múltipla permitida), depois clique em "Próximo".');
    PageDescriptionLabel.Left := 0;
    PageDescriptionLabel.Top := 0;
    PageDescriptionLabel.Width := VersionSelectionPage.SurfaceWidth;
    PageDescriptionLabel.Height := 40;
    PageDescriptionLabel.AutoSize := False;
    PageDescriptionLabel.WordWrap := True;
    
    // 创建复选框数组
    SetArrayLength(VersionCheckBoxes, CorelDrawVersions.Count);
    TopPos := PageDescriptionLabel.Top + PageDescriptionLabel.Height + 20;
    
    // 添加复选框（默认全选）
    for i := 0 to CorelDrawVersions.Count - 1 do
    begin
      VersionCheckBoxes[i] := TCheckBox.Create(VersionSelectionPage);
      VersionCheckBoxes[i].Parent := VersionSelectionPage.Surface;
      VersionCheckBoxes[i].Caption := CorelDrawVersions[i];
      VersionCheckBoxes[i].Left := 20;
      VersionCheckBoxes[i].Top := TopPos;
      VersionCheckBoxes[i].Width := VersionSelectionPage.SurfaceWidth - 40;
      VersionCheckBoxes[i].Checked := True;  // 默认全选
      TopPos := TopPos + 25;
    end;
  end
  else
  begin
    // 只有一个版本或没有检测到版本
    VersionSelectionPage := nil;
    if Assigned(CorelDrawPaths) and (CorelDrawPaths.Count = 1) then
    begin
      DetectedDrawDir := CorelDrawPaths[0];
      SelectedDrawDirs.Add(DetectedDrawDir);
    end
    else if Assigned(CorelDrawPaths) and (CorelDrawPaths.Count = 0) then
    begin
      // 没有检测到版本，让用户手动选择
      MsgBox(GetLocalizedString(
        'CorelDRAW installation directory not detected. Please manually select the CorelDRAW Draw directory (e.g., C:\Program Files\Corel\...\Draw).',
        '未检测到 CorelDRAW 安装目录。请手动选择 CorelDRAW 的 Draw 目录（例如：C:\Program Files\Corel\...\Draw）。',
        'Diretório de instalação do CorelDRAW não detectado. Selecione manualmente o diretório Draw do CorelDRAW (por exemplo: C:\Program Files\Corel\...\Draw).'),
        mbInformation, MB_OK);
      if BrowseForFolder(GetLocalizedString(
        'Please select the CorelDRAW Draw directory',
        '请选择 CorelDRAW 的 Draw 目录',
        'Selecione o diretório Draw do CorelDRAW'), DetectedDrawDir, False) then
      begin
        DetectedDrawDir := NormalizeToDrawDir(DetectedDrawDir);
        if DirExists(DetectedDrawDir) then
        begin
          SelectedDrawDirs.Add(DetectedDrawDir);
        end;
      end;
    end;
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Plugins64Path: string;
  i: Integer;
  selectedCount: Integer;
  drawDir: string;
begin
  Result := True;
  
  // 如果是在版本选择页面
  if Assigned(VersionSelectionPage) and Assigned(CorelDrawPaths) and 
     (CurPageID = VersionSelectionPage.ID) and (CorelDrawVersions.Count > 1) then
  begin
    // 清空之前的选择
    SelectedDrawDirs.Clear;
    
    // 查找所有选中的复选框
    selectedCount := 0;
    for i := 0 to GetArrayLength(VersionCheckBoxes) - 1 do
    begin
      if VersionCheckBoxes[i].Checked then
      begin
        drawDir := CorelDrawPaths[i];
        
        if not DirExists(drawDir) then
        begin
          MsgBox(GetLocalizedString('Invalid directory selected:', '选择的目录无效：', 'Diretório selecionado inválido:') + #13#10 + drawDir, mbCriticalError, MB_OK);
          Result := False;
          exit;
        end;
        
        Plugins64Path := EnsureTrailingBackslash(drawDir) + 'Plugins64';
        // 如果 Plugins64 目录不存在，则自动创建
        if not DirExists(Plugins64Path) then
        begin
          if not ForceDirectories(Plugins64Path) then
          begin
            MsgBox(GetLocalizedString(
              'Failed to create Plugins64 directory:' + #13#10 + Plugins64Path,
              '创建 Plugins64 目录失败：' + #13#10 + Plugins64Path,
              'Falha ao criar diretório Plugins64:' + #13#10 + Plugins64Path),
              mbCriticalError, MB_OK);
            Result := False;
            exit;
          end;
        end;
        
        SelectedDrawDirs.Add(drawDir);
        selectedCount := selectedCount + 1;
      end;
    end;
    
    if selectedCount = 0 then
    begin
      MsgBox(GetLocalizedString(
        'Please select at least one CorelDRAW version.',
        '请至少选择一个 CorelDRAW 版本。',
        'Selecione pelo menos uma versão do CorelDRAW.'), mbError, MB_OK);
      Result := False;
      exit;
    end;
    
    // 设置第一个选中的目录为默认目录（用于兼容现有代码）
    if SelectedDrawDirs.Count > 0 then
      DetectedDrawDir := SelectedDrawDirs[0];
  end;
end;

procedure DeinitializeSetup();
begin
  // 清理内存
  if Assigned(CorelDrawVersions) then
    CorelDrawVersions.Free;
  if Assigned(CorelDrawPaths) then
    CorelDrawPaths.Free;
  if Assigned(SelectedDrawDirs) then
    SelectedDrawDirs.Free;
end;

function InitializeSetup(): Boolean;
begin
  // InitializeSetup 在 InitializeWizard 之前执行
  // 版本检测和选择逻辑都在 InitializeWizard 中处理
  // 语言自动检测通过 [Setup] 部分的 LanguageDetectionMethod=uilanguage 实现
  // 这里只返回 True，允许安装程序继续
  Result := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  i: Integer;
  drawDir: string;
  plugins64Dir: string;
  crzouFilesDir: string;
  sourceCpgPath: string;
  sourceCutToolPath: string;
  sourceUninstallerPath: string;
  destCpgPath: string;
  destCutToolPath: string;
  destUninstallerPath: string;
begin
  // 在安装完成后，将文件复制到所有选中的目录
  if CurStep = ssPostInstall then
  begin
    // 如果选择了多个版本，需要复制文件到其他目录
    if Assigned(SelectedDrawDirs) and (SelectedDrawDirs.Count > 1) then
    begin
      // 获取源文件路径（已经安装到第一个目录的文件）
      if SelectedDrawDirs.Count > 0 then
      begin
        drawDir := SelectedDrawDirs[0];
        plugins64Dir := EnsureTrailingBackslash(drawDir) + 'Plugins64';
        crzouFilesDir := EnsureTrailingBackslash(plugins64Dir) + 'Crzou Files';
        
        sourceCpgPath := EnsureTrailingBackslash(plugins64Dir) + 'cdr-plugin.cpg';
        sourceCutToolPath := EnsureTrailingBackslash(crzouFilesDir) + 'cut-tool.exe';
        sourceUninstallerPath := EnsureTrailingBackslash(plugins64Dir) + 'uninstaller.exe';
        
        // 复制到其他选中的目录
        for i := 1 to SelectedDrawDirs.Count - 1 do
        begin
          drawDir := SelectedDrawDirs[i];
          plugins64Dir := EnsureTrailingBackslash(drawDir) + 'Plugins64';
          crzouFilesDir := EnsureTrailingBackslash(plugins64Dir) + 'Crzou Files';
          
          // 确保目录存在
          if not DirExists(plugins64Dir) then
            CreateDir(plugins64Dir);
          if not DirExists(crzouFilesDir) then
            CreateDir(crzouFilesDir);
          
          // 复制文件
          destCpgPath := EnsureTrailingBackslash(plugins64Dir) + 'cdr-plugin.cpg';
          destCutToolPath := EnsureTrailingBackslash(crzouFilesDir) + 'cut-tool.exe';
          destUninstallerPath := EnsureTrailingBackslash(plugins64Dir) + 'uninstaller.exe';
          
          if FileExists(sourceCpgPath) then
            FileCopy(sourceCpgPath, destCpgPath, False);
          if FileExists(sourceCutToolPath) then
            FileCopy(sourceCutToolPath, destCutToolPath, False);
          if FileExists(sourceUninstallerPath) then
            FileCopy(sourceUninstallerPath, destUninstallerPath, False);
        end;
      end;
    end;
  end;
end;



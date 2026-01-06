### Crzou 插件安装程序（Inno Setup 5）

#### 目标
- 把 `cdr-plugin.cpg` 安装到：`<CorelDraw>\Draw\Plugins64\`
- 在：`<CorelDraw>\Draw\Plugins64\Crzou Files\` 创建目录并放入 `cut-tool.exe`

#### 使用
- 打开 `installer/CrzouPlugin.iss`
- 点击 Compile 生成安装包 `CrzouPluginSetup.exe`

#### 文件来源
- `..\cdr-plugin\bin\x64\Release\cdr-plugin.cpg`
- `..\cdr-plugin\bin\x64\Release\cut-tool.exe`

#### CorelDRAW 路径检测
- 脚本会尝试从注册表（64/32）读取：`HKLM\SOFTWARE\Corel\CorelDRAW\<版本>\InstallDir`
- 若检测失败，会弹窗让你手动选择 CorelDRAW 的 `Draw` 目录



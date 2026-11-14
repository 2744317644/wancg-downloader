# wnacg Windows 桌面版（WinUI 3）

Windows 端原生客户端，.NET 8 + Windows App SDK 1.8（WinUI 3），**免安装**（解压后直接运行 `WnacgDownloader.exe`）。

## 功能

- **链接下载**：粘贴作品页 / 阅读页链接，解析标题、页数、分类、标签、封面，可先预览再下载。
- **书签下载**：导入 Chrome / Edge / Firefox 导出的书签 HTML（也支持 `.txt` 链接列表，或直接粘贴多个链接），勾选后批量下载。
- **漫画预览**：单页 / 双页阅读，页面自动缩放到窗口高度，点击页面左右两侧或「上一页/下一页」切页；图片按需加载并缓存最近 10 页。
- **下载目录**：设置里用文件夹选择器指定；每部作品一个同名文件夹，可选额外打包 ZIP、生成 PDF。
  - PDF 与 iOS 版排版一致：所有页固定 595pt 宽，页高按图片比例计算，横图/竖图混排时不会出现横版页更宽的问题。
- **网络模式**（设置里切换）：
  - **系统代理**：使用 Windows 系统代理；
  - **自定义代理端口**：勾选后使用 `127.0.0.1:<端口>`（默认 7890）；
  - **DoH 直连**：通过 DoH（默认 Cloudflare，备用 AliDNS/DoH.pub）解析真实 IP，用原域名做 TLS SNI 直连。
- **进度队列**：每个下载任务显示进度/速度、可取消、完成后可直接打开文件夹。

## 运行

### 安装版（推荐）

1. 运行 `WnacgDownloader-Setup-1.0.5.exe`；
2. 按向导安装（按用户安装，不需要管理员权限），会创建开始菜单快捷方式，可选桌面图标；
3. 从开始菜单启动 `wnacg 下载器`；在「设置 → 应用」里可卸载。

### 便携版

1. 解压 `WnacgDownloader-win-x64.zip`；
2. 运行 `WnacgDownloader.exe`；
3. 首次启动若出现 SmartScreen，点「更多信息」→「仍要运行」（未签名）。

系统要求：Windows 10 1809+ / Windows 11，x64。

## 构建

需要 **.NET 8 SDK**（Windows）：

```powershell
# 调试构建
dotnet build windows/WnacgDownloader/WnacgDownloader.csproj -c Debug -p:Platform=x64

# 发布自包含 exe（目标机器无需安装 .NET / Windows App Runtime）
dotnet publish windows/WnacgDownloader/WnacgDownloader.csproj `
  -c Release -r win-x64 --self-contained true -p:Platform=x64 `
  -p:WindowsPackageType=None -p:WindowsAppSDKSelfContained=true `
  -p:PublishTrimmed=false `
  -o windows/dist/WnacgDownloader-win-x64
```

或直接运行 `windows/build.ps1 -Publish`。

发布目录约 215 MB / 328 个文件（自带 .NET 运行时和 Windows App SDK 运行时），zip 约 85 MB。

### 安装包（Inno Setup 6）

```powershell
& "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe" windows/installer/wnacg.iss
```

安装包与 exe 图标来自 iOS App 的 `AppIcon`（1024px PNG → 多尺寸 `windows/WnacgDownloader/Assets/app.ico`）。

## 目录结构

```
windows/
  WnacgDownloader/
    App.xaml(.cs)            应用入口
    MainWindow.cs            NavigationView + 页面切换
    DownloadPage.cs          链接解析 / 预览入口 / 下载队列
    BookmarksPage.cs         书签导入与批量下载
    PreviewPage.cs           漫画单页/双页阅读（点击左右切页）
    SettingsPage.cs          目录 / 网络 / 并发设置
    QueueRow.cs              下载任务行（进度/取消/打开目录）
    Core/
      WnacgClient.cs         HTTP（系统代理/自定义端口/DoH 直连）
      DohResolver.cs         DoH 解析 + TLS 校验
      HtmlParser.cs          正则/编码/文件名工具
      BookmarkParser.cs      书签 HTML / 链接列表解析
      DownloadService.cs     图片下载 + info.txt + 可选 ZIP/PDF
      PdfBuilder.cs         极简 PDF 1.4 写入器（JPEG DCTDecode）
      SettingsStore.cs       %LOCALAPPDATA%\WnacgDownloader\settings.json
      Models.cs / AppServices.cs
  SmokeTest/                 核心逻辑控制台冒烟测试（不依赖 UI）
  PdfCheck/                  PDF 渲染验证工具（Windows.Data.Pdf）
  build.ps1
```

## 冒烟测试

```powershell
# 通过本地代理 7890 测试解析 + 197 张图片地址 + 第一张图片
dotnet run --project windows/SmokeTest/SmokeTest.csproj -c Release -- proxy 7890

# DoH 直连模式
dotnet run --project windows/SmokeTest/SmokeTest.csproj -c Release -- doh 0

# 再追加 download 参数会真实下载整部作品并打包 ZIP
dotnet run --project windows/SmokeTest/SmokeTest.csproj -c Release -- proxy 7890 download
```

## 已知限制

- PDF 只嵌入 JPEG 原图（不重编码）；阅读页目前都是 JPEG，非 JPEG 页面会跳过并在状态里说明；
- 部分需要登录的合集/单话内容无法解析（与 Python/iOS 端一致）；
- Windows App SDK 的 `Frame.Navigate` 在本机 Windows 10 上会崩溃，因此 UI 用 `NavigationView.Content` 直接切换页面，未使用 `Frame`；
- 无自动更新，升级请替换整个目录。

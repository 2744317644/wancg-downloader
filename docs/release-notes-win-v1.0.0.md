## Windows WinUI 3 客户端 v1.0.0

Windows 原生桌面客户端（.NET 8 + Windows App SDK 1.8 / WinUI 3），**免安装**：解压后直接运行 `WnacgDownloader.exe`。

### 功能

- **链接下载**：粘贴作品页/阅读页链接，解析封面、标题、页数、分类、标签；可先预览再下载。
- **书签下载**：导入 Chrome / Edge / Firefox 导出的书签 HTML（也支持 `.txt` 链接列表或直接粘贴多个链接），多选批量下载。
- **漫画预览**：软件内按页滚动预览，图片按并发数加载。
- **下载目录**：设置内用文件夹选择器指定；每部作品一个同名文件夹，可选额外打包 ZIP。
- **网络模式**：
  - 系统代理（Windows 系统代理）；
  - 自定义代理端口（`127.0.0.1:<端口>`，默认 7890）；
  - DoH 直连（Cloudflare，备用 AliDNS / DoH.pub；TLS + SNI 校验解析出的 IP）。
- **下载队列**：实时进度/速度、取消任务、完成后打开文件夹。

### 运行要求

- Windows 10 1809+ / Windows 11，x64；
- 解压 `WnacgDownloader-win-x64.zip`，运行 `WnacgDownloader.exe`；
- 未签名，首次启动 SmartScreen 请点「更多信息」→「仍要运行」。

### 构建

源码在 `windows/`，使用 .NET 8 SDK：

```powershell
windows/build.ps1 -Publish
```

发布目录约 215 MB（自带 .NET 与 Windows App SDK 运行时），zip 约 85 MB。

> 本 Release 只附 Windows zip，不包含截图。

# wnacg 漫画下载器（Windows WinUI 3 / Web UI + iOS App）

这个仓库包含两套实现：

- **Windows / Python Web UI**：ZIP + PDF、实时进度、作品预览、直连 DoH；
- **iOS 原生 App**：SwiftUI 独立 App，下载 ZIP、解压图片、生成 PDF，保存到“文件”；
  通过 GitHub Actions 构建 unsigned IPA，使用 Sideloadly / AltStore 侧载。

## iOS 原生 App

源码在 [`ios/`](ios/)，构建流程在 [`.github/workflows/ios.yml`](.github/workflows/ios.yml)。

> **系统要求：iOS 26.0+**。从 1.25.0 起最低部署版本为 iOS 26，低于 iOS 26 的设备无法安装，也不再做兼容适配。

**直接下载 unsigned IPA：** [最新 Release](https://github.com/2744317644/wancg-downloader/releases/latest)

> App 图标使用站点 Logo（看板娘 + 紳士漫畫字标）制作。

### 从 GitHub Actions 下载 IPA

1. 打开仓库的 **Actions** → **Build iOS IPA**；
2. 等构建完成，在本次 run 底部下载 artifact **`WnacgDownloader-unsigned-ipa`**；
3. 解压得到 `WnacgDownloader-unsigned.ipa`。

推送代码到 `main` 或手动 `Run workflow` 都会触发构建。

### 侧载到 iPhone

这个 IPA 是 **unsigned** 的，不能直接双击安装：

1. Windows 安装 [Sideloadly](https://sideloadly.io/)；
2. iPhone 用数据线连接电脑；
3. 把 IPA 拖进 Sideloadly，输入你的 Apple ID；
4. 开始签名安装；
5. iPhone 设置 → 通用 → VPN 与设备管理 → 信任你的开发者证书。

免费 Apple ID 签名的 App **7 天过期**，到期后重新用 Sideloadly 签一次即可；
有付费开发者账号可以用自己的证书签更久。

### App 功能

- **首页**：原生 SwiftUI 渲染，不再套 WebView。抓取首页 HTML 后解析“最新上架 / 同人志 /
  單行本 / 雜誌·短篇”栏目，用三列封面卡片展示；顶部有“全部 / 分类”快捷入口，
  每个栏目的“更多”可进入分类列表；
- **搜索**：首页导航栏搜索框，提交后进入搜索结果页，与分类页共用同一个连续网格；
- **详情页**：点任意封面进入原生详情页，显示封面、标题、分类、页数、收藏、作者、标签，
  下方有“开始阅读”和“下载 ZIP + PDF”按钮；
- **在线阅读**：详情页点“开始阅读”进入原生图片阅读器，纵向连续翻页，图片走本地代理加载；
  自动预载当前页下方 10 页（逐页顺序预载），缓存最多 16 页；
- **分类浏览**：同人志等分类页是一个连续自适应网格（iPhone 三列、iPad 自动增列），
  滑到底自动加载站点下一页并去重，底部显示“正在加载更多 / 加载失败点击重试 / 已经到底了”，
  不再使用固定 9 部一页的悬浮翻页条；
- **筛选**：分类页和搜索结果顶部直接显示“全部 / 翻译 / 日语”胶囊、“屏蔽 AI”开关和“排除标签”入口；
  搜索、标签搜索同样生效；排除标签在筛选条或“设置 → 内容”里管理，会应用到首页、分类、搜索和标签搜索；
  切换筛选会自动回到顶部，并继续加载直到有匹配结果，不会出现“本页没有符合筛选”的假空页；
  首页始终显示全部内容；语言按标题中的“中国翻訳 / 漢化 / 中文”等标记判断，
  未带中文标记的默认归为日语；
- **二级页体验**：首屏用骨架屏占位而不是整屏转圈，支持下拉刷新、加载失败内联重试、
  动态字号与 Reduce Motion；
- **重复下载提示**：已经下载过的作品再次点下载时，会先弹出“已经下载过”确认；
  取消不会重新下载，确认后才重新下载并覆盖同名文件；
- **下载**：粘贴链接，解析封面、标题、页数、标签；下载 ZIP、解压、生成 300 DPI PDF；
- **下载队列**：下载一部作品时进入别的详情页，下载按钮会变成“加入下载队列”；
  可以连续加入多部，前一部完成后自动开始下一部；未开始的任务会保存到本地，
  重启 App 后自动继续；
- **顶部下载条**：下载时在所有页面顶部显示作品名、队列数量和实时进度，点一下跳到下载页；
- **灵动岛 / 锁屏进度**：下载时创建 Live Activity，灵动岛紧凑/展开状态和锁屏都会显示
  作品名、进度和状态；下载结束或失败后结束活动；
- **后台下载（尽力而为）**：下载期间申请 `beginBackgroundTask`，短时间切后台/息屏可以继续；
  iOS 长时间挂起后仍可能暂停，不能像系统后台下载那样绝对保证；失败后可在详情页点
  “重试下载”；
- **文件**：浏览 App Documents 里的 ZIP / PDF，点击 PDF 直接预览（PDFKit），支持分享和删除；
  文件页右上角可开启“隐藏 ZIP 文件”，只显示 PDF，下载记录不受影响；
- **收藏**：详情页可收藏/取消收藏；收藏页分成“已下载 / 未下载”两组，
  下载完成会持久记录，即使之后删除本地 ZIP/PDF，仍显示为已下载；
  右上角可导出为浏览器可导入的 HTML 书签，两个分组会变成两个书签文件夹；
- **历史**：只有点进漫画详情页才记录，保存浏览日期和时间；历史页按天分组，
  显示具体时间，可左滑删除单条或清空全部；入口在“设置 → 历史记录”；
- **后台恢复**：从后台/息屏回到前台时自动重建本地代理和 URLSession；
  遇到 CFNetwork 310（HTTPS 代理连接失败）会自动重启代理并重试一次；
- 底部 **Liquid Glass 页签**：首页/下载/收藏/文件/设置五个页签，使用系统 `TabView`，
  iOS 26 自动获得液态玻璃外观，并固定为常驻不收起（`tabBarMinimizeBehavior(.never)`）；
- **外观**：在“设置 → 外观”可切换“跟随系统 / 浅色 / 深色”，浅色模式会同步调整首页、分类、
  详情和下载页的背景与文字；
- 阅读器顶部「关闭 / 页数 / 刷新」和底部页数进度胶囊使用 **iOS 26 Liquid Glass**；
- **不再支持 iOS 26 以下系统**（最低部署版本 26.0）。

### 实现说明

- `LocalProxy`：在 App 内启动 `127.0.0.1` 的 HTTP CONNECT 代理；
- `DoHResolver`：通过 `doh.pub` 解析真实 IP，内置实测备用 IP；
- `URLSession` 走这个本地代理，TLS SNI 仍然是原域名，证书正常校验；
- 首页封面也通过同一个代理加载并缓存在 `NSCache`，不经过 WebView；
- `ZIPFoundation` 解压，`UIGraphicsPDFRenderer` 生成 PDF，`PDFKit` 预览。

### CI 已验证

GitHub Actions 每次构建都会先跑一个 macOS smoke test：

- 通过 App 内的本地 CONNECT 代理访问 wnacg；
- 解析标题、197 页、封面；
- 解析首页栏目与“更多”分类链接；
- 解析漫画列表页（20 部）和下一页链接；
- 解析搜索页（24 条结果）和搜索分页；
- 解析阅读页的 197 张图片地址；
- 下载一个约 10 MB 的测试 ZIP；
- 用 ZIPFoundation 解压出 53 张图片。

这几步通过后才会打包 IPA，因此下载链路、解析、解压都是实际跑通过的。

### 模拟器 UI 测试与截图（Windows 也能用）

本机没有 Mac 也能在真实 iOS Simulator 里跑 UI 测试并导出截图：GitHub Actions 的
`UI Preview Screenshots` workflow 会在 macOS runner 上启动最新/最旧 iOS 模拟器，
运行 `ios/UITests` 下的 XCUITest，并上传截图、无障碍树和系统日志。

完整原理、配置与排错见：[docs/ios-simulator-ci-guide.md](docs/ios-simulator-ci-guide.md)。

### 本地构建（需要 Mac）

需要 **Xcode 26.3+**（iOS 26 SDK）。GitHub Actions 使用 `macos-15` runner，
并切换到 `/Applications/Xcode_26.3.app`。

```bash
brew install xcodegen
cd ios
xcodegen generate
open WnacgDownloader.xcodeproj
```

选择自己的 Team 和真机运行；或者直接让 GitHub Actions 构建。

> 当前 iOS App 只实现了直连模式，没有代理设置界面；如果所在网络连 Cloudflare IP/SNI
> 也被封锁，App 会下载失败，需要后续加代理配置。

---

## Windows 桌面版（WinUI 3）

`windows/` 下是新的 WinUI 3 原生客户端（.NET 8 + Windows App SDK），提供带开始菜单/桌面图标的**安装版**和免安装便携版：

- **链接下载**：解析作品页/阅读页，展示封面、标题、页数、标签，可先预览再下载；
- **书签下载**：导入 Chrome/Edge/Firefox 导出的书签 HTML（或 `.txt` 链接列表），勾选后批量下载；
- **漫画预览**：单页/双页阅读，自动适配窗口，点击页面左右两侧或按钮切页；
- **设置**：下载目录选择、系统代理 / 自定义代理端口 / DoH 直连、图片并发数、下载后打包 ZIP / 生成 PDF；
- 下载队列显示进度、速度，可取消，完成后可直接打开文件夹。

使用与构建说明见 **[windows/README.md](windows/README.md)**；快速构建发布：`windows/build.ps1 -Publish`。

---

## Windows Web UI

双击 **`启动下载.bat`**，会自动启动本地服务并打开网页。在网页里粘贴作品链接，右侧会显示封面和详情预览，任务区实时显示：

- ZIP 下载进度、速度与大小
- PDF 生成进度（第几页 / 共几页）
- 失败原因、日志
- 完成后的“打开 PDF”“下载 ZIP”“打开文件夹”

服务只监听 `127.0.0.1`，关闭启动窗口或按 `Ctrl+C` 即停止。

```text
作品链接
  │
  ├─ 1. 解析下载页，获取 ZIP 直链
  ├─ 2. 下载 ZIP（断点续传、停滞自动重试）
  ├─ 3. 校验 ZIP
  ├─ 4. 读取 ZIP 内图片，按文件名排序
  └─ 5. 生成 PDF
```

最终同时保留 **ZIP** 和 **PDF**：

```text
downloads/
  [作者] 作品名.zip
  [作者] 作品名.pdf
```

---

## 快速开始

1. 双击 **`启动下载.bat`**（走系统代理，最通用）；
   如果没开代理，双击 **`启动下载-直连.bat`**（DoH 直连，见下文）；
   iPhone / iPad 用 **`启动下载-手机.bat`**，然后看“iPhone / iPad 使用”；
2. 浏览器自动打开 <http://127.0.0.1:8765/>（端口被占用时会自动顺延）；
3. 粘贴一个或多个作品链接（一行一个），点击“开始下载”；
4. 任务卡片会实时刷新下载 / PDF 进度；
5. 完成后点“打开 PDF”或“下载 ZIP”。

如果浏览器没有自动打开，复制启动窗口里显示的地址手动访问即可。

### 批量下载书签

支持把 Chrome / Edge / Firefox 导出的 HTML 书签直接批量下载：

> 不要双击 `batch_bookmarks.py`。Windows 默认不一定把 `.py` 关联到 Python，
> 会弹出“选择打开方式”。请双击下面的 `.bat` 启动器，由它自动寻找 Python。

1. 双击 **`批量下载书签.bat`**，把书签 HTML 拖进窗口；
2. 或双击 **`批量下载书签-直连.bat`**（DoH 直连）；
3. 脚本会先解析书签里的 wnacg 作品，去重后逐个下载；
4. 结束后在控制台和 `downloads/batch_report.txt` 里列出：
   - 成功作品及 ZIP/PDF 路径；
   - 跳过的作品（文件已存在）；
   - 失败作品及具体原因。

命令行用法：

```powershell
python .\batch_bookmarks.py bookmarks.html
python .\batch_bookmarks.py bookmarks.html --direct -o D:\manga
python .\batch_bookmarks.py bookmarks.html --no-pdf --overwrite
python .\batch_bookmarks.py bookmarks.html --start 5 --limit 10
```

### Loon 分流插件

仓库里带有 [`loon/wnacg.lpx`](loon/wnacg.lpx) 和
[`loon/wnacg.plugin`](loon/wnacg.plugin)，内容相同，直接在 Loon 里添加：

```text
https://gist.githubusercontent.com/2744317644/e685e6685071fb84f7aea5a67d1d7c7b/raw/wnacg.lpx
```

`.lpx` 和 `.plugin` 都是纯文本 Loon 插件，只是扩展名不同；加密插件是
`.lpxe`，需要 Loon 的插件加密工具生成，不能直接编辑。

它会把这些请求指向 `PROXY` 策略组：

- `wnacg.com` 网页；
- `qy0.ru` 阅读图片；
- `wn01.download` / `wcdn.date` ZIP 下载；
- `doh.pub` 内置 DoH。

插件只使用域名规则，兼容性优先；配合 App 的“使用系统网络”模式已经够用。
如果仍开着内置 DoH，需要额外补 IP 规则，否则 Loon 可能只看到直连 IP。

安装后在插件里点 `PROXY` 选择你的代理策略组。然后在 App 的
**设置 → 网络** 里打开“使用系统网络 / Loon 分流”，App 就不再走内置 DoH，
由 Loon 按规则处理。

如果某个代理节点仍被 429，换一个节点即可；插件本身只负责分流，不提供节点。

### 命令行启动

```powershell
& "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe" .\wnacg_web.py
```

常用参数：

```powershell
python .\wnacg_web.py --port 9000          # 指定端口
python .\wnacg_web.py --no-browser         # 不自动打开浏览器
python .\wnacg_web.py --output D:\manga    # 指定保存目录
python .\wnacg_web.py --proxy http://127.0.0.1:7890
python .\wnacg_web.py --no-proxy
python .\wnacg_web.py --direct             # DoH 直连，不用代理
```

代理默认自动读取环境变量或 Windows 系统代理（这台机器上是
`http://127.0.0.1:7890`）。

---

## 不用代理：直连模式（DoH）

当前网络对 `wnacg.com` 的封锁主要是 **DNS 污染**：系统 DNS 会把
`www.wnacg.com` 解析到一个错误的 Facebook IP，所以直接访问会超时。
但用 DoH 查到真实的 Cloudflare IP 后，直接建立 TLS 连接是可以通的。

直连模式的做法：

1. 通过 `https://doh.pub/dns-query` 解析 `www.wnacg.com`、`dl1.wn01.download`、
   `t4.qy0.ru` 等域名的真实 IP；
2. 直接连接这个 IP，但 TLS SNI 和 HTTP Host 仍然使用原域名；
3. 不经过任何本地代理，证书仍然正常校验。

脚本内置了实测可用的备用 IP，并会用 TLS + SNI 握手验证 IP 是否真的属于目标域名，
过滤掉 DoH 返回的污染地址；静态 IP 失效时再回退到 DoH / 系统 DNS。

使用方式：

- 双击 **`启动下载-直连.bat`**；
- 或命令行：

  ```powershell
  python .\wnacg_dl.py --direct "https://www.wnacg.com/photos-index-aid-383877.html"
  python .\wnacg_web.py --direct
  ```

Web UI 顶部的网络状态会显示 **“直连（DoH）”**。

实测在这台机器上：

- 详情页、封面、ZIP 直链（HTTP 206）都能直连；
- 9.6 MB 的测试压缩包约 4 秒下完，PDF 正常生成。

限制：

- 只绕过 **DNS 污染**；如果所在网络同时对 Cloudflare IP 或 TLS SNI 做了封锁，
  直连仍然会失败，需要代理；
- DoH 依赖 `doh.pub` 可访问；如果它也被封，需要换 DoH 服务或继续用代理；
- 直连模式会显式禁用系统代理，不会偷偷走代理。

### 浏览器直接访问

如果只想用浏览器看网页，可以把浏览器的“安全 DNS / Secure DNS”设为自定义：

```text
https://doh.pub/dns-query
```

然后直接打开 <https://www.wnacg.com/>。这不会影响下载脚本，脚本用
`--direct` 即可。

---

## iPhone / iPad 使用

### 方案一：添加到主屏幕（现在就能用）

1. 在电脑上双击 **`启动下载-手机.bat`**（直连 + 监听局域网）；
2. 启动窗口会显示类似：

   ```text
   手机访问（同一 Wi-Fi）：
      http://192.168.1.6:8765/
   ```

3. iPhone 连接同一个 Wi-Fi，用 Safari 打开这个地址；
4. 点 Safari 底部的“分享” → **“添加到主屏幕”**；
5. 之后从桌面图标启动，就是全屏的独立界面（PWA），和 App 很接近。

说明：

- 服务仍然运行在电脑上，电脑需要开机并保持窗口不关；
- 下载的 ZIP / PDF 保存在电脑的 `downloads` 目录；
- 在 iPhone 上点“下载 ZIP”或“下载 PDF”，Safari 会保存到“文件”App；
- 只建议在可信的家庭 Wi-Fi 下使用；当前没有加访问密码；
- 第一次启动如果 Windows 防火墙弹窗，请允许“专用网络”；
- 如果 iPhone 打不开，可用管理员 PowerShell 放行端口：

  ```powershell
  New-NetFirewallRule -DisplayName "wnacg web" -Direction Inbound `
    -Protocol TCP -LocalPort 8765 -Action Allow -Profile Private
  ```

如果要在外面也能用，可以在电脑和 iPhone 上装 Tailscale / ZeroTier，
然后用电脑的虚拟局域网 IP 访问，不需要公网端口映射。

### 方案二：真正的 IPA（需要 Mac）

在当前 Windows 环境里**无法直接生成可安装的 IPA**，因为：

- IPA 需要 macOS + Xcode 编译；
- 需要 Apple 账号签名（免费账号 7 天有效，AltStore/Sideloadly 侧载，
  或 99 美元/年的开发者账号）；
- 未签名的 IPA 不能直接装到非越狱 iPhone；
- iOS 也不允许普通 App 像桌面一样长期跑 Python 本地服务器。

如果确实要做原生 App，可行路线是：

1. **SwiftUI 原生 App**：URLSession 下载、PDFKit 生成 PDF、保存到“文件”；
   需要 Mac + Xcode 编译签名；
2. **BeeWare / Briefcase**：把 Python 逻辑打包成 iOS App，仍然需要 Mac 构建；
3. 在 iPhone 上装 Pythonista / a-Shell 运行改编脚本（无需 IPA，但不是独立 App）。

如果你有 Mac，我可以下一步给你搭一个 SwiftUI 工程骨架；否则 PWA 是当前
最省事、马上能用的方案。

---

## Web UI 功能

### 作品预览

粘贴作品链接后，右侧预览栏会自动请求详情页并显示：

- 封面
- 标题
- 分类、页数、投稿者、上传日期、收藏数
- 标签
- “打开原页”和“下载此作品”按钮

预览是服务端解析后的结构化卡片，不是直接嵌入原站 iframe（原站有广告且通常禁止被嵌入）。
预览结果会缓存 10 分钟，避免重复请求。

### 任务

- **开始下载**：支持一次粘贴最多 30 个链接，队列串行处理。
- **同时生成 PDF**：默认勾选；取消后只下载 ZIP。
- **PDF DPI**：默认 300（最高），只影响 PDF 页面物理尺寸，不改变图片像素；数值越大页面越小。
- **JPG 质量**：默认 100（最高），用于把 PNG / WebP 等转成 PDF 内嵌图；JPG 原图不受影响。
- **覆盖已有文件**：重新下载 ZIP 并重新生成 PDF。
- **取消**：运行中或排队中的任务可以取消；已经下载的部分会保留为 `.part`，下次同链接会续传。
- **重试**：失败（或已取消）的任务卡片上会显示“重试”按钮，按原来的链接、PDF 设置重新入队；已有的有效 ZIP 会跳过，未完成的部分会续传。
- **清空已完成**：只清理网页上的任务卡片，不删除磁盘文件。
- **打开文件夹**：直接打开保存目录。

### 进度

- 解析：正在请求作品页 / 下载页；
- 下载：显示百分比、已下载 / 总大小；
- PDF：显示当前页 / 总页数；
- 停滞保护：超过 75 秒没有收到新数据会自动断开并续传重试，避免任务永远卡住。

### 文件

- **打开 PDF**：浏览器内直接预览（流式传输）；
- **下载 PDF**：保存到浏览器下载目录；
- **下载 ZIP**：下载原始压缩包。

---

## PDF 说明

- **JPG**：原始 JPEG 字节直接嵌入 PDF（`DCTDecode`），不重编码、不损失画质，PDF 大小 ≈ ZIP 内图片总和。
- **PNG / WebP / GIF / BMP / TIFF**：用 Pillow 解码后以最高质量 JPEG（默认质量 100，4:4:4 不抽样）嵌入。体积会明显大于质量 90（实测 13 张 PNG：90 → 10.8 MB，100 → 20.7 MB），但画质优先；想控制体积可以在网页里把“JPG 质量”调到 90 或 95，或使用 CLI 的 `--pdf-quality 90`。
- 透明背景合成白底；16 位灰度、CMYK、EXIF 旋转会自动处理。
- 损坏图片会跳过并记录日志；如果一张都读不出来则报错。
- PDF 先写 `.part`，成功后再改名，避免留下半截文件。

### 需要安装 Pillow 吗？

- **纯 JPG**：不需要，脚本只用标准库。
- **PNG / WebP / GIF / CMYK / 带旋转的 JPEG**：需要 Pillow。
  本机已安装（Pillow 12.3.0）；换电脑时执行：

  ```powershell
  pip install pillow
  ```

没有 Pillow 时，脚本会明确提示，不会静默生成坏 PDF。

---

## 原有命令行模式

Web UI 不影响原来的 CLI，适合批量或脚本调用：

```powershell
# 下载 + PDF
python .\wnacg_dl.py "https://www.wnacg.com/photos-index-aid-383877.html"
python .\wnacg_dl.py 383877 383000 399799
python .\wnacg_dl.py -i urls.txt -o D:\manga

# 只下载 ZIP
python .\wnacg_dl.py --no-pdf URL

# 只把本地 ZIP 转 PDF（不联网）
python .\wnacg_dl.py --from-zip "downloads\作品.zip"
python .\wnacg_dl.py --from-zip downloads
```

CLI 常用参数：

| 参数 | 说明 |
| --- | --- |
| `-o, --output 目录` | 保存目录，默认 `./downloads` |
| `--proxy URL` / `--no-proxy` | 指定代理 / 强制直连 |
| `--direct` | DoH 直连模式（无需代理，适合仅 DNS 污染的网络） |
| `--cookie "..."` | 额外 Cookie，用于 Cloudflare 验证或登录限定内容 |
| `--overwrite` | 覆盖已存在的 ZIP / PDF |
| `--no-pdf` | 只下载 ZIP |
| `--pdf-dpi DPI` | PDF 页面尺寸，默认 300（最高） |
| `--pdf-quality 质量` | 非 JPEG 图片的 JPEG 质量，默认 100（最高） |
| `--from-zip ZIP...` | 离线转换成 PDF |
| `--dry-run` | 只解析，不下载 |

---

## 常见问题

### 1. 提示“备用直链失效（HTTP 404）”

通常出现在**刚上传不久**的作品上：Server 2 还没同步到该文件。

可以：

1. 过一段时间再试；
2. 用浏览器打开下载页，点 **Server 1** 手动下载；
3. 如果 Server 1 也被人机验证拦住，可先在浏览器访问
   <https://d1.wcdn.date/> 并通过验证，然后在开发者工具 →
   Application/Storage → Cookies 中复制 `cf_clearance`，再运行：

   ```powershell
   python .\wnacg_dl.py --cookie "cf_clearance=..." --user-agent "你的浏览器 UA" 399788
   ```

### 2. 提示“被 Cloudflare 人机验证拦截”

同上。`--cookie` 需要包含有效的 `cf_clearance`，且 `--user-agent`
要与浏览器一致。

### 3. 任务一直不动

脚本有 75 秒停滞保护，会自动断开并续传。若代理本身不稳定，可以：

- 换一个代理节点后重新提交；
- 或先关闭任务，等网络恢复后重新提交（会从 `.part` 续传）。

### 4. 下载很慢 / 连不上

- 默认自动读取系统代理（Clash 的 `127.0.0.1:7890` 等）；
- 也可以启动时指定：`--proxy http://127.0.0.1:7890`；
- 不想走代理：`--no-proxy`。

### 5. 这是“合集 / 系列”页面

合集页面本身没有单个 ZIP，脚本会提示你改用其中某一话的作品链接。

### 6. 端口被占用

服务会自动从 `8765` 往后找空闲端口，具体地址看启动窗口。如果 `8765` 被之前的窗口占用，会提示并改用 `8766`，以启动窗口显示的地址为准。也可以手动指定：

```powershell
python .\wnacg_web.py --port 9000
```

### 7. 需要登录才能看的内容

CLI 可以把浏览器 Cookie 传给脚本：

```powershell
python .\wnacg_dl.py --cookie "从浏览器复制的 Cookie" URL
```

Web UI 暂未提供 Cookie 输入框。

---

## 注意事项

- 仅供个人学习、备份使用；请遵守网站条款，不要高频、批量地请求。
- 下载内容的版权归原作者及发布者所有，请在 24 小时内删除。
- 网站结构可能随时调整；如果页面解析失效，任务卡片会显示明确错误。

# 开发日志 / WORKLOG

记录每次开发会话的改动、验证与发布。新条目写在最上面。

---

## 2026-11-06（第十二轮：iOS 阅读器按钮与灵动岛齐平）

- 阅读器悬浮按钮（关闭/页数/刷新）之前虽然上移到顶部两角，但仍在安全区下方，视觉比灵动岛低；
- `readerChrome()` 加 `.ignoresSafeArea(edges: .top)`，top padding 10 / 水平 24；
- XCUITest 实测 iPhone 17 Pro（402×874pt）：关闭按钮 `x=23.75, y=9.75, 40.5×40.5`，与灵动岛同一行；
- UI 测试新增断言 `frame.minY < 24` 防回归；
- iOS 26.2 全流程 + iOS 18.x 分类回归均通过；
- **v1.24.4（build 266）**：<https://github.com/2744317644/wancg-downloader/releases/tag/v1.24.4>（仅 IPA）。

---

## 2026-11-06（第十一轮：Windows PDF 横竖页排版与 iOS 对齐）

- 原 Windows PDF 每页宽度 = 图片宽 × 72/144，横版页和竖版页宽度不同，阅读器里横版会显得更宽；
- 改为和 iOS 一致的排版：**所有页固定 595pt 宽，页高 = 图片高 × (595 / 图片宽)**；
- 竖版页变高、横版页同宽较矮，混排时页面宽度一致；JPEG 仍原样 DCTDecode 嵌入；
- 用 800×1200 竖图 + 1600×900 横图生成测试 PDF：两页 `Windows.Data.Pdf` 报告宽度均 793.33px（595pt），页高 1190px / 446.25px；
- 版本 1.0.2，发布 win-v1.0.2。

---

## 2026-11-06（第十轮：Windows 客户端补上 PDF 输出）

- `windows/WnacgDownloader/Core/PdfBuilder.cs`：极简 PDF 1.4 写入器，每页一张全幅图片；JPEG 直接 `DCTDecode` 嵌入，不重编码；
- `AppSettings.CreatePdf`（默认 true），设置页新增「下载完成后生成 PDF」；
- `DownloadService` 在图片下载 / ZIP 打包后生成 `<作品名>.pdf`，进度写入下载队列；
- `SmokeTest` 增加 PDF 结构/页数校验；新增 `windows/PdfCheck` 用 `Windows.Data.Pdf` 渲染首屏验证；
- 实测 197 页作品：PDF 104 MB / 197 页 / 结构有效 / 首屏渲染正确；
- 版本 1.0.1，发布 win-v1.0.1（zip，无截图）。

---

## 2026-11-06（第九轮：Windows WinUI 3 原生客户端）

### 新增 `windows/`

- 新项目 `windows/WnacgDownloader`：.NET 8 + Windows App SDK 1.8（WinUI 3），**unpackaged + self-contained**，解压运行 `WnacgDownloader.exe`；
- 功能：
  - 链接解析 → 封面/标题/页数/标签 → 预览 / 下载；
  - 浏览器书签 HTML / 链接列表导入 → 多选批量下载；
  - 软件内漫画滚动预览（并发加载）；
  - 设置：下载目录（FolderPicker）、系统代理 / 自定义 `127.0.0.1:端口` / DoH 直连、图片并发、ZIP 打包；
  - 下载队列：进度/速度、取消、打开文件夹。

### 核心实现

- `WnacgClient`：`SocketsHttpHandler` 三模式（系统代理 / 自定义代理端口 / DoH ConnectCallback）；正则解析移植自 iOS/Python；
- `DohResolver`：Cloudflare + AliDNS/DoH.pub 回退，TLS + SNI 校验 IP 后缓存 10 分钟；
- `DownloadService`：并发下载阅读页图片 → 文件夹 + `info.txt` + 可选 ZIP；
- `SmokeTest` 控制台：代理与 DoH 两种模式都验证了解析、197 个图片地址、首图；代理模式额外完整下载 197 页并打包 ZIP。

### 踩坑

- Windows App SDK 的 `Frame.Navigate` 在本机 Windows 10 上直接 `0xC0000005` 崩溃（页面构造前），改为 `NavigationView.Content` 直接切换页面；
- 125% DPI 下窗口初始尺寸偏小，`AppWindow.Resize(1400,950)` 并在 UI 自动化中等待窗口稳定；
- 用 PowerShell 写含中文的 JSON 时曾被终端编码搞坏路径，改用 `Environment.GetFolderPath` 构造。

### 构建/验证

- `dotnet publish` 产出 328 个文件 / 约 215 MB，zip 约 85 MB；发布版 exe 启动正常；
- UI 自动化截图验证（本地，不上传）：下载页、解析结果、预览、书签、设置；下载队列显示 39/197 进度；
- 发布：**win-v1.0.0**（zip 附在 GitHub Release，不含截图）。

---

## 2026-11-05（第八轮：阅读器操作按钮上移到顶部两角）

- 用户截图指出关闭（×）/ 页数（23P）/ 刷新三个悬浮按钮位置偏低，压在第一格漫画/对白上；
- `readerChrome()` 去掉 `safeAreaInsets` 计算，改为 `padding(.top, 10)` + `padding(.horizontal, 24)`，贴合屏幕顶部两角，避开灵动岛与圆角；
- 单击切换沉浸、左缘右滑返回、滚动进度 HUD、右缘页码条保持不变；
- 验证：iOS 26.2 全流程 UI + iOS 18.x 分类回归通过；Release 编译 + smoke test 通过；
- **v1.24.3（build 265）**：<https://github.com/2744317644/wancg-downloader/releases/tag/v1.24.3>（仅 IPA，无截图）。

---

## 2026-11-05（第七轮：public 化解决 Actions 额度 + 清理 GitHub 截图 + 阅读器沉浸修复）

### Actions 额度

- private 仓库的 Actions 分钟数用尽，macOS job 排队约 15 分钟后被取消；
- 按 GitHub 计费文档，**public 仓库的标准 GitHub-hosted runner 免费**，已把仓库转为 public（`2744317644/wancg-downloader`）；
- runner 从 `macos-15` 切到 `macos-26`（该镜像含 Xcode 26.3），恢复后构建/UI 测试正常启动。

### 清理 GitHub 上的截图（public 合规）

- 删除 v1.21.0–v1.24.1 共 **33 个**截图类 release assets；
- 从 v1.21.0–v1.21.4 共 **5 个** release 说明中移除内嵌图片 markdown；
- 删除 **41 个**包含截图/xcresult 的 Actions artifacts；
- `ui-preview.yml` 不再收集/上传截图与 `.xcresult`，只上传文本日志；Release 从现在起只附 IPA。

### v1.24.2 阅读器修复

- 沉浸切换导致画面上移：根因是隐藏导航栏/状态栏改变了 ScrollView 的 safe area；
- 改为**全屏内容 + 悬浮 chrome**（关闭/页数/刷新悬浮在图片上），状态栏/导航栏常驻隐藏，切换只改 opacity，画面不再移动；
- 保留左缘右滑返回、滚动进度 HUD、右缘页码条。

### 测试调整

- walkthrough 通过后，同一次 `xcodebuild test` 里的分类页测试因站点 429 没拿到「同人志」chip（历史审计也提示过这个串扰）；
- 改为两套独立 `xcodebuild test` 会话、分类页先跑；失败日志分别上传。

### 发布

- IPA 已验证 **1.24.2 / build 264**，Release **只附 IPA、不含截图**；
- UI 测试重跑通过：iOS 26.2 完整全流程 + iOS 18.x 分类页回归；
- **v1.24.2**：<https://github.com/2744317644/wancg-downloader/releases/tag/v1.24.2>

---

## 2026-11-04（第六轮：详情页背景优化 + 阅读器左缘返回手势）

### 详情页背景返工

- 第五轮的全宽模糊封面会把标题和元信息糊在一起，观感偏脏；
- 改为**封面同色柔光晕**：模糊图限制在左侧封面缩略图附近（190×220），径向遮罩渐隐，opacity 0.40；
- 标题/分类/页数/上传者区域保持干净，保留淡入与失败降级。

### 阅读器左缘返回

- 新增左缘右滑返回手势：起点距左边缘 <32pt、横向位移 >90pt 且以横向为主时 `dismiss()`；
- 与单击沉浸、纵向滚动、右缘页码拖动条互不冲突。

### 验证与发布

- iOS 26.2 全流程 UI 测试通过；iOS 18.x 分类页回归通过；Release 编译/smoke test 通过。
- **v1.24.1（build 263）**：<https://github.com/2744317644/wancg-downloader/releases/tag/v1.24.1>

---

## 2026-11-04（第五轮：阅读器沉浸模式 + 下载仪表盘 + 详情封面氛围）

### 阅读器

- 单击页面进入沉浸模式：隐藏导航栏、状态栏和工具栏；再单击恢复（`chromeHidden` + `.toolbar(.hidden)` + `.statusBarHidden`）。
- 右缘页码拖动条加宽到 32pt，并加 6pt 触发阈值，减少误触跳页。
- 保留滚动进度 HUD。

### 下载页

- 新增「最近下载」卡片：最近 3 个 ZIP/PDF、大小、时间、分享按钮，「全部文件」跳到文件 tab（`ContentView` 增加 `selectedTab` binding）。
- 下载 tab 角标 = 进行中任务 + 排队数量。

### 详情页

- 封面模糊渐隐 hero 背景（`CoverImageStore` 取封面，opacity 0.30 / blur 28 / mask 渐隐），作为 header 的 background 不改变布局。

### 编译插曲

- `ForEach(recentFiles)` 在 Xcode 26.3/SwiftUI 下被错误解析为 Binding overload；依次尝试 `id: \.url`、`indices`、`Range` 均失败，最终改为**展开最多 3 行**（列表本来固定 3 条）+ 补 `RecentDownload.name` 访问器后编译通过。
- 期间本机 FlClash 代理端口短暂未监听导致 push 失败，恢复 7890 后推送成功。

### 验证与发布

- iOS 26.2 全流程 UI 测试通过；iOS 18.x 分类页回归通过；Release 编译/smoke test 通过。
- **v1.24.0（build 262）**：<https://github.com/2744317644/wancg-downloader/releases/tag/v1.24.0>

---

## 2026-11-04（第四轮：主线程零阻塞 + 体验增强 + 双 iOS CI）

### 稳定性

- `ProxySession` 改为懒启动：代理 listener 启动（最长 5s）不再发生在 App 启动/回前台/阅读器重载/设置切换的主线程上；启动与回前台重启都移到后台线程，并用 NSCondition 让并发请求等待首次启动完成。
- `WnacgApp` 去掉启动时直接 `LocalProxy.start()` 的阻塞调用，改为后台预热。

### 下载体验

- 下载进度、Live Activity、PDF 进度更新全部节流（进度 UI ≤10 次/秒、Live Activity ≤2 次/秒、PDF ≤6.7 次/秒）。
- 下载页新增「下载队列」卡片：显示排队作品、数量，可逐个取消排队（`AppModel.cancelQueued`）。

### 阅读 / 详情

- 阅读器新增滚动进度 HUD（「37% · 共 126P」，滚动出现 1.5s 后淡出；进度来自真实滚动偏移）。
- 详情页标签默认折叠为 8 个，可展开全部；标签点击目标 44pt。

### CI

- `ui-preview.yml` 新增 `legacy-runtime` 并行 job：自动选择最旧可用 iOS runtime（当前 18.x）跑分类页回归，覆盖 iOS 17/18 兼容性；主 job 继续在最新 iOS 26.2 跑完整全流程测试。
- 两个 job 均通过；Release 编译与 smoke test 通过。

### 发布

- **v1.23.0（build 261）**：<https://github.com/2744317644/wancg-downloader/releases/tag/v1.23.0>

---

## 2026-11-04（第三轮：技能库多代理审计 + 稳定性/性能修复）

### 使用 E:\Code\Skills 派出 4 个并行子 agent

用技能库里的四个技能做只读审计（报告在 `docs/qa/`）：

- `review-swarm` → `docs/qa/review-swarm-v1.22.0.md`（v1.21.4..v1.22.0 diff 的回归/安全/可靠性/契约审查）
- `swiftui-performance-audit` → `docs/qa/swiftui-performance-audit-v1.22.0.md`
- `swiftui-ui-patterns` + `swiftui-liquid-glass` → `docs/qa/ui-patterns-review-v1.22.0.md`
- `swift-concurrency-expert` → `docs/qa/concurrency-review-v1.22.0.md`

### 按报告修复

- 分类页自动重试任务会取消自己（`load()` 取消 `recoveryTask`），重试以 -999 失败 → 修正。
- 代理重启 `invalidateAndCancel()` 共享 session 导致兄弟请求 -999 失败 → 将 -999 纳入重试。
- 本地代理启动失败一次后 `startupError` 粘滞 → 请求前尝试重启一次。
- 阅读器补 `.preferredColorScheme(.dark)` + 深色工具栏（修 iOS 17/18 浅色下标题不可见）。
- `seamlessNavigationBar()` 只在 iOS 26 隐藏背景，旧系统保留系统导航栏背景。
- 性能：正则缓存、页面解析移出主线程、磁盘封面 ImageIO 预解码、收藏文件匹配改集合、文件列表 stat 只读一次、默认关闭空 120Hz display link。
- 44pt 触摸目标：粘贴/复制/收藏/首页 chips/更多。
- CI：`ui-preview.yml` 现在在 main 的 `ios/**` 变更时自动跑；全流程测试增加“解析后键盘自动收起”断言。

### 发布

- **v1.22.1（build 260）**：<https://github.com/2744317644/wancg-downloader/releases/tag/v1.22.1>
- 验证：iOS 26.2 模拟器全流程 + 分类页回归通过；Release 编译/smoke test 通过。

---

## 2026-11-04（第二轮：全流程 QA + UI 美化）

### 全流程模拟器走查

新增 `ios/UITests/AppWalkthroughUITests.swift`，在 iOS 26.2 / iPhone 17 Pro 模拟器上自动走完整 App 并逐屏截图 + 输出无障碍树：

- 首页（光/暗）与下拉刷新 → 搜索「love」→ 分类页 → 详情页 → 阅读器 → 下载页（真实解析一部作品）→ 收藏 / 文件 / 历史 / 设置（含深色模式切换与设置项检查）。
- 两个测试（全流程走查 + 分类页回归）均通过。

### 发现并修复

- **下载页解析后键盘遮挡底部页签栏**：点「解析作品」时主动收起键盘，并增加键盘「完成」按钮（此前 XCUITest 也因键盘遮挡无法切页）。
- 走查同时确认分类页自动加载、阅读器返回底栏、搜索/详情/设置等流程正常。

### UI 美化

- 新增 `AppBackground` 统一全 App 渐变背景（首页/分类/详情/下载/收藏/文件/历史/空状态）。
- 首页：骨架屏加载（替换居中菊花）、栏目头显示「N 部」、扩大「更多」点击区域。
- 详情页：「开始阅读」改为强调色主按钮，「下载 ZIP + PDF」改次级按钮；「标签」「看过这本的人也看了」统一章节标题样式；复制标题按钮加大点击区域；推荐卡片加按压反馈。
- 下载页：新增「粘贴」按钮从剪贴板填入链接。
- 设置页：「关于」增加构建号和「查看最新版本」链接。
- 收藏卡片统一按压缩放反馈。

### 发布

- **v1.22.0（build 259）**：<https://github.com/2744317644/wancg-downloader/releases/tag/v1.22.0>
- 验证：iOS 26.2 模拟器全流程 + 分类页回归测试通过；Release 编译/ smoke test 通过。

---

## 2026-11-04

### 工作区整理

- 将 `E:\Code\manga-downloader` 从本地旧状态（`31e9e3b Initial iOS app and web downloader` + 大量未提交改动，对应 v1.20.4 前后）同步到 `origin/main`（`46ad229`，即 v1.21.4 代码 + iOS 26 UI 测试工作流）。
- 旧工作区已用 `git stash` 保存，可随时找回：
  - `git stash list` → `stash@{0}: On main: pre-sync old v1.20.4 workspace 2026-11-04`
- 本地调试产物（CI 的 `job.log`、`tree.json`）已备份到
  `E:\Code\manga-downloader-local-backup-20261104\`，并保留在工作区（未跟踪）。
- 对比结论：旧工作区里 Python / webui / 图标 / loon / CI 文件与当前版本**字节级一致**；iOS 源码是旧版（9 宫格翻页器、阅读器 push 等），差异全部是当前 v1.21.x 新版覆盖旧版，没有需要反向合入的内容。

### 本次会话完成的版本（均已发布）

| 版本 | build | 内容 |
| --- | --- | --- |
| v1.21.0 | 254 | 二级分类页重做：删除「每页固定 9 部 + 居中悬浮 ‹1/N› 翻页器」，改为连续自适应网格（iPhone 3 列 / iPad 自动增列）；顶部可见筛选胶囊 + 屏蔽 AI；骨架屏、下拉刷新、内联错误重试、44pt 触摸目标；去掉第二条底栏。 |
| v1.21.1 | 255 | 修复「加载更多总失败要下拉刷新」：根因是触底哨兵 `.id` 重建导致连环请求 → 站点 429；改为稳定触发 + 请求最小间隔 1.1s + Referer + 空页/回环保护 + 429 文案 + 明确「加载更多」兜底按钮。性能：筛选分类缓存到 model、封面卡 `Equatable`、去掉嵌套 `LazyVStack`、缩略图 JPEG 编码移到后台；修复请求取消后 `isLoading` 卡死。 |
| v1.21.2 | 256 | 修复「必须点加载更多才刷新」：触发点从非懒加载的外层 VStack 哨兵改为 `LazyVGrid` 末行卡片 `onAppear`，提前 9 部预取；末尾行会被下一页封面填满。 |
| v1.21.3 | 257 | 网格内懒哨兵（每页重新武装）+ 预取提前到 12 部；请求间隔 0.7s；失败后自动静默重试最多 2 次（2.5s 后），单次网络抖动自愈。 |
| v1.21.4 | 258 | 阅读器由 NavigationLink push 改为 **fullScreenCover**，移除 `.toolbar(.hidden, for: .tabBar)`，返回时底栏不再延迟弹出；阅读器左上角新增关闭按钮（xmark）。 |

发布页：<https://github.com/2744317644/wancg-downloader/releases>

### CI / 验证

- 新增模拟器 UI 测试（`ios/UITests/CategoryScreenUITests.swift` + `.github/workflows/ui-preview.yml`），覆盖：
  - 分类页 3 列布局、单条原生 TabBar、无旧页码控件；
  - 滑动自动加载（不点按钮）：已加载数 `100 → 120 → 160 → 180`，无失败；
  - 筛选切换、详情页跳转、阅读器打开/关闭 + 关闭后底栏立即存在断言；
  - 截图自动上传为 artifact。
- UI 工作流改为**自动选择最高 iOS runtime**：macOS runner 上可用 iOS 26.0 / 26.1 / 26.2，现固定跑 **iOS 26.2 + iPhone 17 Pro**（之前误用列表第一台 iPhone 16 Pro / iOS 18.5，截图是 iOS 18 风格）。
- 每次发布均通过：Release 编译、macOS 代理/解析 smoke test、IPA 打包与上传。

### 验证截图

- `docs/screenshots/`（本地）：分类页、自动加载后、iOS 26 版分类页/阅读器截图等。
- GitHub Release assets 含 `WnacgDownloader-unsigned.ipa` 与若干截图。

### 备注

- 本机 Windows 上无法运行 dsh-ios 模拟器工具；UI 验证统一走 GitHub Actions 的 macOS 模拟器。
- GitHub 直连曾多次中断，部分提交通过 GitHub API 直写远端；现已正常 fetch/push。

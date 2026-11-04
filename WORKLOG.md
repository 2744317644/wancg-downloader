# 开发日志 / WORKLOG

记录每次开发会话的改动、验证与发布。新条目写在最上面。

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

# 开发日志 / WORKLOG

记录每次开发会话的改动、验证与发布。新条目写在最上面。

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

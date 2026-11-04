## 用技能库做了一次多代理审计：修掉一批稳定性/性能问题

这版用 `E:\Code\Skills` 里的 review-swarm、swiftui-performance-audit、swiftui-ui-patterns、swift-concurrency-expert 四个技能并行审计了 v1.22.0 的代码，按报告修掉了高风险项，并补上了 UI 测试门禁。

### 修复

- **分类页“自动重试”实际无效**：失败后的恢复任务调用 `load()` 时会把自己 `cancel` 掉，重试请求随即以 `-999` 取消并显示错误。已修正。
- **代理重启会误杀同 session 的其它请求**：代理重启会 `invalidateAndCancel()` 共享 URLSession，封面/列表等兄弟请求以 `-999` 失败且不重试。现在 `-999` 会走重试。
- **本地代理启动失败一次后永久卡死**：`startupError` 是粘滞的，之前只能靠切后台再回来恢复；现在请求时会先尝试重启一次代理。
- **阅读器在 iOS 17/18 浅色模式下标题/页码不可见**：阅读器没有声明深色配色，iOS 26 的玻璃导航栏掩盖了这个问题。已显式 `.preferredColorScheme(.dark)` + 深色工具栏。
- **iOS 17/18 导航栏隐藏背景导致内容与标题重叠**：`seamlessNavigationBar()` 现在只在 iOS 26 启用（旧系统保留系统背景）。

### 性能

- 页面 HTML 解析移出主线程；`HTMLParser` 的正则改为缓存复用（此前每张卡片会编译十几次 `NSRegularExpression`）。
- 磁盘缓存封面改用 `CGImageSource` 预解码缩略图（此前 `UIImage(contentsOfFile:)` 会在主线程懒解码，暖图一页 20 张时掉帧）。
- 收藏的本地文件匹配改为一次性文件名集合（此前每次出现都做 O(收藏×文件) + 正则）。
- 文件列表的 `stat` 只在初始化时读一次，不再在排序比较器里反复读盘。
- 默认关闭空的 120Hz CADisplayLink（只耗电、没有确认的渲染收益），需要时可在设置里手动开启。

### 交互

- 粘贴 / 复制标题 / 收藏 / 首页分类 chips / “更多”等触摸目标统一到 44pt。
- 首页移除容易误解的“预览 N 部”计数。

### CI

- UI 测试现在会在 **main 分支的 iOS 改动**时自动运行（此前只有手动 dispatch / 旧分支触发），新增“解析后键盘必须自动收起”的断言；仍固定跑最新 iOS runtime。

版本 **1.22.1**（build 260），unsigned IPA 见下方 Assets。

## 阅读器沉浸模式不再让画面跳动

### 问题

切换沉浸模式时，旧实现用 `.toolbar(.hidden, for: .navigationBar)` + `.statusBarHidden(...)` 隐藏系统栏。隐藏导航栏/状态栏会改变 ScrollView 的安全区域（safe area inset），SwiftUI 重新布局并调整内容内缩，视觉上就是**漫画向上跳一下**。

### 修复

- 阅读器改为**全屏内容 + 悬浮 chrome**：
  - ScrollView 使用 `.ignoresSafeArea()` 全屏出血，页面图片延伸到屏幕边缘；
  - 关闭 / 页数 / 刷新按钮改成悬浮在图片上的毛玻璃圆钮（保留 `reader-close-button` 标识）；
  - 状态栏常驻隐藏，导航栏常驻隐藏；
- 切换沉浸模式只改变悬浮 chrome 的 **opacity**，不增删任何参与布局的视图，safe area 不变 → 画面完全不动；
- 保留单击切换、左缘右滑返回、滚动进度 HUD、右缘页码条。

### 验证

- Release 编译 + 真实站点 smoke test 通过；
- iOS 26.2 完整全流程 UI 测试通过（阅读器打开/关闭、tab bar 回归）；
- 最旧 iOS（18.x）分类页回归通过。

版本 **1.24.2**（build 264），unsigned IPA 见下方 Assets。

### 发布策略变更

- 仓库已转为 **public**（标准 GitHub-hosted runner 免费，CI 不再受私有仓库分钟数限制）；
- **从本版起 Release 只附 IPA，不再附带截图**；CI 也只上传文本日志，不上传截图/.xcresult，避免把站点画面公开到 GitHub。


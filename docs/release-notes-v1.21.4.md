## 从阅读器返回时，悬浮底栏不再「弹出来」

之前「开始阅读」是用 NavigationLink push 进入阅读器，阅读器里用 `.toolbar(.hidden, for: .tabBar)` 隐藏了原生页签栏；返回时系统要把页签栏重新显示出来，于是会看到它慢半拍「弹出来」。

这版改为：

- 阅读器通过 **全屏 cover** 呈现（和「文件 → 打开已下载 PDF」的交互方式一致），阅读时页面覆盖在 App 之上，页签栏从未被隐藏/恢复，返回时它**本来就在**，不再有弹出延迟；
- 阅读器导航栏左上角新增 **关闭按钮**（`xmark`），点击即可回到详情页；
- 移除了阅读器里的 `.toolbar(.hidden, for: .tabBar)`。

### 验证

模拟器 UI 测试：详情页点「开始阅读」→ 阅读器全屏打开 → 点左上角关闭 → 断言页签栏立即存在，并连续截图确认；此前的自动加载 / 筛选 / 详情跳转用例仍然通过。

![阅读器](https://github.com/2744317644/wancg-downloader/releases/download/v1.21.4/reader.png)

![返回详情页](https://github.com/2744317644/wancg-downloader/releases/download/v1.21.4/after-reader.png)

版本 **1.21.4**（build 258），unsigned IPA 见下方 Assets。

**补充验证（iOS 26）**：已使用 iOS 26.2 / iPhone 17 Pro 模拟器重跑完整 UI 测试并通过，iOS 26 风格截图见 category-ios26.png、reader-ios26.png。

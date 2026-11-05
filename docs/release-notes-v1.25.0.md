## 只支持 iOS 26+，阅读器按钮换成液态玻璃

### 最低系统版本改为 iOS 26

- `deploymentTarget` 从 iOS 17 提升到 **iOS 26.0**（App、Widget、UITests 全部）；
- 低于 iOS 26 的设备**无法安装/使用**，不再做旧系统适配；
- CI 删除 `legacy-runtime`（最旧 iOS 18.x 回归）job，只跑最新 iOS 26 模拟器；文档同步更新。

### 阅读器液态玻璃

- 顶部「关闭 / 页数 / 刷新」三个悬浮控件改用 iOS 26 Liquid Glass：
  - `GlassEffectContainer` 分组；
  - 按钮：`.glassEffect(.regular.interactive(), in: Circle())`；
  - 页数胶囊：`.glassEffect(.regular, in: Capsule())`；
- 底部滚动页数进度胶囊（如「0% · 共 23P」）同样改成 Liquid Glass；
- 位置不变：按钮顶部仍与灵动岛底部齐平，UI 测试的 `minY` 断言保留。

### 验证

- Release 编译成功（iOS 26.3 / iOS 26.2 模拟器）；
- 全流程 UI 测试只在最新 iOS 26 runtime 上运行；
- 版本 **1.25.0**（build 269）。

> 本 Release 只附 unsigned IPA，不包含截图。

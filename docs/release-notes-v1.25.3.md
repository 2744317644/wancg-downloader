## 修复阅读器左上角关闭/返回按钮点按无反应

### 原因

阅读器顶部三个控件用 `GlassEffectContainer` + `.glassEffect(.interactive())` 包在一起。Liquid Glass 的交互玻璃层会参与命中测试，部分系统/设备上会把本应落到「关闭」Button 的触摸先吞掉，表现为按钮看得到但按了没反应。

### 修复

- 去掉外层 `GlassEffectContainer`，每个控件单独应用玻璃效果；
- 按钮玻璃改为**非交互** `.glassEffect(.regular, in: Circle())`，点击交给 SwiftUI `Button` 自己处理；
- 给关闭/刷新按钮显式加 `.contentShape(Circle())`，命中区域固定为整个玻璃圆形；
- 圆形按钮从 40pt 调到 44pt，符合最小触摸目标；
- 其他：位置、液态玻璃外观、页数 HUD 行为不变。

### 验证

- iOS 26.2 全流程 UI 测试通过（包含打开阅读器 → 点关闭 → 回到详情）；
- 版本 **1.25.3**（build 272）。

> 本 Release 只附 unsigned IPA，不包含截图。

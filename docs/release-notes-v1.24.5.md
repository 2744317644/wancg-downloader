## PDF 阅读器页间黑色间隙修复

### 原因

生成的 PDF 每页图片是铺满页面的（已用 `Windows.Data.Pdf` 逐页渲染确认无页内黑边）。黑色间隙来自 **App 内 PDF 阅读器**：

- `PDFView` 用了深色背景；
- PDFKit 默认显示分页间隙（`displaysPageBreaks`）和页面阴影，连续滚动时两页之间就露出一条深色背景。

### 修复

iOS 文件页的 PDF 阅读器：

- `displaysPageBreaks = false`：连续滚动时不显示分页间隙；
- `pageBreakMargins = .zero`：页间边距归零；
- `pageShadowsEnabled = false`：去掉页面阴影；
- 背景保持深色，但页面已经首尾相接，不再有黑色缝隙。

> 用外部 App（Edge、Adobe、系统「文件」预览等）打开 PDF 时，页间空隙是阅读器自己的分页背景，不属于 PDF 文件内容；要彻底无缝只能用长图 PDF，当前仍保持标准分页 PDF。

### 版本

- **1.24.5**（build 267），Release 只附 unsigned IPA。

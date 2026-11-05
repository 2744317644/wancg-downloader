## Windows WinUI 3 客户端 v1.0.1

新增 **PDF 输出**，修正上一版「暂不支持 PDF」的限制。

### 新增

- **下载后生成 PDF**：设置页新增开关（默认开启），下载完成后把图片按顺序写成一个 PDF：
  - 极简 PDF 1.4 写入器，直接嵌入 JPEG（`DCTDecode`），不重新编码、不损失画质；
  - 每页一张全幅图片，页面尺寸按 144 DPI 换算；
  - 非 JPEG 页面会跳过并在状态里提示；
  - 进度显示在下载队列里（例如 `正在生成 PDF 197/197`）。
- 生成位置：下载根目录下与作品文件夹同名的 `.pdf`。

### 验证

- 完整下载 197 页作品后生成 PDF：104 MB、197 页、`%PDF-`/`%%EOF` 结构校验通过；
- 用 `Windows.Data.Pdf` 实际渲染第一页，确认页面内容正常（渲染工具见 `windows/PdfCheck`）。

### 其他

- 版本号更新为 **1.0.1**；
- 仍为免安装 self-contained x64，Windows 10 1809+ / Windows 11；
- Release 只附 zip，不包含截图。

下载后解压运行 `WnacgDownloader.exe` 即可；首次运行 SmartScreen 选「更多信息」→「仍要运行」。

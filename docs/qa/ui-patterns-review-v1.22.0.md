# wnacg iOS UI/UX 与 SwiftUI 模式评审（v1.22.0）

> **基线**：`main` @ `f605732`（= `v1.22.0`，build 259），`ios/project.yml:5-6` deployment target **iOS 17.0**，TARGETED_DEVICE_FAMILY `1,2`。
> **方式**：只读静态审查 + 仓库内既有截图 / XCUITest 无障碍树。未编译、未运行、未改源码、未提交。
> **证据**：`.gh-artifacts/walk3/*.png` 与 `.gh-artifacts/walk3.log`（iOS 26.2 / iPhone 17 Pro，2026-11-04 走查）；`docs/screenshots/reader.png` 是仓库里唯一可确认的 **pre-iOS 26** 阅读器截图（与 `reader-ios26.png` 成对，按 CI 旧配置应为 iOS 18）。控件尺寸取自 `walk3.log` 的无障碍帧，见附录 A。
> **关联**：`docs/qa/review-swarm-v1.22.0.md`（F4 只跑 iOS 26、F5 粘贴、F6「N 部」）、`docs/qa/concurrency-review-v1.22.0.md`（F2 主线程代理重启、F7「no cancel UI」）；重叠项本文只做 UI 视角补充，不重复论证。
> **严重度**：高 = 用户直接看不清/做不了；中 = 明显不统一或无障碍不达标；低 = 细节与长期项。

## TL;DR

- **没有功能性 UI 阻塞**；iOS 26 上整体观感已经可以发。
- 最该修的是**阅读器 chrome**：黑色画布没有声明深色工具栏，浅色模式 + iOS 17/18 下标题不可见、页码和加载文案发暗（有截图证据，U1）。
- 第二个系统性问题：`seamlessNavigationBar()` 把导航栏背景永久隐藏。iOS 26 上系统会随内容自适应，17/18 不会，滚动时标题直接压在封面上（U2）。
- 第三类：**这轮打磨涉及的控件里仍有几个没守住 44pt**——这版新增的「粘贴」47×29、这版声称已扩大的「更多」37×33 与「复制标题」30×30、标签高 23.3、首页 chips 高 29.3；而分类页 chips 已经是 44。写法已经存在，直接复用。
- 美化空间最大的三块：**阅读器沉浸**、**详情页层级**、**下载页从“一张卡”变成“下载仪表盘”**。

---

## 1. 真实 UI bug / 模式违规

### 1.1 总表（高 / 中）

| ID | 严重度 | 位置 | 现象 | 修法 |
|---|---|---|---|---|
| U1 | **高** | `ReaderView.swift:279-282`, `294-299`, `311-332` | 黑底阅读器没有声明深色工具栏/配色。iOS 17/18 + 浅色模式下标题不可见、页码暗灰、`ProgressView("正在加载图片…")` 与错误说明是深色文字压黑底。iOS 26 的玻璃工具栏会自动适配（`reader-ios26.png` 正常），CI 只跑 26 所以永远发现不了。 | 给阅读器的 `NavigationStack` 加 `.preferredColorScheme(.dark)`，或至少 `.toolbarColorScheme(.dark, for: .navigationBar)`；页码/加载文案随之变亮。 |
| U2 | 中高 | `Theme.swift:3-8`（`seamlessNavigationBar`）+ 9 处调用：`HomeView.swift:299`、`CategoryView.swift:253`、`AlbumDetailView.swift:105`、`ContentView.swift:33`、`FavoritesView.swift:86`、`FilesView.swift:75`、`HistoryView.swift:100`、`SettingsView.swift:137`、`ReaderView.swift:282` | `.toolbarBackground(.hidden)` 永久隐藏导航栏底。`ui-03-category-scrolled.png` 里封面直接滚到标题下；iOS 26 截图中标题变成了白色（系统自适应），iOS 17/18 没有这层适配，也没有原生 scroll edge 衬底。 | iOS 26 去掉这个隐藏（用系统默认滚动边缘效果）；< 26 二选一：保留原生栏背景，或自绘顶部渐隐 scrim。 |
| U3 | 中 | 多处，见 1.2 / 附录 A | 自绘可点控件低于 44pt：粘贴 47×29、打开原页 70×14.3、更多 37×33.3、复制标题 30×30、标签按钮高 23.3、首页 chips 高 29.3、收藏 CTA 370×40。 | `.frame(minHeight: 44)` / `.contentShape(Rectangle())`；分类页的 44pt 写法已经存在，抽成共享样式。 |
| U4 | 中 | `AlbumDetailView.swift:62-99`（错误 71-90、loading 91-98 在推荐位之后），`182-184` | 详情加载失败/进行中的提示排在「看过这本的人也看了」**之后**，首屏看不到；加载中会先渲染「0 页」。 | 状态块移到 `header`/`actionButtons` 之间；页数用 `if let`，没有就整行不显示。 |
| U5 | 中 | `AlbumDetailView.swift:106-117`（导航栏心）与 `288-308`（整行收藏 CTA）；`245-310` 三个 `.plain` 按钮 | 同一个「收藏」动作出现两次；三个同宽 CTA 高 44/46/40，且都是 `.plain` + 自绘背景，**没有任何按压反馈**（系统 `borderedProminent` 在 26 上反而是玻璃质感）。 | 删掉整行收藏按钮（保留导航栏心 + 标题下的小状态），统一 CTA 样式并补 press 反馈；高度统一 48。 |
| U6 | 中 | `CategoryView.swift:228-242`, `235`, `553-566` | 语言/AI 筛选栏在 ScrollView 里，滚 10+ 屏后消失；唯一改筛选的入口不可见。 | `.safeAreaInset(edge: .top)` 固定筛选栏（加材质/玻璃底），并显示「已筛选 · 重置」。 |
| U7 | 中 | `ReaderView.swift:343-383`（`DragGesture(minimumDistance: 0)` 369，宽 24 的命中条 378，覆盖在 274-278） | 阅读器右缘一条 24pt 宽、全高的透明热区，**任何从右缘开始的滑动都会跳页**（竖滑阅读时手正好停在右缘）；也低于 44pt。 | 只有滑块拇指区域可拖（44×44），轨道仅显示；或给手势加方向判定（竖向位移为主时让给 ScrollView）。 |
| U8 | 中 | `HomeView.swift:256-259`（固定 3 列）、`HomeView.swift:238`（缩略图固定 360px） | 首页永远 3 列：iPad 上封面约 320pt、动态字体下标题挤成 2 行截断；iPad 3x 需要约 960px 缩略图，实际只存 360px，封面发糊。分类页已经是自适应列（`CategoryView.swift:210-216`）。 | 复用分类页的 adaptive 列（min 104 / max 154，AX 字号 160/220）；缩略图上限按显示尺寸放大到 ~480-600px。 |
| U9 | 中 | `AlbumDetailView.swift:179`、`412-422`；`HomeView.swift:431-432`；`ContentView.swift:78`；以及大量 `.tertiary` 小字（如 `HomeView.swift:416`、`CategoryView.swift:494-496`, `542`） | `systemMint` 小字压白底对比度约 **2.1:1**（WCAG 小字要求 4.5:1）；`.tertiary` 11pt 也约 2.1:1（「6 部」「已经到底了」）。 | 新增语义 `accentText`（浅色用更深的 teal，深色用 systemMint）专供文字；小字从 `.tertiary` 提到 `.secondary`。 |
| U10 | 中 | `ReaderView.swift:396-398` | 占位高度 = `UIScreen.main.bounds.width * 1.4`：横屏 iPhone 会得到 1200pt+ 空块，iPad 同理；图片加载后高度跳变。 | 用可用宽度（GeometryReader / `containerRelativeFrame`）估算，或用已加载图片的宽高比；至少不要用全屏宽度。 |
| U11 | 中 | `ContentView.swift:100-120`（mint 解析）与 `219-241`（blue 下载）；`AlbumDetailView.swift:247-286` | 下载页两个 58pt 同等重量的主按钮，却用两种强调色（mint / blue），同屏还有蓝色标签、蓝色上传者、mint 链接；详情页主按钮是自绘 flat mint。全 App 主按钮有 3 种表达。 | 一个主色（建议 mint）；层级用填充 vs 描边而不是换色；抽一个共享 `AppPrimaryButton`/`AppSecondaryButton`。 |
| U12 | 中 | `ContentView.swift:14-28`, `326-340`；`AppModel.swift:20,44-49`；`RootView.swift:14-16` | 空闲时下载页 ~70% 是空渐变；底部状态行和卡片内提示重复；队列只有一个「队列 N」数字，**没有列表、没有取消**（并发评审 F7 也提到 no cancel UI）；下载中切到首页/设置页签，底栏没有任何角标。 | 下载页补「队列 / 最近完成」区块 + 取消；空闲态放 3 步使用提示；`下载` 页签加 `.badge`；空闲时隐藏状态行。 |
| U13 | 中 | `AlbumDetailView.swift:142-197`；`ContentView.swift:130-177`；`CategoryView.swift:385-408` | 固定 HStack 头部（140pt 封面 + 文字列）在 AX 大字号下标题 4 行截断、`lineLimit(1)` 的信息行截断；筛选空态的「清除筛选 + 继续加载」两个 `.controlSize(.large)` 按钮在 AX 字号下横向溢出。 | `dynamicTypeSize.isAccessibilitySize` 时改 VStack / `ViewThatFits`；两个按钮改纵向或 `ViewThatFits`。 |
| U14 | 中低 | `FilesView.swift:63-72`、`HistoryView.swift:71-97` | `.insetGrouped` List 自带不透明分组背景，`.background(AppBackground())` 只对空态可见；深色下这两页是纯黑，其它页是蓝黑渐变。 | `.scrollContentBackground(.hidden)`；或者接受原生分组背景并删掉这两页的 AppBackground。 |
| U15 | 中低 | `FilesView.swift:113-152`（PDF 只在 148-152 用 `onTapGesture`，ZIP 行完全不可点），`140-145`（分享图标无 label） | 行不是 Button：VoiceOver 没有按钮语义、没有高亮；ZIP 行点按无任何反应；分享图标只有 SF Symbol 名。 | PDF 行改 `Button`（或 NavigationLink）；ZIP 行点按弹 ShareLink/上下文菜单；补无障碍 label。 |
| U16 | 中低 | `HomeView.swift:486-490`、`CategoryView.swift:463-466`/`438-443`、`AlbumDetailView.swift:76-78`、`ReaderView.swift:320-322`、`ContentView.swift:346-348` | 错误直接显示 `error.localizedDescription`，中文界面里会混出 `The request timed out.` 之类的系统英文/技术文案。 | 加 `WnacgError.userMessage`（映射 timeout/offline/429/解析失败），技术细节只在 DEBUG 显示。 |

### 1.2 需要展开的问题

#### U1 · 阅读器在浅色 + iOS 17/18 下“没有标题”

- **代码**：`ReaderView.swift:279` 黑底；`:280-282` `.navigationTitle(title)` + `.inline` + `.seamlessNavigationBar()`；`:294-300` 页码用 `.secondary`；`:311-332` 加载/错误浮层；全文件没有 `toolbarColorScheme` / `preferredColorScheme`。
- **证据**：`docs/screenshots/reader.png`（pre-iOS 26 / 应为 iOS 18）里顶部只有 X、`126P`、刷新，**标题区完全空白**，`126P` 是暗灰。`ReaderView` 对黑画布没有任何深色声明，所以标题/`.secondary` 页码会按系统当前 scheme 取色；浅色模式下即为深色字压黑底（深色模式下标题本应可见，故推断该截图是浅色）。`docs/screenshots/reader-ios26.png` 同屏标题是白色玻璃胶囊。两图对照 + 代码可确认这是 runtime 相关的配色缺陷，不是内容缺失。
- **修法**：在 `AlbumDetailView.swift:135-139` 的 cover 上把阅读器整体钉成深色（也解决状态栏/浮层文字）：

```swift
.fullScreenCover(isPresented: $showReader) {
    NavigationStack {
        ReaderView(aid: album.aid, title: displayTitle)
    }
    .preferredColorScheme(.dark)   // 黑画布 → 深色 chrome / 状态栏 / 浮层
}
```

  如果不想影响 cover 内的系统控件，最低限度在 `ReaderView` 的 `.seamlessNavigationBar()` 后加 `.toolbarColorScheme(.dark, for: .navigationBar)`；同时把页码改成 `.primary` 或放在玻璃胶囊里。
- **验证**：iOS 17.0 / 18.x 模拟器，Appearance=浅色，打开阅读器看标题与加载文案；目前 CI 没有这两个 runtime（review-swarm F4）。

#### U2 · 全局隐藏导航栏背景是 iOS 15–25 的写法，在 iOS 26 上是在跟系统打架

- 这个修饰符解决的问题（滚动后出现模糊条/分割线）在 iOS 26 上已经改成了系统 scroll edge effect；`.hidden` 会把它一并关掉，截图里滚动后的标题区没有任何衬底。iOS 26 的标题颜色会自动跟着背景走（截图里变白），但 **iOS 17/18 不会**，所以在支持的旧系统上标题会黑字压在彩色封面上。
- 建议的收敛写法（`Theme.swift`）：

```swift
extension View {
    @ViewBuilder
    func appNavigationChrome() -> some View {
        if #available(iOS 26.0, *) {
            self                            // 交给系统滚动边缘效果
        } else {
            self.toolbarBackground(.hidden, for: .navigationBar)  // 旧系统保持现行观感…
                // …但首页/分类/详情在滚动时最好再加一层顶部 scrim，否则标题压封面
        }
    }
}
```

  如果坚持“< 26 也完全无栏”的观感，就在每个滚动页加一层仅在滚动后出现的顶部渐隐（`overlay(alignment: .top)` + `ignoresSafeArea(edges: .top)`），成本比恢复原生栏更高。
- **风险**：iOS 26 上恢复默认后，页面顶端可能重新出现系统玻璃/分隔。需要按 `home → 分类 → 详情 → 设置` 顺序对比截图；这是视觉决策，不是行为风险。

#### U3 · 44pt 命中区：v1.22 新控件的实测值

| 控件 | 文件 | a11y 帧（pt） | 目标 |
|---|---|---|---|
| 首页 chips（全部/最新上架/…） | `HomeView.swift:388-398` | 49×**29.3**、73×29.3… | 44 高 |
| 首页「更多」 | `HomeView.swift:419-437` | 37×**33.3** | 44×44 |
| 详情「复制标题」 | `AlbumDetailView.swift:162-173` | **30×30** | 44×44 |
| 详情标签按钮 | `AlbumDetailView.swift:312-319`, `329-339` | 40×**23.3** | 44 高（或改非交互） |
| 详情「收藏」CTA | `AlbumDetailView.swift:288-308` | 370×**40** | 48 |
| 下载页「粘贴」 | `ContentView.swift:64-80` | 47×**29** | 44×44 |
| 下载页「打开原页」 | `ContentView.swift:195-198` | 70×**14.3** | 44 高 |
| 阅读器失败态「重试 / 重新加载」 | `ReaderView.swift:412-421` | 按代码推算约 20 高（caption/caption2，无 padding；未在 log 中实测） | 44 |
| 阅读器右缘进度条 | `ReaderView.swift:343-383` | 宽 24（代码） | 44（且只让拇指可拖） |
| 分类页筛选 pills（对照） | `CategoryView.swift:568-620` | 64.3×**44** | ✅ 已达标 |

> 首页卡片按钮（117.7×207.7）和推荐卡（113×181）是达标的；问题集中在“文字型”控件。分类页的 `.frame(minHeight: 44)` + `.contentShape(Rectangle())`（`CategoryView.swift:590`, `615`）就是现成模板。

#### U4/U5 · 详情页的层级与状态

- 现在的顺序是：header → 3 个 CTA → 标签墙 → 下载状态 → 队列横幅 → 推荐 → 错误/加载。用户失败后不滚动根本看不到原因，加载中也先看到「0 页」（`model.preview?.pages ?? album.pages ?? 0`）。
- 三连 CTA（44/46/40）把首屏下半屏吃满，而标签区（实测 8 行 × 23.3pt）又把「看过这本的人也看了」推到第二屏之后。标签是元数据，不是主内容。
- **建议**：header 下直接放状态块（loading 占位 / error + 重试）；CTA 只保留两个（「开始阅读」主、「下载」次），收藏留在导航栏心并在 header 显示「已收藏」小字；标签默认 2 行 + 「展开全部（N）」；主/次按钮加 press 反馈（`scaleEffect(0.98)` / 系统 `borderless`）。

#### U6 · 分类页筛选需要“固定”

- 现在 `filterRow` 是滚动内容的第一行；`ui-03-category-scrolled.png` 里已经看不到筛选，而下面是无限加载的连续网格。用户滚了 30 部之后想切「翻译」，只能先滚回顶。
- 建议 `.safeAreaInset(edge: .top)` 固定；iOS 26 上给材质/玻璃底，< 26 用 `.ultraThinMaterial`（与首页 chips 一致）。同时把“当前筛选”做成可见状态（例如「翻译 · 屏蔽 AI」+ 重置 ×），不要只在空态提供“清除筛选”。
- **风险**：`safeAreaInset` 与 `.refreshable` / `ScrollViewReader.scrollTo` 的叠加需要实测；分类自身的历史评审（R4）就提醒过这一点。固定栏占用约 56pt，换来始终可达。

#### U7/U10 · 阅读器布局的两处硬编码

- `ReaderPageSlider` 是一个 24pt 宽、全高的 `GeometryReader`，`DragGesture(minimumDistance: 0)`，从右缘开始的任何触摸都会 `seek()`。这不是“点按跳页”，而是误触跳页。建议：轨道只显示；命中区收到滑块的 44×44 拇指；拖动开始后再扩大。
- `placeholderHeight = UIScreen.main.bounds.width * 1.4`：横屏宽 874 → 1223pt 的占位，且与图片实际高度无关。阅读器支持横屏（`project.yml:44-52`），iPad 也在设备族里，所以这是可复现的。建议用 `GeometryReader` 的可用宽度 + 已加载图片的宽高比，占位高度在图片回来后平滑收敛。

#### U8 · 首页的响应式网格

- 分类页的列定义是自适应 + AX 字号特判；首页仍是固定 3 列。iPad 上 3 列会让每张卡 ~320pt，封面糊（360px 缩略图）、标题被截断；AX 字号下 3 列只剩 ~117pt/列，标题 2 行基本放不下。
- 建议把 `CategoryView.swift:210-216` 的列计算抽成共享 helper，首页直接使用；同时把 `HomeView.swift:238` 的 `kCGImageSourceThumbnailMaxPixelSize` 从 360 提到 ~480-600（或按 `displayScale`/列宽计算）。注意 `CoverImageStore` 的 48MB 上限和 120 张计数需要同步评估。
- 如果做 iPad 专项，首页/详情建议加 `frame(maxWidth: 700)` 或分栏；目前详情在 iPad 上 991pt 宽、封面仍是 140pt，视觉比例失衡。

#### U9 · 强调色做小字：让 mint 只做“填充/图标”

- 实测值：`systemMint`（浅色）≈ RGB(0,199,190)，对白底 ≈ 2.1:1；`tertiaryLabel` ≈ 2.1:1。`AlbumDetailView.swift:179` 的「同人誌／漢化」、`HomeView.swift:432` 的「更多」、`ContentView.swift:78` 的「粘贴」都是 11–12pt 的 mint/tertiary 小字。
- 建议在 `Theme.swift` 增加动态 `accentText`（浅色用深 teal，例如 RGB(0,122,118) ≈ 5.2:1；深色继续 systemMint），所有“文字链接/强调文字”用它；mint 保留给按钮填充和 ≥20pt 图标。`.tertiary` 只用于装饰/大字号，11pt 的计数改 `.secondary`。

#### U11/U12 · 下载页：一个主色、一个仪表盘

- 同屏两个 58.3pt 的 `borderedProminent`（mint 解析 / blue 下载）+ 蓝色标签/上传者/链接，视觉上像两个并列主操作。建议统一 mint 品牌色；“解析”做主按钮，“下载”用“选中结果卡”里的主按钮（同一色），层级靠卡片位置和禁用态表达。或者反过来：解析是次要步骤（描边），下载是主操作（mint 填充）。
- 空闲态截图（`ui-walk-tab-download.png`）下半屏全空；卡片下面一行“粘贴作品链接后点解析”与卡片里的“也支持直接输入编号”重复。建议：空闲时展示 3 步提示 + 最近下载（`DownloadFolders.allFiles()` 前 3 个）；有任务时展示队列列表（可取消）+ 当前进度；完成后显示成功卡（文件名 + ShareLink）。这几块数据都已经存在，不需要新网络请求。
- 下载中/排队时给底栏「下载」页签 `.badge`（`AppModel.hasActiveDownload` / `queue.count`）；这是当前唯一“切走就失联”的核心流程（Live Activity 只是补充）。
- 队列取消需要 `AppModel` 增加 `removeQueued(aid:)`（现在只有 `enqueue`/`processNext`），并发评审 F7 也指出“no cancel UI”。

#### U13 · Dynamic Type 布局

- 分类页已经示范了 `dynamicTypeSize.isAccessibilitySize` 的用法；首页、详情、下载页还没用。
- 详情 header、下载预览卡：`isAccessibilitySize` 时改成 VStack（封面在上），信息行放开 `lineLimit`。
- 筛选空态两个大按钮：AX 字号下换 VStack，或用 `ViewThatFits`。
- 固定字号列表：`ContentView.swift:294` 的 `font(.system(size: 10).monospacedDigit())`（ETA/速度）改 `.caption2.monospacedDigit()`；阅读器页码 `ReaderView.swift:433` 的 11pt 用 `@ScaledMetric`/`.caption2`；`PerformanceHUD` 是诊断 UI，可不动。

### 1.3 低优先级细节

| ID | 位置 | 问题 | 建议 |
|---|---|---|---|
| U17 | `HomeView.swift:416-418` | 「6 部」紧挨「更多」，读起来像“该分类共 6 部”；且屏蔽 AI 后数字会变（review-swarm F6 已报）。 | 改「本栏 6 部」或去掉数字；这是新加的文案。 |
| U18 | `HomeView.swift:388-398` vs `CategoryView.swift:568-620`；`HomeView.swift:482-500` vs `FavoritesView.swift:45-56`；`HomeView.swift:402-411` vs `AlbumDetailView.swift:209-224` | 两套 chip（半透明 material vs 实色）、两套空/错态（自绘 vs ContentUnavailableView）、重复的渐变小节标题。 | 抽 `FilterChip`、`SectionHeaderBar`；错误态统一用 `ContentUnavailableView(actions:)`。 |
| U19 | `HomeView.swift:308-317`、`FavoritesView.swift:102-106` | 搜索用 `navigationDestination(isPresented:)` + 条件 + 独立 `searchQuery`；导出用 `sheet(isPresented:)` + `if let`。 | `navigationDestination(item:)`（`SearchTarget: Identifiable`）与 `sheet(item:)`；少一个布尔状态源。 |
| U20 | `AlbumCardView.swift:84-88`、`AlbumDetailView.swift:106-117`/`226-235`、`ReaderView.swift:432-438`、`FilesView.swift:140-145` | VoiceOver 噪音/缺失：卡片里多一个 “Photo” 元素；详情信息行的图标被读成 “Love/person/Plain Text Document”；导航栏心 label 是 “Love” 且不播报已收藏；页码只读 “1”；分享按钮无 label。 | 装饰图 `.accessibilityHidden(true)`；卡片 `.accessibilityElement(children: .combine)`；心 `.accessibilityLabel("收藏/取消收藏")` + `accessibilityValue`；页码「第 N 页」；分享 `分享 \(file.name)`。 |
| U21 | `FilesView.swift:81-88` | 「隐藏 ZIP」是 Menu 里唯一开关，开启后工具栏没有任何状态提示；用户会以为 ZIP 丢了，空态只说“没有匹配的文件”。 | 激活时换 `line.3.horizontal.decrease.circle.fill`（或加一个小圆点），空态文案说明筛选已开启。 |
| U22 | `FilesView.swift:365`；`RootView.swift:55-61` | PDF 预览画布写死近黑（浅色模式下跳）；调试 HUD 固定右上，会压在首页刷新按钮/标题上。 | PDF 画布用 `.secondarySystemBackground`（或按 colorScheme）；HUD 下移或放底部（仅调试，可低优先）。 |

---

## 2. 美化 / 打磨建议 Top 8（按用户可见影响排序）

### R1 · 阅读器沉浸化（Liquid Glass + 可隐藏 chrome）—— 影响：核心功能，每个用户每天
- **改什么**
  - 按 U1 固定深色 chrome；把页码做成右上角小玻璃胶囊「12 / 126」，而不是裸的 `126P` 文本（`ReaderView.swift:294-300`）。
  - 点页面切换导航栏显隐（`@State chromeVisible` + `.toolbar(.hidden, for: .navigationBar)` / `.statusBarHidden`），给漫画一个真正的全屏阅读体验；关闭按钮始终保留一个淡出手势入口。
  - 修 U7（右缘误触）与 U10（占位高度）；失败态的两个按钮改成 44pt 的描边按钮（`ReaderView.swift:407-424`）。
  - iOS 26 上给悬浮页码/工具栏加 `glassEffect(.regular.interactive(), in: .capsule)`，< 26 回落 `.ultraThinMaterial`；如果同时有多个玻璃控件，用 `GlassEffectContainer` 包一层。
- **风险**：点按切换 chrome 会与未来的缩放/翻页手势冲突；先做“点按隐藏/显示”，不做缩放。强制深色会改变状态栏与系统弹层颜色（预期内）。
- **工作量**：**M**

### R2 · 导航栏与滚动边缘：停止全局隐藏，恢复 iOS 26 原生处理 —— 影响：所有页面
- **改什么**：按 U2 收敛 `seamlessNavigationBar()`；iOS 26 用系统默认，iOS 17/18 保留现状或加顶部 scrim。顺带确认恢复默认后，首页/分类的搜索栏与标题的垂直关系仍然正常（`.navigationBarDrawer(.always)` 在 iOS 26 上占 114pt，见附录 A）。
- **风险**：iOS 26 顶部会重新出现系统玻璃边缘；需要和“整页渐变”审美做一次对比决策。不是行为风险。
- **工作量**：**S**

### R3 · 详情页信息层级：两行主操作 + 可折叠标签 + 状态前移 —— 影响：转化路径最长的一屏
- **改什么**（`AlbumDetailView.swift`）
  - 标题从 `.headline` 提到 `.title3.weight(.bold)`（`:149`），行数 3；分类行保留 accentText。
  - 删除整行「收藏」CTA（`:288-308`），导航栏心 + header 里的「已收藏」小字即可；CTA 高度统一 48，并加 press 反馈（U5）。
  - 标签默认 2 行（8 个）+「展开全部（31）」（`:321-346`），把「看过这本的人也看了」提到第二屏。
  - 错误/加载移到 header 下（U4），页数用 optional（`:182-184`）。
  - iPad/regular width 加 `.frame(maxWidth: 700)` 居中（`:100`）。
- **风险**：去掉收藏按钮可能降低收藏发现率——用导航栏心的放大命中区和「已收藏」状态补偿；A/B 判断只能真机/内部体验。
- **工作量**：**M**

### R4 · 分类页：固定筛选栏 + 可见的筛选状态 —— 影响：长列表浏览的主控制
- **改什么**：按 U6 用 `.safeAreaInset(edge: .top)` 固定 `filterRow`，加材质底；新增“已筛选（翻译 · 屏蔽 AI） ×”摘要；把「重置」从空态提升为常态可用。可选：把语言筛选收进导航栏 title menu（title-menus 模式），给无限网格让出 56pt。
- **风险**：`safeAreaInset` + `.refreshable` + `scrollToTop` 三者叠加需要实测；固定栏在小屏上占空间。
- **工作量**：**M**

### R5 · 下载页从“表单”升级为“下载仪表盘” —— 影响：核心页签首屏
- **改什么**（`ContentView.swift` + `AppModel.swift` + `RootView.swift`）
  - 统一一个主色、一个主按钮样式（U11）；空闲态补 3 步提示 + 最近下载（前 3 个文件，来自 `DownloadFolders.allFiles()`），消除 70% 空白（U12）。
  - 队列区：`ForEach(model.queue)` 展示标题/位置 + 取消（需要 `AppModel.removeQueued`）；当前进度卡放在最上面。
  - 完成态：绿色勾 + 文件名 + ShareLink（现在只有底部状态文字和两个链接）。
  - 底栏「下载」`.badge` 显示进行中/排队数；空闲时隐藏重复的状态行。
  - URL 输入框补清除按钮与 `.submitLabel(.go)` + `.onSubmit { parse }`。
- **风险**：队列取消需要模型改动（并发评审 F7 的“no cancel UI”）；最近下载要读文件，注意首屏成本（一次 `allFiles()` 即可，和文件页共用）。
- **工作量**：**M**

### R6 · 统一控制层：一套 chip / 按钮 / 玻璃回落 —— 影响：全 App 的“精致感”
- **改什么**（建议落在 `Theme.swift`）
  - 抽 `FilterChip`（Home / Category / 详情标签共用）和 `AppPrimaryButtonStyle` / `AppSecondaryButtonStyle`（统一 48 高、统一 press 反馈、禁用态）。
  - iOS 26：主按钮用 `.buttonStyle(.glassProminent)` + `.tint(.mint)`，次按钮 `.buttonStyle(.glass)`；chip 用 `.glassEffect(.regular.interactive(), in: .capsule)`；多个相邻玻璃控件用 `GlassEffectContainer`。iOS 17/18：回落 `.ultraThinMaterial` + 1px 描边（就是首页 chip 现在的样子）。
  - 不要给内容卡（封面、卡片容器）加玻璃——Apple 的玻璃是给“浮在内容之上的控件层”的；把 `AppBackground` 和卡片保持扁平。
  - 统一圆角 token：10（缩略图）/12（输入/状态卡）/13（CTA）/16-18（大卡）现在混用。
- **风险**：玻璃叠玻璃、在封面图上对比度不足；只对导航/筛选/悬浮控件用；`reduceTransparency` 下要有材质回落。
- **工作量**：**M**

### R7 · 首页：删掉重复的 chips，做自适应网格 —— 影响：首屏信息密度
- **改什么**：`HomeView.swift:357-386` 的 chips 与栏目头的「更多」是同一批入口（除「全部」外完全重复）。要么删掉 chips 行（把「全部作品」放到工具栏或第一栏的尾部），要么把它改成 ScrollViewReader 的“跳栏”控件；同时用 R/U8 的 adaptive 列，iPad + AX 字号都受益；按 U17 改「N 部」的措辞。
- **风险**：删 chips 会少一个显式的分类入口（但每个栏目头仍有「更多」）；跳栏实现需要 `scrollTo` id，和现有 LazyVStack 兼容。
- **工作量**：**M**（只做“删 chips”是 S；做成跳栏 + 自适应网格是 M）

### R8 · 可访问性与状态一致性 pass —— 影响：AX 字号/VoiceOver 用户 + 整体质感
- **改什么**
  - U3 的 44pt 清单一次过完（用共享 style，不逐处改）。
  - U9 的 `accentText` + `.secondary` 小字。
  - U13 的 AX 布局（详情 header、下载预览卡、筛选空态）。
  - U15/U16/U20/U21：Button 语义、错误文案、VoiceOver 标签、Files 筛选状态。
  - 空/错态统一 `ContentUnavailableView`（含 actions），与收藏/文件/历史一致。
- **风险**：对比度调整会改变品牌观感（mint 小字变深）；AX 布局改动需要逐屏截图回归。
- **工作量**：**M**

---

## 3. 应当保持不动的部分（原生模式已经是对的）

1. **原生 `TabView` + `.tabItem` + `#available(iOS 26) .tabBarMinimizeBehavior(.never)`**（`RootView.swift:9-45`）：保留。历史多次自定义 tab bar 都回退了（见 `docs/category-ui-review.md`），iOS 26 的浮动玻璃底栏就该交给系统；`Group` + availability 的写法也正确。不要在 iPad 上另起自定义栏；以后若要更原生，考虑 `.tabViewStyle(.sidebarAdaptable)`，但那是产品决策，不是 v1.22 的 polish。
2. **每个 tab 自己的 `NavigationStack` + `.navigationTitle` + `.inline` + `NavigationLink`**：保留。没有跨 tab 的深链需求，不需要引入全局 router；`HistoryView(embedded: true)` 复用同一个 stack 也合理。
3. **`.searchable(placement: .navigationBarDrawer(displayMode: .always))` + `.onSubmit(of: .search)`**：保留。这是系统搜索的标准用法，截图里搜索栏的观感也是全 App 最“iOS”的部分。
4. **空态用 `ContentUnavailableView`**（`FavoritesView.swift:45-56`、`FilesView.swift:50-61`、`HistoryView.swift:58-69`）：保留并扩展；不要为了“统一背景”自己重绘空态。
5. **设置页的 `Form` + 原生 Toggle/Picker/Stepper/Footer**：保留。设置页就该是系统 grouped 外观，硬套 AppBackground/自定义卡片只会更差。
6. **统一 `AppBackground` 渐变 + `.ignoresSafeArea()`**（`Theme.swift:22-41`）：保留。它把首页/分类/详情/下载/空态串起来了；问题只在于 List 页没有隐藏自己的背景（U14），不是背景本身。
7. **骨架屏 + reduce-motion**（`AlbumCardView.swift:40-68`、`HomeView.swift:462-480`、`CategoryView.swift:352-360`）：保留。9/12 张占位、无布局跳动、尊重 reduceMotion，这版做得对。
8. **分类页的 adaptive 列 + `dynamicTypeSize` 特判 + 三态 footer**（`CategoryView.swift:210-216`, `483-549`）：保留，并作为其它页的模板。
9. **阅读器的呈现模型**：`fullScreenCover`（`AlbumDetailView.swift:130-139`）、连续 `LazyVStack`、图片 downsample + prefetch + 取消（`ReaderView.swift:98-231`）、自定义进度条概念：保留。只改 chrome/命中区（R1），不要退回 push 或加翻页。
10. **原生 alert / ShareLink / `.refreshable` / `.scrollDismissesKeyboard(.interactively)` / 键盘「完成」toolbar**：保留。键盘问题是 v1.22 的实修，方向对。
11. **触感反馈**（分类筛选 `UISelectionFeedbackGenerator`、收藏/复制 `UIImpactFeedbackGenerator`）：保留；只把它补齐到首页 chips/详情按钮，而不是删掉。
12. **mint 作为 App tint**：保留。要修的是“mint 作为小字文本”的对比度（U9），不是换品牌色。

---

## 4. 检查矩阵（按评审要求逐项）

| 维度 | 结论 | 证据 / 备注 |
|---|---|---|
| SwiftUI 状态所有权 | 基本正确。`@StateObject` 根模型 + `@EnvironmentObject` 共享 store 是 iOS 17 可接受的旧式写法；`@ObservedObject` 只做注入。 | `RootView.swift:4-37`。小问题：同一个 `AppModel` 对 `ContentView` 是显式注入、对 `AlbumDetailView` 是 EnvironmentObject，两种方式混用；不影响运行，但建议统一（低）。搜索/导出两个展示状态用布尔 + 可选值（U19）。 |
| 导航 | 每 tab 独立 `NavigationStack`、inline title、`NavigationLink` 目标视图：正确。阅读器用 fullScreenCover：正确。 | 不建议为这个规模引入 path-based router；搜索改用 `navigationDestination(item:)` 即可。 |
| iOS 26 Liquid Glass | **没有误用**：唯一的 26 API 是正确 gate 的 `tabBarMinimizeBehavior`；没有 `glassEffect`/`GlassEffectContainer`/`.buttonStyle(.glass)`，所以也没有“缺 fallback”的 bug。但自绘 `.ultraThinMaterial` 控件在 26 上会被系统按钮的玻璃质感比下去——这是机会（R6），不是违规。 | `RootView.swift:39-45`；grep 确认全仓无 `glassEffect`。全局隐藏导航栏背景与 iOS 26 的滚动边缘处理方向相反（U2）。 |
| Dynamic Type | 分类页达标；首页固定 3 列、详情/下载固定 HStack、若干固定 10/11pt 字号未适配。 | `CategoryView.swift:210-216` 是模板；U8/U13。 |
| 深色模式 | 背景/卡片/标签/CTA 大体正确；阅读器 chrome 与 PDF 画布是例外。 | `detail-dark-1.22.png` 整体可读；`reader.png` + `ReaderView` 无 toolbar scheme（U1）；`FilesView.swift:365`。 |
| 44pt 命中区 | 卡片/栏目/推荐卡达标；文字型控件普遍不达标（附录 A）。 | 分类 pills 44 证明团队已有标准；把同一写法复制到 U3 清单。 |
| 安全区 | `AppBackground` / 阅读器黑底 / PDF 底部编辑栏 / 键盘处理都正确。 | `Theme.swift:39`、`ReaderView.swift:279`、`FilesView.swift:257-262`。底部浮 tab 覆盖内容属 iOS 26 正常表现，不是 inset 缺失。 |
| 加载 / 空 / 错误态 | 首页骨架、分类骨架 + footer 三态、收藏/文件/历史空态都不错。 | 问题：详情错误/加载埋底（U4）、错误文案透传（U16）、空/错态两套视觉（U18）、下载页空闲占位（U12）。 |
| 视觉一致性 | 两套 chip、两套主按钮、3 种 CTA 高度、5 种圆角、2 种强调色、重复的小节标题渐变条。 | U11/U18、R6。 |
| 信息层级 | 首页 chips 与栏目头重复；详情三 CTA + 标签墙；下载两等权主按钮；文件行没有主操作。 | U5/U11/U12/U17、R3/R5/R7。 |

---

## 5. 发版建议

- **建议阻塞项（唯一）**：**U1 阅读器 chrome**。它在 iOS 17/18 + 浅色模式下直接表现为“标题不见了、页码看不清”，属于用户能一眼看到的缺陷；修法是 `preferredColorScheme(.dark)` 或 `toolbarColorScheme(.dark)` 一行级改动，风险极低。如果这个版本仍宣称“iOS 17 兼容”，建议修完再发。
- **强烈建议同批验证**：U2 在 iOS 17/18 上滚动首页/分类/详情（当前 CI 只跑 iOS 26，review-swarm F4）；至少人工在旧 runtime 截三张滚动图。
- **不阻塞但应排期**：U3/U4/U5/U6（用户天天碰到的细节）、R1–R5。
- **明确不建议阻塞**：U14–U22 都是低风险细节；U18/U19 属于代码结构，不影响发版。

### 需要跑一遍的验证矩阵（只读环境无法执行，交给 Mac/CI）

1. iOS 17.0 + 18.x，浅色：阅读器打开 → 标题/页码/加载文案；首页滚动 → 标题是否压封面；分类滚动 → 同上；设置滚动 → 同上。
2. iOS 26.2：同一组截图，确认恢复 default 导航栏后顶部观感（U2/R2），以及新增的玻璃 chip/CTA 是否和系统 tab bar 协调。
3. AX5 字号：首页/详情/下载/分类筛选空态各一张截图，确认不截断、不横向溢出。
4. iPad（或 iPad 模拟器）：首页网格列数、详情最大宽度、阅读器横屏占位高度。
5. VoiceOver：首页卡片、详情心/复制/标签、阅读器页码/关闭、文件行。

### 无法静态确认、需模拟器/真机的点

- iOS 26 默认（不隐藏）导航栏后的实际玻璃/边缘观感，以及 `.toolbarBackground(.hidden)` 是否确实抑制了 scroll edge effect（截图只能说明没有可见衬底）。
- 分类页 `.safeAreaInset(edge: .top)` 与 `.refreshable` / `scrollToTop` 的叠加行为。
- 阅读器“点按隐藏 chrome”与现有滚动/滑块的冲突。
- iPad 分栏/大屏比例是否真的影响观感（静态只能按尺寸推算）。

---

## 附录 A · 关键控件实测尺寸（来自 `walk3.log` 无障碍帧，单位 pt）

| 页面 | 控件 | 帧 |
|---|---|---|
| 首页 | 全部 / 最新上架 / 同人志 / 單行本 / 雜誌·短篇 | 49×29.3、73×29.3、61×29.3、61×29.3、76.3×29.3 |
| 首页 | 更多（每栏） | 37×33.3 |
| 首页 | 专辑卡 | 117.7×207.7 |
| 首页 | 搜索框 | 370×44 |
| 分类 | 全部 / 翻译 / 日语 / 屏蔽 AI | 64.3×44、50×44、50×44、80×44 |
| 详情 | 复制标题 | 30×30 |
| 详情 | 标签（单枚） | 40×23.3（部分 62×23.3） |
| 详情 | 开始阅读 / 下载 ZIP + PDF / 收藏 | 370×44、371×46、370×40 |
| 详情 | 推荐卡 | 113×181.2 |
| 详情 | 导航栏心（系统 toolbar） | 31.3×36（系统栏，不据此判 44） |
| 下载 | 粘贴 | 47×29 |
| 下载 | 打开原页 | 70×14.3 |
| 下载 | 解析作品 / 下载 ZIP + PDF | 338×58.3（两个） |
| 下载 | 链接输入框 | 314×44 |
| 底栏 | 首页/下载/收藏/文件/设置 | 77×54（达标） |

> 说明：SwiftUI 自绘按钮的无障碍帧基本等于命中区；系统 toolbar/bar button 可能由 UIKit 额外扩大命中，不在上表的“待修”结论里。卡片/底栏/搜索框/输入框是达标的正面样板。

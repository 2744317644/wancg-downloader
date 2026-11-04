# 分类 / 二级列表页（同人志等）UI 与代码评审

> **评审基线**：`main` @ `ca9cb7f`（tag `v1.20.4`，2026-11-04），即用户反馈问题的那版。
> **工作区状态提示**：写作时工作区已被切到 `redesign/category-ui`（`7681a1d`，正在修改中）。
> 第 2–3 节的行号全部指 **v1.20.4**；附录 B 才是对新分支的抽查，两者行号不能混用。
> **评审方式**：Windows 静态审查（本机无 Swift/Xcode 工具链），CI（macOS-15 + Xcode 26.3，
> `.github/workflows/ios.yml`）只做编译 + 联网 smoke test，没有 UI 测试。因此行为类结论
> 来自代码、SwiftUI 布局计算与历史回归，合并前必须按 §7 的 QA 矩阵在模拟器/真机复测。
> **目标读者**：实现者 / Lead。文中的“修复”都按可直接落代码的粒度写。

---

## TL;DR（先给结论）

1. **当前不是分页，是“把一条连续列表每 9 条切一段”**。站点列表页每页约 20 部
   （`README.md:48`；`ios/TestMain.swift:82` 的 smoke test 也按 ≥10 条断言），
   与客户端 9 条一页毫无对应关系。因此底栏的页码 / 分母 / 跳页对话框全部是假语义（P0-2）。
2. **“9 宫格 = 一屏”的前提在主流设备上不成立**：横屏 iPhone 一“页”约 4.5 个屏高，
   iPad 横屏约 2.3 个屏高，iPad 竖屏比视口高 26%；即便 iPhone 15 Pro 竖屏也只是“勉强刚好”
   （P0-1）。3 个固定列在 iPad 上还会得到 400pt+ 的巨型封面。
3. **客户端筛选 + 假分页互相放大**：`fillPage` 一旦遇到“整页都被过滤掉”的站点页就 `break`
   （`CategoryView.swift:352`），然后 pager 因 `visibleAlbums.isEmpty` 被整个隐藏
   （`CategoryView.swift:143`），空状态只剩“清除筛选”按钮；而后续站点页很可能明明有匹配内容
   → 用户被引导去关掉筛选，这是最伤的一个 bug（P0-3）。
4. **刷新/重试先清空列表再发请求**（`CategoryView.swift:45-54`），网络失败即丢失已经加载的
   内容（P0-4）；且分类页没有下拉刷新（`HomeView` 有，`CategoryView` 没有）。
5. **历史 30+ 次 pager 迭代（v1.19.2 → v1.20.4）都在改外观**——悬浮条、收起、Coolapk 自定义
   tab bar、Liquid Glass、居中极简……全部回退。仓库早期其实做过连续网格
   （`4fc6a43`、`BatchGridView.swift`、`CategoryGridView.swift`），后来被删。结论：
   **问题在“假分页”这个模型，不在 pager 的样式**。建议删掉 pager，回到
   continuous adaptive `LazyVGrid` + footer 触底加载 + 顶部 filter chips（§4），
   风险与正确写法见 §5（R1–R14）。

---

## 1. 现状代码地图（v1.20.4）

### 1.1 数据层 `CategoryFeedModel`（`ios/Sources/CategoryView.swift:4-86`）

| 行 | 内容 | 备注 |
|---|---|---|
| 6-11 | `albums / isLoading / error / hasMore / pageCount / resetGeneration` | `pageCount`(10) 与 `resetGeneration`(11) **声明后从未被 View 读取**（`git grep` 确认）→ 死状态 |
| 13-14 | `startURL`、`nextURL` | 站点页游标，本身是对的 |
| 16-18 | `loaded`、`generation`、`loadedAids` | 首次加载门 / 竞态令牌 / aid 去重 |
| 25-28 | `loadIfNeeded()` | `guard !loaded` |
| 30-33 | `reload()` | 先 `loaded=false`，再 `load(reset:true, force:true)` |
| 35-38 | `loadMore()` | `guard loaded, hasMore, !isLoading` |
| 40-54 | `load(reset:)` 入口 | reset 时**先清空** `albums`、`loadedAids`、`pageCount`、`resetGeneration`、`nextURL`、`hasMore`、`error`、`loaded` |
| 55-58 | `guard let url = nextURL` | 结束态 |
| 60-67 | `isLoading = true` → 建 client → `fetchHTML` → `guard current == generation` | 竞态保护 |
| 68-75 | `parseCards` → `loadedAids` 去重 append → `pageCount += 1` → 解析 `nextPageURL` → `hasMore = nextURL != nil` | |
| 78-81 | `catch { error = ... }` | **下一页失败时只设置 error，不改变 hasMore** |
| 82-84 | `if current == generation { isLoading = false }` | |

### 1.2 视图层 `CategoryView`（`ios/Sources/CategoryView.swift:88-378`）

| 行 | 内容 | 备注 |
|---|---|---|
| 91 | `@StateObject model` | init 里 `StateObject(wrappedValue:)`（107-115） |
| 92-94 | 全局 `@AppStorage`：语言筛选、`content.hideAI` | 跨屏共享 |
| 95 | `selectedAlbum` | **只声明、只在 139 行被引用，从未赋值** → 死代码 |
| 96-100 | `currentPage / isLoadingPage / showJump / jumpText / pageSize = 9` | 假分页状态 |
| 102-105 | 固定 3 列 `GridItem(.flexible())` | |
| 117-132 | `ScrollView { LazyVGrid(columns:3) { ForEach(pageItems) } }` | 只渲染 9 个 |
| 134 | `.id(currentPage)` | **整棵 ScrollView 身份重置** |
| 139-141 | `.navigationDestination(item: $selectedAlbum)` | 与 121-127 的 `NavigationLink { AlbumDetailView }` 并存 |
| 142-146 | `.safeAreaInset(edge: .bottom)` 浮动 pager | 叠在原生 TabView 之上 |
| 147-160 | toolbar：筛选菜单 + 刷新 | 筛选按钮无状态指示 |
| 161-169 | `.task { loadFirstPage() }`、`onChange(languageFilter/hideAI) → resetToFirstPage()` | |
| 170-179 | 跳页 alert + `TextField(keyboardType: .numberPad)` | 文案见 178 行 |
| 180-217 | overlay：加载 / 错误 / “本页没有符合筛选的作品” | 只有列表为空时 UI |
| 220-225 | `pageItems` 切片 | |
| 227-229 | `loadedPageCount = ceil(visibleAlbums.count/9)` | **分母 = 已加载条数，不是总页数** |
| 231-233 | `canGoNext = count > (current+1)*9 \|\| model.hasMore` | |
| 235-285 | `floatingBar`：‹ 计数 › | 32×32 按钮（242、269），32 高计数（260） |
| 279-284 | 底栏实心背景 + 透明 `onTapGesture {}` 屏蔽层 | 历史 hack（`05c653d`） |
| 287-311 | `loadFirstPage / resetToFirstPage / reload` | |
| 313-335 | `goToPage`：`hasEnoughForPage` + `withAnimation(0.18)` | |
| 337-340 | `jumpToPage`：只校验 `Int > 0` | |
| 342-354 | `fillPage`：最多 20 次串行 `loadMore`，**`visibleAlbums.count` 不增长就 break**（352） | |
| 356-372 | `selectedLanguage` / `visibleAlbums`（每次 body 重新 filter） | |

### 1.3 相关文件

- 卡片：`ios/Sources/AlbumCardView.swift`（标题 2 行 12-16；元信息 `.font(.system(size: 10))` 18-28；
  封面 `HomeCover` 33-72，`.task(id: album.coverURL)` 58-71，80ms 防抖 64）。
- 首页入口：`ios/Sources/HomeView.swift`——搜索跳转 298-307、分类 chips 347-376、
  “更多” 406-422、卡片网格 432-441；封面缓存 `CoverImageStore` 105-236
  （NSCache 120 张 / 48MB 129-130，磁盘缩略图 189-195，downsample 360px 219-235）。
- 根容器：`ios/Sources/RootView.swift:8-30` 原生 `TabView`；iOS 26 `tabBarMinimizeBehavior(.never)`
  39-45。`ios/Sources/FloatingTabBar.swift:11` **无任何引用（死文件）**。
- 筛选：`ios/Sources/MangaFilter.swift`——`MangaLanguageFilter` 3-17；标题启发式分类 19-40；
  AI 标记表/正则 42-83；toolbar `MangaFilterMenu` 85-100。
- 主题：`ios/Sources/Theme.swift:3-8` `seamlessNavigationBar()`。
- 构建：`ios/project.yml`（iOS 17.0、XcodeGen、`TARGETED_DEVICE_FAMILY: "1,2"`、iPhone 横屏
  44-52、WnacgProxyCheck 显式源文件清单 96-111）；`.github/workflows/ios.yml`
  （macOS-15、Xcode 26.3、`xcodegen generate`、Release 编译 iphoneos、联网 smoke test）。
- 文档：`README.md:48-50` 仍写“分类页每页 20 部（站点原生分页），滑到底自动加载”。

---

## 2. 布局量化：为什么“9 宫格 = 一页”不成立

布局公式（v1.20.4）：`W = (屏宽 - 32 - 20) / 3`，封面高 `4W/3`，
卡片高 `H ≈ 4W/3 + 50`（2 行标题 + 元信息 + 间距），
一页内容高 `≈ 3H + 2×14 + 12 + 18`。
可用视口 ≈ 屏高 − 状态栏 − 导航栏（44）− 原生 tab bar（49+34）− pager（46）。

| 设备 / 方向 | 屏 (pt) | 卡片宽 W | 一页内容高 ≈ | 可用视口 ≈ | 结论 |
|---|---|---|---|---|---|
| iPhone SE3 竖 | 375×667 | 108 | 639 | ~508 | **一页要滚 ~26%** |
| iPhone 13 mini 竖 | 375×812 | 108 | 639 | ~653 | 刚好 |
| iPhone 15 Pro 竖 | 393×852 | 114 | 663 | ~654 | **刚溢出，第 3 行被 pager 遮住一点** |
| iPhone 15 Pro Max 竖 | 430×932 | 126 | 712 | ~734 | 刚好 |
| iPhone 15 Pro 横 | 852×393 | 267 | 1275 | ~283 | **一页 ≈ 4.5 个视口高；单张卡片(~406pt)比视口还高** |
| iPad 10 竖 | 1024×1366 | 324 | 1504 | ~1196 | **比视口高 26%** |
| iPad 10 横 | 1366×1024 | 438 | 1960 | ~854 | **一页 ≈ 2.3 个视口高；封面 438×584pt** |

> 数字是布局计算值（±10%），但结论不依赖精确值：在 **横屏 iPhone、iPad 竖/横、小屏 SE、
> 大字号** 这四类场景下，“9 个 = 一页 = 一屏”都不成立。再叠加 Dynamic Type 时标题行高增长，
> 一页更高。`project.yml:44-52` 明确声明了 iPhone 横屏 + iPad 全方向，所以这些都不是边缘 case。

---

## 3. 问题清单

> 格式：**证据** file:line → **症状**（用户看到什么）→ **修复**（可直接实施）。
> 严重度：P0 = 核心流程不可用/数据丢失；P1 = 高频体验/无障碍硬伤；P2 = 代码质量、边缘、清理。

### P0

#### P0-1 固定 9 宫格在横屏 / iPad / 小屏 / 大字号下根本不是“一页”

- **证据**：`CategoryView.swift:100`（`pageSize = 9`）、`:102-105`（固定 3 列）、
  `:220-225`（按 9 切片）；`ios/project.yml:44-52`（声明 iPhone 横屏 + iPad 全方向）、
  `:58`（`TARGETED_DEVICE_FAMILY: "1,2"`）；`AlbumCardView.swift:9-10`（3:4 封面）。
- **症状**：横屏下一个“页”要滚约 4.5 屏，点一次下一页直接跳掉 4 屏内容；iPad 上 3 列变成
  400pt 宽巨卡、一页仍装不下一屏；小屏 SE 上第 3 行永远被 pager 切掉；大字号时更糟。
  用户感知：“下一页=跳页，一次翻掉一屏多，根本不知道自己在哪”。
- **修复**：删除客户端 9 条分页，改为**连续自适应网格**：
  `[GridItem(.adaptive(minimum: 104, maximum: 154), spacing: 10)]`（iPhone 自动 3 列、
  iPad/横屏 4–6 列），`ScrollView + LazyVGrid` 连续滚动，站点页只作为数据游标。
  若短期非保留分页不可：用 `GeometryReader` 计算“一屏能放几行 × 列”动态定 pageSize，
  并在 iPad/横屏切到自适应列——但这是掩盖问题，仍建议删。

#### P0-2 假分页语义：页码 / 分母 / 跳页全部对不上站点

- **证据**：`CategoryView.swift:227-229`（`loadedPageCount = ceil(visible/9)`，分母是“已加载”）、
  `:257`（`"\(currentPage+1) / \(loadedPageCount)"`）、`:170-179`（跳页 alert：
  “当前第 X 页，已加载 Y 页”，只校验 `Int > 0`）、`:73`（模型 `pageCount` 记录的是站点页数、
  **却从未显示**，`git grep` 确认）、`:337-340`（`jumpToPage`）；
  `README.md:48`（站点页约 20 部）；`ios/TestMain.swift:82`（列表页解析 ≥10 条）。
- **症状**：初始一次请求拿了约 20 部 → 底栏直接显示“1 / 3”，用户以为全站只有 3 页；
  翻到第 3 页后分母随着继续加载变成 4、5……**分母永远追着分子跑**；站点实际页码完全不可见；
  输入 99 会把 20 次串行请求当真（`fillPage`），失败则静默无反馈。
- **修复**：推荐直接删除页码 / 跳页 / 分母（连续滚动不需要）。若产品坚持分页：
  ① 以**站点页**为唯一页码：解析站点分页 HTML 的总页数/当前页（`HomeParser.nextPageURL`
  已能解析 `span.next`，需补总量解析），显示“第 x / y 页（本站）”，跳页直接构造站点 URL；
  ② 绝不再显示“已加载 N 页”这种混合计数；③ 列表底部改显示“已加载 N 部 · 已经到底了”。

#### P0-3 筛选 + 假分页 → 空页死胡同，文案还误导用户关筛选

- **证据**：`CategoryView.swift:342-354`（`fillPage` 循环里 `if visibleAlbums.count == before { break }`，352）、
  `:361-372`（`visibleAlbums` 在客户端过滤）、`:143`（`if !visibleAlbums.isEmpty { floatingBar }` →
  **空时 pager 被隐藏**）、`:180-217`（overlay 仅在 `visibleAlbums.isEmpty` 时出现）、
  `:201-215`（“本页没有符合筛选的作品” + “清除筛选” + 重置 `languageFilter`/`hideAI`）、
  `:164-169`（filter 变更 `resetToFirstPage()`，但不重新请求）、`MangaFilter.swift:19-40`（标题启发式分类）。
- **症状**：在“同人志”里选“翻译”后，若第一屏之后某个站点页恰好全是日语标题，
  `fillPage` 立刻 break，页面变空；pager 消失、没有“继续加载”按钮，只剩
  “本页没有符合筛选的作品 / 清除筛选”。而下一站点页可能就有中文标题——用户被引导去关筛选，
  永远看不到后面的内容。iPad 上同人志整页大多是日文时，这个路径非常容易触发。
- **修复**：① `fillPage` 不能在“单页无新增可见项”时 break：改为
  `while visible.count < target && hasMore && attempts < max && !model.isLoading`，
  用“连续空页计数”上限（如 6）保护，而不是“一页没增长就停”；
  ② 空态永远保留筛选 chips + “继续加载”按钮（有 `hasMore` 时），“清除筛选”作为次要操作；
  ③ 文案区分“筛选后暂无匹配（可继续加载）”，不要说“本页”；
  ④ 根治还是回到连续网格 + footer 自动加载（§4）。

#### P0-4 刷新/重试先清空列表 → 失败即数据丢失；且没有下拉刷新

- **证据**：`CategoryView.swift:45-54`（`reset` 分支在 `fetchHTML` 之前就
  `albums = []` / `loadedAids.removeAll()`）、`:30-33`（`reload()` 复用同一路径）、
  `:305-311`（toolbar 刷新）、`:184-199`（错误态只在空列表时可见）、
  `:161-163`（只有 `.task`，**没有 `.refreshable`**）；对照 `HomeView.swift:318-320` 有下拉刷新。
- **症状**：已经有 10 页内容后点刷新，列表先变空、中间转圈；网络一失败（或 429/代理 310）
  就只剩错误页，之前加载的全没了；同时分类页无法下拉刷新，与首页手势不一致。
- **修复**：`refresh()` 改成“先取第一页到临时变量，成功后再替换”：
  ```swift
  func refresh() async {
      let html = try await fetchPage(startURL)          // 失败直接 throw，不动旧数据
      let parsed = HomeParser.parseCards(html)
      albums = dedupe(parsed); loadedAids = Set(albums.map(\.aid))
      nextURL = HomeParser.nextPageURL(html, current: startURL); hasMore = nextURL != nil
  }
  ```
  失败时保留旧列表 + 顶部/底部错误条（可重试）；筛选变更才允许清空并回顶。
  同时给 ScrollView 加 `.refreshable { await model.refresh() }`。

### P1

#### P1-1 不能左右滑动翻页，只能点 32pt 小箭头；浏览成本极高

- **证据**：`CategoryView.swift:117-132`（只有 ScrollView，无 `DragGesture` / `TabView(.page)`）、
  `:235-285`（唯一翻页入口是 chevron 按钮）、`:313-335`（`goToPage`）。
- **症状**：同人志有几百页，用户必须精确点底栏小箭头几十/上百次；没有滑动翻页
  （与漫画阅读器、相册的既有心智不符）；横屏下每点一次跳掉 4 屏更糟。
- **修复**：推荐删掉分页（连续滚动后不再需要翻页）。若短保留：加水平 `DragGesture`
  （阈值 + 不与 NavigationStack 左边缘返回手势冲突），或在页面级用 `.tabViewStyle(.page)`
  但会引入左右滑与返回手势冲突，不优先。

#### P1-2 pager 触摸目标 < 44pt，且完全没有无障碍标签

- **证据**：`CategoryView.swift:240-243`、`:267-270`（`frame(width:32,height:32)` +
  `contentShape(Rectangle())` → 命中区 32×32）、`:260`（计数按钮 `minHeight: 32`）、
  `:237-273`（三个 Button 均无 `accessibilityLabel`/`accessibilityHint`/`accessibilityValue`）。
- **症状**：HIG 要求可点区域 ≥44×44pt，这里只有 32×32/32 高，拇指容易点空；
  VoiceOver 把 ‹ › 读成无意义符号（甚至“未命名按钮”），计数按钮“1 / 3”不说明可跳页。
- **修复**：如果保留 pager：按钮命中区改 44×44（可保持视觉 32，用
  `.frame(width:44,height:44).contentShape(Rectangle())`）；加
  `.accessibilityLabel("上一页")`、`.accessibilityLabel("下一页")`、
  `.accessibilityLabel("第 \(currentPage+1) 页，共 \(loadedPageCount) 页")`
  + `.accessibilityHint("轻点跳转")`；删除分页则整段消失。

#### P1-3 双层底栏 + 触控屏蔽 hack + 不透明色条

- **证据**：`CategoryView.swift:142-146`（`safeAreaInset(edge: .bottom)` 浮动条）、
  `:279`（`.background(Color(uiColor: .systemGroupedBackground))` 全宽实心条）、
  `:280-284`（`Color.clear.contentShape(Rectangle()).onTapGesture {}` 透明屏蔽层，
  来自 `05c653d`“shield touches from covers”）、`RootView.swift:8-30`（原生 TabView 常驻）、
  `RootView.swift:39-45`（iOS 26 `tabBarMinimizeBehavior(.never)`，tab bar 永不收起）。
- **症状**：iPhone 底部同时出现一条 46pt 不透明空白条（里面只有小 pager）和原生
  Liquid Glass tab bar；视觉上像两条底栏。实心条把内容挡出视口、挤掉 ~46pt；
  透明屏蔽层的 `onTapGesture` 会把落在该条内的滑动手势吞掉（拇指区无法起滑）。
  iOS 26 下玻璃 tab bar 上方贴一条实色条尤其突兀；iPadOS 18 tab bar 移到顶部时，
  底部又只剩这条孤零零的 pager。
- **修复**：直接删除整个 `safeAreaInset` 浮动条与屏蔽层；列表内容按系统默认滚到 native
  tab bar 下方，让 Liquid Glass 自己处理透视。若需要“回到顶部”，用
  `overlay(alignment: .bottomTrailing)` 放置 44×44 按钮（在内容安全区内，天然位于 tab bar
  之上），不要再造底栏。删除
  `Color.clear…onTapGesture {}` 这类历史 hack。

#### P1-4 筛选状态完全不可见；菜单在搜索页无效；清空筛选会顺手改全局设置

- **证据**：`CategoryView.swift:92-94`（两个 `@AppStorage` 全局键）、`:147-150`
  （toolbar 永远显示 `MangaFilterMenu`）、`:356-359`（`selectedLanguage` 在
  `appliesLanguageFilter == false` 时固定返回 `.all`，但菜单仍可点）、
  `:208-211`（“清除筛选”同时重置 `languageFilter` 和 `hideAI`）、
  `MangaFilter.swift:85-100`（图标固定为 `line.3.horizontal.decrease.circle`，无选中态）、
  `HomeView.swift:301-306`（搜索页 `appliesLanguageFilter: false`）、
  `AlbumDetailView.swift:303-307`（标签搜索却用默认 `true`）、
  `SettingsView.swift:88-94`（`hideAI` 是设置项）。
- **症状**：用户看不出当前启用了“翻译”或“屏蔽 AI”（图标没变化、没有 chip、列表里只是
  少了东西）；在搜索结果页点筛选菜单，界面毫无变化但全局值被改了，回到首页/分类页才突然
  被过滤；空态点“清除筛选”会把用户在设置里特意开的“屏蔽 AI”一起关掉，且无确认。
  同一条搜索 URL 在首页入口不套语言过滤、在标签入口套语言过滤，语义不一致。
- **修复**：把筛选做成**顶部可见 chips**（全部/翻译/日语/屏蔽 AI，选中态 = mint 填充 +
  checkmark + `.isSelected`），搜索页（`appliesLanguageFilter:false`）隐藏语言 chips、
  只留“屏蔽 AI”并显示 scope；`清除筛选` 只清当前屏显式激活的筛选，若包含全局设置需
  文案说明（或改成局部覆盖，不改 `@AppStorage`）；标签搜索与首页搜索统一 `appliesLanguageFilter`
  语义。

#### P1-5 过滤在 fetch 之后做 + 启发式分类 → 假阳性/假阴性，且只过滤已加载页

- **证据**：`CategoryView.swift:361-372`（`visibleAlbums` 对 `model.albums` 做客户端过滤）、
  `MangaFilter.swift:19-40`（标题含“中国翻訳/漢化/中文…”才算翻译，其余一律 `.japanese`；
  `isAI` 只看标题）、`:164-169`（filter 变更不重新请求，只 `resetToFirstPage`）。
- **症状**：英文/繁体标题的翻译作品被归到“日语”；没有中文标记的日文作品在“翻译”下消失；
  “翻译”筛选实际只对已加载的那几页生效，用户以为筛的是全站；AI 过滤只看标题，
  标签/作者里的 AI 作品漏过。同人志多为日文原文 + 中文译名混排，误判率尤其高。
- **修复**：优先做**服务端筛选**（搜索页已有 `f=` 等参数，`HomeParser.searchURL` 188-200；
  可研究站点分类/排序参数）；短期保留启发式则：改名为“标题标记”类筛选并在 UI 上注明
  “按标题粗略判断”，同时配合“自动继续加载直到匹配/到底”（与 P0-3 修复一致），
  并在空态提示“可能因标题判断误差漏掉内容，可切换全部”。

#### P1-6 下一页失败完全静默；跳页无效也没有反馈

- **证据**：`CategoryView.swift:78-81`（`loadMore` 失败只写 `model.error`）、
  `:180-217`（overlay 只在 `visibleAlbums.isEmpty` 时渲染 error）、
  `:337-340`（`jumpToPage` 无范围校验/无结果反馈）、`:313-335`（`goToPage` 加载失败时
  `if visibleAlbums.count > page*pageSize` 不成立 → 静默不动）。
- **症状**：浏览到第 5 页时网络断了，点“下一页”只看到 pager 转一下然后回到原页码，
  没有任何错误提示；用户不知道是加载慢、没网、还是 App 坏了；跳页输入超范围也无提示。
- **修复**：只要 `model.error != nil`（无论列表是否为空）就在 grid 底部显示
  “加载失败 · 重试”（≥44pt 可点），并在顶部加短暂错误条；跳页前校验范围并禁用按钮，
  失败/超范围给 `alert`/inline 文案；`loadMore` 失败保留 `hasMore` 但 UI 提供显式重试。

#### P1-7 加载/空/错误三态混淆：没有骨架、没有“到底了”、没有下拉刷新

- **证据**：`CategoryView.swift:182-183`（首次加载是全屏 `ProgressView("正在加载…")`）、
  `:184-199`（错误态）、`:201-215`（筛选空态）、`:143`（空时隐藏 pager）、
  无 footer/end 状态（对比历史 `4fc6a43` 有“继续下滑加载更多/已经到底了”）；无 `.refreshable`。
- **症状**：首屏白屏转圈而不是骨架（HIG 建议先占位再替换）；到最后一页时 pager 变成
  `N / N` 然后“下一页”变灰，没有任何“已经到底了”的确认（NN/g 完整性错觉）；
  加载失败与服务器真空结果、筛选无结果共用一套 UI，用户不知道该怎么办。
- **修复**：三态分流：
  ① 首次加载 → 9–12 个 `SkeletonAlbumCard`（`isLoading && albums.isEmpty` 时，
  超过 ~200ms 再显示，`allowsHitTesting(false)`、`accessibilityHidden(true)`、respect Reduce Motion）；
  ② 服务端真空 → “这个分类暂时没有作品” + 下拉刷新；
  ③ 筛选无结果 → 保留 chips + “继续加载”/“清除筛选”；
  ④ 列表非空时底部 footer：`加载中 / 加载失败·重试 / 已经到底啦·共 N 部` 三选一。
  加 `.refreshable`；`ContentUnavailableView` 项目里已有先例（`FavoritesView.swift:46`）。

#### P1-8 `.id(currentPage)` + `withAnimation` → 整页闪/封面重载/掉帧

- **证据**：`CategoryView.swift:134`（`.id(currentPage)`）、`:320-322`、`:328-331`
  （`withAnimation(.easeInOut(duration: 0.18)) { currentPage = ... }`）、
  `AlbumCardView.swift:35`（`@State image`）、`:58-71`（`.task(id: album.coverURL)` 重载封面）。
- **症状**：翻页时整棵 ScrollView 身份被替换（不是平移/淡入的“翻页”动画），
  在 `withAnimation` 里表现为整页交叉淡入/闪白；9 张卡片的 `@State image` 全部销毁重建，
  每张重走 `.task`（即使命中内存缓存，也先渲染一帧 `photo` 占位）→ 肉眼可见闪烁；
  滚动位置被强制归零；120Hz 设备上同样能感到卡顿（120Hz 监控见 `HighRefreshRateController`）。
- **修复**：删除 `.id(currentPage)`（分页本身也删）。任何“筛选/刷新”都不要改 ScrollView
  身份；需要回顶用 `ScrollViewReader.scrollTo(topAnchor)`；需要动效时用
  `.transition(.opacity)` 只作用在内容层且 ≤120ms；respect `accessibilityReduceMotion`。

#### P1-9 Dynamic Type / 布局：固定 3 列 + 固定 10pt/32pt，大字号必截断

- **证据**：`CategoryView.swift:102-105`（固定 3 列）、`:238-243`、`:266-270`（图标
  `.system(size:14)` + 固定 32）、`:258-260`（`.footnote` 但 `minWidth:64/minHeight:32`）、
  `AlbumCardView.swift:12-16`（`.caption2` + `lineLimit(2, reservesSpace: true)` 会随字号增长）、
  `:26`（元信息 `.font(.system(size: 10))` 固定不缩放）、`:18-28`（`pages`/`date` 缺失时行高为 0，
  同行卡片高度不一致）。
- **症状**：AX 字号下 3 列变窄 + 标题 2 行放不下 → 大面积截断；pager 文字（尤其
  “第 12 / 12 页”类文案）会挤压/溢出；元信息不随字号放大，与系统可读性设置不符。
- **修复**：`AlbumCardView` 元信息改语义字体（`.caption2`，新分支已改）；列宽用
  `@ScaledMetric`，`dynamicTypeSize.isAccessibilitySize` 时降为 2 列；pager 一旦保留就要
  取消固定宽高、允许换行；元信息行给固定最小高度（如 `.frame(height: 14, alignment: .leading)`
  或 `.lineLimit(1, reservesSpace: true)`）保证行高一致。

#### P1-10 卡片/翻页的无障碍语义缺失

- **证据**：`CategoryView.swift:117-127`（每张卡是 `NavigationLink { AlbumCardView }`，
  内部 3 个 `Text` + 封面图，无 `.accessibilityElement(children:.combine)` /
  `.accessibilityLabel`）、`AlbumCardView.swift:48-50`（占位 `photo` 图标会被读）、
  `:20`（`Text("\(pages)P")` 会被读成英文“P”）、`:22-24`（日期 `2026-11-04` 直读）、
  `CategoryView.swift:170-179`（页码输入框只有 placeholder）、无翻页/筛选变化的
  accessibility announcement；`:320`（withAnimation 未检查 Reduce Motion）。
- **症状**：VoiceOver 逐字读卡片（标题、页数、日期拆成多个元素），封面占位也参与朗读；
  “123P”读作“123 P”；翻页/筛选后没有任何播报，读屏用户不知道列表变了。
- **修复**：卡片 `.accessibilityElement(children: .combine)` +
  `.accessibilityLabel("\(title)，\(pages) 页，\(date)")`；封面
  `.accessibilityHidden(true)`；文案 `"\(pages)P"` → `"\(pages) 页"`（日期可格式化）；
  icon-only 按钮补 label/hint；翻页/筛选后
  `AccessibilityNotification.Announcement("第 N 页，共 M 页")` 或“已加载 N 部”；
  `withAnimation` 前判断 `reduceMotion`。

### P2

#### P2-1 导航：死代码 + 重复 destination + 嵌套 CategoryView 重复注册

- **证据**：`CategoryView.swift:95`（`selectedAlbum` 从未赋值）、`:139-141`
  （`.navigationDestination(item:)`）、`:121-127`（同时用 `NavigationLink { AlbumDetailView }`）、
  `HomeView.swift:298-307`（搜索用 `navigationDestination(isPresented:)`）、
  `AlbumDetailView.swift:303-307`（从标签再推一个 `CategoryView`，且用默认
  `appliesLanguageFilter: true`）。
- **症状**：目前用户可见行为“碰巧”正常（`selectedAlbum` 恒 nil），但这是死代码；
  从分类→详情→标签→分类的栈里会存在多个 `.navigationDestination(item: HomeAlbum)` 注册，
  SwiftUI 会打“A navigationDestination for HomeAlbum was declared earlier on the stack”警告，
  且只有最靠近栈根的那个生效；未来改成 `NavigationLink(value:)` 时极易推错目的地/推两次。
- **修复**：删掉 `selectedAlbum` 与 `.navigationDestination(item:)`；在 `HomeView` 的
  `NavigationStack` 根部统一注册**唯一**一个 `.navigationDestination(for: HomeAlbum.self)`，
  所有卡片改用 `NavigationLink(value: album)`；不要在 pushed view（`CategoryView`）里注册
  destination；标签搜索与首页搜索统一 `appliesLanguageFilter` 语义（搜索=全部语言）。

#### P2-2 无限滚动 / 模型门控的正确性细节

- **证据**：`CategoryView.swift:35-38`（`loadMore` 依赖 `loaded`）、`:40-85`（代际竞态）、
  `:55-58`+`:74-75`（`nextPageURL` 直接相信站点 next 链接，不校验 `next != current`）、
  `:63-65`（`guard let client else { return }` 在 `isLoading = true` 之后 → 一旦 client 为 nil
  会永远卡 loading；目前 `try WnacgClient()` 保证非 nil，属潜在雷）、
  `:231-233`（`canGoNext` 用 `model.hasMore`，出错/空页时“下一页”永远可点）、
  `:342-354`（`fillPage` 单次用户操作最多 20 次串行请求、无取消）、
  `:305-311`（`reload` 的 Task 在 pop 后不会取消）。
- **症状**：`fillPage` 可能在一次点击里连续发 20 个请求（慢网络下转圈几十秒，且易触发站点
  429/代理 310）；页面已弹栈后请求还在跑；站点若返回自引用 next 链接，`hasMore` 永远
  true、反复请求同一页（`loadedAids` 只防重复卡片，不防重复请求）。
- **修复**：`isLoading` 用 `defer` 收尾（含 catch/取消分支）；`nextPageURL` 校验
  `next != current`、并对“连续无新增”设上限；把 `fillPage` 改为 footer 触发的
  `loadMore`（每次 1 页，UI 可取消）；`cancel` 当前 page-fill Task 在
  `.onDisappear`/筛选变更时；`canGoNext` 不再用 `hasMore` 兜底，改成“已有下一段内容或
  可请求”并显示 loading 状态。

#### P2-3 封面重载 / 缓存：翻页重新跑 `.task`，缓存无清理

- **证据**：`AlbumCardView.swift:33-72`（`@State image` + `.task(id:)`，80ms 防抖，
  缓存命中同步赋值，未命中走 `CoverImageStore.shared.image`）、
  `HomeView.swift:110`（NSCache）、`:129-130`（`countLimit = 120` / `totalCostLimit = 48MB`）、
  `:189-195`（磁盘写缩略图，**无任何清理逻辑**）、`:219-235`（360px 下采样）、
  `HomeView.swift:116-119`（并发默认 3，可在设置调 1–6）。
- **症状**：`.id(currentPage)` 每次翻页销毁 9 个卡片 → 图片状态清零、重新走 `.task`，
  首帧显示 `photo` 占位再跳图；连续浏览几十页后 NSCache 频繁淘汰，回看已看过的页要重新
  读盘/解码；`CoverThumbnails` 目录只增不减（长期占磁盘）。
- **修复**：删除 `.id` 后卡片状态自然保留；封面处理保持“先占位骨架 → 命中缓存立即替换”；
  在启动/进入分类时对 `CoverThumbnails` 做一次 LRU/7 天清理；NSCache 用 cost 而非
  count 作为主限制（已在做）并考虑把 `countLimit` 提到 ~200 或按屏数动态；下一屏封面
  可在当前屏出现后预取（`CoverImageStore.shared.image(for:)` 已是 async，可提前 Task）。

#### P2-4 性能：`visibleAlbums` 每帧/每次 body 重算 5 次，且 AI 过滤代价高

- **证据**：`CategoryView.swift:220-225`（`pageItems` → visibleAlbums）、`:227-229`
  （`loadedPageCount` → visibleAlbums）、`:231-233`（`canGoNext` → visibleAlbums）、
  `:143`（safeAreaInset 条件 → visibleAlbums）、`:181`（overlay 条件 → visibleAlbums）
  → **一次 body 5 次 O(n) 过滤**；`hideAI` 为真时每次过滤对每部作品跑
  `AIContentFilter.matches`（`MangaFilter.swift:42-83`：90+ 个 `contains` + 一次
  `NSRegularExpression`）；`:319-331` 的 `withAnimation` 会放大重算；
  `model.albums` 无上限（历史 `7eff171` 做过 bound、`1e9895b` 又因滚动跳变移除）。
- **症状**：加载几十页后（n 上百），翻页、弹 alert、筛选都会触发 5 次全量过滤 + 正则；
  主线程掉帧，尤其在 120Hz 设备上更明显。
- **修复**：把“过滤后的列表”缓存为 `@Published`/`@State` 派生值，在
  `albums/filter` 变化时**只算一次**（或让 `CategoryFeedModel` 暴露
  `visibleAlbums(filter:)`）；body 里只读；`AIContentFilter` 预编译结果；
  连续网格下 LazyVGrid 本身是懒加载，但 `ForEach` 的数组不要每 body 重新 filter。
  用现有 FPS HUD（`SettingsView.swift:96-102`）验收。

#### P2-5 首页入口 chips / “更多”的触摸目标与语义

- **证据**：`HomeView.swift:347-376`（分类入口 chips 实为 `NavigationLink`）、`:378-388`
  （`.caption` + 12/7 padding → 高约 30pt，<44）、`:406-422`（“更多”文字 + 9pt chevron，
  行高不足 44）、`:360-373`（只为有 `moreURL` 的 section 生成 chip）。
- **症状**：入口小、`更多` 与卡片之间间距小，容易点错；chips 长得像筛选项但实际是导航，
  用户可能误以为点了筛选；某些栏目因为没解析到 moreURL 就不出现在 chips 里，入口不一致。
- **修复**：chips 高度 44、选中/导航视觉与筛选 chip 区分（如带 › 或分组标题）；
  “更多”整行 `.contentShape` + 44pt；对无 moreURL 的 section 也提供入口（构造默认分类 URL）。

#### P2-6 死代码与文档漂移

- **证据**：`ios/Sources/FloatingTabBar.swift:11` 全仓库无引用（`git grep FloatingTabBar`
  只有声明）；`CategoryView.swift:10-11` 的 `pageCount`/`resetGeneration` 无读取；
  `CategoryView.swift:95` `selectedAlbum` 死代码；`README.md:48-50` 仍描述“每页 20 部、
  滑到底自动加载、可一直往下翻”；`README.md:72-73` 描述五个 tab 为
  “首页/下载/收藏/历史/文件”，实际 `RootView.swift:9-29` 是“首页/下载/收藏/文件/设置”。
- **症状**：代码维护者被历史文件/死状态误导；README 与真实行为不符，用户按文档预期使用会困惑。
- **修复**：删除 `FloatingTabBar.swift`（或明确接线，但当前已回原生 tab bar）；
  删除未用的 Published/State；重写 README 分类/搜索/筛选段落（按新设计描述连续滚动、
  chips、无分页）；更新 tab 列表。

#### P2-7 导航栏/平台细节：`seamlessNavigationBar()` 与 iPad

- **证据**：`Theme.swift:3-8`（隐藏导航栏背景）、`CategoryView.swift:136-138`（使用它 +
  `.inline` 标题）、`project.yml:48-52`（iPad 四方向）、iOS 26 `tabBarMinimizeBehavior`
  `RootView.swift:40-44`。
- **症状**：滚动时封面卡片从透明导航栏下穿过，文字/封面叠在一起，可读性差（浅色模式尤其）；
  iPadOS 18+ tab bar 在顶部/浮动时，本页“底部 pager”的语境完全不对；iPad 上无
  readable width 限制，3 列巨卡。
- **修复**：要么恢复导航栏材质/模糊，要么 iOS 26 用
  `.scrollEdgeEffectStyle(.soft, for: .top)`（需 `#available(iOS 26.0, *)` 守卫，
  参照 `RootView.swift:40-44` 的写法）；网格用 adaptive 列（P0-1），iPad 自然 5–6 列；
  内容宽度可用 `.frame(maxWidth: 1000)` 居中（可选）。

---

## 4. 推荐方向（替换 v1.20.4 的分页模型）

一句话：**删分页、删底栏、删 `.id`；连续自适应网格 + 内容内 footer 触底加载 +
顶部可见 filter chips + 骨架 + 下拉刷新 + 首次加载/回顶辅助**。

```
ScrollViewReader { proxy in
  ScrollView {
    LazyVStack(spacing: 0) {
      // 可选：内容内标题/计数（不用 toolbar，也不用第二根固定 bar）
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 154), spacing: 10)],
                spacing: 14) {
        ForEach(albums) { album in
          NavigationLink(value: album) { AlbumCardView(album: album) }
            .buttonStyle(AlbumCardButtonStyle())
        }
      }
      footer   // Loading / 加载失败·重试 / 已经到底啦 · 共 N 部
    }
  }
  .safeAreaInset(edge: .top, spacing: 0) { filterChips }   // 唯一一条自绘 bar，且是 chips 不是底栏
  .refreshable { await model.refresh() }
  .scrollIndicators(.hidden)
  .overlay(alignment: .bottomTrailing) { backToTopButton } // 不新增底栏
}
```

必须保持/改造的模型部分：

- 保留站点页游标 `nextURL` + `hasMore` + `loadedAids` + `generation`（数据源是对的）。
- 新增显式状态机（`initialLoading / loadingMore / loaded / empty / error / end`），
  避免“空列表 + isLoading + error + hasMore”互相打架。
- `refresh()` 成功后替换数据，失败不动旧数据（P0-4）。
- 过滤变更：清空数据 → 回顶 → 重新拉第一页 → 有界地继续拉直到有匹配或到底（P0-3）；
  客户端启发式过滤继续存在时，UI 要说明“按标题粗略筛选”。
- 删除：`currentPage / pageSize / pageItems / loadedPageCount / canGoNext / floatingBar /
  jump alert / .id(currentPage) / safeAreaInset(bottom) / 触控屏蔽 hack`。
- 不要用 `.tabViewStyle(.page)` 做分页（与 NavigationStack 返回手势/筛选状态冲突，且
  “每页 9 个”信息密度问题依旧）。

---

## 5. 替换方向的风险清单（Swift / SwiftUI 正确性）

> 这些是“连续网格 + onAppear 加载 + chips + 骨架 + 下拉刷新 + 回顶”这一方向最容易踩的坑。
> 每条给：触发条件 → 为什么错 → 正确写法 → 验收。R1/R2/R5 是最高风险。

### R1 `onAppear` 触发 `loadMore`：重复请求与“不再触发”停滞

- **触发**：最后一张卡片 `.onAppear` 里 `Task { await model.loadMore() }`；
  列表追加后最后一张变化；用户上滑回到最后一张；筛选把新页整页过滤掉。
- **为什么错**：
  - 重复：一次布局里多个 cell 可能同时 appear（iPad/横屏一屏 12–20 张），
    或追加后旧最后一张重新 appear → 同一时刻多次调用（`isLoading` 门挡一部分，
    但 `onAppear` 的 Task 是异步的，存在竞态窗口）。
  - 停滞：若 `loadMore` 拉到的站点页在筛选后**没有新增可见项**，最后一张卡片身份不变，
    `onAppear` 不会再次触发 → 列表停在原地，`hasMore == true` 却永远不再加载。
  - 重入：筛选/刷新重置数据时，旧 cell 的 Task 还在跑。
- **正确写法**：
  - 门控放在 Model 里，用“请求令牌 + 上次请求时的数据版本”，而不是只看 `isLoading`：
    ```swift
    @Published private(set) var requestToken = 0
    private var lastRequestedAlbumsCount = -1
    func loadMoreIfNeeded() async {
        guard hasMore, !isLoading, albums.count != lastRequestedAlbumsCount else { return }
        lastRequestedAlbumsCount = albums.count
        await load(reset: false)
        // 若加载成功但可见集合没变化（被筛掉/重复 aid），允许下一次立即再拉：
        // 用连续空页计数上限 6 保护，并给 footer 一个“继续加载”按钮兜底。
    }
    ```
    刷新/筛选变更/加载结束后把 `lastRequestedAlbumsCount = -1` 重置（历史
    `BatchGridView` 的 `lastRequestedCount` 就是为此加的，`af54fbc^:ios/Sources/BatchGridView.swift`）。
  - 触发点用**内容内 footer**（`onAppear` 或 `.task` 于 footer 哨兵视图）而不是“最后一张卡”：
    footer 在每次追加后都会重新出现，天然可重复触发；footer 也是错误重试/到底状态的载体。
  - 另加“短内容自适应”：加载完成后若 `contentHeight < viewportHeight`，再触发一次
    （旧实现 `checkContentNeedsMore` 的做法），否则第一页不满屏时不会继续加载。
- **验收**：快速上下滑到底不重复发请求（可在 `loadMore` 里打日志/断点）；筛选“翻译”后
  连续 6 个站点页无匹配时显示“继续加载”，不卡死；旋转屏幕后自动补足。

### R2 任务取消与 `isLoading` 卡死

- **触发**：`.task`/`onAppear` 里的 Task 在视图 pop、`.task` 被取消、`URLSession` 被取消时；
  尤其**取消分支提前 `return` 而没有复位 loading**。
- **为什么错**：典型写法
  ```swift
  do { ... } catch {
      if err is CancellationError { return }   // ← 这里 return 跳过后面的 isLoading = false
      error = ...
  }
  if token == generation { isLoading = false }
  ```
  会让 `isLoading` 永远 true，`loadMore()` 的 `guard !isLoading` 永远失败 → 无限加载死掉、
  UI 停在 footer spinner。`URLSession.data(for:)` 取消时通常抛 `URLError(.cancelled)`，
  但 429 退避里的 `Task.sleep` 取消会抛 `CancellationError`（`WnacgClient.swift:68-73`），
  这条路径是真实可达的。
- **正确写法**：`defer { if token == generation { isLoading = false } }`；取消分支只
  `return`，不写 error；把“取消”与“失败”分开处理；给 `loadMore` 增加
  `Task.isCancelled` 早退。
- **验收**：加载中立即返回上一页、快速切换筛选、后台/回前台各 5 次，再次进入分类页仍能加载。

### R3 `@StateObject` + 变化的 `startURL` / 筛选 identity

- **触发**：把筛选参数拼进 `startURL` 后复用同一个 `CategoryView` 实例（同一导航位置、
  同一 View 身份）；或 `navigationDestination(isPresented:)` 闭包里换查询词。
- **为什么错**：`_model = StateObject(wrappedValue: CategoryFeedModel(startURL: startURL))`
  的 autoclosure 只在**首次构建**执行；之后 `startURL` 改变但 model 还是旧的 → 永远显示
  上一次筛选/搜索的结果（`CategoryView.swift:107-115` 当前写法）。
- **正确写法**：筛选**不要**通过换 URL 复用视图身份；保持 `startURL` 在单次 push 内不变，
  筛选作为 model 的可变参数（`model.apply(filter:)` 内部重新拉取/重算）。如果必须换 URL：
  用 `.id(startURL)` 重建视图（但会丢滚动/状态，需接受）或在 model 里 `load(from:)` +
  `.task(id: startURL)` 明确取消旧请求。
- **验收**：同一次 push 内切换筛选，不会出现“筛选变了但请求还是旧 URL”；重复搜索两次
  第二次结果正确。

### R4 `.refreshable` + `ScrollView` + `safeAreaInset(.top)` 的兼容性

- **触发**：`ScrollView { ... }.refreshable { ... }` 与 `.safeAreaInset(edge: .top)` 同时用。
- **为什么错**：`.refreshable` 在 ScrollView 上是 iOS 16+ 可用（target 17 没问题），但
  与顶部 safeAreaInset 叠放时，下拉刷新的 spinner 可能被 inset 视图遮住/位置错位；
  另外 refresh 闭包常与 `loadMore` 并发：如果 refresh 重置了数据但旧 `loadMore` 返回后
  继续 append，会出现重复/乱序。模型里的 `generation` 必须保留（不要为了“简化”删掉）。
- **正确写法**：refresh 时 `generation += 1`（现有机制），旧请求一律 `guard token == generation`
  丢弃；refresh 结束（成功或失败）重置 `lastRequestedAlbumsCount`；顶部 inset 条不要用
  不透明背景，用 `.ultraThinMaterial` 且不加第二条底栏；首次实现后真机确认 spinner 位置。
- **验收**：下拉刷新时旧请求还在跑 → 最终列表无重复、无回退；刷新失败保留旧列表。

### R5 刷新 / 筛选“先清空再请求”会丢内容

- 见 P0-4。新实现里保留“旧数据直到新数据成功返回”，把 `reset` 分成
  `replaceOnSuccess`（刷新）与 `clearNow`（筛选变更）两种语义。
- **验收**：已有 10 页时断网 → 刷新 → 旧内容还在 + 错误条；恢复网络后重试成功替换。

### R6 骨架屏：`redacted`/shimmer 的性能与无障碍

- **触发**：12+ 个 skeleton 各自 `repeatForever` 动画；`redacted(reason: .placeholder)`。
- **为什么错**：每个卡片一个无限动画会持续触发重绘，120Hz/省电模式不友好；
  `.redacted` 只是样式，不自动屏蔽 VoiceOver；骨架如果可点会误触。
- **正确写法**：一个共享的 phase 动画（`TimelineView` 或单一 `.animation` + 外部 state），
  或只做静态灰色占位（更省电）；`allowsHitTesting(false)` + `.accessibilityHidden(true)`；
  `reduceMotion` 时关闭 shimmer；只在 `isLoading && albums.isEmpty` 且延迟 ~200ms 后显示，
  避免一闪而过。
- **验收**：Instruments/能耗无持续动画泄漏；VoiceOver 不读骨架；Reduce Motion 下无动画。

### R7 “回到顶部”：iOS 17 安全实现，且不要新增底栏

- **触发**：想监听滚动位置。注意 `onScrollGeometryChange` / `scrollPosition` 的某些
  modifier 是 **iOS 18+**；项目 deployment target 17.0（`project.yml:5-6,17`）。
- **为什么错**：直接用 iOS 18 API 在 Xcode 26 下不会编译报错（SDK 有），但运行到 iOS 17
  会 crash 或不可用；如果这里用 `safeAreaInset(.bottom)` 放回顶按钮，就把删掉的双层底栏
  又加回来（P1-3）。
- **正确写法**（iOS 17 可用）：顶部放 `GeometryReader { proxy in Color.clear.preference(...) }`
  哨兵 + `PreferenceKey`，在 `.onPreferenceChange` 里按阈值切换 `showBackToTop`；
  点击 `withAnimation { proxy.scrollTo(topAnchorID, anchor: .top) }`（给列表顶部加
  `Color.clear.frame(height: 0).id("top")`）；按钮放 `.overlay(alignment: .bottomTrailing)`，
  44×44、`.thinMaterial` 底、避开 tab bar（overlay 在 view 的安全区内，天然在 tab bar 上方）；
  `reduceMotion` 时无动画直接跳。
- **验收**：iOS 17 模拟器上编译 + 运行正常（不是只有 26 可用）；按钮不遮挡最后一行；
  滚回顶部后按钮消失。

### R8 原生 tab bar / iOS 26 Liquid Glass 共存

- **触发**：想“让列表滚到 tab bar 下面”“不要第二条底栏”“iOS 26 玻璃效果”。
- **正确写法**：
  - 删除 `safeAreaInset(edge: .bottom)` 条，让系统 tab bar 自己浮在内容上；
    背景只画在 ScrollView 底下（`Color(uiColor: .systemGroupedBackground).ignoresSafeArea()`）。
  - **不要**在内容层自绘 `.ultraThinMaterial`/`.glassEffect` 的大条（HIG Materials：
    Liquid Glass 是控件/导航层，不是内容层）；如需顶部 chips 的区分，可用内容内 header
    或很薄的 `.ultraThinMaterial` chip 背景。
  - iOS 26 专属 API（`glassEffect`、`scrollEdgeEffectStyle`、`safeAreaBar` 等）一律
    `if #available(iOS 26.0, *)` 包住，参照 `RootView.swift:40-44` 的既有模式；
    target 17 的代码必须能在 iOS 17 上跑。
  - 保持 `RootView` 的 `tabItem` 原生写法；不要接回自定义 tab bar（历史已证明会引发
    “是否隐藏 tab bar/双层栏”问题，见附录 A 的 37656b2 / a066508）。
- **验收**：iOS 17 与 iOS 26 各跑一遍；iPhone 横屏、iPadOS 18（tab bar 可能在顶部）都不出现
  第二条底栏或内容被遮；iOS 26 玻璃 tab bar 下内容可透视。

### R9 自适应网格 / Dynamic Type / 卡片高度一致性

- **触发**：`GridItem(.adaptive(minimum:maximum:))` + 3:4 封面 + 可选元信息行。
- **为什么错**：`minimum` 太小会得到 4–5 列过窄；`maximum` 太大会在 iPad 上出现 1–2 列巨卡；
  `AlbumCardView` 元信息行在 `pages == nil || date.isEmpty` 时高度为 0，同一行卡片高矮不齐；
  字号放大后标题 2 行不够。
- **正确写法**：`minimum ≈ 104, maximum ≈ 154` 起步（研究文档同为 104–140）；用
  `@ScaledMetric` 让 minimum 随字号增长；`isAccessibilitySize` 时降到 2 列；
  `AlbumCardView` 元信息行给固定最小高度/占位（或整体用
  `.frame(minHeight:)`），保证同行等高；卡片内不要写死 `font(.system(size:))`。
- **验收**：iPhone SE/15 Pro/iPad 竖横 + AX1/AX5 截屏对比，无截断、同行等高。

### R10 空态 / footer / 筛选无结果三态（连续网格下）

- **触发**：`visibleAlbums.isEmpty`、`hasMore == false`、`error != nil` 同时出现。
- **正确写法**：状态机优先级：`!albums.isEmpty && !visible.isEmpty` → 网格 + footer；
  `albums.isEmpty && isLoading` → 骨架；`albums.isEmpty && !isLoading` → 服务端空/错误；
  `!albums.isEmpty && visible.isEmpty` → 筛选空（保留 chips + 继续加载 + 清除筛选）；
  footer：`isLoading` → spinner；`error != nil` → “加载失败 · 重试”；`!hasMore` →
  “已经到底啦 · 共 N 部”；否则留 24pt 空位保证可触发。
- **验收**：四类场景各走一遍（断网首载、服务端 0 条、筛选 0 条、正常到底），文案与操作各不相同。

### R11 连续网格的内存 / 性能

- **触发**：连续滚动加载到几百上千条；`visibleAlbums` 每次 body 重算；封面缓存。
- **正确写法**：
  - 把过滤结果缓存成派生值（见 P2-4），不要每行/每 body 重算。
  - `albums` 本身是轻量 struct，可保留全部；**不要**重蹈 `7eff171` 的“运行时裁剪 + 滚动补偿”
    （随后 `1e9895b` 又删掉，因为滚动会跳）。若确需上限，裁掉“视口上方 >N 屏”的项并只
    在滚动停止时做，或干脆不裁。
  - 封面：`LazyVGrid` + `HomeCover.task(id:)` 已足够；但连续滚动会不断创建/销毁卡片，
    注意 NSCache 淘汰后回看要重新读盘；可提高缓存上限/预取下一屏、保持磁盘缓存清理。
  - `.onAppear` 触发不要放在每个 cell 里做重活；footer 哨兵即可。
- **验收**：连续滚 300+ 条、返回再看 10 次，FPS HUD 无明显掉帧、内存不持续增长。

### R12 导航与搜索复用（同一 CategoryView 三种入口）

- **触发**：首页 chips、“更多”、搜索、标签搜索都复用 `CategoryView`。
- **正确写法**：
  - 在 `HomeView` 的 `NavigationStack` 根部注册**唯一**的
    `.navigationDestination(for: HomeAlbum.self)`；`CategoryView`/`AlbumDetailView` 内部
    只发 `NavigationLink(value:)`，不注册 destination（避免“declared earlier on the stack”）。
  - 搜索入口（`HomeView.swift:298-307`）目前用 `navigationDestination(isPresented:)`；
    如果改成 value/item 驱动，注意不要在 pushed view 里再注册；`searchQuery` 变化时
    用 `.id(searchQuery)` 或改为 item 以保证重新构建 model（R3）。
  - 标签搜索与首页搜索统一 `appliesLanguageFilter: false`（搜索就是全语言），分类页才为 true。
  - 嵌套 CategoryView（分类→详情→标签→分类）是允许的，但每层只注册一次、状态独立。
- **验收**：深层嵌套 push/pop 10 次、重复搜索 2 次，无重复 push、无 console 警告、无旧结果。

### R13 编译 / 构建适配（Xcode 26.3 + iOS 17 target + XcodeGen）

- `ios/project.yml:5-6,17`：deployment target 17.0；Xcode 26.3 SDK 编译，**iOS 18/26 API
  必须 `#available` 守卫**（项目已用 `RootView.swift:40-44` 模式）。
- `ios/project.yml:18-20`：`sources: [Sources]` 自动收新文件；但 **WnacgProxyCheck 目标
  是显式文件清单**（96-111）。若把 model/解析逻辑拆成新文件且被 `HomeParser`/`WnacgClient`
  引用，CI 的 macOS smoke test 目标会编译失败——新增文件要同步加进该清单（或让新文件
  不被 proxy 目标依赖）。
- `.github/workflows/ios.yml:12-46`：Release / `-sdk iphoneos` 编译；`:48-65` 跑联网
  smoke test（依赖 wnacg 站点可达，网络抖动/429 可能导致 CI 红灯，与 UI 改动无关）。
  CI **没有 UI 测试**，布局/手势/无障碍只能人工验证——建议至少在 CI 前跑 `xcodebuild`
  确认编译，并按 §7 手测。
- 保持 `SWIFT_VERSION: "5.0"`（`project.yml:59`）：新代码不要依赖 Swift 6 严格并发特性；
  `@MainActor` model + `@StateObject` 现有模式可继续用。
- 若新增 XCTest target（可选）：把 model 的 loadMore 门控/去重/竞态抽成可注入 client 的
  纯逻辑测试，这是 CI 能覆盖的部分。

### R14 可访问性验收（连续网格 + chips）

- chips 高度 ≥44；选中态用填充 + checkmark + `.isSelected`，不只靠颜色；
- 卡片 `.accessibilityElement(children: .combine)` + label（标题/页数/日期），封面
  `.accessibilityHidden(true)`；`Text("\(pages)P")` 改“页”；
- 加载更多/筛选变化/回顶后用 `AccessibilityNotification.Announcement` 播报
  （如“已加载 20 部”“筛选：翻译”）；
- Reduce Motion：骨架、chips 切换、回顶滚动都要降级；
- 深色模式：只用语义色（`Color.primary/.secondary/.systemGroupedBackground`），
  不要 `.foregroundStyle(.black)`（v1.20.4 在 mint 按钮上用 black，浅/深色对比需复测）。

---

## 6. 历史：这 30+ 次改版到底试了什么（为什么 pager 是回头路）

`git log --oneline -- ios/Sources/CategoryView.swift` 共 44 个提交，2026-11-03/04 两天内
密集迭代；`git log --all --name-only -- '*CategoryGridView*'` 还能看到更早的
`CategoryGridView.swift`（424 行）与 `BatchGridView.swift`（404 行）两个连续网格实现。
关键节点：

| 提交 | 内容 | 教训 |
|---|---|---|
| `4fc6a43` | 最初的分类页：连续 `LazyVGrid` + 最后卡片 `onAppear` 加载 + 下拉刷新 + footer | 方向本来就是对的（README 至今还这样写） |
| `7dd4e8b` / `a78de9f` / `3514973` | 改用 `UIViewRepresentable` + `UICollectionView` 做网格/批量 | 为了性能/预取付出巨大复杂度 |
| `7d86487` / `f4eb86c` | “append pages during drag”“defer collection updates during drag” | **滚动中追加数据会导致布局跳/白屏**，必须延迟或动画外插入 |
| `b47ca61` / `eb50587` | 封面 prefetch、拖动时延迟加载 | 连续网格的封面任务管理是成本所在 |
| `661b6c4` | “Prevent white flash during category page trimming” | 运行时裁剪/身份变化会出现白闪 |
| `7eff171` → `1e9895b` | 先加数据上限+滚动补偿，后删除 | 裁剪方案会滚动跳变，最终放弃 |
| `3770379` | “Fix category infinite scroll request gate after loading” | onAppear 门控错过“加载结束”时机，需要 `lastRequestedCount` 这类令牌 |
| `89f0516` → `a7d11d7` | 切 9 条分页（同一个提交里甚至有语法错误，下一提交才修） | 分页是仓促切换，非设计结论 |
| `b38921c` / `84b6f16` / `969ae79` | 18 条批量 + 底部 spinner → 又“Restore continuous category scrolling” | 批量/分页模型反复被否定又回退 |
| `72b9d82` | `window.safeAreaInsets` + `.ignoresSafeArea` 让内容滚到底栏下 | 自绘底栏与安全区打架，后来改 `safeAreaInset` |
| `67dd214` | “polished 9-item paged category with page jump” | pager/跳页正式成型（问题都在这） |
| `0025afd` / `61603c0` / `dea9226` | 折叠底栏 / Liquid Glass / 原生 bottom toolbar | 都试图让 pager 不碍事，均回退 |
| `37656b2` → `a066508` | 换成自定义 Coolapk tab bar → 又回退原生 | 自定义 tab bar 与原生/多页面冲突，代价大 |
| `05c653d` | “Shrink pager controls and shield touches from covers” | 触点屏蔽 hack 的来源（现在仍残留） |
| `c947769` / `f52b7fb` / `40674ad` / `3c9ef04` | 小悬浮条 → 居中极简 → 去 header → 可收起 pager | 全是外观层微调，模型未动 |
| `ca9cb7f`（v1.20.4） | “Revert to centered always-visible pager” | 最终回到问题现场 |
| `af54fbc` / `1caaafe` | 删除 `CategoryGridView.swift` / `BatchGridView.swift` | 连续网格的实现被删，但没有被替代解决 |

结论：**pager 外观改了约 15 版都无解，说明要换的是“9 个一页”的模型，而不是 pager 样式。**
这次重做应直接回到 `4fc6a43` 的连续网格骨架，用 R1–R14 把当年踩过的坑补上。

---

## 7. 合并前验证清单

**静态检查（可在 Windows 完成）**

- [ ] `git grep -n "pageSize\|currentPage\|loadedPageCount\|jumpToPage\|showJump" -- ios/Sources` 无残留
- [ ] `git grep -n "safeAreaInset(edge: .bottom)" -- ios/Sources` 分类页无底栏
- [ ] `git grep -n "\.id(currentPage)" -- ios/Sources` 无
- [ ] `git grep -n "navigationDestination" -- ios/Sources` 只在栈根（HomeView）出现一次
- [ ] `git grep -n "onTapGesture {}" -- ios/Sources` 无触点屏蔽 hack
- [ ] iOS 18/26 API 均有 `#available` 守卫（`glassEffect`/`scrollEdgeEffectStyle` 等）
- [ ] `xcodegen` 后 `WnacgProxyCheck` 目标能编译（若新增/拆分文件，检查 `project.yml:96-111`）

**模拟器/真机 QA 矩阵**（CI 不覆盖，必须人工）

| 维度 | 取值 |
|---|---|
| 设备 | iPhone SE3、iPhone 15 Pro、iPhone 15 Pro Max、iPad 10、iPad Pro 11 |
| 方向 | 竖、横（iPhone 横屏 + iPad 四方向） |
| 系统 | iOS 17.x（必须能编译运行）、iOS 18.x、iOS 26.x（Liquid Glass / 顶部 tab bar） |
| 字号 | 默认、AX1、AX5（Dynamic Type） |
| 无障碍 | VoiceOver 全流程、Reduce Motion、加深色模式 |
| 功能 | 分类入口（chips/更多）、分页→连续滚动、筛选切换、清空筛选、筛选 0 结果、服务端 0 结果、断网首载、翻页中断网、下拉刷新失败、到底提示、返回详情再回来位置保持、旋转中滚动、后台回前台、重复搜索、标签搜索嵌套、iOS 26 tab bar 透视 |
| 性能 | 连续滚 300+ 条 + FPS HUD（设置里可开）、内存峰值、封面缓存磁盘清理 |

**行为验收（对应本文 P0/P1）**

- [ ] 横屏 iPhone 一屏至少完整显示 1 行卡片；9 宫格不再是“页”（P0-1）
- [ ] 不再出现 `N / M` 页码与跳页弹窗；底部可变内容只有 tab bar（P0-2/P1-3）
- [ ] 筛选到“翻译”后连续多个站点页无匹配时，自己能继续加载，不出现“本页没有…”死胡同（P0-3）
- [ ] 已有内容时刷新失败，旧内容仍在 + 有错误提示（P0-4）
- [ ] 页面可连续滑动浏览，无需点小箭头；44pt 触摸目标；VoiceOver 可读（P1-1/P1-2/P1-10）
- [ ] 筛选状态始终可见（chips/选中态），搜索页不显示无效语言筛选（P1-4）
- [ ] 加载失败（非首屏）有可见重试；跳页/继续加载失败有反馈（P1-6）
- [ ] 首屏骨架、到底提示、下拉刷新、三态文案（P1-7）
- [ ] 翻页/筛选不再整页闪白、封面不再逐张闪（P1-8）
- [ ] Dynamic Type AX5 下无截断/重叠（P1-9）
- [ ] AI 过滤标记正确（`MangaFilter.swift:42-83`），两个入口语言筛选语义一致（P2-1）

---

## 附录 A. 对 `redesign/category-ui` 分支的抽查（`7681a1d`，**进行中，非本文评审基线**）

> 写作时该分支正在改（worktree 还有未提交修改），以下仅作合并前自检提示，**不代表已实测**。
> 这一节不是对 v1.20.4 的评审。

1. **`CategoryFeedModel` 取消分支会卡住 `isLoading`**：`load(reset:force:)` 的
   `catch` 里 `if err is CancellationError { return }` 直接 `return`，跳过末尾
   `if token == generation { isLoading = false }`。若 429 退避的 `Task.sleep` 被取消
   （`WnacgClient.swift:68-73` 会抛 `CancellationError`），`isLoading` 永远 true →
   `loadMore()` 的 `guard !isLoading` 永远失败 → footer 一直转圈。建议 `defer` 复位。
2. **`onAppear` 最后一张卡片 + 过滤**：`albumGrid` 里
   `if album.id == visibleAlbums.last?.id { requestMore() }`。若某站点页的内容全被筛选掉
   （`visibleAlbums` 末尾 id 不变），`onAppear` 不会再次触发 → 停在 `hasMore == true`。
   `fillFilteredPages(limit:)` 只在首载/刷新/筛选变更时跑；滚动中途没有兜底。
   建议改用 footer 哨兵 + “连续无新增可见项就再拉一页（有界）”。
3. **筛选 pills 高度**：`.font(.caption)` + `.padding(.vertical, 7)` ≈ 31–33pt，
   低于 44pt 触摸目标；`.accessibilityAddTraits(.isSelected)` 有了，但 label/命中区还需补。
4. **`safeAreaInset(edge: .top)` + `.refreshable`**：下拉刷新 spinner 与顶部 filter bar
   的相对位置需要真机确认（SwiftUI 常见错位）。
5. **“清除筛选”仍会顺带 `hideAI = false`**（`filteredEmptyState`/`emptyState`），
   和 v1.20.4 相同的语义问题（P1-4），确认是否接受。
6. **`scrollToTop` 用 `visibleAlbums.first` 作为锚点**：筛选后若 `visibleAlbums` 为空
   （空态）则直接 return，滚动位置保持原处；确认空态展示位置是否合理（建议锚到
   `topAnchor` 而不是第一个 item）。
7. **`.scrollOffsetReader` 每帧 `onPreferenceChange`**：阈值切换有 guard，但
   `GeometryReader` 尺寸随内容变化；确认长列表滚动时无明显开销（用 FPS HUD 验证）。
8. 已做对、不要回退的点：无 `.id(currentPage)`、无底栏 pager、无跳页弹窗、
   `refresh()` 失败保留旧数据、`AlbumCardView` 元信息改 `.caption2`（Dynamic Type）、
   新增 `AlbumCardButtonStyle` 按压反馈、`onAppear` 过滤时 `fillFilteredPages`
   （方向对，但需 R1 的 footer 兜底）。

---

## 附录 B. 死代码 / 文档清理清单

| 对象 | 位置 | 处理 |
|---|---|---|
| `FloatingTabBar` | `ios/Sources/FloatingTabBar.swift:11` | 全仓无引用 → 删除（或明确接线；当前 `RootView` 用原生 `TabView`） |
| `selectedAlbum` + `.navigationDestination(item:)` | `ios/Sources/CategoryView.swift:95,139-141` | 删除，改栈根 value-based destination（P2-1） |
| `pageCount` / `resetGeneration` | `ios/Sources/CategoryView.swift:10-11` | 删除（从未被 View 读取） |
| 触控屏蔽层 | `CategoryView.swift:280-284` | 随底栏一起删除 |
| README 分类/搜索描述 | `README.md:48-50` | 改成新设计（连续滚动/筛选 chips/无分页） |
| README tab 列表 | `README.md:72-73` | 与实际 `RootView.swift:9-29`（首页/下载/收藏/文件/设置）一致 |
| `pageSize`/`jumpText`/`showJump`/`isLoadingPage` 状态 | `CategoryView.swift:96-100` | 随分页删除 |

---

## 附录 C. 无法静态验证、需真机确认的点

- 横屏/大字号下的实际行高与视口高度（本文 §2 为计算值，需模拟器截屏核对）。
- pager 底栏在 iOS 17 与 iOS 26 上的叠放/材质观感（尤其是 `tabBarMinimizeBehavior(.never)`）。
- `safeAreaInset(.top)` + `.refreshable` 下拉 spinner 位置（R4）。
- VoiceOver 实际朗读顺序/卡片合并效果（P1-10）。
- 站点每页真实条数（README 说 20、smoke test 断言 ≥10；最终以线上页面为准，但
  “app 的 9 条 ≠ 站点页”结论不受影响）。
- 429/代理 310 的真实触发频率（`WnacgClient.swift:60-95` 的重试与 `fillPage` 20 次串行
  请求叠加时的表现）。

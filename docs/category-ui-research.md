# 分类/二级列表页 UI 调研 + 可实施方案

目标页：`CategoryView`（同人志等分类、首页 section 的「更多」、搜索结果共用）。当前实现是「每页固定 9 个 + 底部居中悬浮 ‹ 1/N › 翻页器 + 跳页弹窗」，近 30 个 release 反复迭代仍未解决，说明**问题不在翻页器样式，而在"分页"这个模型本身**。

**结论先行**：删掉悬浮翻页器与固定 9 宫格，改成「一个连续自适应网格 + 触底自动加载 + 内容内联 footer + 顶部筛选 scope chips」。这是 Mihon/Tachiyomi 类阅读器采用的内容组织模型，也是 NN/g 对「无限滚动 + 明确的分页地标」的折中建议。

## 1. 平台与竞品模式调研（每条都影响下文 spec）

- **Apple HIG · Collections**：图像内容用标准网格；「避免在用户正在浏览时动态改变布局」——一次性改版到网格，不要边滚边变；每格要有足够 padding，方便点选 [HIG Collections](https://developer.apple.com/design/human-interface-guidelines/collections)。
- **HIG · Lists and tables**：文本型内容用列表；图像为主仍用 collection，不要把网格做成表格 [HIG Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)。
- **HIG · Tab bars**：iOS 上 tab bar 是浮在内容之上的 Liquid Glass 层，「导航到不同 section 时保持 tab bar 可见」；最小化行为只属于「带底部 accessory 的 tab bar」，通过点 tab 或滚回顶部退出 [HIG Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)。→ 不允许再叠第二条底栏。
- **HIG · Materials**：Liquid Glass 是「控件/导航层」，**不要用在内容层**；滚动边缘的模糊（scroll edge effect）由系统负责，regular 变体保证文字可读 [HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials)。
- **HIG · Loading**：一有内容就先显示，「用占位文本/图形先撑住，再逐步替换」——骨架屏优先于居中菊花 [HIG Loading](https://developer.apple.com/design/human-interface-guidelines/loading)。
- **HIG · Searching / Search fields**：结果页要「清楚显示当前筛选范围」；用 scope bar 在明确定义的分类间筛选；默认给最宽范围再收窄 [HIG Searching](https://developer.apple.com/design/human-interface-guidelines/searching)、[HIG Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields)。
- **NN/g · Infinite scrolling**：优点是无中断、交互成本低；风险是难以重新定位、**完整性的错觉**、到不了页脚、无障碍问题。推荐折中：无限滚动 + 明确的「加载更多/分页地标」[NN/g infinite scrolling](https://www.nngroup.com/articles/infinite-scrolling-tips/)。
- **NN/g · Response times**：0.1s 内视为瞬时，1s 内保持心流；>1s 必须有明确反馈 [NN/g response times](https://www.nngroup.com/articles/response-times-3-important-limits/)。→ 骨架屏阈值 ≈0.2–0.3s，不要每次翻页都整屏转圈。
- **HIG · Accessibility**：iOS 控件默认 44×44 pt，最小 28×28；带边框控件间距 ~12 pt、无边框 ~24 pt；支持 Dynamic Type 放大到 200%；正文对比度 4.5:1；手势必须有点击替代 [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)。
- **HIG · Motion**：动效要有目的、可关闭；高频交互不要加动画；滚动/翻页动画要能被打断 [HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion)。
- **MangaDex（浏览/搜索）**：高级搜索把标题/作者/语言/题材放一起，排序独立；语言过滤是单一入口 + 确认应用；结果支持网格/列表视图切换 [MangaDex 功能指南](https://forums.mangadex.org/threads/image-guide-to-useful-site-features.51612/)。
- **Mihon / Tachiyomi（开源漫画阅读器）**：库按 categories 组织、阅读器可配置（README 明列）；漫画阅读器的库/浏览普遍是「连续网格 + 顶部筛选」，而不是 9 个一页的假分页 [Mihon](https://github.com/mihonapp/mihon)。
- **iOS 26 原生配套**：`scrollEdgeEffectStyle(_:for:)`（iOS 26+）调滚动边缘效果 [API](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:))；若确实需要底部渐隐栏，用 iOS 26 的 `safeAreaBar(edge:alignment:spacing:content:)` 与系统融合，而不是自绘底板 [API](https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:))；`LazyVGrid` 用 `GridItem(.adaptive(minimum:maximum:))` 做自适应列数 [LazyVGrid](https://developer.apple.com/documentation/swiftui/lazyvgrid)。

## 2. 三个设计方向与取舍

### 方案 A（推荐）连续自适应网格 + 触底自动加载 + 内联 footer
站点分页对用户不可见，只作为数据游标；一张网格滚到底，末尾给「到底了」标记。
- 优点：无中断、无翻页器、无跳页弹窗；iPhone 3 列 / iPad 5–6 列同一套代码；返回详情页回来位置不丢；与原生 tab bar 零冲突；可访问性最好（VoiceOver 顺序连续）。
- 缺点：长列表内存增长（用懒加载 + 去重 + 上限回收）；必须补「到底」与「加载失败」地标，否则触发 NN/g 的完整性错觉。
- 风险控制：按 `aid` 去重（现有 `loadedAids` 可复用）；到底显示条数；筛选变化时重置换数据并回到顶部。

### 方案 B 显式「加载更多」按钮（保守替代）
首屏一页，底部一个 44pt 按钮，点一次追加一页。
- 优点：用户可控、省流量、分页地标明确；实现最小（保留现 model 的 `loadMore` 即可）。
- 缺点：3 列网格一页只有 9 个时几乎每屏都要点一次，交互成本高；NN/g 把它列为无限滚动的妥协方案，适合内容「等权重但不必一次看完」的站点；对「找同人志」这种持续浏览场景偏保守。
- 适用：站点反爬/超时严重时的降级方案（把自动加载改成手动按钮即可，UI 其余不变）。

### 方案 C 横向分页网格（每页一屏，左右滑）
- 优点：页码地标强，像「翻画册」；理论上能把「第 N 页」做得直观。
- 缺点：与 NavigationStack 的左滑返回手势冲突；一屏 9 个信息密度低；每页独立状态导致刷新/筛选后位置错乱；iPad 上每页留白更大；跳页仍需弹窗——即当前 30 次失败迭代的老路。
- 结论：**明确否决**，不要再用任何"翻页器"变体（coolapk 悬浮/可折叠/居中极简都属同一模型）。

## 3. 推荐实施方案（给 SwiftUI 工程师，可直接照做）

**3.1 导航与头部**
- 保留 `NavigationStack` 与 `.navigationTitle(title)` + `.navigationBarTitleDisplayMode(.inline)`、保留原生返回键与 `seamlessNavigationBar()`。
- 列表第一个 element 是**内容内头部**（不是 bar）：`Text(title)`（`.title2.bold()` 或滚动后隐藏）+ 一行副标题 `已加载 N 部 · 全部/翻译/日语`（`.footnote.secondary`）。不要用工具栏放标题。
- 刷新：**保留** toolbar 的 `arrow.clockwise`（手势的无障碍替代），同时加下拉刷新（3.9）；两者共用 `await reload()`。请求中按钮禁用，不弹 HUD。

**3.2 筛选状态可见性（chips，不用菜单）**
- 用一个横向 `ScrollView(.horizontal)` 的 scope chips 行，放在网格上方，**默认随内容滚走**（不 pinned，避免又变成一条"bar"）；若测试反馈筛选找不到，再改成 `pinnedViews: [.sectionHeaders]` 吸顶并只加一层极薄的 material 背景（不是第二条 bar）：
  `全部 | 翻译 | 日语` 三个互斥 chip + `隐藏 AI` 一个开关 chip（复用 `hideAI`）。
- **用 chips 而不是 Menu 的理由**：只有 3+1 个选项、且状态必须"一眼可见"；HIG 的 scope bar 正是"在明确定义的分类间筛选、默认最宽范围"的形态。超过 5 个选项再退回 Menu/sheet。
- 选中态：mint 填充 + 黑字（与现有 tab bar 选中态一致）+ 可选 checkmark（不能只靠颜色，见 3.12）；未选：`.thinMaterial` 胶囊 + 8% 描边（沿用首页 `chip(_:)` 的样式，保证同 App 一致）。
- 高度 ≥44pt（含 padding）；筛选变化：`resetFeed()` → 清空 albums、回到顶部、**不重建 ScrollView 的 identity**，只重建数据。

**3.3 自适应网格**
- `let columns = [GridItem(.adaptive(minimum: 104, maximum: 140), spacing: 10)]`，`LazyVGrid(columns:, spacing: 14)`；iPhone 自动 3 列，iPad 5–6 列，无需写两套。
- 卡片沿用 `AlbumCardView`（3:4 封面 + `.caption2` 两行标题）；**行内不要固定高度**，`.lineLimit(2, reservesSpace: true)` 保持行高一致。
- 动效：只在筛选切换/首次填充时 `.transition(.opacity)`；滚动中不加任何布局动画（HIG Motion：高频交互不加动效）。

**3.4 无限滚动 vs 假分页 → 选无限滚动（自动加载）**
- **理由**：假分页的"页"是客户端切出来的 9 条（`pageSize=9`），与站点页不是一回事，导致 (a) 每次切页 `.id(currentPage)` 重置滚动位置；(b) 末页可能只有 1–3 个；(c) 筛选作用在已加载数据上，会出现"本页没有符合筛选"但后续页有；(d) 用户要按很多次才能浏览。无限滚动把「翻页」变成网络游标，彻底消掉这四类 bug，也符合 NN/g 对浏览型内容的主流结论。
- 实现：`ForEach(Array(albums.enumerated()), id: \.element.id)`，在 `index >= albums.count - 6` 的 cell `.onAppear` 里 `await model.loadMore()`；`model` 已有 `hasMore/nextURL/isLoading/loadedAids`，直接复用。
- 必须保留：**不要** `.id(currentPage)`；`loadMore` 期间不改变已有网格的 identity；返回详情页时 NavigationStack 自动保留滚动位置。
- 失败降级：连续 2 次加载失败就自动切换成「加载更多」按钮模式（方案 B 的 footer），不阻塞已加载内容。

**3.5 首屏骨架（不是菊花）**
- 首次进入：渲染 9 个占位 cell（圆角 10 的灰块 + 两行灰条），`.redacted(reason: .placeholder)` 或直接自绘占位；透明度呼吸动画只在 `!reduceMotion` 时开启。
- 阈值：`isLoading && albums.isEmpty` 且已超过 ~200ms 才显示骨架，避免闪烁；一旦有数据立刻整体淡入替换（HIG Loading：先显示占位再替换）。
- 不显示居中 `ProgressView("正在加载…")` 全屏遮罩——这是当前实现看起来"卡"的主因之一。

**3.6 加载更多 footer（在内容里，不在 safeAreaInset）**
- 列表最后一个 element 是 footer：`HStack { ProgressView().controlSize(.small); Text("正在加载更多…") }`，`.footnote.secondary`，上下 padding 16，`accessibilityLabel("正在加载更多")`。
- 失败态：整行可点（≥44pt）「加载失败，点击重试」+ `wifi.exclamationmark`；点了触发同一 `loadMore()`。
- **放在 ScrollView 内部**，绝不使用 `safeAreaInset(edge:.bottom)` 画底板（那是当前悬浮条的根源，会与系统 tab bar 叠成两层）。

**3.7 到底状态**
- `hasMore == false && !albums.isEmpty` → footer 显示 `— 已经到底了 · 共 N 部 —`（`.caption2.tertiary`，居中，上下 24pt）。这正是 NN/g 说的"完整性错觉"解药：明确告诉用户列表结束。
- 空结果与"到底"要分开：0 条走 3.8。

**3.8 空态 / 错误态**
- 区分三种，文案与操作不同：
  - 加载失败且无数据：居中卡片（`wifi.exclamationmark` 橙色）「加载失败」+ 错误摘要 2 行 + `重试` 按钮（`.borderedProminent`.mint，≥44pt）；chips 保持可见可切。
  - 服务端确实 0 条：「本分类暂无作品」，副文案「下拉刷新试试」。
  - 筛选后 0 条：「当前筛选没有结果」+「清除筛选」按钮（清 language=all、hideAI=false），点击后回到全部并重置 feed。
- 不把错误做成 toast/HUD；错误要留在内容流里可重试。

**3.9 下拉刷新**
- `ScrollView { ... }.refreshable { await model.reload() }`（with 3.1 的 toolbar 按钮作为无障碍替代）。
- 刷新语义：保留当前筛选，重置到站点第一页，**保留网格 identity**；若用户已滚过 2 屏以上，刷新后温和回到顶部（`withAnimation`，reduce motion 时无动画）。

**3.10 回到顶部**
- 不新增常驻悬浮按钮（会再次与 tab bar 抢层级）。优先用系统能力：点状态栏回顶 + 再点当前 tab 回顶（上线前在 iOS 26 真机各验一次）；`RootView` 保持 `.tabBarMinimizeBehavior(.never)` [API](https://developer.apple.com/documentation/swiftui/tabbarminimizebehavior)，不引入底部 accessory。
- 如产品坚持要有可见入口：仅在滚动超过 2 屏后出现一个 44×44 的 `chevron.up` 小胶囊（`.thinMaterial`，非 Liquid Glass），点击回顶后立即隐藏；出现/消失用 opacity，`reduceMotion` 时直接切换。

**3.11 与原生 iOS 26 Liquid Glass tab bar 共存（关键）**
- **删除 `safeAreaInset(edge:.bottom)` 的整条悬浮栏**——这是"两层底栏"观感与各种遮挡问题的来源；网格内容按系统默认继续滚到 tab bar 下方，让 Liquid Glass 自己去透视内容。
- 不要再给列表底部加不透明 `systemGroupedBackground` 条；背景保持 `.systemGroupedBackground` 画在 ScrollView 下方即可。
- 导航栏继续 `toolbarBackground(.hidden)`；若顶部内容与状态栏文字对比不足，用 iOS 26 的 `.scrollEdgeEffectStyle(.soft, for: .top)`（默认 automatic 可先不动），而不是自己加毛玻璃条。
- 未来若真需要一条"列表工具条"（如排序），用 iOS 26 `safeAreaBar(edge:.bottom)` 让系统处理与 tab bar 的层叠，且只在需要时出现；不要自绘。

**3.12 触控 / 无障碍 / Dynamic Type**
- 所有可点元素 ≥44×44pt：chip 高度 44（文字 15pt + 上下 12 padding）、footer 重试行 44、刷新按钮系统尺寸即可；chip 间距 ≥8，避免误触。
- Dynamic Type：chip 用 `.subheadline`（不要固定 pt），卡片标题 `.caption2` 会随字号放大；在 `@Environment(\.dynamicTypeSize).isAccessibilitySize` 时把最小列宽提到 150pt 或直接降到 2 列，避免文字被压成 1 行截断。
- 颜色不只传达状态：选中 chip 同时有填充 + checkmark；错误同时有图标 + 文案；对比度按 4.5:1 检查（尤其薄荷绿上的黑字、深色模式下的 secondary 文本）。
- VoiceOver：卡片 `.accessibilityElement(children:.combine)` + label「标题，N 页，日期」；chip 用 `.accessibilityAddTraits(.isSelected)`；footer 加载完成时不要抢焦点，用 `AccessibilityNotification.Announcement` 播报「已加载另外 N 部」。
- 深色模式：只用语义色（`Color.primary/.secondary/.systemGroupedBackground`），不要硬编码白/黑；占位骨架用 `Color.primary.opacity(0.08)` 一类半透明色，自动适配。

**3.13 减少动态效果（Reduce Motion）**
- 读 `@Environment(\.accessibilityReduceMotion)`：关闭骨架呼吸、chip 切换缩放、回顶滚动动画（改为直接跳转），保留必要的 opacity 淡入（≤120ms）。
- 不做整页翻转/横滑转场（方案 C 本就被否决，此条兜底）。

## 4. 落地顺序与验收

1. 删悬浮翻页器 + 跳页弹窗 + `pageSize`/`currentPage`/`.id(currentPage)`，删 `safeAreaInset`。
2. 网格改 adaptive；接 `loadMore` 到底部触发；补 footer / 到底 / 错误 / 空态。
3. 加 header + scope chips，替换 toolbar 里的 `MangaFilterMenu`（其它页面保留菜单）。
4. 加骨架屏、下拉刷新、reduce-motion、Dynamic Type 分支。
5. 验收：iPhone SE/17 Pro Max + iPad 各跑一遍；VoiceOver 遍历一遍；Dynamic Type 最大字号无截断；切换筛选无"空页"；返回详情页回来位置保持；底部不再出现任何第二条 bar。

## 5. 参考来源

Apple Human Interface Guidelines：
- [Collections](https://developer.apple.com/design/human-interface-guidelines/collections) · [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables)
- [Loading](https://developer.apple.com/design/human-interface-guidelines/loading) · [Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- [Materials / Liquid Glass](https://developer.apple.com/design/human-interface-guidelines/materials) · [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
- [Searching](https://developer.apple.com/design/human-interface-guidelines/searching) · [Search fields / scope bars](https://developer.apple.com/design/human-interface-guidelines/search-fields)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

Apple Developer Documentation（iOS 26 / SwiftUI）：
- [LazyVGrid](https://developer.apple.com/documentation/swiftui/lazyvgrid) · [GridItem](https://developer.apple.com/documentation/swiftui/griditem)
- [scrollEdgeEffectStyle(_:for:)](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:)) · [safeAreaBar(edge:alignment:spacing:content:)](https://developer.apple.com/documentation/swiftui/view/safeareabar(edge:alignment:spacing:content:))
- [TabBarMinimizeBehavior](https://developer.apple.com/documentation/swiftui/tabbarminimizebehavior)

UX 研究：
- [NN/g — Infinite Scrolling: When to Use It, When to Avoid It](https://www.nngroup.com/articles/infinite-scrolling-tips/)
- [NN/g — Response Times: The 3 Important Limits](https://www.nngroup.com/articles/response-times-3-important-limits/)

竞品 / 开源参考：
- [Mihon（Tachiyomi 后继，开源漫画阅读器）](https://github.com/mihonapp/mihon)
- [MangaDex 功能指南（浏览/搜索筛选与语言过滤）](https://forums.mangadex.org/threads/image-guide-to-useful-site-features.51612/)

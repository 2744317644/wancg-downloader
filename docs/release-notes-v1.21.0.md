## 二级分类页重做（同人志 / 全部作品 / 栏目“更多” / 搜索结果）

之前的分类页把数据切成「每页固定 9 部」，再叠一条居中悬浮的 `‹ 1 / N ›` 翻页条；近 30 个版本都在改这条翻页器，但没有解决假分页本身带来的问题：横屏/iPad 下一页并不是一屏、页码分母只是“已加载页数”、筛选后整页被隐藏却没有入口、浮动条和原生 tab bar 叠成两层、切页时 `.id(currentPage)` 重置滚动位置。

这次直接换掉模型：

- **连续自适应网格**：删除固定 9 部一页、跳页弹窗、`.id(currentPage)`、底部浮动翻页条和触控屏蔽 hack；站点分页只作为数据游标。iPhone 三列，iPad/横屏自动增列（`GridItem(.adaptive)`）。
- **触底自动加载**：按作品 `aid` 去重，底部内联显示「正在加载更多 / 加载失败点击重试 / 已经到底了 · 共 N 部」，用触底哨兵替代“最后一张卡 onAppear”，整页被筛选掉也不会停滞。
- **筛选状态可见**：右上角菜单改成网格上方的「全部 / 翻译 / 日语」胶囊 + 「屏蔽 AI」开关（选中态带勾选、44pt 触摸目标）；切换筛选会回到顶部，并继续加载直到有匹配结果，不再出现“本页没有符合筛选”的假空页。
- **加载与异常**：首屏用骨架占位代替整屏转圈；下拉刷新失败保留已加载内容；加载失败内联重试；封面卡片按压反馈；Dynamic Type 与 Reduce Motion 适配。
- **稳定性修复**：修复请求取消后 `isLoading` 永远卡住导致一直转圈的问题；修复筛选后空态重试无效的问题；清理失败的悬浮 TabBar 实验代码和无用菜单。
- **与 iOS 26 Liquid Glass 共存**：只保留原生 `TabView` 底栏，不再叠加任何自绘底栏。

## 验证

GitHub Actions 中完成：

- Xcode 26.3 Release 编译 + macOS 代理/解析 smoke test 通过；
- iOS 模拟器 UI 测试通过：3 列 117.7pt 卡片、筛选胶囊 44pt、Tab Bar 只有一条、无旧页码控件；滚动自动加载到 33 部作品；筛选切换正常；详情页跳转/返回正常。

截图：

![分类页顶部](https://github.com/2744317644/wancg-downloader/releases/download/v1.21.0/category-top.png)

![筛选状态](https://github.com/2744317644/wancg-downloader/releases/download/v1.21.0/category-filtered.png)

![滚动加载](https://github.com/2744317644/wancg-downloader/releases/download/v1.21.0/category-scrolled.png)

版本 **1.21.0**（build 254），unsigned IPA 见下方 Assets。

import SwiftUI

struct SettingsView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    }

    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue
    @AppStorage("network.useSystemNetwork") private var useSystemNetwork = false
    @AppStorage("display.force120") private var force120 = true
    @AppStorage("performance.coverConcurrency") private var coverConcurrency = 3
    @AppStorage("performance.readerConcurrency") private var readerConcurrency = 2
    @AppStorage("content.hideAI") private var hideAI = false
    @AppStorage(TagExclusionStore.storageKey) private var excludedTagsRaw = ""
    @State private var showExcludeTags = false
    @AppStorage("debug.showFPS") private var showFPS = false

    var body: some View {
        NavigationStack {
            Form {
                Section("外观") {
                    Picker("深色模式", selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.icon)
                                .tag(mode.rawValue)
                        }
                    }
                }

                Section {
                    Toggle("使用系统网络 / Loon 分流", isOn: $useSystemNetwork)
                        .onChange(of: useSystemNetwork) { _, enabled in
                            Task.detached(priority: .userInitiated) {
                                ProxySession.shared.setUseSystemNetwork(enabled)
                            }
                        }
                } header: {
                    Text("网络")
                } footer: {
                    Text(
                        "开启后不再使用 App 内置 DoH 代理，"
                        + "直接交给 Loon、Clash 或系统 Wi-Fi 代理处理，"
                        + "适合按域名/DNS 分流。关闭时使用内置 DoH 直连。"
                    )
                }

                Section("浏览") {
                    NavigationLink {
                        HistoryView(embedded: true)
                    } label: {
                        Label("历史记录", systemImage: "clock.arrow.circlepath")
                    }
                }

                Section {
                    Toggle("锁定 120Hz（ProMotion）", isOn: $force120)
                        .onChange(of: force120) { _, enabled in
                            HighRefreshRateController.shared.setEnabled(enabled)
                        }
                } header: {
                    Text("显示")
                } footer: {
                    Text(
                        "开启后会请求 ProMotion 120Hz；"
                        + "实际帧率仍可能因省电、发热或系统策略降低。"
                    )
                }

                Section {
                    Stepper(
                        "封面并发 \(coverConcurrency)",
                        value: $coverConcurrency,
                        in: 1...6
                    )
                    .onChange(of: coverConcurrency) { _, value in
                        CoverImageStore.shared.setConcurrency(value)
                    }

                    Stepper(
                        "阅读器预载并发 \(readerConcurrency)",
                        value: $readerConcurrency,
                        in: 1...4
                    )
                    .onChange(of: readerConcurrency) { _, value in
                        ReaderImageStore.shared.setConcurrency(value)
                    }
                } header: {
                    Text("性能")
                } footer: {
                    Text(
                        "调高封面/阅读器预载并发会更快，但会增加 CPU、内存和 429 风险；"
                        + "卡顿或限流时调低。"
                    )
                }

                Section {
                    Toggle("屏蔽 AI 图集", isOn: $hideAI)
                    Button {
                        showExcludeTags = true
                    } label: {
                        HStack {
                            Label("排除标签", systemImage: "tag.slash")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(excludedTags.count)")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("内容")
                } footer: {
                    Text(
                        "屏蔽 AI 与排除标签会应用到首页、分类、搜索和标签搜索结果；"
                        + "排除标签优先读取站点标签页精确匹配，覆盖不到时按标题关键词回退。"
                        + "收藏和历史不受影响。"
                    )
                }

                Section {
                    Toggle("显示 FPS / 最慢帧", isOn: $showFPS)
                } header: {
                    Text("诊断")
                } footer: {
                    Text("在右上角显示实时 FPS 和最近最慢一帧耗时，用于反馈滑动卡顿。")
                }

                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("构建")
                        Spacer()
                        Text(appBuild)
                            .foregroundStyle(.secondary)
                    }
                    Link(destination: URL(
                        string: "https://github.com/2744317644/wancg-downloader/releases"
                    )!) {
                        Label("查看最新版本", systemImage: "arrow.up.circle")
                    }
                } header: {
                    Text("关于")
                }
            }
            .floatingTabBarContentInset()
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .seamlessNavigationBar()
            .sheet(isPresented: $showExcludeTags) {
                TagExclusionSheet(rawTags: $excludedTagsRaw)
            }
        }
    }

    private var excludedTags: [String] {
        TagExclusionStore.list(from: excludedTagsRaw)
    }
}

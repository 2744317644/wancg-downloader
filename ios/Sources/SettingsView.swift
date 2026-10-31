import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue
    @AppStorage("network.useSystemNetwork") private var useSystemNetwork = false

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
                            ProxySession.shared.setUseSystemNetwork(enabled)
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

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(
                            Bundle.main.infoDictionary?[
                                "CFBundleShortVersionString"
                            ] as? String ?? "1.0"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .seamlessNavigationBar()
        }
    }
}

import SwiftUI

struct RootView: View {
    @StateObject private var downloadModel = AppModel()
    @State private var selection = 0
    @AppStorage("debug.showFPS") private var showFPS = false

    private var downloadBadge: Int {
        downloadModel.queue.count + (downloadModel.hasActiveDownload ? 1 : 0)
    }

    var body: some View {
        let tabs = TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(0)

            ContentView(model: downloadModel, selectedTab: $selection)
                .tabItem { Label("下载", systemImage: "arrow.down.circle.fill") }
                .tag(1)
                .badge(downloadBadge)

            FavoritesView()
                .tabItem { Label("收藏", systemImage: "heart.fill") }
                .tag(2)

            FilesView()
                .tabItem { Label("文件", systemImage: "folder.fill") }
                .tag(3)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(4)
        }
        .tint(.mint)
        .environment(\.locale, AppDateFormatting.chineseLocale)
        .task {
            downloadModel.resumeQueueIfNeeded()
        }
        .environmentObject(downloadModel)
        .environmentObject(FavoritesStore.shared)
        .environmentObject(DownloadHistory.shared)
        .environmentObject(HistoryStore.shared)

        Group {
            if #available(iOS 26.0, *) {
                tabs.tabBarMinimizeBehavior(.never)
            } else {
                tabs
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .appReturnedFromBackground
            )
        ) { _ in
            if !downloadModel.hasActiveDownload {
                // Restarting the proxy blocks on a listener semaphore; keep it
                // off the main actor right after returning from background.
                Task.detached(priority: .utility) {
                    ProxySession.shared.restart()
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if showFPS {
                PerformanceHUD()
                    .padding(.top, 8)
                    .padding(.trailing, 12)
            }
        }
    }
}

#Preview {
    RootView()
}

import SwiftUI

struct RootView: View {
    @StateObject private var downloadModel = AppModel()
    @StateObject private var chrome = AppChrome()
    @State private var selection = 0
    @AppStorage("debug.showFPS") private var showFPS = false

    var body: some View {
        let tabs = TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
                .tag(0)

            ContentView(model: downloadModel)
                .tabItem { Label("下载", systemImage: "arrow.down.circle.fill") }
                .tag(1)

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
        .task {
            downloadModel.resumeQueueIfNeeded()
        }
        .environmentObject(downloadModel)
        .environmentObject(FavoritesStore.shared)
        .environmentObject(DownloadHistory.shared)
        .environmentObject(HistoryStore.shared)
        .environmentObject(chrome)

        tabs
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !chrome.isBarHidden {
                    AppBottomBar(selection: $selection, chrome: chrome)
                }
            }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .appReturnedFromBackground
            )
        ) { _ in
            if !downloadModel.hasActiveDownload {
                ProxySession.shared.restart()
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

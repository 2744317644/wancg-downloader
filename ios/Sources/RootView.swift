import SwiftUI

struct RootView: View {
    @StateObject private var downloadModel = AppModel()
    @State private var selection = 0
    @State private var settingsID = UUID()
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
                .id(settingsID)
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

        Group {
            if #available(iOS 26.0, *) {
                tabs.tabBarMinimizeBehavior(.onScrollDown)
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
                ProxySession.shared.restart()
            }
        }
        .onChange(of: selection) { _, newValue in
            if newValue != 4 {
                settingsID = UUID()
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

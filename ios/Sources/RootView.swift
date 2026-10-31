import SwiftUI

struct RootView: View {
    @StateObject private var downloadModel = AppModel()
    @State private var selection = 0

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

        Group {
            if #available(iOS 26.0, *) {
                tabs.tabBarMinimizeBehavior(.onScrollDown)
            } else {
                tabs
            }
        }
        .overlay(alignment: .bottom) {
            if downloadModel.hasActiveDownload || !downloadModel.queue.isEmpty {
                GeometryReader { proxy in
                    BottomDownloadProgress(model: downloadModel) {
                        selection = 1
                    }
                    .frame(width: min(proxy.size.width * 0.4, 240))
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height
                            - proxy.safeAreaInsets.bottom - 64
                    )
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .animation(
            .snappy(duration: 0.22),
            value: downloadModel.hasActiveDownload
        )
    }
}

#Preview {
    RootView()
}

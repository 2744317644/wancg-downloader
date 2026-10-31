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

            HistoryView()
                .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }
                .tag(3)

            FilesView()
                .tabItem { Label("文件", systemImage: "folder.fill") }
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

        if #available(iOS 26.0, *) {
            tabs.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            tabs
        }
    }
}

#Preview {
    RootView()
}

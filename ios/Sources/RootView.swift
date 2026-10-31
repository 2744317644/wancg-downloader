import SwiftUI

struct RootView: View {
    @StateObject private var downloadModel = AppModel()
    @State private var selection = 0
    @State private var tabBarExpanded = false

    private var tabs: some View {
        TabView(selection: $selection) {
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
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 76)
        }
        .tint(.mint)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            tabs

            FloatingTabBar(
                selection: $selection,
                expanded: $tabBarExpanded
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
        .simultaneousGesture(tabSwipe)
        .environmentObject(downloadModel)
        .environmentObject(FavoritesStore.shared)
        .environmentObject(DownloadHistory.shared)
        .environmentObject(HistoryStore.shared)
    }

    /// 上滑展开页签，下滑收起；不必滚到顶部，也不用点击。
    private var tabSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                let vertical = value.translation.height
                let horizontal = value.translation.width
                guard abs(vertical) > 30,
                      abs(vertical) > abs(horizontal) else {
                    return
                }
                let shouldExpand = vertical < 0
                guard shouldExpand != tabBarExpanded else { return }
                withAnimation(.snappy(duration: 0.22)) {
                    tabBarExpanded = shouldExpand
                }
            }
            .onEnded { value in
                let vertical = value.translation.height
                let horizontal = value.translation.width
                guard abs(vertical) > 24,
                      abs(vertical) > abs(horizontal) else {
                    return
                }
                withAnimation(.snappy(duration: 0.22)) {
                    tabBarExpanded = vertical < 0
                }
            }
    }
}

#Preview {
    RootView()
}

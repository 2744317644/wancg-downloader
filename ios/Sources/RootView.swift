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

            FilesView()
                .tabItem { Label("文件", systemImage: "folder.fill") }
                .tag(2)
        }
        .tint(.mint)
        .environmentObject(downloadModel)

        if #available(iOS 26.0, *) {
            // iOS 26 的系统 TabView 会自动使用 Liquid Glass 外观。
            tabs.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            tabs
        }
    }
}

#Preview {
    RootView()
}

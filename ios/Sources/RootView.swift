import SwiftUI

struct RootView: View {
    @StateObject private var downloadModel = AppModel()
    @StateObject private var chrome = AppChrome()
    @State private var selection = 0
    @AppStorage("debug.showFPS") private var showFPS = false

    var body: some View {
        ZStack {
            tabContent(HomeView(), tag: 0)
            tabContent(ContentView(model: downloadModel), tag: 1)
            tabContent(FavoritesView(), tag: 2)
            tabContent(FilesView(), tag: 3)
            tabContent(SettingsView(), tag: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            downloadModel.resumeQueueIfNeeded()
        }
        .environmentObject(downloadModel)
        .environmentObject(FavoritesStore.shared)
        .environmentObject(DownloadHistory.shared)
        .environmentObject(HistoryStore.shared)
        .environmentObject(chrome)
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

    @ViewBuilder
    private func tabContent<Content: View>(
        _ content: Content,
        tag: Int
    ) -> some View {
        content
            .opacity(selection == tag ? 1 : 0)
            .allowsHitTesting(selection == tag)
            .accessibilityHidden(selection != tag)
            .zIndex(selection == tag ? 1 : 0)
    }
}

#Preview {
    RootView()
}

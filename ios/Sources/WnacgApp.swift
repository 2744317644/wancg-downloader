import SwiftUI

extension Notification.Name {
    static let appReturnedFromBackground = Notification.Name(
        "wnacg.appReturnedFromBackground"
    )
}

@main
struct WnacgApp: App {
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    init() {
        DownloadFolders.prepare()
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "wnacg-url-cache"
        )
        if !UserDefaults.standard.bool(
            forKey: ProxySession.systemNetworkKey
        ) {
            _ = try? LocalProxy.shared.start()
        }
        Task { @MainActor in
            HighRefreshRateController.shared.applySavedSetting()
            DownloadLiveActivityManager.shared.cleanupOrphaned()
        }
    }

    private var colorScheme: ColorScheme? {
        AppearanceMode(rawValue: appearance)?.colorScheme
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(colorScheme)
                .onChange(of: scenePhase) { old, phase in
                    if phase == .active && old == .background {
                        NotificationCenter.default.post(
                            name: .appReturnedFromBackground, object: nil
                        )
                    }
                }
        }
    }
}

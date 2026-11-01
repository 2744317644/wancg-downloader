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
        if !UserDefaults.standard.bool(
            forKey: ProxySession.systemNetworkKey
        ) {
            _ = try? LocalProxy.shared.start()
        }
        Task { @MainActor in
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

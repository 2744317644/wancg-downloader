import SwiftUI

@main
struct WnacgApp: App {
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasBeenActive = false

    init() {
        if !UserDefaults.standard.bool(
            forKey: ProxySession.systemNetworkKey
        ) {
            _ = try? LocalProxy.shared.start()
        }
    }

    private var colorScheme: ColorScheme? {
        AppearanceMode(rawValue: appearance)?.colorScheme
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(colorScheme)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    if hasBeenActive {
                        ProxySession.shared.restart()
                    } else {
                        hasBeenActive = true
                    }
                }
        }
    }
}

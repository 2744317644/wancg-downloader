import SwiftUI

@main
struct WnacgApp: App {
    @AppStorage("appearance") private var appearance = AppearanceMode.system.rawValue

    init() {
        _ = try? LocalProxy.shared.start()
    }

    private var colorScheme: ColorScheme? {
        AppearanceMode(rawValue: appearance)?.colorScheme
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(colorScheme)
        }
    }
}

import SwiftUI

@main
struct WnacgApp: App {
    init() {
        _ = try? LocalProxy.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

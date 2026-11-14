import SwiftUI

enum AppLayout {
    /// Extra bottom room so the last row of scrollable content can clear the
    /// iOS 26 floating tab bar.
    static let floatingTabBarInset: CGFloat = 76
}

extension View {
    /// Add bottom content inset to scroll/List/Form content so it can scroll
    /// above the floating tab bar instead of being hidden behind it.
    func floatingTabBarContentInset() -> some View {
        contentMargins(
            .bottom,
            AppLayout.floatingTabBarInset,
            for: .scrollContent
        )
    }
}

import SwiftUI

extension View {
    /// 去掉滚动后导航栏的模糊/分割边界，保持整页连贯。
    func seamlessNavigationBar() -> some View {
        toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// 封面卡片的按压反馈；此前用 `.plain` 时网格里的卡片点击没有任何反馈。
struct AlbumCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// 全 App 统一的页面背景：浅色是轻微的系统色渐变，深色是带一点蓝调的近黑渐变。
/// 首页 / 分类 / 详情 / 下载 / 收藏 / 空状态都使用它，避免有的页面是纯灰、有的页面是渐变的割裂感。
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.04, green: 0.06, blue: 0.10),
                    Color(red: 0.02, green: 0.03, blue: 0.06),
                ]
                : [
                    Color(uiColor: .systemBackground),
                    Color(uiColor: .secondarySystemBackground),
                ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

import SwiftUI
import UIKit

extension Notification.Name {
    static let categoryHomeRequested = Notification.Name(
        "wnacg.categoryHomeRequested"
    )
    static let categoryPreviousRequested = Notification.Name(
        "wnacg.categoryPreviousRequested"
    )
    static let categoryNextRequested = Notification.Name(
        "wnacg.categoryNextRequested"
    )
    static let categoryJumpRequested = Notification.Name(
        "wnacg.categoryJumpRequested"
    )
}

@MainActor
final class AppChrome: ObservableObject {
    @Published var isCategoryActive = false
    @Published var isBarHidden = false
    @Published var currentPage = 0
    @Published var canGoPrevious = false
    @Published var canGoNext = false
    @Published var isLoadingPage = false
}

struct AppBottomBar: View {
    @Binding var selection: Int
    @ObservedObject var chrome: AppChrome

    private struct Tab {
        let title: String
        let icon: String
        let tag: Int
    }

    private let tabs = [
        Tab(title: "首页", icon: "house.fill", tag: 0),
        Tab(title: "下载", icon: "arrow.down.circle.fill", tag: 1),
        Tab(title: "收藏", icon: "heart.fill", tag: 2),
        Tab(title: "文件", icon: "folder.fill", tag: 3),
        Tab(title: "设置", icon: "gearshape.fill", tag: 4),
    ]

    var body: some View {
        Group {
            if chrome.isCategoryActive {
                categoryBar
            } else {
                tabBar
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .animation(.snappy(duration: 0.22), value: chrome.isCategoryActive)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.tag) { tab in
                Button {
                    selection = tab.tag
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 34, height: 28)
                            .background {
                                if selection == tab.tag {
                                    Capsule()
                                        .fill(Color.mint.opacity(0.18))
                                }
                            }
                        Text(tab.title)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(
                        selection == tab.tag ? Color.mint : Color.secondary
                    )
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 58)
        .padding(.horizontal, 6)
        .modifier(ChromeGlassCapsule())
    }

    private var categoryBar: some View {
        HStack(spacing: 10) {
            Button {
                NotificationCenter.default.post(
                    name: .categoryHomeRequested, object: nil
                )
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text("首页")
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回首页")

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                Button {
                    NotificationCenter.default.post(
                        name: .categoryPreviousRequested, object: nil
                    )
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 42, height: 42)
                }
                .disabled(!chrome.canGoPrevious || chrome.isLoadingPage)
                .opacity(
                    !chrome.canGoPrevious || chrome.isLoadingPage ? 0.35 : 1
                )

                if chrome.isLoadingPage {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 94, height: 42)
                } else {
                    Button {
                        NotificationCenter.default.post(
                            name: .categoryJumpRequested, object: nil
                        )
                    } label: {
                        HStack(spacing: 4) {
                            Text("第 \(chrome.currentPage + 1) 页")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .frame(width: 94, height: 42)
                    }
                }

                Button {
                    NotificationCenter.default.post(
                        name: .categoryNextRequested, object: nil
                    )
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 42, height: 42)
                }
                .disabled(!chrome.canGoNext || chrome.isLoadingPage)
                .opacity(
                    !chrome.canGoNext || chrome.isLoadingPage ? 0.35 : 1
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .modifier(ChromeGlassCapsule())
    }
}

private struct ChromeGlassCapsule: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
        }
    }
}

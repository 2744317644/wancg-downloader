import SwiftUI
import UIKit

private struct TabItem: Identifiable {
    let tag: Int
    let title: String
    let icon: String
    var id: Int { tag }
}

struct FloatingTabBar: View {
    @Binding var selection: Int
    @Binding var expanded: Bool

    private let items: [TabItem] = [
        TabItem(tag: 0, title: "首页", icon: "house.fill"),
        TabItem(tag: 1, title: "下载", icon: "arrow.down.circle.fill"),
        TabItem(tag: 2, title: "收藏", icon: "heart.fill"),
        TabItem(tag: 3, title: "历史", icon: "clock.arrow.circlepath"),
        TabItem(tag: 4, title: "文件", icon: "folder.fill"),
    ]

    var body: some View {
        let bar = HStack(spacing: 2) {
            ForEach(items) { item in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.snappy(duration: 0.22)) {
                        selection = item.tag
                        expanded = false
                    }
                } label: {
                    VStack(spacing: expanded ? 2 : 0) {
                        Image(systemName: item.icon)
                            .font(.system(
                                size: expanded ? 17 : 19,
                                weight: .semibold
                            ))
                        if expanded {
                            Text(item.title)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, expanded ? 7 : 9)
                    .foregroundStyle(
                        selection == item.tag ? Color.black : Color.primary
                    )
                    .background(
                        selection == item.tag ? Color.mint : Color.clear,
                        in: Capsule()
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
        }
        .padding(5)
        .frame(maxWidth: .infinity)

        Group {
            if #available(iOS 26.0, *) {
                bar.glassEffect(.regular, in: Capsule())
            } else {
                bar.background(.ultraThinMaterial, in: Capsule())
            }
        }
        .overlay(
            Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }
}

import SwiftUI

struct DownloadTopBar: View {
    @ObservedObject var model: AppModel
    let onTap: () -> Void

    private var title: String {
        model.preview?.title ?? "正在解析作品…"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.mint)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if !model.queue.isEmpty {
                            Text("队列 \(model.queue.count)")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }
                        Text("\(Int(model.downloadProgress * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: model.downloadProgress)
                        .tint(.mint)
                        .scaleEffect(x: 1, y: 0.8, anchor: .center)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                Divider().opacity(0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("正在下载 \(title)，点击查看下载页")
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

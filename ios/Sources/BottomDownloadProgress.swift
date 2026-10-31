import SwiftUI

struct BottomDownloadProgress: View {
    @ObservedObject var model: AppModel
    let onTap: () -> Void

    private var progress: Double {
        min(1, max(0, model.downloadProgress))
    }

    var body: some View {
        Button(action: onTap) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.22))
                    Capsule()
                        .fill(Color.mint)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("下载进度 \(Int(progress * 100))%")
        .animation(.linear(duration: 0.2), value: progress)
    }
}

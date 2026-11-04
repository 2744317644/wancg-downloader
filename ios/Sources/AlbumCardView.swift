import SwiftUI
import UIKit

struct AlbumCardView: View {
    let album: HomeAlbum

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HomeCover(album: album)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)

            Text(album.title)
                .font(.caption2)
                .foregroundStyle(Color.primary.opacity(0.92))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)

            HStack(spacing: 4) {
                if let pages = album.pages {
                    Text("\(pages)P")
                }
                if !album.date.isEmpty {
                    Text(album.date)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}

extension AlbumCardView: Equatable {
    static func == (lhs: AlbumCardView, rhs: AlbumCardView) -> Bool {
        lhs.album == rhs.album
    }
}

/// 首页 / 分类页共用的骨架占位卡。
struct AlbumSkeletonCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .aspectRatio(3.0 / 4.0, contentMode: .fit)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(height: 9)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .frame(width: 62, height: 8)
        }
        .opacity(dimmed ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
            ) {
                dimmed = true
            }
        }
    }
}

struct HomeCover: View {
    let album: HomeAlbum
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.low)
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(Color.primary.opacity(0.18))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .task(id: album.coverURL) {
            guard let coverURL = album.coverURL else { return }
            if let cached = CoverImageStore.shared.cachedImage(for: coverURL) {
                image = cached
                return
            }
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            let loaded = await CoverImageStore.shared.image(
                for: coverURL, referer: album.pageURL
            )
            guard !Task.isCancelled, let loaded else { return }
            image = loaded
        }
    }
}

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
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
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
            let loaded = await CoverImageStore.shared.image(
                for: coverURL, referer: album.pageURL
            )
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

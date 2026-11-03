import SwiftUI
import UIKit
import Kingfisher

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

    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
        "Version/17.0 Mobile/15E148 Safari/604.1"

    private var coverModifier: AnyModifier {
        AnyModifier { request in
            var request = request
            request.setValue(
                album.pageURL.absoluteString,
                forHTTPHeaderField: "Referer"
            )
            request.setValue(
                Self.userAgent, forHTTPHeaderField: "User-Agent"
            )
            return request
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))

            KFImage(album.coverURL)
                .placeholder {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(Color.primary.opacity(0.18))
                }
                .setProcessor(
                    DownsamplingImageProcessor(
                        size: CGSize(width: 360, height: 480)
                    )
                )
                .scaleFactor(UIScreen.main.scale)
                .backgroundDecode()
                .requestModifier(coverModifier)
                .fade(duration: 0.15)
                .resizable()
                .scaledToFill()
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

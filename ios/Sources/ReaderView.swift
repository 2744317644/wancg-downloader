import SwiftUI
import UIKit
import ImageIO

private enum ReaderImageDecoder {
    static let maxPixelSize: CGFloat = 1600

    static func downsample(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }
}

@MainActor
final class ReaderModel: ObservableObject {
    let aid: String
    let title: String

    @Published var pageURLs: [URL] = []
    @Published var isLoading = true
    @Published var error: String?

    private var client: WnacgClient?
    private var loaded = false

    init(aid: String, title: String) {
        self.aid = aid
        self.title = title
    }

    func load() async {
        guard !loaded else { return }
        isLoading = true
        do {
            let client = try WnacgClient()
            self.client = client
            let itemURL = URL(
                string: "https://www.wnacg.com/photos-item-aid-\(aid).html"
            )!
            let galleryURL = URL(
                string: "https://www.wnacg.com/photos-index-aid-\(aid).html"
            )!
            let html = try await client.fetchHTML(
                itemURL, referer: galleryURL
            )
            guard let arrayText = HTMLParser.first(
                "\"page_url\"\\s*:\\s*\\[(.*?)\\]", in: html
            ) else {
                throw WnacgError.message("没有找到阅读图片")
            }
            let raw = HTMLParser.all("\"(https?://[^\"]+)\"", in: arrayText)
            let urls = raw.map { value in
                value
                    .replacingOccurrences(of: "\\/", with: "/")
                    .replacingOccurrences(of: "http://", with: "https://")
            }.compactMap(URL.init(string:))
            guard !urls.isEmpty else {
                throw WnacgError.message("阅读页没有图片")
            }
            pageURLs = urls
            error = nil
            loaded = true
        } catch let err {
            error = err.localizedDescription
        }
        isLoading = false
    }
}

@MainActor
final class ReaderImageStore {
    static let shared = ReaderImageStore()

    private let cache = NSCache<NSURL, UIImage>()
    private var client: WnacgClient?

    private var prefetching = Set<URL>()
    private var prefetchQueue: [(url: URL, referer: URL)] = []
    private var activePrefetch = 0
    private let maxConcurrentPrefetch = 1

    private init() {
        cache.countLimit = 16
        cache.totalCostLimit = 140 * 1024 * 1024
    }

    func image(for url: URL, referer: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        if client == nil {
            client = try? WnacgClient()
        }
        guard let client else { return nil }

        do {
            let data = try await client.imageData(url, referer: referer)
            guard let image = await decode(data) else { return nil }
            cacheImage(image, for: url)
            return image
        } catch {
            // img5 偶发超时，尝试同一路径的 img4 镜像。
            if var components = URLComponents(
                url: url, resolvingAgainstBaseURL: false
            ), components.host == "img5.qy0.ru" {
                components.host = "img4.qy0.ru"
                if let mirror = components.url,
                   let data = try? await client.imageData(mirror, referer: referer),
                   let image = await decode(data) {
                    cacheImage(image, for: url)
                    return image
                }
            }
            return nil
        }
    }

    private func decode(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            ReaderImageDecoder.downsample(data)
        }.value
    }

    /// 预载当前页下面的图片，默认由页面传入后续 10 页。
    func prefetch(_ urls: [URL], referer: URL) {
        for url in urls {
            guard cache.object(forKey: url as NSURL) == nil,
                  !prefetching.contains(url) else {
                continue
            }
            prefetching.insert(url)
            prefetchQueue.append((url, referer))
        }
        startPrefetch()
    }

    private func startPrefetch() {
        while activePrefetch < maxConcurrentPrefetch,
              !prefetchQueue.isEmpty {
            let item = prefetchQueue.removeFirst()
            activePrefetch += 1
            Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: .milliseconds(120))
                _ = await self.image(for: item.url, referer: item.referer)
                self.finishPrefetch(item.url)
            }
        }
    }

    private func finishPrefetch(_ url: URL) {
        prefetching.remove(url)
        activePrefetch = max(0, activePrefetch - 1)
        startPrefetch()
    }

    private func cacheImage(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

struct ReaderView: View {
    let aid: String
    let title: String

    @StateObject private var model: ReaderModel

    init(aid: String, title: String) {
        self.aid = aid
        self.title = title
        _model = StateObject(wrappedValue: ReaderModel(aid: aid, title: title))
    }

    private var referer: URL {
        URL(string: "https://www.wnacg.com/photos-item-aid-\(aid).html")!
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(model.pageURLs.enumerated()), id: \.offset) { index, url in
                    ReaderPageView(
                        url: url,
                        referer: referer,
                        pageNumber: index + 1,
                        prefetchURLs: Array(
                            model.pageURLs.dropFirst(index + 1).prefix(10)
                        )
                    )
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !model.pageURLs.isEmpty {
                    Text("\(model.pageURLs.count)P")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if model.isLoading {
                ProgressView("正在加载图片…")
                    .tint(.white)
            } else if let error = model.error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        Task { await model.load() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.mint)
                    .foregroundStyle(.black)
                }
                .padding()
            }
        }
        .task {
            await model.load()
        }
    }
}

private struct ReaderPageView: View {
    let url: URL
    let referer: URL
    let pageNumber: Int
    let prefetchURLs: [URL]

    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0

    private var placeholderHeight: CGFloat {
        UIScreen.main.bounds.width * 1.4
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            } else if failed {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.3))
                    Button("重试") {
                        attempt += 1
                    }
                    .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .frame(height: placeholderHeight)
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: placeholderHeight)
            }

            Text("\(pageNumber)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(8)
        }
        .task(id: attempt) {
            failed = false
            ReaderImageStore.shared.prefetch(prefetchURLs, referer: referer)
            image = await ReaderImageStore.shared.image(
                for: url, referer: referer
            )
            failed = image == nil
        }
    }
}

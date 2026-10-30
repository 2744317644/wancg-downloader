import SwiftUI
import UIKit

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
            let html = try await client.fetchHTML(itemURL)
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

    private init() {
        cache.countLimit = 8
    }

    func image(for url: URL, referer: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        do {
            if client == nil {
                client = try WnacgClient()
            }
            guard let client else { return nil }
            let data = try await client.imageData(url, referer: referer)
            guard let image = UIImage(data: data) else { return nil }
            cache.setObject(image, forKey: url as NSURL)
            return image
        } catch {
            return nil
        }
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
                        pageNumber: index + 1
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

    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0

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
                .frame(height: 320)
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
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
            image = await ReaderImageStore.shared.image(
                for: url, referer: referer
            )
            failed = image == nil
        }
    }
}

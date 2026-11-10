import SwiftUI
import UIKit
import ImageIO
import CryptoKit

@MainActor
final class HomeFeedModel: ObservableObject {
    @Published var sections: [HomeSection] = []
    @Published var isLoading = false
    @Published var error: String?

    private var client: WnacgClient?
    private var loaded = false
    private var generation = 0

    func load(force: Bool = false) async {
        if !force && (isLoading || loaded) { return }
        generation += 1
        let current = generation
        isLoading = true
        error = nil
        do {
            let client = try WnacgClient()
            self.client = client
            let html = try await client.fetchHTML(
                URL(string: "https://www.wnacg.com/")!
            )
            guard current == generation else { return }
            let parsed = await Task.detached(priority: .userInitiated) {
                HomeParser.parse(html)
            }.value
            guard current == generation else { return }
            sections = parsed
            loaded = true
            if sections.isEmpty {
                error = "首页没有解析到作品，可能站点结构变了"
            }
        } catch let err {
            guard current == generation else { return }
            error = err.localizedDescription
        }
        if current == generation {
            isLoading = false
        }
    }
}

private actor CoverLimiter {
    private var limit: Int
    private var active = 0
    private var order: [UUID] = []
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire() async throws {
        if active < limit {
            active += 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                waiters[id] = continuation
                order.append(id)
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func updateLimit(_ newLimit: Int) {
        limit = max(1, newLimit)
        while active < limit {
            guard let id = order.first else { break }
            order.removeFirst()
            guard let continuation = waiters.removeValue(forKey: id) else {
                continue
            }
            active += 1
            continuation.resume()
        }
    }

    private func cancel(_ id: UUID) {
        guard let continuation = waiters.removeValue(forKey: id) else {
            return
        }
        order.removeAll { $0 == id }
        continuation.resume(throwing: CancellationError())
    }

    func release() {
        while let id = order.first {
            order.removeFirst()
            guard let continuation = waiters.removeValue(forKey: id) else {
                continue
            }
            continuation.resume()
            return
        }
        active = max(0, active - 1)
    }
}

@MainActor
final class CoverImageStore {
    static let shared = CoverImageStore()
    static let concurrencyKey = "performance.coverConcurrency"

    private let cache = NSCache<NSURL, UIImage>()
    private let limiter: CoverLimiter
    private let coverCacheDirectory: URL
    private var client: WnacgClient?

    private init() {
        let saved = UserDefaults.standard.object(
            forKey: Self.concurrencyKey
        ) as? Int ?? 3
        limiter = CoverLimiter(limit: saved)
        let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        coverCacheDirectory = caches.appendingPathComponent(
            "CoverThumbnails", isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: coverCacheDirectory, withIntermediateDirectories: true
        )
        cache.countLimit = 120
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func setConcurrency(_ value: Int) {
        let clamped = min(6, max(1, value))
        Task { await limiter.updateLimit(clamped) }
    }

    func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func image(for url: URL, referer: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        let directory = coverCacheDirectory
        if let diskImage = await Task.detached(priority: .utility, operation: {
            Self.readThumbnail(for: url, in: directory)
        }).value {
            cache.setObject(
                diskImage,
                forKey: url as NSURL,
                cost: Int(diskImage.size.width * diskImage.size.height * 4)
            )
            return diskImage
        }

        return await loadImage(for: url, referer: referer)
    }

    private func loadImage(for url: URL, referer: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        do {
            try Task.checkCancellation()
            try await limiter.acquire()
            defer {
                Task { await limiter.release() }
            }
            try Task.checkCancellation()
            if let cached = cache.object(forKey: url as NSURL) {
                return cached
            }
            if client == nil {
                client = try? WnacgClient()
            }
            guard let client else { return nil }
            let data = try await client.imageData(url, referer: referer)
            try Task.checkCancellation()
            // Downsample *and* JPEG-encode on the background queue. Encoding
            // used to run on the main actor; when a page of 20 covers landed
            // at once it produced visible scroll hitches.
            let prepared = await Task.detached(priority: .background) {
                Self.prepareThumbnail(data)
            }.value
            guard let prepared else { return nil }
            let image = prepared.image
            let cost = Int(image.size.width * image.size.height * 4)
            cache.setObject(image, forKey: url as NSURL, cost: cost)

            if let thumbnail = prepared.thumbnailData {
                let directory = coverCacheDirectory
                Task.detached(priority: .utility) {
                    let destination = Self.diskURL(for: url, in: directory)
                    try? thumbnail.write(to: destination, options: .atomic)
                }
            }
            return image
        } catch {
            return nil
        }
    }

    nonisolated private static func diskURL(for url: URL, in directory: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".jpg")
    }

    nonisolated private static func readThumbnail(
        for url: URL,
        in directory: URL
    ) -> UIImage? {
        let fileURL = diskURL(for: url, in: directory)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        guard let source = CGImageSourceCreateWithURL(
            fileURL as CFURL, nil
        ) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 360,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else { return nil }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }

    nonisolated private static func prepareThumbnail(
        _ data: Data
    ) -> (image: UIImage, thumbnailData: Data?)? {
        guard let image = downsample(data) else { return nil }
        return (image, image.jpegData(compressionQuality: 0.82))
    }

    nonisolated private static func downsample(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 360,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }
}

struct HomeView: View {
    @StateObject private var model = HomeFeedModel()
    @State private var searchText = ""
    @State private var searchQuery = ""
    @State private var showSearch = false
    @AppStorage("content.hideAI") private var hideAI = false
    @AppStorage(TagExclusionStore.storageKey) private var excludedTagsRaw = ""
    @State private var tagIndexVersion = 0

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: 3
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if model.sections.isEmpty && model.isLoading {
                        loadingView
                    } else if let error = model.error, model.sections.isEmpty {
                        errorView(error)
                    } else {
                        categoryChips
                        ForEach(displaySections) { section in
                            sectionView(section)
                        }
                        if let error = model.error {
                            HStack(spacing: 8) {
                                Image(systemName: "wifi.exclamationmark")
                                    .foregroundStyle(.orange)
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Spacer(minLength: 0)
                                Button("重试") {
                                    Task { await model.load(force: true) }
                                }
                                .font(.caption2)
                            }
                            .padding(.vertical, 4)
                        }
                        footer
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(background)
            .navigationTitle("发现")
            .navigationBarTitleDisplayMode(.inline)
            .seamlessNavigationBar()
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索漫画"
            )
            .onSubmit(of: .search) {
                submitSearch()
            }
            .navigationDestination(isPresented: $showSearch) {
                if !searchQuery.isEmpty,
                   let url = HomeParser.searchURL(searchQuery) {
                    CategoryView(
                        title: "搜索：\(searchQuery)",
                        startURL: url
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.load(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
                }
            }
            .refreshable {
                await model.load(force: true)
            }
            .task {
                await model.load()
                await refreshTagCoverage()
            }
            .onChange(of: excludedTagsRaw) { _, _ in
                Task { await refreshTagCoverage() }
            }
        }
    }

    private func refreshTagCoverage() async {
        let excluded = TagExclusionStore.list(from: excludedTagsRaw)
        guard !excluded.isEmpty else {
            tagIndexVersion += 1
            return
        }
        let dates = model.sections
            .flatMap(\.albums)
            .compactMap { $0.date.isEmpty ? nil : $0.date }
        await ExcludedTagIndex.shared.ensureCoverage(
            tags: excluded,
            through: dates.min() ?? ""
        )
        tagIndexVersion += 1
    }

    private func submitSearch() {
        let value = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        searchQuery = value
        showSearch = true
    }

    private var displaySections: [HomeSection] {
        _ = tagIndexVersion
        let excluded = TagExclusionStore.list(from: excludedTagsRaw)
        guard hideAI || !excluded.isEmpty else { return model.sections }
        return model.sections.compactMap { section in
            let albums = section.albums.filter {
                (!hideAI || !$0.isAI)
                    && !ExcludedTagIndex.shared.isExcluded(
                        album: $0,
                        tags: excluded
                    )
            }
            guard !albums.isEmpty else { return nil }
            return HomeSection(
                title: section.title,
                albums: albums,
                moreURL: section.moreURL
            )
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                NavigationLink {
                    CategoryView(
                        title: "全部作品",
                        startURL: URL(string: "https://www.wnacg.com/albums.html")!
                    )
                } label: {
                    chip("全部")
                }
                .buttonStyle(.plain)

                ForEach(displaySections) { section in
                    if let moreURL = section.moreURL {
                        NavigationLink {
                            CategoryView(
                                title: section.title,
                                startURL: moreURL
                            )
                        } label: {
                            chip(section.title)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(Color.primary.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    private func sectionView(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [.mint, .blue],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: 15)
                Text(section.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if let moreURL = section.moreURL {
                    NavigationLink {
                        CategoryView(
                            title: section.title,
                            startURL: moreURL
                        )
                    } label: {
                        HStack(spacing: 2) {
                            Text("更多")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.mint)
                        .padding(.leading, 6)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if section.albums.isEmpty {
                Text("该分类暂无作品")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(section.albums) { album in
                    NavigationLink {
                        AlbumDetailView(album: album)
                    } label: {
                        AlbumCardView(album: album).equatable()
                    }
                        .buttonStyle(AlbumCardButtonStyle())
                    }
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在加载首页…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // 骨架屏比居中菊花更稳：首屏布局不跳，图片回来时自然填充。
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(0..<9, id: \.self) { _ in
                    AlbumSkeletonCard()
                }
            }
        }
        .padding(.vertical, 4)
        .allowsHitTesting(false)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试") {
                Task { await model.load(force: true) }
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)
            .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private var footer: some View {
        Text("仅供个人备份")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
    }

    private var background: some View {
        AppBackground()
    }
}

import SwiftUI
import UIKit
import ImageIO

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
            sections = HomeParser.parse(html)
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

@MainActor
final class CoverImageStore {
    static let shared = CoverImageStore()

    private let cache = NSCache<NSURL, UIImage>()
    private var client: WnacgClient?

    private init() {
        cache.countLimit = 120
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    func image(for url: URL, referer: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        do {
            if client == nil {
                client = try? WnacgClient()
            }
            guard let client else { return nil }
            let data = try await client.imageData(url, referer: referer)
            guard let image = await Task.detached(
                priority: .userInitiated
            ) {
                Self.downsample(data)
            }.value else { return nil }
            let cost = Int(image.size.width * image.size.height * 4)
            cache.setObject(image, forKey: url as NSURL, cost: cost)
            return image
        } catch {
            return nil
        }
    }

    private static func downsample(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 520,
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
    @Environment(\.colorScheme) private var colorScheme

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
                        ForEach(model.sections) { section in
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
                        startURL: url,
                        appliesLanguageFilter: false
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
            }
        }
    }

    private func submitSearch() {
        let value = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        searchQuery = value
        showSearch = true
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

                ForEach(model.sections) { section in
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
                Spacer()
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
                        .font(.caption2)
                        .foregroundStyle(.mint)
                    }
                    .buttonStyle(.plain)
                }
                Text("\(section.albums.count) 部")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                        AlbumCardView(album: album)
                    }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("正在加载首页…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
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
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.04, green: 0.06, blue: 0.10),
                    Color(red: 0.02, green: 0.03, blue: 0.06),
                ]
                : [
                    Color(uiColor: .systemBackground),
                    Color(uiColor: .secondarySystemBackground),
                ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

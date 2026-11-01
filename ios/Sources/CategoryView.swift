import SwiftUI
import UIKit

@MainActor
final class CategoryFeedModel: ObservableObject {
    @Published private(set) var albums: [HomeAlbum] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var hasMore = true
    @Published private(set) var pageCount = 0

    private let startURL: URL
    private var nextURL: URL?
    private var client: WnacgClient?
    private var loaded = false
    private var generation = 0
    private var loadedAids = Set<String>()

    init(startURL: URL) {
        self.startURL = startURL
        self.nextURL = startURL
    }

    func loadIfNeeded() async {
        guard !loaded else { return }
        await load(reset: true)
    }

    func reload() async {
        loaded = false
        await load(reset: true, force: true)
    }

    func loadMore() async {
        guard loaded, hasMore, !isLoading else { return }
        await load(reset: false)
    }

    private func load(reset: Bool, force: Bool = false) async {
        if isLoading && !force { return }
        generation += 1
        let current = generation

        if reset {
            albums = []
            loadedAids.removeAll(keepingCapacity: false)
            pageCount = 0
            nextURL = startURL
            hasMore = true
            error = nil
            loaded = false
        }
        guard let url = nextURL else {
            hasMore = false
            return
        }

        isLoading = true
        do {
            if client == nil {
                client = try WnacgClient()
            }
            guard let client else { return }
            let html = try await client.fetchHTML(url)
            guard current == generation else { return }
            let newAlbums = HomeParser.parseCards(html)
            let unique = newAlbums.filter {
                loadedAids.insert($0.aid).inserted
            }
            albums.append(contentsOf: unique)
            pageCount += 1
            nextURL = HomeParser.nextPageURL(html, current: url)
            hasMore = nextURL != nil
            loaded = true
            error = nil
        } catch let err {
            guard current == generation else { return }
            error = err.localizedDescription
        }
        if current == generation {
            isLoading = false
        }
    }
}

struct CategoryView: View {
    let title: String
    let appliesLanguageFilter: Bool
    @StateObject private var model: CategoryFeedModel
    @AppStorage("manga.languageFilter")
    private var languageFilter = MangaLanguageFilter.all.rawValue
    @State private var selectedAlbum: HomeAlbum?

    init(
        title: String,
        startURL: URL,
        appliesLanguageFilter: Bool = true
    ) {
        self.title = title
        self.appliesLanguageFilter = appliesLanguageFilter
        _model = StateObject(wrappedValue: CategoryFeedModel(startURL: startURL))
    }

    var body: some View {
        let albums = visibleAlbums
        let safe = windowSafeInsets
        CategoryGridView(
            albums: albums,
            isLoading: model.isLoading,
            hasMore: model.hasMore,
            topInset: safe.top + 44,
            bottomInset: safe.bottom + 56,
            onSelect: { selectedAlbum = $0 },
            onLoadMore: {
                Task { await model.loadMore() }
            },
            onRefresh: {
                await model.reload()
            }
        )
        .background(background)
        .ignoresSafeArea(edges: [.top, .bottom])
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .seamlessNavigationBar()
        .navigationDestination(item: $selectedAlbum) { album in
            AlbumDetailView(album: album)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                MangaFilterMenu()
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.isLoading)
            }
        }
        .task {
            await model.loadIfNeeded()
        }
        .overlay {
            if model.albums.isEmpty {
                if model.isLoading {
                    ProgressView("正在加载…")
                } else if let error = model.error {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("重试") {
                            Task { await model.reload() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.mint)
                        .foregroundStyle(.black)
                    }
                    .padding()
                } else {
                    ContentUnavailableView(
                        "没有找到作品",
                        systemImage: "magnifyingglass",
                        description: Text("换个关键词或分类试试")
                    )
                }
            } else if albums.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("本页没有符合筛选的作品")
                        .font(.subheadline)
                    Button("清除筛选") {
                        languageFilter = MangaLanguageFilter.all.rawValue
                    }
                    .buttonStyle(.bordered)
                    .tint(.mint)
                }
            }
        }
    }

    private var selectedLanguage: MangaLanguageFilter {
        guard appliesLanguageFilter else { return .all }
        return MangaLanguageFilter(rawValue: languageFilter) ?? .all
    }

    private var windowSafeInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            if let window = scene.windows.first(where: \.isKeyWindow) {
                return window.safeAreaInsets
            }
        }
        return .zero
    }

    private var visibleAlbums: [HomeAlbum] {
        guard selectedLanguage != .all else { return model.albums }
        return model.albums.filter { album in
            album.matches(language: selectedLanguage)
        }
    }

    private var background: some View {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
    }
}

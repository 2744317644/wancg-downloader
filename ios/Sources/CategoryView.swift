import SwiftUI
import UIKit

// MARK: - Feed model

@MainActor
final class CategoryFeedModel: ObservableObject {
    @Published private(set) var albums: [HomeAlbum] = []
    @Published private(set) var visibleAlbums: [HomeAlbum] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var hasMore = true
    @Published private(set) var didLoadOnce = false
    @Published private(set) var loadedPageCount = 0

    private let startURL: URL
    private var nextURL: URL?
    /// Last successfully fetched site page; used as Referer for the next one.
    private var currentPageURL: URL?
    private var client: WnacgClient?
    private var generation = 0
    private var loadedAids = Set<String>()
    private var filterLanguage: MangaLanguageFilter = .all
    private var filterHideAI = false
    private var lastLoadFinishedAt: Date?
    private var recoveryTask: Task<Void, Never>?
    private var recoveryAttempts = 0

    /// Pages are fetched one at a time; a minimum gap keeps rapid scroll
    /// events from firing a burst of requests at the site (which answers with
    /// HTTP 429 and made "load more" look permanently broken).
    private let minimumRequestInterval: TimeInterval = 0.7

    init(startURL: URL) {
        self.startURL = startURL
        self.nextURL = startURL
    }

    func loadInitial() async {
        guard !didLoadOnce else { return }
        await load(reset: true)
    }

    /// Replace the first site page without clearing the grid until the new
    /// data actually arrives, so pull-to-refresh never flashes an empty page.
    func refresh() async {
        await load(reset: true, force: true)
    }

    func loadMore() async {
        guard didLoadOnce, hasMore, !isLoading else { return }
        await throttleIfNeeded()
        guard !isLoading, hasMore else { return }
        await load(reset: false)
    }

    func setFilters(language: MangaLanguageFilter, hideAI: Bool) {
        guard language != filterLanguage || hideAI != filterHideAI else { return }
        filterLanguage = language
        filterHideAI = hideAI
        recomputeVisibleAlbums()
    }

    private func recomputeVisibleAlbums() {
        var result = albums
        if filterLanguage != .all {
            result = result.filter { $0.matches(language: filterLanguage) }
        }
        if filterHideAI {
            result = result.filter { !$0.isAI }
        }
        visibleAlbums = result
    }

    private func throttleIfNeeded() async {
        guard let last = lastLoadFinishedAt else { return }
        let elapsed = Date().timeIntervalSince(last)
        guard elapsed < minimumRequestInterval else { return }
        let wait = minimumRequestInterval - elapsed
        try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
    }

    private func load(reset: Bool, force: Bool = false) async {
        if isLoading && !force { return }
        recoveryTask?.cancel()
        recoveryTask = nil
        if reset {
            recoveryAttempts = 0
        }
        generation += 1
        let token = generation
        isLoading = true
        error = nil

        guard let url = reset ? startURL : nextURL else {
            hasMore = false
            isLoading = false
            lastLoadFinishedAt = Date()
            return
        }
        let referer = reset ? nil : (currentPageURL ?? startURL)

        do {
            if client == nil {
                client = try WnacgClient()
            }
            guard let client else {
                isLoading = false
                lastLoadFinishedAt = Date()
                return
            }
            let html = try await client.fetchHTML(url, referer: referer)
            guard token == generation else { return }

            // Regex parsing is CPU-bound; keep it off the main actor so the
            // append of a new page cannot block the frame mid-scroll.
            let parsedPage = await Task.detached(priority: .userInitiated) {
                (
                    cards: HomeParser.parseCards(html),
                    next: HomeParser.nextPageURL(html, current: url)
                )
            }.value
            guard token == generation else { return }
            let parsed = parsedPage.cards
            let next = parsedPage.next
            // Never keep a cursor that points back at the page we just read:
            // that made the sentinel spin on the same page forever.
            let usableNext = (next != nil && next != url) ? next : nil

            if reset {
                var seen = Set<String>()
                let unique = parsed.filter { seen.insert($0.aid).inserted }
                loadedAids = seen
                albums = unique
                loadedPageCount = 1
                currentPageURL = url
                nextURL = usableNext
                hasMore = usableNext != nil
            } else if parsed.isEmpty {
                // An empty 200 page means there is nothing usable further down.
                currentPageURL = url
                nextURL = nil
                hasMore = false
            } else {
                let fresh = parsed.filter { loadedAids.insert($0.aid).inserted }
                albums.append(contentsOf: fresh)
                loadedPageCount += 1
                currentPageURL = url
                nextURL = usableNext
                hasMore = usableNext != nil
            }

            didLoadOnce = true
            recoveryAttempts = 0
            recomputeVisibleAlbums()
        } catch let err {
            guard token == generation else { return }
            // Cancellation must still fall through to the isLoading reset —
            // an early return here would leave the feed permanently "busy".
            if !(err is CancellationError) {
                error = err.localizedDescription
                scheduleRecovery()
            }
        }

        lastLoadFinishedAt = Date()
        if token == generation {
            isLoading = false
        }
    }

    /// A transient network/429 failure used to stop the feed until the user
    /// manually refreshed. Retry up to twice with a short delay so a single
    /// hiccup heals itself while the user keeps browsing.
    private func scheduleRecovery() {
        recoveryTask?.cancel()
        guard recoveryAttempts < 2 else { return }
        recoveryAttempts += 1
        recoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.error != nil, self.hasMore, !self.isLoading else {
                return
            }
            // `load()` cancels `recoveryTask` on entry. If that task is still
            // `self`, it would cancel the recovery request itself (URLSession
            // -999), so detach it from the property before retrying.
            self.recoveryTask = nil
            self.error = nil
            await self.load(reset: false)
        }
    }
}

// MARK: - Screen

/// Second-level listing screen used by category pages ("同人志", "全部作品",
/// a home section's 更多) and by search results.
///
/// A single continuous, adaptive grid is the model here: the site's page
/// numbers are only a data cursor and never surface in the UI.
struct CategoryView: View {
    let title: String
    let appliesLanguageFilter: Bool

    @StateObject private var model: CategoryFeedModel
    @AppStorage("manga.languageFilter")
    private var languageFilter = MangaLanguageFilter.all.rawValue
    @AppStorage("content.hideAI") private var hideAI = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var isAutoFilling = false
    @State private var isRefreshing = false

    /// How many albums before the current end prefetching starts. Two rows on
    /// an iPhone: the next site page is normally in place before the user can
    /// see the final row, so that row is already filled with new covers
    /// instead of showing a single orphaned card above the footer.
    private static let prefetchDistance = 12

    private var columns: [GridItem] {
        let minimum: CGFloat = dynamicTypeSize.isAccessibilitySize ? 160 : 104
        let maximum: CGFloat = dynamicTypeSize.isAccessibilitySize ? 220 : 154
        return [
            GridItem(.adaptive(minimum: minimum, maximum: maximum), spacing: 10),
        ]
    }

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
        ScrollViewReader { proxy in
            ScrollView {
                // A plain VStack: the only lazy container needed here is the
                // grid itself. Nesting the grid inside a LazyVStack made every
                // appended page re-layout the whole lazy stack.
                VStack(spacing: 16) {
                    filterRow
                        .id("category-top")
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                isRefreshing = true
                await model.refresh()
                await fillFilteredPages(limit: 3)
                isRefreshing = false
            }
            .background(background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .seamlessNavigationBar()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { @MainActor in
                            isRefreshing = true
                            await model.refresh()
                            await fillFilteredPages(limit: 3)
                            isRefreshing = false
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isLoading)
                }
            }
            .onChange(of: languageFilter) { _, _ in
                handleFilterChange(proxy: proxy)
            }
            .onChange(of: hideAI) { _, _ in
                handleFilterChange(proxy: proxy)
            }
            .task {
                syncModelFilters()
                await model.loadInitial()
                await fillFilteredPages(limit: 2)
            }
        }
    }

    // MARK: Content states

    @ViewBuilder
    private var content: some View {
        if model.albums.isEmpty {
            if model.isLoading {
                skeletonGrid
            } else if let error = model.error {
                fullErrorState(error)
            } else if model.didLoadOnce {
                emptyState
            } else {
                skeletonGrid
            }
        } else if visibleAlbums.isEmpty {
            if isAutoFilling || model.isLoading {
                filteringState
            } else if let error = model.error {
                filteredErrorState(error)
            } else {
                filteredEmptyState
            }
        } else {
            albumGrid
            footer
        }
    }

    private var albumGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(
                Array(visibleAlbums.enumerated()),
                id: \.element.id
            ) { index, album in
                NavigationLink {
                    AlbumDetailView(album: album)
                } label: {
                    // `.equatable()` lets SwiftUI skip re-rendering the covers
                    // already on screen whenever a page is appended.
                    AlbumCardView(album: album).equatable()
                }
                .buttonStyle(AlbumCardButtonStyle())
                .onAppear {
                    // Prefetch when the last rows come into the lazy grid's
                    // render window. Unlike a sentinel in the outer VStack,
                    // these cells only appear when the user actually scrolls
                    // near the bottom — and they re-arm for every new page.
                    if index >= visibleAlbums.count - Self.prefetchDistance {
                        requestMore()
                    }
                }
            }

            if model.hasMore {
                // Lazy sentinel: lives *inside* the LazyVGrid (so it is only
                // created near the viewport), and gets a new identity after
                // every fetched page. That re-arms the automatic load without
                // the old problem of a non-lazy sentinel firing once at launch
                // or an immediately-retriggered `.id` chain.
                Color.clear
                    .frame(height: 1)
                    .accessibilityHidden(true)
                    .id("lazy-end-\(model.loadedPageCount)-\(model.albums.count)")
                    .onAppear { requestMore() }
            }
        }
        .padding(.top, 4)
    }

    private var skeletonGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(0..<12, id: \.self) { _ in
                AlbumSkeletonCard()
            }
        }
        .padding(.top, 4)
        .allowsHitTesting(false)
    }

    private var filteringState: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("正在筛选符合条件的内容…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text("没有符合筛选的作品")
                .font(.subheadline.weight(.semibold))
            Text("已加载的作品里没有匹配项，可以继续往后加载，或清除筛选")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            HStack(spacing: 10) {
                Button("清除筛选") {
                    UISelectionFeedbackGenerator().selectionChanged()
                    languageFilter = MangaLanguageFilter.all.rawValue
                    hideAI = false
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
                .foregroundStyle(.black)
                .controlSize(.large)

                if model.hasMore {
                    Button("继续加载") {
                        isAutoFilling = true
                        Task { @MainActor in
                            await fillFilteredPages(limit: 5)
                            isAutoFilling = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.mint)
                    .controlSize(.large)
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text("这个分类暂时没有作品")
                .font(.subheadline.weight(.semibold))
            Text("可以返回上一页看看其他分类")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func filteredErrorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.orange)
            Text("加载更多失败")
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 24)
            Button("重试") {
                requestMore(force: true)
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)
            .foregroundStyle(.black)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func fullErrorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.orange)
            Text("加载失败")
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("重试") {
                Task { @MainActor in
                    await model.refresh()
                    await fillFilteredPages(limit: 2)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)
            .foregroundStyle(.black)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }

    @ViewBuilder
    private var footer: some View {
        if model.isLoading && !isRefreshing {
            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(isAutoFilling ? "正在筛选…" : "正在加载更多…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("已加载 \(model.albums.count) 部")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("正在加载更多，已加载 \(model.albums.count) 部")
        } else if let error = model.error {
            Button {
                requestMore(force: true)
            } label: {
                VStack(spacing: 4) {
                    Label("加载失败，点击重试", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("加载失败，点击重试")
        } else if model.hasMore {
            Button {
                requestMore(force: true)
            } label: {
                VStack(spacing: 3) {
                    Label("加载更多", systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("已加载 \(model.albums.count) 部")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("load-more-button")
            .accessibilityLabel("加载更多，已加载 \(model.albums.count) 部")
        } else {
            Text("已经到底了 · 共 \(visibleAlbums.count) 部")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .accessibilityLabel("已经到底了，共 \(visibleAlbums.count) 部作品")
        }
    }

    // MARK: Filter chips

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if appliesLanguageFilter {
                    ForEach(MangaLanguageFilter.allCases) { filter in
                        languagePill(filter)
                    }
                }
                aiPill
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func languagePill(_ filter: MangaLanguageFilter) -> some View {
        let selected = selectedLanguage == filter
        return Button {
            guard languageFilter != filter.rawValue else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            languageFilter = filter.rawValue
        } label: {
            HStack(spacing: 4) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                }
                Text(filter.title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(selected ? Color.black : Color.primary.opacity(0.82))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                selected ? Color.mint : Color.primary.opacity(0.06),
                in: Capsule()
            )
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var aiPill: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            hideAI.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: hideAI ? "checkmark" : "sparkles")
                    .font(.system(size: 9, weight: .bold))
                Text("屏蔽 AI")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(hideAI ? Color.black : Color.primary.opacity(0.82))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                hideAI ? Color.mint : Color.primary.opacity(0.06),
                in: Capsule()
            )
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(hideAI ? .isSelected : [])
    }

    // MARK: Helpers

    private func handleFilterChange(proxy: ScrollViewProxy) {
        syncModelFilters()
        Task { @MainActor in
            await fillFilteredPages(limit: 6)
            scrollToTop(proxy: proxy)
        }
    }

    private func syncModelFilters() {
        model.setFilters(language: selectedLanguage, hideAI: hideAI)
    }

    private func scrollToTop(proxy: ScrollViewProxy) {
        guard appliesLanguageFilter || !visibleAlbums.isEmpty else { return }
        if reduceMotion {
            proxy.scrollTo("category-top", anchor: .top)
        } else {
            withAnimation(.snappy(duration: 0.32)) {
                proxy.scrollTo("category-top", anchor: .top)
            }
        }
    }

    private func requestMore(force: Bool = false) {
        guard !isAutoFilling else { return }
        guard model.hasMore, !model.isLoading else { return }
        if !force, model.error != nil { return }
        Task { await model.loadMore() }
    }

    /// Client-side filters can hide a whole fetched page. Keep pulling site
    /// pages (bounded) until at least one match shows up, so the screen never
    /// presents a false "empty result".
    private func fillFilteredPages(limit: Int) async {
        var attempts = 0
        while visibleAlbums.isEmpty,
              model.hasMore,
              model.error == nil,
              attempts < limit {
            await model.loadMore()
            attempts += 1
        }
    }

    // MARK: Derived state

    private var selectedLanguage: MangaLanguageFilter {
        guard appliesLanguageFilter else { return .all }
        return MangaLanguageFilter(rawValue: languageFilter) ?? .all
    }

    private var visibleAlbums: [HomeAlbum] {
        model.visibleAlbums
    }

    private var background: some View {
        AppBackground()
    }
}



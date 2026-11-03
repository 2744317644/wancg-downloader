import SwiftUI
import UIKit

// MARK: - Feed model

@MainActor
final class CategoryFeedModel: ObservableObject {
    @Published private(set) var albums: [HomeAlbum] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var hasMore = true
    @Published private(set) var didLoadOnce = false
    @Published private(set) var loadedPageCount = 0

    private let startURL: URL
    private var nextURL: URL?
    private var client: WnacgClient?
    private var generation = 0
    private var loadedAids = Set<String>()

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
        await load(reset: false)
    }

    private func load(reset: Bool, force: Bool = false) async {
        if isLoading && !force { return }
        generation += 1
        let token = generation
        isLoading = true
        error = nil

        let url = reset ? startURL : nextURL
        guard let url else {
            hasMore = false
            isLoading = false
            return
        }

        do {
            if client == nil {
                client = try WnacgClient()
            }
            guard let client else {
                isLoading = false
                return
            }
            let html = try await client.fetchHTML(url)
            guard token == generation else { return }

            let parsed = HomeParser.parseCards(html)
            let next = HomeParser.nextPageURL(html, current: url)

            if reset {
                var seen = Set<String>()
                let unique = parsed.filter { seen.insert($0.aid).inserted }
                loadedAids = seen
                albums = unique
                loadedPageCount = 1
            } else {
                let fresh = parsed.filter { loadedAids.insert($0.aid).inserted }
                albums.append(contentsOf: fresh)
                loadedPageCount += 1
            }

            nextURL = next
            hasMore = next != nil
            didLoadOnce = true
        } catch let err {
            guard token == generation else { return }
            if err is CancellationError { return }
            error = err.localizedDescription
        }

        if token == generation {
            isLoading = false
        }
    }
}

// MARK: - Screen

/// Second-level listing screen used by category pages ("同人志", "全部作品",
/// a home section's 更多) and by search results.
///
/// A single continuous, adaptive grid is the model here: the site's page
/// numbers are only a data cursor and never surface in the UI. That removes
/// the whole class of bugs the old "9 items per page + floating pager" design
/// kept producing (wrong page counters, tiny 32pt arrows, a second bottom bar
/// stacked on the native tab bar, empty pages after filtering, …).
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
                LazyVStack(spacing: 16) {
                    if appliesLanguageFilter {
                        filterRow(proxy: proxy)
                    }
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
            .task {
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
            ForEach(visibleAlbums) { album in
                NavigationLink {
                    AlbumDetailView(album: album)
                } label: {
                    AlbumCardView(album: album)
                }
                .buttonStyle(AlbumCardButtonStyle())
                .onAppear {
                    if album.id == visibleAlbums.last?.id {
                        requestMore()
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var skeletonGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(0..<12, id: \.self) { _ in
                SkeletonAlbumCard()
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
                    Task { @MainActor in
                        await fillFilteredPages(limit: 2)
                    }
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
                Task { @MainActor in
                    await fillFilteredPages(limit: 3)
                }
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
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(isAutoFilling ? "正在筛选…" : "正在加载更多…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .accessibilityLabel("正在加载更多")
        } else if let error = model.error {
            Button {
                requestMore(force: true)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.exclamationmark")
                    Text("加载失败，点击重试")
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("加载失败，点击重试")
        } else if !model.hasMore {
            Text("已经到底了 · 共 \(visibleAlbums.count) 部")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .accessibilityLabel("已经到底了，共 \(visibleAlbums.count) 部作品")
        } else {
            Color.clear.frame(height: 20)
        }
    }

    // MARK: Filter chips

    private func filterRow(proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MangaLanguageFilter.allCases) { filter in
                    languagePill(filter, proxy: proxy)
                }
                aiPill(proxy: proxy)
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func languagePill(
        _ filter: MangaLanguageFilter,
        proxy: ScrollViewProxy
    ) -> some View {
        let selected = selectedLanguage == filter
        return Button {
            guard languageFilter != filter.rawValue else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            languageFilter = filter.rawValue
            applyFilterChange(proxy: proxy)
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
            .contentShape(Capsule())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func aiPill(proxy: ScrollViewProxy) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            hideAI.toggle()
            applyFilterChange(proxy: proxy)
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
            .contentShape(Capsule())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(hideAI ? .isSelected : [])
    }

    // MARK: Helpers

    private func applyFilterChange(proxy: ScrollViewProxy) {
        Task { @MainActor in
            await fillFilteredPages(limit: 6)
            scrollToTop(proxy: proxy)
        }
    }

    private func scrollToTop(proxy: ScrollViewProxy) {
        guard let first = visibleAlbums.first else { return }
        if reduceMotion {
            proxy.scrollTo(first.id, anchor: .top)
        } else {
            withAnimation(.snappy(duration: 0.32)) {
                proxy.scrollTo(first.id, anchor: .top)
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
        let languageFiltered: [HomeAlbum]
        if selectedLanguage == .all {
            languageFiltered = model.albums
        } else {
            languageFiltered = model.albums.filter {
                $0.matches(language: selectedLanguage)
            }
        }
        guard hideAI else { return languageFiltered }
        return languageFiltered.filter { !$0.isAI }
    }

    private var background: some View {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
    }
}

// MARK: - Supporting views

private struct SkeletonAlbumCard: View {
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

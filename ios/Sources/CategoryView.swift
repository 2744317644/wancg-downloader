import SwiftUI
import UIKit

@MainActor
final class CategoryFeedModel: ObservableObject {
    @Published private(set) var albums: [HomeAlbum] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var hasMore = true
    @Published private(set) var pageCount = 0
    @Published private(set) var resetGeneration = 0

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
            resetGeneration += 1
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
    @AppStorage("content.hideAI") private var hideAI = false
    @State private var selectedAlbum: HomeAlbum?
    @State private var currentPage = 0
    @State private var isLoadingPage = false
    @State private var showJump = false
    @State private var jumpText = ""
    private let pageSize = 9

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: 3
    )

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
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(pageItems) { album in
                    NavigationLink {
                        AlbumDetailView(album: album)
                    } label: {
                        AlbumCardView(album: album)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .scrollIndicators(.hidden)
        .id(currentPage)
        .background(background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .seamlessNavigationBar()
        .navigationDestination(item: $selectedAlbum) { album in
            AlbumDetailView(album: album)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !visibleAlbums.isEmpty {
                floatingBar
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                MangaFilterMenu()
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.isLoading || isLoadingPage)
            }
        }
        .task {
            await loadFirstPage()
        }
        .onChange(of: languageFilter) { _, _ in
            resetToFirstPage()
        }
        .onChange(of: hideAI) { _, _ in
            resetToFirstPage()
        }
        .alert("跳转到页", isPresented: $showJump) {
            TextField("页码", text: $jumpText)
                .keyboardType(.numberPad)
            Button("取消", role: .cancel) {}
            Button("跳转") {
                jumpToPage()
            }
        } message: {
            Text("当前第 \(currentPage + 1) 页，已加载 \(loadedPageCount) 页")
        }
        .overlay {
            if visibleAlbums.isEmpty {
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
                            Task { await reload() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.mint)
                        .foregroundStyle(.black)
                    }
                    .padding()
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("本页没有符合筛选的作品")
                            .font(.subheadline)
                        Button("清除筛选") {
                            languageFilter = MangaLanguageFilter.all.rawValue
                            hideAI = false
                        }
                        .buttonStyle(.bordered)
                        .tint(.mint)
                    }
                }
            }
        }
    }

    private var pageItems: [HomeAlbum] {
        let start = currentPage * pageSize
        guard start < visibleAlbums.count else { return [] }
        let end = min(start + pageSize, visibleAlbums.count)
        return Array(visibleAlbums[start..<end])
    }

    private var loadedPageCount: Int {
        max(1, (visibleAlbums.count + pageSize - 1) / pageSize)
    }

    private var canGoNext: Bool {
        visibleAlbums.count > (currentPage + 1) * pageSize || model.hasMore
    }

    private var floatingBar: some View {
        HStack(spacing: 14) {
            Button {
                goToPage(currentPage - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .disabled(currentPage == 0 || isLoadingPage)
            .opacity(currentPage == 0 || isLoadingPage ? 0.35 : 1)

            if isLoadingPage {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 64, height: 32)
            } else {
                Button {
                    jumpText = "\(currentPage + 1)"
                    showJump = true
                } label: {
                    Text("\(currentPage + 1) / \(loadedPageCount)")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .frame(minWidth: 64, minHeight: 32)
                }
            }

            Button {
                goToPage(currentPage + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .disabled(!canGoNext || isLoadingPage)
            .opacity(!canGoNext || isLoadingPage ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 7)
        .background(Color(uiColor: .systemGroupedBackground))
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {}
        }
    }

    private func loadFirstPage() async {
        guard !isLoadingPage else { return }
        isLoadingPage = true
        await model.loadIfNeeded()
        await fillPage(0)
        isLoadingPage = false
    }

    private func resetToFirstPage() {
        currentPage = 0
        Task {
            guard !isLoadingPage else { return }
            isLoadingPage = true
            await fillPage(0)
            isLoadingPage = false
        }
    }

    private func reload() async {
        isLoadingPage = true
        currentPage = 0
        await model.reload()
        await fillPage(0)
        isLoadingPage = false
    }

    private func goToPage(_ page: Int) {
        guard page >= 0, !isLoadingPage else { return }
        let pageEnd = (page + 1) * pageSize
        let hasEnoughForPage = visibleAlbums.count >= pageEnd
            || !model.hasMore
        if page * pageSize < visibleAlbums.count,
           hasEnoughForPage {
            withAnimation(.easeInOut(duration: 0.18)) {
                currentPage = page
            }
            return
        }
        Task {
            isLoadingPage = true
            await fillPage(page)
            if visibleAlbums.count > page * pageSize {
                withAnimation(.easeInOut(duration: 0.18)) {
                    currentPage = page
                }
            }
            isLoadingPage = false
        }
    }

    private func jumpToPage() {
        guard let value = Int(jumpText), value > 0 else { return }
        goToPage(value - 1)
    }

    private func fillPage(_ page: Int) async {
        let target = (page + 1) * pageSize
        var attempts = 0
        while visibleAlbums.count < target,
              model.hasMore,
              !model.isLoading,
              attempts < 20 {
            let before = visibleAlbums.count
            await model.loadMore()
            attempts += 1
            if visibleAlbums.count == before { break }
        }
    }

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

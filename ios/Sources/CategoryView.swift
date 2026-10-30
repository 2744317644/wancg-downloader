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
        await load(reset: true)
    }

    func loadMore() async {
        guard loaded, hasMore, !isLoading else { return }
        await load(reset: false)
    }

    private func load(reset: Bool) async {
        guard !isLoading else { return }
        if reset {
            albums = []
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
            let newAlbums = HomeParser.parseCards(html)
            let existing = Set(albums.map(\.aid))
            albums.append(contentsOf: newAlbums.filter {
                !existing.contains($0.aid)
            })
            pageCount += 1
            nextURL = HomeParser.nextPageURL(html, current: url)
            hasMore = nextURL != nil
            loaded = true
            error = nil
        } catch let err {
            error = err.localizedDescription
        }
        isLoading = false
    }
}

struct CategoryView: View {
    let title: String
    @StateObject private var model: CategoryFeedModel

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: 3
    )

    init(title: String, startURL: URL) {
        self.title = title
        _model = StateObject(wrappedValue: CategoryFeedModel(startURL: startURL))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if !model.albums.isEmpty {
                    HStack {
                        Text("\(model.albums.count) 部作品")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if model.pageCount > 0 {
                            Text("第 \(model.pageCount) 页")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(model.albums) { album in
                        NavigationLink {
                            AlbumDetailView(album: album)
                        } label: {
                            AlbumCardView(album: album)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if album.aid == model.albums.last?.aid {
                                Task { await model.loadMore() }
                            }
                        }
                    }
                }

                footer
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.isLoading)
            }
        }
        .refreshable {
            await model.reload()
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
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if !model.albums.isEmpty {
            HStack {
                Spacer()
                if model.isLoading {
                    ProgressView()
                } else if model.hasMore {
                    Text("继续下滑加载更多")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("已经到底了")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.top, 8)
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.06, blue: 0.10),
                Color(red: 0.02, green: 0.03, blue: 0.06),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

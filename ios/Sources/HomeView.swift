import SwiftUI
import UIKit

@MainActor
final class HomeFeedModel: ObservableObject {
    @Published var sections: [HomeSection] = []
    @Published var isLoading = false
    @Published var error: String?

    private var client: WnacgClient?
    private var loaded = false

    func load(force: Bool = false) async {
        if isLoading || (loaded && !force) { return }
        isLoading = true
        error = nil
        do {
            let client = try WnacgClient()
            self.client = client
            let html = try await client.fetchHTML(
                URL(string: "https://www.wnacg.com/")!
            )
            sections = HomeParser.parse(html)
            loaded = true
            if sections.isEmpty {
                error = "首页没有解析到作品，可能站点结构变了"
            }
        } catch let err {
            error = err.localizedDescription
        }
        isLoading = false
    }
}

@MainActor
final class CoverImageStore {
    static let shared = CoverImageStore()

    private let cache = NSCache<NSURL, UIImage>()
    private var client: WnacgClient?

    private init() {
        cache.countLimit = 120
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

struct HomeView: View {
    let onSelect: (HomeAlbum) -> Void

    @StateObject private var model = HomeFeedModel()

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: 3
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    hero

                    if model.sections.isEmpty && model.isLoading {
                        loadingView
                    } else if let error = model.error, model.sections.isEmpty {
                        errorView(error)
                    } else {
                        categoryChips
                        ForEach(model.sections) { section in
                            sectionView(section)
                        }
                        footer
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(background)
            .navigationTitle("发现")
            .navigationBarTitleDisplayMode(.large)
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

    private var hero: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.mint, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.black.opacity(0.75))
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text("绅士漫画")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("最新上架 · 同人志 · 单行本")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                NavigationLink {
                    CategoryView(
                        title: "全部作品",
                        startURL: URL(string: "https://www.wnacg.com/albums.html")!,
                        onSelect: onSelect
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
                                startURL: moreURL,
                                onSelect: onSelect
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
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1)
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
                    .foregroundStyle(.white)
                Spacer()
                if let moreURL = section.moreURL {
                    NavigationLink {
                        CategoryView(
                            title: section.title,
                            startURL: moreURL,
                            onSelect: onSelect
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

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(section.albums) { album in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSelect(album)
                    } label: {
                        AlbumCardView(album: album)
                    }
                    .buttonStyle(.plain)
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
        Text("内容来自绅士漫画 · 仅供个人备份")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
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

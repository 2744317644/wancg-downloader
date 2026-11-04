import SwiftUI
import UIKit

@MainActor
final class AlbumDetailModel: ObservableObject {
    let album: HomeAlbum
    @Published var preview: MangaPreview?
    @Published var isLoading = true
    @Published var error: String?

    private var client: WnacgClient?
    private var loaded = false

    init(album: HomeAlbum) {
        self.album = album
    }

    func load() async {
        guard !loaded else { return }
        isLoading = true
        error = nil
        do {
            let client = try WnacgClient()
            self.client = client
            preview = try await client.preview(for: album.aid)
            error = nil
            loaded = true
        } catch let err {
            error = err.localizedDescription
        }
        isLoading = false
    }
}

struct AlbumDetailView: View {
    let album: HomeAlbum

    @EnvironmentObject private var downloadModel: AppModel
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var downloads: DownloadHistory
    @EnvironmentObject private var history: HistoryStore
    @State private var showAlreadyDownloaded = false
    @State private var didCopyTitle = false
    @State private var downloadStartedHere = false
    @State private var showReader = false
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("content.hideAI") private var hideAI = false
    @StateObject private var model: AlbumDetailModel

    init(album: HomeAlbum) {
        self.album = album
        _model = StateObject(wrappedValue: AlbumDetailModel(album: album))
    }

    private var displayTitle: String {
        model.preview?.title ?? album.title
    }

    private var tags: [String] {
        model.preview?.tags ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                actionButtons
                if !tags.isEmpty { tagGrid }
                downloadStatus
                queueBanner
                recommendationsSection
                if let error = model.error, !model.isLoading {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("详情加载失败")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button("重试") {
                            Task { await model.load() }
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(
                        cornerRadius: 12, style: .continuous
                    ))
                }
                if model.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在加载详情…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
        }
        .background(background)
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
        .seamlessNavigationBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    favorites.toggle(album: album, preview: model.preview)
                } label: {
                    Image(systemName: favorites.isFavorite(album.aid)
                        ? "heart.fill" : "heart")
                }
                .tint(.pink)
            }
        }
        .task {
            await model.load()
            history.record(album: album, preview: model.preview)
        }
        .alert("已经下载过", isPresented: $showAlreadyDownloaded) {
            Button("取消", role: .cancel) {}
            Button("重新下载", role: .destructive) {
                performDownload()
            }
        } message: {
            Text("《\(displayTitle)》已经下载过。重新下载会覆盖同名文件。")
        }
        // Present the reader as a full-screen cover instead of a navigation
        // push. The push had to hide the native tab bar (`.toolbar(.hidden,
        // for: .tabBar)`), and dismissing it animated the floating tab bar
        // back in a beat later. With a cover the tab bar is never hidden or
        // re-shown, so it is simply already there when the reader closes.
        .fullScreenCover(isPresented: $showReader) {
            NavigationStack {
                ReaderView(aid: album.aid, title: displayTitle)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            HomeCover(album: album)
                .frame(width: 140, height: 187)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 8) {
                    Text(displayTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .contextMenu {
                            Button {
                                copyTitle()
                            } label: {
                                Label("复制标题", systemImage: "doc.on.doc")
                            }
                        }

                    Button {
                        copyTitle()
                    } label: {
                        Image(systemName: didCopyTitle
                            ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(didCopyTitle ? Color.mint : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("复制标题")
                }

                if let category = model.preview?.category, !category.isEmpty {
                    Text(category)
                        .font(.caption)
                        .foregroundStyle(.mint)
                }

                infoLine(
                    "doc.text", "\(model.preview?.pages ?? album.pages ?? 0) 页"
                )
                if let favorites = model.preview?.favorites {
                    infoLine("heart", "\(favorites)")
                }
                if let uploader = model.preview?.uploader, !uploader.isEmpty {
                    infoLine("person", uploader)
                }
                if let uploaded = model.preview?.uploaded, !uploaded.isEmpty {
                    infoLine("calendar", uploaded)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func copyTitle() {
        UIPasteboard.general.string = displayTitle
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        didCopyTitle = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopyTitle = false
        }
    }

    private func infoLine(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
    }

    private var isActiveDownload: Bool {
        downloadModel.isDownloading(album.aid)
    }

    private var isQueued: Bool {
        downloadModel.isQueued(album.aid)
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                showReader = true
            } label: {
                Label("开始阅读", systemImage: "book.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(.ultraThinMaterial, in: RoundedRectangle(
                        cornerRadius: 13, style: .continuous
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button(action: startDownload) {
                HStack(spacing: 8) {
                    if isActiveDownload {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Image(systemName: isQueued
                            ? "clock" : "arrow.down.circle.fill")
                    }
                    Text(downloadButtonTitle)
                        .font(.subheadline.bold())
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(.mint, in: RoundedRectangle(
                    cornerRadius: 13, style: .continuous
                ))
            }
            .buttonStyle(.plain)
            .disabled(isActiveDownload || isQueued)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                favorites.toggle(album: album, preview: model.preview)
            } label: {
                Label(
                    favorites.isFavorite(album.aid) ? "已收藏" : "收藏",
                    systemImage: favorites.isFavorite(album.aid)
                        ? "heart.fill" : "heart"
                )
                .font(.subheadline)
                .foregroundStyle(
                    favorites.isFavorite(album.aid) ? Color.pink : Color.primary
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func tagChip(_ tag: String) -> some View {
        Text(tag)
            .font(.caption2)
            .foregroundStyle(Color.primary.opacity(0.85))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private var tagGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("标签")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 68), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(tags, id: \.self) { tag in
                    if let searchURL = HomeParser.searchURL(tag) {
                        NavigationLink {
                            CategoryView(
                                title: "标签：\(tag)",
                                startURL: searchURL
                            )
                        } label: {
                            tagChip(tag)
                        }
                        .buttonStyle(.plain)
                    } else {
                        tagChip(tag)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var queueBanner: some View {
        if let position = downloadModel.queuePosition(album.aid) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text("已加入下载队列，第 \(position) 位")
            }
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(
                cornerRadius: 10, style: .continuous
            ))
        }
    }

    private var downloadButtonTitle: String {
        if isActiveDownload { return "下载中…" }
        if let position = downloadModel.queuePosition(album.aid) {
            return "已加入队列（第 \(position) 位）"
        }
        if downloadModel.hasActiveDownload {
            return "加入下载队列"
        }
        return downloads.isDownloaded(album.aid)
            ? "重新下载 ZIP + PDF" : "下载 ZIP + PDF"
    }

    @ViewBuilder
    private var downloadStatus: some View {
        if (downloadStartedHere || downloadModel.isDownloading(album.aid))
            && downloadModel.input == album.pageURL.absoluteString
            && (downloadModel.isBusy || downloadModel.zipURL != nil
                || downloadModel.pdfURL != nil || downloadModel.errorMessage != nil) {
            VStack(alignment: .leading, spacing: 8) {
                if downloadModel.isBusy {
                    ProgressView(value: downloadModel.downloadProgress)
                        .tint(.mint)
                }
                Text(downloadModel.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let error = downloadModel.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)

                    if !downloadModel.isBusy {
                        Button {
                            Task { await downloadModel.retryCurrentDownload() }
                        } label: {
                            Label("重试下载", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                }

                HStack(spacing: 14) {
                    if let zip = downloadModel.zipURL {
                        ShareLink(item: zip) {
                            Label("分享 ZIP", systemImage: "square.and.arrow.up")
                        }
                    }
                    if let pdf = downloadModel.pdfURL {
                        ShareLink(item: pdf) {
                            Label("分享 PDF", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.mint)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(
                cornerRadius: 12, style: .continuous
            ))
        }
    }

    @ViewBuilder
    private var recommendationsSection: some View {
        let items = (model.preview?.recommendations ?? [])
            .filter { $0.aid != album.aid && (!hideAI || !$0.isAI) }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("看过这本的人也看了")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in
                            NavigationLink {
                                AlbumDetailView(album: item)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HomeCover(album: item)
                                        .frame(width: 112, height: 149)
                                    Text(item.title)
                                        .font(.caption2)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .frame(width: 112, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.top, 4)
        }
    }

    private func startDownload() {
        guard !isActiveDownload, !isQueued else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if downloads.isDownloaded(album.aid)
            || downloads.hasDownloadedFile(matching: displayTitle) {
            showAlreadyDownloaded = true
        } else {
            performDownload()
        }
    }

    private func performDownload() {
        downloadStartedHere = true
        downloadModel.enqueue(album: album)
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

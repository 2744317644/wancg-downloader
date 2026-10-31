import SwiftUI
import UIKit

struct FavoritesView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var downloads: DownloadHistory
    @State private var exportURL: URL?
    @State private var showExport = false

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: 3
    )

    private var downloaded: [FavoriteManga] {
        favorites.items.filter { downloads.isDownloaded($0.aid) }
    }

    private var pending: [FavoriteManga] {
        favorites.items.filter { !downloads.isDownloaded($0.aid) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if favorites.items.isEmpty {
                    ContentUnavailableView(
                        "还没有收藏",
                        systemImage: "heart",
                        description: Text("在漫画详情页点“收藏”，就会出现在这里")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            section(
                                title: "已下载",
                                subtitle: "文件删除后仍保留已下载记录",
                                systemImage: "checkmark.circle.fill",
                                color: .mint,
                                items: downloaded
                            )

                            section(
                                title: "未下载",
                                subtitle: "收藏了但还没下载过",
                                systemImage: "arrow.down.circle",
                                color: .orange,
                                items: pending
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            )
            .navigationTitle("收藏")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportFavorites()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(favorites.items.isEmpty)
                }
            }
            .sheet(isPresented: ) {
                if let exportURL {
                    FavoritesExportSheet(url: exportURL)
                }
            }
            .onAppear {
                downloads.reconcile(with: favorites.items)
            }
        }
    }

    private func exportFavorites() {
        guard let url = FavoritesExporter.write(
            items: favorites.items,
            downloadedAids: downloads.downloadedAids
        ) else { return }
        exportURL = url
        showExport = true
    }

    private func section(
        title: String,
        subtitle: String,
        systemImage: String,
        color: Color,
        items: [FavoriteManga]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
                Text("\(items.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if items.isEmpty {
                Text("暂无")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(items) { item in
                        favoriteCard(item)
                    }
                }
            }
        }
    }

    private func favoriteCard(_ item: FavoriteManga) -> some View {
        NavigationLink {
            AlbumDetailView(album: item.homeAlbum)
        } label: {
            ZStack(alignment: .topTrailing) {
                AlbumCardView(album: item.homeAlbum)

                if downloads.isDownloaded(item.aid) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white, .mint)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                favorites.remove(item)
            } label: {
                Label("取消收藏", systemImage: "heart.slash")
            }
        }
    }
}


private struct FavoritesExportSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Image(systemName: "doc.text")
                    .font(.system(size: 42))
                    .foregroundStyle(.mint)
                Text("收藏夹 HTML 已生成")
                    .font(.headline)
                Text("已下载和未下载会分别放在两个书签文件夹中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(url.lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                ShareLink(item: url) {
                    Label("分享 / 存储到文件", systemImage: "square.and.arrow.up")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
                .foregroundStyle(.black)
                .padding(.top, 6)
            }
            .padding(24)
            .navigationTitle("导出收藏夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

import SwiftUI
import UIKit

struct FavoritesView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var downloads: DownloadHistory

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
            .onAppear {
                downloads.reconcile(with: favorites.items)
            }
        }
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

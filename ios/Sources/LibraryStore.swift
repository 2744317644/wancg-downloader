import Foundation
import SwiftUI

struct FavoriteManga: Codable, Identifiable, Hashable {
    let aid: String
    let title: String
    let coverURL: String?
    let pageURL: String
    let pages: Int?
    let date: String
    let addedAt: Date

    var id: String { aid }

    var galleryURL: URL {
        URL(string: pageURL)
            ?? URL(string: "https://www.wnacg.com/photos-index-aid-\(aid).html")!
    }

    var homeAlbum: HomeAlbum {
        HomeAlbum(
            aid: aid,
            title: title,
            coverURL: coverURL.flatMap(URL.init(string:)),
            info: pages.map { "\($0) 页" } ?? "",
            pages: pages,
            date: date,
            pageURL: galleryURL
        )
    }
}

@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    @Published private(set) var items: [FavoriteManga] = []

    private let key = "wnacg.favorites.v1"

    private init() {
        load()
    }

    func isFavorite(_ aid: String) -> Bool {
        items.contains { $0.aid == aid }
    }

    func toggle(album: HomeAlbum, preview: MangaPreview?) {
        if let index = items.firstIndex(where: { $0.aid == album.aid }) {
            items.remove(at: index)
        } else {
            let title = preview?.title ?? album.title
            let cover = (preview?.coverURL ?? album.coverURL)?.absoluteString
            let pageURL = (preview?.pageURL ?? album.pageURL).absoluteString
            let pages = preview?.pages ?? album.pages
            let item = FavoriteManga(
                aid: album.aid,
                title: title,
                coverURL: cover,
                pageURL: pageURL,
                pages: pages,
                date: album.date,
                addedAt: Date()
            )
            items.insert(item, at: 0)
        }
        save()
    }

    func remove(_ item: FavoriteManga) {
        items.removeAll { $0.aid == item.aid }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return
        }
        do {
            items = try JSONDecoder().decode(
                [FavoriteManga].self, from: data
            )
        } catch {
            UserDefaults.standard.set(data, forKey: key + ".backup")
            items = []
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

@MainActor
final class DownloadHistory: ObservableObject {
    static let shared = DownloadHistory()

    @Published private(set) var downloadedAids: Set<String> = []

    private let key = "wnacg.downloaded.v1"

    private init() {
        load()
    }

    func isDownloaded(_ aid: String) -> Bool {
        downloadedAids.contains(aid)
    }

    private func normalizedTitle(_ title: String) -> String {
        HTMLParser.safeFilename(title).lowercased()
    }

    private func file(_ url: URL, matches title: String) -> Bool {
        let name = normalizedTitle(title)
        guard !name.isEmpty else { return false }
        let ext = url.pathExtension.lowercased()
        guard ext == "zip" || ext == "pdf" else { return false }
        return url.deletingPathExtension().lastPathComponent
            .lowercased() == name
    }

    func hasDownloadedFile(matching title: String) -> Bool {
        guard !title.isEmpty else { return false }
        let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }
        return files.contains { file($0, matches: title) }
    }

    func markDownloaded(_ aid: String) {
        guard !aid.isEmpty, !downloadedAids.contains(aid) else { return }
        downloadedAids.insert(aid)
        save()
    }

    /// 老版本下载过的文件没有历史记录，按标题匹配一次本地 ZIP/PDF。
    func reconcile(with favorites: [FavoriteManga]) {
        guard !favorites.isEmpty else { return }
        let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        var changed = false
        for favorite in favorites where !downloadedAids.contains(favorite.aid) {
            if files.contains(where: { file($0, matches: favorite.title) }) {
                downloadedAids.insert(favorite.aid)
                changed = true
            }
        }
        if changed { save() }
    }

    private func load() {
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        downloadedAids = Set(saved)
    }

    private func save() {
        UserDefaults.standard.set(
            Array(downloadedAids), forKey: key
        )
    }
}

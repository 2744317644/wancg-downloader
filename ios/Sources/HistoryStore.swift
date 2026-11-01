import Foundation
import SwiftUI

struct HistoryEntry: Codable, Identifiable, Hashable {
    let aid: String
    let title: String
    let coverURL: String?
    let pageURL: String
    let pages: Int?
    let date: String
    let viewedAt: Date

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
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var items: [HistoryEntry] = []

    private let key = "wnacg.history.v1"
    private let maximumCount = 200

    private init() {
        load()
    }

    /// 只有进入详情页才会调用，列表浏览不记录。
    func record(album: HomeAlbum, preview: MangaPreview?) {
        let entry = HistoryEntry(
            aid: album.aid,
            title: preview?.title ?? album.title,
            coverURL: (preview?.coverURL ?? album.coverURL)?.absoluteString,
            pageURL: (preview?.pageURL ?? album.pageURL).absoluteString,
            pages: preview?.pages ?? album.pages,
            date: album.date,
            viewedAt: Date()
        )
        items.removeAll { $0.aid == album.aid }
        items.insert(entry, at: 0)
        if items.count > maximumCount {
            items = Array(items.prefix(maximumCount))
        }
        save()
    }

    func remove(_ entry: HistoryEntry) {
        items.removeAll { $0.aid == entry.aid }
        save()
    }

    func remove(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where items.indices.contains(index) {
            items.remove(at: index)
        }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return
        }
        do {
            items = try JSONDecoder().decode(
                [HistoryEntry].self, from: data
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

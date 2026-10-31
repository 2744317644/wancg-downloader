import Foundation

struct QueuedDownload: Codable, Identifiable, Hashable {
    let aid: String
    let title: String
    let coverURL: String?
    let pageURL: String
    let pages: Int?
    let date: String
    let addedAt: Date

    var id: String { aid }

    init(album: HomeAlbum) {
        aid = album.aid
        title = album.title
        coverURL = album.coverURL?.absoluteString
        pageURL = album.pageURL.absoluteString
        pages = album.pages
        date = album.date
        addedAt = Date()
    }

    var homeAlbum: HomeAlbum {
        HomeAlbum(
            aid: aid,
            title: title,
            coverURL: coverURL.flatMap(URL.init(string:)),
            info: pages.map { "\($0) 页" } ?? "",
            pages: pages,
            date: date,
            pageURL: URL(string: pageURL)
                ?? URL(string: "https://www.wnacg.com/photos-index-aid-\(aid).html")!
        )
    }
}

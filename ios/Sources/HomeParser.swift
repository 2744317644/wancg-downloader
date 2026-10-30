import Foundation

struct HomeAlbum: Identifiable {
    let id = UUID()
    let aid: String
    let title: String
    let coverURL: URL?
    let info: String
    let pages: Int?
    let date: String
    let pageURL: URL
}

struct HomeSection: Identifiable {
    let id = UUID()
    let title: String
    let albums: [HomeAlbum]
    let moreURL: URL?
}

enum HomeParser {
    static let baseURL = URL(string: "https://www.wnacg.com/")!

    static func parse(_ html: String) -> [HomeSection] {
        let blocks = HTMLParser.blocks(
            "<div class=\"imgBox\">(.*?)(?=<div class=\"(?:imgBox|sh)\">|</body>)",
            in: html
        )
        var sections: [HomeSection] = []

        for block in blocks {
            guard let title = HTMLParser.first(
                "<span class=\"Title\">(.*?)</span>", in: block
            ).map(HTMLParser.clean), !title.isEmpty else {
                continue
            }

            let albums = parseCards(block)
            if albums.isEmpty { continue }

            let moreRaw = HTMLParser.first(
                "<div class=\"Sub_H2\"[^>]*>.*?<a href=\"([^\"]+)\"",
                in: block
            )
            let moreURL = moreRaw.flatMap {
                URL(string: $0, relativeTo: baseURL)?.absoluteURL
            }

            sections.append(HomeSection(
                title: title,
                albums: albums,
                moreURL: moreURL
            ))
        }
        return sections
    }

    static func parseCards(_ html: String) -> [HomeAlbum] {
        var albums: [HomeAlbum] = []
        var seen = Set<String>()

        for card in HTMLParser.blocks("<li[^>]*>(.*?)</li>", in: html) {
            guard let href = HTMLParser.first(
                "href=\"(/photos-index-aid-(\\d+)\\.html)\"", in: card
            ), let aid = HTMLParser.first(
                "photos-index-aid-(\\d+)\\.html", in: href
            ) else {
                continue
            }
            guard !seen.contains(aid) else { continue }

            let title = HTMLParser.first(
                "<a class=\"txtA\"[^>]*>(.*?)</a>", in: card
            ).map(HTMLParser.clean) ?? ""
            if title.isEmpty { continue }

            let info = HTMLParser.first(
                "<span class=\"info\">(.*?)</span>", in: card
            ).map(HTMLParser.clean) ?? ""

            let coverRaw = HTMLParser.first(
                "<img[^>]+src=\"([^\"]+)\"", in: card
            )
            let coverURL = coverRaw.flatMap { raw -> URL? in
                URL(string: HTMLParser.encodedURLString(
                    HTMLParser.normalizeURL(raw)
                ))
            }

            let pages = HTMLParser.first("(\\d+)\\s*[張张]", in: info)
                .flatMap(Int.init)
            let date = HTMLParser.first(
                "(\\d{4}-\\d{2}-\\d{2})", in: info
            ) ?? ""

            let pageURL = URL(
                string: "https://www.wnacg.com/photos-index-aid-\(aid).html"
            )!
            albums.append(HomeAlbum(
                aid: aid,
                title: title,
                coverURL: coverURL,
                info: info,
                pages: pages,
                date: date,
                pageURL: pageURL
            ))
            seen.insert(aid)
        }
        return albums
    }

    static func nextPageURL(_ html: String, current: URL) -> URL? {
        guard let href = HTMLParser.first(
            "<span class=\"next\"><a href=\"([^\"]+)\"", in: html
        ) else {
            return nil
        }
        return URL(string: href, relativeTo: current)?.absoluteURL
    }
}

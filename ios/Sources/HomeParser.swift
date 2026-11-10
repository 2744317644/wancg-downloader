import Foundation

struct HomeAlbum: Identifiable, Hashable {
    var id: String { aid }
    let aid: String
    let title: String
    let coverURL: URL?
    let info: String
    let pages: Int?
    let date: String
    let pageURL: URL
    /// Classified once at parse time. The old computed properties re-ran the
    /// full title-marker scan (~100 `contains`) for every album on every view
    /// update, which is main-thread work that showed up as dropped frames
    /// while a page of 20 covers was being appended.
    let language: MangaLanguageFilter
    let isAI: Bool

    init(
        aid: String,
        title: String,
        coverURL: URL?,
        info: String,
        pages: Int?,
        date: String,
        pageURL: URL
    ) {
        self.aid = aid
        self.title = title
        self.coverURL = coverURL
        self.info = info
        self.pages = pages
        self.date = date
        self.pageURL = pageURL
        self.language = MangaLanguageFilter.detect(in: title)
        self.isAI = AIContentFilter.matches(title)
    }
}

struct HomeSection: Identifiable {
    var id: String { title }
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
        var seenTitles = Set<String>()
        let hiddenTitles: Set<String> = ["最新上架", "最新更新"]

        for block in blocks {
            guard let title = HTMLParser.first(
                "<span class=\"Title\">(.*?)</span>", in: block
            ).map(HTMLParser.clean), !title.isEmpty else {
                continue
            }
            // The homepage's "latest additions" rail is hidden in the app.
            guard !hiddenTitles.contains(title) else { continue }
            guard seenTitles.insert(title).inserted else { continue }

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

            // Some sections use `class="txtA hei"` (single-volume cards),
            // so the class match must accept extra class names. If the title
            // link is absent, use the cover alt text — never the info span,
            // which contains "2026-11-07, 24張圖片".
            let title = HTMLParser.first(
                "<a class=\"txtA[^\"]*\"[^>]*>(.*?)</a>", in: card
            ).map(HTMLParser.clean) ?? ""
            var fallbackTitle = title.isEmpty
                ? HTMLParser.first(
                    "<a class=\"ImgA[^\"]*\"[^>]*>.*?<span[^>]*>(.*?)</span>",
                    in: card
                ).map(HTMLParser.clean) ?? ""
                : title
            if fallbackTitle.isEmpty {
                // Last resort for cards where the title only exists as the
                // cover image's alt text.
                fallbackTitle = HTMLParser.first(
                    "<img[^>]+alt=\"([^\"]+)\"",
                    in: card
                ).map(HTMLParser.clean) ?? ""
            }
            if fallbackTitle.isEmpty { continue }
            let displayTitle = fallbackTitle

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
                title: displayTitle,
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

    static func parseRecommendations(_ html: String) -> [HomeAlbum] {
        let cards = HTMLParser.matches(
            "<a class=\"dv-rec-item\"[^>]*href=\"[^\"]+\"[^>]*>.*?</a>",
            in: html
        )
        var albums: [HomeAlbum] = []
        var seen = Set<String>()

        for card in cards {
            guard let href = HTMLParser.first(
                "href=\"([^\"]+)\"", in: card
            ), let aid = HTMLParser.first(
                "photos-index-aid-(\\d+)", in: href
            ), !seen.contains(aid) else {
                continue
            }

            let title = HTMLParser.first(
                "<p class=\"dv-rec-title\"[^>]*>(.*?)</p>", in: card
            ).map(HTMLParser.clean) ?? ""
            if title.isEmpty { continue }

            let coverRaw = HTMLParser.first(
                "<img[^>]+src=\"([^\"]+)\"", in: card
            )
            let coverURL = coverRaw.flatMap { raw -> URL? in
                URL(string: HTMLParser.encodedURLString(
                    HTMLParser.normalizeURL(raw)
                ))
            }
            let favorite = HTMLParser.first(
                "<span class=\"dv-rec-fav\"[^>]*>(.*?)</span>", in: card
            ).map(HTMLParser.clean) ?? ""

            albums.append(HomeAlbum(
                aid: aid,
                title: title,
                coverURL: coverURL,
                info: favorite,
                pages: nil,
                date: "",
                pageURL: URL(
                    string: "https://www.wnacg.com/photos-index-aid-\(aid).html"
                )!
            ))
            seen.insert(aid)
            if albums.count >= 12 { break }
        }
        return albums
    }

    static func nextPageURL(_ html: String, current: URL) -> URL? {
        if let href = HTMLParser.first(
            "<span class=\"next\"><a href=\"([^\"]+)\"", in: html
        ) {
            return URL(string: href, relativeTo: current)?.absoluteURL
        }
        if let href = HTMLParser.first(
            "<span class=\"thispage\">.*?</span>\\s*<a href=\"([^\"]+)\"",
            in: html
        ) {
            return URL(string: href, relativeTo: current)?.absoluteURL
        }
        return nil
    }

    static func tagURL(_ tag: String) -> URL? {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        guard let encoded = trimmed.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) else { return nil }
        return URL(string: "https://www.wnacg.com/albums-index-tag-\(encoded).html")
    }

    static func searchURL(_ query: String) -> URL? {
        var components = URLComponents(
            string: "https://www.wnacg.com/search/index.php"
        )!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "m", value: ""),
            URLQueryItem(name: "syn", value: "yes"),
            URLQueryItem(name: "f", value: "_all"),
            URLQueryItem(name: "s", value: "create_time_DESC"),
        ]
        return components.url
    }
}

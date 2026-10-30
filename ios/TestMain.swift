import Foundation

@main
struct ProxyCheck {
    static func main() async {
        do {
            let client = try WnacgClient()
            let preview = try await client.preview(for: "383877")
            print("TITLE=\(preview.title)")
            print("PAGES=\(preview.pages ?? -1)")
            let info = try await client.downloadInfo(reqID: preview.aid)
            print("ZIP=\(info.zipURL.absoluteString)")
            print("FILENAME=\(info.filename)")
            guard preview.pages != nil else {
                print("PARSE_FAIL=missing pages")
                exit(2)
            }
            guard preview.title != "未命名作品" else {
                print("PARSE_FAIL=missing title")
                exit(2)
            }
            guard preview.coverURL != nil else {
                print("PARSE_FAIL=missing cover")
                exit(2)
            }

            let sample = try await client.preview(for: "399500")
            let sampleInfo = try await client.downloadInfo(reqID: sample.aid)
            let downloaded = try await client.download(
                sampleInfo, referer: sample.pageURL
            ) { _ in }
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: downloaded.path
            )
            let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            print("DOWNLOAD=\(size)")
            guard size > 1_000_000 else {
                print("DOWNLOAD_FAIL=too small")
                exit(2)
            }

            let images = try ZipExtractor.extractImages(from: downloaded)
            print("IMAGES=\(images.count)")
            if let first = images.first {
                try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            }
            try? FileManager.default.removeItem(at: downloaded)
            guard images.count > 10 else {
                print("EXTRACT_FAIL=too few images")
                exit(2)
            }

            let homeHTML = try await client.fetchHTML(
                URL(string: "https://www.wnacg.com/")!
            )
            let sections = HomeParser.parse(homeHTML)
            print("HOME_SECTIONS=\(sections.count)")
            print("HOME_CARDS=\(sections.reduce(0) { $0 + $1.albums.count })")
            if let first = sections.first {
                print("HOME_FIRST=\(first.title) \(first.albums.count)")
                print("HOME_MORE=\(first.moreURL?.absoluteString ?? "nil")")
            }
            guard sections.count >= 3 else {
                print("HOME_FAIL=too few sections")
                exit(2)
            }
            guard sections.contains(where: { !$0.albums.isEmpty }) else {
                print("HOME_FAIL=no cards")
                exit(2)
            }
            guard sections.contains(where: { $0.moreURL != nil }) else {
                print("HOME_FAIL=no category links")
                exit(2)
            }

            let listURL = URL(string: "https://www.wnacg.com/albums.html")!
            let listHTML = try await client.fetchHTML(listURL)
            let listAlbums = HomeParser.parseCards(listHTML)
            let nextPage = HomeParser.nextPageURL(listHTML, current: listURL)
            print("LIST_CARDS=\(listAlbums.count)")
            print("LIST_NEXT=\(nextPage?.absoluteString ?? "nil")")
            if listAlbums.count < 10 || nextPage == nil {
                print("LIST_FAIL=missing cards or next page")
                exit(2)
            }

            if let searchURL = HomeParser.searchURL("Flugel") {
                let searchHTML = try await client.fetchHTML(searchURL)
                let searchAlbums = HomeParser.parseCards(searchHTML)
                let searchNext = HomeParser.nextPageURL(
                    searchHTML, current: searchURL
                )
                print("SEARCH_CARDS=\(searchAlbums.count)")
                print("SEARCH_NEXT=\(searchNext?.absoluteString ?? "nil")")
                guard !searchAlbums.isEmpty, searchNext != nil else {
                    print("SEARCH_FAIL=missing results or next page")
                    exit(2)
                }
            }

            let itemHTML = try await client.fetchHTML(
                URL(string: "https://www.wnacg.com/photos-item-aid-383877.html")!
            )
            let pageArray = HTMLParser.first(
                "\"page_url\"\\s*:\\s*\\[(.*?)\\]", in: itemHTML
            ) ?? ""
            let readerURLs = HTMLParser.all(
                "\"(https?://[^\"]+)\"", in: pageArray
            )
            print("READER_PAGES=\(readerURLs.count)")
            if readerURLs.count < 10 {
                print("READER_FAIL=too few pages")
                exit(2)
            }
            exit(0)
        } catch {
            print("ERROR=\(error.localizedDescription)")
            exit(1)
        }
    }
}

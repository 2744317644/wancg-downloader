import Foundation

final class WnacgClient {
    let session: URLSession

    init() throws {
        if let error = ProxySession.shared.startupError {
            throw error
        }
        session = ProxySession.shared.session
    }

    func fetchHTML(_ url: URL, referer: URL? = nil) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WnacgError.message("无效的服务器响应")
        }
        guard http.statusCode == 200 else {
            throw WnacgError.message("访问失败：HTTP \(http.statusCode)")
        }
        return String(decoding: data, as: UTF8.self)
    }

    func imageData(_ url: URL, referer: URL?) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WnacgError.message("封面加载失败")
        }
        return data
    }

    func preview(for rawInput: String) async throws -> MangaPreview {
        let target = try await resolveTarget(rawInput)
        let html = try await fetchHTML(target.galleryURL)

        let desktopTitle = HTMLParser.first(
            "<div id=\"bodywrap\" class=\"userwrap\">\\s*<h2>(.*?)</h2>", in: html
        )
        let mobileTitle = HTMLParser.first(
            "id=\"comicName\"[^>]*>(.*?)</div>", in: html
        )
        let titleTag = HTMLParser.first("<title[^>]*>(.*?)</title>", in: html)
        var title = [mobileTitle, desktopTitle].compactMap { $0 }
            .map(HTMLParser.clean)
            .first { !$0.isEmpty }
        if title == nil, let titleTag {
            var value = HTMLParser.clean(titleTag)
            value = value.replacingOccurrences(
                of: "\\s*[-–—|]\\s*紳士漫畫.*$",
                with: "",
                options: .regularExpression
            )
            title = value
        }
        let displayTitle = title ?? "未命名作品"

        let thumb = HTMLParser.first(
            "<div class=\"asTBcell uwthumb\">(.*?)</div>", in: html
        )
        var coverRaw = thumb.flatMap {
            HTMLParser.first("<img[^>]+src=\"([^\"]+)\"", in: $0)
        }
        if coverRaw == nil {
            coverRaw = HTMLParser.first(
                "id=\"Cover\"[^>]*>\\s*<img[^>]+src=\"([^\"]+)\"", in: html
            )
        }
        let coverURL = coverRaw.flatMap { raw -> URL? in
            let normalized = HTMLParser.normalizeURL(raw)
            return URL(string: HTMLParser.encodedURLString(normalized))
        }

        var category = ""
        var pages: Int?
        var favorites: Int?
        for label in HTMLParser.all("<label[^>]*>(.*?)</label>", in: html) {
            let text = HTMLParser.clean(label)
            if text.hasPrefix("分類：") {
                category = String(text.dropFirst("分類：".count))
            } else if text.hasPrefix("頁數：") {
                let value = String(text.dropFirst("頁數：".count))
                pages = Int(value.replacingOccurrences(of: "P", with: "")
                    .trimmingCharacters(in: .whitespaces))
            } else if text.hasPrefix("收藏：") {
                favorites = Int(text.dropFirst("收藏：".count))
            }
        }

        if category.isEmpty {
            category = HTMLParser.first(
                "class=\"pd\"[^>]*href=\"/albums-index-cate-\\d+\\.html\"[^>]*>(.*?)</a>",
                in: html
            ).map(HTMLParser.clean) ?? ""
        }

        let dateText = HTMLParser.first(
            "<span class=\"date\">(.*?)</span>", in: html
        ).map(HTMLParser.clean) ?? ""
        if pages == nil {
            pages = HTMLParser.first("(\\d+)\\s*P", in: dateText).flatMap(Int.init)
        }
        if favorites == nil {
            favorites = HTMLParser.first("收藏\\s*(\\d+)", in: dateText)
                .flatMap(Int.init)
        }
        if pages == nil {
            pages = HTMLParser.first("(\\d+)\\s*P\\s*·", in: html).flatMap(Int.init)
        }

        var tags = HTMLParser.all(
            "<a class=\"tagshow\"[^>]*>(.*?)</a>", in: html
        ).map(HTMLParser.clean)
        tags += HTMLParser.all(
            "<a class=\"dv-tag\"[^>]*>(.*?)</a>", in: html
        ).map(HTMLParser.clean)
        tags = tags.filter { !$0.isEmpty }
        var uniqueTags: [String] = []
        for tag in tags where !uniqueTags.contains(tag) {
            uniqueTags.append(tag)
        }

        var uploader = HTMLParser.first(
            "<a href=\"/albums-user-uid-\\d+\\.html\">.*?<p>(.*?)</p>", in: html
        ).map(HTMLParser.clean) ?? ""
        if uploader.isEmpty {
            uploader = HTMLParser.first(
                "class=\"pd introName\"[^>]*>(.*?)</a>", in: html
            ).map(HTMLParser.clean) ?? ""
        }

        let uploaded = HTMLParser.first(
            "上傳於\\s*(\\d{4}-\\d{2}-\\d{2})", in: html
        ) ?? ""

        return MangaPreview(
            aid: target.aid,
            title: displayTitle,
            category: category,
            pages: pages,
            favorites: favorites,
            uploader: uploader,
            uploaded: uploaded,
            tags: uniqueTags,
            coverURL: coverURL,
            pageURL: target.galleryURL
        )
    }

    func downloadInfo(reqID: String) async throws -> DownloadInfo {
        let url = URL(string: "https://www.wnacg.com/download-index-aid-\(reqID).html")!
        let html = try await fetchHTML(
            url, referer: URL(string: "https://www.wnacg.com/photos-index-aid-\(reqID).html")
        )

        let rawName = HTMLParser.first("FILE_NAME:\\s*\"([^\"]+)\"", in: html)
            ?? "wnacg-\(reqID)"
        var filename = HTMLParser.safeFilename(rawName)
        if !filename.lowercased().hasSuffix(".zip") { filename += ".zip" }

        let hrefs = HTMLParser.all("href\\s*=\\s*\"([^\"]+)\"", in: html)
        var zipRaw = hrefs.first {
            let value = $0.lowercased()
            return value.contains(".zip") && (value.contains("dl") || value.contains("download"))
        } ?? hrefs.first { $0.lowercased().contains(".zip") }

        if zipRaw == nil {
            zipRaw = HTMLParser.first(
                "(https?://[^\"'<>\\s]+\\.zip(?:\\?[^\"'<>\\s]*)?)", in: html
            )
        }
        guard let rawLink = zipRaw else {
            throw WnacgError.message("下载页里没有找到 ZIP 直链")
        }

        let normalized = HTMLParser.normalizeURL(rawLink)
        guard let zipURL = URL(string: HTMLParser.encodedURLString(normalized)) else {
            throw WnacgError.message("ZIP 直链格式无效")
        }
        return DownloadInfo(zipURL: zipURL, filename: filename)
    }

    func download(
        _ info: DownloadInfo,
        referer: URL,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        let downloads = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0]
        let destination = downloads.appendingPathComponent(info.filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }

        let downloader = FileDownloader()
        return try await downloader.download(
            info.zipURL,
            destination: destination,
            referer: referer,
            progress: progress
        )
    }

    private struct Target {
        let aid: String
        let host: String
        let galleryURL: URL
    }

    private func resolveTarget(_ rawInput: String) async throws -> Target {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.range(of: "^\\d+$", options: .regularExpression) != nil {
            let url = URL(string: "https://www.wnacg.com/photos-index-aid-\(input).html")!
            return Target(aid: input, host: "www.wnacg.com", galleryURL: url)
        }

        var text = input
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), let host = url.host else {
            throw WnacgError.message("无法识别这个链接")
        }

        if let aid = HTMLParser.first("aid-(\\d+)", in: url.path) {
            let gallery = URL(string: "https://\(host)/photos-index-aid-\(aid).html")!
            return Target(aid: aid, host: host, galleryURL: gallery)
        }

        if url.path.contains("photos-view") || url.path.contains("photos-slide") {
            let html = try await fetchHTML(url)
            guard let aid = HTMLParser.first(
                "/photos-index-aid-(\\d+)\\.html", in: html
            ) else {
                throw WnacgError.message("无法从阅读页找到作品编号")
            }
            let gallery = URL(string: "https://\(host)/photos-index-aid-\(aid).html")!
            return Target(aid: aid, host: host, galleryURL: gallery)
        }

        throw WnacgError.message("请粘贴作品页链接，例如 photos-index-aid-383877.html")
    }
}

private final class FileDownloader: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?
    private var finished: URL?
    private var progressHandler: ((Double) -> Void)?
    private var session: URLSession!
    private var request: URLRequest?
    private var retries = 0

    func download(
        _ url: URL,
        destination: URL,
        referer: URL,
        progress: @escaping (Double) -> Void
    ) async throws -> URL {
        self.destination = destination
        progressHandler = progress

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        self.request = request

        let configuration = URLSessionConfiguration.default
        configuration.connectionProxyDictionary =
            ProxySession.shared.session.configuration.connectionProxyDictionary
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 1200
        session = URLSession(
            configuration: configuration, delegate: self, delegateQueue: nil
        )

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: request).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let value = min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        DispatchQueue.main.async { [progressHandler] in
            progressHandler?(value)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let destination else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            finished = destination
        } catch {
            finished = nil
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        session.finishTasksAndInvalidate()
        guard let continuation else { return }
        self.continuation = nil

        if let error {
            continuation.resume(throwing: error)
        } else if let finished {
            continuation.resume(returning: finished)
        } else {
            continuation.resume(throwing: WnacgError.message("下载完成但文件保存失败"))
        }
    }
}

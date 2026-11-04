import Foundation

final class WnacgClient {
    var session: URLSession { ProxySession.shared.session }

    init() throws {
        if let error = ProxySession.shared.startupError {
            throw error
        }
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
        let (data, response) = try await load(request)
        guard let http = response as? HTTPURLResponse else {
            throw WnacgError.message("无效的服务器响应")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 429 {
                throw WnacgError.message(
                    "访问太频繁，被站点限流（HTTP 429），稍后点“重试”即可"
                )
            }
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
        let (data, response) = try await load(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WnacgError.message("图片加载失败")
        }
        return data
    }

    /// 后台/息屏后本地代理可能已经失效；遇到 310 重启代理，
    /// 遇到 HTTP 429 时按 Retry-After / 指数退避重试。
    private func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        if ProxySession.shared.startupError != nil {
            // A single failed local-proxy start used to be sticky forever:
            // every later request threw before the retry loop, so only a
            // background→foreground restart could heal the app. Try once here.
            ProxySession.shared.restart()
        }
        if let startupError = ProxySession.shared.startupError {
            throw startupError
        }
        var rateLimitAttempt = 0
        var proxyAttempt = 0

        while true {
            do {
                let result = try await session.data(for: request)
                if let http = result.1 as? HTTPURLResponse,
                   http.statusCode == 429,
                   rateLimitAttempt < 2 {
                    let delay = retryDelay(http, attempt: rateLimitAttempt)
                    rateLimitAttempt += 1
                    do {
                        try await Task.sleep(
                            nanoseconds: UInt64(delay * 1_000_000_000)
                        )
                    } catch {
                        throw error
                    }
                    continue
                }
                return result
            } catch {
                if Task.isCancelled { throw error }
                let nsError = error as NSError
                let code = nsError.code
                let proxyFailure =
                    code == 310 || code == -310
                    || (nsError.domain == NSURLErrorDomain
                        // -999: the shared URLSession is invalidated when the
                        // proxy restarts, which kills sibling in-flight
                        // requests. Retry those too instead of surfacing a
                        // bogus "cancelled" failure for covers/feed requests.
                        && [-999, -1001, -1004, -1005, -1009, -1200]
                            .contains(code))
                guard proxyFailure, proxyAttempt < 2 else { throw error }
                proxyAttempt += 1
                ProxySession.shared.restart()
                do {
                    try await Task.sleep(nanoseconds: 300_000_000)
                } catch {
                    throw error
                }
            }
        }
    }

    private func retryDelay(_ response: HTTPURLResponse, attempt: Int) -> Double {
        if let raw = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(raw.trimmingCharacters(in: .whitespaces)) {
            return min(max(seconds, 1), 8)
        }
        return attempt == 0 ? 2 : 4
    }

    func preview(for rawInput: String) async throws -> MangaPreview {
        let target = try await resolveTarget(rawInput)
        let html = try await fetchHTML(
            target.galleryURL,
            referer: URL(string: "https://www.wnacg.com/")
        )

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
            pageURL: target.galleryURL,
            recommendations: HomeParser.parseRecommendations(html)
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
        progress: @escaping (Double, Int64, Int64) -> Void
    ) async throws -> URL {
        let downloads = DownloadFolders.zipDirectory
        try FileManager.default.createDirectory(
            at: downloads, withIntermediateDirectories: true
        )
        let destination = downloads.appendingPathComponent(info.filename)
        let partial = destination.appendingPathExtension("part")
        try? FileManager.default.removeItem(at: partial)

        let downloader = FileDownloader()
        do {
            _ = try await downloader.download(
                info.zipURL,
                destination: partial,
                referer: referer,
                progress: progress
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: partial, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
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
    private var progressHandler: ((Double, Int64, Int64) -> Void)?
    private var session: URLSession!
    private var request: URLRequest?
    private var retries = 0
    private var failure: Error?
    private var downloadTask: URLSessionDownloadTask?

    func download(
        _ url: URL,
        destination: URL,
        referer: URL,
        progress: @escaping (Double, Int64, Int64) -> Void
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

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let task = session.downloadTask(with: request)
                self.downloadTask = task
                task.resume()
            }
        } onCancel: {
            self.downloadTask?.cancel()
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
            progressHandler?(value, totalBytesWritten, totalBytesExpectedToWrite)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: location)
            failure = WnacgError.message("下载失败：HTTP \(http.statusCode)")
            return
        }
        guard let destination else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            finished = destination
        } catch {
            finished = nil
            failure = WnacgError.message(
                "下载完成但文件保存失败：\(error.localizedDescription)"
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        session.finishTasksAndInvalidate()
        downloadTask = nil
        guard let continuation else { return }
        self.continuation = nil

        if let error {
            continuation.resume(throwing: error)
        } else if let failure {
            continuation.resume(throwing: failure)
        } else if let finished {
            continuation.resume(returning: finished)
        } else {
            continuation.resume(throwing: WnacgError.message("下载完成但文件保存失败"))
        }
    }
}

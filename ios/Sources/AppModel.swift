import Foundation
import UIKit

@MainActor
final class AppModel: ObservableObject {
    @Published var input = ""
    @Published var preview: MangaPreview?
    @Published var coverImage: UIImage?
    @Published var makePDF = true
    @Published var isBusy = false
    @Published var status = "粘贴作品链接后点“解析”"
    @Published var downloadProgress: Double = 0
    @Published var pdfProgress: Double = 0
    @Published var errorMessage: String?
    @Published var zipURL: URL?
    @Published var pdfURL: URL?
    @Published private(set) var activeAid: String?
    @Published private(set) var queue: [QueuedDownload] = []

    private var client: WnacgClient?
    private let queueKey = "wnacg.downloadQueue.v1"
    private let inflightKey = "wnacg.downloadInflight.v1"
    private var inflightItem: QueuedDownload?
    private var didResumeQueue = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    var hasActiveDownload: Bool {
        activeAid != nil || isBusy
    }

    func isDownloading(_ aid: String) -> Bool {
        activeAid == aid
    }

    func isQueued(_ aid: String) -> Bool {
        queue.contains { $0.aid == aid }
    }

    func queuePosition(_ aid: String) -> Int? {
        guard let index = queue.firstIndex(where: { $0.aid == aid }) else {
            return nil
        }
        return index + 1
    }

    init() {
        do {
            client = try WnacgClient()
        } catch {
            errorMessage = error.localizedDescription
        }
        loadQueue()
        recoverInflight()
    }

    /// App 启动后把上次未开始的任务继续跑起来。
    func resumeQueueIfNeeded() {
        guard !didResumeQueue else { return }
        didResumeQueue = true
        guard activeAid == nil, !isBusy else { return }
        processNext()
    }

    private func persistQueue() {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        UserDefaults.standard.set(data, forKey: queueKey)
    }

    private func setInflight(_ item: QueuedDownload?) {
        inflightItem = item
        if let item, let data = try? JSONEncoder().encode(item) {
            UserDefaults.standard.set(data, forKey: inflightKey)
        } else {
            UserDefaults.standard.removeObject(forKey: inflightKey)
        }
    }

    private func recoverInflight() {
        guard let data = UserDefaults.standard.data(forKey: inflightKey),
              let item = try? JSONDecoder().decode(
                  QueuedDownload.self, from: data
              ) else {
            return
        }
        UserDefaults.standard.removeObject(forKey: inflightKey)
        if !queue.contains(where: { $0.aid == item.aid }) {
            queue.insert(item, at: 0)
            persistQueue()
        }
    }

    private func loadQueue() {
        guard let data = UserDefaults.standard.data(forKey: queueKey),
              let saved = try? JSONDecoder().decode(
                  [QueuedDownload].self, from: data
              ) else {
            return
        }
        queue = saved
    }

    func parse(value: String? = nil, drainQueue: Bool = true) async {
        guard !isBusy else { return }
        let value = (value ?? input)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            errorMessage = "请先粘贴作品链接"
            return
        }

        if client == nil {
            client = try? WnacgClient()
        }
        isBusy = true
        errorMessage = nil
        preview = nil
        coverImage = nil
        zipURL = nil
        pdfURL = nil
        downloadProgress = 0
        pdfProgress = 0
        status = "正在解析作品页…"

        do {
            guard let client else {
                throw WnacgError.message("网络代理初始化失败")
            }
            let result = try await client.preview(for: value)
            preview = result
            status = "解析完成"

            if let coverURL = result.coverURL {
                Task {
                    if let data = try? await client.imageData(
                        coverURL, referer: result.pageURL
                    ), let image = UIImage(data: data) {
                        await MainActor.run {
                            if self.preview?.aid == result.aid {
                                self.coverImage = image
                            }
                        }
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            status = "解析失败"
        }
        isBusy = false
        if drainQueue && activeAid == nil {
            processNext()
        }
    }

    func parseAndDownload() async {
        await parse(drainQueue: false)
        guard !isBusy, preview != nil, errorMessage == nil else { return }
        _ = await download()
    }

    func enqueue(album: HomeAlbum) {
        guard activeAid != album.aid,
              !isQueued(album.aid) else { return }

        let item = QueuedDownload(album: album)
        if activeAid == nil && !isBusy && queue.isEmpty {
            startQueued(item)
        } else {
            queue.append(item)
            persistQueue()
        }
    }

    private func startQueued(_ item: QueuedDownload) {
        let album = item.homeAlbum
        activeAid = item.aid
        setInflight(item)
        Task {
            await parse(
                value: album.pageURL.absoluteString,
                drainQueue: false
            )
            guard let preview, errorMessage == nil else {
                activeAid = nil
                setInflight(nil)
                processNext()
                return
            }
            guard preview.aid == album.aid else {
                queue.insert(item, at: 0)
                persistQueue()
                activeAid = nil
                setInflight(nil)
                return
            }
            let started = await download(expectedAid: album.aid)
            if !started {
                queue.insert(item, at: 0)
                persistQueue()
                activeAid = nil
                setInflight(nil)
            }
        }
    }

    private func processNext() {
        guard activeAid == nil, !isBusy, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        persistQueue()
        startQueued(next)
    }

    func retryCurrentDownload() async {
        guard !isBusy, preview != nil else { return }
        _ = await download()
    }

    @discardableResult
    func download(expectedAid: String? = nil) async -> Bool {
        guard !isBusy, let preview, let client else { return false }
        if let expectedAid, preview.aid != expectedAid {
            errorMessage = "下载任务被其他操作打断，请重试"
            return false
        }
        if isQueued(preview.aid) {
            queue.removeAll { $0.aid == preview.aid }
            persistQueue()
        }
        activeAid = preview.aid
        isBusy = true
        errorMessage = nil
        zipURL = nil
        pdfURL = nil
        downloadProgress = 0
        pdfProgress = 0
        status = "正在获取下载地址…"
        beginBackgroundTask()
        DownloadLiveActivityManager.shared.start(
            aid: preview.aid, title: preview.title
        )
        DownloadLiveActivityManager.shared.update(
            progress: 0, status: status
        )
        defer {
            endBackgroundTask()
            DownloadLiveActivityManager.shared.end(
                progress: downloadProgress, status: status
            )
        }

        do {
            let info = try await client.downloadInfo(reqID: preview.aid)
            status = "正在下载 ZIP…"
            let downloaded = try await client.download(
                info, referer: preview.pageURL
            ) { value in
                Task { @MainActor in
                    self.downloadProgress = value * 0.7
                    DownloadLiveActivityManager.shared.update(
                        progress: value * 0.7, status: "正在下载 ZIP…"
                    )
                }
            }
            zipURL = downloaded
            try ZipExtractor.validate(downloaded)
            downloadProgress = 0.7
            DownloadLiveActivityManager.shared.update(
                progress: 0.7, status: "正在处理 PDF…"
            )

            if makePDF {
                status = "正在解压图片…"
                let images = try await Task.detached(
                    priority: .userInitiated
                ) {
                    try ZipExtractor.extractImages(from: downloaded)
                }.value
                defer {
                    if let first = images.first {
                        try? FileManager.default.removeItem(
                            at: first.deletingLastPathComponent()
                        )
                    }
                }
                DownloadHistory.shared.markDownloaded(preview.aid)
                let base = downloaded.deletingPathExtension().lastPathComponent
                let documents = FileManager.default.urls(
                    for: .documentDirectory, in: .userDomainMask
                )[0]
                let output = documents.appendingPathComponent(base + ".pdf")

                status = "正在生成 PDF（共 \(images.count) 页）…"
                let pages = try await Task.detached(
                    priority: .userInitiated
                ) {
                    try PDFBuilder.build(
                        images: images, output: output, dpi: 300
                    ) { current, total in
                        Task { @MainActor in
                            let value = total > 0
                                ? 0.7 + 0.3 * Double(current) / Double(total)
                                : 0.7
                            self.pdfProgress = value
                            DownloadLiveActivityManager.shared.update(
                                progress: value, status: "正在生成 PDF…"
                            )
                        }
                    }
                }.value
                pdfURL = output
                pdfProgress = 1
                status = "完成：ZIP + PDF（\(pages) 页）"
            } else {
                DownloadHistory.shared.markDownloaded(preview.aid)
                status = "完成：ZIP"
            }
            downloadProgress = 1
            NotificationCenter.default.post(
                name: .downloadsChanged, object: nil
            )
        } catch {
            errorMessage = error.localizedDescription
            status = "下载失败"
        }
        isBusy = false
        activeAid = nil
        if inflightItem?.aid == preview.aid {
            setInflight(nil)
        }
        processNext()
        return true
    }

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "wnacg-download"
        ) { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}

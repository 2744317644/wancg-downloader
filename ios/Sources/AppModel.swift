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

    private var client: WnacgClient?

    init() {
        do {
            client = try WnacgClient()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func parse() async {
        guard !isBusy else { return }
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            errorMessage = "请先粘贴作品链接"
            return
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
                        await MainActor.run { self.coverImage = image }
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            status = "解析失败"
        }
        isBusy = false
    }

    func parseAndDownload() async {
        await parse()
        guard !isBusy, preview != nil, errorMessage == nil else { return }
        await download()
    }

    func download() async {        guard !isBusy, let preview, let client else { return }
        isBusy = true
        errorMessage = nil
        zipURL = nil
        pdfURL = nil
        downloadProgress = 0
        pdfProgress = 0
        status = "正在获取下载地址…"

        do {
            let info = try await client.downloadInfo(reqID: preview.aid)
            status = "正在下载 ZIP…"
            let downloaded = try await client.download(
                info, referer: preview.pageURL
            ) { value in
                Task { @MainActor in
                    self.downloadProgress = value * 0.7
                }
            }
            zipURL = downloaded
            downloadProgress = 0.7
            DownloadHistory.shared.markDownloaded(preview.aid)

            if makePDF {
                status = "正在解压图片…"
                let images = try ZipExtractor.extractImages(from: downloaded)
                defer {
                    if let first = images.first {
                        try? FileManager.default.removeItem(
                            at: first.deletingLastPathComponent()
                        )
                    }
                }
                let base = downloaded.deletingPathExtension().lastPathComponent
                let documents = FileManager.default.urls(
                    for: .documentDirectory, in: .userDomainMask
                )[0]
                let output = documents.appendingPathComponent(base + ".pdf")

                status = "正在生成 PDF（共 \(images.count) 页）…"
                let pages = try PDFBuilder.build(
                    images: images, output: output, dpi: 300
                ) { current, total in
                    Task { @MainActor in
                        self.pdfProgress = total > 0
                            ? 0.7 + 0.3 * Double(current) / Double(total)
                            : 0.7
                    }
                }
                pdfURL = output
                pdfProgress = 1
                status = "完成：ZIP + PDF（\(pages) 页）"
            } else {
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
    }
}

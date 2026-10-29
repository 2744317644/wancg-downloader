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
            exit(0)
        } catch {
            print("ERROR=\(error.localizedDescription)")
            exit(1)
        }
    }
}

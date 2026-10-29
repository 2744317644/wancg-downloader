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
            exit(0)
        } catch {
            print("ERROR=\(error.localizedDescription)")
            exit(1)
        }
    }
}

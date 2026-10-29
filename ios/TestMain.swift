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
            exit(0)
        } catch {
            print("ERROR=\(error.localizedDescription)")
            exit(1)
        }
    }
}

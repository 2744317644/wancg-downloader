import Foundation

enum FavoritesExporter {
    static func write(
        items: [FavoriteManga],
        downloadedAids: Set<String>
    ) -> URL? {
        let downloaded = items.filter { downloadedAids.contains($0.aid) }
        let pending = items.filter { !downloadedAids.contains($0.aid) }
        let now = Date()
        let name = "wnacg-favorites.html"

        let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0]
        let output = documents.appendingPathComponent(name)
        let stamp = Int(now.timeIntervalSince1970)

        var lines: [String] = [
            "<!DOCTYPE NETSCAPE-Bookmark-file-1>",
            "<!-- This is an automatically generated file. -->",
            "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">",
            "<TITLE>wnacg 收藏夹</TITLE>",
            "<H1>wnacg 收藏夹</H1>",
            "<DL><p>",
        ]
        appendFolder(
            title: "已下载",
            items: downloaded,
            stamp: stamp,
            to: &lines
        )
        appendFolder(
            title: "未下载",
            items: pending,
            stamp: stamp,
            to: &lines
        )
        lines.append("</DL><p>")
        lines.append("")

        do {
            try lines.joined(separator: "\n").write(
                to: output, atomically: true, encoding: .utf8
            )
            return output
        } catch {
            return nil
        }
    }

    private static func appendFolder(
        title: String,
        items: [FavoriteManga],
        stamp: Int,
        to lines: inout [String]
    ) {
        lines.append("    <DT><H3 ADD_DATE=\"\(stamp)\">\(escape(title)) (\(items.count))</H3>")
        lines.append("    <DL><p>")
        for item in items {
            let added = Int(item.addedAt.timeIntervalSince1970)
            lines.append(
                "        <DT><A HREF=\"\(escape(item.pageURL))\" ADD_DATE=\"\(added)\">\(escape(item.title))</A>"
            )
        }
        lines.append("    </DL><p>")
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

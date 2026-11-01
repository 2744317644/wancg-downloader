import Foundation

enum FavoritesExporter {
    static func write(
        items: [FavoriteManga],
        downloadedAids: Set<String>
    ) -> URL? {
        let name = "wnacg-favorites.html"
        let documents = DownloadFolders.documents
        let output = documents.appendingPathComponent(name)

        var lines: [String] = [
            "<!DOCTYPE NETSCAPE-Bookmark-file-1>",
            "<!-- This is an automatically generated file. -->",
            "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">",
            "<TITLE>wnacg 收藏夹</TITLE>",
            "<H1>wnacg 收藏夹</H1>",
            "<DL><p>",
        ]

        for item in items {
            let isDownloaded = downloadedAids.contains(item.aid)
            let marker = isDownloaded ? "【已下载】" : "【未下载】"
            let status = isDownloaded ? "已下载" : "未下载"
            let added = Int(item.addedAt.timeIntervalSince1970)
            lines.append(
                "    <DT><A HREF=\"\(escape(item.pageURL))\""
                + " ADD_DATE=\"\(added)\" DESCRIPTION=\"\(status)\">"
                + "\(marker)\(escape(item.title))</A>"
            )
        }

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

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

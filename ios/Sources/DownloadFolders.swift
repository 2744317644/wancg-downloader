import Foundation

enum DownloadFolders {
    static var documents: URL {
        FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0]
    }

    static var zipDirectory: URL {
        documents.appendingPathComponent("ZIP", isDirectory: true)
    }

    static var pdfDirectory: URL {
        documents.appendingPathComponent("PDF", isDirectory: true)
    }

    static func prepare() {
        let manager = FileManager.default
        for directory in [zipDirectory, pdfDirectory] {
            try? manager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        migrateLegacyFiles()
    }

    static func allFiles() -> [URL] {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: documents,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var result: [URL] = []
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard ext == "zip" || ext == "pdf" else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            result.append(url)
        }
        return result
    }

    private static func migrateLegacyFiles() {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for file in files {
            let ext = file.pathExtension.lowercased()
            let targetDirectory: URL
            if ext == "zip" {
                targetDirectory = zipDirectory
            } else if ext == "pdf" {
                targetDirectory = pdfDirectory
            } else {
                continue
            }

            let target = targetDirectory.appendingPathComponent(
                file.lastPathComponent
            )
            guard !manager.fileExists(atPath: target.path) else { continue }
            try? manager.moveItem(at: file, to: target)
        }
    }
}

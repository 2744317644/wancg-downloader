import Foundation
import ZIPFoundation

enum ZipExtractor {
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "jfif", "png", "webp",
        "gif", "bmp", "tif", "tiff",
    ]

    static func extractImages(from zipURL: URL) throws -> [URL] {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("wnacg-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let archive = try Archive(url: zipURL, accessMode: .read)
        var entries: [Entry] = []
        for entry in archive {
            guard entry.type == .file else { continue }
            let path = entry.path.replacingOccurrences(of: "\\", with: "/")
            if path.contains("__MACOSX") || path.hasPrefix(".") { continue }
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            guard imageExtensions.contains(ext) else { continue }
            entries.append(entry)
        }

        entries.sort { naturalLess($0.path, $1.path) }
        guard !entries.isEmpty else {
            throw WnacgError.message("压缩包里没有找到图片")
        }

        var images: [URL] = []
        for (index, entry) in entries.enumerated() {
            let ext = URL(fileURLWithPath: entry.path).pathExtension.lowercased()
            let name = String(format: "%05d.%@", index, ext)
            let destination = root.appendingPathComponent(name)
            _ = try archive.extract(entry, to: destination)
            if fileManager.fileExists(atPath: destination.path) {
                images.append(destination)
            }
        }
        return images
    }

    private enum Token: Equatable {
        case number(Int)
        case text(String)
    }

    private static func tokens(_ value: String) -> [Token] {
        var result: [Token] = []
        var current = ""
        var currentIsNumber = false

        for character in value.lowercased() {
            let isNumber = character.isNumber
            if current.isEmpty {
                current = String(character)
                currentIsNumber = isNumber
            } else if isNumber == currentIsNumber {
                current.append(character)
            } else {
                result.append(currentIsNumber ? .number(Int(current) ?? 0) : .text(current))
                current = String(character)
                currentIsNumber = isNumber
            }
        }
        if !current.isEmpty {
            result.append(currentIsNumber ? .number(Int(current) ?? 0) : .text(current))
        }
        return result
    }

    private static func naturalLess(_ lhs: String, _ rhs: String) -> Bool {
        let left = tokens(lhs)
        let right = tokens(rhs)
        for (a, b) in zip(left, right) {
            switch (a, b) {
            case let (.number(x), .number(y)):
                if x != y { return x < y }
            case let (.text(x), .text(y)):
                if x != y { return x < y }
            case (.number, .text):
                return true
            case (.text, .number):
                return false
            }
        }
        return left.count < right.count
    }
}

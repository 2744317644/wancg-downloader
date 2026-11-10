import Foundation

/// User-managed tag/keyword exclusions. The listing HTML only carries the
/// album title, so exclusions are applied to the title text (case- and
/// width-insensitively); no extra per-album requests are made.
enum TagExclusionStore {
    static let storageKey = "manga.excludedTags"

    static func list(from raw: String) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for line in raw.split(whereSeparator: { $0.isNewline }) {
            let tag = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty else { continue }
            let key = normalized(tag)
            guard seen.insert(key).inserted else { continue }
            result.append(tag)
        }
        return result
    }

    static func serialize(_ tags: [String]) -> String {
        list(from: tags.joined(separator: "\n")).joined(separator: "\n")
    }

    static func key(_ tag: String) -> String {
        normalized(tag)
    }

    static func contains(_ tag: String, in list: [String]) -> Bool {
        let key = normalized(tag)
        return list.contains { normalized($0) == key }
    }

    static func matches(_ title: String, excluded: [String]) -> Bool {
        guard !excluded.isEmpty else { return false }
        let text = normalized(title)
        return excluded.contains { text.contains(normalized($0)) }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .widthInsensitive],
            locale: .current
        ).lowercased()
    }
}

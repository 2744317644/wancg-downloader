import Foundation

enum HTMLParser {
    static func first(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[valueRange])
    }

    static func all(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[valueRange])
        }
    }

    static func clean(_ value: String) -> String {
        var text = value.replacingOccurrences(
            of: "<[^>]+>", with: " ", options: .regularExpression
        )
        text = decodeEntities(text)
        text = text.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ value: String) -> String {
        var text = value
        let named = [
            "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&lt;": "<", "&gt;": ">", "&nbsp;": " ",
        ]
        for (key, replacement) in named {
            text = text.replacingOccurrences(of: key, with: replacement)
        }

        guard let regex = try? NSRegularExpression(pattern: "&#(x?[0-9A-Fa-f]+);") else {
            return text
        }
        let matches = regex.matches(
            in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)
        )
        for match in matches.reversed() {
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else { continue }
            let raw = String(text[range])
            let number: UInt32?
            if raw.lowercased().hasPrefix("x") {
                number = UInt32(raw.dropFirst(), radix: 16)
            } else {
                number = UInt32(raw)
            }
            guard let scalarValue = number, let scalar = UnicodeScalar(scalarValue) else {
                continue
            }
            if let fullRange = Range(match.range(at: 0), in: text) {
                text.replaceSubrange(fullRange, with: String(Character(scalar)))
            }
        }
        return text
    }

    static func normalizeURL(_ value: String) -> String {
        var url = decodeEntities(value).trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasPrefix("////") {
            url = "https:" + String(url.dropFirst(2))
        } else if url.hasPrefix("//") {
            url = "https:" + url
        } else if url.hasPrefix("/") {
            url = "https://www.wnacg.com" + url
        }
        return url
    }

    static func encodedURLString(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(charactersIn: "%")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func safeFilename(_ value: String) -> String {
        var name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.replacingOccurrences(
            of: "[<>:\"/\\\\|?*\\u{0000}-\\u{001F}]",
            with: "_",
            options: .regularExpression
        )
        name = name.replacingOccurrences(
            of: "\\.zip$", with: "", options: [.regularExpression, .caseInsensitive]
        )
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        if name.isEmpty { name = "wnacg" }
        if name.count > 120 { name = String(name.prefix(120)) }
        return name
    }
}

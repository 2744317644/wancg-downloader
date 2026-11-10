import Foundation

/// Resolves excluded tag names to actual album IDs by walking the site's
/// `/albums-index-tag-<tag>.html` pages. Tag listing pages are newest-first,
/// so we only need to read pages until their oldest card predates the oldest
/// album currently loaded. This gives exact tag matches without fetching the
/// detail page of every card; if coverage is incomplete we fall back to the
/// title keyword match.
@MainActor
final class ExcludedTagIndex {
    static let shared = ExcludedTagIndex()

    private var client: WnacgClient?
    private var aidsByTag: [String: Set<String>] = [:]
    private var coverageByTag: [String: String] = [:]
    private var nextByTag: [String: URL] = [:]
    private var exhaustedTags = Set<String>()
    private var fetchingTags = Set<String>()

    private let maxPagesPerCall = 8

    func ensureCoverage(tags: [String], through oldestDate: String) async {
        guard !tags.isEmpty else { return }
        for tag in tags {
            let key = TagExclusionStore.key(tag)
            guard !key.isEmpty, !fetchingTags.contains(key) else { continue }
            if exhaustedTags.contains(key) { continue }
            if !oldestDate.isEmpty,
               let covered = coverageByTag[key],
               covered <= oldestDate {
                continue
            }
            fetchingTags.insert(key)
            await fetchPages(tag: tag, key: key, through: oldestDate)
            fetchingTags.remove(key)
        }
    }

    func isExcluded(album: HomeAlbum, tags: [String]) -> Bool {
        for tag in tags {
            let key = TagExclusionStore.key(tag)
            guard !key.isEmpty else { continue }

            if let aids = aidsByTag[key] {
                if aids.contains(album.aid) { return true }
                let covered = exhaustedTags.contains(key)
                    || (!album.date.isEmpty
                        && (coverageByTag[key] ?? "").isEmpty == false
                        && album.date >= (coverageByTag[key] ?? ""))
                if covered {
                    // The whole relevant date range has been indexed and the
                    // album is not in this tag's set.
                    continue
                }
            }

            if TagExclusionStore.matches(album.title, excluded: [tag]) {
                return true
            }
        }
        return false
    }

    private func fetchPages(tag: String, key: String, through oldestDate: String) async {
        if client == nil {
            client = try? WnacgClient()
        }
        guard let client else { return }

        var url = nextByTag[key] ?? HomeParser.tagURL(tag)

        var pages = 0
        while pages < maxPagesPerCall, let current = url {
            do {
                let html = try await client.fetchHTML(
                    current,
                    referer: HomeParser.baseURL
                )
                let cards = HomeParser.parseCards(html)
                let next = HomeParser.nextPageURL(html, current: current)

                var aids = aidsByTag[key] ?? []
                for card in cards {
                    aids.insert(card.aid)
                }
                aidsByTag[key] = aids

                let pageOldest = cards
                    .compactMap { $0.date.isEmpty ? nil : $0.date }
                    .min()
                if let pageOldest,
                   coverageByTag[key] == nil
                        || pageOldest < (coverageByTag[key] ?? "") {
                    coverageByTag[key] = pageOldest
                }

                if let next {
                    nextByTag[key] = next
                } else {
                    nextByTag.removeValue(forKey: key)
                    exhaustedTags.insert(key)
                }
                pages += 1

                if exhaustedTags.contains(key) { break }
                if let pageOldest,
                   !oldestDate.isEmpty,
                   pageOldest <= oldestDate {
                    break
                }
                url = next
                if url != nil {
                    try? await Task.sleep(for: .milliseconds(250))
                }
            } catch {
                // Keep partial coverage; the title fallback still applies.
                break
            }
        }
    }
}

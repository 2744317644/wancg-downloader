import Foundation

struct MangaPreview: Identifiable {
    let id = UUID()
    let aid: String
    let title: String
    let category: String
    let pages: Int?
    let favorites: Int?
    let uploader: String
    let uploaded: String
    let tags: [String]
    let coverURL: URL?
    let pageURL: URL
    let recommendations: [HomeAlbum]
}

struct DownloadInfo {
    let zipURL: URL
    let filename: String
}

enum WnacgError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text):
            return text
        }
    }
}

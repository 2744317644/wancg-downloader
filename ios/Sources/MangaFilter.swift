import SwiftUI

enum MangaLanguageFilter: String, CaseIterable, Identifiable {
    case all
    case translated
    case japanese

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .translated: return "翻译"
        case .japanese: return "日语"
        }
    }
}

extension HomeAlbum {
    /// 站点列表没有语言字段，按标题里的常见标记做一次轻量分类。
    var language: MangaLanguageFilter {
        let text = title.lowercased()
        let translatedMarkers = [
            "中国翻訳", "中国翻译", "中文", "漢化", "汉化", "翻譯", "翻译",
            "中文版", "中国語", "chinese", "translated", "漢化組", "汉化组",
        ]
        if translatedMarkers.contains(where: { text.contains($0) }) {
            return .translated
        }
        return .japanese
    }

    func matches(language: MangaLanguageFilter) -> Bool {
        language == .all || self.language == language
    }
}

struct MangaFilterMenu: View {
    @AppStorage("manga.languageFilter")
    private var language = MangaLanguageFilter.all.rawValue
    @AppStorage("manga.hideDownloaded")
    private var hideDownloaded = false

    var body: some View {
        Menu {
            Picker("语言", selection: $language) {
                ForEach(MangaLanguageFilter.allCases) { filter in
                    Text(filter.title).tag(filter.rawValue)
                }
            }

            Toggle("隐藏已下载", isOn: $hideDownloaded)
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }
}

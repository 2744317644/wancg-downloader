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

    /// 站点列表没有语言字段，按标题里的常见标记做一次轻量分类。
    /// 在 `HomeAlbum` 解析时调用一次并缓存，避免每帧重复扫描标题。
    static func detect(in title: String) -> MangaLanguageFilter {
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
}

extension HomeAlbum {
    func matches(language: MangaLanguageFilter) -> Bool {
        language == .all || self.language == language
    }
}

enum AIContentFilter {
    private static let markers = [
        "ai生成", "aiイラスト", "aiグラビア", "ai美女", "ai画像",
        "ai写真", "aiアート", "aiヌード", "aiコスプレ", "aiチャット",
        "ai着せ替え", "ai绘画", "ai绘图", "ai繪圖", "ai艺术",
        "ai藝術", "ai作品", "ai漫画", "ai漫畫", "ai插画",
        "ai插畫", "ai寫真", "ai图集", "ai圖集", "ai art",
        "ai-art", "ai generated", "ai-generated", "ai girl", "ai model",
        "生成ai", "ai画像生成", "aiイラスト生成", "ai写真集",
        "aiヌード写真", "aiエロ", "aiフェラ", "aiセックス",
        "aiおっぱい", "aiちんこ", "ai彼女", "ai少女", "aiロリ",
        "ai制服", "ai巨乳", "ai爆乳", "ai裸", "ai全裸", "aiエッチ",
        "aiセクシー", "aiランジェリー", "ai水着", "ai着エロ",
        "ai脱衣", "aiポートレート", "aiフォト", "aiモデル",
        "ai美少女", "ai人妻", "ai痴女", "ai寝取られ", "ai同人",
        "ai画集", "aiヘアヌード", "ai porn", "ai nude", "ai hentai",
        "ai waifu", "ai anime", "ai cosplay", "ai gravure",
        "ai women", "ai woman", "ai image", "ai images", "ai gallery",
        "ai illustration", "ai图集", "ai图片", "ai圖片", "ai图像",
        "ai圖像", "ai创作", "ai創作", "ai模特", "ai换脸", "ai換臉",
        "ai脫衣", "ai裸照", "ai色图", "ai色圖", "ai涩图", "ai澀圖",
        "ai黄图", "ai黃圖", "ai生成画像", "ai生成圖片",
    ]

    private static let tokenRegex = try? NSRegularExpression(
        pattern: "(^|[\\s\\[\\]【】()（）_-])ai($|[\\s\\[\\]【】()（）_-])",
        options: [.caseInsensitive]
    )

    static func matches(_ title: String) -> Bool {
        let text = title.folding(
            options: [.caseInsensitive, .widthInsensitive],
            locale: .current
        ).lowercased()
        if markers.contains(where: { text.contains($0) }) {
            return true
        }
        guard let tokenRegex else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return tokenRegex.firstMatch(in: text, range: range) != nil
    }
}

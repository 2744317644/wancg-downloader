import Foundation
import UIKit

enum PDFBuilder {
    static func build(
        images: [URL],
        output: URL,
        dpi: CGFloat = 300,
        progress: @escaping (Int, Int) -> Void
    ) throws -> Int {
        if FileManager.default.fileExists(atPath: output.path) {
            try? FileManager.default.removeItem(at: output)
        }

        let fallback = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: fallback)
        var pages = 0
        let total = images.count

        try renderer.writePDF(to: output) { context in
            for imageURL in images {
                autoreleasepool {
                    guard let image = UIImage(contentsOfFile: imageURL.path) else {
                        return
                    }
                    let width = max(1, image.size.width * 72 / dpi)
                    let height = max(1, image.size.height * 72 / dpi)
                    let pageRect = CGRect(x: 0, y: 0, width: width, height: height)

                    context.beginPage(withBounds: pageRect, pageInfo: [:])
                    context.cgContext.interpolationQuality = .high
                    context.cgContext.setFillColor(UIColor.white.cgColor)
                    context.cgContext.fill(pageRect)
                    image.draw(in: pageRect)
                    pages += 1

                    let current = pages
                    DispatchQueue.main.async {
                        progress(current, total)
                    }
                }
            }
        }

        guard pages > 0 else {
            throw WnacgError.message("所有图片都无法读取，PDF 未生成")
        }
        return pages
    }
}

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
        // Every page uses the same width. Mixed portrait/landscape pages
        // previously had different page widths, so PDF viewers displayed
        // portrait pages narrower than landscape ones.
        let pageWidth: CGFloat = 595

        try renderer.writePDF(to: output) { context in
            for imageURL in images {
                autoreleasepool {
                    guard let image = UIImage(contentsOfFile: imageURL.path) else {
                        return
                    }
                    let imageWidth = max(1, image.size.width)
                    let scale = pageWidth / imageWidth
                    let pageHeight = max(1, image.size.height * scale)
                    let pageRect = CGRect(
                        x: 0, y: 0, width: pageWidth, height: pageHeight
                    )

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

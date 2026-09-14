import AppKit
import Testing
@testable import Lens

@Test @MainActor func visionRecognizesThreeLanguagesInRenderedImage() async throws {
    let context = try #require(CGContext(data: nil, width: 1400, height: 360, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 1400, height: 360))
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let lines = ["Please save your changes before closing this window.", "변경 사항을 저장한 후에 창을 닫아 주세요.", "変更を保存してからウィンドウを閉じてください。"]
    for (i, line) in lines.enumerated() {
        (line as NSString).draw(at: CGPoint(x: 30, y: 280 - i * 100), withAttributes: [.font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black])
    }
    NSGraphicsContext.restoreGraphicsState()
    let image = try #require(context.makeImage())
    let blocks = try await OCRService().recognize(image, source: nil)
    #expect(Set(blocks.compactMap(\.language)) == Set(LensLanguage.allCases))
    #expect(blocks.contains { $0.text.contains("save your changes") })
    #expect(blocks.contains { $0.text.contains("변경") && $0.text.contains("저장") })
    #expect(blocks.contains { $0.text.contains("変更") && $0.text.contains("保存") })
}

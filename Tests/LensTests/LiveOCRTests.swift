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
    #expect(Set(blocks.compactMap(\.language)) == Set(TranslationBenchmark.languages))
    #expect(blocks.contains { $0.text.contains("save your changes") })
    #expect(blocks.contains { $0.text.contains("변경") && $0.text.contains("저장") })
    #expect(blocks.contains { $0.text.contains("変更") && $0.text.contains("保存") })
}

@Test @MainActor func visionRecognizesFrenchGermanAndChineseWithoutThreeLanguageRestriction() async throws {
    let context = try #require(CGContext(data: nil, width: 1800, height: 360, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 1800, height: 360))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let lines = ["Veuillez enregistrer les modifications avant de fermer cette fenêtre.",
                 "Bitte speichern Sie Ihre Änderungen, bevor Sie dieses Fenster schließen.",
                 "请保存所有修改，然后再关闭这个窗口。"]
    for (index, line) in lines.enumerated() {
        (line as NSString).draw(at: CGPoint(x: 30, y: 280 - index * 100),
            withAttributes: [.font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black])
    }
    NSGraphicsContext.restoreGraphicsState()
    let languages = ["fr", "de", "zh"].compactMap(LensLanguage.init(rawValue:))
    let blocks = try await OCRService().recognize(#require(context.makeImage()), source: nil, languages: languages)
    #expect(Set(blocks.compactMap { $0.language?.languageCode }) == ["fr", "de", "zh"])
    #expect(blocks.contains { $0.text.contains("enregistrer") })
    #expect(blocks.contains { $0.text.contains("speichern") })
    #expect(blocks.contains { $0.text.contains("保存") })
}

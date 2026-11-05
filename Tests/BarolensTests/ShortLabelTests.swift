import AppKit
import CoreImage
import Testing
@testable import Barolens

@MainActor private final class LabelEngine: TranslationEngine {
    var received: [TranslationInput] = []
    func availability(source: BarolensLanguage, target: BarolensLanguage) async -> LanguagePairStatus { .installed }
    func cancel() {}
    func translate(_ inputs: [TranslationInput]) async throws -> [TranslationOutput] {
        received += inputs
        return inputs.map { .init(id: $0.id, text: "번역 " + $0.text) }
    }
}
@MainActor private final class LabelClock { var value = 0.0 }
private func labelBlock(_ text: String, x: Double = 0.1, y: Double = 0.8,
                        language: BarolensLanguage? = nil, confidence: Float = 1) -> TextBlock {
    .init(text: text, bounds: CGRect(x: x, y: y, width: 0.35, height: 0.03), language: language, confidence: confidence)
}

@Suite struct ShortLabelTests {
    @Test func explicitEnglishHandlesShortAndLongLabels() {
        for label in ["A", "I", "Go", "OK", "Save", "Account", "Settings", "Preferences", "Save changes",
                      "View details", "Continue", "Cancel", "File", "Home", "Open", "Configuration"] {
            #expect(OCRService.detectLanguage(label, source: .english, languages: [.english, .korean]) == .english)
        }
        // Ambiguous isolated keyboard-like letters and nonlinguistic symbols remain excluded.
        for text in ["X", "123", "⚙", "---", "", " "] {
            #expect(OCRService.detectLanguage(text, source: .english) == nil)
        }
    }

    @Test func explicitSourceRespectsScriptsAndClearForeignLanguage() {
        for label in ["設定", "保存", "終了", "日"] {
            #expect(OCRService.detectLanguage(label, source: .japanese) == .japanese)
        }
        #expect(OCRService.detectLanguage("가", source: .korean) == .korean)
        #expect(OCRService.detectLanguage("あ", source: .japanese) == .japanese)
        #expect(OCRService.detectLanguage("Oui", source: .english) == nil)
        #expect(OCRService.detectLanguage("Bonjour", source: .english) == nil)
        let french = BarolensLanguage(rawValue: "fr")!
        #expect(OCRService.detectLanguage("Bonjour", source: french, languages: [french]) == french)
        #expect(OCRService.detectLanguage("Settings", source: .japanese) == nil)
        for text in ["Settings 設定", "Save 변경", "한국어와日本語です", "Settings Настройки"] {
            #expect(OCRService.detectLanguage(text, source: .english) == nil)
        }
        #expect(OCRService.detectLanguage("This is a complete English sentence.", source: .japanese) == .english)
        #expect(OCRService.detectLanguage("Settings", source: .english, languages: [.korean]) == nil)
    }

    @Test func autoKeepsAmbiguityWithoutMergingIndependentLabels() {
        #expect(OCRService.detectLanguage("Preferences") == .english)
        #expect(OCRService.detectLanguage("View details") == .english)
        for text in ["A", "I", "X", "OK", "Settings", "設定", "日", "123", "Settings 設定"] {
            #expect(OCRService.detectLanguage(text) == nil)
        }
        let labels = [labelBlock("Settings"), labelBlock("Continue", y: 0.75)]
        #expect(OCRService.groupParagraphs(labels).count == labels.count)
    }

    @Test func contextualFallbackIsLocalAndNeverPropagates() {
        let header = labelBlock("This is a complete sentence written in English.")
        let settings = labelBlock("Settings", y: 0.75)
        let remote = labelBlock("Settings", x: 0.6, y: 0.75)
        let tail = labelBlock("Home", y: 0.7)
        let result = OCRService.assignLanguages(to: [header, settings, remote, tail])
        #expect(result.map(\.language) == [.english, .english, nil, nil])
        let conflicting = OCRService.assignLanguages(to: [header, settings, labelBlock("한국어 설명입니다", y: 0.7)])
        #expect(conflicting[1].language == nil)
        #expect(OCRService.assignLanguages(to: [header, labelBlock("Oui", y: 0.75)])[1].language == nil)
        #expect(result[1].text == settings.text && result[1].bounds == settings.bounds)
    }

    @Test func diagnosticCountsDistinguishSelectionFromOCRAbsence() {
        let context = RegionalTranslationPipeline.Context(source: .english, target: .korean, languages: [.english, .korean])
        let blocks = [labelBlock("Settings", language: .english), labelBlock("OK"),
                      labelBlock("blurry", language: .english, confidence: 0.2),
                      labelBlock("これは日本語です", language: .japanese), labelBlock("설정", language: .korean)]
        let counts = RegionalTranslationPipeline.TextSelection(blocks, context: context)
        #expect(counts.recognized == 5 && counts.eligible == 1 && counts.uncertainLanguage == 1)
        #expect(counts.lowConfidence == 1 && counts.otherSource == 1 && counts.alreadyTarget == 1)
        let none = RegionalTranslationPipeline.TextSelection([], context: context)
        let unknown = RegionalTranslationPipeline.TextSelection([labelBlock("OK")], context: context)
        #expect(none.emptyStatus != unknown.emptyStatus)
        let low = RegionalTranslationPipeline.TextSelection([labelBlock("blurry", confidence: .nan)], context: context)
        #expect(low.lowConfidence == 1 && low.eligible == 0)
    }

    @Test @MainActor func denseSyntheticLabelsReachTranslationInsteadOfDisappearing() async throws {
        let cg = try #require(CGContext(data: nil, width: 2400, height: 1200, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        cg.setFillColor(NSColor.white.cgColor); cg.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
        let labels = ["Settings", "Account", "Save changes", "View details", "Continue", "Preferences"]
        for row in 0..<8 {
            for col in 0..<6 {
                (labels[col] as NSString).draw(at: CGPoint(x: 20 + col * 395, y: 1120 - row * 145),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black])
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = try #require(cg.makeImage())
        let blocks = try await OCRService().recognize(image, source: .english, languages: [.english, .korean])
        #expect(blocks.count == 48 && blocks.allSatisfy { $0.language == .english })
        let engine = LabelEngine(), clock = LabelClock()
        let pipeline = RegionalTranslationPipeline(translator: engine, automatic: false, now: { clock.value },
            recognize: { _, _, _ in blocks })
        pipeline.receive(CIImage(cgImage: image), context: .init(source: .english, target: .korean, languages: [.english, .korean]),
            fingerprint: .init(bytes: Array(repeating: 255, count: 128 * 80 * 4)))
        clock.value = 0.13
        #expect(await pipeline.recognizeNext())
        var steps = 0
        while steps < 20, await pipeline.translateNext() { steps += 1 }
        #expect(pipeline.recordCount == 48 && pipeline.display.count == 48 && engine.received.count == 48)
        #expect(steps == 12)
        #expect(pipeline.diagnostics.selection.eligible == 48)
        let auto = try await OCRService().recognize(image, languages: [.english, .korean])
        let accepted = auto.filter { $0.language == .english }.count
        #expect(accepted > 0 && accepted < auto.count)
        let autoEngine = LabelEngine()
        let autoPipeline = RegionalTranslationPipeline(translator: autoEngine, automatic: false, now: { clock.value },
            recognize: { _, _, _ in auto })
        var autoStatus = ""
        autoPipeline.onStatus = { autoStatus = $0 }
        autoPipeline.receive(CIImage(cgImage: image), context: .init(source: nil, target: .korean, languages: [.english, .korean]),
            fingerprint: .init(bytes: Array(repeating: 255, count: 128 * 80 * 4)))
        clock.value += 0.13
        #expect(await autoPipeline.recognizeNext())
        var autoSteps = 0
        while autoSteps < 20, await autoPipeline.translateNext() { autoSteps += 1 }
        #expect(autoPipeline.display.count == accepted)
        #expect(autoPipeline.diagnostics.selection.uncertainLanguage == auto.count - accepted)
        #expect(autoStatus == L10n.text("Translated areas: %1$@ · %2$@ areas need a source language",
            String(accepted), String(auto.count - accepted)))
        print("SHORT_LABEL_REGRESSION OCR=\(blocks.count) translated=\(pipeline.display.count) batches=\(steps) autoEligible=\(accepted)/\(auto.count)")
        pipeline.reset(); autoPipeline.reset()

        cg.setFillColor(NSColor.white.cgColor); cg.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
        for (index, label) in ["設定", "保存", "終了"].enumerated() {
            (label as NSString).draw(at: CGPoint(x: 30 + index * 500, y: 1100),
                withAttributes: [.font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        let japanese = try await OCRService().recognize(#require(cg.makeImage()), source: .japanese, languages: [.japanese, .korean])
        #expect(japanese.count == 3 && japanese.allSatisfy { $0.language == .japanese })
        print("SHORT_LABEL_JAPANESE OCR=\(japanese.count) source=ja eligible=\(japanese.filter { $0.language == .japanese }.count)")
    }
}

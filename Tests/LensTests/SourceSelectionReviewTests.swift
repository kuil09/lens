import AppKit
import CoreImage
import Testing
@testable import Lens

@MainActor private final class SourceReviewEngine: TranslationEngine {
    var batches: [[TranslationInput]] = []
    func availability(source: LensLanguage, target: LensLanguage) async -> LanguagePairStatus { .installed }
    func cancel() {}
    func translate(_ inputs: [TranslationInput]) async throws -> [TranslationOutput] {
        batches.append(inputs)
        return inputs.map { .init(id: $0.id, text: "review: " + $0.text) }
    }
}

@Test @MainActor func explicitSourceReachesRequestsWhileAutomaticModeKeepsLanguageBatches() async {
    let blocks = [
        TextBlock(text: "This is a complete sentence written in English.",
                  bounds: CGRect(x: 0.1, y: 0.6, width: 0.3, height: 0.1), language: .english, confidence: 1),
        TextBlock(text: "이 문장은 한국어로 작성했습니다.",
                  bounds: CGRect(x: 0.6, y: 0.3, width: 0.3, height: 0.1), language: .korean, confidence: 1)
    ]
    for source: LensLanguage? in [.korean, nil] {
        let engine = SourceReviewEngine()
        var clock = 0.0
        let pipeline = RegionalTranslationPipeline(translator: engine, automatic: false, now: { clock },
            recognize: { _, receivedSource, _ in
                #expect(receivedSource == source)
                return blocks
            })
        pipeline.receive(CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 128, height: 80)),
                         context: .init(source: source, target: .japanese, languages: [.english, .korean, .japanese]))
        clock = 0.13
        #expect(await pipeline.recognizeNext())
        while await pipeline.translateNext() {}
        #expect(engine.batches.flatMap { $0 }.count == 2)
        #expect(engine.batches.allSatisfy { Set($0.map(\.source)).count == 1 })
        #expect(engine.batches.count == (source == nil ? 2 : 1))
        if let source { #expect(engine.batches.flatMap { $0 }.allSatisfy { $0.source == source }) }
        #expect(pipeline.diagnostics.maxActiveTranslation == 1)
    }
}

@Test func explicitOCRSourceIsAHintNotAFilterForDifferentLanguageText() {
    let text = "This is a complete sentence written in English."
    #expect(OCRService.detectLanguage(text) == .english)
    // Characterizes the existing contract, not a claim that issue #2 is resolved.
    #expect(OCRService.detectLanguage(text, source: .korean) == .korean)
}

import CoreImage
import CoreVideo
import Testing
@testable import Lens

@MainActor private final class RecordingPipelineEngine: TranslationEngine {
    var action: (() -> Void)?
    var requests = 0
    var cancellations = 0
    func availability(source: LensLanguage, target: LensLanguage) async -> LanguagePairStatus { .installed }
    func cancel() { cancellations += 1 }
    func translate(_ inputs: [TranslationInput]) async throws -> [TranslationOutput] {
        requests += 1; action?()
        return inputs.map { .init(id: $0.id, text: "translated " + $0.text) }
    }
}

@MainActor private final class RecordingPipelineProbe {
    let engine = RecordingPipelineEngine()
    var now = 0.0
    var observations: [RecordingObservation] = []
    var outputs: [RecordingTranslation] = []
    var ocrAction: (() -> Void)?
    let block = TextBlock(text: "Do not delete 12 files.", bounds: CGRect(x: 0.1, y: 0.3, width: 0.6, height: 0.15),
                          language: .english, confidence: 1)
    let context = RegionalTranslationPipeline.Context(source: .english, target: .korean, languages: [.english])
    lazy var pipeline = RegionalTranslationPipeline(translator: engine, automatic: false, now: { [unowned self] in now },
        recognize: { [unowned self] _, _, _ in ocrAction?(); return [block] })
    init() {
        pipeline.onRecordingObservation = { [unowned self] in observations.append($0) }
        pipeline.onRecordingTranslation = { [unowned self] in outputs.append($0) }
    }
    func feed(_ byte: UInt8 = 255) throws {
        var buffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(nil, 128, 80, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess)
        let frame = RecordingFrame(id: UInt64(now * 1000), contextID: 7, capturedAt: now,
            buffer: try #require(buffer), pointSize: CGSize(width: 128, height: 80), opacity: 1)
        pipeline.receive(CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 128, height: 80)),
            context: context, fingerprint: .init(bytes: Array(repeating: byte, count: 128 * 80 * 4)), recordingFrame: frame)
    }
    func seed() async throws {
        pipeline.setRecordingActive(true)
        try feed(); now = 0.6
        #expect(await pipeline.recognizeNext())
    }
}

@Test @MainActor func recordingReceivesLateResultButLiveOverlayDoesNotResurrect() async throws {
    let p = RecordingPipelineProbe(); try await p.seed()
    p.engine.action = { p.now = 0.7; try? p.feed(0) }
    #expect(await p.pipeline.translateNext())
    #expect(p.pipeline.display.isEmpty)
    #expect(p.outputs.count == 1)
    #expect(p.outputs.first?.observationID == p.observations.first?.id)
    #expect(p.outputs.first?.outputs.first?.id == p.block.id)
    #expect(p.engine.cancellations == 0)
    #expect(p.pipeline.diagnostics.maxActiveTranslation == 1)
    #expect(p.engine.requests == 1)
    p.engine.action = nil
}

@Test @MainActor func recordingCanUseOCRThatFinishedAfterScrollWithoutAnotherOCRRequest() async throws {
    let p = RecordingPipelineProbe()
    p.ocrAction = { p.now = 0.7; try? p.feed(0) }
    try await p.seed()
    #expect(p.pipeline.display.isEmpty)
    #expect(p.observations.count == 1)
    #expect(await p.pipeline.translateNext())
    #expect(p.outputs.count == 1)
    #expect(p.pipeline.diagnostics.ocrRequests == 1)
    #expect(p.pipeline.diagnostics.maxActiveOCR == 1)
    #expect(p.pipeline.diagnostics.retainedFrames == 1)
    p.ocrAction = nil
}

@Test @MainActor func recordingHardResetRejectsLateSourceAndTranslation() async throws {
    let p = RecordingPipelineProbe(); try await p.seed()
    p.engine.action = { p.pipeline.reset() }
    #expect(await p.pipeline.translateNext())
    #expect(p.outputs.isEmpty)
    #expect(p.pipeline.display.isEmpty)
    #expect(!(await p.pipeline.translateNext()))
    p.engine.action = nil
    let q = RecordingPipelineProbe()
    q.ocrAction = { q.pipeline.reset() }
    try await q.seed()
    #expect(q.observations.isEmpty)
    q.ocrAction = nil
}

@Test @MainActor func recordingStoppedBeforeReplyCannotPublishLateResult() async throws {
    let p = RecordingPipelineProbe(); try await p.seed()
    p.engine.action = { p.pipeline.setRecordingActive(false) }
    #expect(await p.pipeline.translateNext())
    #expect(p.outputs.isEmpty)
    #expect(p.pipeline.display.count == 1)
    p.engine.action = nil
}

@Test @MainActor func recordingReusesCompletedTextWithoutSpawningAnotherTranslation() async throws {
    let p = RecordingPipelineProbe(); try await p.seed()
    #expect(await p.pipeline.translateNext())
    p.pipeline.setRecordingActive(false)
    p.pipeline.setRecordingActive(true)
    p.now = 2
    #expect(await p.pipeline.recognizeNext())
    #expect(p.outputs.count == 2)
    #expect(!(await p.pipeline.translateNext()))
    #expect(p.engine.requests == 1)
}

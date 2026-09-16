import AppKit
import CoreImage
import Testing
@testable import Lens

@MainActor private final class ManualTime { var value = 0.0 }
private func sample(_ pixels: [Int] = [], value: UInt8 = 0) -> FrameFingerprint {
    var bytes = Array(repeating: UInt8(255), count: 128 * 80 * 4)
    for pixel in pixels { for channel in 0..<3 { bytes[pixel * 4 + channel] = value } }
    return FrameFingerprint(bytes: bytes)
}
private let changingPixel = 40 * 128 + 112
private let stableBounds = CGRect(x: 0.05, y: 0.4, width: 0.3, height: 0.1)
private let changingBounds = CGRect(x: 0.8, y: 0.45, width: 0.18, height: 0.15)
private func paragraph(_ text: String, bounds: CGRect = stableBounds) -> TextBlock {
    TextBlock(text: text, bounds: bounds, language: .english, confidence: 1)
}
@MainActor private final class ProbeEngine: TranslationEngine {
    var inputs: [[TranslationInput]] = []
    var cancellations = 0
    var action: (@MainActor () async -> Void)?
    func availability(source: LensLanguage, target: LensLanguage) async -> LanguagePairStatus { .installed }
    func cancel() { cancellations += 1 }
    func translate(_ inputs: [TranslationInput]) async throws -> [TranslationOutput] {
        self.inputs.append(inputs)
        await action?()
        return inputs.map { .init(id: $0.id, text: "translated: " + $0.text) }
    }
}
@MainActor private final class Harness {
    let time = ManualTime()
    let engine = ProbeEngine()
    var blocks = [paragraph("The document will not be deleted.")]
    var ocrAction: (@MainActor () async -> Void)?
    var fingerprint = sample()
    let image = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 128, height: 80))
    let context = RegionalTranslationPipeline.Context(source: .english, target: .korean, languages: [.english])
    lazy var pipeline = RegionalTranslationPipeline(translator: engine, automatic: false,
        now: { [unowned self] in time.value }, recognize: { [unowned self] image, _, _ in
            #expect(image.width == 128 && image.height == 80)
            let submitted = blocks
            await ocrAction?()
            return submitted
        })
    func feed(at time: Double, _ fingerprint: FrameFingerprint? = nil) {
        self.time.value = time
        if let fingerprint { self.fingerprint = fingerprint }
        pipeline.receive(image, context: context, fingerprint: self.fingerprint)
    }
    func initial() async {
        feed(at: 0); time.value = 0.13
        #expect(await pipeline.recognizeNext())
        while await pipeline.translateNext() { }
    }
}

@Test func regionalBackoffHasBoundedPeriodicChecksAndEarlyStableRecovery() {
    var scheduler = RegionalBackoff()
    scheduler.observe(sample(), at: 0)
    let initial = scheduler.due(at: 0.13)
    scheduler.dispatched(initial, at: 0.13); scheduler.checked(initial, submitted: scheduler.generation, at: 0.13)
    var attempts: [Double] = []
    for tick in 2...62 {
        let now = Double(tick) / 10
        scheduler.observe(tick.isMultiple(of: 2) ? sample([changingPixel]) : sample(), at: now)
        let due = scheduler.due(at: now)
        if !due.isEmpty { scheduler.dispatched(due, at: now); attempts.append(now) }
    }
    let cell = 2 * 8 + 7
    #expect(scheduler.regions[cell].interval == 2)
    #expect(attempts.count >= 2 && attempts.count <= 4)
    #expect(zip(attempts, attempts.dropFirst()).allSatisfy { $1 - $0 <= 2.11 })
    #expect(scheduler.regions[0].interval == 0.25 && scheduler.regions[0].attempts == 1)
    let recovered = scheduler.due(at: 6.33)
    #expect(recovered.contains(cell))
    scheduler.dispatched(recovered, at: 6.33)
    scheduler.checked(recovered, submitted: scheduler.generation, at: 6.33)
    #expect(scheduler.regions[cell].interval == 0.25)
    #expect(!scheduler.hasPending)
}

@Test @MainActor func staticTextSurvivesSixSecondsOfAnimationWithoutGlobalCancellation() async {
    let h = Harness()
    h.blocks.append(paragraph("The clock says 12 seconds.", bounds: changingBounds))
    await h.initial()
    let stableID = h.pipeline.display.first { $0.block.bounds == stableBounds }!.id
    for tick in 2...62 {
        h.feed(at: Double(tick) / 10, tick.isMultiple(of: 2) ? sample([changingPixel]) : sample())
        h.blocks[1] = paragraph(tick.isMultiple(of: 2) ? "The clock says 13 seconds." : "The clock says 12 seconds.", bounds: changingBounds)
        _ = await h.pipeline.recognizeNext()
        while await h.pipeline.translateNext() { }
        #expect(h.pipeline.display.contains { $0.id == stableID })
    }
    let bodyRequests = h.engine.inputs.flatMap { $0 }.filter { $0.text == h.blocks[0].text }
    #expect(bodyRequests.count == 1)
    #expect(h.pipeline.diagnostics.ocrRequests <= 5)
    #expect(h.pipeline.diagnostics.translationBatches <= 5)
    #expect(h.engine.cancellations == 0)
    print("REGIONAL_SIMULATION seconds=6 body_requests=\(bodyRequests.count) ocr=\(h.pipeline.diagnostics.ocrRequests) batches=\(h.pipeline.diagnostics.translationBatches)")
}

@Test @MainActor func unchangedParagraphReusesTranslationAfterConservativeHiding() async {
    let h = Harness(); await h.initial()
    let original = h.pipeline.display.first!.id
    h.feed(at: 0.4, sample([35 * 128 + 15]))
    #expect(h.pipeline.display.isEmpty)
    h.time.value = 0.53
    #expect(await h.pipeline.recognizeNext())
    #expect(h.pipeline.display.first?.id == original)
    #expect(!(await h.pipeline.translateNext()))
    #expect(h.engine.inputs.count == 1)
    #expect(h.pipeline.diagnostics.reusedTranslations == 1)
}

@Test @MainActor func readerSnapshotSurvivesPixelMaskAndOCRWhileChangedTextWaitsForExplicitApply() async {
    let h = Harness(), reading = TranslationReading()
    h.pipeline.onReading = { sources, epoch in reading.receive(sources, epoch: epoch) }
    await h.initial(); reading.open()
    let original = reading.rows
    h.feed(at: 0.4, sample([35 * 128 + 15]))
    #expect(h.pipeline.display.isEmpty)
    #expect(reading.rows == original)
    h.blocks = [paragraph("Delete the document now.")]
    h.time.value = 0.53
    #expect(await h.pipeline.recognizeNext())
    reading.apply()
    #expect(reading.rows.first?.isPrevious == true)
    #expect(await h.pipeline.translateNext())
    #expect(reading.rows.first?.text == original.first?.text)
    reading.apply()
    #expect(reading.rows.first?.text == "translated: Delete the document now.")
    #expect(reading.rows.first?.id == original.first?.id)
}

@Test @MainActor func unstableOCRIsNotAConfirmedReaderDeletion() async {
    let h = Harness(), reading = TranslationReading()
    h.pipeline.onReading = { sources, epoch in reading.receive(sources, epoch: epoch) }
    await h.initial(); reading.open()
    let original = reading.rows
    h.feed(at: 0.4, sample([35 * 128 + 15])); h.time.value = 0.53
    h.ocrAction = { h.feed(at: 0.6, sample()) }
    #expect(await h.pipeline.recognizeNext())
    reading.apply()
    #expect(reading.rows.first?.text == original.first?.text)
    #expect(reading.rows.first?.isPrevious == true)
    h.ocrAction = nil
}

@Test @MainActor func wrappedContextIsOneRequestAndMaskHidesItsEntireReferenceTranslation() async throws {
    let h = Harness()
    let lines = [
        paragraph("Do not delete any of the remaining", bounds: CGRect(x: 0.05, y: 0.5, width: 0.5, height: 0.06)),
        paragraph("12 files.", bounds: CGRect(x: 0.05, y: 0.42, width: 0.12, height: 0.06))
    ]
    h.blocks = OCRService.groupParagraphs(lines)
    #expect(h.blocks.count == 1)
    await h.initial()
    let original = try #require(h.pipeline.display.first)
    #expect(h.engine.inputs[0].count == 1)
    #expect(h.engine.inputs[0][0].text == "Do not delete any of the remaining 12 files.")
    #expect(original.block.sourceLines.count == 2)
    h.feed(at: 0.4, sample([35 * 128 + 10]))
    #expect(h.pipeline.display.isEmpty)
    #expect(h.pipeline.referenceLayer.contains { $0.id == original.id })
    #expect(h.pipeline.displayMask.hiddenIDs.contains(original.id))
    h.time.value = 0.53
    #expect(await h.pipeline.recognizeNext())
    #expect(h.pipeline.display.first?.id == original.id)
    #expect(h.engine.inputs.count == 1)
}

@Test @MainActor func localChangeDoesNotDiscardAnUnrelatedInflightResultEvenInTheSameCell() async {
    let h = Harness()
    h.blocks = [paragraph("The value will not change.", bounds: CGRect(x: 0.02, y: 0.03, width: 0.04, height: 0.04))]
    h.feed(at: 0); h.time.value = 0.13
    #expect(await h.pipeline.recognizeNext())
    h.engine.action = { [unowned h] in
        h.feed(at: 0.2, sample([10 * 128 + 12]))
        #expect(!(await h.pipeline.translateNext()))
    }
    #expect(await h.pipeline.translateNext())
    #expect(h.pipeline.display.count == 1)
    #expect(h.engine.cancellations == 0)
    #expect(h.pipeline.diagnostics.maxActiveTranslation == 1)
    h.engine.action = nil
}

@Test @MainActor func numericNegationChangeRejectsLateResultAndNeverFuzzilyReusesIt() async {
    let h = Harness()
    h.blocks = [paragraph("Do not delete 12 files.", bounds: changingBounds)]
    h.feed(at: 0); h.time.value = 0.13
    #expect(await h.pipeline.recognizeNext())
    h.engine.action = { [unowned h] in
        h.blocks = [paragraph("Delete 13 files.", bounds: changingBounds)]
        h.feed(at: 0.4, sample([changingPixel])); h.time.value = 0.53
        #expect(await h.pipeline.recognizeNext())
    }
    #expect(await h.pipeline.translateNext())
    #expect(h.pipeline.display.isEmpty)
    #expect(h.pipeline.diagnostics.discardedResults == 1)
    h.engine.action = nil
    #expect(await h.pipeline.translateNext())
    #expect(h.pipeline.display.map(\.text) == ["translated: Delete 13 files."])
}

@Test @MainActor func abaChangesCannotResurrectAnOldResponse() async {
    let h = Harness()
    h.blocks = [paragraph("Do not delete 12 files.", bounds: changingBounds)]
    h.feed(at: 0); h.time.value = 0.13
    #expect(await h.pipeline.recognizeNext())
    h.engine.action = { [unowned h] in
        h.feed(at: 0.2, sample([changingPixel])); h.feed(at: 0.3, sample())
    }
    #expect(await h.pipeline.translateNext())
    #expect(h.pipeline.display.isEmpty)
    #expect(h.pipeline.diagnostics.discardedResults == 1)
    h.engine.action = nil
}

@Test @MainActor func boundedWorkersUseLatestFrameAndNeverCatchUpInABurst() async {
    let h = Harness()
    h.feed(at: 0); h.time.value = 0.13
    h.ocrAction = { [unowned h] in
        for tick in 1...100 { h.feed(at: 0.13 + Double(tick) / 1000, sample([changingPixel])) }
        #expect(!(await h.pipeline.recognizeNext()))
    }
    #expect(await h.pipeline.recognizeNext())
    #expect(h.pipeline.diagnostics.maxActiveOCR == 1)
    #expect(h.pipeline.diagnostics.retainedFrames == 1)
    h.ocrAction = nil
    h.time.value = 100
    #expect(await h.pipeline.recognizeNext())
    #expect(!(await h.pipeline.recognizeNext()))
    #expect(h.pipeline.scheduler.saturationWait > 90)
    #expect(h.pipeline.diagnostics.ocrRequests == 2)
}

@Test @MainActor func allDueRegionsShareOneObservationAndTranslationBatchesStayBounded() async {
    let h = Harness()
    h.blocks = (0..<40).map { index in
        paragraph("This is region number \(index).", bounds: CGRect(x: Double(index % 8) / 8 + 0.025,
            y: Double(index / 8) / 5 + 0.03, width: 0.07, height: 0.08))
    }
    await h.initial()
    #expect(h.pipeline.display.count == 40)
    #expect(h.engine.inputs.count == 10 && h.engine.inputs.allSatisfy { $0.count <= 4 })
    #expect(h.pipeline.scheduler.regions.allSatisfy { $0.attempts == 1 })
    #expect(h.pipeline.diagnostics.ocrRequests == 1)
    #expect(h.pipeline.diagnostics.maxActiveTranslation == 1)
}

@Test @MainActor func currentTextTableIsBoundedAndParagraphsAreNotSplitAtGridLines() async {
    let h = Harness()
    let text = "This paragraph crosses several grid lines.\nDo not delete the remaining 12 files."
    h.blocks = [paragraph(text, bounds: CGRect(x: 0.08, y: 0.1, width: 0.84, height: 0.4))]
    await h.initial()
    #expect(h.engine.inputs.first?.first?.text == text)
    #expect(h.engine.inputs.flatMap { $0 }.count == 1)
    h.pipeline.reset()
    h.blocks = (0..<300).map { paragraph("The row number is \($0).") }
    h.feed(at: 1); h.time.value = 1.2
    #expect(await h.pipeline.recognizeNext())
    #expect(h.pipeline.recordCount == 300)
    h.blocks = (0..<300).map { paragraph("The updated row number is \($0).") }
    h.feed(at: 2, sample(Array(0..<(128 * 80))))
    h.time.value = 2.2
    #expect(await h.pipeline.recognizeNext())
    #expect(h.pipeline.recordCount == 300) // Current text only, not 600 queued versions.
}

@Test @MainActor func sceneAndLanguageResetsRejectPendingResultsAndClearBackoff() async {
    let h = Harness()
    h.feed(at: 0); h.time.value = 0.13
    #expect(await h.pipeline.recognizeNext())
    h.engine.action = { [unowned h] in
        h.pipeline.reset()
        h.pipeline.receive(h.image, context: .init(source: .english, target: .japanese, languages: [.english]), fingerprint: sample())
    }
    #expect(await h.pipeline.translateNext())
    #expect(h.pipeline.display.isEmpty && h.pipeline.recordCount == 0)
    #expect(h.pipeline.scheduler.regions.allSatisfy { $0.level == 0 })
    h.engine.action = nil
    h.time.value = 1
    h.pipeline.receive(h.image, context: .init(source: .english, target: .japanese, languages: [.english]),
        fingerprint: sample(Array(0..<(128 * 80))))
    #expect(h.pipeline.diagnostics.sceneResets == 1)
    #expect(h.pipeline.display.isEmpty)
}

@Test func slowFadesAccumulateAndChangedPixelFootprintsAreConservative() {
    var scheduler = RegionalBackoff()
    scheduler.observe(sample(), at: 0)
    let before = scheduler.generation, epoch = scheduler.epoch
    for step in 1...12 { scheduler.observe(sample([changingPixel], value: UInt8(255 - step)), at: Double(step) / 30) }
    #expect(!scheduler.unchanged(changingBounds, since: before, epoch: epoch))
    #expect(scheduler.unchanged(stableBounds, since: before, epoch: epoch))
}

@Test func continuousBroadChangesDoNotResetTheirDeadlineForever() {
    var scheduler = RegionalBackoff()
    scheduler.observe(sample(), at: 0)
    let dark = sample(Array(0..<(128 * 80)))
    var resets = 0, requests = 0
    for tick in 1...180 {
        let time = Double(tick) / 30
        if scheduler.observe(tick.isMultiple(of: 2) ? sample() : dark, at: time) { resets += 1 }
        let due = scheduler.due(at: time)
        if !due.isEmpty { scheduler.dispatched(due, at: time); requests += 1 }
    }
    #expect(resets == 1)
    #expect(requests >= 2 && requests <= 4)
    #expect(scheduler.regions.allSatisfy { $0.interval == 2 })
}

@Test func staleReplyDoesNotRestartTheQuietPeriodButServiceErrorsRemainPaced() {
    var scheduler = RegionalBackoff()
    scheduler.observe(sample(), at: 0)
    for tick in 1...20 {
        scheduler.observe(tick.isMultiple(of: 2) ? sample() : sample([changingPixel]), at: Double(tick) / 10)
    }
    let cell = 2 * 8 + 7
    #expect(scheduler.regions[cell].interval == 2)
    scheduler.dispatched([cell], at: 2)
    scheduler.observe(sample([changingPixel]), at: 2.05)
    scheduler.retry([cell], at: 2.24, sourceChanged: true)
    #expect(scheduler.due(at: 2.25).contains(cell))
    scheduler.dispatched([cell], at: 2.25)
    scheduler.retry([cell], at: 2.26)
    #expect(!scheduler.due(at: 2.5).contains(cell))
    #expect(scheduler.due(at: 4.26).contains(cell))
}

@Test @MainActor func realVisionAndPixelSamplerPreserveBodyButInvalidateChangedNumbers() async throws {
    func frame(state: String, critical: String) throws -> CIImage {
        let context = try #require(CGContext(data: nil, width: 1000, height: 400, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1000, height: 400))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black]
        ("Please keep this document open." as NSString).draw(at: CGPoint(x: 25, y: 310), withAttributes: attributes)
        (critical as NSString).draw(at: CGPoint(x: 25, y: 210), withAttributes: attributes)
        ("The state is \(state)." as NSString).draw(at: CGPoint(x: 720, y: 260), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        return CIImage(cgImage: try #require(context.makeImage()))
    }
    let time = ManualTime(), engine = ProbeEngine()
    let pipeline = RegionalTranslationPipeline(translator: engine, automatic: false, now: { time.value })
    let context = RegionalTranslationPipeline.Context(source: .english, target: .korean, languages: [.english])
    // Use confidently identifiable prose here. Short ambiguous labels are tested
    // separately; explicit source no longer forces their language classification.
    pipeline.receive(try frame(state: "A", critical: "Please do not delete the remaining 12 files."), context: context)
    time.value = 0.13; #expect(await pipeline.recognizeNext())
    while await pipeline.translateNext() { }
    let body = try #require(pipeline.display.first { $0.block.text.contains("keep this document") })
    let critical = try #require(pipeline.display.first { $0.block.text.contains("12 files") })
    time.value = 0.4
    pipeline.receive(try frame(state: "B", critical: "Please do not delete the remaining 12 files."), context: context)
    #expect(pipeline.display.contains { $0.id == body.id })
    #expect(pipeline.display.contains { $0.id == critical.id })
    time.value = 0.53; #expect(await pipeline.recognizeNext())
    while await pipeline.translateNext() { }
    time.value = 1
    pipeline.receive(try frame(state: "B", critical: "Please delete the remaining 13 files now."), context: context)
    #expect(pipeline.display.contains { $0.id == body.id })
    #expect(!pipeline.display.contains { $0.id == critical.id })
    time.value = 1.13; #expect(await pipeline.recognizeNext())
    while await pipeline.translateNext() { }
    #expect(pipeline.display.contains { $0.block.text.contains("13 files") })
    #expect(!pipeline.display.contains { $0.block.text.contains("12 files") })
    #expect(engine.inputs.flatMap { $0 }.filter { $0.text == body.block.text }.count == 1)
    #expect(engine.cancellations == 0)
}

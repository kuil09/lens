import Foundation
import CoreGraphics
import CoreVideo
import CoreImage
import Testing
@testable import Lens

private struct TrackerDocument {
    static let size = CGSize(width: 640, height: 480)
    static let ids = (0..<7).map { _ in UUID() }
    let image: CGImage
    let blocks: [TextBlock]

    init(dx: Int = 0, dy: Int = 0, replacement: String? = nil, occluded: Bool = false) throws {
        let context = try #require(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
            bytesPerRow: 640 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: Self.size))
        context.setShouldAntialias(false)
        var blocks: [TextBlock] = []
        func draw(_ text: String, index: Int, x: Int, y: Int) {
            let rect = CGRect(x: x, y: y, width: 256, height: 24)
            // Deterministic synthetic glyphs encode every character (including numbers/not).
            context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
            for (column, code) in text.utf8.enumerated() {
                for bit in 0..<7 where code & (1 << bit) != 0 {
                    context.fill(CGRect(x: x + 3 + column * 7, y: y + 3 + bit * 2,
                                        width: 2 + (column % 2), height: 2))
                }
            }
            let normalized = CGRect(x: rect.minX / 640, y: rect.minY / 480,
                                    width: rect.width / 640, height: rect.height / 480)
            blocks.append(TextBlock(id: Self.ids[index], text: text, bounds: normalized,
                language: .english, confidence: 1,
                sourceLines: [SourceLine(text: text, bounds: normalized.insetBy(dx: 1 / 640, dy: 1 / 480))]))
        }
        context.saveGState()
        context.clip(to: CGRect(x: 20, y: 30, width: 600, height: 390))
        for index in 0..<6 {
            draw(index == 2 ? (replacement ?? "Row2 Do not delete 12 files") : "Row\(index) Read \(index * 19 + 31) files now",
                 index: index, x: 185 + dx, y: 80 + index * 55 + dy)
        }
        context.restoreGState()
        if occluded {
            context.setFillColor(CGColor(gray: 0.7, alpha: 1))
            context.fill(CGRect(x: 182 + dx, y: 188 + dy, width: 10, height: 30))
        }
        draw("Fixed document header", index: 6, x: 185, y: 440)
        image = try #require(context.makeImage())
        self.blocks = blocks
    }

    func observation(id: UUID = UUID(), context: UInt64 = 1, blocks: [TextBlock]? = nil) -> RecordingObservation {
        RecordingObservation(id: id, contextID: context, frameID: 10, capturedAt: 1,
            image: image, pointSize: Self.size, blocks: blocks ?? self.blocks, target: .korean)
    }

    func frame(id: UInt64 = 20, context: UInt64 = 1) throws -> RecordingFrame {
        try trackerFrame(image, pointSize: Self.size, id: id, context: context)
    }
}

private func trackerFrame(_ image: CGImage, pointSize: CGSize, id: UInt64 = 20,
                          context: UInt64 = 1) throws -> RecordingFrame {
    var value: CVPixelBuffer?
    try #require(CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height,
        kCVPixelFormatType_32BGRA, [kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &value) == kCVReturnSuccess)
    let buffer = try #require(value)
    try #require(CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess)
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let context2D = try #require(CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: image.width,
        height: image.height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
    context2D.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return RecordingFrame(id: id, contextID: context, capturedAt: Double(id) / 10,
        buffer: buffer, pointSize: pointSize, opacity: 1)
}

private func trackerTranslation(_ observation: RecordingObservation) -> RecordingTranslation {
    RecordingTranslation(observationID: observation.id, contextID: observation.contextID,
        outputs: observation.blocks.map { TranslationOutput(id: $0.id, text: "번역: \($0.text)") })
}

@Test(arguments: [false, true])
func recordingTrackerCoreImageObservationMatchesProductionCopy(taggedSRGB: Bool) throws {
    let document = try TrackerDocument()
    let capture = try document.frame()
    if taggedSRGB {
        CVBufferSetAttachment(capture.buffer, kCVImageBufferCGColorSpaceKey,
            CGColorSpace(name: CGColorSpace.sRGB)!, .shouldPropagate)
    }
    // Match FrameAnalysis.cgImage and RecordingCompositor.copy, not two CGContext draws.
    let context = CIContext(options: [.cacheIntermediates: false])
    let input = CIImage(cvPixelBuffer: capture.buffer)
    let observationImage = try #require(context.createCGImage(input, from: input.extent))
    let observation = RecordingObservation(id: UUID(), contextID: capture.contextID, frameID: capture.id,
        capturedAt: capture.capturedAt, image: observationImage, pointSize: capture.pointSize,
        blocks: document.blocks, target: .korean)
    let tracker = RecordingTracker()
    tracker.observe(observation)
    tracker.resolve(trackerTranslation(observation))
    let owned = try RecordingCompositor().copy(capture)
    let mapped = tracker.map(owned)
    #expect(mapped.count == document.blocks.count,
        "imageSpace=\(String(describing: observationImage.colorSpace?.name)) bits=\(observationImage.bitsPerComponent) \(tracker.diagnostics)")
    #expect(tracker.diagnostics.samePositionMatches == document.blocks.count)
    #expect(tracker.diagnostics.unmatchedComparisons == 0)
}

@Test(arguments: [(24, 0), (0, 18), (-20, -14), (18, 16)])
func recordingTrackerMatchesTwoDimensionalScrollAndStableHeader(delta: (Int, Int)) throws {
    let tracker = RecordingTracker()
    let original = try TrackerDocument()
    let observation = original.observation()
    tracker.observe(observation)
    tracker.resolve(trackerTranslation(observation))
    #expect(tracker.map(try original.frame()).count == original.blocks.count)
    let moved = try TrackerDocument(dx: delta.0, dy: delta.1)
    let mapped = tracker.map(try moved.frame())
    #expect(mapped.count >= 3, "\(tracker.diagnostics)")
    #expect(mapped.contains { $0.id == TrackerDocument.ids[6] })
    for result in mapped {
        let expected = try #require(moved.blocks.first { $0.id == result.id })
        #expect(abs(result.source.bounds.minX - expected.bounds.minX) < 0.000001)
        #expect(abs(result.source.bounds.minY - expected.bounds.minY) < 0.000001)
        #expect(abs(result.source.sourceLines[0].bounds.minX - expected.sourceLines[0].bounds.minX) < 0.000001)
        #expect(abs(result.source.sourceLines[0].bounds.minY - expected.sourceLines[0].bounds.minY) < 0.000001)
        #expect(result.text == "번역: \(expected.text)")
        #expect(result.background == [1, 1, 1, 1])
    }
    #expect(tracker.diagnostics.maxRegistrationsPerFrame == 1)
    #expect(tracker.diagnostics.maxComparedBytesPerFrame <= 32 * 1_048_576)
    let registrations = tracker.diagnostics.registrationRequests
    #expect(tracker.map(try moved.frame(id: 21)).map(\.id) == mapped.map(\.id))
    #expect(tracker.diagnostics.registrationRequests == registrations)
    #expect(tracker.diagnostics.registrationCacheHits > 0)
}

@Test(arguments: [(0, 0), (18, 16)])
func recordingTrackerRepeatedOCRWithNewIDsKeepsLatestExactResult(delta: (Int, Int)) throws {
    let tracker = RecordingTracker()
    let document = try TrackerDocument()
    let original = document.blocks[2]
    var observations: [RecordingObservation] = []
    for confidence: Float in [0.8, 0.9, 1] {
        let block = TextBlock(id: UUID(), text: original.text, bounds: original.bounds,
            language: original.language, confidence: confidence, sourceLines: original.sourceLines)
        let observation = document.observation(blocks: [block])
        tracker.observe(observation)
        observations.append(observation)
    }
    // A late old translation must not replace the latest observation's identity/confidence.
    for observation in observations.reversed() { tracker.resolve(trackerTranslation(observation)) }
    let mapped = tracker.map(try TrackerDocument(dx: delta.0, dy: delta.1).frame())
    #expect(mapped.count == 1)
    let result = try #require(mapped.first)
    #expect(result.id == observations.last?.blocks.first?.id)
    #expect(result.source.confidence == 1)
    #expect(tracker.diagnostics.deduplicatedMatches == 2)
    #expect(tracker.diagnostics.overlapRejections == 0)
    #expect(result.text == "번역: \(original.text)")
    #expect(abs(result.source.bounds.minX - (original.bounds.minX + Double(delta.0) / 640)) < 0.000001)
    #expect(abs(result.source.bounds.minY - (original.bounds.minY + Double(delta.1) / 480)) < 0.000001)
}

@Test(arguments: ["source", "language", "sourceLines", "translation"])
func recordingTrackerRepeatedOCRStillRejectsConflictingEvidence(difference: String) throws {
    let tracker = RecordingTracker()
    let document = try TrackerDocument()
    let original = document.blocks[2]
    let first = document.observation(blocks: [original])
    tracker.observe(first)
    tracker.resolve(trackerTranslation(first))
    let conflicting = TextBlock(id: UUID(), text: difference == "source" ? "Do delete 13 files" : original.text,
        bounds: original.bounds,
        language: difference == "language" ? .japanese : original.language, confidence: 1,
        sourceLines: difference == "sourceLines" ? [SourceLine(text: "Do delete 13 files",
            bounds: original.sourceLines[0].bounds)] : original.sourceLines)
    let second = document.observation(blocks: [conflicting])
    tracker.observe(second)
    tracker.resolve(RecordingTranslation(observationID: second.id, contextID: second.contextID,
        outputs: [TranslationOutput(id: conflicting.id,
            text: difference == "translation" ? "다른 번역" : "번역: \(original.text)")]))
    #expect(tracker.diagnostics.recordCount == 2 && tracker.diagnostics.pendingCount == 0)
    #expect(tracker.map(try document.frame()).isEmpty)
    #expect(tracker.diagnostics.samePositionMatches == 2)
    #expect(tracker.diagnostics.overlapRejections == 2)
}

@Test(arguments: [(0, 0), (18, 16)])
func recordingTrackerBoundsDriftKeepsExactParagraphAndHeader(delta: (Int, Int)) throws {
    let tracker = RecordingTracker()
    let document = try TrackerDocument()
    let originals = [document.blocks[2], document.blocks[6]]
    let first = document.observation(blocks: originals)
    let newer = originals.map { block in
        TextBlock(id: UUID(), text: block.text,
            bounds: block.bounds.insetBy(dx: -1 / 640, dy: -1 / 480), language: block.language, confidence: 1,
            sourceLines: block.sourceLines.map {
                SourceLine(text: $0.text, bounds: $0.bounds.insetBy(dx: -0.5 / 640, dy: -0.5 / 480))
            })
    }
    let second = document.observation(blocks: newer)
    tracker.observe(first); tracker.observe(second)
    tracker.resolve(trackerTranslation(second)); tracker.resolve(trackerTranslation(first))
    let mapped = tracker.map(try TrackerDocument(dx: delta.0, dy: delta.1).frame())
    #expect(mapped.count == 2, "\(tracker.diagnostics)")
    #expect(Set(mapped.map(\.id)) == Set(newer.map(\.id)))
    #expect(tracker.diagnostics.overlapRejections == 0)
    #expect(tracker.diagnostics.geometryDeduplicatedMatches == 2)
}

@Test func recordingTrackerDifferentBoundsContainingAdditionalInkRemainConflicting() throws {
    let tracker = RecordingTracker()
    let document = try TrackerDocument()
    let canvas = try #require(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8,
        bytesPerRow: 2560, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
    canvas.draw(document.image, in: CGRect(origin: .zero, size: TrackerDocument.size))
    canvas.setFillColor(CGColor(gray: 0, alpha: 1))
    canvas.fill(CGRect(x: 450, y: 195, width: 4, height: 6))
    let image = try #require(canvas.makeImage())
    let original = document.blocks[2]
    let larger = TextBlock(id: UUID(), text: original.text,
        bounds: CGRect(x: original.bounds.minX, y: original.bounds.minY,
                       width: original.bounds.width + 20 / 640, height: original.bounds.height),
        language: original.language, confidence: 1, sourceLines: original.sourceLines)
    for block in [original, larger] {
        let observation = RecordingObservation(id: UUID(), contextID: 1, frameID: 1, capturedAt: 1,
            image: image, pointSize: TrackerDocument.size, blocks: [block], target: .korean)
        tracker.observe(observation); tracker.resolve(trackerTranslation(observation))
    }
    #expect(tracker.map(try trackerFrame(image, pointSize: TrackerDocument.size)).isEmpty)
    #expect(tracker.diagnostics.samePositionMatches == 2)
    #expect(tracker.diagnostics.overlapRejections == 2)
    #expect(tracker.diagnostics.deduplicatedMatches == 0)
}

@Test func recordingTrackerObservationsAtDifferentScrollPositionsDeduplicate() throws {
    let tracker = RecordingTracker()
    let firstDocument = try TrackerDocument()
    let secondDocument = try TrackerDocument(dx: 18, dy: 16)
    let first = firstDocument.observation(blocks: [firstDocument.blocks[2]])
    let source = secondDocument.blocks[2]
    let latestBlock = TextBlock(id: UUID(), text: source.text, bounds: source.bounds,
        language: source.language, confidence: source.confidence, sourceLines: source.sourceLines)
    let second = secondDocument.observation(blocks: [latestBlock])
    tracker.observe(first); tracker.resolve(trackerTranslation(first))
    tracker.observe(second); tracker.resolve(trackerTranslation(second))
    let mapped = tracker.map(try secondDocument.frame())
    #expect(mapped.count == 1, "\(tracker.diagnostics)")
    #expect(mapped.first?.id == latestBlock.id)
}

@Test func recordingTrackerNewerChangedObservationCannotFillOlderDifferentSource() throws {
    let tracker = RecordingTracker()
    let newer = try TrackerDocument(replacement: "Row2 Do delete 13 files")
    let observation = newer.observation()
    tracker.observe(observation)
    tracker.resolve(trackerTranslation(observation))
    let older = try TrackerDocument()
    let mapped = tracker.map(try older.frame(id: 1))
    #expect(!mapped.contains { $0.id == TrackerDocument.ids[2] })
    #expect(mapped.contains { $0.id == TrackerDocument.ids[6] })
    #expect(tracker.map(try newer.frame()).contains { $0.id == TrackerDocument.ids[2] })
}

@Test func recordingTrackerLateResultOutlivesSourceFrameAndMapsEarlierFrame() throws {
    let tracker = RecordingTracker()
    let result = try autoreleasepool { () throws -> RecordingTranslation in
        let source = try TrackerDocument(dx: 18, dy: 16)
        let observation = source.observation()
        tracker.observe(observation)
        #expect(tracker.map(try source.frame()).isEmpty)
        return trackerTranslation(observation)
    } // Neither the full observation image nor any source video frame is kept by the test.
    #expect(tracker.diagnostics.pendingCount == 7)
    let earlier = try TrackerDocument().frame(id: 1)
    #expect(tracker.map(earlier).isEmpty)
    tracker.resolve(result)
    let mapped = tracker.map(earlier)
    #expect(mapped.count >= 3, "\(tracker.diagnostics)")
    #expect(tracker.diagnostics.pendingCount == 0)
    for block in mapped where block.id != TrackerDocument.ids[6] {
        #expect(abs(block.source.bounds.minX - 185.0 / 640) < 0.000001)
    }
}

@Test(arguments: ["Row2 Do not delete 13 files", "Row2 Do delete 12 files"])
func recordingTrackerRejectsChangedDigitsAndNegation(replacement: String) throws {
    let tracker = RecordingTracker()
    let source = try TrackerDocument()
    let observation = source.observation()
    tracker.observe(observation)
    tracker.resolve(trackerTranslation(observation))
    #expect(tracker.map(try source.frame()).contains { $0.id == TrackerDocument.ids[2] })
    for delta in [(0, 0), (18, 16)] {
        let changed = try TrackerDocument(dx: delta.0, dy: delta.1, replacement: replacement)
        let mapped = tracker.map(try changed.frame())
        #expect(!mapped.contains { $0.id == TrackerDocument.ids[2] })
        #expect(mapped.contains { $0.id == TrackerDocument.ids[6] })
    }
}

@Test func recordingTrackerRejectsOcclusionLargeDisplacementAndMismatchedContext() throws {
    let tracker = RecordingTracker()
    let source = try TrackerDocument()
    let observation = source.observation()
    tracker.observe(observation)
    tracker.resolve(trackerTranslation(observation))
    #expect(!tracker.map(try TrackerDocument(dx: 18, dy: 16, occluded: true).frame())
        .contains { $0.id == TrackerDocument.ids[2] })
    let large = tracker.map(try TrackerDocument(dx: 170).frame())
    #expect(large.map(\.id) == [TrackerDocument.ids[6]])
    #expect(tracker.map(try source.frame(context: 2)).isEmpty)
    tracker.reset()
    tracker.resolve(trackerTranslation(observation))
    #expect(tracker.map(try source.frame()).isEmpty)
    #expect(tracker.diagnostics.recordCount == 0 && tracker.diagnostics.evidenceBytes == 0)
    #expect(tracker.diagnostics.rejectedTranslations == 7)
}

@Test func recordingTrackerSameCoordinateEvidenceNeedsNoRegistrationAndRejectsWrongVersion() throws {
    let tracker = RecordingTracker()
    let source = try TrackerDocument()
    let observation = source.observation(blocks: [source.blocks[2]])
    tracker.observe(observation)
    tracker.resolve(RecordingTranslation(observationID: UUID(), contextID: 1,
        outputs: [TranslationOutput(id: source.blocks[2].id, text: "wrong version")]))
    tracker.resolve(RecordingTranslation(observationID: observation.id, contextID: 2,
        outputs: [TranslationOutput(id: source.blocks[2].id, text: "wrong context")]))
    #expect(tracker.map(try source.frame()).isEmpty)
    tracker.resolve(trackerTranslation(observation))
    #expect(tracker.map(try source.frame()).count == 1)
    #expect(tracker.diagnostics.registrationRequests == 0)
    let bad = TextBlock(text: "edge", bounds: CGRect(x: 0, y: 0, width: 0.4, height: 0.1), language: .english, confidence: 1)
    tracker.observe(source.observation(blocks: [bad]))
    let rightEdge = TextBlock(text: "right edge", bounds: CGRect(x: 0.6, y: 0.3, width: 0.4, height: 0.1),
                              language: .english, confidence: 1)
    tracker.observe(source.observation(blocks: [rightEdge]))
    let invalid = TextBlock(text: "invalid", bounds: CGRect(x: Double.nan, y: 0.3, width: 0.4, height: 0.1),
                            language: .english, confidence: 1)
    tracker.observe(source.observation(blocks: [invalid]))
    #expect(tracker.diagnostics.recordCount == 1)
    #expect(tracker.diagnostics.rejectedObservations == 3)
    #expect(tracker.diagnostics.rejectedGeometry == 3)
}

@Test func recordingTrackerEvictsCompletedBeforePendingAndBoundsInFlightEvidence() throws {
    let tracker = RecordingTracker()
    let source = try TrackerDocument()
    var observations: [RecordingObservation] = []
    for _ in 0..<32 {
        let observation = source.observation(blocks: [source.blocks[2]])
        observations.append(observation)
        tracker.observe(observation)
    }
    #expect(tracker.diagnostics.recordCount == 32 && tracker.diagnostics.pendingCount == 32)
    tracker.resolve(trackerTranslation(observations[31]))
    tracker.observe(source.observation(blocks: [source.blocks[2]]))
    #expect(tracker.diagnostics.evictedCompleted == 1 && tracker.diagnostics.evictedPending == 0)
    tracker.resolve(trackerTranslation(observations[0]))
    #expect(tracker.map(try source.frame()).count == 1)
    for _ in 0..<40 { tracker.observe(source.observation(blocks: [source.blocks[2]])) }
    #expect(tracker.diagnostics.evictedPending > 0)
    #expect(tracker.diagnostics.peakRecordCount <= 32)
    #expect(tracker.diagnostics.peakEvidenceBytes <= 16 * 1_048_576)
    tracker.reset()
    #expect(tracker.diagnostics.evidenceBytes == 0 && tracker.diagnostics.pendingCount == 0)

    let context = try #require(CGContext(data: nil, width: 1600, height: 1600, bitsPerComponent: 8,
        bytesPerRow: 6400, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1600))
    context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fill(CGRect(x: 200, y: 200, width: 12, height: 12))
    let image = try #require(context.makeImage())
    let largeBlock = TextBlock(text: "Large evidence", bounds: CGRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9),
                               language: .english, confidence: 1)
    for _ in 0..<3 {
        tracker.observe(RecordingObservation(id: UUID(), contextID: 1, frameID: 1, capturedAt: 0,
            image: image, pointSize: CGSize(width: 1600, height: 1600), blocks: [largeBlock], target: .korean))
    }
    #expect(tracker.diagnostics.recordCount == 1 && tracker.diagnostics.pendingCount == 1)
    #expect(tracker.diagnostics.evictedPending == 2)
    #expect(tracker.diagnostics.peakEvidenceBytes <= 16 * 1_048_576)
}

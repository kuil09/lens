import AppKit
import Combine
import CoreImage
import Testing
@testable import Lens

private func legacyPixels(_ bounds: CGRect) -> [Int] {
    guard !bounds.isNull, !bounds.isInfinite, bounds.width > 0, bounds.height > 0 else { return [] }
    let x0 = max(0, Int(floor(bounds.minX * 128)) - 1), x1 = min(128, Int(ceil(bounds.maxX * 128)) + 1)
    let y0 = max(0, Int(floor(bounds.minY * 80)) - 1), y1 = min(80, Int(ceil(bounds.maxY * 80)) + 1)
    guard x0 < x1, y0 < y1 else { return [] }
    return (y0..<y1).flatMap { y in (x0..<x1).map { y * 128 + $0 } }
}

@Test func gridQueriesMatchLegacyAtEdgesAndAcrossChanges() {
    var grid = RegionalBackoff()
    var bytes = Array(repeating: UInt8(255), count: 128 * 80 * 4)
    grid.observe(.init(bytes: bytes), at: 0)
    let submitted = grid.generation, epoch = grid.epoch
    for pixel in stride(from: 0, to: 128 * 80, by: 71) { bytes[pixel * 4] = 0 }
    grid.observe(.init(bytes: bytes), at: 0.1)
    for x in -3...18 {
        for y in -3...18 {
            for width in [0.0001, 0.125, 0.49, 1.2] {
                let bounds = CGRect(x: Double(x) / 16, y: Double(y) / 16, width: width, height: 0.2)
                let indices = legacyPixels(bounds)
                let expected = Set(indices.map { ($0 / 128 / 16) * 8 + ($0 % 128 / 16) })
                #expect(grid.cells(intersecting: bounds) == expected)
                #expect(grid.unchanged(bounds, since: submitted, epoch: epoch) ==
                    (grid.epoch == epoch && !indices.isEmpty && indices.allSatisfy { grid.pixels[$0] <= submitted }))
            }
        }
    }
    #expect(grid.cells(intersecting: .null).isEmpty)
    #expect(grid.cells(intersecting: CGRect(x: 1e100, y: 0, width: 1e99, height: 1)).isEmpty)
    grid.reset()
    #expect(!grid.unchanged(CGRect(x: 0, y: 0, width: 1, height: 1), since: submitted, epoch: epoch))
}

@Test func nextOCRDeadlinePreservesBudgetAndQuietRecovery() throws {
    var grid = RegionalBackoff()
    #expect(grid.nextDeadline == nil)
    grid.observe(.init(bytes: Array(repeating: 255, count: 128 * 80 * 4)), at: 0)
    #expect(try #require(grid.nextDeadline) == 0.12)
    let due = grid.due(at: 0.12)
    grid.dispatched(due, at: 0.12)
    #expect(try #require(grid.nextDeadline) >= 0.37)
    grid.checked(due, submitted: grid.generation, at: 0.12)
    #expect(grid.nextDeadline == nil)
}

@Test func nextDeadlineMatchesDueCellsThroughoutBackoffAndRecovery() throws {
    var grid = RegionalBackoff()
    var bytes = Array(repeating: UInt8(255), count: 128 * 80 * 4)
    grid.observe(.init(bytes: bytes), at: 0)
    for tick in 1...800 {
        let now = Double(tick) / 20
        if tick < 700 && tick.isMultiple(of: 2) {
            bytes[(40 * 128 + 112) * 4] = tick.isMultiple(of: 4) ? 0 : 255
            grid.observe(.init(bytes: bytes), at: now)
        }
        if let deadline = grid.nextDeadline {
            #expect(!grid.due(at: deadline).isEmpty)
            #expect(grid.due(at: deadline - 0.0001).isEmpty)
            #expect(deadline >= grid.lastOCR + 0.25)
        }
        let selected = grid.due(at: now)
        if !selected.isEmpty {
            grid.dispatched(selected, at: now)
            if tick > 700 { grid.checked(selected, submitted: grid.generation, at: now) }
        }
    }
    #expect(grid.nextDeadline == nil)
    #expect(grid.regions[2 * 8 + 7].level == 0)
}

@Test @MainActor func overlayReusesOnlyExactlyUnchangedLayouts() throws {
    _ = NSApplication.shared
    let overlay = TranslationOverlay(frame: CGRect(x: 0, y: 0, width: 800, height: 500))
    let first = DisplayTranslation(block: .init(text: "Do not delete 12 files.",
        bounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1), language: .english, confidence: 1),
        text: "파일 12개를 삭제하지 마세요.", background: .white)
    let second = DisplayTranslation(block: .init(text: "Keep this paragraph.",
        bounds: CGRect(x: 0.5, y: 0.2, width: 0.3, height: 0.1), language: .english, confidence: 1),
        text: "이 문단은 유지합니다.", background: .white)
    overlay.translations = [first, second]
    let manager = try #require(overlay.layouts.first?.manager)
    let count = overlay.layoutBuildCount
    for _ in 0..<30 { overlay.translations = [first, second] }
    #expect(overlay.layoutBuildCount == count)
    let changed = DisplayTranslation(block: second.block, text: "Changed 13", background: .black)
    overlay.translations = [first, changed]
    #expect(overlay.layouts.first?.manager === manager)
    #expect(overlay.layoutBuildCount == count + 1)
    overlay.setFrameSize(CGSize(width: 600, height: 400))
    #expect(overlay.layouts.first?.manager !== manager)
    overlay.translations = []
    #expect(overlay.layouts.isEmpty)
}

@MainActor private final class WakeProbe {
    var now = 0.0
    var requests: [(Double, @MainActor @Sendable () -> Void)] = []
    var entered: CheckedContinuation<Void, Never>?
    func schedule(_ delay: Double, _ action: @escaping @MainActor @Sendable () -> Void) -> AnyCancellable {
        requests.append((now + delay, action))
        // Deliberately retain canceled callbacks to exercise stale delivery.
        return AnyCancellable {}
    }
}
@MainActor private final class HousekeepingTranslator: TranslationEngine {
    func availability(source: LensLanguage, target: LensLanguage) async -> LanguagePairStatus { .installed }
    func cancel() {}
    func translate(_ inputs: [TranslationInput]) async throws -> [TranslationOutput] {
        inputs.map { .init(id: $0.id, text: $0.text) }
    }
}
@Test @MainActor func OCRWakeIsSingleAndStaleDeliveryCannotRestartAfterReset() async throws {
    let probe = WakeProbe()
    var pipeline: RegionalTranslationPipeline? = RegionalTranslationPipeline(translator: HousekeepingTranslator(),
        now: { probe.now }, recognize: { _, _, _ in
            probe.entered?.resume(); probe.entered = nil
            return []
        }, scheduleWake: { probe.schedule($0, $1) })
    let image = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 128, height: 80))
    let context = RegionalTranslationPipeline.Context(source: .english, target: .korean, languages: [.english])
    let fingerprint = FrameFingerprint(bytes: Array(repeating: 255, count: 128 * 80 * 4))
    for tick in 0..<4 {
        probe.now = Double(tick) / 100
        pipeline?.receive(image, context: context, fingerprint: fingerprint)
    }
    #expect(probe.requests.count == 1)
    let initialWake = try #require(probe.requests.first)
    probe.now = initialWake.0
    await withCheckedContinuation { continuation in
        probe.entered = continuation
        initialWake.1()
    }
    #expect(pipeline?.diagnostics.ocrRequests == 1)
    pipeline?.reset()
    let afterReset = pipeline?.diagnostics.ocrRequests
    initialWake.1()
    #expect(pipeline?.diagnostics.ocrRequests == afterReset)
}

@Test @MainActor func waitingOCRWakeDoesNotRetainPipeline() {
    let probe = WakeProbe()
    var pipeline: RegionalTranslationPipeline? = RegionalTranslationPipeline(translator: HousekeepingTranslator(),
        now: { probe.now }, scheduleWake: { probe.schedule($0, $1) })
    pipeline?.receive(CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 128, height: 80)),
        context: .init(source: .english, target: .korean, languages: [.english]),
        fingerprint: .init(bytes: Array(repeating: 255, count: 128 * 80 * 4)))
    #expect(probe.requests.count == 1)
    weak var released = pipeline
    pipeline = nil
    #expect(released == nil)
    probe.requests[0].1()
    #expect(probe.requests.count == 1)
}

@Test @MainActor func responsivenessReplacesWakeWithoutAcceptingCanceledCallback() async throws {
    let probe = WakeProbe()
    let pipeline = RegionalTranslationPipeline(translator: HousekeepingTranslator(), now: { probe.now },
        recognize: { _, _, _ in probe.entered?.resume(); probe.entered = nil; return [] },
        scheduleWake: { probe.schedule($0, $1) })
    pipeline.receive(CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 128, height: 80)),
        context: .init(source: .english, target: .korean, languages: [.english]),
        fingerprint: .init(bytes: Array(repeating: 255, count: 128 * 80 * 4)))
    let first = try #require(probe.requests.first)
    pipeline.setResponsiveness(.fast)
    #expect(probe.requests.count == 2)
    first.1()
    #expect(pipeline.diagnostics.ocrRequests == 0)
    probe.now = 0.12
    await withCheckedContinuation { continuation in
        probe.entered = continuation; probe.requests[1].1()
    }
    #expect(pipeline.diagnostics.ocrRequests == 1)
    pipeline.reset()
}

@Test @MainActor func unchangedDisplaySuppressesPublicationButNeverHidesEpochChanges() async throws {
    let probe = WakeProbe()
    let block = TextBlock(text: "Do not delete 12 files.", bounds: CGRect(x: 0.1, y: 0.4, width: 0.3, height: 0.1),
                          language: .english, confidence: 1)
    let pipeline = RegionalTranslationPipeline(translator: HousekeepingTranslator(), automatic: false,
        now: { probe.now }, recognize: { _, _, _ in [block] })
    var displayChanges = 0, readingChanges = 0
    pipeline.onDisplay = { _ in displayChanges += 1 }
    pipeline.onReading = { _, _ in readingChanges += 1 }
    let image = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 128, height: 80))
    let context = RegionalTranslationPipeline.Context(source: .english, target: .korean, languages: [.english])
    let bytes = Array(repeating: UInt8(255), count: 128 * 80 * 4)
    pipeline.receive(image, context: context, fingerprint: .init(bytes: bytes))
    let emptyReadingChanges = readingChanges
    for _ in 0..<30 { pipeline.receive(image, context: context, fingerprint: .init(bytes: bytes)) }
    #expect(displayChanges == 0 && readingChanges == emptyReadingChanges)
    probe.now = 0.13
    #expect(await pipeline.recognizeNext())
    #expect(await pipeline.translateNext())
    let stable = try #require(pipeline.display.first)
    let published = displayChanges
    var changed = bytes
    changed[(40 * 128 + 112) * 4] = 0 // A different grid cell, outside the paragraph.
    probe.now = 0.4
    pipeline.receive(image, context: context, fingerprint: .init(bytes: changed))
    probe.now = 0.53
    #expect(await pipeline.recognizeNext())
    #expect(displayChanges == published && pipeline.display.first == stable)
    pipeline.reset()
    #expect(displayChanges == published + 1 && pipeline.display.isEmpty)
    let resetReadingChanges = readingChanges
    pipeline.reset()
    #expect(readingChanges == resetReadingChanges + 1)
}

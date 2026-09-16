import AppKit
@preconcurrency import AVFoundation
import Testing
import Darwin
@testable import Lens

@MainActor private struct ScrollFixture {
    static let size = CGSize(width: 640, height: 360)
    static let body = CGRect(x: 12, y: 15, width: 616, height: 280)
    static let ids = (0..<9).map { _ in UUID() }
    let image: CGImage
    let raster: ScrollRaster
    let items: [DisplayTranslation]

    init(offset: Double = 0, changed: Bool = false, changedIndex: Int = 1, duplicate: Bool = false, textured: Bool = false, scale: Int = 1) throws {
        let context = try #require(CGContext(data: nil, width: 640 * scale, height: 360 * scale, bitsPerComponent: 8,
            bytesPerRow: 640 * scale * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(origin: .zero, size: Self.size))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.black]
        var items: [DisplayTranslation] = []
        func text(_ source: String, _ translated: String, id: UUID, rect: CGRect) {
            (source as NSString).draw(in: rect, withAttributes: attributes)
            let normalized = CGRect(x: rect.minX / 640, y: rect.minY / 360, width: rect.width / 640, height: rect.height / 360)
            items.append(.init(block: .init(id: id, text: source, bounds: normalized, language: .english, confidence: 1),
                               text: translated, background: .white))
        }
        text("Fixed document header", "고정된 문서 머리말", id: Self.ids[8], rect: CGRect(x: 25, y: 320, width: 570, height: 25))
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: Self.body).addClip()
        for index in 0..<8 {
            let rect = CGRect(x: 25, y: 245 - Double(index * 65) + offset, width: 570, height: 36)
            let source = index == changedIndex && changed ? "Section \(index): Delete 13 files now." :
                "Section \(duplicate && index == 1 ? 0 : index): Do not delete 12 files."
            let translated = index == changedIndex && changed ? "문서 \(index): 파일 13개를 지금 삭제하세요." :
                "문서 \(duplicate && index == 1 ? 0 : index): 파일 12개를 삭제하지 마세요."
            // Partial paragraphs are drawn but never admitted as complete OCR input.
            if Self.body.contains(rect) {
                text(source, translated, id: Self.ids[index], rect: rect)
            } else { (source as NSString).draw(in: rect, withAttributes: attributes) }
        }
        NSGraphicsContext.restoreGraphicsState()
        if textured {
            NSColor.gray.setStroke()
            let stripe = NSBezierPath(); stripe.move(to: CGPoint(x: 0, y: 280)); stripe.line(to: CGPoint(x: 640, y: 280)); stripe.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        image = try #require(context.makeImage())
        raster = try #require(ScrollRaster(image: image))
        self.items = items
    }
    func frame(_ id: Int, time: Double, epoch: UInt64 = 1) -> ScrollRecordingExperiment.Frame {
        .init(id: id, timestamp: time, epoch: epoch, raster: raster, pointSize: Self.size,
              scrollBounds: CGRect(x: Self.body.minX / 640, y: Self.body.minY / 360,
                                   width: Self.body.width / 640, height: Self.body.height / 360))
    }
}

@Test @MainActor func scrollExperimentMovesExactTextAndCoverButKeepsHeaderFixed() async throws {
    let original = try ScrollFixture()
    let moved = try ScrollFixture(offset: 10)
    let experiment = ScrollRecordingExperiment()
    var outputs: [ScrollRecordingExperiment.Output] = []
    await experiment.append(original.frame(0, time: 0), at: 0) { outputs.append($0) }
    for item in original.items { experiment.learn(item, observedFrameID: 0, epoch: 1) }
    await experiment.append(moved.frame(1, time: 0.1), at: 0.1) { outputs.append($0) }
    await experiment.flush(at: 0.2, force: true) { outputs.append($0) }
    #expect(outputs.count == 2 && outputs.map(\.timestamp) == [0, 0.1])
    #expect(outputs[0].translations.count == original.items.count)
    for item in outputs[1].translations {
        let expected = try #require(moved.items.first { $0.id == item.id })
        #expect(abs(expected.block.bounds.minY - item.block.bounds.minY) < 0.000001)
        #expect(expected.text == item.text)
    }
    #expect(outputs[1].translations.count == moved.items.count)
}

@Test @MainActor func scrollExperimentRejectsChangedNumbersNegationDuplicatesAndWrongEpoch() async throws {
    let original = try ScrollFixture()
    let changed = try ScrollFixture(offset: 8, changed: true)
    let duplicate = try ScrollFixture(duplicate: true)
    let experiment = ScrollRecordingExperiment()
    var outputs: [ScrollRecordingExperiment.Output] = []
    await experiment.append(original.frame(0, time: 0), at: 0) { outputs.append($0) }
    for item in original.items { experiment.learn(item, observedFrameID: 0, epoch: 1) }
    await experiment.append(changed.frame(1, time: 0.1), at: 0.1) { outputs.append($0) }
    await experiment.append(duplicate.frame(2, time: 0.2), at: 0.2) { outputs.append($0) }
    await experiment.flush(at: 0.3, force: true) { outputs.append($0) }
    #expect(!outputs[1].translations.contains { $0.id == ScrollFixture.ids[1] })
    #expect(!outputs[2].translations.contains { $0.id == ScrollFixture.ids[0] || $0.id == ScrollFixture.ids[1] })
    await experiment.append(original.frame(3, time: 0.4, epoch: 2), at: 0.4) { outputs.append($0) }
    experiment.learn(original.items[0], observedFrameID: 0, epoch: 1)
    await experiment.flush(at: 0.5, force: true) { outputs.append($0) }
    #expect(outputs.last?.translations.isEmpty == true && experiment.stats.rejectedResults == 1)
}

@Test @MainActor func scrollExperimentBoundsMemoryWorkAndFallsBackForLateResults() async throws {
    let original = try ScrollFixture()
    let limits = ScrollRecordingExperiment.Limits(wait: 0.8, frames: 3, frameBytes: original.raster.cost * 2,
        references: 2, referenceBytes: 100_000, comparedBytesPerFrame: 64)
    let experiment = ScrollRecordingExperiment(limits: limits)
    var times: [Double] = []
    for tick in 0..<30 {
        await experiment.append(original.frame(tick, time: Double(tick) / 15), at: Double(tick) / 15) {
            times.append($0.timestamp); #expect($0.translations.isEmpty)
        }
        if tick == 10 { experiment.learn(original.items[0], observedFrameID: 0, epoch: 1) }
        #expect(experiment.frameCount <= 2 && experiment.frameBytes <= limits.frameBytes)
    }
    experiment.learn(original.items[0], observedFrameID: 29, epoch: 1)
    await experiment.flush(at: 2, force: true) { times.append($0.timestamp); #expect($0.translations.isEmpty) }
    #expect(times.count == 30 && zip(times, times.dropFirst()).allSatisfy { $1 > $0 })
    #expect(experiment.stats.rejectedResults == 1 && experiment.stats.maxComparedBytes <= 64)
    #expect(experiment.stats.peakReferenceBytes <= limits.referenceBytes && experiment.frameCount == 0)
    experiment.cancel()
    #expect(experiment.referenceBytes == 0)
}

@Test @MainActor func delayedTranslationCanFillAnEarlierFrameWithoutRetiming() async throws {
    let original = try ScrollFixture()
    let moved = try ScrollFixture(offset: 10)
    let experiment = ScrollRecordingExperiment()
    var output: ScrollRecordingExperiment.Output?
    await experiment.append(original.frame(0, time: 10), at: 10) { _ in Issue.record("Unexpected early output") }
    await experiment.append(moved.frame(1, time: 10.3), at: 10.3) { _ in Issue.record("Unexpected early output") }
    for item in moved.items { experiment.learn(item, observedFrameID: 1, epoch: 1) }
    await experiment.flush(at: 10.81) { output = $0 }
    #expect(output?.timestamp == 10 && output?.translations.count == original.items.count)
}

@Test @MainActor func scrollExperimentRejectsCoverCrossingViewportAndTexturedPerimeter() async throws {
    let original = try ScrollFixture()
    let edge = try ScrollFixture(offset: 14)
    let textured = try ScrollFixture(textured: true)
    let experiment = ScrollRecordingExperiment()
    var outputs: [ScrollRecordingExperiment.Output] = []
    await experiment.append(original.frame(0, time: 0), at: 0) { outputs.append($0) }
    for item in original.items { experiment.learn(item, observedFrameID: 0, epoch: 1) }
    await experiment.append(edge.frame(1, time: 0.1), at: 0.1) { outputs.append($0) }
    await experiment.flush(at: 0.2, force: true) { outputs.append($0) }
    // Complete source glyphs are insufficient if the translation cover crosses the clip boundary.
    #expect(edge.items.contains { $0.id == ScrollFixture.ids[0] })
    #expect(!outputs[1].translations.contains { $0.id == ScrollFixture.ids[0] })
    #expect(outputs[1].translations.contains { $0.id == ScrollFixture.ids[8] })
    await experiment.append(textured.frame(2, time: 0.3, epoch: 2), at: 0.3) { outputs.append($0) }
    experiment.learn(try #require(textured.items.first { $0.id == ScrollFixture.ids[0] }), observedFrameID: 2, epoch: 2)
    #expect(experiment.stats.rejectedResults == 1)
}

@Test @MainActor func scrollExperimentCancellationDuringEncoderWaitDoesNotRestartOrQueueFrames() async throws {
    let fixture = try ScrollFixture()
    let experiment = ScrollRecordingExperiment()
    await experiment.append(fixture.frame(0, time: 0), at: 0) { _ in Issue.record("Unexpected early output") }
    let (events, entered) = AsyncStream<Void>.makeStream()
    var resume: CheckedContinuation<Void, Never>?
    let flushing = Task { @MainActor in
        await experiment.append(fixture.frame(1, time: 1), at: 1) { _ in
            await withCheckedContinuation { continuation in
                resume = continuation
                entered.yield(())
            }
        }
    }
    for await _ in events { break }
    await experiment.append(fixture.frame(2, time: 1.1), at: 1.1) { _ in Issue.record("Concurrent encoder work") }
    #expect(experiment.stats.rejectedFrames == 1)
    experiment.cancel()
    try #require(resume).resume()
    await flushing.value
    entered.finish()
    #expect(experiment.frameCount == 0 && experiment.referenceBytes == 0)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["LENS_SCROLL_VIDEO_EXPERIMENT"] == "1"))
@MainActor func generateScrollRecordingComparison() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LensScrollExperiment-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    let baseline = try LensVideoWriter(destination: directory.appendingPathComponent("current.mp4"), width: 1280, height: 720)
    let buffered = try LensVideoWriter(destination: directory.appendingPathComponent("buffered.mp4"), width: 1280, height: 720)
    let experiment = ScrollRecordingExperiment()
    var live: [DisplayTranslation] = []
    var job: (due: Int, frame: Int, items: [DisplayTranslation], epoch: UInt64)?
    var requests = 0, rawBaseline = 0, rawBuffered = 0, visibleParagraphs = 0, wrongPositions = 0
    var perPhase: [Int: (total: Int, baseline: Int, buffered: Int)] = [:]
    var truth: [Int: [DisplayTranslation]] = [:]
    var matchTimes: [Double] = []
    var before = rusage(); getrusage(RUSAGE_SELF, &before)
    let wallStart = ProcessInfo.processInfo.systemUptime
    func write(_ image: CGImage, _ time: Double, _ writer: LensVideoWriter) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !writer.ready && writer.failure == nil && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(try writer.append(image, seconds: time))
    }
    func emit(_ output: ScrollRecordingExperiment.Output) async throws {
        let expected = try #require(truth[output.id])
        for translated in output.translations {
            if !expected.contains(where: { $0.id == translated.id && $0.text == translated.text &&
                abs($0.block.bounds.minY - translated.block.bounds.minY) < 0.0014 }) {
                wrongPositions += 1
                print("SCROLL_MISMATCH frame=\(output.id) paragraph=\(ScrollFixture.ids.firstIndex(of: translated.id) ?? -1) y=\(translated.block.bounds.minY * 360) expectedY=\(expected.first { $0.id == translated.id }.map { $0.block.bounds.minY * 360 } ?? -999)")
            }
        }
        // Match identities explicitly; never use visual similarity to score changed text.
        let absent = expected.filter { item in item.id != ScrollFixture.ids[8] && !output.translations.contains { $0.id == item.id && $0.text == item.text } }.count
        rawBuffered += absent
        let phase = output.id / 30
        let current = perPhase[phase] ?? (0, 0, 0)
        perPhase[phase] = (current.total, current.baseline, current.buffered + absent)
        try await write(output.image, output.timestamp, buffered)
        truth.removeValue(forKey: output.id)
    }
    for tick in 0..<240 {
        let phase = tick / 30
        let offset: Double
        switch phase {
        case 0: offset = 0
        case 1: offset = Double(tick - 30) * 2
        case 2: offset = 60 + Double(tick - 60) * 8
        case 3: offset = 300
        case 4: offset = 300 - Double(tick - 120) * 6
        case 5: offset = 120
        case 6: offset = 120 + Double(tick - 180) * 0.375
        default: offset = 131.25
        }
        let changed = phase >= 5
        let fixture = try autoreleasepool { try ScrollFixture(offset: offset, changed: changed, changedIndex: 3, scale: 2) }
        let epoch: UInt64 = phase == 7 ? 2 : 1
        if tick == 210 { live.removeAll() }
        if phase == 5 { #expect(fixture.items.contains { $0.id == ScrollFixture.ids[3] && $0.block.text.contains("13") }) }
        truth[tick] = fixture.items
        let count = fixture.items.filter { $0.id != ScrollFixture.ids[8] }.count
        visibleParagraphs += count
        if let result = job, result.due <= tick {
            for item in result.items { experiment.learn(item, observedFrameID: result.frame, epoch: result.epoch) }
            if result.epoch == epoch {
                let valid = result.items.filter { item in fixture.items.contains { $0.id == item.id && $0.text == item.text && $0.block.bounds == item.block.bounds } }
                for item in valid { live.removeAll { $0.id == item.id }; live.append(item) }
            }
            job = nil
        }
        live = live.filter { item in fixture.items.contains { $0.id == item.id && $0.text == item.text && $0.block.bounds == item.block.bounds } }
        let time = Double(tick) / 15
        let began = ProcessInfo.processInfo.systemUptime
        try await experiment.append(fixture.frame(tick, time: time, epoch: epoch), at: time, emit: emit)
        matchTimes.append(ProcessInfo.processInfo.systemUptime - began)
        if job == nil && tick.isMultiple(of: 4) {
            // Same bounded batch size, round-robin fairness, and <=4 Hz admission.
            let inputs = (0..<min(4, fixture.items.count)).map { fixture.items[(requests + $0) % fixture.items.count] }
            requests += 1
            job = (tick + (phase == 7 ? 20 : 6), tick, inputs, epoch)
        }
        let raw = count - live.filter { $0.id != ScrollFixture.ids[8] }.count
        rawBaseline += raw
        let current = perPhase[phase] ?? (0, 0, 0)
        perPhase[phase] = (current.total + count, current.baseline + raw, current.buffered)
        let currentImage = try autoreleasepool { try #require(LensSnapshot.image(background: fixture.image, pointSize: ScrollFixture.size, translations: live, maskOpacity: 1)) }
        try await write(currentImage, time, baseline)
    }
    try await experiment.flush(at: 16, force: true, emit: emit)
    let first = try await baseline.finish(seconds: 16)
    let second = try await buffered.finish(seconds: 16)
    var after = rusage(); getrusage(RUSAGE_SELF, &after)
    let cpuSeconds = Double(after.ru_utime.tv_sec + after.ru_stime.tv_sec - before.ru_utime.tv_sec - before.ru_stime.tv_sec) +
        Double(after.ru_utime.tv_usec + after.ru_stime.tv_usec - before.ru_utime.tv_usec - before.ru_stime.tv_usec) / 1e6
    #expect(wrongPositions == 0)
    #expect(experiment.stats.peakFrames <= 12 && experiment.stats.peakFrameBytes <= 96 * 1_048_576)
    #expect(requests <= 64)
    let sorted = matchTimes.sorted()
    print("SCROLL_VIDEO directory=\(directory.path)")
    print("SCROLL_VIDEO raw baseline=\(rawBaseline)/\(visibleParagraphs) buffered=\(rawBuffered)/\(visibleParagraphs) wrong=\(wrongPositions) requests=\(requests)")
    print("SCROLL_VIDEO stats=\(experiment.stats) appendWallP95Ms=\(sorted[Int(Double(sorted.count - 1) * 0.95)] * 1000)")
    print("SCROLL_VIDEO offlineBothPathsCpuSeconds=\(cpuSeconds) wallSeconds=\(ProcessInfo.processInfo.systemUptime - wallStart) peakRSSMiB=\(Double(after.ru_maxrss)/1_048_576)")
    for phase in perPhase.keys.sorted() { print("SCROLL_VIDEO phase=\(phase) result=\(perPhase[phase]!)") }
    for url in [first, second] {
        let asset = AVURLAsset(url: url)
        #expect(abs(try await asset.load(.duration).seconds - 16) < 0.08)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output); #expect(reader.startReading())
        var times: [Double] = []
        while let sample = output.copyNextSampleBuffer() { times.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds) }
        #expect(reader.status == .completed && times.count == 240)
        #expect(zip(times, times.dropFirst()).allSatisfy { abs($1 - $0 - 1.0 / 15) < 0.002 })
    }
}

import Foundation
import CoreImage
@preconcurrency import AVFoundation
import Testing
@testable import Lens

@Suite(.serialized)
struct RecordingWorkerTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RecordingWorkerTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func frame(id: UInt64 = 1, at time: Double = ProcessInfo.processInfo.systemUptime,
                       width: Int = 160, height: Int = 100) throws -> RecordingFrame {
        var buffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary, &buffer) == kCVReturnSuccess)
        let pixels = try #require(buffer)
        CIContext().render(CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to:
            CGRect(x: 0, y: 0, width: width, height: height)), to: pixels)
        return RecordingFrame(id: id, contextID: 1, capturedAt: time, buffer: pixels,
            pointSize: CGSize(width: width, height: height), opacity: 1)
    }

    private func samples(_ url: URL) async throws -> (times: [Double], duration: Double, first: CVPixelBuffer) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.load(.tracks)
        #expect(tracks.count == 1)
        let track = try #require(tracks.first)
        #expect(track.mediaType == .video)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output); #expect(reader.startReading())
        var times: [Double] = [], first: CVPixelBuffer?
        while let sample = output.copyNextSampleBuffer() {
            times.append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
            if first == nil { first = CMSampleBufferGetImageBuffer(sample) }
        }
        #expect(reader.status == .completed)
        return (times, try await asset.load(.duration).seconds, try #require(first))
    }

    private func red(_ pixels: CVPixelBuffer, x: Int, y: Int) throws -> Int {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        let bytes = try #require(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt8.self)
        return Int(bytes[y * CVPixelBufferGetBytesPerRow(pixels) + x * 4 + 2])
    }

    @Test func captureTimestampsIdleDurationAndExclusivePublication() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("video.mp4")
        let original = Data("keep existing".utf8); try original.write(to: destination)
        let first = try frame()
        let worker = try RecordingWorker(destination: destination, firstFrame: first)
        try await Task.sleep(for: .milliseconds(220))
        let captured = ProcessInfo.processInfo.systemUptime
        worker.offer(RecordingFrame(id: 2, contextID: 1, capturedAt: captured, buffer: first.buffer,
            pointSize: first.pointSize, opacity: 1))
        let duration = ProcessInfo.processInfo.systemUptime - first.capturedAt
        worker.stop(seconds: duration, waitForTranslations: true)
        let saved = try await worker.finish()
        #expect(saved != destination)
        #expect(try Data(contentsOf: destination) == original)
        #expect(!FileManager.default.fileExists(atPath: worker.temporaryURL.path))
        let decoded = try await samples(saved)
        #expect(decoded.times.first == 0)
        #expect(decoded.times.count >= 3)
        #expect(zip(decoded.times, decoded.times.dropFirst()).allSatisfy { $0 < $1 })
        #expect(decoded.times.contains { abs($0 - (captured - first.capturedAt)) < 0.004 })
        #expect(abs(decoded.duration - duration) < 0.08)
        #expect(try red(decoded.first, x: 80, y: 50) > 220)
    }

    @Test func ownsPixelsAndCapsSourceMailboxAndGlyphStorage() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try frame(width: 2_048, height: 1_024)
        let worker = try RecordingWorker(destination: root.appendingPathComponent("caps.mp4"), firstFrame: first)
        // Startup copied the buffer. Mutating this now must not change the buffered frame.
        CIContext().render(CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 2_048, height: 1_024)), to: first.buffer)
        let image = try #require(CIContext().createCGImage(CIImage(color: .white), from: CGRect(x: 0, y: 0, width: 32, height: 32)))
        for index in 0..<200 {
            worker.offer(RecordingFrame(id: UInt64(index + 2), contextID: 1, capturedAt: first.capturedAt,
                buffer: first.buffer, pointSize: first.pointSize, opacity: 1))
            worker.observe(RecordingObservation(id: UUID(), contextID: 1, frameID: 1, capturedAt: first.capturedAt,
                image: image, pointSize: first.pointSize, blocks: [], target: .korean))
            worker.resolve(RecordingTranslation(observationID: UUID(), contextID: 1,
                outputs: [.init(id: UUID(), text: String(repeating: "x", count: 40_000))]))
        }
        try await Task.sleep(for: .milliseconds(850))
        let caps = await worker.statistics()
        #expect(caps.frames <= RecordingWorker.maximumFrames)
        #expect(caps.sourceBytes <= RecordingWorker.maximumSourceBytes)
        #expect(caps.peakFrames <= RecordingWorker.maximumFrames && caps.peakSourceBytes <= RecordingWorker.maximumSourceBytes)
        #expect(caps.incomingFrames <= 1 && caps.observations <= RecordingWorker.maximumObservations)
        #expect(caps.observationBytes <= RecordingWorker.maximumObservationBytes)
        #expect(caps.results <= RecordingWorker.maximumResults && caps.resultBytes <= RecordingWorker.maximumResultBytes)
        worker.stop(seconds: ProcessInfo.processInfo.systemUptime - first.capturedAt, waitForTranslations: false)
        let saved = try await worker.finish()
        let decoded = try await samples(saved)
        #expect(try red(decoded.first, x: 20, y: 20) > 220)
        let finished = await worker.statistics()
        #expect(finished.frames == 0 && finished.sourceBytes == 0 && finished.incomingFrames == 0)
        #expect(finished.trackerRecords == 0 && finished.trackerEvidenceBytes == 0)
        #expect(finished.rejectedTranslations >= caps.rejectedTranslations)
        #expect(finished.rejectedTranslations > 0)
    }

    @Test func glyphCacheReusesMovingPositionAndHonorsOpacity() throws {
        let compositor = RecordingCompositor()
        let source = try frame(width: 320, height: 200), target = try frame(width: 320, height: 200)
        func block(_ text: String, y: Double) -> RecordingBlock {
            let source = TextBlock(text: "Source", bounds: CGRect(x: 0.1, y: y, width: 0.6, height: 0.2), language: .english, confidence: 1)
            return RecordingBlock(id: source.id, source: source, text: text, background: [0, 0, 0, 1])
        }
        compositor.render(source, blocks: [block("Translation", y: 0.6)], into: target.buffer)
        #expect(try red(target.buffer, x: 31, y: 50) < 10)
        #expect(try red(target.buffer, x: 31, y: 150) > 240)
        compositor.render(source, blocks: [block("Translation", y: 0.3)], into: target.buffer)
        #expect(compositor.rasterizations == 1 && compositor.glyphCount == 1)
        let transparent = RecordingFrame(id: source.id, contextID: 1, capturedAt: source.capturedAt,
            buffer: source.buffer, pointSize: source.pointSize, opacity: 0)
        compositor.render(transparent, blocks: [block("Translation", y: 0.6)], into: target.buffer)
        #expect(try red(target.buffer, x: 31, y: 50) > 240)
        for index in 0..<40 { compositor.render(source, blocks: [block("Text \(index)", y: 0.6)], into: target.buffer) }
        #expect(compositor.glyphCount == 32 && compositor.glyphBytes <= RecordingCompositor.maximumGlyphBytes)
        compositor.reset(); #expect(compositor.glyphCount == 0 && compositor.glyphBytes == 0)
    }

    @Test @MainActor func cancellationAndRepeatedStopShareFinalizationWithoutRetainingFacade() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        var recording: LensRecording? = LensRecording()
        var saved: URL?
        recording?.onSaved = { saved = $0 }
        weak var released = recording
        try recording?.start(destination: root.appendingPathComponent("stop.mp4"), firstFrame: frame())
        let finish = try #require(recording?.stop())
        #expect(recording?.isFinishing == true)
        let again = try #require(recording?.stop(reason: .sourceInvalidated))
        finish.cancel()
        recording = nil
        #expect(released == nil)
        await finish.value; await again.value
        #expect(saved == root.appendingPathComponent("stop.mp4"))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("stop.mp4").path))
    }

    @Test @MainActor func staleInitialCaptureStartsAtClickAndRejectsPrestartOffers() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let stale = try frame(at: ProcessInfo.processInfo.systemUptime - 600)
        let recording = LensRecording(), destination = root.appendingPathComponent("stale.mp4")
        try recording.start(destination: destination, firstFrame: stale)
        recording.offer(stale)
        try await Task.sleep(for: .milliseconds(120))
        let finish = try #require(recording.stop(reason: .sourceInvalidated))
        let duration = recording.elapsed
        #expect(duration < 10)
        await finish.value
        let decoded = try await samples(destination)
        #expect(decoded.times.first == 0 && abs(decoded.duration - duration) < 0.08)
    }

    @Test @MainActor func normalStopAcceptsTranslationDuringTail() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try frame()
        // A solid surrounding color with one source ink patch is exact tracker evidence.
        let imageContext = CIContext()
        let sourceImage = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 160, height: 100))
        let ink = CIImage(color: .black).cropped(to: CGRect(x: 48, y: 64, width: 12, height: 8)).composited(over: sourceImage)
        imageContext.render(ink, to: first.buffer)
        let image = try #require(imageContext.createCGImage(ink, from: CGRect(x: 0, y: 0, width: 160, height: 100)))
        let block = TextBlock(text: "Source", bounds: CGRect(x: 0.2, y: 0.6, width: 0.6, height: 0.2), language: .english, confidence: 1)
        let observation = RecordingObservation(id: UUID(), contextID: 1, frameID: first.id, capturedAt: first.capturedAt,
            image: image, pointSize: first.pointSize, blocks: [block], target: .korean)
        let recording = LensRecording()
        let destination = root.appendingPathComponent("tail.mp4")
        var errors: [String] = []; recording.onError = { errors.append($0) }
        try recording.start(destination: destination, firstFrame: first)
        let finish = try #require(recording.stop())
        try await Task.sleep(for: .milliseconds(100))
        recording.observe(observation)
        recording.resolve(.init(observationID: observation.id, contextID: 1, outputs: [.init(id: block.id, text: " ")]))
        await finish.value
        #expect(errors.isEmpty && !recording.isFinishing)
        let decoded = try await samples(destination)
        // The late result's white cover must erase the black source ink near the top.
        #expect(try red(decoded.first, x: 52, y: 32) > 220)
    }
}

import Foundation
@preconcurrency import AVFoundation
import CoreVideo

/// One serial owner for tracking, owned source pixels, compositing and encoding. The lock
/// protects only a bounded mailbox; capture never queues a task or waits for the encoder.
final class RecordingWorker: @unchecked Sendable {
    static let delay = 0.8
    static let maximumFrames = 12
    static let maximumSourceBytes = 96 * 1_024 * 1_024
    static let maximumObservations = 4
    static let maximumObservationBytes = 16 * 1_024 * 1_024
    static let maximumResults = 32
    static let maximumResultBytes = 1_024 * 1_024
    struct Statistics: Sendable {
        let frames: Int
        let sourceBytes: Int
        let peakFrames: Int
        let peakSourceBytes: Int
        let incomingFrames: Int
        let observations: Int
        let observationBytes: Int
        let results: Int
        let resultBytes: Int
        let encodedFrames: Int
        let translatedFrames: Int
        let droppedFrames: Int
        let glyphs: Int
        let glyphBytes: Int
        let trackerRecords: Int
        let trackerEvidenceBytes: Int
        let peakTrackerEvidenceBytes: Int
        let registrationRequests: Int
        let rejectedObservations: Int
        let rejectedTranslations: Int
        let registrationFailures: Int
        let samePositionMatches: Int
        let movedMatches: Int
        let unmatchedComparisons: Int
        let overlapRejections: Int
        let geometryDeduplicatedMatches: Int
        let maxRegistrationsPerFrame: Int
        let maxComparedBytesPerFrame: Int
    }
    private struct Mailbox {
        var admitting = true
        var acceptingEvidence = true
        var incoming: RecordingFrame?
        var observations: [RecordingObservation] = []
        var results: [RecordingTranslation] = []
        var observationBytes = 0
        var resultBytes = 0
    }
    private let queue = DispatchQueue(label: "dev.local.lens.recording", qos: .userInitiated)
    private let lock = NSLock()
    private var mailbox = Mailbox()
    private var state: State!
    private var timer: DispatchSourceTimer?
    private var completion: Result<URL, Error>?
    private var waiters: [CheckedContinuation<URL, Error>] = []
    private var stopping = false
    private let onFailure: @Sendable (String) -> Void
    let temporaryURL: URL
    let startedAt: Double

    init(destination: URL, firstFrame: RecordingFrame, onFailure: @escaping @Sendable (String) -> Void = { _ in }) throws {
        guard Self.valid(firstFrame) else { throw VideoError.invalidSize }
        startedAt = firstFrame.capturedAt
        temporaryURL = destination.deletingLastPathComponent().appendingPathComponent(".Lens-recording-\(UUID().uuidString).mp4")
        self.onFailure = onFailure
        // Startup is synchronous for the throwing facade; all heavy work still runs off-main.
        try queue.sync {
            state = try State(destination: destination, temporaryURL: temporaryURL, firstFrame: firstFrame)
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(1_000_000_000 / 15), leeway: .milliseconds(3))
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }

    deinit {
        timer?.cancel()
        // Dropping an active owner also tears AVFoundation down on its serial owner.
        let abandoned = state
        queue.async { abandoned?.encoder.cancel() }
    }

    func offer(_ frame: RecordingFrame) {
        guard Self.valid(frame) else { return }
        lock.withLock {
            guard mailbox.admitting else { return }
            // At most one capture-pool reference, replaced in place and copied on the worker.
            if mailbox.incoming.map({ $0.capturedAt >= frame.capturedAt }) != true { mailbox.incoming = frame }
        }
    }

    func observe(_ observation: RecordingObservation) {
        let bytes = observation.image.bytesPerRow * observation.image.height
        guard bytes <= Self.maximumObservationBytes, observation.blocks.count <= 128,
              observation.blocks.reduce(0, { $0 + $1.text.utf8.count }) <= 65_536 else { return }
        lock.withLock {
            guard mailbox.acceptingEvidence else { return }
            while mailbox.observations.count >= Self.maximumObservations || mailbox.observationBytes + bytes > Self.maximumObservationBytes {
                let removed = mailbox.observations.removeFirst()
                mailbox.observationBytes -= removed.image.bytesPerRow * removed.image.height
            }
            mailbox.observations.append(observation); mailbox.observationBytes += bytes
        }
    }

    func resolve(_ translation: RecordingTranslation) {
        let bytes = translation.outputs.reduce(0, { $0 + $1.text.utf8.count })
        guard translation.outputs.count <= 128, bytes <= 65_536 else { return }
        lock.withLock {
            guard mailbox.acceptingEvidence else { return }
            while mailbox.results.count >= Self.maximumResults || mailbox.resultBytes + bytes > Self.maximumResultBytes {
                mailbox.resultBytes -= mailbox.results.removeFirst().outputs.reduce(0, { $0 + $1.text.utf8.count })
            }
            mailbox.results.append(translation); mailbox.resultBytes += bytes
        }
    }

    /// Admission closes before returning, including when the caller cancels its await.
    func stop(seconds: Double, waitForTranslations: Bool) {
        let first = lock.withLock {
            guard mailbox.admitting || (!waitForTranslations && mailbox.acceptingEvidence) else { return false }
            mailbox.admitting = false
            mailbox.acceptingEvidence = waitForTranslations
            if !waitForTranslations {
                mailbox.observations.removeAll(); mailbox.results.removeAll()
                mailbox.observationBytes = 0; mailbox.resultBytes = 0
            }
            return true
        }
        guard first else { return }
        queue.async { [self] in
            guard completion == nil, !state.encoder.finishing else { return }
            if stopping {
                do { try state.drain(now: .infinity); try advanceStop() }
                catch { finish(with: .failure(error)) }
                return
            }
            stopping = true
            state.stopDuration = max(0, seconds)
            do {
                try consumeMailbox(sampleIdle: false)
                state.frames.removeAll { $0.capturedAt > startedAt + state.stopDuration }
                if !waitForTranslations { try state.drain(now: .infinity) }
                try advanceStop()
            } catch { finish(with: .failure(error)) }
        }
    }

    /// All callers share the same encoder finalization, independent of task cancellation.
    func finish() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                if let completion { continuation.resume(with: completion) }
                else { waiters.append(continuation) }
            }
        }
    }

    func statistics() async -> Statistics {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let pending = lock.withLock { mailbox }
                let diagnostics = state.finishedDiagnostics ?? state.tracker.diagnostics
                continuation.resume(returning: Statistics(frames: state.frames.count + (state.latest == nil ? 0 : 1),
                    sourceBytes: state.sourceBytes, peakFrames: state.peakFrames, peakSourceBytes: state.peakSourceBytes,
                    incomingFrames: pending.incoming == nil ? 0 : 1,
                    observations: pending.observations.count, observationBytes: pending.observationBytes,
                    results: pending.results.count, resultBytes: pending.resultBytes,
                    encodedFrames: state.encoder.encodedFrames, translatedFrames: state.translatedFrames, droppedFrames: state.droppedFrames,
                    glyphs: state.compositor.glyphCount, glyphBytes: state.compositor.glyphBytes,
                    trackerRecords: state.tracker.diagnostics.recordCount,
                    trackerEvidenceBytes: state.tracker.diagnostics.evidenceBytes,
                    peakTrackerEvidenceBytes: diagnostics.peakEvidenceBytes,
                    registrationRequests: diagnostics.registrationRequests,
                    rejectedObservations: diagnostics.rejectedObservations,
                    rejectedTranslations: diagnostics.rejectedTranslations,
                    registrationFailures: diagnostics.registrationFailures,
                    samePositionMatches: diagnostics.samePositionMatches,
                    movedMatches: diagnostics.movedMatches,
                    unmatchedComparisons: diagnostics.unmatchedComparisons,
                    overlapRejections: diagnostics.overlapRejections,
                    geometryDeduplicatedMatches: diagnostics.geometryDeduplicatedMatches,
                    maxRegistrationsPerFrame: diagnostics.maxRegistrationsPerFrame,
                    maxComparedBytesPerFrame: diagnostics.maxComparedBytesPerFrame))
            }
        }
    }

    private static func valid(_ frame: RecordingFrame) -> Bool {
        let width = CVPixelBufferGetWidth(frame.buffer), height = CVPixelBufferGetHeight(frame.buffer)
        // Allow for the owned BGRA buffer's row alignment before allocating it.
        let row = ((width * 4 + 255) / 256) * 256
        return width >= 2 && height >= 2 && row <= maximumSourceBytes / height
            && frame.capturedAt.isFinite && frame.pointSize.width.isFinite && frame.pointSize.height.isFinite
            && frame.pointSize.width > 0 && frame.pointSize.height > 0
    }

    private func consumeMailbox(sampleIdle: Bool) throws {
        let pending = lock.withLock {
            let value = mailbox
            mailbox.incoming = nil; mailbox.observations.removeAll(); mailbox.results.removeAll()
            mailbox.observationBytes = 0; mailbox.resultBytes = 0
            return value
        }
        for observation in pending.observations { state.tracker.observe(observation) }
        for translation in pending.results { state.tracker.resolve(translation) }
        if let incoming = pending.incoming { try state.admit(incoming) }
        else if sampleIdle && pending.admitting { try state.repeatIdle(at: ProcessInfo.processInfo.systemUptime) }
    }

    private func tick() {
        guard completion == nil, !state.encoder.finishing else { return }
        autoreleasepool {
            do {
                if let failure = state.encoder.failure { throw failure }
                try consumeMailbox(sampleIdle: !stopping)
                try state.drain(now: ProcessInfo.processInfo.systemUptime)
                if stopping { try advanceStop() }
            } catch {
                lock.withLock { mailbox.admitting = false }
                onFailure(error.localizedDescription)
                finish(with: .failure(error))
            }
        }
    }

    private func advanceStop() throws {
        try state.drain(now: ProcessInfo.processInfo.systemUptime)
        guard state.frames.isEmpty else { return }
        timer?.cancel(); timer = nil
        state.finishedDiagnostics = state.tracker.diagnostics
        state.latest = nil; state.tracker.reset(); state.compositor.reset()
        try state.encoder.finish(seconds: state.stopDuration) { [self] in
            queue.async { [self] in finish(with: Result { try state.encoder.publish() }) }
        }
    }

    private func finish(with result: Result<URL, Error>) {
        guard completion == nil else { return }
        timer?.cancel(); timer = nil
        lock.withLock { mailbox = Mailbox(admitting: false, acceptingEvidence: false) }
        if state.finishedDiagnostics == nil { state.finishedDiagnostics = state.tracker.diagnostics }
        state.frames.removeAll(); state.latest = nil; state.tracker.reset(); state.compositor.reset()
        if case .failure = result { state.encoder.cancel() }
        completion = result
        let pending = waiters; waiters.removeAll()
        for waiter in pending { waiter.resume(with: result) }
    }

    private final class State: @unchecked Sendable {
        let compositor = RecordingCompositor()
        var tracker = RecordingTracker()
        var finishedDiagnostics: RecordingTracker.Diagnostics?
        let encoder: RecordingEncoder
        let start: Double
        var frames: [RecordingFrame] = []
        var latest: RecordingFrame?
        var lastSample: Double = -.infinity
        var droppedFrames = 0
        var translatedFrames = 0
        var peakFrames = 0
        var peakSourceBytes = 0
        var stopDuration: Double = 0
        var sourceBytes: Int { frames.reduce(0, { $0 + Self.cost($1) }) + (latest.map(Self.cost) ?? 0) }
        static func cost(_ frame: RecordingFrame) -> Int { CVPixelBufferGetBytesPerRow(frame.buffer) * CVPixelBufferGetHeight(frame.buffer) }

        init(destination: URL, temporaryURL: URL, firstFrame: RecordingFrame) throws {
            start = firstFrame.capturedAt
            encoder = try RecordingEncoder(destination: destination, temporaryURL: temporaryURL,
                width: CVPixelBufferGetWidth(firstFrame.buffer), height: CVPixelBufferGetHeight(firstFrame.buffer))
            try admit(firstFrame)
        }

        func admit(_ frame: RecordingFrame) throws {
            guard frame.capturedAt >= start, frame.capturedAt > lastSample else { droppedFrames += 1; return }
            // The 15 Hz mailbox consumer downsamples capture callbacks. Do not quantize
            // the surviving capture timestamp against the preceding idle sample.
            latest = nil
            let reservation = ((CVPixelBufferGetWidth(frame.buffer) * 4 + 255) / 256) * 256 * CVPixelBufferGetHeight(frame.buffer)
            while !frames.isEmpty && (frames.count >= RecordingWorker.maximumFrames - 1 || sourceBytes + reservation * 2 > RecordingWorker.maximumSourceBytes) {
                try emitFirst()
            }
            let owned = try compositor.copy(frame)
            latest = owned
            updatePeaks()
            // A single oversized-but-valid image may occupy most of the budget. Encode it
            // immediately rather than duplicating its accounting in the delay queue.
            if Self.cost(owned) * 2 > RecordingWorker.maximumSourceBytes {
                try emit(owned)
                lastSample = frame.capturedAt
            } else { try enqueue(owned) }
        }

        func repeatIdle(at time: Double) throws {
            guard let latest, time - lastSample >= 1.0 / 15 - 0.001 else { return }
            let frame = RecordingFrame(id: latest.id, contextID: latest.contextID, capturedAt: time,
                buffer: latest.buffer, pointSize: latest.pointSize, opacity: latest.opacity, dirtyRects: latest.dirtyRects)
            try enqueue(frame)
        }

        func enqueue(_ frame: RecordingFrame) throws {
            while !frames.isEmpty && (frames.count >= RecordingWorker.maximumFrames - 1 || sourceBytes + Self.cost(frame) > RecordingWorker.maximumSourceBytes) {
                try emitFirst()
            }
            if sourceBytes + Self.cost(frame) > RecordingWorker.maximumSourceBytes {
                try emit(frame)
            } else { frames.append(frame) }
            lastSample = frame.capturedAt
            updatePeaks()
        }

        func updatePeaks() {
            peakFrames = max(peakFrames, frames.count + (latest == nil ? 0 : 1))
            peakSourceBytes = max(peakSourceBytes, sourceBytes)
        }

        func drain(now: Double) throws {
            while let frame = frames.first, frame.capturedAt + RecordingWorker.delay <= now { try emitFirst() }
        }

        func emitFirst() throws {
            let frame = frames.removeFirst()
            try emit(frame)
        }

        func emit(_ frame: RecordingFrame) throws {
            let blocks = tracker.map(frame)
            if try encoder.append(frame, blocks: blocks, compositor: compositor, seconds: frame.capturedAt - start) {
                if !blocks.isEmpty { translatedFrames += 1 }
            } else { droppedFrames += 1 }
        }
    }
}

/// AVFoundation is touched only on the worker queue, except its completion callback.
private final class RecordingEncoder: @unchecked Sendable {
    private let destination: URL
    private let temporaryURL: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var lastTime: CMTime?
    private(set) var finishing = false
    private(set) var encodedFrames = 0

    init(destination: URL, temporaryURL: URL, width: Int, height: Int) throws {
        self.destination = destination; self.temporaryURL = temporaryURL
        let width = width - width % 2, height = height - height % 2
        writer = try AVAssetWriter(outputURL: temporaryURL, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: min(20_000_000, max(1_000_000, width * height * 4)),
                AVVideoExpectedSourceFrameRateKey: 15, AVVideoMaxKeyFrameIntervalKey: 30, AVVideoAllowFrameReorderingKey: false]
        ])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(input) else { throw VideoError.encoding("The H.264 encoder is unavailable.") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? VideoError.encoding("Could not start recording.") }
        writer.startSession(atSourceTime: .zero)
    }

    deinit { if writer.status == .writing { writer.cancelWriting() } }
    var failure: Error? { writer.status == .failed ? writer.error ?? VideoError.encoding("The encoder stopped.") : nil }

    func append(_ frame: RecordingFrame, blocks: [RecordingBlock], compositor: RecordingCompositor, seconds: Double) throws -> Bool {
        if let failure { throw failure }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        guard !finishing, seconds.isFinite, seconds >= 0, lastTime.map({ time > $0 }) ?? true,
              input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else { return false }
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool,
            [kCVPixelBufferPoolAllocationThresholdKey as String: 4] as CFDictionary, &buffer)
        if result == kCVReturnWouldExceedAllocationThreshold { return false }
        guard result == kCVReturnSuccess, let buffer else { throw VideoError.encoding("Could not create a video buffer.") }
        compositor.render(frame, blocks: blocks, into: buffer)
        guard adaptor.append(buffer, withPresentationTime: time) else { throw writer.error ?? VideoError.encoding("Could not write the video frame.") }
        lastTime = time; encodedFrames += 1
        return true
    }

    func finish(seconds: Double, completion: @escaping @Sendable () -> Void) throws {
        guard !finishing else { return }
        finishing = true
        if let failure { throw failure }
        guard let lastTime else {
            writer.cancelWriting(); try? FileManager.default.removeItem(at: temporaryURL)
            throw VideoError.encoding("There are no video frames to save.")
        }
        let end = max(CMTime(seconds: seconds.isFinite ? max(0, seconds) : 0, preferredTimescale: 600), lastTime + CMTime(value: 1, timescale: 15))
        writer.endSession(atSourceTime: end); input.markAsFinished()
        writer.finishWriting(completionHandler: completion)
    }

    func publish() throws -> URL {
        guard writer.status == .completed else {
            throw writer.error ?? VideoError.encoding("Could not finish saving the video.")
        }
        return try LensExportFiles.publish(temporaryURL, to: destination)
    }

    func cancel() { if writer.status == .writing { writer.cancelWriting() } }
}

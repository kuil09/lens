import AppKit
import Combine
import OSLog

@MainActor
final class LensRecording: ObservableObject {
    enum StopReason: String { case requested, sourceInvalidated, frameUnavailable, writerFailure }
    private let logger = Logger(subsystem: "dev.local.lens", category: "Recording")
    @Published private(set) var isRecording = false
    @Published private(set) var isFinishing = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var message = L10n.text("Save the screen and translations as silent MP4 video.")
    var onStateChange: (() -> Void)?
    var onError: ((String) -> Void)?
    var onSaved: ((URL) -> Void)?
    private var writer: LensVideoWriter?
    private var worker: RecordingWorker?
    private var acceptsFinishingEvidence = false
    private var ticker: Task<Void, Never>?
    private var finalization: Task<Void, Never>?
    private var startedAt: Double = 0

    var durationText: String {
        let seconds = Int(elapsed)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    /// Production capture/OCR inputs. Pixels, tracking, typography and encoding stay on
    /// one background worker; this facade publishes lifecycle metadata only.
    func start(destination: URL, firstFrame: RecordingFrame) throws {
        guard !isRecording, !isFinishing else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let initial = RecordingFrame(id: firstFrame.id, contextID: firstFrame.contextID, capturedAt: now,
            buffer: firstFrame.buffer, pointSize: firstFrame.pointSize, opacity: firstFrame.opacity, dirtyRects: firstFrame.dirtyRects)
        worker = try RecordingWorker(destination: destination, firstFrame: initial) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop(reason: .writerFailure) }
        }
        startedAt = now
        elapsed = 0; isRecording = true
        message = L10n.text("Recording · %1$@", String(describing: destination.lastPathComponent))
        onStateChange?()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self, isRecording else { return }
                elapsed = max(0, ProcessInfo.processInfo.systemUptime - startedAt)
            }
        }
    }

    func offer(_ frame: RecordingFrame) { if isRecording { worker?.offer(frame) } }
    func observe(_ observation: RecordingObservation) {
        if isRecording || (isFinishing && acceptsFinishingEvidence) { worker?.observe(observation) }
    }
    func resolve(_ translation: RecordingTranslation) {
        if isRecording || (isFinishing && acceptsFinishingEvidence) { worker?.resolve(translation) }
    }

    /// Pull-only diagnostics for tests and local profiling; no additional UI or per-frame callback.
    func diagnostics() async -> RecordingWorker.Statistics? { await worker?.statistics() }

    func start(destination: URL, firstFrame: CGImage, frame: @escaping @MainActor () -> CGImage?) throws {
        guard !isRecording, !isFinishing else { return }
        writer = try LensVideoWriter(destination: destination, width: firstFrame.width, height: firstFrame.height)
        startedAt = ProcessInfo.processInfo.systemUptime
        elapsed = 0
        isRecording = true
        message = L10n.text("Recording · %1$@", String(describing: destination.lastPathComponent))
        onStateChange?()
        do { try writer?.append(firstFrame, seconds: 0) }
        catch { stop(); throw error }
        // Sample the latest composed scene even if ScreenCaptureKit reports an idle desktop.
        // One task, no frame queue, and no catch-up loop after a delayed tick.
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(67)) } catch { return }
                guard let self, isRecording, let writer else { return }
                elapsed = ProcessInfo.processInfo.systemUptime - startedAt
                do {
                    if let failure = writer.failure { throw failure }
                    if writer.ready {
                        guard let image = frame() else { stop(reason: .frameUnavailable); return }
                        try writer.append(image, seconds: elapsed)
                    }
                } catch {
                    stop(reason: .writerFailure)
                    onError?(L10n.text("Recording stopped. %1$@", String(describing: error.localizedDescription)))
                    return
                }
            }
        }
    }

    @discardableResult
    func stop(reason: StopReason = .requested) -> Task<Void, Never>? {
        if isFinishing, reason != .requested {
            acceptsFinishingEvidence = false
            worker?.stop(seconds: elapsed, waitForTranslations: false)
        }
        guard isRecording, writer != nil || worker != nil else { return finalization }
        // Only lifecycle metadata; never log captured pixels, text, or destinations.
        logger.notice("Recording stopped: \(reason.rawValue, privacy: .public)")
        elapsed = max(0, ProcessInfo.processInfo.systemUptime - startedAt)
        ticker?.cancel(); ticker = nil
        isRecording = false; isFinishing = true
        acceptsFinishingEvidence = reason == .requested
        message = L10n.text("Saving video…")
        onStateChange?()
        let duration = elapsed
        let writer = writer, worker = worker
        worker?.stop(seconds: duration, waitForTranslations: reason == .requested)
        let temporaryURL = worker?.temporaryURL ?? writer!.temporaryURL
        let savedCallback = onSaved, errorCallback = onError
        finalization = Task { [weak self] in
            do {
                let saved: URL
                if let worker {
                    saved = try await worker.finish()
                    let stats = await worker.statistics()
                    // Aggregate lifecycle counters only, never source text or saved paths.
                    self?.logger.notice("Recording summary: encoded=\(stats.encodedFrames) translated=\(stats.translatedFrames) dropped=\(stats.droppedFrames) peakFrames=\(stats.peakFrames) peakSourceBytes=\(stats.peakSourceBytes)")
                    self?.logger.notice("Recording tracker: rejectedObservations=\(stats.rejectedObservations) rejectedTranslations=\(stats.rejectedTranslations) registrations=\(stats.registrationRequests) registrationFailures=\(stats.registrationFailures) peakEvidenceBytes=\(stats.peakTrackerEvidenceBytes)")
                    self?.logger.notice("Recording matches: same=\(stats.samePositionMatches) moved=\(stats.movedMatches) unmatched=\(stats.unmatchedComparisons) overlaps=\(stats.overlapRejections) geometryMerged=\(stats.geometryDeduplicatedMatches)")
                }
                else { saved = try await writer!.finish(seconds: duration) }
                self?.message = L10n.text("Saved · %1$@", String(describing: saved.lastPathComponent))
                savedCallback?(saved)
            } catch {
                self?.message = L10n.text("Could not save the video.")
                var detail = error.localizedDescription
                if FileManager.default.fileExists(atPath: temporaryURL.path) {
                    detail += L10n.text("\nRecovery file: %1$@", String(describing: temporaryURL.path))
                }
                errorCallback?(detail)
            }
            self?.writer = nil; self?.worker = nil
            self?.acceptsFinishingEvidence = false
            self?.isFinishing = false; self?.finalization = nil
            self?.onStateChange?()
        }
        return finalization
    }
}

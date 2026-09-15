import AppKit
import Combine

@MainActor
final class LensRecording: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isFinishing = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var message = L10n.text("Save the screen and translations as silent MP4 video.")
    var onStateChange: (() -> Void)?
    var onError: ((String) -> Void)?
    var onSaved: ((URL) -> Void)?
    private var writer: LensVideoWriter?
    private var ticker: Task<Void, Never>?
    private var finalization: Task<Void, Never>?
    private var startedAt: Double = 0

    var durationText: String {
        let seconds = Int(elapsed)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

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
                        guard let image = frame() else { stop(); return }
                        try writer.append(image, seconds: elapsed)
                    }
                } catch {
                    stop()
                    onError?(L10n.text("Recording stopped. %1$@", String(describing: error.localizedDescription)))
                    return
                }
            }
        }
    }

    @discardableResult
    func stop() -> Task<Void, Never>? {
        guard isRecording, let writer else { return finalization }
        elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        ticker?.cancel(); ticker = nil
        isRecording = false; isFinishing = true
        message = L10n.text("Saving video…")
        onStateChange?()
        let duration = elapsed
        finalization = Task { [self] in
            do {
                let saved = try await writer.finish(seconds: duration)
                message = L10n.text("Saved · %1$@", String(describing: saved.lastPathComponent))
                onSaved?(saved)
            } catch {
                message = L10n.text("Could not save the video.")
                var detail = error.localizedDescription
                if FileManager.default.fileExists(atPath: writer.temporaryURL.path) {
                    detail += L10n.text("\nRecovery file: %1$@", String(describing: writer.temporaryURL.path))
                }
                onError?(detail)
            }
            self.writer = nil
            isFinishing = false; finalization = nil
            onStateChange?()
        }
        return finalization
    }
}
